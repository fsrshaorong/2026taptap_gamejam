-- ============================================================================
-- RunInventory.lua
-- Tracks one extraction run's loot and searched rooms.
-- ============================================================================

local RunInventory = {}

RunInventory.gold = 0
RunInventory.parts = 0
RunInventory.searchedRooms = {}
RunInventory.carriedItems = {}
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
        value = 24,
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
        value = 30,
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
        typeName = "作业器材",
        rarity = "uncommon",
        rarityName = "少见",
        icon = "assets/items/static_lens.png",
        value = 16,
        effectText = "可作为后续扫描设备材料。",
        description = "透过它看灯光时，会看见不存在的边界线。",
    },
    {
        id = "blackbox_tag",
        name = "黑匣标签",
        type = "record",
        typeName = "记录残片",
        rarity = "uncommon",
        rarityName = "少见",
        icon = "assets/items/blackbox_tag.png",
        value = 18,
        effectText = nil,
        description = "标签上的编号被刮掉了，只剩下回收部门的旧印章。",
    },
}

local ITEM_DEF_LOOKUP = {}
for _, def in ipairs(RunInventory.ITEM_DEFS) do
    ITEM_DEF_LOOKUP[def.id] = def
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
    RunInventory.parts = 0
    RunInventory.searchedRooms = {}
    RunInventory.carriedItems = {}
    RunInventory.failureSalvage = nil
    RunInventory.searchBonus = 0
    RunInventory.stats = newStats()
end

function RunInventory.CellKey(x, y)
    return cellKey(x, y)
end

function RunInventory.GetItemDef(itemId)
    return ITEM_DEF_LOOKUP[itemId]
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
    local ok = false
    if love and love.filesystem and love.filesystem.getInfo then
        ok = love.filesystem.getInfo(def.icon) ~= nil
    else
        local file = io and io.open and io.open(def.icon, "rb") or nil
        if file then
            file:close()
            ok = true
        end
    end
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
        value = value + ((def and def.value or 0) * (stack.count or 0))
    end
    return value
end

function RunInventory.ClearCarriedItems()
    RunInventory.carriedItems = {}
end

