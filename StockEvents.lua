-- Prevent multiple loads
if _G.__STOCKMARKET_CLEAN__ then
    return
end
_G.__STOCKMARKET_CLEAN__ = true

-- Clean old log entries every 24 hours
local function CleanOldStockLogs()
    CharDBExecute([[DELETE FROM character_stockmarket_log WHERE log_time < NOW() - INTERVAL 30 DAY]])
end
CreateLuaEvent(CleanOldStockLogs, 86400000, 0)

-- Get investment amount from DB
local function GetInvested(guid)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
    return q and tonumber(q:GetRow(0).InvestedMoney) or 0
end

-- Get latest stock event from global
local function GetActiveStockEvent()
    return _G.__CURRENT_STOCK_EVENT__ or { id = "NULL", change = "NULL" }
end

-- AIO registration (deferred until AIO is ready)
local function RegisterHandlers()
    if not AIO then
        CreateLuaEvent(RegisterHandlers, 1000, 1)
        return
    end

    if _G.__STOCKMARKET_HANDLERS_REGISTERED__ then return end
    _G.__STOCKMARKET_HANDLERS_REGISTERED__ = true

    local Handlers = {}

    function Handlers.Deposit(player, copper)
        local guid = player:GetGUIDLow()
        if type(copper) ~= "number" or copper < 10000 then
            AIO.Msg():Add("StockMarket", "DepositResult", false, "Minimum deposit is 1 gold."):Send(player)
            return
        end

        if player:GetCoinage() < copper then
            AIO.Msg():Add("StockMarket", "DepositResult", false, "Not enough funds."):Send(player)
            return
        end

        player:ModifyMoney(-copper)
        local total = GetInvested(guid) + copper
        local event = GetActiveStockEvent()

        CharDBExecute(string.format([[INSERT INTO character_stockmarket (guid, InvestedMoney, last_updated)
            VALUES (%d, %d, NOW())
            ON DUPLICATE KEY UPDATE InvestedMoney = VALUES(InvestedMoney), last_updated = NOW()]], guid, total))

        CharDBExecute(string.format([[INSERT INTO character_stockmarket_log (guid, event_id, change_amount, resulting_gold, percent_change, description)
            VALUES (%d, %s, %d, %d, %s, 'Deposit')]], guid, tostring(event.id), copper, math.floor(total / 10000), tostring(event.change)))

        AIO.Msg():Add("StockMarket", "DepositResult", true, copper):Add("StockMarket", "InvestedGold", total):Send(player)
    end

    function Handlers.Withdraw(player, copper)
        local guid = player:GetGUIDLow()
        if type(copper) ~= "number" or copper < 1 then
            AIO.Msg():Add("StockMarket", "WithdrawResult", false, "Minimum withdraw is 1 copper."):Send(player)
            return
        end

        local invested = GetInvested(guid)
        if copper > invested then
            AIO.Msg():Add("StockMarket", "WithdrawResult", false, "Insufficient invested funds."):Send(player)
            return
        end

        local total = invested - copper
        local event = GetActiveStockEvent()

        CharDBExecute(string.format("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE guid = %d", total, guid))

        CharDBExecute(string.format([[INSERT INTO character_stockmarket_log (guid, event_id, change_amount, resulting_gold, percent_change, description)
            VALUES (%d, %s, %d, %d, %s, 'Withdraw')]], guid, tostring(event.id), -copper, math.floor(total / 10000), tostring(event.change)))

        player:ModifyMoney(copper)

        AIO.Msg():Add("StockMarket", "WithdrawResult", true, copper):Add("StockMarket", "InvestedGold", total):Send(player)
    end

    function Handlers.Query(player)
        local guid = player:GetGUIDLow()
        local total = GetInvested(guid)
        AIO.Msg():Add("StockMarket", "InvestedGold", total):Send(player)
    end

    AIO.AddHandlers("StockMarket", Handlers)
end

CreateLuaEvent(RegisterHandlers, 0, 1)

