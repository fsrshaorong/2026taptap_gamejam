-- ============================================================================
-- MetaProgress.lua — 局外持久化进度管理
-- 管理:全局结算币,已登记回收资历,已申领/装备的带入物品,统计数据
-- ============================================================================

local Balance = require("systems.Balance")

local MetaProgress = {}

-- ============================================================================
-- 物品定义
-- ============================================================================

---@class MetaItem
---@field id string
---@field name string
---@field desc string
---@field price number
---@field category string "数值"|"机制"
---@field icon string 显示用 emoji/符号

MetaProgress.ITEMS = {
    {
        id = "armor",
        name = "防护甲",
        desc = "+25 最大血量",
        price = Balance.shop.armor.price,
        category = "数值",
        icon = "[DEF]",
    },
    {
        id = "whetstone",
        name = "磨刀石",
        desc = "+5 战斗力",
        price = Balance.shop.whetstone.price,
        category = "数值",
        icon = "[ATK]",
    },
    {
        id = "medkit",
        name = "急救包",
        desc = "首次踩雷免疫伤害",
        price = Balance.shop.medkit.price,
        category = "机制",
        icon = "[MED]",
    },
    {
        id = "compass",
        name = "罗盘",
        desc = "开局显示撤离信标所在象限",
        price = Balance.shop.compass.price,
        category = "机制",
        icon = "[NAV]",
    },
    {
        id = "backpack",
        name = "大背包",
        desc = "搜索奖励 +50%",
        price = Balance.shop.backpack.price,
        category = "数值",
        icon = "[BAG]",
    },
}

table.insert(MetaProgress.ITEMS, {
    id = "insulated_gloves",
    name = "绝缘套",
    desc = "雷险伤害 -10",
    price = Balance.shop.insulated_gloves.price,
    category = "机制",
    icon = "[ISO]",
})

local ITEM_BALANCE_TEXT = {
    armor = { name = "防护背心", desc = "最大生命 +20。不是保险，只是布料厚一点。", price = Balance.shop.armor.price },
    whetstone = { name = "磨刀石", desc = "初始战斗力 +2。后勤称这属于基础安全措施。", price = Balance.shop.whetstone.price },
    medkit = { name = "急救包", desc = "出发携带急救物资。后勤提醒：不是装饰品。", price = Balance.shop.medkit.price },
    insulated_gloves = { name = "绝缘套", desc = "雷险伤害 -10。不能保证安全，只能保证好看一点。", price = Balance.shop.insulated_gloves.price },
    compass = { name = "罗盘", desc = "显示撤离信标方向提示。它偶尔也会表达意见。", price = Balance.shop.compass.price },
    backpack = { name = "大背包", desc = "回收包容量 +2。拿得更多，不代表跑得更快。", price = Balance.shop.backpack.price },
}

for _, item in ipairs(MetaProgress.ITEMS) do
    local tuned = ITEM_BALANCE_TEXT[item.id]
    if tuned then
        item.name = tuned.name
        item.desc = tuned.desc
        item.price = tuned.price
    end
end

MetaProgress.CONSUMABLES = {
    {
        id = "emergency_bandage",
        name = "应急止血贴",
        desc = "局内使用: 恢复 25 生命",
        price = 12,
        type = "consumable",
        typeName = "作业消耗品",
        rarity = "common",
        rarityName = "一般",
        icon = "[BND]",
        value = 10,
        effectText = "恢复 25 生命。本轮未使用不返还。",
        description = "后勤部标准急救贴, 适合在撤离前多撑一口气。",
        maxCarry = 3,
        effects = { heal = 25 },
    },
}

-- ============================================================================
-- 天赋定义
-- ============================================================================

---@class MetaTalent
---@field id string
---@field direction string
---@field name string
---@field desc string
---@field price number

MetaProgress.TALENTS = {
    {
        id = "talent_map",
        direction = "区域扫描图",
        name = "邻域感知",
        desc = "进入房间时高亮 8 邻域",
        price = Balance.talents.talent_map,
    },
    {
        id = "talent_mine",
        direction = "雷险区",
        name = "厚皮",
        desc = "雷伤降低 10 点",
        price = Balance.talents.talent_mine,
    },
    {
        id = "talent_monster",
        direction = "异常体",
        name = "威压",
        desc = "异常体避让窗口 +2 秒",
        price = Balance.talents.talent_monster,
    },
    {
        id = "talent_extract",
        direction = "撤离",
        name = "抢救条款",
        desc = "信号中断时抢救条款额外保留 +10 结算币",
        price = Balance.talents.talent_extract,
    },
    {
        id = "talent_event",
        direction = "事件",
        name = "议价",
        desc = "旅商折价率改善",
        price = Balance.talents.talent_event,
    },
}

-- ============================================================================
-- 内部状态
-- ============================================================================

local SAVE_FILE = "meta_save.json"
local MAX_EQUIPPED = 2
local RECENT_RECOVERY_MAX = 5

local function newRecovery()
    return {
        totalItems = 0,
        totalValue = 0,
        totalExtractionsWithItems = 0,
        recentItems = {},
    }
end

local function newWarehouse()
    return {
        items = {},
    }
end

local function newConsumables()
    return {}
end

local function newLoadout()
    return {
        consumables = {},
    }
end

-- 运行时数据
local data = {
    gold = 0,
    unlockedTalents = {},   -- { [talentId] = true }
    ownedItems = {},        -- { [itemId] = true }
    equippedItems = {},     -- { itemId, ... } 最多 MAX_EQUIPPED 个
    stats = {
        totalRuns = 0,
        totalExtractions = 0,
        totalGoldEarned = 0,
    },
    recovery = newRecovery(),
    warehouse = newWarehouse(),
    consumables = newConsumables(),
    loadout = newLoadout(),
}

