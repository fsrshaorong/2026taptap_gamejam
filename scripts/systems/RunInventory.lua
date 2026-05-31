-- ============================================================================
-- RunInventory.lua
-- Tracks one extraction run's loot and searched rooms.
-- ============================================================================

local Balance = require("systems.Balance")

local RunInventory = {}

RunInventory.gold = 0
RunInventory.pendingGold = 0
RunInventory.safeGold = 0
RunInventory.parts = 0
RunInventory.searchedRooms = {}
RunInventory.carriedItems = {}
RunInventory.consumables = {}
RunInventory.failureSalvage = nil
RunInventory.searchBonus = 0  -- 搜索奖励加成百分比(装备效果)
RunInventory.stats = {}

RunInventory.ITEM_DEFS = {
    {
        id = "broken_copper_wire",
        name = "断裂铜线",
        type = "relic",
        typeName = "异常回收物",
        rarity = "common",
        rarityName = "一般",
        icon = "assets/items/broken_copper_wire.png",
        value = 8,
        effectText = nil,
        description = "仍然能卖钱，这已经很难得了。",
    },
    {
        id = "dim_capacitor",
        name = "暗淡电容",
        type = "relic",
        typeName = "异常回收物",
        rarity = "common",
        rarityName = "一般",
        icon = "assets/items/dim_capacitor.png",
        value = 10,
        effectText = nil,
        description = "拆下来时它轻轻响了一声，像是在叹气。",
    },
    {
        id = "whisper_wick",
        name = "低语灯芯",
        type = "relic",
        typeName = "异常回收物",
        rarity = "rare",
        rarityName = "稀有",
        icon = "assets/items/whisper_wick.png",
        value = 45,
        effectText = nil,
        description = "它在没有电源的情况下发光，并且偶尔像在催你下班。",
    },
    {
        id = "sealed_core_shard",
        name = "封存核心碎片",
        type = "relic",
        typeName = "异常回收物",
        rarity = "rare",
        rarityName = "稀有",
        icon = "assets/items/sealed_core_shard.png",
        value = 45,
        effectText = nil,
        description = "被封条压住的裂片仍在缓慢发热。",
    },
    {
        id = "emergency_bandage",
        name = "应急止血贴",
        type = "consumable",
        typeName = "作业消耗品",
        rarity = "common",
        rarityName = "一般",
        icon = "assets/items/emergency_bandage.png",
        value = 10,
        effectText = "恢复少量生命。",
        description = "后勤部称它经过消毒。包装上的日期不建议细看。",
    },
    {
        id = "static_lens",
        name = "静电透镜",
        type = "tool",
        typeName = "异常回收物",
        rarity = "uncommon",
        rarityName = "稀有",
        icon = "assets/items/static_lens.png",
        value = 16,
        effectText = "可作为后续扫描设备材料。",
        description = "透过它看灯光时，会看见不存在的边界线。",
    },
    {
        id = "blackbox_tag",
        name = "黑匣标签",
        type = "record",
        typeName = "异常回收物",
        rarity = "uncommon",
        rarityName = "稀有",
        icon = "assets/items/blackbox_tag.png",
        value = 18,
        effectText = nil,
        description = "标签上的编号被刮掉了，只剩下回收部门的旧印章。",
    },
}

local ITEM_DEF_LOOKUP = {}
for _, def in ipairs(RunInventory.ITEM_DEFS) do
    def.baseValue = def.baseValue or def.value or 0
    def.value = def.value or def.baseValue
    ITEM_DEF_LOOKUP[def.id] = def
end

local QUALITY_ITEMS = {
    low = "broken_copper_wire",
    common = "dim_capacitor",
    rare = "static_lens",
    precious = "whisper_wick",
    abnormal = "sealed_core_shard",
}

local function syncGoldAlias()
    RunInventory.gold = RunInventory.pendingGold
end

local function itemBaseValue(def)
    return def and (def.baseValue or def.value or 0) or 0
end

