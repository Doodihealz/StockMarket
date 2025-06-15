if _G.__STOCKMARKET_CLEAN__ then return end
_G.__STOCKMARKET_CLEAN__ = true

local __NEXT_LOG_EVENT_ID__ = (function() local q = CharDBQuery("SELECT MAX(event_id) FROM character_stockmarket_log") return (q and not q:IsNull(0)) and q:GetUInt32(0) + 1 or 1 end)()
local __NEXT_STOCK_EVENT_TIME__ = 0
local __STOCKDATA_COOLDOWNS__ = {}

local function GetInvested(guid) local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid) return q and tonumber(q:GetRow(0).InvestedMoney) or 0 end
local function GetActiveStockEvent() return _G.__CURRENT_STOCK_EVENT__ or { id = "NULL", change = "NULL" } end
CreateLuaEvent(function() CharDBExecute("TRUNCATE TABLE character_stockmarket_log") end, 86400000, 0)

local function RegisterHandlers()
if not AIO then return CreateLuaEvent(RegisterHandlers, 1000, 1) end
if _G.__STOCKMARKET_HANDLERS_REGISTERED__ then return end
_G.__STOCKMARKET_HANDLERS_REGISTERED__ = true
local H = {}
function H.Deposit(p,c)
local g=p:GetGUIDLow()
if type(c)~="number"or c<10000 then return AIO.Msg():Add("StockMarket","DepositResult",false,"Minimum deposit is 1 gold."):Send(p)end
if p:GetCoinage()<c then return AIO.Msg():Add("StockMarket","DepositResult",false,"Not enough funds."):Send(p)end
p:ModifyMoney(-c)
CharDBExecute(string.format("INSERT INTO character_stockmarket (guid,InvestedMoney,last_updated) VALUES(%d,%d,NOW()) ON DUPLICATE KEY UPDATE InvestedMoney=InvestedMoney+VALUES(InvestedMoney),last_updated=NOW()",g,c))
local q=CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid="..g)
local total=(q and not q:IsNull(0))and q:GetUInt32(0)or 0
local e=GetActiveStockEvent()
CharDBExecute(string.format("INSERT INTO character_stockmarket_log (guid,event_id,change_amount,percent_change,resulting_gold,description,created_at) VALUES(%d,%d,%d,%.2f,%d,'Market Event: %s',NOW())",g,__NEXT_LOG_EVENT_ID__,c,e.change,math.floor(total/10000),e.text))
__NEXT_LOG_EVENT_ID__=__NEXT_LOG_EVENT_ID__+1
AIO.Msg():Add("StockMarket","DepositResult",true,c):Add("StockMarket","InvestedGold",total):Send(p)
end
function H.Withdraw(p, c)
local g = p:GetGUIDLow()
if type(c) ~= "number" or c < 1 then return AIO.Msg():Add("StockMarket", "WithdrawResult", false, "Minimum withdraw is 1 copper."):Send(p) end
local i = GetInvested(g)
if c > i then return AIO.Msg():Add("StockMarket", "WithdrawResult", false, "Insufficient invested funds."):Send(p) end
local total = i - c
local e = GetActiveStockEvent()
CharDBExecute(string.format("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE guid = %d", total, g))
CharDBExecute(string.format("INSERT INTO character_stockmarket_log (guid, event_id, change_amount, resulting_gold, percent_change, description) VALUES (%d, %s, %d, %d, %s, 'Withdraw')", g, tostring(e.id), -c, math.floor(total / 10000), tostring(e.change)))
p:ModifyMoney(c)
AIO.Msg():Add("StockMarket", "WithdrawResult", true, c):Add("StockMarket", "InvestedGold", total):Send(p)
end
function H.Query(p) local g = p:GetGUIDLow() AIO.Msg():Add("StockMarket", "InvestedGold", GetInvested(g)):Send(p) end
AIO.AddHandlers("StockMarket", H)
end
CreateLuaEvent(RegisterHandlers, 0, 1)

local function GetRandomStockEvent()
local q = WorldDBQuery("SELECT id, event_text, percent_change, is_positive, rarity FROM stockmarket_events")
if not q then return nil end
local events, totalWeight = {}, 0
repeat
local id, text, change, pos, rarity = q:GetUInt32(0), q:GetString(1), q:GetFloat(2), q:GetUInt8(3) == 1, q:GetUInt8(4)
local weight = 1 / (rarity + 1) + (pos and 0.05 or 0)
table.insert(events, {id=id, text=text, change=change, positive=pos, weight=weight})
totalWeight = totalWeight + weight
until not q:NextRow()
local r, sum = math.random() * totalWeight, 0
for _, e in ipairs(events) do sum = sum + e.weight if r <= sum then return e end end
end

