local STOCK_BROKER_NPC_ID = 90001
local INPUT_DEPOSIT       = 50001
local INPUT_WITHDRAW      = 50002
local INPUT_DEPOSIT_ALL   = 50003
local INPUT_WITHDRAW_ALL  = 50004

local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:16:16:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16:0:0|t"

local GOLD_CAP_COPPER     = 10000000000
local WITHDRAW_CAP_COPPER = GOLD_CAP_COPPER - 20000
local MIN_TRANSACTION     = 10000

local function SafeDBQuery(query, ...)
    return CharDBQuery(string.format(query, ...))
end

local function SafeDBExecute(query, ...)
    return CharDBExecute(string.format(query, ...))
end

local function FormatMoney(copper)
    copper = tonumber(copper or 0) or 0
    if copper < 0 then copper = 0 end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRemainder = copper % 100
    return string.format("%d%s %d%s %d%s", gold, GOLD_ICON, silver, SILVER_ICON, copperRemainder, COPPER_ICON)
end

local function GetInvested(accountId)
    local q = CharDBQuery(string.format(
        "SELECT CAST(InvestedMoney AS CHAR) AS im FROM character_stockmarket WHERE account = %.0f LIMIT 1",
        accountId
    ))
    if not q then return 0, "Database error occurred" end
    if q.IsNull and q:IsNull(0) then return 0, nil end
    local s = (q.GetString and q:GetString(0)) or (q.GetRow and q:GetRow(0) and q:GetRow(0).im) or nil
    local n = tonumber(s)
    if not n then return 0, nil end
    return n, nil
end

local function GetActiveStockEvent()
    return _G.__CURRENT_STOCK_EVENT__ or { id = 0, change = 0, text = "No active event" }
end

local function CalculatePercentChange(change, original)
    local percentChange = 0
    if math.abs(original) > 0 then
        percentChange = (change / math.abs(original)) * 100
    elseif change > 0 then
        percentChange = 100
    end
    return math.floor(percentChange * 100 + 0.5) / 100
end

local function EscapeSQLString(s)
    if not s then return "" end
    return (tostring(s):gsub("'", "''"))
end

local function LogTransaction(accountId, guid, eventId, changeAmount, resultingCopper, description)
    local original = resultingCopper - changeAmount
    local percentChange = CalculatePercentChange(changeAmount, original)
    local sign = percentChange >= 0 and "+" or ""
    local percentString = string.format("%s%.2f%%", sign, percentChange)
    SafeDBExecute(
        "INSERT INTO character_stockmarket_log " ..
        "(account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) " ..
        "VALUES (%.0f, %.0f, %.0f, %.0f, '%s', %.2f, '%s', NOW())",
        accountId, guid, eventId, changeAmount, percentString, (resultingCopper / 10000),
        EscapeSQLString(description)
    )
end

local function ValidateGoldInput(input)
    if not input or input == "" then return nil, "No value entered" end
    local cleanInput = tostring(input):gsub("[^%d]", "")
    local goldAmount = tonumber(cleanInput)
    if not goldAmount or goldAmount <= 0 then
        return nil, "Invalid amount entered"
    end
    local copperAmount = goldAmount * 10000
    if copperAmount < MIN_TRANSACTION then
        return nil, "Minimum transaction is 1 gold"
    end
    if copperAmount > GOLD_CAP_COPPER then
        return nil, "Amount too large"
    end
    return copperAmount, nil
end

local function ProcessDeposit(player, amount)
    local accountId = player:GetAccountId()
    local guid = player:GetGUIDLow()

    if amount == 0 then
        amount = player:GetCoinage()
    end
    if amount < MIN_TRANSACTION then
        return false, "Minimum deposit is 1 gold"
    end
    if player:GetCoinage() < amount then
        return false, "Insufficient funds"
    end

    local investedOld, err = GetInvested(accountId)
    if err then return false, err end

    if investedOld + amount > GOLD_CAP_COPPER then
        local maxDeposit = GOLD_CAP_COPPER - investedOld
        if maxDeposit <= 0 then
            return false, "You've reached the maximum allowed investment"
        else
            return false, ("Deposit would exceed cap. Max you can deposit now: %s"):format(FormatMoney(maxDeposit))
        end
    end

    player:ModifyMoney(-amount)

    SafeDBExecute(
        "INSERT INTO character_stockmarket (account, InvestedMoney, last_updated) " ..
        "VALUES (%.0f, %.0f, NOW()) " ..
        "ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + VALUES(InvestedMoney), last_updated = NOW()",
        accountId, amount
    )

    local investedNew = investedOld + amount
    local percentChange = CalculatePercentChange(amount, investedOld)
    local e = GetActiveStockEvent()
    LogTransaction(accountId, guid, (type(e.id) == "number" and e.id or 0), amount, investedNew, "NPC Deposit")

    return true, amount, percentChange, investedNew
end

