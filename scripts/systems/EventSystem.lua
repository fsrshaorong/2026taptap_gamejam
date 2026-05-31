-- ============================================================================
-- EventSystem.lua
-- Event room assignment and interaction rules.
-- ============================================================================

local Balance = require("systems.Balance")
local GameText = require("systems.GameText")

local EventSystem = {}

EventSystem.EVENT_TYPES = {
    { id = "trader", name = GameText.events.trader.name, enterMsg = GameText.events.trader.enter, doneMsg = GameText.events.trader.done, weight = 30 },
    { id = "dice", name = GameText.events.dice.name, enterMsg = GameText.events.dice.enter, doneMsg = GameText.events.dice.done, weight = 25 },
    { id = "altar", name = GameText.events.altar.name, enterMsg = GameText.events.altar.enter, doneMsg = GameText.events.altar.done, weight = 25 },
    { id = "trap", name = GameText.events.trap.name, enterMsg = GameText.events.trap.enter, doneMsg = GameText.events.trap.done, weight = 20 },
}

EventSystem.completedEvents = {}
EventSystem.assignedEvents = {}
EventSystem.interactedEvents = {}
EventSystem.optionState = {}
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

local function result(ok, msg, extra)
    local r = {
        ok = ok,
        msg = msg or "",
        goldDelta = 0,
        pendingGoldDelta = 0,
        safeGoldDelta = 0,
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

function EventSystem.Reset(seed)
    EventSystem.completedEvents = {}
    EventSystem.assignedEvents = {}
    EventSystem.interactedEvents = {}
    EventSystem.optionState = {}
    EventSystem.seed = seed or os.time()
end

function EventSystem.GetEventType(x, y)
    local key = keyOf(x, y)
    if EventSystem.assignedEvents[key] then return EventSystem.assignedEvents[key] end
    local hash = (x * 73 + y * 137 + EventSystem.seed * 31) % 10000
    local totalWeight = 0
    for _, def in ipairs(EventSystem.EVENT_TYPES) do totalWeight = totalWeight + def.weight end
    local roll = hash % totalWeight
    local acc = 0
    for _, def in ipairs(EventSystem.EVENT_TYPES) do
        acc = acc + def.weight
        if roll < acc then
            EventSystem.assignedEvents[key] = def.id
            return def.id
        end
    end
    EventSystem.assignedEvents[key] = "trader"
    return "trader"
end

function EventSystem.GetEventDef(eventId)
    for _, def in ipairs(EventSystem.EVENT_TYPES) do
        if def.id == eventId then return def end
    end
    return nil
end

function EventSystem.IsCompleted(x, y)
    return EventSystem.completedEvents[keyOf(x, y)] == true
end

function EventSystem.MarkCompleted(x, y, optionId)
    local key = keyOf(x, y)
    EventSystem.completedEvents[key] = true
    local state = getStoredOptionState(key)
    state.completed = true
    state.completedCount = (state.completedCount or 0) + 1
    if optionId then state.completedOption = optionId end
end

function EventSystem.MarkInteracted(x, y)
    EventSystem.interactedEvents[keyOf(x, y)] = true
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

function EventSystem.GetEnterMessage(x, y)
    local eventId = EventSystem.GetEventType(x, y)
    local def = EventSystem.GetEventDef(eventId)
    if EventSystem.IsCompleted(x, y) then
        return def and def.doneMsg or "事件已完成。"
    end
    return def and def.enterMsg or "发现事件房。"
end

function EventSystem.getTradableItems(runInventoryOrContext)
    return (runInventoryOrContext and runInventoryOrContext.tradableItems) or {}
end

function EventSystem.getTradeDisplayName(itemId)
    return tostring(itemId or "未知物品")
end

function EventSystem.canExecuteTrade(optionData, state)
    if optionData and optionData.enabled == false then
        return false, optionData.disabledReason or "条件不足"
    end
    if state and state.completed then return false, "事件已完成" end
    return true, nil
end

function EventSystem.executeTrade(optionData, state, context)
    local ok, reason = EventSystem.canExecuteTrade(optionData, state)
    if not ok then
        return result(false, reason, { eventType = state and state.eventType or nil, optionId = optionData and optionData.id or nil })
    end
    return EventSystem.ExecuteOptionById(state.x, state.y, optionData.id, context)
end

EventSystem.canTrade = EventSystem.canExecuteTrade

local function concreteTradables(ctx)
    local items = {}
    for _, item in ipairs(ctx.tradableItems or {}) do
        if item.type ~= "virtual" and (item.count or 0) > 0 then
            table.insert(items, item)
        end
    end
    return items
end

local function getTraderOptions(ctx)
    local items = concreteTradables(ctx or {})
    local options = {}
    for _, item in ipairs(items) do
        local price = Balance.TraderSaleValue(item.baseValue or item.value)
        table.insert(options, option(
            "sell_item:" .. item.itemId,
            string.format(GameText.events.trader.sellFormat, item.name or item.itemId, item.baseValue or item.value or 0, price),
            GameText.events.trader.intro,
            (item.name or item.itemId) .. " x1",
            "已锁定 +" .. price,
            "该物品会从回收包移除",
            price > 0,
            "该物品无可结算价值"
        ))
    end
    if #options == 0 then
        table.insert(options, option("no_item", GameText.events.trader.noItem, GameText.events.trader.noItem, "无", "无", "无", false, GameText.events.trader.noItem))
    end
    table.insert(options, option("leave", GameText.events.trader.leave, "暂不交易。", "无", "无", "无", true, nil))
    return options
end

local function getDiceOptions(ctx)
    local canBet = (ctx.pendingGold or ctx.gold or 0) >= Balance.gambler.bet
    return {
        option("bet_small", GameText.events.dice.label, GameText.events.dice.intro, "待结算币 " .. Balance.gambler.bet, "5:+20 / 6:+60", "1-4:-20", canBet, GameText.events.dice.disabled),
        option("leave", "离开", "不下注。", "无", "无", "无", true, nil),
    }
end

local function getAltarOptions(ctx, state)
    local step = (state.altarStep or 0) + 1
    local cost = Balance.altar.hpCosts[step]
    if not cost then
        return { option("leave", "关闭", "祭坛已经沉默。", "无", "无", "无", true, nil) }
    end
    local reward = Balance.altar.rewards[step] or { gold = 0, itemQuality = "common" }
    local canOffer = (ctx.hp or 0) > cost
    return {
        option("offer_hp", GameText.events.altar.label .. " " .. cost, GameText.events.altar.intro, "生命 " .. cost, "待结算币 +" .. reward.gold .. " / 异常回收物 x1", GameText.events.altar.risk or "当前生命不足则不可献祭", canOffer, GameText.events.altar.disabled),
        option("leave", GameText.events.altar.leave, "暂不献祭。", "无", "无", "无", true, nil),
    }
end

local function getTrapOptions(ctx)
    return {
        option("disarm", GameText.events.trap.label, "使用战斗力进行一次检定。", "一次检定", "成功: 待结算币 +25 / 回收物 x2", "失败: 生命 -1 / 协议压力 +5", true, nil),
        option("leave", "离开", "不处理机关。", "无", "无", "无", true, nil),
    }
end

function EventSystem.GetOptions(x, y, context)
    local state = EventSystem.GetEventState(x, y)
    local def = state.def
    local title = def and def.name or "事件"
    local desc = state.completed and (def and def.doneMsg or "事件已完成。") or (def and def.enterMsg or "发现事件房。")
    local options = {}
    if state.completed then
        options = { option("leave", "关闭", "事件已完成。", "无", "无", "无", true, nil) }
    elseif state.eventType == "trader" then
        options = getTraderOptions(context or {})
    elseif state.eventType == "dice" then
        options = getDiceOptions(context or {})
    elseif state.eventType == "altar" then
        options = getAltarOptions(context or {}, state.optionState or {})
    elseif state.eventType == "trap" then
        options = getTrapOptions(context or {})
    end
    return { state = state, title = title, description = desc, options = options }
end

function EventSystem.Execute(x, y, context)
    local eventId = EventSystem.GetEventType(x, y)
    local defaultOption = "leave"
    if eventId == "trader" then
        local items = concreteTradables(context or {})
        defaultOption = items[1] and ("sell_item:" .. items[1].itemId) or "leave"
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
        return result(true, "事件交互取消。", { eventType = eventId, optionId = optionId, closePanel = true })
    end
    if EventSystem.completedEvents[key] then
        return result(false, "此处事件已完成。", { eventType = eventId, optionId = optionId })
    end

    local menu = EventSystem.GetOptions(x, y, context or {})
    local selected = nil
    for _, opt in ipairs(menu.options or {}) do
        if opt.id == optionId then
            selected = opt
            break
        end
    end
    if not selected then return result(false, "未知事件选项。", { eventType = eventId, optionId = optionId }) end
    if selected.enabled == false then return result(false, selected.disabledReason or "条件不足。", { eventType = eventId, optionId = optionId }) end

    if eventId == "trader" then return EventSystem._ExecTrader(x, y, context, optionId) end
    if eventId == "dice" then return EventSystem._ExecDice(x, y, context, optionId) end
    if eventId == "altar" then return EventSystem._ExecAltar(x, y, context, optionId) end
    if eventId == "trap" then return EventSystem._ExecTrap(x, y, context, optionId) end
    return result(false, "未知事件类型。", { eventType = eventId, optionId = optionId })
end

function EventSystem._ExecTrader(x, y, ctx, optionId)
    ctx = ctx or {}
    local itemId = optionId and optionId:match("^sell_item:(.+)$")
    if not itemId then return result(false, "未知交易项。", { eventType = "trader", optionId = optionId }) end
    for _, item in ipairs(concreteTradables(ctx)) do
        if item.itemId == itemId and (item.count or 0) > 0 then
            local price = Balance.TraderSaleValue(item.baseValue or item.value)
            EventSystem.MarkCompleted(x, y, optionId)
            return result(true, string.format(GameText.events.trader.success .. "已锁定 +%d。", price), {
                safeGoldDelta = price,
                sellItemId = itemId,
                sellCount = 1,
                completed = true,
                closePanel = true,
                eventType = "trader",
                optionId = optionId,
            })
        end
    end
    return result(false, GameText.events.trader.noItem, { eventType = "trader", optionId = optionId })
end

function EventSystem._ExecDice(x, y, ctx, optionId)
    ctx = ctx or {}
    if optionId ~= "bet_small" then return result(false, "未知下注项。", { eventType = "dice", optionId = optionId }) end
    if (ctx.pendingGold or ctx.gold or 0) < Balance.gambler.bet then
        return result(false, GameText.events.dice.disabled, { eventType = "dice", optionId = optionId })
    end
    local roll = (x * 197 + y * 83 + EventSystem.seed * 59 + (ctx.pendingGold or ctx.gold or 0)) % 6 + 1
    EventSystem.MarkCompleted(x, y, optionId)
    if roll <= Balance.gambler.loseMaxRoll then
        return result(true, string.format(GameText.events.dice.lose, roll), {
            pendingGoldDelta = -Balance.gambler.bet,
            completed = true,
            closePanel = true,
            eventType = "dice",
            optionId = optionId,
        })
    end
    local net = (roll == Balance.gambler.bigWinRoll) and Balance.gambler.bigWinNet or Balance.gambler.smallWinNet
    return result(true, roll == Balance.gambler.bigWinRoll and GameText.events.dice.bigWin or GameText.events.dice.smallWin, {
        pendingGoldDelta = net,
        completed = true,
        closePanel = true,
        eventType = "dice",
        optionId = optionId,
    })
end

function EventSystem._ExecAltar(x, y, ctx, optionId)
    ctx = ctx or {}
    if optionId ~= "offer_hp" then return result(false, "未知祭坛选项。", { eventType = "altar", optionId = optionId }) end
    local key = keyOf(x, y)
    local state = getStoredOptionState(key)
    local step = (state.altarStep or 0) + 1
    local cost = Balance.altar.hpCosts[step]
    if not cost then
        EventSystem.MarkCompleted(x, y, optionId)
        return result(false, GameText.events.altar.maxed, { eventType = "altar", optionId = optionId })
    end
    if (ctx.hp or 0) <= cost then
        return result(false, GameText.events.altar.disabled, { eventType = "altar", optionId = optionId })
    end
    state.altarStep = step
    local reward = Balance.altar.rewards[step] or { gold = 0, itemQuality = "common" }
    local completed = step >= #Balance.altar.hpCosts
    if completed then EventSystem.MarkCompleted(x, y, optionId) end
    return result(true, string.format(GameText.events.altar.success, cost, reward.gold), {
        hpDelta = -cost,
        pendingGoldDelta = reward.gold,
        rewardItemQuality = reward.itemQuality,
        completed = completed,
        closePanel = false,
        eventType = "altar",
        optionId = optionId,
    })
end

local TRAP_POWER_REQ = 8
local TRAP_SUCCESS_GOLD = 25
local TRAP_SUCCESS_PARTS = 2
local TRAP_FAIL_HP = 1

function EventSystem._ExecTrap(x, y, ctx, optionId)
    ctx = ctx or {}
    if optionId ~= "disarm" then return result(false, "未知机关选项。", { eventType = "trap", optionId = optionId }) end
    EventSystem.MarkCompleted(x, y, optionId)
    if (ctx.power or 0) >= TRAP_POWER_REQ then
        return result(true, "机关处理成功: 待结算币 +" .. TRAP_SUCCESS_GOLD .. "，回收物 +" .. TRAP_SUCCESS_PARTS .. "。", {
            pendingGoldDelta = TRAP_SUCCESS_GOLD,
            rewardItems = {
                { quality = "common", count = 1 },
                { quality = "low", count = 1 },
            },
            partsDelta = 0,
            completed = true,
            closePanel = true,
            eventType = "trap",
            optionId = optionId,
        })
    end
    return result(true, "机关失控: 生命 -" .. TRAP_FAIL_HP .. "，协议压力 +5。", {
        hpDelta = -TRAP_FAIL_HP,
        pressureDelta = 5,
        completed = true,
        closePanel = true,
        eventType = "trap",
        optionId = optionId,
    })
end

return EventSystem
