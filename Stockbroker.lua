local STOCK_BROKER_NPC_ID = 90001
local INPUT_DEPOSIT = 50001
local INPUT_WITHDRAW = 50002
local INPUT_DEPOSIT_ALL = 50003
local INPUT_WITHDRAW_ALL = 50004

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:16:16:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16:0:0|t"
local MAX_COPPER = 2147483647

local function FormatGold(c)
    c = tonumber(c or 0)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local r = c % 100
    return string.format("%d%s %d%s %d%s", g, GOLD_ICON, s, SILVER_ICON, r, COPPER_ICON)
end

local function GetInvested(guid)
    local q = CharDBQuery("SELECT InvestedMoney FROM character_stockmarket WHERE guid = " .. guid)
    return q and tonumber(q:GetRow(0).InvestedMoney) or 0
end

local function GetActiveStockEvent()
    return _G.__CURRENT_STOCK_EVENT__ or { id = 0, change = 0 }
end

local function LogTransaction(guid, event_id, change, resultingCopper, description)
    local goldChange = change / 10000
    local resultingGold = resultingCopper / 10000
    local e = GetActiveStockEvent() or { id = 0, change = 0 }

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
        "INSERT INTO character_stockmarket_log (guid, event_id, change_amount, percent_change, resulting_gold, description, created_at) " ..
        "VALUES (%d, %d, %d, '%s', %.2f, '%s', NOW())",
        guid, e.id, change, percentString, resultingGold, description
    ))
end

local function OnGossipHello(event, player, creature)
    local guid = player:GetGUIDLow()
    local invested = GetInvested(guid)
    local formatted = FormatGold(invested)

    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "Total Invested: " .. formatted, 1, 99999)
    player:GossipMenuAddItem(0, "|cFFFFFF00[Deposit Custom Amount]|r", 1, INPUT_DEPOSIT, true, "Insert the amount of gold to deposit:")
    player:GossipMenuAddItem(0, "|cFFFFFF00[Withdraw Custom Amount]|r", 1, INPUT_WITHDRAW, true, "Insert the amount of gold to withdraw:")
    player:GossipMenuAddItem(0, "|cFF00FF00[Deposit All]|r", 1, INPUT_DEPOSIT_ALL)
    player:GossipMenuAddItem(0, "|cFFFF0000[Withdraw All]|r", 1, INPUT_WITHDRAW_ALL)
    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, intid, code)
    local guid = player:GetGUIDLow()
    local amount

    if intid == INPUT_DEPOSIT or intid == INPUT_WITHDRAW then
        if not code then
            player:SendBroadcastMessage("|cffff0000No value entered.|r")
            player:GossipComplete()
            return
        end

        local clean = string.gsub(code, "[^%d]", "")
        local gold = tonumber(clean)
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
            local old = GetInvested(guid)
            player:ModifyMoney(-copper)

            CharDBExecute(string.format(
                "INSERT INTO character_stockmarket (guid, InvestedMoney, last_updated) " ..
                "VALUES (%d, %d, NOW()) ON DUPLICATE KEY UPDATE InvestedMoney = InvestedMoney + %d, last_updated = NOW()",
                guid, copper, copper
            ))

            local total = old + copper
            LogTransaction(guid, 1, copper, total, "Player deposited gold.")

            local percent = (old > 0) and (copper / old) * 100 or 100
            percent = math.floor(percent * 100 + 0.5) / 100
            local sign = (percent > 0) and "+" or ""
            local color = (percent > 0) and "|cff00ff00" or "|cffffff00"

            player:SendBroadcastMessage(string.format("|cff00ff00Deposited %s.|r", FormatGold(copper)))
            player:SendBroadcastMessage(string.format("|cffffff00Investment change:|r %s%s%.2f%%%s", color, sign, percent, "|r"))
        else
            player:SendBroadcastMessage("|cffff0000Not enough gold.|r")
        end

    elseif intid == INPUT_WITHDRAW or intid == INPUT_WITHDRAW_ALL then
        local invested = GetInvested(guid)
        local withdrawAmount = (intid == INPUT_WITHDRAW_ALL) and invested or amount

        if invested >= withdrawAmount and withdrawAmount > 0 then
            CharDBExecute(string.format(
                "UPDATE character_stockmarket SET InvestedMoney = InvestedMoney - %d, last_updated = NOW() WHERE guid = %d",
                withdrawAmount, guid
            ))

            local total = invested - withdrawAmount
            LogTransaction(guid, 2, -withdrawAmount, total, "Player withdrew gold.")
            player:ModifyMoney(withdrawAmount)

            local percent = (invested > 0) and (-withdrawAmount / invested) * 100 or 0
            percent = math.floor(percent * 100 + 0.5) / 100
            local sign = (percent > 0) and "+" or ""
            local color = (percent < 0) and "|cffff0000" or "|cffffff00"

            player:SendBroadcastMessage(string.format("|cff00ff00Withdrew %s.|r", FormatGold(withdrawAmount)))
            player:SendBroadcastMessage(string.format("|cffffff00Investment change:|r %s%s%.2f%%%s", color, sign, percent, "|r"))
        else
            player:SendBroadcastMessage("|cffff0000Not enough invested funds.|r")
        end
    end

    player:GossipComplete()
end

RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(STOCK_BROKER_NPC_ID, 2, OnGossipSelect)