local function ProcessWithdrawal(player, amount)
    local accountId = player:GetAccountId()
    local guid = player:GetGUIDLow()

    local investedOld, err = GetInvested(accountId)
    if err then return false, err end
    if investedOld == 0 then return false, "No investments to withdraw" end

    if amount == 0 then amount = investedOld end
    amount = math.min(amount, investedOld, WITHDRAW_CAP_COPPER)
    if amount < MIN_TRANSACTION then
        return false, "Minimum withdrawal is 1 gold"
    end

    local playerCopper = player:GetCoinage()
    local maxAllowed = GOLD_CAP_COPPER - playerCopper
    if maxAllowed <= 0 then
        return false, "You cannot hold any more gold"
    end
    amount = math.min(amount, maxAllowed)
    if amount <= 0 then
        return false, "Cannot withdraw - would exceed gold cap"
    end

    player:ModifyMoney(amount)

    SafeDBExecute(
        "UPDATE character_stockmarket SET InvestedMoney = InvestedMoney - %.0f, last_updated = NOW() WHERE account = %.0f",
        amount, accountId
    )

    local investedNew = investedOld - amount
    local percentChange = CalculatePercentChange(-amount, investedOld)
    local e = GetActiveStockEvent()
    LogTransaction(accountId, guid, (type(e.id) == "number" and e.id or 0), -amount, investedNew, "NPC Withdrawal")

    return true, amount, percentChange, investedNew
end

local function GetNextEventMessage()
    local eventTime = rawget(_G, "__NEXT_STOCK_EVENT_TIME__")
    local now = os.time()
    local timeLeft = type(eventTime) == "number" and (eventTime - now) or 0
    if timeLeft > 0 then
        local minutes = math.ceil(timeLeft / 60)
        return string.format("Next Market Event in: |cff00ff00%d minute%s|r",
            minutes, minutes == 1 and "" or "s")
    else
        return "Next Market Event: |cffff0000Not scheduled|r"
    end
end

local function OnGossipHello(event, player, creature)
    local accountId = player:GetAccountId()
    local invested, err = GetInvested(accountId)
    if err then
        player:SendBroadcastMessage("|cffff0000[StockMarket]|r " .. err)
        return
    end

    local formattedInvestment = FormatMoney(invested)
    local timeMessage = GetNextEventMessage()

    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "Account Investment: " .. formattedInvestment, 1, 99999)
    player:GossipMenuAddItem(0, timeMessage, 1, 99998)
    player:GossipMenuAddItem(0, "|cFFFFFF00[Deposit Custom Amount]|r", 1, INPUT_DEPOSIT, true, "Enter the amount of gold to deposit:")
    player:GossipMenuAddItem(0, "|cFFFFFF00[Withdraw Custom Amount]|r", 1, INPUT_WITHDRAW, true, "Enter the amount of gold to withdraw:")
    player:GossipMenuAddItem(0, "|cFF00FF00[Deposit All Gold]|r", 1, INPUT_DEPOSIT_ALL)
    player:GossipMenuAddItem(0, "|cFFFF0000[Withdraw All Investments]|r", 1, INPUT_WITHDRAW_ALL)
    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, intid, code)
    local amount = 0

    if intid == INPUT_DEPOSIT or intid == INPUT_WITHDRAW then
        local validatedAmount, validationError = ValidateGoldInput(code)
        if validationError then
            player:SendBroadcastMessage("|cffff0000[StockMarket]|r " .. validationError .. ".")
            player:GossipComplete()
            return
        end
        amount = validatedAmount
    end

    if intid == INPUT_DEPOSIT or intid == INPUT_DEPOSIT_ALL then
        local success, result, percentChange, newTotal = ProcessDeposit(player, amount)
        if success then
            player:SendBroadcastMessage(string.format("|cff00ff00[StockMarket]|r Deposit successful: %s", FormatMoney(result)))
            player:SendBroadcastMessage(string.format("|cff00ff00[StockMarket]|r Investment change: |cff00ff00+%.2f%%|r", percentChange))
            player:SendBroadcastMessage(string.format("|cff00ff00[StockMarket]|r Total invested: %s", FormatMoney(newTotal)))
        else
            player:SendBroadcastMessage("|cffff0000[StockMarket]|r " .. result .. ".")
        end
    elseif intid == INPUT_WITHDRAW or intid == INPUT_WITHDRAW_ALL then
        local success, result, percentChange, newTotal = ProcessWithdrawal(player, amount)
        if success then
            player:SendBroadcastMessage(string.format("|cff00ff00[StockMarket]|r Withdrawal successful: %s", FormatMoney(result)))
            player:SendBroadcastMessage(string.format("|cff00ff00[StockMarket]|r Investment change: |cffff0000%.2f%%|r", percentChange))
            player:SendBroadcastMessage(string.format("|cff00ff00[StockMarket]|r Total invested: %s", FormatMoney(newTotal)))
        else
            player:SendBroadcastMessage("|cffff0000[StockMarket]|r " .. result .. ".")
        end
    end

    player:GossipComplete()
end

RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 2, OnGossipSelect)