local function TriggerHourlyEvent()
local e = GetRandomStockEvent()
if not e then return end
local color, sign = e.positive and "|cff00ff00" or "|cffff0000", e.positive and "+" or "-"
local msg = string.format("[StockMarket] %s: %s%s%.2f%%%s", e.text, color, sign, math.abs(e.change), "|r")
SendWorldMessage(msg)
local m = 1 + (e.change / 100)
local q = CharDBQuery("SELECT guid, InvestedMoney FROM character_stockmarket WHERE InvestedMoney > 0")
if q then
repeat
local g, i = q:GetUInt32(0), q:GetUInt32(1)
local new = math.floor(i * m)
local delta = new - i
CharDBExecute(string.format("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE guid = %d", new, g))
CharDBExecute(string.format("INSERT INTO character_stockmarket_log (guid, event_id, change_amount, resulting_gold, percent_change, description) VALUES (%d, %d, %d, %d, %.2f, 'Market Event: %s')", g, e.id, delta, math.floor(new / 10000), e.change, e.text))
until not q:NextRow()
end
_G.__CURRENT_STOCK_EVENT__ = e
end

local function ScheduleNextStockEvent()
local delay = math.random(900000, 1800000)
__NEXT_STOCK_EVENT_TIME__ = os.time() + math.floor(delay / 1000)
local min = math.floor(delay / 60000)
local msg = string.format("[StockMarket] Next stock market event in %d minute%s.", min, min==1 and "" or "s")
SendWorldMessage(msg)
CreateLuaEvent(function() TriggerHourlyEvent() ScheduleNextStockEvent() end, delay, 1)
end

local function AnnounceNextStockEventTime()
local t = __NEXT_STOCK_EVENT_TIME__ - os.time()
if t > 0 then
local min = math.ceil(t / 60)
local msg = string.format("[StockMarket] Next market event in %d minute%s.", min, min==1 and "" or "s")
SendWorldMessage(msg)
end
end

CreateLuaEvent(AnnounceNextStockEventTime, 600000, 0)
ScheduleNextStockEvent()

__STOCKDATA_COOLDOWNS__ = __STOCKDATA_COOLDOWNS__ or {}
__NEXT_STOCK_EVENT_TIME__ = __NEXT_STOCK_EVENT_TIME__ or os.time() + 600

RegisterPlayerEvent(42, function(_, player, command)
    if not player then return false end

    local cmd = command:lower():gsub("[#./]", "")
    local guid, now = player:GetGUIDLow(), os.time()
    local key = guid .. "_" .. cmd

    if cmd == "stockhelp" then
        player:SendBroadcastMessage("|cff00ff00[StockMarket]|r Available commands:")
        player:SendBroadcastMessage("|cffffff00.stockdata|r - View your current investment.")
        player:SendBroadcastMessage("|cffffff00.stocktimer|r - See when the next event will occur.")
        player:SendBroadcastMessage("|cffffff00.stockhelp|r - Show this help message.")
        return false
    end

    if cmd == "stockdata" or cmd == "stocktimer" then
        if not player:IsGM() and now - (__STOCKDATA_COOLDOWNS__[key] or 0) < 300 then
            player:SendBroadcastMessage("|cffffcc00[StockMarket]|r You can only use this command once every 5 minutes.")
            return false
        end
        __STOCKDATA_COOLDOWNS__[key] = now

        if cmd == "stocktimer" then
            local remaining = (__NEXT_STOCK_EVENT_TIME__ or now) - now
            local minutes = math.ceil(remaining / 60)
            local msg = remaining > 0 and string.format("|cff00ff00[StockMarket]|r Next market event in %d minute%s.", minutes, minutes == 1 and "" or "s")
                or "|cffffcc00[StockMarket]|r No market event is currently scheduled."
            player:SendBroadcastMessage(msg)

        elseif cmd == "stockdata" then
            local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
            if not q or q:IsNull(0) then
                player:SendBroadcastMessage("|cffffcc00[StockMarket]|r No money in stock market. Go invest!")
                return false
            end
            local copper = q:GetUInt32(0)
            local gold = math.floor(copper / 10000)
            local silver = math.floor((copper % 10000) / 100)
            local remainingCopper = copper % 100
            player:SendBroadcastMessage(string.format(
                "|cff00ff00[StockMarket]|r Your investment: %d|TInterface\\MoneyFrame\\UI-GoldIcon:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0|t",
                gold, silver, remainingCopper
            ))
        end
        return false
    end
end)
