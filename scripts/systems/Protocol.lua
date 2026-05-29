-- ============================================================================
-- Protocol.lua
-- "Five-four-three-two-one" pressure meter for a single extraction run.
-- Progress is driven by unique explored rooms, keeping minesweeper reasoning
-- free from real-time pressure.
-- ============================================================================

local Protocol = {}

Protocol.level = 5
Protocol.exploredRooms = 0
Protocol.lastChanged = false

local THRESHOLDS = {
    { rooms = 16, level = 1 },
    { rooms = 12, level = 2 },
    { rooms = 8, level = 3 },
    { rooms = 4, level = 4 },
    { rooms = 0, level = 5 },
}

local DESCRIPTIONS = {
    [5] = "稳定",
    [4] = "警戒",
    [3] = "压迫",
    [2] = "封锁",
    [1] = "临界",
}

function Protocol.Reset()
    Protocol.level = 5
    Protocol.exploredRooms = 0
    Protocol.lastChanged = false
end

function Protocol.GetLevelForExploredRooms(exploredRooms)
    local rooms = math.max(0, math.floor(tonumber(exploredRooms) or 0))
    for _, threshold in ipairs(THRESHOLDS) do
        if rooms >= threshold.rooms then
            return threshold.level
        end
    end
    return 5
end

function Protocol.UpdateByExploredRooms(exploredRooms)
    Protocol.exploredRooms = math.max(0, math.floor(tonumber(exploredRooms) or 0))

    local nextLevel = Protocol.GetLevelForExploredRooms(Protocol.exploredRooms)
    Protocol.lastChanged = nextLevel ~= Protocol.level
    Protocol.level = nextLevel

    return {
        level = Protocol.level,
        exploredRooms = Protocol.exploredRooms,
        changed = Protocol.lastChanged,
        description = Protocol.GetDescription(),
    }
end

function Protocol.GetDescription()
    return DESCRIPTIONS[Protocol.level] or "未知"
end

function Protocol.GetHUDText()
    return "协议: " .. tostring(Protocol.level) .. " / " .. Protocol.GetDescription()
end

function Protocol.GetStatus()
    return {
        level = Protocol.level,
        exploredRooms = Protocol.exploredRooms,
        changed = Protocol.lastChanged,
        description = Protocol.GetDescription(),
    }
end

return Protocol