local function pickQualityFromTable(dropTable, roll, adjacent)
    if adjacent and adjacent >= Balance.search.highAdjacentBonus.adjacentAtLeast then
        roll = math.min(100, roll + Balance.search.highAdjacentBonus.rareBonus)
    end
    for _, entry in ipairs(dropTable or {}) do
        if roll <= entry.max then
            return entry.quality
        end
    end
    return nil
end

local function newStats()
    return {
        moves = 0,
        searchedRooms = 0,
        chestRooms = 0,
        mineHits = 0,
        mineImmunityUsed = 0,
        monstersDefeated = 0,
        combatDamage = 0,
        trades = 0,
        eventsCompleted = 0,
        diceEvents = 0,
        altarEvents = 0,
        trapEvents = 0,
    }
end

local function cellKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

function RunInventory.Reset()
    RunInventory.gold = 0
    RunInventory.pendingGold = 0
    RunInventory.safeGold = 0
    RunInventory.parts = 0
    RunInventory.searchedRooms = {}
    RunInventory.carriedItems = {}
    RunInventory.consumables = {}
    RunInventory.failureSalvage = nil
    RunInventory.searchBonus = 0
    RunInventory.stats = newStats()
end

function RunInventory.AddPendingGold(amount)
    amount = math.floor(tonumber(amount) or 0)
    RunInventory.pendingGold = math.max(0, RunInventory.pendingGold + amount)
    syncGoldAlias()
    return RunInventory.pendingGold
end

function RunInventory.AddSafeGold(amount)
    amount = math.floor(tonumber(amount) or 0)
    RunInventory.safeGold = math.max(0, RunInventory.safeGold + amount)
    syncGoldAlias()
    return RunInventory.safeGold
end