local function toNonNegativeNumber(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    return math.floor(value)
end

local function getConsumableDef(itemId)
    for _, item in ipairs(MetaProgress.CONSUMABLES) do
        if item.id == itemId then return item end
    end
    return nil
end

local function copyCountMap(map)
    local copied = {}
    for id, count in pairs(map or {}) do
        count = toNonNegativeNumber(count)
        if count > 0 then
            copied[id] = count
        end
    end
    return copied
end

local function copyRecoveryItem(item)
    item = item or {}
    return {
        id = item.id or item.itemId or "",
        name = item.name or item.itemId or item.id or "",
        rarityName = item.rarityName or "",
        value = toNonNegativeNumber(item.value),
    }
end

local DISPLAY_ICON_KEYS = {
    armor = "item.equipment.armor",
    whetstone = "item.equipment.whetstone",
    medkit = "item.equipment.medkit",
    compass = "item.equipment.compass",
    backpack = "item.equipment.backpack",
    insulated_gloves = "item.equipment.insulated_gloves",
    emergency_bandage = "item.consumable.emergency_bandage",
}

local DISPLAY_DEFAULT_ICON_KEYS = {
    equipment = "item.equipment.default",
    consumable = "item.consumable.default",
    recovered = "item.recovered.default",
    relic = "item.recovered.default",
    tool = "item.recovered.default",
    record = "item.recovered.default",
    talent = "item.talent.default",
}

local function getDisplayCategory(item)
    local category = item.category
    if category and category ~= "" and category ~= "数值" and category ~= "机制" then
        return category
    end
    if item.source == "recovered" or item.type == "relic" or item.type == "tool" or item.type == "record" then
        return "recovered"
    end
    if item.type == "equipment" or item.type == "consumable" or item.type == "talent" then
        return item.type
    end
    return "other"
end

local function getDisplayIconKey(item)
    return item.iconKey
        or DISPLAY_ICON_KEYS[item.id]
        or DISPLAY_DEFAULT_ICON_KEYS[getDisplayCategory(item)]
        or DISPLAY_DEFAULT_ICON_KEYS[item.type]
        or "item.placeholder"
end

local function refreshDisplayAdapter(item)
    local value = toNonNegativeNumber(item.baseValue or item.value)
    local price = toNonNegativeNumber(item.price)
    local category = getDisplayCategory(item)
    item.category = category
    item.kind = item.kind or item.type or "unknown"
    item.branch = item.branch or category
    item.iconKey = getDisplayIconKey(item)
    item.display = {
        iconKey = item.iconKey,
        category = category,
        rarity = item.rarity or "common",
        typeLabel = item.typeName or "物品",
        rarityLabel = item.rarityName or "一般",
        shortEffect = item.effectText or "",
        shortDescription = item.description or item.desc or "",
        valueText = value > 0 and tostring(value) or "",
        priceText = price > 0 and (tostring(price) .. " 结算币") or "",
        statusText = item.statusText or "",
        primaryAction = item.primaryAction,
        secondaryAction = item.secondaryAction,
        disabledReason = item.disabledReason,
    }
    return item
end

local function copyDisplayData(item)
    item = item or {}
    local copied = {
        id = item.id or item.itemId or "",
        name = item.name or item.id or item.itemId or "",
        type = item.type or "unknown",
        typeName = item.typeName or "物品",
        category = item.category,
        branch = item.branch,
        kind = item.kind,
        rarity = item.rarity or "common",
        rarityName = item.rarityName or "一般",
        icon = item.icon or "",
        iconKey = item.iconKey,
        value = toNonNegativeNumber(item.baseValue or item.value),
        baseValue = toNonNegativeNumber(item.baseValue or item.value),
        price = toNonNegativeNumber(item.price),
        effectText = item.effectText,
        description = item.description or item.desc or "",
        source = item.source or "unknown",
        unique = item.unique == true,
        count = item.count,
        canSell = item.canSell == true,
        canBuy = item.canBuy == true,
        canEquip = item.canEquip == true,
        canUse = item.canUse == true,
        isEquipped = item.isEquipped == true,
        loadoutCount = toNonNegativeNumber(item.loadoutCount),
        owned = item.owned == true,
        statusText = item.statusText,
        primaryAction = item.primaryAction,
        secondaryAction = item.secondaryAction,
        disabledReason = item.disabledReason,
    }
    return refreshDisplayAdapter(copied)
end

local function displayFromMetaItem(item)
    if not item then return nil end
    return copyDisplayData({
        id = item.id,
        name = item.name,
        type = item.type or "equipment",
        typeName = item.typeName or "作业装备",
        category = "equipment",
        branch = item.category or "其它",
        rarity = item.rarity or "logistics",
        rarityName = item.rarityName or "后勤",
        icon = item.icon or "[EQP]",
        iconKey = item.iconKey,
        value = item.value or item.price or 0,
        price = item.price or item.value or 0,
        effectText = item.effectText or item.desc,
        description = item.description or item.desc,
        source = item.source or "equipment",
        unique = item.unique ~= false,
    })
end

local function displayFromConsumable(item)
    if not item then return nil end
    return copyDisplayData({
        id = item.id,
        name = item.name,
        type = "consumable",
        typeName = item.typeName or "作业消耗品",
        category = "consumable",
        rarity = item.rarity or "common",
        rarityName = item.rarityName or "一般",
        icon = item.icon or "[USE]",
        iconKey = item.iconKey,
        value = item.value or 0,
        price = item.price or item.value or 0,
        effectText = item.effectText or item.desc,
        description = item.description or item.desc,
        source = item.source or "consumable",
        unique = false,
    })
end

local function displayFromStack(stack, source)
    stack = stack or {}
    local def = stack.def or stack
    return copyDisplayData({
        id = stack.itemId or stack.id or def.id,
        name = def.name or stack.name or stack.itemId or stack.id,
        type = def.type or stack.type or "relic",
        typeName = def.typeName or stack.typeName or "异常回收物",
        category = "recovered",
        rarity = def.rarity or stack.rarity or "common",
        rarityName = def.rarityName or stack.rarityName or "一般",
        icon = def.icon or stack.icon or "",
        iconKey = def.iconKey or stack.iconKey,
        value = def.baseValue or def.value or stack.baseValue or stack.value or 0,
        baseValue = def.baseValue or def.value or stack.baseValue or stack.value or 0,
        price = def.price or stack.price or 0,
        effectText = def.effectText or stack.effectText,
        description = def.description or stack.description or "",
        source = source or stack.source or "recovered",
        unique = def.unique == true or stack.unique == true,
    })
end

local function trimRecentItems(items)
    local trimmed = {}
    if items then
        for _, item in ipairs(items) do
            if #trimmed >= RECENT_RECOVERY_MAX then break end
            table.insert(trimmed, copyRecoveryItem(item))
        end
    end
    return trimmed
end

local function normalizeWarehouseItem(item)
    item = copyDisplayData(item)
    item.count = toNonNegativeNumber(item.count)
    if item.count <= 0 then
        return nil
    end
    if item.source == "" or item.source == "unknown" then
        item.source = "recovered"
    end
    return item
end

local function normalizeWarehouse(savedWarehouse)
    local normalized = newWarehouse()
    savedWarehouse = savedWarehouse or {}
    for id, item in pairs(savedWarehouse.items or {}) do
        local normalizedItem = normalizeWarehouseItem(item)
        if normalizedItem then
            normalizedItem.id = normalizedItem.id ~= "" and normalizedItem.id or id
            normalized.items[normalizedItem.id] = normalizedItem
        end
    end
    return normalized
end

local function normalizeConsumables(savedConsumables)
    return copyCountMap(savedConsumables)
end

local function normalizeLoadout(savedLoadout)
    local normalized = newLoadout()
    savedLoadout = savedLoadout or {}
    normalized.consumables = copyCountMap(savedLoadout.consumables)
    for itemId, count in pairs(normalized.consumables) do
        local stock = data.consumables and data.consumables[itemId] or count
        if count > stock then
            normalized.consumables[itemId] = stock
        end
        if not getConsumableDef(itemId) or normalized.consumables[itemId] <= 0 then
            normalized.consumables[itemId] = nil
        end
    end
    return normalized
end

local function normalizeRecovery(savedRecovery)
    savedRecovery = savedRecovery or {}
    return {
        totalItems = toNonNegativeNumber(savedRecovery.totalItems),
        totalValue = toNonNegativeNumber(savedRecovery.totalValue),
        totalExtractionsWithItems = toNonNegativeNumber(savedRecovery.totalExtractionsWithItems),
        recentItems = trimRecentItems(savedRecovery.recentItems),
    }
end

local function pushRecentRecoveryItems(items)
    for _, stack in ipairs(items or {}) do
        local def = stack.def or {}
        local count = math.floor(tonumber(stack.count) or 1)
        if count < 1 then count = 1 end
        for _ = 1, count do
            table.insert(data.recovery.recentItems, 1, {
                id = stack.itemId or stack.id or "",
                name = def.name or stack.name or stack.itemId or stack.id or "",
                rarityName = def.rarityName or stack.rarityName or "",
                value = toNonNegativeNumber(def.value or stack.value),
            })
        end
    end
    data.recovery.recentItems = trimRecentItems(data.recovery.recentItems)
end

-- ============================================================================
-- 存档读写
-- ============================================================================

--- 加载存档
function MetaProgress.Load()
    if fileSystem:FileExists(SAVE_FILE) then
        local file = File(SAVE_FILE, FILE_READ)
        if file:IsOpen() then
            local ok, saved = pcall(cjson.decode, file:ReadString())
            file:Close()
            if ok and saved then
                data.gold = toNonNegativeNumber(saved.gold)
                -- 天赋
                data.unlockedTalents = {}
                if saved.unlockedTalents then
                    for _, id in ipairs(saved.unlockedTalents) do
                        data.unlockedTalents[id] = true
                    end
                end
                -- 物品
                data.ownedItems = {}
                if saved.ownedItems then
                    for _, id in ipairs(saved.ownedItems) do
                        data.ownedItems[id] = true
                    end
                end
                -- 装备
                data.equippedItems = saved.equippedItems or {}
                -- 验证装备的物品确实拥有
                local valid = {}
                for _, id in ipairs(data.equippedItems) do
                    if data.ownedItems[id] then
                        table.insert(valid, id)
                    end
                end
                data.equippedItems = valid
                -- 统计
                data.stats = { totalRuns = 0, totalExtractions = 0, totalGoldEarned = 0 }
                if saved.stats then
                    data.stats.totalRuns = toNonNegativeNumber(saved.stats.totalRuns)
                    data.stats.totalExtractions = toNonNegativeNumber(saved.stats.totalExtractions)
                    data.stats.totalGoldEarned = toNonNegativeNumber(saved.stats.totalGoldEarned)
                end
                data.recovery = normalizeRecovery(saved.recovery)
                data.warehouse = normalizeWarehouse(saved.warehouse)
                data.consumables = normalizeConsumables(saved.consumables)
                data.loadout = normalizeLoadout(saved.loadout)
                print("[MetaProgress] Loaded: gold=" .. data.gold)
            end
        end
    else
        print("[MetaProgress] No save file, starting fresh")
    end
end

--- 保存存档
function MetaProgress.Save()
    -- 转换 set -> array 存储
    local talentList = {}
    for id, _ in pairs(data.unlockedTalents) do
        table.insert(talentList, id)
    end
    local itemList = {}
    for id, _ in pairs(data.ownedItems) do
        table.insert(itemList, id)
    end

    local saveData = {
        gold = data.gold,
        unlockedTalents = talentList,
        ownedItems = itemList,
        equippedItems = data.equippedItems,
        stats = data.stats,
        recovery = data.recovery,
        warehouse = data.warehouse,
        consumables = data.consumables,
        loadout = data.loadout,
    }

    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(saveData))
        file:Close()
        print("[MetaProgress] Saved: gold=" .. data.gold)
    end
