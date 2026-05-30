-- ============================================================================
-- Tutorial.lua - 新手教程系统
-- 对话式引导，等待玩家操作完成后推进下一步
-- ============================================================================

local Tutorial = {}

-- 教程状态
Tutorial.active = false
Tutorial.stepIndex = 0
Tutorial.waitingForAction = false
Tutorial.dialogVisible = false
Tutorial.completed = false  -- 教程是否已完成过

-- 教程步骤定义
-- type: "dialog" = 纯对话(点击继续), "action" = 等待玩家操作
Tutorial.steps = {
    {
        type = "dialog",
        text = "欢迎来到灰尾公司, 新晋回收员.",
        subtext = "(点击继续)",
    },
    {
        type = "dialog",
        text = "你的任务是深入废弃设施, 回收物资后安全撤离.",
        subtext = "(点击继续)",
    },
    {
        type = "action",
        text = "使用 WASD 或方向键移动, 走到门口进入下一个房间.",
        subtext = "[ 等待移动... ]",
        action = "move",  -- 等待玩家移动到另一个房间
    },
    {
        type = "dialog",
        text = "左侧的数字表示附近有几个危险房间(地雷/怪物).",
        subtext = "数字越大越危险, 0 = 周围安全. (点击继续)",
    },
    {
        type = "action",
        text = "看到箱子了吗? 按 F 或点击箱子搜索物资.",
        subtext = "[ 等待搜索... ]",
        action = "search",  -- 等待玩家搜索
    },
    {
        type = "dialog",
        text = "很好! 搜索可以获得金币、零件和装备.",
        subtext = "(点击继续)",
    },
    {
        type = "action",
        text = "按 M 打开地图, 查看已探索区域.",
        subtext = "[ 等待打开地图... ]",
        action = "open_map",  -- 等待玩家打开地图
    },
    {
        type = "dialog",
        text = "地图上可以看到你走过的路线和标记的危险区域.",
        subtext = "(点击继续)",
    },
    {
        type = "dialog",
        text = "遇到异常体(怪物)时, 靠近后按 F 攻击.",
        subtext = "也可以绕路回避. (点击继续)",
    },
    {
        type = "dialog",
        text = "找到撤离点后按 E 撤离. 活着带回物资才算成功!",
        subtext = "(点击继续)",
    },
    {
        type = "dialog",
        text = "警戒协议会随探索深入而降级, 协议越低越危险.",
        subtext = "注意左侧栏的协议等级提示. (点击继续)",
    },
    {
        type = "dialog",
        text = "教程结束! 祝你回收顺利, 平安归来.",
        subtext = "(点击开始正式探索)",
    },
}

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
        mode = "normal",
        width = 5,
        height = 5,
        mineDensity = 0.08,
        mineCount = 2,
        spawnSafeRadius = 1,
        pathWidth = 0,
        randomExitCount = 1,
        monsterRoomRatio = 0.05,
        chestRoomRatio = 0.15,
        eventRoomRatio = 0,
        maxMonsterRooms = 1,
        maxChestRooms = 2,
        maxEventRooms = 0,
        minMonsterRooms = 0,
        minChestRooms = 1,
        minEventRooms = 0,
        mineHitsAreFatal = false,
        revealOnMove = true,
        moveRequiresRevealed = false,
        seed = 777,
    }
end

return Tutorial
