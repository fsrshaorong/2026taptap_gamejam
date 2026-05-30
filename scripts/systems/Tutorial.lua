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
        action = "move",
    },
    {
        type = "dialog",
        text = "左侧的数字表示附近有几个危险房间(地雷).",
        subtext = "这就是扫雷! 数字 = 周围格子中的地雷数量. (点击继续)",
    },
    {
        type = "dialog",
        text = "数字为 0 = 周围全安全. 数字越大, 附近地雷越多, 要小心!",
        subtext = "利用数字推理哪些格子安全, 哪些可能是地雷. (点击继续)",
    },
    {
        type = "dialog",
        text = "如果你怀疑某个房间有地雷, 可以在地图上插旗标记.",
        subtext = "插旗能帮你记住危险位置, 避免误入. (点击继续)",
    },
    {
        type = "action",
        text = "按 M 打开地图, 查看已探索区域.",
        subtext = "[ 等待打开地图... ]",
        action = "open_map",
    },
    {
        type = "dialog",
        text = "这是全局地图! 已探索格子会显示数字.",
        subtext = "点击未探索的格子可以插旗标记! (点击继续)",
    },
    {
        type = "action",
        text = "试试在地图上点击一个格子, 给它插上旗子.",
        subtext = "[ 等待插旗... ]",
        action = "flag",
    },
    {
        type = "dialog",
        text = "插旗成功! 再次点击可以取消旗子.",
        subtext = "旗子帮你标记疑似地雷的房间. (点击继续)",
    },
    {
        type = "action",
        text = "关闭地图继续探索. 按 M 或 ESC 关闭.",
        subtext = "[ 等待关闭地图... ]",
        action = "close_map",
    },
    {
        type = "action",
        text = "看到箱子了吗? 按 F 或点击箱子搜索物资.",
        subtext = "[ 等待搜索... ]",
        action = "search",
    },
    {
        type = "dialog",
        text = "很好! 搜索可以获得金币、零件和装备.",
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
        subtext = "(点击返回主菜单)",
    },
}

for index, text in ipairs(GameText.tutorial.steps) do
    if Tutorial.steps[index] then
        Tutorial.steps[index].text = text
        if Tutorial.steps[index].type == "dialog" then
            Tutorial.steps[index].subtext = GameText.tutorial.click
        end
    end
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
        mode = "judge",
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
