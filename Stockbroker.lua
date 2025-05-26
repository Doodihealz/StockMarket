local STOCK_BROKER_NPC_ID = 90001
local INPUT_DEPOSIT = 50001
local INPUT_WITHDRAW = 50002

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:16:16:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16:0:0|t"

-- Format copper into gold/silver/copper string with icons
local function FormatGold(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRest = copper % 100
    return string.format("%d%s %d%s %d%s", gold, GOLD_ICON, silver, SILVER_ICON, copperRest, COPPER_ICON)
end

-- Get invested copper amount for player GUID
local function GetInvested(guid)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
    return q and tonumber(q:GetRow(0).InvestedMoney) or 0
end

-- Show gossip menu
local function OnGossipHello(event, player, creature)
    player:GossipClearMenu()

    local guid = player:GetGUIDLow()
    local investedCopper = GetInvested(guid)
    local investedGold = FormatGold(investedCopper)

    player:GossipMenuAddItem(0, "Total Invested: " .. investedGold, 1, 99999)

    -- Input boxes for deposit/withdraw with custom prompt
    player:GossipMenuAddItem(
        0,
        "|cFFFFFF00[Deposit Gold]|r",
        1,
        INPUT_DEPOSIT,
        true,
        "Insert the amount of gold you want to deposit:"
    )

    player:GossipMenuAddItem(
        0,
        "|cFFFFFF00[Withdraw Gold]|r",
        1,
        INPUT_WITHDRAW,
        true,
        "Insert the amount of gold you want to withdraw:"
    )

    player:GossipSendMenu(1, creature)
end

-- Handle deposit/withdraw logic based on input
local function OnGossipSelect(event, player, creature, sender, intid, code)
    local guid = player:GetGUIDLow()

    if intid == INPUT_DEPOSIT then
        local amount = tonumber(code)
        if not amount or amount <= 0 then
            player:SendBroadcastMessage("|cffff0000Invalid gold amount.|r")
        else
            local copper = amount * 10000
            if player:GetCoinage() >= copper then
                CharDBExecute(string.format([[
                    INSERT INTO character_stockmarket (guid, InvestedMoney, last_updated)
                    VALUES (%d, %d, NOW())
                    ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + %d, last_updated = NOW()
                ]], guid, copper, copper))
                player:ModifyMoney(-copper)
                player:SendBroadcastMessage(string.format("|cff00ff00Deposited %s.|r", FormatGold(copper)))
            else
                player:SendBroadcastMessage("|cffff0000Not enough gold.|r")
            end
        end

    elseif intid == INPUT_WITHDRAW then
        local amount = tonumber(code)
        if not amount or amount <= 0 then
            player:SendBroadcastMessage("|cffff0000Invalid gold amount.|r")
        else
            local copper = amount * 10000
            local invested = GetInvested(guid)
            if invested >= copper then
                CharDBExecute(string.format(
                    "UPDATE character_stockmarket SET InvestedMoney = InvestedMoney - %d, last_updated = NOW() WHERE guid = %d",
                    copper, guid
                ))
                player:ModifyMoney(copper)
                player:SendBroadcastMessage(string.format("|cff00ff00Withdrew %s.|r", FormatGold(copper)))
            else
                player:SendBroadcastMessage("|cffff0000Not enough invested funds.|r")
            end
        end
    end

    player:GossipComplete()
end

RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 2, OnGossipSelect)
