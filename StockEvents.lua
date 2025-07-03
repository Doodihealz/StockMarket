if _G.__STOCKMARKET_CLEAN__ then return end
_G.__STOCKMARKET_CLEAN__ = true

local GOLD_CAP_COPPER = 2147483647

local __NEXT_LOG_EVENT_ID__ = (function()
    local q = CharDBQuery("SELECT MAX(event_id) FROM character_stockmarket_log")
    return (q and not q:IsNull(0)) and q:GetUInt32(0) + 1 or 1
end)()
local __STOCKDATA_COOLDOWNS__ = {}

CharDBExecute("DELETE FROM character_stockmarket_log WHERE created_at < NOW() - INTERVAL 1 DAY")

local function GetInvested(account)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE account = " .. account)
    if not q then
        print("[StockMarket] Database query failed for GetInvested (Account: " .. account .. ")")
        return nil, "db_error"
    end
    local row = q:GetRow(0)
    if not row then return 0 end
    return tonumber(row.InvestedMoney) or 0
end

local function GetActiveStockEvent()
    return _G.__CURRENT_STOCK_EVENT__ or { id = "NULL", change = 0, text = "" }
end

CreateLuaEvent(function()
    CharDBExecute("DELETE FROM character_stockmarket_log WHERE created_at < NOW() - INTERVAL 1 DAY")
end, 86400000, 0)

local function Deposit(p, c)
    local acc = p:GetAccountId()
    local guid = p:GetGUIDLow()

    if type(c) ~= "number" or c < 10000 then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Minimum deposit is 1 gold."); return
    elseif p:GetCoinage() < c then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Not enough funds."); return
    end

    local investedOld, err = GetInvested(acc)
    if err == "db_error" then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Error accessing investment data."); return
    end

    if investedOld + c > GOLD_CAP_COPPER then
        local maxDeposit = GOLD_CAP_COPPER - investedOld
        if maxDeposit <= 0 then
            p:SendBroadcastMessage("|cffff0000[StockMarket]|r You've reached the maximum allowed investment."); return
        end
        local g, s, co = math.floor(maxDeposit/10000), math.floor((maxDeposit%10000)/100), maxDeposit%100
        p:SendBroadcastMessage(("|cffff0000[StockMarket]|r Deposit would exceed gold cap. Max: %dg %ds %dc."):format(g, s, co))
        return
    end

    p:ModifyMoney(-c)
    CharDBExecute(("INSERT INTO character_stockmarket (account,InvestedMoney,last_updated) VALUES(%d,%d,NOW()) ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + VALUES(InvestedMoney), last_updated = NOW()"):format(acc, c))
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE account = " .. acc)
    local investedNew = q and not q:IsNull(0) and q:GetUInt32(0) or 0

    local pctDelta = investedOld > 0 and (c / investedOld) * 100 or 100
    pctDelta = math.floor(pctDelta * 100 + 0.5) / 100
    local pctStr = ("%+.2f%%"):format(pctDelta)

    CharDBExecute(("INSERT INTO character_stockmarket_log (account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) VALUES(%d, %d, %d, %d, '%s', %.2f, 'Deposit: %s', NOW())")
        :format(acc, guid, __NEXT_LOG_EVENT_ID__, c, pctStr, investedNew / 10000, GetActiveStockEvent().text))
    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1

    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Deposit successful: %dg (+%s)"):format(c / 10000, pctStr))
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Total invested: %dg"):format(investedNew / 10000))
end

local function Withdraw(p, c)
    local acc = p:GetAccountId()
    local guid = p:GetGUIDLow()

    if type(c) ~= "number" or c < 1 then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Minimum withdraw is 1 copper."); return
    end

    local investedOld, err = GetInvested(acc)
    if err == "db_error" then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Error accessing investment data."); return
    end

    if c > investedOld then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Insufficient invested funds."); return
    end

    local currentMoney = p:GetCoinage()
    if currentMoney + c > GOLD_CAP_COPPER then
        local maxWithdraw = GOLD_CAP_COPPER - currentMoney
        if maxWithdraw <= 0 then
            p:SendBroadcastMessage("|cffff0000[StockMarket]|r You cannot hold any more gold. Withdraw denied."); return
        end
        local g, s, co = math.floor(maxWithdraw/10000), math.floor((maxWithdraw%10000)/100), maxWithdraw%100
        p:SendBroadcastMessage(("|cffff0000[StockMarket]|r Withdraw would exceed gold cap. Max: %dg %ds %dc."):format(g, s, co))
        return
    end

    local investedNew = investedOld - c
    p:ModifyMoney(c)
    CharDBExecute(("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE account = %d"):format(investedNew, acc))

    local changeAmt = -c
    local pctDelta = investedOld > 0 and (changeAmt / investedOld) * 100 or 0
    pctDelta = math.floor(pctDelta * 100 + 0.5) / 100
    local pctStr = ("%+.2f%%"):format(pctDelta)

    CharDBExecute(("INSERT INTO character_stockmarket_log (account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) VALUES(%d, %d, %d, %d, '%s', %.2f, 'Withdraw', NOW())")
        :format(acc, guid, GetActiveStockEvent().id, changeAmt, pctStr, investedNew / 10000))

    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1

    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Withdraw successful: %dg (~%s)"):format(c / 10000, pctStr))
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Total invested: %dg"):format(investedNew / 10000))
end

local function QueryInvestment(p)
    local acc = p:GetAccountId()
    local invested = GetInvested(acc) or 0
    local g, s, co = math.floor(invested/10000), math.floor((invested%10000)/100), invested%100
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Total account investment: %d|TInterface\\MoneyFrame\\UI-GoldIcon:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0|t")
        :format(g, s, co))
end