function RunInventory.SpendPendingGold(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    if RunInventory.pendingGold < amount then return false end
    RunInventory.pendingGold = RunInventory.pendingGold - amount
    syncGoldAlias()
    return true
end

function RunInventory.CellKey(x, y)
    return cellKey(x, y)
end

function RunInventory.GetItemDef(itemId)
    return ITEM_DEF_LOOKUP[itemId]
end

local function copyConsumables(consumables)
    local copied = {}
    for itemId, count in pairs(consumables or {}) do
        count = math.floor(tonumber(count) or 0)
        if count > 0 then
            copied[itemId] = count
        end
    end
    return copied
end

local RUN_ICON_KEYS = {
    emergency_bandage = "item.consumable.emergency_bandage",
}

local function getRunIconKey(def)
    if not def then return "item.placeholder" end
    if RUN_ICON_KEYS[def.id] then return RUN_ICON_KEYS[def.id] end
    if def.type == "consumable" then return "item.consumable.default" end
    return "item.recovered.default"
end

local function makeRunDisplayAdapter(item)
    local value = item.baseValue or item.value or 0
    local category = item.category or (item.type == "consumable" and "consumable" or "recovered")
    item.category = category
    item.branch = item.branch or category
    item.kind = item.kind or item.type or "relic"
    item.iconKey = item.iconKey or getRunIconKey(item)
    item.display = {
        iconKey = item.iconKey,
        category = category,
        rarity = item.rarity or "common",
        typeLabel = item.typeName or "异常回收物",
        rarityLabel = item.rarityName or "一般",
        shortEffect = item.effectText or "",
        shortDescription = item.description or "",
        valueText = value > 0 and tostring(value) or "",
        priceText = "",
        statusText = item.statusText or "",
        primaryAction = item.primaryAction,
        secondaryAction = item.secondaryAction,
        disabledReason = item.disabledReason,
    }
    return item
end

function RunInventory.GetItemDisplayData(itemId)
    local def = RunInventory.GetItemDef(itemId) or {}
    return makeRunDisplayAdapter({
        id = itemId,
        name = def.name or "未知物品",
        type = def.type or "relic",
        typeName = def.typeName or "异常回收物",
        category = def.type == "consumable" and "consumable" or "recovered",
        rarity = def.rarity or "common",
        rarityName = def.rarityName or "一般",
        icon = def.icon or "",
        iconKey = def.iconKey,
        value = itemBaseValue(def),
        baseValue = itemBaseValue(def),
        effectText = def.effectText,
        description = def.description or "",
        source = "recovered",
        unique = def.unique == true,
    })
end

function RunInventory.SetConsumables(consumables)
    RunInventory.consumables = copyConsumables(consumables)
end

function RunInventory.AddConsumable(itemId, count)
    local def = RunInventory.GetItemDef(itemId)
    if not def then return false, "unknown_item" end
    if def.type ~= "consumable" then return false, "not_consumable" end
    count = math.floor(tonumber(count) or 1)
    if count < 1 then return false, "invalid_count" end
    RunInventory.consumables[itemId] = (RunInventory.consumables[itemId] or 0) + count
    return true, { itemId = itemId, count = count, total = RunInventory.consumables[itemId] }
end

function RunInventory.GetConsumableCount(itemId)
    return RunInventory.consumables[itemId] or 0
end

function RunInventory.GetConsumables()
    return copyConsumables(RunInventory.consumables)
end

function RunInventory.UseConsumable(itemId, context)
    context = context or {}
    local def = RunInventory.GetItemDef(itemId)
    if not def or def.type ~= "consumable" then return false, "not_consumable" end
    local count = RunInventory.GetConsumableCount(itemId)
    if count <= 0 then return false, "not_enough" end

    if itemId == "emergency_bandage" then
        local hp = context.hp or 0
        local maxHp = context.maxHp or hp
        if hp >= maxHp then return false, "hp_full" end
        local heal = math.min(25, maxHp - hp)
        local result = nil
        if context.applyHpDelta then
            result = context.applyHpDelta(heal)
        end
        RunInventory.consumables[itemId] = count - 1
        if RunInventory.consumables[itemId] <= 0 then
            RunInventory.consumables[itemId] = nil
        end
        return true, {
            itemId = itemId,
            heal = heal,
            count = RunInventory.GetConsumableCount(itemId),
            result = result,
        }
    end

    return false, "not_implemented"
end

function RunInventory.GetAllItemDefs()
    return RunInventory.ITEM_DEFS
end

function RunInventory.GetItemDisplayName(itemId)
    local def = RunInventory.GetItemDef(itemId)
    return def and def.name or tostring(itemId or "未知物品")
end

function RunInventory.HasItemIcon(itemId)
    local def = RunInventory.GetItemDef(itemId)
    if not def or not def.icon or def.icon == "" then
        return false
    end
    local ok = cache:Exists(def.icon)
    return ok
end

local function copyItemStack(stack)
    local def = RunInventory.GetItemDef(stack.itemId)
    return {
        itemId = stack.itemId,
        count = stack.count,
        source = stack.source,
        def = def,
    }
end

function RunInventory.AddCarriedItem(itemId, count, source)
    local def = RunInventory.GetItemDef(itemId)
    if not def then
        return false, "unknown_item"
    end
    count = math.floor(tonumber(count) or 1)
    if count < 1 then count = 1 end

    local stack = RunInventory.carriedItems[itemId]
    if not stack then
        stack = { itemId = itemId, count = 0, source = source or "unknown" }
        RunInventory.carriedItems[itemId] = stack
    end
    stack.count = stack.count + count
    stack.source = source or stack.source
    return true, copyItemStack(stack)
end

function RunInventory.AddRewardItemByQuality(quality, source)
    local itemId = QUALITY_ITEMS[quality or "common"] or QUALITY_ITEMS.common
    local ok, stack = RunInventory.AddCarriedItem(itemId, 1, source or "event")
    if ok then
        RunInventory.parts = RunInventory.parts + 1
        return stack
    end
    return nil
end

function RunInventory.GetCarriedItems()
    local items = {}
    for _, stack in pairs(RunInventory.carriedItems) do
        table.insert(items, copyItemStack(stack))
    end
    table.sort(items, function(a, b)
        return (a.def and a.def.name or a.itemId) < (b.def and b.def.name or b.itemId)
    end)
    return items
end

function RunInventory.GetCarriedItemCount()
    local count = 0
    for _, stack in pairs(RunInventory.carriedItems) do
        count = count + (stack.count or 0)
    end
    return count
end

function RunInventory.GetCarriedItemValue()
    local value = 0
    for _, stack in pairs(RunInventory.carriedItems) do
        local def = RunInventory.GetItemDef(stack.itemId)
        value = value + (itemBaseValue(def) * (stack.count or 0))
    end
    return value
end

function RunInventory.ClearCarriedItems()
    RunInventory.carriedItems = {}
end

function RunInventory.ConvertCarriedItemsToPartsOrGold(partsToGoldRate)
    return RunInventory.GetExtractionReward(partsToGoldRate)
end

function RunInventory.GetLooseParts()
    local looseParts = RunInventory.parts - RunInventory.GetCarriedItemCount()
    if looseParts < 0 then looseParts = 0 end
    return looseParts
end

function RunInventory.GetCarriedItemSummary(maxItems)
    maxItems = maxItems or 3
    local names = {}
    for _, stack in ipairs(RunInventory.GetCarriedItems()) do
        local def = stack.def
        table.insert(names, (def and def.name or stack.itemId) .. " x" .. stack.count)
        if #names >= maxItems then break end
    end
    local remaining = RunInventory.GetCarriedItemCount() - #names
    if remaining > 0 then
        table.insert(names, "等 " .. RunInventory.GetCarriedItemCount() .. " 件")
    end
    if #names == 0 then return "无" end
    return table.concat(names, " / ")
end

function RunInventory.GetTradableItems()
    local items = {}
    for _, stack in ipairs(RunInventory.GetCarriedItems()) do
        table.insert(items, {
            id = stack.itemId,
            itemId = stack.itemId,
            name = stack.def and stack.def.name or stack.itemId,
            count = stack.count,
            value = itemBaseValue(stack.def),
            baseValue = itemBaseValue(stack.def),
            type = stack.def and stack.def.type or "unknown",
        })
    end
    table.insert(items, {
        id = "parts",
        itemId = "parts",
        name = "异常回收物",
        count = RunInventory.GetLooseParts(),
        value = 10,
        type = "virtual",
    })
    return items
end

function RunInventory.GetTradableItemDisplayName(itemId)
    if itemId == "parts" then return "异常回收物" end
    return RunInventory.GetItemDisplayName(itemId)
end

function RunInventory.GetTradableItemCount(itemId)
    if itemId == "parts" then return RunInventory.GetLooseParts() end
    local stack = RunInventory.carriedItems[itemId]
    return stack and stack.count or 0
end

function RunInventory.RemoveTradableItem(itemId, count)
    count = math.floor(tonumber(count) or 1)
    if count < 1 then count = 1 end
    if itemId == "parts" then
        if RunInventory.GetLooseParts() < count then return false, "not_enough" end
        RunInventory.parts = RunInventory.parts - count
        return true
    end

    local stack = RunInventory.carriedItems[itemId]
    if not stack or stack.count < count then return false, "not_enough" end
    stack.count = stack.count - count
    RunInventory.parts = math.max(0, RunInventory.parts - count)
    if stack.count <= 0 then
        RunInventory.carriedItems[itemId] = nil
    end
    return true
end

local function chooseItemId(roll, isChest, index, adjacent)
    roll = ((roll or 0) + (index or 1) * 17) % 100 + 1
    local quality = pickQualityFromTable(isChest and Balance.chest.dropTable or Balance.search.dropTable, roll, adjacent)
    return quality and QUALITY_ITEMS[quality] or nil
end

local function buildRewardItems(roll, isChest, adjacent)
    local itemCount = 0
    if isChest then
        itemCount = Balance.RollRange(roll, adjacent or 0, 0, 5, Balance.chest.minItems, Balance.chest.maxItems)
    elseif chooseItemId(roll, false, 1, adjacent) then
        itemCount = 1
    end

    local items = {}
    for i = 1, itemCount do
        local itemId = chooseItemId(roll, isChest, i, adjacent)
        if not itemId then
            break
        end
        local found = nil
        for _, stack in ipairs(items) do
            if stack.itemId == itemId then
                found = stack
                break
            end
        end
        if found then
            found.count = found.count + 1
        else
            table.insert(items, { itemId = itemId, count = 1, source = isChest and "chest" or "search" })
        end
    end
    return items
end

function RunInventory.GetReward(minefield, x, y)
    local cell = minefield:GetCellView(x, y)
    local adjacent = (cell and cell.adjacent) or 0
    local seed = minefield.seed or 1
    local roll = (x * 37 + y * 53 + seed * 7) % 100

    local isChest = (cell and cell.roomType == "chest")
    local gold = 0
    if isChest then
        gold = Balance.RollRange(seed, x, y, 11, Balance.chest.baseMin, Balance.chest.baseMax) + adjacent
        gold = math.min(Balance.chest.goldCap, gold)
    else
        gold = Balance.RollRange(seed, x, y, 7, Balance.search.baseMin, Balance.search.baseMax)
            + math.floor(adjacent / Balance.search.adjacentDivisor)
        gold = math.min(Balance.search.goldCap, gold)
    end
    local items = buildRewardItems(roll, isChest, adjacent)
    local parts = 0
    for _, stack in ipairs(items) do
        parts = parts + stack.count
    end

    if RunInventory.searchBonus > 0 then
        gold = math.floor(gold * (1 + RunInventory.searchBonus / 100))
        gold = math.min(isChest and Balance.chest.goldCap or Balance.search.goldCap, gold)
    end

    return { gold = gold, pendingGold = gold, parts = parts, items = items, isChest = isChest, itemValue = 0 }
end

function RunInventory.GetSearchState(minefield, run)
    if not run or not minefield then
        return { canSearch = false, searched = false, reason = "not_ready" }
    end

    local p = run:GetPlayer()
    local cell = minefield:GetCellView(p.x, p.y)
    local key = cellKey(p.x, p.y)
    local searched = RunInventory.searchedRooms[key] == true

    if not cell or not cell.revealed or cell.mine then
        return { canSearch = false, searched = searched, reason = "unsafe" }
    end
    if cell.spawn then
        return { canSearch = false, searched = searched, reason = "spawn" }
    end
    if cell.exitId then
        return { canSearch = false, searched = searched, reason = "exit" }
    end
    -- 怪物房不可搜索(只能战斗)
    if cell.roomType == "monster" then
        return { canSearch = false, searched = searched, reason = "monster" }
    end
    if cell.roomType == "event" then
        return { canSearch = false, searched = false, reason = "event" }
    end
    if searched then
        return { canSearch = false, searched = true, reason = "searched", isChest = (cell.roomType == "chest") }
    end

    return {
        canSearch = true,
        searched = false,
        isChest = (cell.roomType == "chest"),
        reward = RunInventory.GetReward(minefield, p.x, p.y),
    }
end

function RunInventory.CanSearch(minefield, run)
    return RunInventory.GetSearchState(minefield, run).canSearch == true
end

function RunInventory.SearchCurrentRoom(minefield, run)
    local state = RunInventory.GetSearchState(minefield, run)
    if not state.canSearch then
        return {
            ok = false,
            status = state.reason,
            searched = state.searched,
        }
    end

    local p = run:GetPlayer()
    local key = cellKey(p.x, p.y)
    local reward = state.reward

    RunInventory.searchedRooms[key] = true
    RunInventory.AddPendingGold(reward.pendingGold or reward.gold or 0)
    RunInventory.parts = RunInventory.parts + reward.parts
    reward.itemValue = 0
    for _, stack in ipairs(reward.items or {}) do
        RunInventory.AddCarriedItem(stack.itemId, stack.count, stack.source)
        local def = RunInventory.GetItemDef(stack.itemId)
        reward.itemValue = reward.itemValue + (itemBaseValue(def) * stack.count)
    end
    RunInventory.stats.searchedRooms = RunInventory.stats.searchedRooms + 1
    if reward.isChest then
        RunInventory.stats.chestRooms = RunInventory.stats.chestRooms + 1
    end

    return {
        ok = true,
        status = "searched",
        reward = reward,
        gold = RunInventory.gold,
        pendingGold = RunInventory.pendingGold,
        safeGold = RunInventory.safeGold,
        parts = RunInventory.parts,
        carriedItems = RunInventory.GetCarriedItems(),
    }
end

function RunInventory.GetSearchedCount()
    local count = 0
    for _ in pairs(RunInventory.searchedRooms) do
        count = count + 1
    end
    return count
end

function RunInventory.GetTotals()
    syncGoldAlias()
    return {
        gold = RunInventory.gold,
        pendingGold = RunInventory.pendingGold,
        safeGold = RunInventory.safeGold,
        totalRunGold = RunInventory.pendingGold + RunInventory.safeGold,
        parts = RunInventory.parts,
        looseParts = RunInventory.GetLooseParts(),
        carriedItemCount = RunInventory.GetCarriedItemCount(),
        carriedItemValue = RunInventory.GetCarriedItemValue(),
        carriedItems = RunInventory.GetCarriedItems(),
        consumables = RunInventory.GetConsumables(),
        searchedRooms = RunInventory.GetSearchedCount(),
        failureSalvage = RunInventory.failureSalvage,
    }
end

function RunInventory.GetHUDSummary(context)
    context = context or {}
    local totals = RunInventory.GetTotals()
    local recoveredItems = {}
    for _, stack in ipairs(totals.carriedItems or {}) do
        local item = RunInventory.GetItemDisplayData(stack.itemId)
        table.insert(recoveredItems, {
            iconKey = item.display.iconKey,
            name = item.name,
            count = stack.count or 1,
            text = item.name .. " x" .. (stack.count or 1),
        })
    end

    local consumables = {}
    for itemId, count in pairs(totals.consumables or {}) do
        local item = RunInventory.GetItemDisplayData(itemId)
        table.insert(consumables, {
            iconKey = item.display.iconKey,
            name = item.name,
            count = count,
            text = item.name .. " x" .. count,
        })
    end
    table.sort(consumables, function(a, b) return a.name < b.name end)

    local protocol = context.protocol or {}
    local nearbyMineRisk = context.nearbyMineRisk or 0
    local mineRiskState = context.mineRiskState
    if not mineRiskState then
        if context.mineTriggered then
            mineRiskState = "danger"
        elseif nearbyMineRisk >= 3 then
            mineRiskState = "warning"
        else
            mineRiskState = "normal"
        end
    end

    return {
        pendingCurrency = totals.pendingGold or 0,
        lockedCurrency = totals.safeGold or 0,
        recoveredItems = recoveredItems,
        recoveredItemCount = totals.carriedItemCount or 0,
        consumables = consumables,
        consumableCounts = totals.consumables or {},
        equipmentEffects = context.equipmentEffects or {},
        protocolLevel = protocol.level or 5,
        protocolStatus = protocol.description or "",
        pressure = protocol.pressure or 0,
        pressureMax = protocol.maxPressure or 100,
        nearbyMineRisk = nearbyMineRisk,
        mineRiskState = mineRiskState,
    }
end

function RunInventory.RecordMove()
    RunInventory.stats.moves = RunInventory.stats.moves + 1
end

function RunInventory.RecordMineHit(immuneUsed)
    RunInventory.stats.mineHits = RunInventory.stats.mineHits + 1
    if immuneUsed then
        RunInventory.stats.mineImmunityUsed = RunInventory.stats.mineImmunityUsed + 1
    end
end

function RunInventory.RecordCombat(result)
    if not result or not result.fought then return end
    if result.inventoryRecorded then return end
    result.inventoryRecorded = true
    RunInventory.stats.monstersDefeated = RunInventory.stats.monstersDefeated + 1
    RunInventory.stats.combatDamage = RunInventory.stats.combatDamage + (result.damage or 0)
    if result.reward and not result.dead then
        RunInventory.AddPendingGold(result.reward.pendingGold or result.reward.gold or 0)
        RunInventory.parts = RunInventory.parts + (result.reward.parts or 0)
    end
end

function RunInventory.RecordTrade()
    RunInventory.stats.trades = RunInventory.stats.trades + 1
end

function RunInventory.RecordEvent(eventType)
    RunInventory.stats.eventsCompleted = RunInventory.stats.eventsCompleted + 1
    if eventType == "trader" then
        RunInventory.RecordTrade()
    elseif eventType == "dice" then
        RunInventory.stats.diceEvents = RunInventory.stats.diceEvents + 1
    elseif eventType == "altar" then
        RunInventory.stats.altarEvents = RunInventory.stats.altarEvents + 1
    elseif eventType == "trap" then
        RunInventory.stats.trapEvents = RunInventory.stats.trapEvents + 1
    end
end

function RunInventory.GetRunStats(run)
    return {
        moves = RunInventory.stats.moves,
        searchedRooms = RunInventory.GetSearchedCount(),
        chestRooms = RunInventory.stats.chestRooms,
        mineHits = RunInventory.stats.mineHits,
        mineImmunityUsed = RunInventory.stats.mineImmunityUsed,
        monstersDefeated = RunInventory.stats.monstersDefeated,
        combatDamage = RunInventory.stats.combatDamage,
        trades = RunInventory.stats.trades,
        eventsCompleted = RunInventory.stats.eventsCompleted,
        diceEvents = RunInventory.stats.diceEvents,
        altarEvents = RunInventory.stats.altarEvents,
        trapEvents = RunInventory.stats.trapEvents,
        turns = run and run.turn or 0,
    }
end

--- 撤离成功时的结算:待结算与已锁定收益入账
---@param partsToGoldRate? number 旧兼容参数，当前不再折算零散回收物
---@return table { totalGold: number, convertedGold: number, directGold: number, parts: number }
function RunInventory.GetExtractionReward(partsToGoldRate)
    partsToGoldRate = partsToGoldRate or 10
    local carriedCount = RunInventory.GetCarriedItemCount()
    local carriedValue = RunInventory.GetCarriedItemValue()
    local looseParts = RunInventory.GetLooseParts()
    local loosePartsGold = 0
    local convertedGold = 0
    local totalGold = RunInventory.pendingGold + RunInventory.safeGold
    return {
        totalGold = totalGold,
        convertedGold = convertedGold,
        directGold = totalGold,
        pendingGold = RunInventory.pendingGold,
        safeGold = RunInventory.safeGold,
        parts = RunInventory.parts,
        looseParts = looseParts,
        loosePartsGold = loosePartsGold,
        carriedItemCount = carriedCount,
        carriedItemValue = carriedValue,
        carriedItems = RunInventory.GetCarriedItems(),
        carriedSummary = RunInventory.GetCarriedItemSummary(3),
    }
end

--- 失败抢救条款选项
--- 新机制:待结算失败丢失，已锁定收益保留，回收物按抢救条款处理
function RunInventory.GetFailureSalvageOptions()
    local carriedItemCount = RunInventory.GetCarriedItemCount()
    local carriedItemValue = RunInventory.GetCarriedItemValue()
    local salvagedItem = nil
    local bestValue = -1
    for _, stack in ipairs(RunInventory.GetCarriedItems()) do
        local value = itemBaseValue(stack.def)
        if value > bestValue then
            bestValue = value
            salvagedItem = { itemId = stack.itemId, count = 1, source = stack.source, def = stack.def }
        end
    end
    return {
        safeGold = RunInventory.safeGold,
        pendingGoldLost = RunInventory.pendingGold,
        lostParts = RunInventory.parts,
        lostItemCount = carriedItemCount,
        lostItemValue = carriedItemValue,
        lostItems = RunInventory.GetCarriedItems(),
        salvagedItem = salvagedItem,
        canSalvagePart = false,
        salvageBonus = 0,
        currentGold = RunInventory.pendingGold,
        currentParts = RunInventory.parts,
        carriedItemCount = carriedItemCount,
        carriedItemValue = carriedItemValue,
        searchedRooms = RunInventory.GetSearchedCount(),
    }
end

function RunInventory.ApplyFailureSalvage(choice)
    local options = RunInventory.GetFailureSalvageOptions()
    local salvage = {
        choice = choice,
        gold = options.safeGold,
        pendingGoldLost = options.pendingGoldLost,
        parts = 0,
        bonus = 0,
        salvagedItem = options.salvagedItem,
        carriedItems = options.salvagedItem and { options.salvagedItem } or {},
    }

    RunInventory.failureSalvage = salvage
    return salvage
end

return RunInventory
