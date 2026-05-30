-- ============================================================================
-- ButtonSystem.lua — 按钮交互逻辑
-- 定义每个按钮对每个场景组件的作用
-- ============================================================================

local GameState = require("systems.GameState")

local ButtonSystem = {}

-- 按钮对组件的作用定义
-- 返回: { result = "描述结果", risk = "描述风险", apply = function() }
local ACTIONS = {}

-- ============================================================================
-- 「停」按钮的作用
-- ============================================================================
ACTIONS.stop = {
    lighthouse = function(state)
        if state.components.lighthouse == "overload" then
            return {
                result = "停止灯塔过载, 灯塔将熄灭.",
                risk = "灯塔熄灭后需要重新启动.",
                apply = function()
                    state.components.lighthouse = "off"
                end,
            }
        elseif state.components.lighthouse == "on" then
            return {
                result = "关闭灯塔.",
                risk = "海面船只可能失去方向.",
                apply = function()
                    state.components.lighthouse = "off"
                end,
            }
        else
            return nil -- 无法操作
        end
    end,
    waterwheel = function(state)
        if state.components.waterwheel ~= "stopped" then
            return {
                result = "停止水车运转.",
                risk = "水车停止后灯塔将失去持续供电.",
                apply = function()
                    state.components.waterwheel = "stopped"
                end,
            }
        end
        return nil
    end,
}

-- ============================================================================
-- 「反」按钮的作用
-- ============================================================================
ACTIONS.reverse = {
    waterwheel = function(state)
        if state.components.waterwheel == "forward" then
            return {
                result = "反转水车方向, 切换供电线路.",
                risk = "反转可能导致备用线路过载.",
                apply = function()
                    state.components.waterwheel = "reverse"
                end,
            }
        elseif state.components.waterwheel == "reverse" then
            return {
                result = "将水车恢复正转.",
                risk = "无明显风险.",
                apply = function()
                    state.components.waterwheel = "forward"
                end,
            }
        elseif state.components.waterwheel == "stopped" then
            return {
                result = "反向启动水车.",
                risk = "反向启动可能导致水流改道.",
                apply = function()
                    state.components.waterwheel = "reverse"
                end,
            }
        end
        return nil
    end,
    lighthouse = function(state)
        if state.components.lighthouse == "on" then
            return {
                result = "反转灯光照射方向(海面↔村庄).",
                risk = "改变照射方向将影响被照亮的区域.",
                apply = function()
                    -- 反转灯光方向的效果会在 Day 转换时体现
                    state._lightDirection = (state._lightDirection == "sea") and "village" or "sea"
                end,
            }
        end
        return nil
    end,
}

-- ============================================================================
-- 「连」按钮的作用
-- ============================================================================
ACTIONS.connect = {
    cable = function(state)
        if state.components.cable == "disconnected" then
            return {
                result = "接通主电缆, 为灯塔供电.",
                risk = "主电缆当前不稳定, 可能留下过载隐患.",
                apply = function()
                    state.components.cable = "main"
                    -- 如果水车在运转, 灯塔亮起
                    if state.components.waterwheel ~= "stopped" then
                        state.components.lighthouse = "on"
                    end
                end,
            }
        elseif state.components.cable == "broken" then
            return {
                result = "修复并连接电缆.",
                risk = "修复后的电缆强度降低.",
                apply = function()
                    state.components.cable = "main"
                    if state.components.waterwheel ~= "stopped" then
                        state.components.lighthouse = "on"
                    end
                end,
            }
        end
        return nil
    end,
    waterwheel = function(state)
        if state.components.waterwheel == "stopped" then
            return {
                result = "连接水车并正向启动.",
                risk = "无明显风险.",
                apply = function()
                    state.components.waterwheel = "forward"
                    -- 如果电缆已连接, 灯塔亮起
                    if state.components.cable == "main" or state.components.cable == "backup" then
                        state.components.lighthouse = "on"
                    end
                end,
            }
        end
        return nil
    end,
}

-- ============================================================================
-- 「切」按钮的作用
-- ============================================================================
ACTIONS.cut = {
    cable = function(state)
        if state.components.cable == "main" or state.components.cable == "backup" then
            return {
                result = "切断当前电缆线路.",
                risk = "切断后灯塔将断电, 村庄可能断电.",
                apply = function()
                    state.components.cable = "disconnected"
                    state.components.lighthouse = "off"
                end,
            }
        end
        return nil
    end,
    lighthouse = function(state)
        if state.components.lighthouse == "overload" then
            return {
                result = "切断灯塔过载线路, 隔离危险.",
                risk = "灯塔熄灭, 但可避免爆炸.",
                apply = function()
                    state.components.lighthouse = "off"
                    state.components.cable = "broken"
                end,
            }
        end
        return nil
    end,
}

