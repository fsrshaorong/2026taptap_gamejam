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
-- 已交互过的事件 key="x,y" -> true
EventSystem.interactedEvents = {}
-- 事件选项状态 key="x,y" -> table
EventSystem.optionState = {}
-- 随机种子
EventSystem.seed = 1

local function keyOf(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function getStoredOptionState(key)
    local state = EventSystem.optionState[key]
    if not state then
        state = {}
        EventSystem.optionState[key] = state
    end
    return state
end

-- ============================================================================
-- 初始化 / 重置
-- ============================================================================

function EventSystem.Reset(seed)
    EventSystem.completedEvents = {}
    EventSystem.assignedEvents = {}
    EventSystem.interactedEvents = {}
    EventSystem.optionState = {}
    EventSystem.seed = seed or os.time()
end

-- ============================================================================
-- 事件分配（懒分配：首次进入事件房时确定类型）
-- ============================================================================

---@param x number
---@param y number
---@return EventTypeId
function EventSystem.GetEventType(x, y)
    local key = keyOf(x, y)
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
    local key = keyOf(x, y)
    return EventSystem.completedEvents[key] == true
end

---@param x number
---@param y number
function EventSystem.MarkCompleted(x, y, optionId)
    local key = keyOf(x, y)
    EventSystem.completedEvents[key] = true
    local state = getStoredOptionState(key)
    state.completed = true
    state.completedCount = (state.completedCount or 0) + 1
    if optionId then
        state.completedOption = optionId
    end
end

function EventSystem.MarkInteracted(x, y)
    local key = keyOf(x, y)
    EventSystem.interactedEvents[key] = true
end

function EventSystem.GetEventState(x, y)
    local key = keyOf(x, y)
    local eventType = EventSystem.GetEventType(x, y)
    return {
        eventId = key,
        x = x,
        y = y,
        eventType = eventType,
        completed = EventSystem.completedEvents[key] == true,
        interacted = EventSystem.interactedEvents[key] == true,
        optionState = EventSystem.optionState[key] or {},
        def = EventSystem.GetEventDef(eventType),
    }
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
-- 选项与交易接口
-- ============================================================================

local function result(ok, msg, extra)
    local r = {
        ok = ok,
        msg = msg or "",
        goldDelta = 0,
        partsDelta = 0,
        hpDelta = 0,
        powerDelta = 0,
        pressureDelta = 0,
        completed = false,
        closePanel = false,
        eventType = nil,
        optionId = nil,
    }
    if extra then
        for k, v in pairs(extra) do r[k] = v end
    end
    return r
end

function EventSystem.getTradableItems(runInventoryOrContext)
    local source = runInventoryOrContext or {}
    return {
        {
            id = "parts",
            name = "异常回收物",
            count = source.parts or 0,
        },
    }
end

function EventSystem.getTradeDisplayName(itemId)
    if itemId == "parts" then return "异常回收物" end
    return tostring(itemId or "未知物品")
end

function EventSystem.canExecuteTrade(option, state)
    if option and option.enabled == false then
        return false, option.disabledReason or "条件不足"
    end
    if state and state.completed then
        return false, "事件已完成"
    end
    return true, nil
end

function EventSystem.executeTrade(option, state, context)
    local ok, reason = EventSystem.canExecuteTrade(option, state)
    if not ok then
        return result(false, reason, { eventType = state and state.eventType or nil, optionId = option and option.id or nil })
    end
    return EventSystem.ExecuteOptionById(state.x, state.y, option.id, context)
end

EventSystem.canTrade = EventSystem.canExecuteTrade

local function option(id, label, desc, cost, reward, risk, enabled, disabledReason)
    return {
        id = id,
        label = label,
        description = desc,
        cost = cost or "无",
        reward = reward or "无",
        risk = risk or "无",
        enabled = enabled ~= false,
        disabledReason = disabledReason,
    }
end

local function getTraderOptions(ctx)
    local tradePrice = ctx.tradePrice or 15
    local healCost = 12
    local intelCost = 6
    local buffCost = 15
    local missingHp = math.max(0, (ctx.maxHp or 0) - (ctx.hp or 0))
    return {
        option(
            "sell_parts",
            "出售异常回收物",
            "选择出售对象: 异常回收物(parts). 当前使用虚拟可交易物, 后续可接背包/仓库物品.",
            "异常回收物 x1",
            "结算币 +" .. tradePrice,
            "会减少可撤离折算资源",
            (ctx.parts or 0) >= 1,
            "异常回收物不足"
        ),
        option(
            "heal",
            "购买急救服务",
            "旅商提供一次快速包扎, 立即恢复生命.",
            "结算币 " .. healCost,
            "生命 +" .. math.min(25, missingHp),
            "事件完成后旅商离开",
            (ctx.gold or 0) >= healCost and missingHp > 0,
            missingHp <= 0 and "生命已满" or "结算币不足"
        ),
        option(
            "intel",
            "购买雷险提示",
            "购买一条本局情报提示, 不揭示地图, 只提供判断规则.",
            "结算币 " .. intelCost,
            "获得雷险提示",
            "无直接资源收益",
            (ctx.gold or 0) >= intelCost,
            "结算币不足"
        ),
        option(
            "buff",
            "购买临时兴奋剂",
            "当前局战斗力提升, 只作为临时状态使用.",
            "结算币 " .. buffCost,
            "战斗力 +3",
            "事件完成后旅商离开",
            (ctx.gold or 0) >= buffCost,
            "结算币不足"
        ),
        option("leave", "离开", "暂不交易, 保留事件房可再次进入.", "无", "无", "无", true, nil),
    }
end

local function getDiceOptions(ctx)
    local canBet = (ctx.gold or 0) >= 10
    return {
        option("bet_small", "下注 10 结算币", "掷出 4/5/6 获胜, 否则失败.", "结算币 10", "成功净赚 +10", "失败 -10", canBet, "结算币不足"),
        option("leave", "离开", "不下注.", "无", "无", "无", true, nil),
    }
end

local function getAltarOptions(ctx)
    local canOffer = (ctx.hp or 0) > 1
    return {
        option("offer_hp", "献祭生命", "以生命换取稳定资源, 但会惊动区域协议.", "生命 1", "结算币 +15, 异常回收物 +1", "协议压力 +5", canOffer, "生命不足"),
        option("leave", "离开", "不触碰祭坛.", "无", "无", "无", true, nil),
    }
end

local function getTrapOptions(ctx)
    return {
        option("disarm", "处理机关", "使用战斗力进行非战斗检定.", "一次检定", "成功: 结算币 +25, 异常回收物 +2", "失败: 生命 -1, 协议压力 +5", true, nil),
        option("leave", "离开", "不处理机关.", "无", "无", "无", true, nil),
    }
end

function EventSystem.GetOptions(x, y, context)
    local state = EventSystem.GetEventState(x, y)
    local def = state.def
    local title = def and def.name or "事件"
    local desc = def and def.enterMsg or "发现事件房."
    if state.completed then
        desc = def and def.doneMsg or "事件已完成."
    end

    local options = {}
    if not state.completed then
        if state.eventType == "trader" then
            options = getTraderOptions(context or {})
        elseif state.eventType == "dice" then
            options = getDiceOptions(context or {})
        elseif state.eventType == "altar" then
            options = getAltarOptions(context or {})
        elseif state.eventType == "trap" then
            options = getTrapOptions(context or {})
        end
    else
        options = { option("leave", "关闭", "事件已完成, 可以安全经过.", "无", "无", "无", true, nil) }
    end

    return {
        state = state,
        title = title,
        description = desc,
        options = options,
    }
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
    local eventId = EventSystem.GetEventType(x, y)
    local defaultOption = "leave"
    if eventId == "trader" then
        defaultOption = "sell_parts"
    elseif eventId == "dice" then
        defaultOption = "bet_small"
    elseif eventId == "altar" then
        defaultOption = "offer_hp"
    elseif eventId == "trap" then
        defaultOption = "disarm"
    end
    return EventSystem.ExecuteOptionById(x, y, defaultOption, context)
end

function EventSystem.ExecuteOptionById(x, y, optionId, context)
    local key = keyOf(x, y)
    local eventId = EventSystem.GetEventType(x, y)
    EventSystem.MarkInteracted(x, y)

    if optionId == "leave" then
        return result(true, "事件交互取消.", {
            eventType = eventId,
            optionId = optionId,
            closePanel = true,
            completed = false,
        })
    end

    if EventSystem.completedEvents[key] then
        return result(false, "此处事件已完成.", { eventType = eventId, optionId = optionId })
    end

    local menu = EventSystem.GetOptions(x, y, context or {})
    local selected = nil
    for _, opt in ipairs(menu.options or {}) do
        if opt.id == optionId then
            selected = opt
            break
        end
    end
    if not selected then
        return result(false, "未知事件选项.", { eventType = eventId, optionId = optionId })
    end
    if selected.enabled == false then
        return result(false, selected.disabledReason or "条件不足.", { eventType = eventId, optionId = optionId })
    end

    if eventId == "trader" then
        return EventSystem._ExecTrader(x, y, context, optionId)
    elseif eventId == "dice" then
        return EventSystem._ExecDice(x, y, context, optionId)
    elseif eventId == "altar" then
        return EventSystem._ExecAltar(x, y, context, optionId)
    elseif eventId == "trap" then
        return EventSystem._ExecTrap(x, y, context, optionId)
    end

    return result(false, "未知事件类型.", { eventType = eventId, optionId = optionId })
end

-- ============================================================================
-- 旅商：可扩展交易
-- ============================================================================

function EventSystem._ExecTrader(x, y, ctx, optionId)
    ctx = ctx or {}
    local price = ctx.tradePrice or 15
    if optionId == "sell_parts" then
        if (ctx.parts or 0) < 1 then
            return result(false, "异常回收物不足.", { eventType = "trader", optionId = optionId })
        end
        EventSystem.MarkCompleted(x, y, optionId)
        return result(true, "出售异常回收物, 获得结算币 +" .. price .. ".", {
            goldDelta = price,
            partsDelta = -1,
            completed = true,
            closePanel = true,
            eventType = "trader",
            optionId = optionId,
        })
    elseif optionId == "heal" then
        local healCost = 12
        if (ctx.gold or 0) < healCost then
            return result(false, "结算币不足.", { eventType = "trader", optionId = optionId })
        end
        local heal = math.min(25, math.max(0, (ctx.maxHp or 0) - (ctx.hp or 0)))
        if heal <= 0 then
            return result(false, "生命已满.", { eventType = "trader", optionId = optionId })
        end
        EventSystem.MarkCompleted(x, y, optionId)
        return result(true, "急救完成. 生命 +" .. heal .. ".", {
            goldDelta = -healCost,
            hpDelta = heal,
            completed = true,
            closePanel = true,
            eventType = "trader",
            optionId = optionId,
        })
    elseif optionId == "intel" then
        local cost = 6
        if (ctx.gold or 0) < cost then
            return result(false, "结算币不足.", { eventType = "trader", optionId = optionId })
        end
        EventSystem.MarkCompleted(x, y, optionId)
        return result(true, "雷险提示: 数字只统计雷房; 异常体和事件房不会增加雷数.", {
            goldDelta = -cost,
            completed = true,
            closePanel = true,
            eventType = "trader",
            optionId = optionId,
        })
    elseif optionId == "buff" then
        local cost = 15
        if (ctx.gold or 0) < cost then
            return result(false, "结算币不足.", { eventType = "trader", optionId = optionId })
        end
        EventSystem.MarkCompleted(x, y, optionId)
        return result(true, "临时兴奋剂生效. 战斗力 +3.", {
            goldDelta = -cost,
            powerDelta = 3,
            completed = true,
            closePanel = true,
            eventType = "trader",
            optionId = optionId,
        })
    end
    return result(false, "未知交易项.", { eventType = "trader", optionId = optionId })
end

-- ============================================================================
-- 骰子赌博：赌注10金 → 掷骰子 → 4+赢20金, 3以下输掉赌注
-- ============================================================================

local DICE_BET = 10
local DICE_WIN = 20
local DICE_WIN_THRESHOLD = 4  -- 掷出4/5/6赢

function EventSystem._ExecDice(x, y, ctx, optionId)
    ctx = ctx or {}
    if optionId ~= "bet_small" then
        return result(false, "未知下注项.", { eventType = "dice", optionId = optionId })
    end
    if (ctx.gold or 0) < DICE_BET then
        return result(false, "结算币不足, 下注取消.", { eventType = "dice", optionId = optionId })
    end
    -- 基于位置和种子的确定性骰子结果
    local hash = (x * 197 + y * 83 + EventSystem.seed * 59 + (ctx.gold or 0)) % 6 + 1
    EventSystem.MarkCompleted(x, y, optionId)
    if hash >= DICE_WIN_THRESHOLD then
        local net = DICE_WIN - DICE_BET
        return result(true, "掷出 " .. hash .. "! 下注成功: 结算币 +" .. net .. ".", {
            goldDelta = net,
            completed = true,
            closePanel = true,
            eventType = "dice",
            optionId = optionId,
        })
    else
        return result(true, "掷出 " .. hash .. "... 下注失败: 结算币 -" .. DICE_BET .. ".", {
            goldDelta = -DICE_BET,
            completed = true,
            closePanel = true,
            eventType = "dice",
            optionId = optionId,
        })
    end
end

-- ============================================================================
-- 神秘祭坛：献祭 1 HP → 获得 15 金币 + 1 零件
-- ============================================================================

local ALTAR_HP_COST = 1
local ALTAR_GOLD_REWARD = 15
local ALTAR_PARTS_REWARD = 1

function EventSystem._ExecAltar(x, y, ctx, optionId)
    ctx = ctx or {}
    if optionId ~= "offer_hp" then
        return result(false, "未知祭坛选项.", { eventType = "altar", optionId = optionId })
    end
    if (ctx.hp or 0) <= ALTAR_HP_COST then
        return result(false, "生命不足, 建议不要把自己也献上去.", { eventType = "altar", optionId = optionId })
    end
    EventSystem.MarkCompleted(x, y, optionId)
    return result(true, "祭坛响应: 生命 -" .. ALTAR_HP_COST .. ", 结算币 +" .. ALTAR_GOLD_REWARD .. ", 异常回收物 +" .. ALTAR_PARTS_REWARD .. ", 协议压力 +5.", {
        goldDelta = ALTAR_GOLD_REWARD,
        partsDelta = ALTAR_PARTS_REWARD,
        hpDelta = -ALTAR_HP_COST,
        pressureDelta = 5,
        completed = true,
        closePanel = true,
        eventType = "altar",
        optionId = optionId,
    })
end

-- ============================================================================
-- 陷阱拆解：战斗力检定 → 成功大奖，失败扣血
-- ============================================================================

local TRAP_POWER_REQ = 8   -- 需要战斗力 >= 8
local TRAP_SUCCESS_GOLD = 25
local TRAP_SUCCESS_PARTS = 2
local TRAP_FAIL_HP = 1

function EventSystem._ExecTrap(x, y, ctx, optionId)
    ctx = ctx or {}
    if optionId ~= "disarm" then
        return result(false, "未知机关选项.", { eventType = "trap", optionId = optionId })
    end
    local power = ctx.power or 0
    EventSystem.MarkCompleted(x, y, optionId)
    if power >= TRAP_POWER_REQ then
        return result(true, "机关处理成功: 结算币 +" .. TRAP_SUCCESS_GOLD .. ", 异常回收物 +" .. TRAP_SUCCESS_PARTS .. ".", {
            goldDelta = TRAP_SUCCESS_GOLD,
            partsDelta = TRAP_SUCCESS_PARTS,
            completed = true,
            closePanel = true,
            eventType = "trap",
            optionId = optionId,
        })
    else
        return result(true, "机关失控: 生命 -" .. TRAP_FAIL_HP .. ", 协议压力 +5.", {
            hpDelta = -TRAP_FAIL_HP,
            pressureDelta = 5,
            completed = true,
            closePanel = true,
            eventType = "trap",
            optionId = optionId,
        })
    end
end

return EventSystem
