-- ============================================================================
-- Protocol.lua
-- Pressure-driven five-level protocol system.
-- ============================================================================

local Balance = require("systems.Balance")
local GameText = require("systems.GameText")

local Protocol = {}

Protocol.level = 5
Protocol.pressure = 0
Protocol.maxPressure = Balance.pressure.max
Protocol.lastChanged = false
Protocol.lastPressureDelta = 0

local THRESHOLDS = Balance.pressure.thresholds
local BASE_EXPLORE_PRESSURE = Balance.pressure.explore

function Protocol.Reset()
    Protocol.level = 5
    Protocol.pressure = 0
    Protocol.maxPressure = Balance.pressure.max
    Protocol.lastChanged = false
    Protocol.lastPressureDelta = 0
end

function Protocol.AddPressure(amount)
    amount = tonumber(amount) or BASE_EXPLORE_PRESSURE
    Protocol.lastPressureDelta = amount
    Protocol.pressure = Balance.Clamp(Protocol.pressure + amount, Balance.pressure.min, Protocol.maxPressure)

    local prevLevel = Protocol.level
    Protocol.level = Protocol._ComputeLevel()
    Protocol.lastChanged = Protocol.level ~= prevLevel

    return {
        level = Protocol.level,
        pressure = Protocol.pressure,
        changed = Protocol.lastChanged,
        penalty = false,
        description = Protocol.GetDescription(),
    }
end

function Protocol._ComputeLevel()
    for _, t in ipairs(THRESHOLDS) do
        if Protocol.pressure >= t.pressure then
            return t.level
        end
    end
    return 5
end

function Protocol.GetDescription()
    local text = GameText.protocol.levels[Protocol.level]
    return (text and text.short) or "未知"
end

function Protocol.GetHUDText()
    return "撤离协议: " .. tostring(Protocol.level) .. " / " .. Protocol.GetDescription()
end

function Protocol.GetStatus()
    return {
        level = Protocol.level,
        pressure = Protocol.pressure,
        maxPressure = Protocol.maxPressure,
        changed = Protocol.lastChanged,
        description = Protocol.GetDescription(),
    }
end

function Protocol.GetPressureRatio()
    if Protocol.maxPressure <= 0 then return 0 end
    return Protocol.pressure / Protocol.maxPressure
end

function Protocol.UpdateByExploredRooms(exploredRooms)
    -- Compatibility shim. Pressure is now updated by AddPressure on first entry.
end

return Protocol
