-- ============================================================================
-- Minefield.lua
-- Pure Lua minesweeper field generation and reveal logic.
-- The generator reserves the spawn, four corner exits, and guaranteed paths
-- before placing mines, then validates that every exit remains reachable.
-- ============================================================================

local Minefield = {}
Minefield.__index = Minefield

local DIR4 = {
    { x = 1, y = 0 },
    { x = -1, y = 0 },
    { x = 0, y = 1 },
    { x = 0, y = -1 },
}

local DIR8 = {
    { x = 1, y = 0 },
    { x = -1, y = 0 },
    { x = 0, y = 1 },
    { x = 0, y = -1 },
    { x = 1, y = 1 },
    { x = 1, y = -1 },
    { x = -1, y = 1 },
    { x = -1, y = -1 },
}

local RNG = {}
RNG.__index = RNG

function RNG.New(seed)
    seed = math.floor(tonumber(seed) or 1)
    seed = seed % 2147483647
    if seed <= 0 then
        seed = seed + 2147483646
    end
    return setmetatable({ seed = seed }, RNG)
end

function RNG:Next()
    self.seed = (self.seed * 48271) % 2147483647
    return self.seed / 2147483647
end

function RNG:Int(minValue, maxValue)
    if maxValue <= minValue then
        return minValue
    end
    return minValue + math.floor(self:Next() * (maxValue - minValue + 1))
end

function RNG:Shuffle(items)
    for i = #items, 2, -1 do
        local j = self:Int(1, i)
        items[i], items[j] = items[j], items[i]
    end
end

