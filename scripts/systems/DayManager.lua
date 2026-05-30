-- ============================================================================
-- DayManager.lua — 天数切换与后果生成
-- 管理 Day 切换逻辑,根据前一天操作生成后果
-- ============================================================================

local GameState = require("systems.GameState")

local DayManager = {}

--- 开始新的一天
function DayManager.StartDay()
    GameState.SaveDaySnapshot()
    GameState.dayObjectiveComplete = false

    local day = GameState.day
    if day == 1 then
        GameState.dayObjective = "点亮灯塔"
        GameState.AddMessage("【第1天】清晨, 灯塔熄灭了.你需要重新点亮它.")
        -- Day 1 初始状态:水车正转但电缆断开
        GameState.components.waterwheel = "forward"
        GameState.components.cable = "disconnected"
        GameState.components.lighthouse = "off"
        GameState.components.battery = "full"
        GameState.components.village = "dark"
        GameState.components.sea = "calm"
    elseif day == 2 then
        GameState.dayObjective = "稳定系统"
        DayManager.GenerateDay2Consequences()
    elseif day == 3 then
        GameState.dayObjective = "保护目标"
        DayManager.GenerateDay3Consequences()
    elseif day == 4 then
        GameState.dayObjective = "固定方向"
        DayManager.GenerateDay4Consequences()
    elseif day == 5 then
        GameState.dayObjective = "最终决定"
        DayManager.GenerateDay5Consequences()
    end

    GameState.SaveDaySnapshot()
end

--- 推进到下一天
function DayManager.AdvanceDay()
    -- 记录当天主要解法
    if #GameState.currentDayActions > 0 then
        GameState.dayActions[GameState.day] = GameState.currentDayActions[1].button
    end

    GameState.day = GameState.day + 1

    if GameState.day > GameState.maxDay then
        GameState.phase = GameState.PHASE.ENDING
        return
    end

    DayManager.StartDay()
    GameState.phase = GameState.PHASE.PLAYING
end

--- Day 2 后果生成
function DayManager.GenerateDay2Consequences()
    local method = GameState.dayActions[1]
    GameState.AddMessage("【第2天】阴天.昨天的操作留下了痕迹...")

    if method == "connect" then
        GameState.AddMessage("主电缆出现漏电迹象.")
        -- 主电缆不稳定, 可能过载
        if GameState.components.cable == "main" then
            GameState.components.lighthouse = "overload"
        end
    elseif method == "cut" then
        GameState.AddMessage("村庄局部区域断电.")
        GameState.components.village = "dark"
    elseif method == "reverse" then
        GameState.AddMessage("水流改道, 水车效率降低.")
        GameState.components.waterwheel = "reverse"
    elseif method == "stop" then
        GameState.AddMessage("机器卡死, 需要重新启动.")
        GameState.components.waterwheel = "stopped"
    elseif method == "swap" then
        GameState.AddMessage("备用电池已耗尽.")
        GameState.components.battery = "empty"
    else
        GameState.AddMessage("系统运转正常, 但有轻微异响.")
    end
end

--- Day 3 后果生成
function DayManager.GenerateDay3Consequences()
    GameState.AddMessage("【第3天】暴雨来袭.多个系统出现问题.")
    GameState.components.sea = "storm"

    -- 暴雨加剧已有问题
    if GameState.components.cable == "broken" or GameState.components.cable == "disconnected" then
        GameState.components.village = "dark"
        GameState.AddMessage("村庄完全断电, 一片漆黑.")
    end
    if GameState.components.lighthouse == "overload" then
        GameState.components.lighthouse = "off"
        GameState.components.cable = "broken"
        GameState.AddMessage("灯塔过载烧毁了主电缆!")
    end
    if GameState.components.sea == "storm" then
        GameState.AddMessage("海面出现船只求救信号!")
    end
end

--- Day 4 后果生成
function DayManager.GenerateDay4Consequences()
    GameState.AddMessage("【第4天】夜幕降临.你只剩2个按钮.")

    if GameState.components.sea == "storm" then
        GameState.components.sea = "lost"
        GameState.AddMessage("船只在风暴中迷失了方向...")
    end
    if GameState.components.village == "dark" then
        GameState.AddMessage("村庄持续断电, 有火灾隐患.")
    end
end

--- Day 5 后果生成
function DayManager.GenerateDay5Consequences()
    GameState.AddMessage("【第5天】黎明前最黑暗的时刻.你只剩最后一个按钮.")

    if GameState.components.village == "dark" then
        GameState.components.village = "burning"
        GameState.AddMessage("村庄起火了!")
    end
    if GameState.components.sea == "lost" then
        GameState.AddMessage("船只即将沉没...")
    end
end

--- 获取结局类型
function DayManager.GetEnding()
    local lastButton = nil
    local available = GameState.GetAvailableButtons()
    if #available > 0 then
        lastButton = available[1].id
    end

    local ending = {
        button = lastButton,
        title = "",
        description = "",
    }

    if lastButton == "connect" then
        ending.title = "连接"
        ending.description = "你将灯塔与村庄的最后电力连接在一起.微弱的光芒同时照亮了海面和村庄.不够亮, 但足够被看见."
    elseif lastButton == "cut" then
        ending.title = "切断"
        ending.description = "你切断了灯塔与过载系统的连接.灯塔熄灭了, 但爆炸的危险消除.村庄在黑暗中安静地等待黎明."
    elseif lastButton == "reverse" then
        ending.title = "反转"
        ending.description = "你反转了灯光的方向.光芒不再照向大海, 而是照向了内陆.有人会被遗忘, 有人会被拯救."
    elseif lastButton == "stop" then
        ending.title = "停止"
        ending.description = "你停下了一切.灯塔,水车,所有机器都安静下来.在寂静中, 你听到了远处的引擎声——救援来了."
    elseif lastButton == "swap" then
        ending.title = "交换"
        ending.description = "你交换了被照亮和被遗忘的对象.谁被拯救, 谁被牺牲, 在最后一刻被你重新定义."
    else
        ending.title = "沉默"
        ending.description = "没有按钮可按.你只能看着这一切发生."
    end

    return ending
end

return DayManager