-- ============================================================================
-- 「换」按钮的作用
-- ============================================================================
ACTIONS.swap = {
    battery = function(state)
        if state.components.battery == "empty" or state.components.battery == "broken" then
            return {
                result = "更换为备用电池.",
                risk = "备用电池容量有限, 只能维持短时间.",
                apply = function()
                    state.components.battery = "full"
                    -- 如果电缆断开但电池满, 可以临时点亮灯塔
                    if state.components.cable == "disconnected" or state.components.cable == "broken" then
                        state.components.lighthouse = "on"
                    end
                end,
            }
        elseif state.components.battery == "full" then
            return {
                result = "取出当前电池作为备件.",
                risk = "若主电缆也断开, 灯塔将完全断电.",
                apply = function()
                    state.components.battery = "empty"
                    if state.components.cable == "disconnected" or state.components.cable == "broken" then
                        state.components.lighthouse = "off"
                    end
                end,
            }
        end
        return nil
    end,
    cable = function(state)
        if state.components.cable == "main" then
            return {
                result = "切换到备用电缆.",
                risk = "备用线路经过村庄, 可能影响村庄供电.",
                apply = function()
                    state.components.cable = "backup"
                end,
            }
        elseif state.components.cable == "backup" then
            return {
                result = "切换回主电缆.",
                risk = "主电缆可能仍有隐患.",
                apply = function()
                    state.components.cable = "main"
                end,
            }
        end
        return nil
    end,
}

--- 获取按钮对组件的操作预报
---@param buttonId string 按钮 ID
---@param componentId string 组件 ID
---@return table|nil { result, risk, apply }
function ButtonSystem.GetAction(buttonId, componentId)
    local buttonActions = ACTIONS[buttonId]
    if not buttonActions then return nil end

    local actionFn = buttonActions[componentId]
    if not actionFn then return nil end

    return actionFn(GameState)
end

--- 获取按钮可操作的所有组件
---@param buttonId string
---@return table[] { componentId, result, risk }
function ButtonSystem.GetAvailableActions(buttonId)
    local result = {}
    local buttonActions = ACTIONS[buttonId]
    if not buttonActions then return result end

    local componentNames = {
        lighthouse = "灯塔",
        waterwheel = "水车",
        cable = "电缆",
        battery = "电池",
        village = "村庄",
        sea = "海面",
    }

    for compId, actionFn in pairs(buttonActions) do
        local action = actionFn(GameState)
        if action then
            table.insert(result, {
                componentId = compId,
                componentName = componentNames[compId] or compId,
                result = action.result,
                risk = action.risk,
                apply = action.apply,
            })
        end
    end
    return result
end

--- 执行按钮操作
---@param buttonId string
---@param componentId string
---@return boolean 是否执行成功
function ButtonSystem.Execute(buttonId, componentId)
    local action = ButtonSystem.GetAction(buttonId, componentId)
    if not action then
        GameState.AddMessage("当前无法对该组件执行此操作.")
        return false
    end

    action.apply()
    GameState.RecordAction(buttonId, componentId)
    GameState.AddMessage("[" .. buttonId .. "->" .. componentId .. "] " .. action.result)
    GameState.CheckObjective()
    return true
end

--- 获取删除按钮的预报信息
---@param buttonId string
---@return table { dependencies = { {component, reason} }, warnings = string[] }
function ButtonSystem.GetDeleteForecast(buttonId)
    local forecast = { dependencies = {}, warnings = {} }
    local buttonActions = ACTIONS[buttonId]
    if not buttonActions then return forecast end

    local componentNames = {
        lighthouse = "灯塔",
        waterwheel = "水车",
        cable = "电缆",
        battery = "电池",
        village = "村庄",
        sea = "海面",
    }

    for compId, actionFn in pairs(buttonActions) do
        local action = actionFn(GameState)
        if action then
            table.insert(forecast.dependencies, {
                component = componentNames[compId] or compId,
                reason = action.result,
            })
        end
    end

    table.insert(forecast.warnings, "明天新增的故障不会被预报.")
    return forecast
end

return ButtonSystem