end

-- ============================================================================
-- 结算币操作
-- ============================================================================

--- 获取当前结算币
---@return number
function MetaProgress.GetGold()
    return data.gold
end

--- 增加结算币(局结算时调用)
---@param amount number
function MetaProgress.AddGold(amount)
    amount = toNonNegativeNumber(amount)
    if amount <= 0 then return end
    data.gold = data.gold + amount
    data.stats.totalGoldEarned = data.stats.totalGoldEarned + amount
    MetaProgress.Save()
end

--- 消费结算币(申领物品/登记资历时调用)
---@param amount number
---@return boolean 是否成功
function MetaProgress.SpendGold(amount)
    amount = toNonNegativeNumber(amount)
    if amount <= 0 then return false end
    if data.gold < amount then return false end
    data.gold = data.gold - amount
    MetaProgress.Save()
    return true
end

-- ============================================================================
-- 物品操作
-- ============================================================================

--- 是否已拥有物品
---@param itemId string
---@return boolean
function MetaProgress.OwnsItem(itemId)
    return data.ownedItems[itemId] == true
end

--- 购买物品
---@param itemId string
---@return boolean success
---@return string? error
function MetaProgress.BuyItem(itemId)
    if data.ownedItems[itemId] then
        return false, "已拥有"
    end
    local item = MetaProgress.GetItemDef(itemId)
    if not item then
        return false, "物品不存在"
    end
    if data.gold < item.price then
        return false, "结算币不足"
    end
    data.gold = data.gold - item.price
    data.ownedItems[itemId] = true
    MetaProgress.Save()
    return true, nil
