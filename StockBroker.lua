local STOCK_BROKER_NPC_ID = 90001
local INPUT_DEPOSIT       = 50001
local INPUT_WITHDRAW      = 50002
local INPUT_DEPOSIT_ALL   = 50003
local INPUT_WITHDRAW_ALL  = 50004

local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:16:16:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16:0:0|t"

local MAX_COPPER          = 2147483647
local GOLD_CAP_COPPER     = 2140000000
local WITHDRAW_CAP_COPPER = 2147480000

local function FormatGold(c)
    c = tonumber(c or 0)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local r = c % 100
    return string.format("%d%s %d%s %d%s", g, GOLD_ICON, s, SILVER_ICON, r, COPPER_ICON)
end

local function GetInvested(account)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE account = " .. account)
    return q and tonumber(q:GetRow(0).InvestedMoney) or 0
end

local function GetActiveStockEvent()
    return _G.__CURRENT_STOCK_EVENT__ or { id = 0, change = 0 }
end

local function LogTransaction(account, guid, event_id, change, resultingCopper, description)
    local percentChange = 0
    local original = resultingCopper - change
    if math.abs(original) > 0 then
        percentChange = (change / math.abs(original)) * 100
    elseif change > 0 then
        percentChange = 100
    end
    percentChange = math.floor(percentChange * 100 + 0.5) / 100
    local sign = percentChange > 0 and "+" or (percentChange < 0 and "-" or "")
    local percentString = string.format("%s%.2f%%", sign, math.abs(percentChange))

    CharDBExecute(string.format(
        "INSERT INTO character_stockmarket_log (account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) " ..
        "VALUES (%d, %d, %d, %d, '%s', %.2f, '%s', NOW())",
        account, guid, event_id, change, percentString, resultingCopper / 10000, description
    ))
end

local function OnGossipHello(event, player, creature)
    local account   = player:GetAccountId()
    local invested  = GetInvested(account)
    local formatted = FormatGold(invested)

    local eventTime = rawget(_G, "__NEXT_STOCK_EVENT_TIME__")
    local now       = os.time()
    local timeLeft  = type(eventTime) == "number" and (eventTime - now) or 0
    local minutes   = math.ceil(timeLeft / 60)
    local timeMsg   = timeLeft > 0 and
        string.format("Next Market Event in: %d minute%s", minutes, minutes == 1 and "" or "s") or
        "Next Market Event: |cffff0000Not scheduled|r"

    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "Account Investment: " .. formatted, 1, 99999)
    player:GossipMenuAddItem(0, timeMsg, 1, 99998)
    player:GossipMenuAddItem(0, "|cFFFFFF00[Deposit Custom Amount]|r",   1, INPUT_DEPOSIT,      true, "Insert the amount of gold to deposit:")
    player:GossipMenuAddItem(0, "|cFFFFFF00[Withdraw Custom Amount]|r",  1, INPUT_WITHDRAW,     true, "Insert the amount of gold to withdraw:")
    player:GossipMenuAddItem(0, "|cFF00FF00[Deposit All]|r",             1, INPUT_DEPOSIT_ALL)
    player:GossipMenuAddItem(0, "|cFFFF0000[Withdraw All]|r",            1, INPUT_WITHDRAW_ALL)
    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, intid, code)
    local account = player:GetAccountId()
    local guid    = player:GetGUIDLow()
    local amount

    if intid == INPUT_DEPOSIT or intid == INPUT_WITHDRAW then
        if not code then
            player:SendBroadcastMessage("|cffff0000No value entered.|r")
            player:GossipComplete()
            return
        end
        local clean = code:gsub("[^%d]", "")
        local gold  = tonumber(clean)
        if not gold or gold <= 0 then
            player:SendBroadcastMessage("|cffff0000Invalid amount.|r")
            player:GossipComplete()
            return
        end
        amount = gold * 10000
        if amount > MAX_COPPER then
            player:SendBroadcastMessage("|cffff0000Too much gold entered.|r")
            player:GossipComplete()
            return
        end
    end

    if intid == INPUT_DEPOSIT or intid == INPUT_DEPOSIT_ALL then
        local copper = (intid == INPUT_DEPOSIT_ALL) and player:GetCoinage() or amount
        if copper > 0 and player:GetCoinage() >= copper then
            local old = GetInvested(account)
            player:ModifyMoney(-copper)
            CharDBExecute(string.format(
                "INSERT INTO character_stockmarket (account, InvestedMoney, last_updated) " ..
                "VALUES (%d, %d, NOW()) ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + %d, last_updated = NOW()",
                account, copper, copper
            ))
            local total = old + copper
            LogTransaction(account, guid, 1, copper, total, "Player deposited gold.")

            local percent = (old > 0) and (copper / old) * 100 or 100
            percent = math.floor(percent * 100 + 0.5) / 100
            local sign  = (percent > 0) and "+" or ""
            player:SendBroadcastMessage(string.format("|cff00ff00Deposited %s.|r", FormatGold(copper)))
            player:SendBroadcastMessage(string.format("|cffffff00Investment change:|r |cff00ff00%s%.2f%%%s", sign, percent, "|r"))
        else
            player:SendBroadcastMessage("|cffff0000Not enough gold.|r")
        end

    elseif intid == INPUT_WITHDRAW or intid == INPUT_WITHDRAW_ALL then
        local invested       = GetInvested(account)
        local requested      = (intid == INPUT_WITHDRAW_ALL) and invested or amount
        if requested > WITHDRAW_CAP_COPPER then
            requested = WITHDRAW_CAP_COPPER
        end

        local playerGold     = player:GetCoinage()
        local maxAllowed     = GOLD_CAP_COPPER - playerGold
        local withdrawAmount = math.min(requested, invested, maxAllowed)

        if withdrawAmount <= 0 then
            player:SendBroadcastMessage("|cffff0000You are already at or over the gold cap (214,000g).|r")
            player:GossipComplete()
            return
        end

        player:ModifyMoney(withdrawAmount)

        CharDBExecute(string.format(
            "UPDATE character_stockmarket SET InvestedMoney = InvestedMoney - %d, last_updated = NOW() WHERE account = %d",
            withdrawAmount, account
        ))
        local total = invested - withdrawAmount
        LogTransaction(account, guid, 2, -withdrawAmount, total, "Player withdrew gold.")

        local percent = (invested > 0) and (-withdrawAmount / invested) * 100 or 0
        percent = math.floor(percent * 100 + 0.5) / 100
        local sign  = (percent > 0) and "+" or ""
        player:SendBroadcastMessage(string.format("|cff00ff00Withdrew %s.|r", FormatGold(withdrawAmount)))
        player:SendBroadcastMessage(string.format("|cffffff00Investment change:|r |cffff0000%s%.2f%%%s", sign, percent, "|r"))
    end

    player:GossipComplete()
end

RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 2, OnGossipSelect)
