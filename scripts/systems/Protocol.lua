-- ============================================================================
-- Protocol.lua (v0.3)
-- "Five-four-three-two-one" pressure-driven system for extraction runs.
-- Pressure accumulates on first-time exploration of unknown cells.
-- Protocol level drops as pressure rises. At Protocol 1, further exploration
-- of unknown cells costs HP (penalty handled by caller).
-- ============================================================================

local Protocol = {}

-- 当前状态
Protocol.level = 5
Protocol.pressure = 0
Protocol.maxPressure = 100
Protocol.lastChanged = false
Protocol.lastPressureDelta = 0

-- 压力阈值: pressure >= threshold → 对应 level
-- 从高压到低压排列
local THRESHOLDS = {
    { pressure = 80, level = 1 },
    { pressure = 60, level = 2 },
    { pressure = 40, level = 3 },
    { pressure = 20, level = 4 },
    { pressure = 0,  level = 5 },
}

local DESCRIPTIONS = {
    [5] = "稳定",
    [4] = "警戒",
    [3] = "压迫",
    [2] = "封锁",
    [1] = "临界",
}

-- 每次探索未知格增加的基础压力值
local BASE_EXPLORE_PRESSURE = 5

function Protocol.Reset()
    Protocol.level = 5
    Protocol.pressure = 0
    Protocol.lastChanged = false
    Protocol.lastPressureDelta = 0
end

--- 增加压力值(首次探索未知房时调用)
--- @param amount number|nil 压力增量(默认 BASE_EXPLORE_PRESSURE)
--- @return table 包含 level, pressure, changed, penalty 字段
function Protocol.AddPressure(amount)
    amount = tonumber(amount) or BASE_EXPLORE_PRESSURE
    Protocol.lastPressureDelta = amount
    Protocol.pressure = Protocol.pressure + amount
    if Protocol.pressure > Protocol.maxPressure then
        Protocol.pressure = Protocol.maxPressure
    end

    local prevLevel = Protocol.level
    Protocol.level = Protocol._ComputeLevel()
    Protocol.lastChanged = Protocol.level ~= prevLevel

    -- Protocol 1 时继续探索未知房需要付出代价(由调用方处理扣血)
    local penalty = Protocol.level == 1
    return {
        level = Protocol.level,
        pressure = Protocol.pressure,
        changed = Protocol.lastChanged,
        penalty = penalty,
        description = Protocol.GetDescription(),
    }
end

--- 根据当前压力值计算协议等级
function Protocol._ComputeLevel()
    for _, t in ipairs(THRESHOLDS) do
        if Protocol.pressure >= t.pressure then
            return t.level
        end
    end
    return 5
end

--- 获取协议等级描述文字
function Protocol.GetDescription()
    return DESCRIPTIONS[Protocol.level] or "未知"
end

--- 获取HUD显示文字
function Protocol.GetHUDText()
    return "协议: " .. tostring(Protocol.level) .. " / " .. Protocol.GetDescription()
end

--- 获取当前完整状态
function Protocol.GetStatus()
    return {
        level = Protocol.level,
        pressure = Protocol.pressure,
        maxPressure = Protocol.maxPressure,
        changed = Protocol.lastChanged,
        description = Protocol.GetDescription(),
    }
end

--- 获取压力百分比 (0~1)
function Protocol.GetPressureRatio()
    return Protocol.pressure / Protocol.maxPressure
end

--- 兼容旧接口: 基于已探索房间数更新(已废弃,仅保留签名)
function Protocol.UpdateByExploredRooms(exploredRooms)
    -- v0.3 不再使用此方法驱动,改为 AddPressure
    -- 保留空实现避免旧调用报错
end

return Protocol