local function GetRandomStockEvent()
    local q = WorldDBQuery("SELECT id, event_text, percent_change, is_positive, rarity FROM stockmarket_events")
    if not q then return nil end

    local events = {}
    local totalWeight = 0

    repeat
        local id = q:GetUInt32(0)
        local text = q:GetString(1)
        local change = q:GetFloat(2)
        local positive = q:GetUInt8(3) == 1
        local rarity = q:GetUInt8(4)

        local baseWeight = 1 / (rarity + 1)
        local bias = positive and 0.05 or 0
        local weight = baseWeight + bias

        table.insert(events, {
            id = id,
            text = text,
            change = change,
            positive = positive,
            rarity = rarity,
            weight = weight
        })

        totalWeight = totalWeight + weight
    until not q:NextRow()

    local r = math.random() * totalWeight
    local sum = 0
    for _, event in ipairs(events) do
        sum = sum + event.weight
        if r <= sum then
            return event
        end
    end

    return nil
end

local __NEXT_STOCK_EVENT_TIME__ = 0

local function TriggerHourlyEvent()
    local event = GetRandomStockEvent()
    if not event then return end

    local color = event.positive and "|cff00ff00" or "|cffff0000"
    local sign = event.positive and "+" or "-"
    local display = string.format("[StockMarket] %s: %s%s%.2f%%|r", event.text, color, sign, math.abs(event.change))
    SendWorldMessage(display)
    print(display)

    local multiplier = 1 + (event.change / 100)

    local results = CharDBQuery("SELECT guid, InvestedMoney FROM character_stockmarket WHERE InvestedMoney > 0")
    if results then
        repeat
            local guid = results:GetUInt32(0)
            local invested = results:GetUInt32(1)
            local newAmount = math.floor(invested * multiplier)
            local delta = newAmount - invested

            CharDBExecute(string.format(
                "UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE guid = %d",
                newAmount, guid
            ))

            CharDBExecute(string.format([[INSERT INTO character_stockmarket_log
                (guid, event_id, change_amount, resulting_gold, percent_change, description)
                VALUES (%d, %d, %d, %d, %.2f, 'Market Event: %s')]],
                guid, event.id, delta, math.floor(newAmount / 10000), event.change, event.text
            ))
        until not results:NextRow()
    end

    _G.__CURRENT_STOCK_EVENT__ = event
end

local function ScheduleNextStockEvent()
    local delay = math.random(600000, 3600000)
    local minutes = math.floor(delay / 60000)

    __NEXT_STOCK_EVENT_TIME__ = os.time() + math.floor(delay / 1000)
    local msg = string.format("[StockMarket] Next stock market event in %d minute%s.", minutes, minutes == 1 and "" or "s")
    SendWorldMessage(msg)
    print(msg)

    CreateLuaEvent(function()
        TriggerHourlyEvent()
        ScheduleNextStockEvent()
    end, delay, 1)
end

local function AnnounceNextStockEventTime()
    local remaining = __NEXT_STOCK_EVENT_TIME__ - os.time()
    if remaining > 0 then
        local minutes = math.ceil(remaining / 60)
        local msg = string.format("[StockMarket] Next market event in %d minute%s.", minutes, minutes == 1 and "" or "s")
        SendWorldMessage(msg)
        print(msg)
    end
end

-- Post countdown every 10 minutes
CreateLuaEvent(AnnounceNextStockEventTime, 600000, 0)

ScheduleNextStockEvent()

-- GM command: .stockevent
local function OnGMCommand(event, player, command)
    local args = {}
    for word in command:gmatch("%S+") do
        table.insert(args, word)
    end

    if args[1]:lower():gsub("[#./]", "") == "stockevent" then
        if not player:IsGM() then
            player:SendBroadcastMessage("You do not have permission to use this command.")
            return false
        end

        if args[2] then
            local eventId = tonumber(args[2])
            if not eventId then
                player:SendBroadcastMessage("|cffff0000Invalid event ID.|r")
                return false
            end

            local q = WorldDBQuery("SELECT id, event_text, percent_change, is_positive, rarity FROM stockmarket_events WHERE id = " .. eventId)
            if not q then
                player:SendBroadcastMessage("|cffff0000Event ID not found.|r")
                return false
            end

            local event = {
                id = q:GetUInt32(0),
                text = q:GetString(1),
                change = q:GetFloat(2),
                positive = q:GetUInt8(3) == 1,
                rarity = q:GetUInt8(4)
            }

            _G.__CURRENT_STOCK_EVENT__ = event
            TriggerHourlyEvent()
            local msg = string.format("|cff00ff00[StockMarket]|r Manual event %d triggered: %s", event.id, event.text)
            player:SendBroadcastMessage(msg)
            print(msg)
        else
            TriggerHourlyEvent()
        end

        return false
    end
end

RegisterPlayerEvent(42, OnGMCommand)