end

--- 装备/卸下物品
---@param itemId string
---@return boolean success
---@return string? error
function MetaProgress.ToggleEquip(itemId)
    if not data.ownedItems[itemId] then
        return false, "未拥有"
    end
    -- 检查是否已装备
    for i, id in ipairs(data.equippedItems) do
        if id == itemId then
            table.remove(data.equippedItems, i)
            MetaProgress.Save()
            return true, nil
        end
    end
    -- 未装备, 尝试装备
    if #data.equippedItems >= MAX_EQUIPPED then
        return false, "最多携带作业装备 " .. MAX_EQUIPPED .. " 件"
    end
    table.insert(data.equippedItems, itemId)
    MetaProgress.Save()
    return true, nil
end

--- 是否已装备
---@param itemId string
---@return boolean
function MetaProgress.IsEquipped(itemId)
    for _, id in ipairs(data.equippedItems) do
        if id == itemId then return true end
    end
    return false
end

--- 获取当前装备列表
---@return string[]
function MetaProgress.GetEquippedItems()
    return data.equippedItems
end

--- 获取物品定义
---@param itemId string
---@return MetaItem?
function MetaProgress.GetItemDef(itemId)
    for _, item in ipairs(MetaProgress.ITEMS) do
        if item.id == itemId then return item end
    end
    return nil
end

function MetaProgress.GetConsumableDef(itemId)
    return getConsumableDef(itemId)
end

function MetaProgress.GetItemDisplayData(itemId)
    return MetaProgress.GetUnifiedItemDisplayData(itemId)
end

function MetaProgress.GetShopItemDisplayData(itemId)
    return MetaProgress.GetUnifiedItemDisplayData(itemId, "shop")
end

function MetaProgress.GetDisplayAdapter(item)
    return refreshDisplayAdapter(item or {})
end

function MetaProgress.GetTalentDisplayData(talentId)
    local talent = MetaProgress.GetTalentDef(talentId)
    if not talent then return nil end
    local branch = "event"
    if talent.id == "talent_map" then
        branch = "explore"
    elseif talent.id == "talent_mine" or talent.id == "talent_monster" then
        branch = "survival"
    elseif talent.id == "talent_extract" then
        branch = "profit"
    end
    return copyDisplayData({
        id = talent.id,
        name = talent.name,
        type = "talent",
        typeName = "回收资历",
        category = "talent",
        branch = branch,
        rarity = "common",
        rarityName = "一般",
        iconKey = "item.talent.default",
        value = talent.price,
        price = talent.price,
        effectText = talent.desc,
        description = MetaProgress.HasTalent(talent.id) and "当前效果已生效" or "解锁后在正式局生效",
        statusText = MetaProgress.HasTalent(talent.id) and "已解锁" or ("解锁费用 " .. talent.price .. " 结算币"),
    })
end

function MetaProgress.GetOwnedCount(itemId, source)
    data.warehouse = normalizeWarehouse(data.warehouse)
    data.consumables = normalizeConsumables(data.consumables)
    if source == "warehouse" or source == "recovered" then
        return MetaProgress.GetWarehouseItemCount(itemId)
    end
    if source == "consumable" then
        return data.consumables[itemId] or 0
    end
    if source == "equipment" then
        return MetaProgress.OwnsItem(itemId) and 1 or 0
    end
    return (data.consumables[itemId] or 0) + MetaProgress.GetWarehouseItemCount(itemId) + (MetaProgress.OwnsItem(itemId) and 1 or 0)
end

