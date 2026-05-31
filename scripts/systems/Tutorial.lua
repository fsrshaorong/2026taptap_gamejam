-- ============================================================================
-- Tutorial.lua - 新手教程系统
-- 对话式引导，等待玩家操作完成后推进下一步
-- ============================================================================

local GameText = require("systems.GameText")

local Tutorial = {}

-- 教程状态
Tutorial.active = false
Tutorial.stepIndex = 0
Tutorial.waitingForAction = false
Tutorial.dialogVisible = false
Tutorial.completed = false  -- 教程是否已完成过

-- 教程步骤定义
-- type: "dialog" = 纯对话(点击继续), "action" = 等待玩家操作
local tutorialActionByIndex = {
    [3] = { action = "move", subtext = GameText.tutorial.waitMove },
    [9] = { action = "open_map", subtext = GameText.tutorial.waitMap },
    [11] = { action = "flag", subtext = GameText.tutorial.waitFlag },
    [13] = { action = "close_map", subtext = GameText.tutorial.waitCloseMap },
    [14] = { action = "search", subtext = GameText.tutorial.waitSearch },
}

Tutorial.steps = {}
for index, text in ipairs(GameText.tutorial.steps) do
    local actionStep = tutorialActionByIndex[index]
    table.insert(Tutorial.steps, {
        type = actionStep and "action" or "dialog",
        text = text,
        subtext = actionStep and actionStep.subtext or GameText.tutorial.click,
        action = actionStep and actionStep.action or nil,
    })
end

--- 开始教程
function Tutorial.Start()
    Tutorial.active = true
    Tutorial.stepIndex = 1
    Tutorial.waitingForAction = false
    Tutorial.dialogVisible = true
end

--- 获取当前步骤
---@return table|nil
function Tutorial.GetCurrentStep()
    if not Tutorial.active then return nil end
    return Tutorial.steps[Tutorial.stepIndex]
end

--- 推进到下一步
function Tutorial.Advance()
    if not Tutorial.active then return end
    Tutorial.stepIndex = Tutorial.stepIndex + 1
    if Tutorial.stepIndex > #Tutorial.steps then
        -- 教程完成
        Tutorial.active = false
        Tutorial.dialogVisible = false
        Tutorial.completed = true
        return
    end
    local step = Tutorial.steps[Tutorial.stepIndex]
    if step.type == "action" then
        Tutorial.waitingForAction = true
    else
        Tutorial.waitingForAction = false
    end
    Tutorial.dialogVisible = true
end

--- 通知动作完成(由 main.lua 调用)
---@param actionName string "move"|"search"|"open_map"
function Tutorial.NotifyAction(actionName)
    if not Tutorial.active then return end
    if not Tutorial.waitingForAction then return end
    local step = Tutorial.steps[Tutorial.stepIndex]
    if step and step.action == actionName then
        Tutorial.waitingForAction = false
        Tutorial.Advance()
    end
end

--- 处理点击(对话框点击继续)
---@return boolean 是否消耗了点击
function Tutorial.HandleClick()
    if not Tutorial.active then return false end
    if not Tutorial.dialogVisible then return false end
    local step = Tutorial.steps[Tutorial.stepIndex]
    if not step then return false end
    -- 只有 dialog 类型可以点击推进
    if step.type == "dialog" then
        Tutorial.Advance()
        return true
    end
    return false
end

--- 是否正在教程中(用于 main.lua 判断)
function Tutorial.IsActive()
    return Tutorial.active
end

--- 重置教程状态
function Tutorial.Reset()
    Tutorial.active = false
    Tutorial.stepIndex = 0
    Tutorial.waitingForAction = false
    Tutorial.dialogVisible = false
end

--- 教程专用地图配置(5x5小地图,固定布局,安全体验)
---@return table 传给 StartNewGame 的 override 参数
function Tutorial.GetMapConfig()
    return {
        mode = "tutorial",
        width = 5,
        height = 5,
        mineCount = 4,
        spawnSafeRadius = 1,
        pathWidth = 0,
        randomExitCount = 0,
        maxMonsterRooms = 5,
        maxChestRooms = 4,
        maxEventRooms = 4,
        minMonsterRooms = 5,
        minChestRooms = 4,
        minEventRooms = 4,
        mineHitsAreFatal = false,
        revealOnMove = true,
        moveRequiresRevealed = false,
        seed = 777,
        manualMap = {
            width = 5,
            height = 5,
            spawn = { x = 1, y = 1 },
            mines = {
                { x = 1, y = 3 }, { x = 2, y = 2 }, { x = 3, y = 1 },
                { x = 4, y = 4 },
            },
            events = {
                { x = 1, y = 4 }, { x = 2, y = 3 }, { x = 3, y = 2 }, { x = 4, y = 1 },
            },
            monsters = {
                { x = 1, y = 5 }, { x = 2, y = 4 }, { x = 3, y = 3 }, { x = 4, y = 2 }, { x = 5, y = 1 },
            },
            chests = {
                { x = 2, y = 5 }, { x = 3, y = 4 }, { x = 4, y = 3 }, { x = 5, y = 2 },
            },
            exits = {
                { id = "tutorial_exit", x = 5, y = 5 },
            },
        },
    }
end

return Tutorial
