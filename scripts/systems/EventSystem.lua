-- ============================================================================
-- EventSystem.lua
-- v0.3 事件系统：管理事件房的类型分配、交互逻辑和状态
-- 支持：旅商交易、骰子赌博、神秘祭坛、陷阱拆解
-- ============================================================================

local EventSystem = {}

-- ============================================================================
-- 事件类型定义
-- ============================================================================

---@alias EventTypeId "trader" | "dice" | "altar" | "trap"

---@class EventDef
---@field id EventTypeId
---@field name string
---@field enterMsg string
---@field doneMsg string
---@field weight number 随机权重

EventSystem.EVENT_TYPES = {
    {
        id = "trader",
        name = "旅商",
        enterMsg = "遇到旅商! 按 T 用零件换金币.",
        doneMsg = "旅商已交易完毕.",
        weight = 30,
    },
    {
        id = "dice",
        name = "赌徒",
        enterMsg = "遇到赌徒! 按 T 赌一把 (赌注: 10金币).",
        doneMsg = "赌徒已离开.",
        weight = 25,
    },
    {
        id = "altar",
        name = "祭坛",
        enterMsg = "发现神秘祭坛! 按 T 献祭生命换取资源.",
        doneMsg = "祭坛能量已耗尽.",
        weight = 25,
    },
    {
        id = "trap",
        name = "机关",
        enterMsg = "发现古老机关! 按 T 尝试拆解 (成功奖励丰厚).",
        doneMsg = "机关已拆解.",
        weight = 20,
    },
}

-- ============================================================================
-- 状态
-- ============================================================================

-- 已完成事件 key="x,y" -> true
EventSystem.completedEvents = {}
-- 已分配事件类型 key="x,y" -> EventTypeId
EventSystem.assignedEvents = {}
-- 随机种子
EventSystem.seed = 1

-- ============================================================================
-- 初始化 / 重置
-- ============================================================================

function EventSystem.Reset(seed)
    EventSystem.completedEvents = {}
    EventSystem.assignedEvents = {}
    EventSystem.seed = seed or os.time()
end

-- ============================================================================
-- 事件分配（懒分配：首次进入事件房时确定类型）
-- ============================================================================

---@param x number
---@param y number
---@return EventTypeId
function EventSystem.GetEventType(x, y)
    local key = tostring(x) .. "," .. tostring(y)
    if EventSystem.assignedEvents[key] then
        return EventSystem.assignedEvents[key]
    end
    -- 基于坐标和种子的确定性随机
    local hash = (x * 73 + y * 137 + EventSystem.seed * 31) % 10000
    local totalWeight = 0
    for _, def in ipairs(EventSystem.EVENT_TYPES) do
        totalWeight = totalWeight + def.weight
    end
    local roll = hash % totalWeight
    local acc = 0
    for _, def in ipairs(EventSystem.EVENT_TYPES) do
        acc = acc + def.weight
        if roll < acc then
            EventSystem.assignedEvents[key] = def.id
            return def.id
        end
    end
    -- fallback
    EventSystem.assignedEvents[key] = "trader"
    return "trader"
end

---@param eventId EventTypeId
---@return EventDef|nil
function EventSystem.GetEventDef(eventId)
    for _, def in ipairs(EventSystem.EVENT_TYPES) do
        if def.id == eventId then return def end
    end
    return nil
end

-- ============================================================================
-- 状态查询
-- ============================================================================

---@param x number
---@param y number
---@return boolean
function EventSystem.IsCompleted(x, y)
    local key = tostring(x) .. "," .. tostring(y)
    return EventSystem.completedEvents[key] == true
end

---@param x number
---@param y number
function EventSystem.MarkCompleted(x, y)
    local key = tostring(x) .. "," .. tostring(y)
    EventSystem.completedEvents[key] = true
end

-- ============================================================================
-- 进入事件房提示
-- ============================================================================

---@param x number
---@param y number
---@return string 进入提示文本
function EventSystem.GetEnterMessage(x, y)
    if EventSystem.IsCompleted(x, y) then
        local eventId = EventSystem.GetEventType(x, y)
        local def = EventSystem.GetEventDef(eventId)
        return def and def.doneMsg or "事件已完成."
    end
    local eventId = EventSystem.GetEventType(x, y)
    local def = EventSystem.GetEventDef(eventId)
    return def and def.enterMsg or "发现事件房."
end

-- ============================================================================
-- 事件执行逻辑
-- ============================================================================

---@class EventResult
---@field ok boolean
---@field msg string
---@field goldDelta number
---@field partsDelta number
---@field hpDelta number