function MetaProgress.GetUnifiedItemDisplayData(itemId, source)
    data.warehouse = normalizeWarehouse(data.warehouse)
    data.consumables = normalizeConsumables(data.consumables)
    data.loadout = normalizeLoadout(data.loadout)

    local display = nil
    local warehouseItem = data.warehouse.items[itemId]
    if source == "equipment" then
        display = displayFromMetaItem(MetaProgress.GetItemDef(itemId))
    elseif source == "consumable" then
        display = displayFromConsumable(getConsumableDef(itemId))
    elseif source == "warehouse" or source == "recovered" then
        display = warehouseItem and copyDisplayData(warehouseItem) or nil
    elseif source == "shop" then
        display = displayFromMetaItem(MetaProgress.GetItemDef(itemId)) or displayFromConsumable(getConsumableDef(itemId))
    else
        display = (warehouseItem and copyDisplayData(warehouseItem))
            or displayFromMetaItem(MetaProgress.GetItemDef(itemId))
            or displayFromConsumable(getConsumableDef(itemId))
    end

    if not display then
        display = copyDisplayData({
            id = itemId,
            name = "未知物品",
            type = "unknown",
            typeName = "未知",
            source = source or "unknown",
        })
    end

    display.count = MetaProgress.GetOwnedCount(display.id, display.source)
    if display.source == "warehouse" or display.source == "recovered" then
        display.count = MetaProgress.GetWarehouseItemCount(display.id)
    elseif display.type == "consumable" then
        display.count = data.consumables[display.id] or 0
    elseif display.type == "equipment" then
        display.count = MetaProgress.OwnsItem(display.id) and 1 or 0
    end
    display.totalValue = (display.count or 0) * (display.value or 0)
    display.isEquipped = MetaProgress.IsEquipped(display.id)
    display.owned = MetaProgress.OwnsItem(display.id) or (display.type == "consumable" and (data.consumables[display.id] or 0) > 0)
    display.loadoutCount = data.loadout.consumables[display.id] or 0
    display.canSell = MetaProgress.CanSellItem(display.id)
    display.canEquip = display.type == "equipment" and MetaProgress.OwnsItem(display.id)
    display.canBuy = (display.type == "equipment" and not MetaProgress.OwnsItem(display.id))
        or (display.type == "consumable" and getConsumableDef(display.id) ~= nil)
    display.canUse = display.type == "consumable" and (display.count or 0) > 0
    if display.isEquipped then
        display.statusText = "已装备"
    elseif (display.loadoutCount or 0) > 0 then
        display.statusText = "已带入 x" .. display.loadoutCount
    elseif display.owned then
        display.statusText = "已拥有"
    end
    return refreshDisplayAdapter(display)
end

function MetaProgress.CanSellItem(itemId)
    data.warehouse = normalizeWarehouse(data.warehouse)
    local item = data.warehouse.items[itemId]
    if not item or item.count <= 0 then return false, "not_owned" end
    if item.unique then return false, "unique" end
    if item.source ~= "recovered" then return false, "not_sellable" end
    if item.type == "equipment" or item.type == "consumable" then return false, "protected_type" end
    if MetaProgress.IsEquipped(itemId) then return false, "equipped" end
    if item.value <= 0 then return false, "no_value" end
    return true, nil
end

function MetaProgress.CanEquipItem(itemId)
    local item = MetaProgress.GetItemDef(itemId)
    if not item then return false, "not_equipment" end
    if not MetaProgress.OwnsItem(itemId) then return false, "not_owned" end
    return true, nil
end

function MetaProgress.CanUseItem(itemId)
    local display = MetaProgress.GetUnifiedItemDisplayData(itemId)
    if display.type ~= "consumable" then return false, "not_consumable" end
    if (display.count or 0) <= 0 then return false, "not_owned" end
    return true, nil
end

function MetaProgress.GetUsableItems()
    return {}
end

function MetaProgress.UseItem(itemId)
    return false, "not_implemented"
end

function MetaProgress.GetConsumableCount(itemId)
    data.consumables = normalizeConsumables(data.consumables)
    return data.consumables[itemId] or 0
end

function MetaProgress.AddConsumable(itemId, count)
    local def = getConsumableDef(itemId)
    if not def then return false, "unknown_consumable" end
    count = toNonNegativeNumber(count or 1)
    if count <= 0 then return false, "invalid_count" end
    data.consumables = normalizeConsumables(data.consumables)
    data.consumables[itemId] = (data.consumables[itemId] or 0) + count
    MetaProgress.Save()
    return true, { itemId = itemId, count = count, total = data.consumables[itemId] }
end

function MetaProgress.RemoveConsumable(itemId, count)
    count = toNonNegativeNumber(count or 1)
    if count <= 0 then return false, "invalid_count" end
    data.consumables = normalizeConsumables(data.consumables)
    local current = data.consumables[itemId] or 0
    if current < count then return false, "not_enough" end
    data.consumables[itemId] = current - count
    if data.consumables[itemId] <= 0 then
        data.consumables[itemId] = nil
    end
    if data.loadout and data.loadout.consumables then
        local loadoutCount = data.loadout.consumables[itemId] or 0
        if loadoutCount > (data.consumables[itemId] or 0) then
            data.loadout.consumables[itemId] = data.consumables[itemId]
        end
    end
    MetaProgress.Save()
    return true, { itemId = itemId, count = count, total = data.consumables[itemId] or 0 }
end

function MetaProgress.BuyConsumable(itemId, count)
    local def = getConsumableDef(itemId)
    if not def then return false, "unknown_consumable" end
    count = toNonNegativeNumber(count or 1)
    if count <= 0 then return false, "invalid_count" end
    local price = toNonNegativeNumber(def.price) * count
    if data.gold < price then return false, "结算币不足" end
    data.gold = data.gold - price
    data.consumables = normalizeConsumables(data.consumables)
    data.consumables[itemId] = (data.consumables[itemId] or 0) + count
    MetaProgress.Save()
    return true, { itemId = itemId, count = count, total = data.consumables[itemId], cost = price }
end

function MetaProgress.SetLoadoutConsumable(itemId, count)
    local def = getConsumableDef(itemId)
    if not def then return false, "unknown_consumable" end
    data.consumables = normalizeConsumables(data.consumables)
    data.loadout = normalizeLoadout(data.loadout)
    count = toNonNegativeNumber(count)
    local stock = data.consumables[itemId] or 0
    local maxCarry = toNonNegativeNumber(def.maxCarry)
    if maxCarry > 0 and count > maxCarry then count = maxCarry end
    local clamped = false
    if count > stock then
        count = stock
        clamped = true
    end
    if count <= 0 then
        data.loadout.consumables[itemId] = nil
    else
        data.loadout.consumables[itemId] = count
    end
    MetaProgress.Save()
    return true, { itemId = itemId, count = count, stock = stock, clamped = clamped }
end

function MetaProgress.GetLoadout()
    data.loadout = normalizeLoadout(data.loadout)
    return {
        consumables = copyCountMap(data.loadout.consumables),
    }
end

function MetaProgress.ValidateLoadout()
    data.loadout = normalizeLoadout(data.loadout)
    return true, MetaProgress.GetLoadout()
end

