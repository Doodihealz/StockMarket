if _G.__STOCKMARKET_CLEAN__ then return end
_G.__STOCKMARKET_CLEAN__ = true

local __NEXT_LOG_EVENT_ID__ = (function()
    local q = CharDBQuery("SELECT MAX(event_id) FROM character_stockmarket_log")
    return (q and not q:IsNull(0)) and q:GetUInt32(0) + 1 or 1
end)()
local __NEXT_STOCK_EVENT_TIME__ = 0
local __STOCKDATA_COOLDOWNS__ = {}

local function GetInvested(guid)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
    return q and tonumber(q:GetRow(0).InvestedMoney) or 0
end

local function GetActiveStockEvent()
    return _G.__CURRENT_STOCK_EVENT__ or { id = "NULL", change = 0, text = "" }
end

CreateLuaEvent(function()
    CharDBExecute("TRUNCATE TABLE character_stockmarket_log")
end, 86400000, 0)

local function Deposit(p, c)
    local g = p:GetGUIDLow()
    if type(c) ~= "number" or c < 10000 then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Minimum deposit is 1 gold.")
        return
    elseif p:GetCoinage() < c then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Not enough funds.")
        return
    end

    local investedOld = GetInvested(g)
    p:ModifyMoney(-c)
    CharDBExecute(("INSERT INTO character_stockmarket (guid,InvestedMoney,last_updated) VALUES(%d,%d,NOW()) ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + VALUES(InvestedMoney), last_updated = NOW()"):format(g, c))
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. g)
    local investedNew = q and not q:IsNull(0) and q:GetUInt32(0) or 0

    local pctDelta = investedOld > 0 and (c / investedOld) * 100 or 100
    pctDelta = math.floor(pctDelta * 100 + 0.5) / 100
    local pctStr = ("%+.2f%%"):format(pctDelta)
    CharDBExecute(("INSERT INTO character_stockmarket_log (guid,event_id,change_amount,percent_change,resulting_gold,description,created_at) VALUES(%d,%d,%d,'%s',%.2f,'Deposit: %s',NOW())")
        :format(g, __NEXT_LOG_EVENT_ID__, c, pctStr, investedNew / 10000, GetActiveStockEvent().text))
    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1

    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Deposit successful: %dg (~%s)"):format(c / 10000, pctStr))
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Total invested: %dg"):format(investedNew / 10000))
end

local function Withdraw(p, c)
    local g = p:GetGUIDLow()
    if type(c) ~= "number" or c < 1 then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Minimum withdraw is 1 copper."); return
    end

    local investedOld = GetInvested(g)
    if c > investedOld then
        p:SendBroadcastMessage("|cffff0000[StockMarket]|r Insufficient invested funds."); return
    end

    local investedNew = investedOld - c
    p:ModifyMoney(c)
    CharDBExecute(("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE guid = %d"):format(investedNew, g))

    local changeAmt = -c
    local pctDelta = investedOld > 0 and (changeAmt / investedOld) * 100 or 0
    pctDelta = math.floor(pctDelta * 100 + 0.5) / 100
    local pctStr = ("%+.2f%%"):format(pctDelta)
    CharDBExecute(("INSERT INTO character_stockmarket_log (guid,event_id,change_amount,percent_change,resulting_gold,description,created_at) VALUES(%d,%d,%d,'%s',%.2f,'Withdraw',NOW())")
        :format(g, GetActiveStockEvent().id, changeAmt, pctStr, investedNew / 10000))
    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1

    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Withdraw successful: %dg (~%s)"):format(c / 10000, pctStr))
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Total invested: %dg"):format(investedNew / 10000))
end

local function QueryInvestment(p)
    local invested = GetInvested(p:GetGUIDLow())
    local gold = math.floor(invested / 10000)
    local silver = math.floor((invested % 10000) / 100)
    local copper = invested % 100
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Your investment: %d|TInterface\\MoneyFrame\\UI-GoldIcon:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0|t")
        :format(gold, silver, copper))
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
    local q = CharDBQuery("SELECT guid, InvestedMoney FROM character_stockmarket WHERE InvestedMoney > 0")
    if q then
        repeat
            local g, investedOld = q:GetUInt32(0), q:GetUInt32(1)
            local investedNew = math.floor(investedOld * m)
            local delta = investedNew - investedOld
            local pctDelta = investedOld > 0 and (delta / investedOld) * 100 or 0
            pctDelta = math.floor(pctDelta * 100 + 0.5) / 100
            local pctStr = ("%+.2f%%"):format(pctDelta)

            CharDBExecute(("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE guid = %d"):format(investedNew, g))
            CharDBExecute(("INSERT INTO character_stockmarket_log (guid,event_id,change_amount,percent_change,resulting_gold,description,created_at) VALUES(%d,%d,%d,'%s',%.2f,'Market Event: %s',NOW())")
                :format(g, e.id, delta, pctStr, investedNew / 10000, e.text))
        until not q:NextRow()
    end

    _G.__CURRENT_STOCK_EVENT__ = e
    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1

    if isManual and PLAYER then
    end
end

local function ScheduleNextStockEvent()
    local delay = math.random(900000, 1800000)
    __NEXT_STOCK_EVENT_TIME__ = os.time() + math.floor(delay / 1000)
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
    local cmd, arg = command:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    arg = tonumber(arg)

    if not player or cmd == "" then return true end

    local validCommands = {
        deposit = true, withdraw = true, stockdata = true,
        stockhelp = true, stocktimer = true, stockevent = true
    }
    if not validCommands[cmd] then return true end

    local now, guid = os.time(), player:GetGUIDLow()
    local key = guid .. "_" .. cmd
    if now - (__STOCKDATA_COOLDOWNS__[key] or 0) < 300 then
        player:SendBroadcastMessage("|cffffcc00[StockMarket]|r You can only use this command once every 5 minutes.")
        return true
    end
    __STOCKDATA_COOLDOWNS__[key] = now

    if cmd == "deposit" and arg then
        Deposit(player, arg)
    elseif cmd == "withdraw" and arg then
        Withdraw(player, arg)
    elseif cmd == "stockdata" then
        QueryInvestment(player)
    elseif cmd == "stockhelp" then
        player:SendBroadcastMessage("|cff00ff00[StockMarket]|r Available commands:")
        player:SendBroadcastMessage("|cffffff00.deposit <copper>|r  Deposit money")
        player:SendBroadcastMessage("|cffffff00.withdraw <copper>|r Withdraw money")
        player:SendBroadcastMessage("|cffffff00.stockdata|r       View investment")
        player:SendBroadcastMessage("|cffffff00.stocktimer|r      Time to next event")
        player:SendBroadcastMessage("|cffffff00.stockevent|r      Trigger event (GM)")
    elseif cmd == "stocktimer" then
        local remaining = (__NEXT_STOCK_EVENT_TIME__ or now) - now
        if remaining > 0 then
            player:SendBroadcastMessage(("[StockMarket] Next market event in %d minute%s."):format(math.ceil(remaining / 60), math.ceil(remaining / 60) == 1 and "" or "s"))
        else
            player:SendBroadcastMessage("|cffffcc00[StockMarket]|r No market event scheduled.")
        end
    elseif cmd == "stockevent" then
        if not player:IsGM() or not player:IsGMVisible() then
            player:SendBroadcastMessage("|cffff0000[StockMarket]|r GM mode required.")
            return true
        end
        TriggerHourlyEvent(true)
        player:SendBroadcastMessage("|cff00ff00[StockMarket]|r Stock market event triggered.")
    end

    return true
end)
