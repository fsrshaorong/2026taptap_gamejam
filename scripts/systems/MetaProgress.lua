-- ============================================================================
-- MetaProgress.lua — 局外持久化进度管理
-- 管理:全局金币,已解锁天赋,已购买/装备的带入物品,统计数据
-- ============================================================================

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
        price = 50,
        category = "数值",
        icon = "[DEF]",
    },
    {
        id = "whetstone",
        name = "磨刀石",
        desc = "+5 战斗力",
        price = 40,
        category = "数值",
        icon = "[ATK]",
    },
    {
        id = "medkit",
        name = "急救包",
        desc = "首次踩雷免疫伤害",
        price = 60,
        category = "机制",
        icon = "[MED]",
    },
    {
        id = "compass",
        name = "罗盘",
        desc = "开局显示撤离点所在象限",
        price = 80,
        category = "机制",
        icon = "[NAV]",
    },
    {
        id = "backpack",
        name = "大背包",
        desc = "搜索奖励 +50%",
        price = 100,
        category = "数值",
        icon = "[BAG]",
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
        direction = "小地图",
        name = "邻域感知",
        desc = "进入房间时高亮 8 邻域",
        price = 100,
    },
    {
        id = "talent_mine",
        direction = "雷房",
        name = "厚皮",
        desc = "雷伤降低 10 点",
        price = 80,
    },
    {
        id = "talent_monster",
        direction = "怪物",
        name = "威压",
        desc = "怪物逃跑时间 +2 秒",
        price = 80,
    },
    {
        id = "talent_extract",
        direction = "撤离",
        name = "保险金",
        desc = "失败保底额外 +10 金币",
        price = 100,
    },
    {
        id = "talent_event",
        direction = "事件",
        name = "议价",
        desc = "NPC 交易价格 15->20",
        price = 120,
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
}

local function toNonNegativeNumber(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    return math.floor(value)
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
    }

    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(saveData))
        file:Close()
        print("[MetaProgress] Saved: gold=" .. data.gold)
    end
end

-- ============================================================================
-- 金币操作
-- ============================================================================

--- 获取当前金币
---@return number
function MetaProgress.GetGold()
    return data.gold
end

--- 增加金币(局结算时调用)
---@param amount number
function MetaProgress.AddGold(amount)
    amount = toNonNegativeNumber(amount)
    if amount <= 0 then return end
    data.gold = data.gold + amount
    data.stats.totalGoldEarned = data.stats.totalGoldEarned + amount
    MetaProgress.Save()
end

--- 消费金币(购买物品/天赋时调用)
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
        return false, "金币不足"
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
        return false, "最多装备 " .. MAX_EQUIPPED .. " 件"
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
        return false, "天赋不存在"
    end
    if data.gold < talent.price then
        return false, "金币不足"
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

function MetaProgress.RecordExtractionReward(reward, runStats)
    if not reward then
        return nil
    end
    if reward.metaRecorded then
        return reward.metaReceipt
    end

    data.recovery = normalizeRecovery(data.recovery)

    local goldAdded = toNonNegativeNumber(reward.totalGold)
    local itemCount = toNonNegativeNumber(reward.carriedItemCount)
    local itemValue = toNonNegativeNumber(reward.carriedItemValue)
    local goldBefore = data.gold

    data.gold = data.gold + goldAdded
    data.stats.totalGoldEarned = data.stats.totalGoldEarned + goldAdded
    data.stats.totalExtractions = data.stats.totalExtractions + 1

    if itemCount > 0 or itemValue > 0 then
        data.recovery.totalItems = data.recovery.totalItems + itemCount
        data.recovery.totalValue = data.recovery.totalValue + itemValue
        data.recovery.totalExtractionsWithItems = data.recovery.totalExtractionsWithItems + 1
        pushRecentRecoveryItems(reward.carriedItems)
    end

    local receipt = {
        goldBefore = goldBefore,
        goldAfter = data.gold,
        goldAdded = goldAdded,
        itemCount = itemCount,
        itemValue = itemValue,
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
---@return { bonusHP: number, bonusPower: number, mineImmunity: boolean, showExitHint: boolean, searchBonus: number }
function MetaProgress.GetEquipBonus()
    local bonus = {
        bonusHP = 0,
        bonusPower = 0,
        mineImmunity = false,
        showExitHint = false,
        searchBonus = 0,
    }
    for _, itemId in ipairs(data.equippedItems) do
        if itemId == "armor" then
            bonus.bonusHP = bonus.bonusHP + 25
        elseif itemId == "whetstone" then
            bonus.bonusPower = bonus.bonusPower + 5
        elseif itemId == "medkit" then
            bonus.mineImmunity = true
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
-- GM 调试方法(免费获取, 不扣金币)
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
