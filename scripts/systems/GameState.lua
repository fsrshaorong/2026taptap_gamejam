-- ============================================================================
-- GameState.lua — 全局游戏状态管理
-- 管理天数,按钮,场景组件状态,玩家选择记录
-- ============================================================================

local GameState = {}

-- 五个按钮定义
GameState.BUTTONS = {
    { id = "stop",    name = "停", desc = "停止机器,水流,灯光旋转,过载状态", color = {220, 60, 60} },
    { id = "reverse", name = "反", desc = "反转水流方向,灯光方向,机械方向", color = {60, 180, 220} },
    { id = "connect", name = "连", desc = "连接电缆,管道,控制节点", color = {60, 220, 100} },
    { id = "cut",     name = "切", desc = "切断线路,隔离危险,断开系统", color = {220, 180, 60} },
    { id = "swap",    name = "换", desc = "交换电池,组件位置,资源归属", color = {180, 100, 220} },
}

-- 场景组件状态枚举
GameState.LIGHTHOUSE_STATE = { OFF = "off", ON = "on", OVERLOAD = "overload" }
GameState.WATERWHEEL_STATE = { FORWARD = "forward", REVERSE = "reverse", STOPPED = "stopped" }
GameState.CABLE_STATE = { DISCONNECTED = "disconnected", MAIN = "main", BACKUP = "backup", BROKEN = "broken" }
GameState.BATTERY_STATE = { FULL = "full", EMPTY = "empty", BROKEN = "broken" }
GameState.VILLAGE_STATE = { SAFE = "safe", DARK = "dark", BURNING = "burning" }
GameState.SEA_STATE = { CALM = "calm", STORM = "storm", LOST = "lost" }

-- 游戏阶段
GameState.PHASE = {
    PLAYING = "playing",         -- 正在操作
    DELETE_CHOOSE = "delete",    -- 选择删除按钮
    DAY_TRANSITION = "transition", -- 天数过渡动画
    ENDING = "ending",           -- 结局
    MENU = "menu",               -- 开始菜单
}

--- 初始化/重置游戏状态
function GameState.Init()
    GameState.day = 1
    GameState.phase = GameState.PHASE.MENU
    GameState.maxDay = 5

    -- 当前可用按钮(true=可用, false=已删除)
    GameState.availableButtons = {
        stop = true,
        reverse = true,
        connect = true,
        cut = true,
        swap = true,
    }

    -- 已删除按钮记录(按顺序)
    GameState.deletedButtons = {}

    -- 场景组件状态
    GameState.components = {
        lighthouse = GameState.LIGHTHOUSE_STATE.OFF,
        waterwheel = GameState.WATERWHEEL_STATE.STOPPED,
        cable = GameState.CABLE_STATE.DISCONNECTED,
        battery = GameState.BATTERY_STATE.FULL,
        village = GameState.VILLAGE_STATE.DARK,
        sea = GameState.SEA_STATE.CALM,
    }

    -- 每天的主要解法记录
    GameState.dayActions = {}

    -- 当天已执行的操作记录(用于当天重置)
    GameState.currentDayActions = {}

    -- 当天开始时的组件快照(用于当天重置)
    GameState.dayStartSnapshot = nil

    -- Day 1 胜利条件:灯塔亮起
    GameState.dayObjective = "点亮灯塔"
    GameState.dayObjectiveComplete = false

    -- 消息日志
    GameState.messages = {}
end

--- 获取当前可用按钮列表
function GameState.GetAvailableButtons()
    local result = {}
    for _, btn in ipairs(GameState.BUTTONS) do
        if GameState.availableButtons[btn.id] then
            table.insert(result, btn)
        end
    end
    return result
end

--- 获取当前天数应有的按钮数量
function GameState.GetExpectedButtonCount()
    return GameState.maxDay - GameState.day + 1
end

--- 删除一个按钮
function GameState.DeleteButton(buttonId)
    if GameState.availableButtons[buttonId] then
        GameState.availableButtons[buttonId] = false
        table.insert(GameState.deletedButtons, buttonId)
        return true
    end
    return false
end

--- 保存当天开始状态(用于重置)
function GameState.SaveDaySnapshot()
    GameState.dayStartSnapshot = {}
    for k, v in pairs(GameState.components) do
        GameState.dayStartSnapshot[k] = v
    end
    GameState.currentDayActions = {}
    GameState.dayObjectiveComplete = false
end

--- 当天重置
function GameState.ResetCurrentDay()
    if GameState.dayStartSnapshot then
        for k, v in pairs(GameState.dayStartSnapshot) do
            GameState.components[k] = v
        end
    end
    GameState.currentDayActions = {}
    GameState.dayObjectiveComplete = false
    GameState.AddMessage("已重置当天状态.")
end

--- 记录一次操作
function GameState.RecordAction(buttonId, targetComponent)
    table.insert(GameState.currentDayActions, {
        button = buttonId,
        target = targetComponent,
        day = GameState.day,
    })
end

--- 添加消息到日志
function GameState.AddMessage(text)
    table.insert(GameState.messages, {
        text = text,
        day = GameState.day,
        time = os.clock(),
    })
    -- 保留最近 10 条
    while #GameState.messages > 10 do
        table.remove(GameState.messages, 1)
    end
end

--- 检查 Day 1 目标是否完成
function GameState.CheckObjective()
    if GameState.day == 1 then
        -- Day 1 目标:灯塔亮起
        if GameState.components.lighthouse == GameState.LIGHTHOUSE_STATE.ON then
            GameState.dayObjectiveComplete = true
        end
    else
        -- 后续天数暂时直接允许完成
        GameState.dayObjectiveComplete = true
    end
    return GameState.dayObjectiveComplete
end

return GameState