function MetaProgress.ConsumeLoadoutForRun()
    data.consumables = normalizeConsumables(data.consumables)
    data.loadout = normalizeLoadout(data.loadout)
    local runLoadout = { consumables = {} }
    for itemId, count in pairs(data.loadout.consumables) do
        local stock = data.consumables[itemId] or 0
        local take = math.min(count, stock)
        if take > 0 then
            runLoadout.consumables[itemId] = take
            data.consumables[itemId] = stock - take
            if data.consumables[itemId] <= 0 then
                data.consumables[itemId] = nil
            end
        end
    end
    data.loadout = normalizeLoadout(data.loadout)
    MetaProgress.Save()
    return true, runLoadout
end

function MetaProgress.GetWarehouseItemDisplayData(itemId)
    data.warehouse = normalizeWarehouse(data.warehouse)
    local item = data.warehouse.items[itemId]
    if not item then return nil end
    local display = copyDisplayData(item)
    display.count = item.count
    display.totalValue = item.count * display.value
    display.canSell = MetaProgress.CanSellItem(itemId)
    display.canEquip = MetaProgress.CanEquipItem(itemId)
    display.canUse = MetaProgress.CanUseItem(itemId)
    return refreshDisplayAdapter(display)
end

-- ============================================================================
-- 天赋操作
-- ============================================================================

--- 是否已解锁天赋
---@param talentId string
---@return boolean
function MetaProgress.HasTalent(talentId)
    return data.unlockedTalents[talentId] == true
end

--- 解锁天赋
---@param talentId string
---@return boolean success
---@return string? error
function MetaProgress.UnlockTalent(talentId)
    if data.unlockedTalents[talentId] then
        return false, "已解锁"
    end
    local talent = MetaProgress.GetTalentDef(talentId)
    if not talent then
        return false, "回收资历不存在"
    end
    if data.gold < talent.price then
        return false, "结算币不足"
    end
    data.gold = data.gold - talent.price
    data.unlockedTalents[talentId] = true
    MetaProgress.Save()
    return true, nil
end

--- 获取天赋定义
---@param talentId string
---@return MetaTalent?
function MetaProgress.GetTalentDef(talentId)
    for _, t in ipairs(MetaProgress.TALENTS) do
        if t.id == talentId then return t end
    end
    return nil
end

-- ============================================================================
-- 统计
-- ============================================================================

--- 记录一次出击
function MetaProgress.RecordRun()
    data.stats.totalRuns = data.stats.totalRuns + 1
    MetaProgress.Save()
end

--- 记录一次成功撤离
function MetaProgress.RecordExtraction()
    data.stats.totalExtractions = data.stats.totalExtractions + 1
    MetaProgress.Save()
end

--- 获取统计数据
function MetaProgress.GetStats()
    return data.stats
end

function MetaProgress.GetRecoverySummary()
    data.recovery = normalizeRecovery(data.recovery)
    return {
        totalItems = data.recovery.totalItems,
        totalValue = data.recovery.totalValue,
        totalExtractionsWithItems = data.recovery.totalExtractionsWithItems,
        recentItems = trimRecentItems(data.recovery.recentItems),
    }
end

function MetaProgress.GetRecoverySummaryText(maxItems)
    local recovery = MetaProgress.GetRecoverySummary()
    maxItems = maxItems or RECENT_RECOVERY_MAX
    local names = {}
    for i, item in ipairs(recovery.recentItems) do
        if i > maxItems then break end
        table.insert(names, item.name or item.id or "")
    end
    if #names == 0 then
        return "最近带回: 无"
    end
    return "最近带回: " .. table.concat(names, " / ")
end

function MetaProgress.AddWarehouseItems(items, source)
    data.warehouse = normalizeWarehouse(data.warehouse)
    local addedCount = 0
    local addedValue = 0
    for _, stack in ipairs(items or {}) do
        local count = toNonNegativeNumber(stack.count or 1)
        if count > 0 then
            local display = displayFromStack(stack, source or "recovered")
            local itemId = display.id
            if itemId and itemId ~= "" then
                local existing = data.warehouse.items[itemId]
                if not existing then
                    existing = copyDisplayData(display)
                    existing.count = 0
                    data.warehouse.items[itemId] = existing
                end
                existing.count = toNonNegativeNumber(existing.count) + count
                existing.source = existing.source or display.source
                addedCount = addedCount + count
                addedValue = addedValue + display.value * count
            end
        end
    end
    return { count = addedCount, value = addedValue }
end

function MetaProgress.GetWarehouseItems(filter)
    data.warehouse = normalizeWarehouse(data.warehouse)
    local list = {}
    for _, item in pairs(data.warehouse.items) do
        if not filter or not filter.source or item.source == filter.source then
            table.insert(list, MetaProgress.GetWarehouseItemDisplayData(item.id))
        end
    end
    table.sort(list, function(a, b)
        return (a.name or a.id) < (b.name or b.id)
    end)
    return list
end

function MetaProgress.GetWarehouseDisplayList(filter)
    if not filter or not filter.category then
        return MetaProgress.GetWarehouseItems(filter)
    end

    local category = filter.category
    local list = {}
    if category == "all" or category == "recovered" then
        for _, item in ipairs(MetaProgress.GetWarehouseItems()) do
            if category == "all" or item.source == "recovered" then
                table.insert(list, item)
            end
        end
    end
    if category == "all" or category == "consumable" then
        for _, def in ipairs(MetaProgress.CONSUMABLES) do
            table.insert(list, MetaProgress.GetUnifiedItemDisplayData(def.id, "consumable"))
        end
    end
    if category == "all" or category == "equipment" then
        for _, def in ipairs(MetaProgress.ITEMS) do
            table.insert(list, MetaProgress.GetUnifiedItemDisplayData(def.id, "equipment"))
        end
    end
    table.sort(list, function(a, b)
        return (a.type or "") .. (a.name or a.id) < (b.type or "") .. (b.name or b.id)
    end)
    return list
end

function MetaProgress.GetWarehouseItemCount(itemId)
    data.warehouse = normalizeWarehouse(data.warehouse)
    local item = data.warehouse.items[itemId]
    return item and item.count or 0