function RunInventory.ConvertCarriedItemsToPartsOrGold(partsToGoldRate)
    return RunInventory.GetExtractionReward(partsToGoldRate)
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
            value = stack.def and stack.def.value or 0,
            type = stack.def and stack.def.type or "unknown",
        })
    end
    table.insert(items, {
        id = "parts",
        itemId = "parts",
        name = "异常回收物",
        count = RunInventory.parts,
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
    if itemId == "parts" then return RunInventory.parts end
    local stack = RunInventory.carriedItems[itemId]
    return stack and stack.count or 0
end

function RunInventory.RemoveTradableItem(itemId, count)
    count = math.floor(tonumber(count) or 1)
    if count < 1 then count = 1 end
    if itemId == "parts" then
        if RunInventory.parts < count then return false, "not_enough" end
        RunInventory.parts = RunInventory.parts - count
        return true
    end

    local stack = RunInventory.carriedItems[itemId]
    if not stack or stack.count < count then return false, "not_enough" end
    stack.count = stack.count - count
    if stack.count <= 0 then
        RunInventory.carriedItems[itemId] = nil
    end
    return true
end

local function chooseItemId(roll, isChest, index)
    roll = (roll + index * 17) % 100
    if isChest then
        if roll >= 88 then return "sealed_core_shard" end
        if roll >= 70 then return "whisper_wick" end
        if roll >= 48 then return "static_lens" end
        if roll >= 28 then return "blackbox_tag" end
        return "dim_capacitor"
    end
    if roll >= 96 then return "whisper_wick" end
    if roll >= 82 then return "blackbox_tag" end
    if roll >= 68 then return "static_lens" end
    if roll >= 38 then return "dim_capacitor" end
    return "broken_copper_wire"
end

local function buildRewardItems(roll, isChest)
    local itemCount = 0
    if isChest then
        itemCount = 1 + (roll % 3)
    elseif roll % 100 >= 45 then
        itemCount = 1
    end

    local items = {}
    for i = 1, itemCount do
        local itemId = chooseItemId(roll, isChest, i)
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
    local gold = 4 + adjacent * 2 + (roll % 6)
    local items = buildRewardItems(roll, isChest)
    local parts = 0
    for _, stack in ipairs(items) do
        parts = parts + stack.count
    end

    -- 宝箱房奖励加成:金币翻倍, 必给零件
    if isChest then
        gold = gold * 2 + 16
    end

    -- 搜索奖励加成(大背包装备效果)
    if RunInventory.searchBonus > 0 then
        gold = math.floor(gold * (1 + RunInventory.searchBonus / 100))
    end

    return { gold = gold, parts = parts, items = items, isChest = isChest, itemValue = 0 }
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
    RunInventory.gold = RunInventory.gold + reward.gold
    RunInventory.parts = RunInventory.parts + reward.parts
    reward.itemValue = 0
    for _, stack in ipairs(reward.items or {}) do
        RunInventory.AddCarriedItem(stack.itemId, stack.count, stack.source)
        local def = RunInventory.GetItemDef(stack.itemId)
        reward.itemValue = reward.itemValue + ((def and def.value or 0) * stack.count)
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
    return {
        gold = RunInventory.gold,
        parts = RunInventory.parts,
        carriedItemCount = RunInventory.GetCarriedItemCount(),
        carriedItemValue = RunInventory.GetCarriedItemValue(),
        carriedItems = RunInventory.GetCarriedItems(),
        searchedRooms = RunInventory.GetSearchedCount(),
        failureSalvage = RunInventory.failureSalvage,
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
    RunInventory.stats.monstersDefeated = RunInventory.stats.monstersDefeated + 1
    RunInventory.stats.combatDamage = RunInventory.stats.combatDamage + (result.damage or 0)
    if result.reward and not result.dead then
        RunInventory.gold = RunInventory.gold + (result.reward.gold or 0)
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

--- 撤离成功时的结算:零件按比例转金币
---@param partsToGoldRate? number 每个零件转换的金币数(默认10)
---@return table { totalGold: number, convertedGold: number, directGold: number, parts: number }
function RunInventory.GetExtractionReward(partsToGoldRate)
    partsToGoldRate = partsToGoldRate or 10
    local carriedCount = RunInventory.GetCarriedItemCount()
    local carriedValue = RunInventory.GetCarriedItemValue()
    local looseParts = RunInventory.parts - carriedCount
    if looseParts < 0 then looseParts = 0 end
    local loosePartsGold = looseParts * partsToGoldRate
    local convertedGold = carriedValue + loosePartsGold
    return {
        totalGold = RunInventory.gold + convertedGold,
        convertedGold = convertedGold,
        directGold = RunInventory.gold,
        parts = RunInventory.parts,
        looseParts = looseParts,
        loosePartsGold = loosePartsGold,
        carriedItemCount = carriedCount,
        carriedItemValue = carriedValue,
        carriedItems = RunInventory.GetCarriedItems(),
        carriedSummary = RunInventory.GetCarriedItemSummary(3),
    }
end

--- 失败保底选项
--- 新机制:金币自动保留(安全资产), 零件全部丢失(风险资产)
--- 保底选择:是否用1个零件换取额外金币(10g)
function RunInventory.GetFailureSalvageOptions()
    local PARTS_SALVAGE_RATE = 10  -- 保底抢救1零件=10金币
    local canSalvagePart = RunInventory.parts >= 1
    local carriedItemCount = RunInventory.GetCarriedItemCount()
    local carriedItemValue = RunInventory.GetCarriedItemValue()
    return {
        safeGold = RunInventory.gold,       -- 自动保留的金币
        lostParts = RunInventory.parts,     -- 将丢失的零件数
        lostItemCount = carriedItemCount,
        lostItemValue = carriedItemValue,
        lostItems = RunInventory.GetCarriedItems(),
        canSalvagePart = canSalvagePart,    -- 是否有零件可抢救
        salvageBonus = canSalvagePart and PARTS_SALVAGE_RATE or 0,  -- 抢救1零件得到的金币
        currentGold = RunInventory.gold,
        currentParts = RunInventory.parts,
        carriedItemCount = carriedItemCount,
        carriedItemValue = carriedItemValue,
        searchedRooms = RunInventory.GetSearchedCount(),
    }
end

--- 应用保底
---@param choice string "salvage_part"=抢救1零件换金币, "accept"=直接接受结果
function RunInventory.ApplyFailureSalvage(choice)
    local options = RunInventory.GetFailureSalvageOptions()
    local salvage = {
        choice = choice,
        gold = options.safeGold,   -- 金币始终保留
        parts = 0,                  -- 零件全部丢失
        bonus = 0,
    }

    if choice == "salvage_part" and options.canSalvagePart then
        salvage.bonus = options.salvageBonus
        salvage.gold = salvage.gold + options.salvageBonus
    end

    RunInventory.failureSalvage = salvage
    return salvage
end

return RunInventory
