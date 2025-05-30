local STOCK_BROKER_NPC_ID = 90001
local INPUT_DEPOSIT = 50001
local INPUT_WITHDRAW = 50002

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:16:16:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16:0:0|t"

local MAX_COPPER = 2147483647

local function FormatGold(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRest = copper % 100
    return string.format("%d%s %d%s %d%s", gold, GOLD_ICON, silver, SILVER_ICON, copperRest, COPPER_ICON)
end

local function GetInvested(guid)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
    return q and tonumber(q:GetRow(0).InvestedMoney) or 0
end

local function LogTransaction(guid, event_id, change_amount, resulting_gold, description)
    CharDBExecute(string.format([[
        INSERT INTO character_stockmarket_log
        (guid, event_id, change_amount, percent_change, resulting_gold, description, created_at)
        VALUES (%d, %d, %d, 0, %d, '%s', NOW())
    ]], guid, event_id, change_amount, resulting_gold, description))
end

local function OnGossipHello(event, player, creature)
    player:GossipClearMenu()

    local guid = player:GetGUIDLow()
    local investedCopper = GetInvested(guid)
    local investedGold = FormatGold(investedCopper)

    player:GossipMenuAddItem(0, "Total Invested: " .. investedGold, 1, 99999)

    player:GossipMenuAddItem(0, "|cFFFFFF00[Deposit Gold]|r", 1, INPUT_DEPOSIT, true, "Insert the amount of gold you want to deposit:")
    player:GossipMenuAddItem(0, "|cFFFFFF00[Withdraw Gold]|r", 1, INPUT_WITHDRAW, true, "Insert the amount of gold you want to withdraw:")

    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, intid, code)
    local guid = player:GetGUIDLow()

    if not code then
        player:SendBroadcastMessage("|cffff0000No value entered. Please try again.|r")
        player:GossipComplete()
        return
    end

    local cleaned = string.gsub(code, "[^%d]", "")
    local gold = tonumber(cleaned)
    if not gold or gold <= 0 then
        player:SendBroadcastMessage("|cffff0000Invalid amount entered.|r")
        player:GossipComplete()
        return
    end

    local copper = gold * 10000
    if copper > MAX_COPPER then
        player:SendBroadcastMessage("|cffff0000Amount too large. Max allowed is 214,748 gold.|r")
        player:GossipComplete()
        return
    end

    if intid == INPUT_DEPOSIT then
        local playerCopper = player:GetCoinage()
        if playerCopper >= copper then
            CharDBExecute(string.format([[
                INSERT INTO character_stockmarket (guid, InvestedMoney, last_updated)
                VALUES (%d, %d, NOW())
                ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + %d, last_updated = NOW()
            ]], guid, copper, copper))

            local newTotal = GetInvested(guid)
            LogTransaction(guid, 1, copper, newTotal, "Player deposited gold.")
            player:ModifyMoney(-copper)
            player:SendBroadcastMessage(string.format("|cff00ff00Deposited %d%s.|r", gold, GOLD_ICON))
        else
            player:SendBroadcastMessage("|cffff0000Not enough gold.|r")
        end

    elseif intid == INPUT_WITHDRAW then
        local invested = GetInvested(guid)
        if invested >= copper then
            CharDBExecute(string.format([[
                UPDATE character_stockmarket
                SET InvestedMoney = InvestedMoney - %d,
                    last_updated = NOW()
                WHERE guid = %d
            ]], copper, guid))

            local newTotal = invested - copper
            LogTransaction(guid, 2, -copper, newTotal, "Player withdrew gold.")
            player:ModifyMoney(copper)
            player:SendBroadcastMessage(string.format("|cff00ff00Withdrew %d%s.|r", gold, GOLD_ICON))
        else
            player:SendBroadcastMessage("|cffff0000Not enough invested funds.|r")
        end
    end

    player:GossipComplete()
end

RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 2, OnGossipSelect)

function Handlers.Deposit(player, copper)
    local guid = player:GetGUIDLow()
    if type(copper) ~= "number" then
        AIO.Msg():Add("StockMarket", "DepositResult", false, "Invalid amount."):Send(player)
        return
    end

    copper = math.floor(copper * 10000)

    if copper < 10000 then
        AIO.Msg():Add("StockMarket", "DepositResult", false, "Minimum deposit is 1 gold."):Send(player)
        return
    end

    if player:GetCoinage() < copper then
        AIO.Msg():Add("StockMarket", "DepositResult", false, "Not enough funds."):Send(player)
        return
    end

    player:ModifyMoney(-copper)

    CharDBExecute(string.format([[
        INSERT INTO character_stockmarket (guid, InvestedMoney, last_updated)
        VALUES (%d, %d, NOW())
        ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + %d, last_updated = NOW()
    ]], guid, copper, copper))

    local newTotal = GetInvested(guid)
    local event = GetActiveStockEvent()

    CharDBExecute(string.format([[
        INSERT INTO character_stockmarket_log (guid, event_id, change_amount, resulting_gold, percent_change, description)
        VALUES (%d, %s, %d, %d, %s, 'Deposit')
    ]], guid, tostring(event.id), copper, math.floor(newTotal / 10000), tostring(event.change)))

    AIO.Msg():Add("StockMarket", "DepositResult", true, copper):Add("StockMarket", "InvestedGold", newTotal):Send(player)
end
