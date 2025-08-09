if _G.__STOCKMARKET_CLEAN__ then return end
_G.__STOCKMARKET_CLEAN__ = true

math.randomseed(os.time())

local GOLD_CAP_COPPER = 10000000000
local floor = math.floor
local min, max = math.min, math.max

local function safe_number(v, default)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
        return default or 0
    end
    return v
end

local function qnum(q, col, default)
    if not q or q:IsNull(col) then return default or 0 end
    local s = q:GetString(col)
    local n = tonumber(s)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default or 0 end
    return n
end

local __NEXT_LOG_EVENT_ID__ = (function()
    local q = CharDBQuery("SELECT MAX(event_id) FROM character_stockmarket_log")
    return (q and not q:IsNull(0)) and q:GetUInt32(0) + 1 or 1
end)()
local __STOCKDATA_COOLDOWNS__ = {}

CharDBExecute("DELETE FROM character_stockmarket_log WHERE created_at < NOW() - INTERVAL 1 DAY")

local function GetInvested(account)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE account = " .. account)
    if not q then return nil, "db_error" end
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
        local g, s, co = floor(maxDeposit/10000), floor((maxDeposit%10000)/100), maxDeposit%100
        p:SendBroadcastMessage(("|cffff0000[StockMarket]|r Deposit would exceed gold cap. Max: %dg %ds %dc."):format(g, s, co))
        return
    end
    p:ModifyMoney(-c)
    CharDBExecute(("INSERT INTO character_stockmarket (account,InvestedMoney,last_updated) VALUES(%.0f,%.0f,NOW()) ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + VALUES(InvestedMoney), last_updated = NOW()"):format(acc, c))
    local investedNew = investedOld + c
    investedNew = safe_number(investedNew, investedOld)
    local pctDelta = investedOld > 0 and (c / investedOld) * 100 or 100
    pctDelta = floor(pctDelta * 100 + 0.5) / 100
    local pctStr = ("%+.2f%%"):format(pctDelta)
    local active = GetActiveStockEvent()
    local eventId = active.id
    if eventId == "NULL" or type(eventId) ~= "number" then
        eventId = __NEXT_LOG_EVENT_ID__
    end
    CharDBExecute(("INSERT INTO character_stockmarket_log (account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) VALUES(%.0f, %.0f, %.0f, %.0f, '%s', %.2f, 'Deposit: %s', NOW())")
        :format(acc, guid, eventId, c, pctStr, investedNew / 10000, active.text))
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
        local g, s, co = floor(maxWithdraw/10000), floor((maxWithdraw%10000)/100), maxWithdraw%100
        p:SendBroadcastMessage(("|cffff0000[StockMarket]|r Withdraw would exceed gold cap. Max: %dg %ds %dc."):format(g, s, co))
        return
    end
    local investedNew = investedOld - c
    p:ModifyMoney(c)
    CharDBExecute(("UPDATE character_stockmarket SET InvestedMoney = %.0f, last_updated = NOW() WHERE account = %.0f"):format(investedNew, acc))
    local changeAmt = -c
    local pctDelta = investedOld > 0 and (changeAmt / investedOld) * 100 or 0
    pctDelta = floor(pctDelta * 100 + 0.5) / 100
    local pctStr = ("%+.2f%%"):format(pctDelta)
    local eventId = GetActiveStockEvent().id
    if eventId == "NULL" or type(eventId) ~= "number" then
        eventId = __NEXT_LOG_EVENT_ID__
    end
    CharDBExecute(("INSERT INTO character_stockmarket_log (account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) VALUES(%.0f, %.0f, %.0f, %.0f, '%s', %.2f, 'Withdraw', NOW())")
        :format(acc, guid, eventId, changeAmt, pctStr, investedNew / 10000))
    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Withdraw successful: %dg (~%s)"):format(c / 10000, pctStr))
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Total invested: %dg"):format(investedNew / 10000))
end

local function QueryInvestment(p)
    local acc = p:GetAccountId()
    local invested = GetInvested(acc) or 0
    local g, s, co = floor(invested/10000), floor((invested%10000)/100), invested%100
    p:SendBroadcastMessage(("|cff00ff00[StockMarket]|r Total account investment: %d|TInterface\\MoneyFrame\\UI-GoldIcon:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0|t")
        :format(g, s, co))
end

local function safeGetFloat(row, column, defaultValue)
    if not row or row:IsNull(column) then return defaultValue or 0 end
    local v = tonumber(row:GetFloat(column)) or (defaultValue or 0)
    if v ~= v or v == math.huge or v == -math.huge then return defaultValue or 0 end
    if math.abs(v) > 1e4 then return defaultValue or 0 end
    return v
end

local EVENTS, EVENTS_WEIGHT = nil, 0