end

function MetaProgress.RemoveWarehouseItem(itemId, count)
    data.warehouse = normalizeWarehouse(data.warehouse)
    count = toNonNegativeNumber(count)
    if count <= 0 then return false, "invalid_count" end
    local item = data.warehouse.items[itemId]
    if not item or item.count < count then return false, "not_enough" end
    item.count = item.count - count
    if item.count <= 0 then
        data.warehouse.items[itemId] = nil
    end
    return true, nil
end

function MetaProgress.SellWarehouseItem(itemId, count)
    data.warehouse = normalizeWarehouse(data.warehouse)
    count = toNonNegativeNumber(count)
    if count <= 0 then return false, "invalid_count" end
    local canSell, reason = MetaProgress.CanSellItem(itemId)
    if not canSell then return false, reason or "not_sellable" end
    local item = data.warehouse.items[itemId]
    if not item or item.count < count then return false, "not_enough" end
    local gainedGold = (item.value or 0) * count
    local ok, removeReason = MetaProgress.RemoveWarehouseItem(itemId, count)
    if not ok then return false, removeReason end
    data.gold = data.gold + gainedGold
    data.stats.totalGoldEarned = data.stats.totalGoldEarned + gainedGold
    MetaProgress.Save()
    return true, { gold = gainedGold, itemId = itemId, count = count, name = item.name }
end

function MetaProgress.GetWarehouseSummary()
    local totalStacks = 0
    local totalItems = 0
    local totalValue = 0
    for _, item in ipairs(MetaProgress.GetWarehouseItems()) do
        totalStacks = totalStacks + 1
        totalItems = totalItems + (item.count or 0)
        if item.canSell then
            totalValue = totalValue + (item.totalValue or 0)
        end
    end
    return { totalStacks = totalStacks, totalItems = totalItems, totalValue = totalValue }
end

function MetaProgress.GetShopDisplayList(filter)
    filter = filter or {}
    local list = {}
    if not filter.type or filter.type == "equipment" or filter.type == "all" then
        for _, item in ipairs(MetaProgress.ITEMS) do
            table.insert(list, MetaProgress.GetUnifiedItemDisplayData(item.id, "equipment"))
        end
    end
    if not filter.type or filter.type == "consumable" or filter.type == "all" then
        for _, item in ipairs(MetaProgress.CONSUMABLES) do
            table.insert(list, MetaProgress.GetUnifiedItemDisplayData(item.id, "consumable"))
        end
    end
    return list
end

function MetaProgress.GetLoadoutDisplayList()
    local list = {}
    for _, item in ipairs(MetaProgress.ITEMS) do
        table.insert(list, MetaProgress.GetUnifiedItemDisplayData(item.id, "equipment"))
    end
    for _, item in ipairs(MetaProgress.CONSUMABLES) do
        table.insert(list, MetaProgress.GetUnifiedItemDisplayData(item.id, "consumable"))
    end
    return list
end

function MetaProgress.GetInventorySummary()
    local consumableCount = 0
    for _, count in pairs(normalizeConsumables(data.consumables)) do
        consumableCount = consumableCount + count
    end
    local ownedEquipment = 0
    for _, item in ipairs(MetaProgress.ITEMS) do
        if MetaProgress.OwnsItem(item.id) then ownedEquipment = ownedEquipment + 1 end
    end
    local warehouse = MetaProgress.GetWarehouseSummary()
    return {
        gold = data.gold,
        warehouseItems = warehouse.totalItems,
        warehouseValue = warehouse.totalValue,
        consumables = consumableCount,
        ownedEquipment = ownedEquipment,
        equipped = #data.equippedItems,
    }
end

function MetaProgress.GetLoadoutSummary()
    data.loadout = normalizeLoadout(data.loadout)
    local names = {}
    for _, itemId in ipairs(data.equippedItems) do
        local display = MetaProgress.GetUnifiedItemDisplayData(itemId, "equipment")
        table.insert(names, display.name)
    end
    local consumableNames = {}
    local totalConsumables = 0
    for itemId, count in pairs(data.loadout.consumables) do
        local display = MetaProgress.GetUnifiedItemDisplayData(itemId, "consumable")
        totalConsumables = totalConsumables + count
        table.insert(consumableNames, display.name .. " x" .. count)
    end
    local effects = {}
    local equipBonus = MetaProgress.GetEquipBonus()
    local talentEffects = MetaProgress.GetTalentEffects()
    if equipBonus.bonusHP > 0 then table.insert(effects, "生命 +" .. equipBonus.bonusHP) end
    if equipBonus.bonusPower > 0 then table.insert(effects, "战斗力 +" .. equipBonus.bonusPower) end
    if equipBonus.mineImmunity then table.insert(effects, "首次雷险免疫") end
    if equipBonus.showExitHint then table.insert(effects, "撤离信标提示") end
    if equipBonus.searchBonus > 0 then table.insert(effects, "搜索收益 +" .. equipBonus.searchBonus .. "%") end
    if talentEffects.mineDmgReduce > 0 then table.insert(effects, "雷险伤害 -" .. talentEffects.mineDmgReduce) end
    if talentEffects.failureGoldBonus > 0 then table.insert(effects, "抢救条款 +" .. talentEffects.failureGoldBonus) end
    local emptyEquipmentHint = "未配置作业装备"
    local emptyConsumablesHint = "未携带作业消耗品"
    local emptyEffectsHint = "本局无额外加成"
    return {
        equipmentText = #names > 0 and table.concat(names, " / ") or emptyEquipmentHint,
        consumableText = #consumableNames > 0 and table.concat(consumableNames, " / ") or emptyConsumablesHint,
        consumablesText = #consumableNames > 0 and table.concat(consumableNames, " / ") or emptyConsumablesHint,
        effects = effects,
        effectsText = #effects > 0 and table.concat(effects, " / ") or emptyEffectsHint,
        emptyEquipmentHint = emptyEquipmentHint,
        emptyConsumablesHint = emptyConsumablesHint,
        emptyEffectsHint = emptyEffectsHint,
        consumableCount = totalConsumables,
    }