local function GetRandomStockEvent()
    local q = WorldDBQuery("SELECT id, event_text, percent_change, is_positive, rarity FROM stockmarket_events")
    if not q then return nil end

    local events, totalWeight = {}, 0
    repeat
        local id = q:GetUInt32(0)
        local text = q:GetString(1)
        local change = q:GetFloat(2)
        local positive = q:GetUInt8(3) == 1
        local rarity = q:GetUInt8(4)
        local weight = 1 / (rarity + 1) + (positive and 0.05 or 0)

        table.insert(events, {
            id = id,
            text = text,
            change = change,
            positive = positive,
            weight = weight
        })

        totalWeight = totalWeight + weight
    until not q:NextRow()

    local r, sum = math.random() * totalWeight, 0
    for _, e in ipairs(events) do
        sum = sum + e.weight
        if r <= sum then return e end
    end
    return nil
end

local function TriggerHourlyEvent(isManual)
    local e = GetRandomStockEvent()
    if not e then return end

    local color = e.positive and "|cff00ff00" or "|cffff0000"
    SendWorldMessage(("[StockMarket] %s: %s%+.2f%%%s"):format(e.text, color, e.change, "|r"))

    local m = 1 + (e.change / 100)
    local q = CharDBQuery("SELECT account, InvestedMoney FROM character_stockmarket WHERE InvestedMoney > 0")
    if q then
        repeat
            local account = q:GetUInt32(0)
            local investedOld = q:GetUInt32(1)
            local investedNew = math.floor(investedOld * m)
            local delta = investedNew - investedOld
            local pctDelta = investedOld > 0 and (delta / investedOld) * 100 or 0
            pctDelta = math.floor(pctDelta * 100 + 0.5) / 100
            local pctStr = ("%+.2f%%"):format(pctDelta)

            CharDBExecute(("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE account = %d")
                :format(investedNew, account))

            CharDBExecute(("INSERT INTO character_stockmarket_log (account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) VALUES(%d, %d, %d, %d, '%s', %.2f, 'Market Event: %s', NOW())")
                :format(account, 0, e.id, delta, pctStr, investedNew / 10000, e.text))
        until not q:NextRow()
    end

    _G.__CURRENT_STOCK_EVENT__ = e
    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1

    if isManual and PLAYER then
    end
end

local function ScheduleNextStockEvent()
    local delay = math.random(900000, 1800000)
    _G.__NEXT_STOCK_EVENT_TIME__ = os.time() + math.floor(delay / 1000)
    SendWorldMessage(("[StockMarket] Next stock market event in %d minute%s."):format(math.floor(delay / 60000), math.floor(delay / 60000) == 1 and "" or "s"))
    CreateLuaEvent(function()
        TriggerHourlyEvent(false)
        ScheduleNextStockEvent()
    end, delay, 1)
end

local function AnnounceNextStockEventTime()
    local remaining = __NEXT_STOCK_EVENT_TIME__ - os.time()
    if remaining > 0 then
        SendWorldMessage(("[StockMarket] Next market event in %d minute%s."):format(math.ceil(remaining/60), math.ceil(remaining/60) == 1 and "" or "s"))
    end
end

CreateLuaEvent(AnnounceNextStockEventTime, 600000, 0)
ScheduleNextStockEvent()

RegisterPlayerEvent(42, function(_, player, command)
    if not player or not command then return end

    local cmd, arg = command:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower():gsub("[#./]", "") or ""
    arg = tonumber(arg)

    local validCommands = {
        stockdata = true,
        stockhelp = true,
        stocktimer = true,
        stockevent = true
    }

    if not validCommands[cmd] then
        return
    end

    local now = os.time()
    local acc = player:GetAccountId()
    local key = acc .. "_" .. cmd

    __STOCKDATA_COOLDOWNS__ = __STOCKDATA_COOLDOWNS__ or {}
    if now - (__STOCKDATA_COOLDOWNS__[key] or 0) < 300 then
        player:SendBroadcastMessage("|cffffcc00[StockMarket]|r You can only use this command once every 5 minutes.")
        return false
    end
    __STOCKDATA_COOLDOWNS__[key] = now

    if cmd == "stockdata" then
        QueryInvestment(player)

    elseif cmd == "stockhelp" then
        player:SendBroadcastMessage("|cff00ff00[StockMarket]|r Available commands:")
        player:SendBroadcastMessage("|cffffff00.stockdata|r       View investment")
        player:SendBroadcastMessage("|cffffff00.stocktimer|r      Time to next event")
        player:SendBroadcastMessage("|cffffff00.stockevent|r      Trigger event (GM)")

    elseif cmd == "stocktimer" then
        local remaining = (__NEXT_STOCK_EVENT_TIME__ or now) - now
        if remaining > 0 then
            player:SendBroadcastMessage(("[StockMarket] Next market event in %d minute%s."):format(
                math.ceil(remaining / 60),
                math.ceil(remaining / 60) == 1 and "" or "s"
            ))
        else
            player:SendBroadcastMessage("|cffffcc00[StockMarket]|r No market event scheduled.")
        end

    elseif cmd == "stockevent" then
        if not player:IsGM() or not player:IsGMVisible() then
            player:SendBroadcastMessage("|cffff0000[StockMarket]|r GM mode required.")
            return false
        end
        TriggerHourlyEvent(true)
        player:SendBroadcastMessage("|cff00ff00[StockMarket]|r Stock market event triggered.")
    end

    return false
end)

RegisterPlayerEvent(3, function(_, player)
    local remaining = __NEXT_STOCK_EVENT_TIME__ - os.time()
    if remaining > 0 then
        player:SendBroadcastMessage(("[StockMarket] Next market event in %d minute%s."):format(
            math.ceil(remaining / 60),
            math.ceil(remaining / 60) == 1 and "" or "s"
        ))
    end
end)