local function LoadEvents()
    local q = WorldDBQuery("SELECT id, event_text, percent_change, is_positive, rarity FROM stockmarket_events")
    if not q then EVENTS, EVENTS_WEIGHT = {}, 0; return end
    local ev, total = {}, 0
    repeat
        local id       = q:GetUInt32(0)
        local text     = q:GetString(1)
        local change   = safeGetFloat(q, 2, 0)
        local positive = q:GetUInt8(3) == 1
        local rarity   = q:GetUInt8(4)
        local weight   = 1 / (rarity + 1) + (positive and 0.05 or 0)
        ev[#ev+1] = { id=id, text=text, change=change, positive=positive, weight=weight }
        total = total + weight
    until not q:NextRow()
    EVENTS, EVENTS_WEIGHT = ev, total
end

LoadEvents()

local function GetRandomStockEvent()
    if not EVENTS or #EVENTS == 0 then LoadEvents() end
    if not EVENTS or #EVENTS == 0 then return nil end
    local r, sum = math.random() * EVENTS_WEIGHT, 0
    for i=1,#EVENTS do
        local e = EVENTS[i]
        sum = sum + e.weight
        if r <= sum then return e end
    end
    return EVENTS[#EVENTS]
end

local function TriggerHourlyEvent(isManual)
    local e = GetRandomStockEvent()
    if not e then return end
    local safeChange = safe_number(e.change, 0)
    print(("[StockMarket] Triggering event: %s (%+.2f%%)"):format(e.text, safeChange))
    local color = e.positive and "|cff00ff00" or "|cffff0000"
    SendWorldMessage(("[StockMarket] %s: %s%+.2f%%%s"):format(e.text, color, safeChange, "|r"))
    local m = 1 + (safeChange / 100)
    local q = CharDBQuery("SELECT account, InvestedMoney FROM character_stockmarket WHERE InvestedMoney > 0")
    if q then
        repeat
            local account     = q:GetUInt32(0)
            local investedOld = qnum(q, 1, 0)
            local investedNewRaw = floor(investedOld * m)
            local investedNew = max(0, min(GOLD_CAP_COPPER, investedNewRaw))
            local delta       = investedNew - investedOld
            local pctDelta    = investedOld > 0 and (delta / investedOld) * 100 or 0
            pctDelta = floor(pctDelta * 100 + 0.5) / 100
            local pctStr = ("%+.2f%%"):format(pctDelta)
            CharDBExecute(("UPDATE character_stockmarket SET InvestedMoney = %.0f, last_updated = NOW() WHERE account = %.0f")
                :format(investedNew, account))
            CharDBExecute(("INSERT INTO character_stockmarket_log (account, guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) VALUES(%.0f, %.0f, %.0f, %.0f, '%s', %.2f, 'Market Event: %s', NOW())")
                :format(account, 0, e.id, delta, pctStr, investedNew / 10000, e.text))
        until not q:NextRow()
    end
    _G.__CURRENT_STOCK_EVENT__ = e
    __NEXT_LOG_EVENT_ID__ = __NEXT_LOG_EVENT_ID__ + 1
end

local function ScheduleNextStockEvent()
    local delay = math.random(900000, 1800000)
    _G.__NEXT_STOCK_EVENT_TIME__ = os.time() + floor(delay / 1000)
    print(string.format("[StockMarket] Scheduling next event in %d minute%s", floor(delay / 60000), floor(delay / 60000) == 1 and "" or "s"))
    CreateLuaEvent(function()
        TriggerHourlyEvent(false)
        ScheduleNextStockEvent()
    end, delay, 1)
end

local function AnnounceNextStockEventTime()
    local remaining = _G.__NEXT_STOCK_EVENT_TIME__ - os.time()
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
    local valid = { stockdata=true, stockdeposit=true, stockwithdraw=true, stockhelp=true, stocktimer=true, stockevent=true }
    if not valid[cmd] then return end
    local now = os.time()
    local acc = player:GetAccountId()
    local key = acc .. "_" .. cmd
    __STOCKDATA_COOLDOWNS__[key] = __STOCKDATA_COOLDOWNS__[key] or 0
    if now - __STOCKDATA_COOLDOWNS__[key] < 300 then
        player:SendBroadcastMessage("|cffffcc00[StockMarket]|r You can only use this command once every 5 minutes.")
        return false
    end
    __STOCKDATA_COOLDOWNS__[key] = now
    if cmd == "stockdata" then
        QueryInvestment(player)
    elseif cmd == "stockdeposit" then
        if arg and arg > 0 then Deposit(player, arg * 10000) else Deposit(player, player:GetCoinage()) end
    elseif cmd == "stockwithdraw" then
        if arg and arg > 0 then
            Withdraw(player, arg * 10000)
        else
            local invested = GetInvested(acc) or 0
            Withdraw(player, invested)
        end
    elseif cmd == "stockhelp" then
        player:SendBroadcastMessage("|cff00ff00[StockMarket]|r Available commands:")
        player:SendBroadcastMessage("|cffffff00.stockdata|r       View investment")
        player:SendBroadcastMessage("|cffffff00.stockdeposit [gold]|r  Deposit gold (0 = all)")
        player:SendBroadcastMessage("|cffffff00.stockwithdraw [gold]|r Withdraw gold (0 = all)")
        player:SendBroadcastMessage("|cffffff00.stocktimer|r      Time to next event")
        player:SendBroadcastMessage("|cffffff00.stockevent|r      Trigger event (GM)")
    elseif cmd == "stocktimer" then
        local remaining = (_G.__NEXT_STOCK_EVENT_TIME__ or now) - now
        if remaining > 0 then
            player:SendBroadcastMessage(("[StockMarket] Next market event in %d minute%s."):format(math.ceil(remaining/60), math.ceil(remaining/60) == 1 and "" or "s"))
        else
            player:SendBroadcastMessage("|cffffcc00[StockMarket]|r No market event scheduled.")
        end
    elseif cmd == "stockevent" then
        if not player:IsGM() or not player:IsGMVisible() then
            player:SendBroadcastMessage("|cffff0000[StockMarket]|r GM mode required.")
        else
            TriggerHourlyEvent(true)
            player:SendBroadcastMessage("|cff00ff00[StockMarket]|r Stock market event triggered.")
        end
    end
    return false
end)

RegisterPlayerEvent(3, function(_, player)
    local remaining = (_G.__NEXT_STOCK_EVENT_TIME__ or os.time()) - os.time()
    if remaining > 0 then
        player:SendBroadcastMessage(("[StockMarket] Next market event in %d minute%s."):format(math.ceil(remaining/60), math.ceil(remaining/60) == 1 and "" or "s"))
    end
end)
