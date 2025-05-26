local STOCK_BROKER_NPC_ID = 90001
local GOLD_VALUES = {1, 5, 10, 25, 50, 100, 500, 1000, 5000, 10000}

local OFFSET_WITHDRAW = 1000
local INTID_DEPOSIT_ALL = 999
local INTID_WITHDRAW_ALL = 1999

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:16:16:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16:0:0|t"

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

local function OnGossipHello(event, player, creature)
    player:GossipClearMenu()

    local guid = player:GetGUIDLow()
    local investedCopper = GetInvested(guid)
    local investedGold = FormatGold(investedCopper)

    player:GossipMenuAddItem(0, "Total Invested: " .. investedGold, 1, 99999)

    player:GossipMenuAddItem(0, "|cFFFFFF00[Deposit Gold]|r", 1, 0)
    for _, gold in ipairs(GOLD_VALUES) do
        player:GossipMenuAddItem(0, GOLD_ICON .. " Deposit " .. gold .. "g", 1, gold)
    end
    player:GossipMenuAddItem(0, GOLD_ICON .. " |cff00ff00Deposit All|r", 1, INTID_DEPOSIT_ALL)

    player:GossipMenuAddItem(0, "|cFFFFFF00[Withdraw Gold]|r", 1, OFFSET_WITHDRAW)
    for _, gold in ipairs(GOLD_VALUES) do
        player:GossipMenuAddItem(0, GOLD_ICON .. " Withdraw " .. gold .. "g", 1, OFFSET_WITHDRAW + gold)
    end
    player:GossipMenuAddItem(0, GOLD_ICON .. " |cff00ff00Withdraw All|r", 1, INTID_WITHDRAW_ALL)

    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, intid, code)
    local guid = player:GetGUIDLow()

    if intid == INTID_DEPOSIT_ALL then
        local copper = player:GetCoinage()
        if copper > 0 then
            CharDBExecute(string.format([[INSERT INTO character_stockmarket (guid, InvestedMoney, last_updated)
                VALUES (%d, %d, NOW())
                ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + %d, last_updated = NOW()]], guid, copper, copper))
            player:ModifyMoney(-copper)
            player:SendBroadcastMessage(string.format("|cff00ff00Deposited %s.|r", FormatGold(copper)))
        else
            player:SendBroadcastMessage("|cffff0000You have no gold to deposit.|r")
        end

    elseif intid == INTID_WITHDRAW_ALL then
        local invested = GetInvested(guid)
        if invested > 0 then
            CharDBExecute(string.format("UPDATE character_stockmarket SET InvestedMoney = 0, last_updated = NOW() WHERE guid = %d", guid))
            player:ModifyMoney(invested)
            player:SendBroadcastMessage(string.format("|cff00ff00Withdrew %s.|r", FormatGold(invested)))
        else
            player:SendBroadcastMessage("|cffff0000You have no invested funds.|r")
        end

    elseif intid > OFFSET_WITHDRAW then
        local copper = (intid - OFFSET_WITHDRAW) * 10000
        local invested = GetInvested(guid)
        if invested >= copper then
            CharDBExecute(string.format("UPDATE character_stockmarket SET InvestedMoney = InvestedMoney - %d, last_updated = NOW() WHERE guid = %d", copper, guid))
            player:ModifyMoney(copper)
            player:SendBroadcastMessage(string.format("|cff00ff00Withdrew %s.|r", FormatGold(copper)))
        else
            player:SendBroadcastMessage("|cffff0000Not enough invested funds.|r")
        end

    elseif intid > 0 then
        local copper = intid * 10000
        if player:GetCoinage() >= copper then
            CharDBExecute(string.format([[INSERT INTO character_stockmarket (guid, InvestedMoney, last_updated)
                VALUES (%d, %d, NOW())
                ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + %d, last_updated = NOW()]], guid, copper, copper))
            player:ModifyMoney(-copper)
            player:SendBroadcastMessage(string.format("|cff00ff00Deposited %s.|r", FormatGold(copper)))
        else
            player:SendBroadcastMessage("|cffff0000Not enough gold.|r")
        end
    end

    player:GossipComplete()
end

RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 2, OnGossipSelect)