--- 执行事件交互（按 T 触发）
---@param x number
---@param y number
---@param context table { gold:number, parts:number, hp:number, maxHp:number, tradePrice:number, power:number }
---@return EventResult
function EventSystem.Execute(x, y, context)
    local key = tostring(x) .. "," .. tostring(y)
    if EventSystem.completedEvents[key] then
        return { ok = false, msg = "此处事件已完成.", goldDelta = 0, partsDelta = 0, hpDelta = 0 }
    end

    local eventId = EventSystem.GetEventType(x, y)

    if eventId == "trader" then
        return EventSystem._ExecTrader(x, y, context)
    elseif eventId == "dice" then
        return EventSystem._ExecDice(x, y, context)
    elseif eventId == "altar" then
        return EventSystem._ExecAltar(x, y, context)
    elseif eventId == "trap" then
        return EventSystem._ExecTrap(x, y, context)
    end

    return { ok = false, msg = "未知事件类型.", goldDelta = 0, partsDelta = 0, hpDelta = 0 }
end

-- ============================================================================
-- 旅商：1零件 → N金币
-- ============================================================================

function EventSystem._ExecTrader(x, y, ctx)
    if ctx.parts < 1 then
        return { ok = false, msg = "旅商想要 1 个零件, 当前没有可交易零件.", goldDelta = 0, partsDelta = 0, hpDelta = 0 }
    end
    local price = ctx.tradePrice or 15
    EventSystem.MarkCompleted(x, y)
    return {
        ok = true,
        msg = "交易成功! 用 1 零件换了 " .. price .. " 金币.",
        goldDelta = price,
        partsDelta = -1,
        hpDelta = 0,
    }
end

-- ============================================================================
-- 骰子赌博：赌注10金 → 掷骰子 → 4+赢20金, 3以下输掉赌注
-- ============================================================================

local DICE_BET = 10
local DICE_WIN = 20
local DICE_WIN_THRESHOLD = 4  -- 掷出4/5/6赢

function EventSystem._ExecDice(x, y, ctx)
    if ctx.gold < DICE_BET then
        return { ok = false, msg = "赌徒要求 " .. DICE_BET .. " 金币赌注, 你金币不够.", goldDelta = 0, partsDelta = 0, hpDelta = 0 }
    end
    -- 基于位置和种子的确定性骰子结果
    local hash = (x * 197 + y * 83 + EventSystem.seed * 59 + ctx.gold) % 6 + 1
    EventSystem.MarkCompleted(x, y)
    if hash >= DICE_WIN_THRESHOLD then
        local net = DICE_WIN - DICE_BET
        return {
            ok = true,
            msg = "掷出 " .. hash .. "! 你赢了! 净赚 " .. net .. " 金币!",
            goldDelta = net,
            partsDelta = 0,
            hpDelta = 0,
        }
    else
        return {
            ok = true,
            msg = "掷出 " .. hash .. "... 运气不好, 输了 " .. DICE_BET .. " 金币.",
            goldDelta = -DICE_BET,
            partsDelta = 0,
            hpDelta = 0,
        }
    end
end

-- ============================================================================
-- 神秘祭坛：献祭 1 HP → 获得 15 金币 + 1 零件
-- ============================================================================

local ALTAR_HP_COST = 1
local ALTAR_GOLD_REWARD = 15
local ALTAR_PARTS_REWARD = 1

function EventSystem._ExecAltar(x, y, ctx)
    if ctx.hp <= ALTAR_HP_COST then
        return { ok = false, msg = "生命不足, 祭坛需要献祭 " .. ALTAR_HP_COST .. " 点生命.", goldDelta = 0, partsDelta = 0, hpDelta = 0 }
    end
    EventSystem.MarkCompleted(x, y)
    return {
        ok = true,
        msg = "献祭成功! 失去 " .. ALTAR_HP_COST .. " HP, 获得 " .. ALTAR_GOLD_REWARD .. " 金币 + " .. ALTAR_PARTS_REWARD .. " 零件.",
        goldDelta = ALTAR_GOLD_REWARD,
        partsDelta = ALTAR_PARTS_REWARD,
        hpDelta = -ALTAR_HP_COST,
    }
end

-- ============================================================================
-- 陷阱拆解：战斗力检定 → 成功大奖，失败扣血
-- ============================================================================

local TRAP_POWER_REQ = 8   -- 需要战斗力 >= 8
local TRAP_SUCCESS_GOLD = 25
local TRAP_SUCCESS_PARTS = 2
local TRAP_FAIL_HP = 1

function EventSystem._ExecTrap(x, y, ctx)
    local power = ctx.power or 0
    EventSystem.MarkCompleted(x, y)
    if power >= TRAP_POWER_REQ then
        return {
            ok = true,
            msg = "拆解成功! (战斗力 " .. power .. " >= " .. TRAP_POWER_REQ .. ") 获得 " .. TRAP_SUCCESS_GOLD .. " 金币 + " .. TRAP_SUCCESS_PARTS .. " 零件!",
            goldDelta = TRAP_SUCCESS_GOLD,
            partsDelta = TRAP_SUCCESS_PARTS,
            hpDelta = 0,
        }
    else
        return {
            ok = true,
            msg = "拆解失败! (战斗力 " .. power .. " < " .. TRAP_POWER_REQ .. ") 机关触发, 损失 " .. TRAP_FAIL_HP .. " HP.",
            goldDelta = 0,
            partsDelta = 0,
            hpDelta = -TRAP_FAIL_HP,
        }
    end
end

return EventSystem