end

function MetaProgress.GetTerminalSummary()
    return {
        inventory = MetaProgress.GetInventorySummary(),
        loadout = MetaProgress.GetLoadoutSummary(),
        recovery = MetaProgress.GetRecoverySummary(),
        recentText = MetaProgress.GetRecoverySummaryText(4),
    }
end

function MetaProgress.RecordExtractionReward(reward, runStats)
    if not reward then
        return nil
    end
    if reward.metaRecorded then
        return reward.metaReceipt
    end

    data.recovery = normalizeRecovery(data.recovery)

    local goldAdded = toNonNegativeNumber(reward.directGold) + toNonNegativeNumber(reward.loosePartsGold)
    local itemCount = toNonNegativeNumber(reward.carriedItemCount)
    local itemValue = toNonNegativeNumber(reward.carriedItemValue)
    local goldBefore = data.gold
    local warehouseAdded = { count = 0, value = 0 }

    data.gold = data.gold + goldAdded
    data.stats.totalGoldEarned = data.stats.totalGoldEarned + goldAdded
    data.stats.totalExtractions = data.stats.totalExtractions + 1

    if itemCount > 0 or itemValue > 0 then
        data.recovery.totalItems = data.recovery.totalItems + itemCount
        data.recovery.totalValue = data.recovery.totalValue + itemValue
        data.recovery.totalExtractionsWithItems = data.recovery.totalExtractionsWithItems + 1
        pushRecentRecoveryItems(reward.carriedItems)
        warehouseAdded = MetaProgress.AddWarehouseItems(reward.carriedItems, "recovered")
    end

    local receipt = {
        goldBefore = goldBefore,
        goldAfter = data.gold,
        goldAdded = goldAdded,
        directGold = toNonNegativeNumber(reward.directGold),
        loosePartsGold = toNonNegativeNumber(reward.loosePartsGold),
        itemCount = itemCount,
        itemValue = itemValue,
        warehouseAdded = warehouseAdded,
        recentItems = trimRecentItems(data.recovery.recentItems),
        stats = runStats,
    }
    reward.metaRecorded = true
    reward.metaReceipt = receipt
    MetaProgress.Save()
    return receipt
end

-- ============================================================================
-- 局内效果查询(StartNewGame 时调用)
-- ============================================================================

--- 获取装备带来的属性加成
---@return { bonusHP: number, bonusPower: number, mineImmunity: boolean, mineDmgReduce: number, showExitHint: boolean, searchBonus: number }
function MetaProgress.GetEquipBonus()
    local bonus = {
        bonusHP = 0,
        bonusPower = 0,
        mineImmunity = false,
        mineDmgReduce = 0,
        showExitHint = false,
        searchBonus = 0,
    }
    for _, itemId in ipairs(data.equippedItems) do
        if itemId == "armor" then
            bonus.bonusHP = bonus.bonusHP + Balance.shop.armor.bonusHP
        elseif itemId == "whetstone" then
            bonus.bonusPower = bonus.bonusPower + Balance.shop.whetstone.bonusPower
        elseif itemId == "medkit" then
            bonus.mineImmunity = true
        elseif itemId == "insulated_gloves" then
            bonus.mineDmgReduce = bonus.mineDmgReduce + Balance.shop.insulated_gloves.mineDmgReduce
        elseif itemId == "compass" then
            bonus.showExitHint = true
        elseif itemId == "backpack" then
            bonus.searchBonus = bonus.searchBonus + 50
        end
    end
    return bonus
end

--- 获取天赋带来的效果
---@return { mineDmgReduce: number, monsterFleeBonus: number, failureGoldBonus: number, tradePrice: number, mapHighlight: boolean }
function MetaProgress.GetTalentEffects()
    local effects = {
        mineDmgReduce = 0,
        monsterFleeBonus = 0,
        failureGoldBonus = 0,
        tradePrice = 15,  -- 默认 NPC 交易价格
        mapHighlight = false,
    }
    if data.unlockedTalents["talent_mine"] then
        effects.mineDmgReduce = 10
    end
    if data.unlockedTalents["talent_monster"] then
        effects.monsterFleeBonus = 2
    end
    if data.unlockedTalents["talent_extract"] then
        effects.failureGoldBonus = 10
    end
    if data.unlockedTalents["talent_event"] then
        effects.tradePrice = 20
    end
    if data.unlockedTalents["talent_map"] then
        effects.mapHighlight = true
    end
    return effects
end

-- ============================================================================
-- GM 调试方法(免费获取, 不扣结算币)
-- ============================================================================

--- GM:免费给予物品
function MetaProgress.GMGrantItem(itemId)
    data.ownedItems[itemId] = true
    MetaProgress.Save()
end

--- GM:免费解锁天赋
function MetaProgress.GMGrantTalent(talentId)
    data.unlockedTalents[talentId] = true
    MetaProgress.Save()
end

--- GM:装备全部已拥有物品(无视上限)
function MetaProgress.GMEquipAll()
    data.equippedItems = {}
    for _, item in ipairs(MetaProgress.ITEMS) do
        if data.ownedItems[item.id] then
            table.insert(data.equippedItems, item.id)
        end
    end
    MetaProgress.Save()
end

--- GM:清空装备
function MetaProgress.GMUnequipAll()
    data.equippedItems = {}
    MetaProgress.Save()
end

--- GM:重置全部存档
function MetaProgress.GMReset()
    data.gold = 0
    data.unlockedTalents = {}
    data.ownedItems = {}
    data.equippedItems = {}
    data.stats = { totalRuns = 0, totalExtractions = 0, totalGoldEarned = 0 }
    data.recovery = newRecovery()
    data.warehouse = newWarehouse()
    data.consumables = newConsumables()
    data.loadout = newLoadout()
    MetaProgress.Save()
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化(游戏启动时调用一次)
function MetaProgress.Init()
    MetaProgress.Load()
end

return MetaProgress