local function clampInt(value, minValue, maxValue)
    value = math.floor(tonumber(value) or minValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function sign(value)
    if value > 0 then return 1 end
    if value < 0 then return -1 end
    return 0
end

local function keyOf(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function copyCoord(cell)
    return { x = cell.x, y = cell.y }
end

local function defaultExits(width, height)
    return {
        { id = "nw", x = 1, y = 1 },
        { id = "ne", x = width, y = 1 },
        { id = "sw", x = 1, y = height },
        { id = "se", x = width, y = height },
    }
end

function Minefield.New(config)
    local self = setmetatable({}, Minefield)
    self:Init(config or {})
    return self
end

function Minefield:Init(config)
    self.width = clampInt(config.width or 15, 3, 200)
    self.height = clampInt(config.height or 15, 3, 200)
    self.seed = tonumber(config.seed) or os.time()
    self.mineDensity = tonumber(config.mineDensity) or 0.18
    self.requestedMineCount = config.mineCount
    self.spawnSafeRadius = clampInt(config.spawnSafeRadius or 1, 0, 20)
    self.pathWidth = clampInt(config.pathWidth or 0, 0, 20)
    self.maxAttempts = clampInt(config.maxAttempts or 8, 1, 50)

    self.spawn = {
        x = clampInt(config.spawnX or math.floor((self.width + 1) / 2), 1, self.width),
        y = clampInt(config.spawnY or math.floor((self.height + 1) / 2), 1, self.height),
    }
    self.exits = config.exits or defaultExits(self.width, self.height)

    self:Generate()
end

function Minefield:Generate()
    local generated = false

    for attempt = 1, self.maxAttempts do
        self.rng = RNG.New(self.seed + attempt * 9973)
        self.generationAttempt = attempt
        self:_BuildEmptyGrid()
        self:_ReserveCriticalCells()
        self:_PlaceMines()
        self:_AssignSpecialRooms()
        self:_ComputeAdjacency()

        local ok = self:HasPathToAllExits()
        if ok then
            generated = true
            break
        end
    end

    self.generated = generated
    return generated
end

function Minefield:_BuildEmptyGrid()
    self.grid = {}
    self.exitLookup = {}
    self.reservedCount = 0
    self.mineCount = 0
    self.targetMineCount = 0
    self.safeCellCount = self.width * self.height
    self.revealedSafeCount = 0
    self.flaggedCount = 0

    for y = 1, self.height do
        self.grid[y] = {}
        for x = 1, self.width do
            self.grid[y][x] = {
                x = x,
                y = y,
                mine = false,
                revealed = false,
                flagged = false,
                adjacent = 0,
                reserved = false,
                reserveReason = nil,
                path = false,
                spawn = false,
                exitId = nil,
                roomType = "normal",
            }
        end
    end

    for _, exit in ipairs(self.exits) do
        if self:IsInside(exit.x, exit.y) then
            local cell = self:GetCell(exit.x, exit.y)
            cell.exitId = exit.id
            cell.roomType = "exit"
            self.exitLookup[exit.id] = copyCoord(cell)
        end
    end

    local spawnCell = self:GetCell(self.spawn.x, self.spawn.y)
    if spawnCell then
        spawnCell.spawn = true
    end
end

function Minefield:_ReserveCriticalCells()
    self:_ReserveArea(self.spawn.x, self.spawn.y, self.spawnSafeRadius, "spawn")

    for _, exit in ipairs(self.exits) do
        if self:IsInside(exit.x, exit.y) then
            self:_ReserveArea(exit.x, exit.y, 0, "exit")
            self:_ReserveRouteTo(exit)
        end
    end
end

function Minefield:_ReserveCell(x, y, reason, isPath)
    local cell = self:GetCell(x, y)
    if not cell then return end

    if not cell.reserved then
        self.reservedCount = self.reservedCount + 1
    end

    cell.reserved = true
    cell.reserveReason = cell.reserveReason or reason
    if isPath then
        cell.path = true
    end
end

function Minefield:_ReserveArea(cx, cy, radius, reason, isPath)
    for y = cy - radius, cy + radius do
        for x = cx - radius, cx + radius do
            if self:IsInside(x, y) then
                self:_ReserveCell(x, y, reason, isPath)
            end
        end
    end
end

function Minefield:_ReservePathPoint(x, y)
    self:_ReserveArea(x, y, self.pathWidth, "path", true)
end

function Minefield:_ReserveRouteTo(exit)
    local x = self.spawn.x
    local y = self.spawn.y
    local guard = self.width * self.height * 4

    self:_ReservePathPoint(x, y)

    while (x ~= exit.x or y ~= exit.y) and guard > 0 do
        guard = guard - 1

        local canMoveX = x ~= exit.x
        local canMoveY = y ~= exit.y
        local moveX = canMoveX

        if canMoveX and canMoveY then
            moveX = self.rng:Int(0, 1) == 0
        elseif canMoveY then
            moveX = false
        end

        if moveX then
            x = x + sign(exit.x - x)
        else
            y = y + sign(exit.y - y)
        end

        self:_ReservePathPoint(x, y)
    end
end

function Minefield:_PlaceMines()
    local candidates = {}
    for y = 1, self.height do
        for x = 1, self.width do
            local cell = self.grid[y][x]
            if not cell.reserved then
                table.insert(candidates, cell)
            end
        end
    end

    local desired
    if self.requestedMineCount ~= nil then
        desired = math.floor(tonumber(self.requestedMineCount) or 0)
    else
        desired = math.floor(self.width * self.height * self.mineDensity + 0.5)
    end

    if desired < 0 then desired = 0 end
    if desired > #candidates then desired = #candidates end

    self.targetMineCount = desired
    self.rng:Shuffle(candidates)

    for i = 1, desired do
        candidates[i].mine = true
        candidates[i].roomType = "mine"
        self.mineCount = self.mineCount + 1
    end

    self.safeCellCount = self.width * self.height - self.mineCount
end

--- 在安全格中分配特殊房型(怪物房,宝箱房)
--- 怪物房不计入雷数邻接, 所以要在 _ComputeAdjacency 之前调用
function Minefield:_AssignSpecialRooms()
    local safeCandidates = {}
    for y = 1, self.height do
        for x = 1, self.width do
            local cell = self.grid[y][x]
            -- 只选择普通安全格(非雷,非出生,非撤离,非保留路径)
            if not cell.mine and not cell.spawn and not cell.exitId
               and cell.roomType == "normal" and not cell.reserved then
                table.insert(safeCandidates, cell)
            end
        end
    end

    self.rng:Shuffle(safeCandidates)

    -- 怪物房数量:约 10% 的安全非保留格
    local monsterCount = math.floor(#safeCandidates * 0.10 + 0.5)
    if monsterCount < 2 then monsterCount = 2 end
    if monsterCount > #safeCandidates then monsterCount = #safeCandidates end

    -- 宝箱房数量:约 8% 的安全非保留格
    local chestCount = math.floor(#safeCandidates * 0.08 + 0.5)
    if chestCount < 2 then chestCount = 2 end
    if chestCount > (#safeCandidates - monsterCount) then
        chestCount = math.max(0, #safeCandidates - monsterCount)
    end

    local idx = 1
    for i = 1, monsterCount do
        if idx > #safeCandidates then break end
        safeCandidates[idx].roomType = "monster"
        idx = idx + 1
    end
    for i = 1, chestCount do
        if idx > #safeCandidates then break end
        safeCandidates[idx].roomType = "chest"
        idx = idx + 1
    end

    -- 事件房数量:约 5% 的安全非保留格, 至少 1 个
    local eventCount = math.floor(#safeCandidates * 0.05 + 0.5)
    if eventCount < 1 then eventCount = 1 end
    if eventCount > (#safeCandidates - idx + 1) then
        eventCount = math.max(0, #safeCandidates - idx + 1)
    end
    for i = 1, eventCount do
        if idx > #safeCandidates then break end
        safeCandidates[idx].roomType = "event"
        idx = idx + 1
    end

    -- 随机撤离房:1-2个, 从剩余候选中选取
    local remainCount = #safeCandidates - idx + 1
    local randomExitCount = 2
    if remainCount < 2 then randomExitCount = math.max(0, remainCount) end

    for i = 1, randomExitCount do
        if idx > #safeCandidates then break end
        local cell = safeCandidates[idx]
        local eid = "random_" .. i
        cell.roomType = "exit"
        cell.exitId = eid
        cell.randomExit = true  -- 标记为随机撤离房(区别于四角固定撤离)
        self.exitLookup[eid] = { x = cell.x, y = cell.y }
        idx = idx + 1
    end

    self.monsterCount = monsterCount
    self.chestCount = chestCount
    self.randomExitCount = randomExitCount
end

function Minefield:_ComputeAdjacency()
    for y = 1, self.height do
        for x = 1, self.width do
            local cell = self.grid[y][x]
            local count = 0

            for _, dir in ipairs(DIR8) do
                local neighbor = self:GetCell(x + dir.x, y + dir.y)
                -- 只统计真正的地雷(怪物房不计入雷数)
                if neighbor and neighbor.mine then
                    count = count + 1
                end
            end

            cell.adjacent = count
        end
    end
end

function Minefield:IsInside(x, y)
    return x >= 1 and x <= self.width and y >= 1 and y <= self.height
end

function Minefield:GetCell(x, y)
    if not self:IsInside(x, y) then
        return nil
    end
    return self.grid[y][x]
end

function Minefield:GetSpawn()
    return { x = self.spawn.x, y = self.spawn.y }
end

function Minefield:GetExits()
    local exits = {}
    for _, exit in ipairs(self.exits) do
        table.insert(exits, { id = exit.id, x = exit.x, y = exit.y })
    end
    return exits
end

function Minefield:GetExit(exitId)
    local exit = self.exitLookup[exitId]
    if not exit then return nil end
    return { x = exit.x, y = exit.y }
end

function Minefield:ForEachCell(callback)
    for y = 1, self.height do
        for x = 1, self.width do
            callback(self.grid[y][x])
        end
    end
end

function Minefield:_PublicCell(cell, revealMines)
    local visibleMine = cell.mine and (cell.revealed or revealMines)
    local state = "hidden"

    if cell.flagged and not cell.revealed then
        state = "flagged"
    elseif visibleMine then
        state = "mine"
    elseif cell.revealed then
        state = cell.adjacent == 0 and "empty" or "number"
    end

    -- 随机撤离房只在揭开后才显示 exitId(四角固定撤离点始终可见)
    local visibleExitId = cell.exitId
    if cell.randomExit and not cell.revealed then
        visibleExitId = nil
    end

    return {
        x = cell.x,
        y = cell.y,
        state = state,
        mine = visibleMine,
        flagged = cell.flagged,
        revealed = cell.revealed,
        adjacent = cell.revealed and cell.adjacent or nil,
        spawn = cell.spawn,
        exitId = visibleExitId,
        reserved = cell.reserved,
        path = cell.path,
        roomType = cell.revealed and cell.roomType or nil,
    }
end

function Minefield:GetCellView(x, y, revealMines)
    local cell = self:GetCell(x, y)
    if not cell then return nil end
    return self:_PublicCell(cell, revealMines == true)
end

function Minefield:GetVisibleMap(revealMines)
    local rows = {}
    for y = 1, self.height do
        rows[y] = {}
        for x = 1, self.width do
            rows[y][x] = self:GetCellView(x, y, revealMines)
        end
    end
    return rows
end

function Minefield:ToggleFlag(x, y)
    local cell = self:GetCell(x, y)
    if not cell then
        return { ok = false, status = "out_of_bounds" }
    end
    if cell.revealed then
        return { ok = false, status = "already_revealed" }
    end

    cell.flagged = not cell.flagged
    if cell.flagged then
        self.flaggedCount = self.flaggedCount + 1
        return { ok = true, status = "flagged", cell = self:_PublicCell(cell, false) }
    end

    self.flaggedCount = self.flaggedCount - 1
    return { ok = true, status = "unflagged", cell = self:_PublicCell(cell, false) }
end

function Minefield:_RevealCell(cell, result)
    if cell.revealed or cell.flagged then
        return
    end

    cell.revealed = true
    if not cell.mine then
        self.revealedSafeCount = self.revealedSafeCount + 1
    end
    table.insert(result.cells, self:_PublicCell(cell, true))
end

function Minefield:Reveal(x, y)
    local cell = self:GetCell(x, y)
    local result = { ok = false, status = "out_of_bounds", hitMine = false, cells = {} }

    if not cell then
        return result
    end
    if cell.flagged then
        result.status = "flagged"
        return result
    end
    if cell.revealed then
        result.ok = true
        result.status = "already_revealed"
        result.cells = { self:_PublicCell(cell, true) }
        return result
    end
    if cell.mine then
        result.ok = true
        result.status = "hit_mine"
        result.hitMine = true
        self:_RevealCell(cell, result)
        return result
    end

    result.ok = true

    local queue = { cell }
    local queued = { [keyOf(cell.x, cell.y)] = true }
    local index = 1

    while index <= #queue do
        local current = queue[index]
        index = index + 1

        if not current.mine and not current.flagged then
            local wasRevealed = current.revealed
            self:_RevealCell(current, result)

            if current.adjacent == 0 and not wasRevealed then
                for _, dir in ipairs(DIR8) do
                    local neighbor = self:GetCell(current.x + dir.x, current.y + dir.y)
                    if neighbor and not neighbor.mine and not neighbor.flagged and not neighbor.revealed then
                        local key = keyOf(neighbor.x, neighbor.y)
                        if not queued[key] then
                            queued[key] = true
                            table.insert(queue, neighbor)
                        end
                    end
                end
            end
        end
    end

    result.status = #result.cells > 1 and "expanded" or "revealed"
    return result
end

function Minefield:RevealAround(x, y)
    local cell = self:GetCell(x, y)
    local result = { ok = false, status = "out_of_bounds", hitMine = false, cells = {} }

    if not cell then
        return result
    end
    if not cell.revealed or cell.adjacent <= 0 then
        result.status = "not_chordable"
        return result
    end

    local flags = 0
    for _, dir in ipairs(DIR8) do
        local neighbor = self:GetCell(x + dir.x, y + dir.y)
        if neighbor and neighbor.flagged then
            flags = flags + 1
        end
    end

    if flags ~= cell.adjacent then
        result.status = "flag_count_mismatch"
        return result
    end

    result.ok = true
    result.status = "revealed"

    for _, dir in ipairs(DIR8) do
        local neighbor = self:GetCell(x + dir.x, y + dir.y)
        if neighbor and not neighbor.flagged and not neighbor.revealed then
            local reveal = self:Reveal(neighbor.x, neighbor.y)
            if reveal.hitMine then
                result.hitMine = true
                result.status = "hit_mine"
            end
            for _, publicCell in ipairs(reveal.cells) do
                table.insert(result.cells, publicCell)
            end
        end
    end

    if #result.cells > 1 and result.status ~= "hit_mine" then
        result.status = "expanded"
    end

    return result
end

function Minefield:RevealAllMines()
    local cells = {}
    self:ForEachCell(function(cell)
        if cell.mine and not cell.revealed then
            cell.revealed = true
            table.insert(cells, self:_PublicCell(cell, true))
        end
    end)
    return cells
end

function Minefield:IsSolved()
    return self.revealedSafeCount >= self.safeCellCount
end

function Minefield:_ReachableSet()
    local start = self:GetCell(self.spawn.x, self.spawn.y)
    local visited = {}
    local queue = {}

    if not start or start.mine then
        return visited
    end

    queue[1] = start
    visited[keyOf(start.x, start.y)] = true

    local index = 1
    while index <= #queue do
        local current = queue[index]
        index = index + 1

        for _, dir in ipairs(DIR4) do
            local neighbor = self:GetCell(current.x + dir.x, current.y + dir.y)
            if neighbor and not neighbor.mine then
                local key = keyOf(neighbor.x, neighbor.y)
                if not visited[key] then
                    visited[key] = true
                    table.insert(queue, neighbor)
                end
            end
        end
    end

    return visited
end

function Minefield:HasPathToAllExits()
    local visited = self:_ReachableSet()
    local details = {}
    local ok = true

    for _, exit in ipairs(self.exits) do
        local reachable = visited[keyOf(exit.x, exit.y)] == true
        details[exit.id] = reachable
        if not reachable then
            ok = false
        end
    end

    return ok, details
end

function Minefield:FindPathToExit(exitId)
    local exit = self:GetExit(exitId)
    if not exit then
        return nil
    end

    local start = self:GetCell(self.spawn.x, self.spawn.y)
    local targetKey = keyOf(exit.x, exit.y)
    local visited = {}
    local parent = {}
    local nodes = {}
    local queue = {}

    if not start or start.mine then
        return nil
    end

    local startKey = keyOf(start.x, start.y)
    visited[startKey] = true
    nodes[startKey] = copyCoord(start)
    queue[1] = start

    local index = 1
    while index <= #queue do
        local current = queue[index]
        index = index + 1

        local currentKey = keyOf(current.x, current.y)
        if currentKey == targetKey then
            local path = {}
            local walkKey = targetKey
            while walkKey do
                table.insert(path, 1, nodes[walkKey])
                walkKey = parent[walkKey]
            end
            return path
        end

        for _, dir in ipairs(DIR4) do
            local neighbor = self:GetCell(current.x + dir.x, current.y + dir.y)
            if neighbor and not neighbor.mine then
                local neighborKey = keyOf(neighbor.x, neighbor.y)
                if not visited[neighborKey] then
                    visited[neighborKey] = true
                    parent[neighborKey] = currentKey
                    nodes[neighborKey] = copyCoord(neighbor)
                    table.insert(queue, neighbor)
                end
            end
        end
    end

    return nil
end

function Minefield:DebugDump(revealMines)
    local lines = {}
    for y = 1, self.height do
        local chars = {}
        for x = 1, self.width do
            local cell = self.grid[y][x]
            local char = "."
            if cell.spawn then
                char = "S"
            elseif cell.exitId then
                char = "E"
            elseif cell.mine and revealMines then
                char = "*"
            elseif cell.revealed and cell.adjacent > 0 then
                char = tostring(cell.adjacent)
            elseif cell.revealed then
                char = "0"
            elseif cell.flagged then
                char = "F"
            elseif cell.path and revealMines then
                char = "+"
            end
            table.insert(chars, char)
        end
        table.insert(lines, table.concat(chars))
    end
    return table.concat(lines, "\n")
end

return Minefield
