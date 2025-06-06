if _G.__STOCKMARKET_CLEAN__ then return end
_G.__STOCKMARKET_CLEAN__ = true

local function GetNextLogEventID()
    local q = CharDBQuery("SELECT MAX(event_id) FROM character_stockmarket_log")
    if q and not q:IsNull(0) then
        return q:GetUInt32(0) + 1
    else
        return 1
    end
end

local __NEXT_LOG_EVENT_ID__ = GetNextLogEventID()

local function CleanOldStockLogs()
    CharDBExecute("TRUNCATE TABLE character_stockmarket_log")
end

CreateLuaEvent(CleanOldStockLogs, 86400000, 0)

local function GetInvested(guid)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
    return q and tonumber(q:GetRow(0).InvestedMoney) or 0
end

local function GetActiveStockEvent()
    return _G.__CURRENT_STOCK_EVENT__ or { id = "NULL", change = "NULL" }
end

local function GetRandomStockEventByRange(minChange, maxChange)
    local q = WorldDBQuery(string.format([[SELECT id, event_text, percent_change, is_positive, rarity
        FROM stockmarket_events WHERE ABS(percent_change) BETWEEN %.2f AND %.2f]], minChange, maxChange))

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

        table.insert(events, { id = id, text = text, change = change, positive = positive, rarity = rarity, weight = weight })
        totalWeight = totalWeight + weight
    until not q:NextRow()

    local r = math.random() * totalWeight
    local sum = 0
    for _, event in ipairs(events) do
        sum = sum + event.weight
        if r <= sum then return event end
    end
    return nil
end

local function PickEventTier()
    local roll = math.random()
    if roll <= 0.10 then return "major" end
    if roll <= 0.50 then return "minor" end
    return "micro"
end

local function GetTierRange(tier)
    if tier == "micro" then return 0.1, 1.0 end
    if tier == "minor" then return 1.1, 3.0 end
    if tier == "major" then return 3.1, 10.0 end
end

local function GetTierDelay(tier)
    if tier == "micro" then return math.random(600000, 1200000) end
    if tier == "minor" then return math.random(1200000, 1800000) end
    if tier == "major" then return math.random(1800000, 3600000) end
end

local __NEXT_STOCK_EVENT_TIME__ = 0

local function TriggerStockEvent()
    local event = _G.__CURRENT_STOCK_EVENT__
    if not event then return end

    local color = event.positive and "|cff00ff00" or "|cffff0000"
    local sign = event.positive and "+" or "-"
    local display = string.format("[StockMarket] %s: %s%s%.2f%%|r", event.text, color, sign, math.abs(event.change))
    SendWorldMessage(display)
    print((string.gsub(display, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))

    local multiplier = 1 + (event.change / 100)
    local results = CharDBQuery("SELECT guid, InvestedMoney FROM character_stockmarket WHERE InvestedMoney > 0")

    if results then
        repeat
            local guid = results:GetUInt32(0)
            local invested = results:GetUInt32(1)
            local newAmount = math.floor(invested * multiplier)
            local delta = newAmount - invested

            CharDBExecute(string.format("UPDATE character_stockmarket SET InvestedMoney = %d, last_updated = NOW() WHERE guid = %d", newAmount, guid))

            CharDBExecute(string.format([[INSERT INTO character_stockmarket_log
                (guid, event_id, change_amount, resulting_gold, percent_change, description)
                VALUES (%d, %d, %d, %d, %.2f, 'Market Event: %s')]],
                guid, event.id, delta, math.floor(newAmount / 10000), event.change, event.text))
        until not results:NextRow()
    end
end

local function ScheduleNextStockEvent()
    local tier = PickEventTier()
    local minChange, maxChange = GetTierRange(tier)
    local delay = GetTierDelay(tier)
    local minutes = math.floor(delay / 60000)
    __NEXT_STOCK_EVENT_TIME__ = os.time() + math.floor(delay / 1000)

    local microETA = math.floor(GetTierDelay("micro") / 60000)
    local minorETA = math.floor(GetTierDelay("minor") / 60000)
    local majorRoll = math.random()
    local majorETA = majorRoll <= 0.10 and math.floor(GetTierDelay("major") / 60000) or nil

    SendWorldMessage("[StockMarket] Micro event ETA: " .. microETA .. " minutes.")
    SendWorldMessage("[StockMarket] Minor event ETA: " .. minorETA .. " minutes.")
    if majorETA then
        SendWorldMessage("[StockMarket] Major event ETA: " .. majorETA .. " minutes.")
    else
        SendWorldMessage("[StockMarket] Major event ETA: Not expected within the next hour.")
    end

    CreateLuaEvent(function()
        local event = GetRandomStockEventByRange(minChange, maxChange)
        if event then
            _G.__CURRENT_STOCK_EVENT__ = event
            TriggerStockEvent()
        end
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

CreateLuaEvent(AnnounceNextStockEventTime, 600000, 0)
ScheduleNextStockEvent()

local __STOCKDATA_COOLDOWNS__ = {}

local function OnStockDataCommand(event, player, command)
    if command:lower():gsub("[#./]", "") ~= "stockdata" then return end

    local guid = player:GetGUIDLow()
    local now = os.time()

    if not player:IsGM() then
        local lastUsed = __STOCKDATA_COOLDOWNS__[guid] or 0
        if now - lastUsed < 300 then
            player:SendBroadcastMessage("|cffffcc00[StockMarket]|r You can only use this command once every 5 minutes.")
            return false
        end
        __STOCKDATA_COOLDOWNS__[guid] = now
    end

    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
    if not q or q:IsNull(0) then
        player:SendBroadcastMessage("|cffffcc00[StockMarket]|r No money in stock market. Go invest!")
        return false
    end

    local copper = q:GetUInt32(0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local remainingCopper = copper % 100

    local msg = string.format("|cff00ff00[StockMarket]|r Your investment: %d|TInterface\\MoneyFrame\\UI-GoldIcon:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0|t",
        gold, silver, remainingCopper)
    player:SendBroadcastMessage(msg)

    return false
end

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
            TriggerStockEvent()
            local msg = string.format("|cff00ff00[StockMarket]|r Manual event %d triggered: %s", event.id, event.text)
            player:SendBroadcastMessage(msg)
            print(msg)
        else
            local tier = PickEventTier()
            local minChange, maxChange = GetTierRange(tier)
            local event = GetRandomStockEventByRange(minChange, maxChange)
            if event then
                _G.__CURRENT_STOCK_EVENT__ = event
                TriggerStockEvent()
            end
        end

        return false
    end
end

RegisterPlayerEvent(42, OnStockDataCommand)
RegisterPlayerEvent(42, OnGMCommand)

local function OnPlayerLogin(event, player)
    local function eta(ms)
        return string.format("%d minutes", math.floor(ms / 60000))
    end

    local microETA = eta(GetTierDelay("micro"))
    local minorETA = eta(GetTierDelay("minor"))
    local majorChance = math.random() <= 0.10
    local majorETA = majorChance and eta(GetTierDelay("major")) or "Not expected within the next hour"

    player:SendBroadcastMessage("[StockMarket] Micro event ETA: " .. microETA .. ".")
    player:SendBroadcastMessage("[StockMarket] Minor event ETA: " .. minorETA .. ".")
    player:SendBroadcastMessage("[StockMarket] Major event ETA: " .. majorETA .. ".")
end

RegisterPlayerEvent(3, OnPlayerLogin)
