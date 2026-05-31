-- ============================================================================
-- Minefield.lua
-- Pure Lua minesweeper field generation and reveal logic.
-- Supports three generation modes:
-- legacy: center spawn, corner exits, guaranteed paths (current demo behavior)
-- normal: random spawn, random hidden exits, no guaranteed path
-- judge: fully manual map layout for stable demo/showcase runs
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

local function clampNumber(value, minValue, maxValue)
    value = tonumber(value) or minValue
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

local function copyExit(exit)
    return {
        id = exit.id,
        x = exit.x,
        y = exit.y,
        randomExit = exit.randomExit == true,
    }
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
    self.mode = config.mode or config.gameMode or "legacy"
    self.manualMap = config.manualMap
    self.mineDensity = tonumber(config.mineDensity) or 0.18
    self.requestedMineCount = config.mineCount
    local defaultSpawnSafeRadius = self.mode == "normal" and 0 or 1
    self.spawnSafeRadius = clampInt(config.spawnSafeRadius or defaultSpawnSafeRadius, 0, 20)
    self.pathWidth = clampInt(config.pathWidth or 0, 0, 20)
    self.maxAttempts = clampInt(config.maxAttempts or 8, 1, 50)
    self.randomExitCount = clampInt(config.randomExitCount or 2, 0, 20)
    self.spawnLocked = config.spawnX ~= nil or config.spawnY ~= nil
    self.expandZeroCells = config.expandZeroCells == true
    local normalMode = self.mode == "normal"
    self.monsterRoomRatio = clampNumber(config.monsterRoomRatio or (normalMode and 0.035 or 0.10), 0, 1)
    self.chestRoomRatio = clampNumber(config.chestRoomRatio or (normalMode and 0.025 or 0.08), 0, 1)
    self.eventRoomRatio = clampNumber(config.eventRoomRatio or (normalMode and 0.018 or 0.05), 0, 1)
    self.minMonsterRooms = clampInt(config.minMonsterRooms or 2, 0, 50)
    self.minChestRooms = clampInt(config.minChestRooms or 2, 0, 50)
    self.minEventRooms = clampInt(config.minEventRooms or 1, 0, 50)
    self.maxMonsterRooms = clampInt(config.maxMonsterRooms or (normalMode and 7 or 200), 0, 200)
    self.maxChestRooms = clampInt(config.maxChestRooms or (normalMode and 5 or 200), 0, 200)
    self.maxEventRooms = clampInt(config.maxEventRooms or (normalMode and 3 or 200), 0, 200)

    self.spawn = {
        x = clampInt(config.spawnX or math.floor((self.width + 1) / 2), 1, self.width),
        y = clampInt(config.spawnY or math.floor((self.height + 1) / 2), 1, self.height),
    }
    if config.exits then
        self.exits = {}
        for _, exit in ipairs(config.exits) do
            table.insert(self.exits, copyExit(exit))
        end
    elseif self.mode == "legacy" then
        self.exits = defaultExits(self.width, self.height)
    else
        self.exits = {}
    end

    self:Generate()
end

function Minefield:Generate()
    if self.manualMap or self.mode == "judge" then
        self.rng = RNG.New(self.seed)
        self.generationAttempt = 1
        self:_GenerateManual()
        self.generated = true
        return true
    end

    local generated = false

    for attempt = 1, self.maxAttempts do
        self.rng = RNG.New(self.seed + attempt * 9973)
        self.generationAttempt = attempt
        if self.mode == "normal" and not self.spawnLocked then
            self:_ChooseRandomSpawn()
        end
        self:_BuildEmptyGrid()
        self:_ReserveCriticalCells()
        self:_PlaceMines()
        self:_AssignSpecialRooms()
        self:_ComputeAdjacency()

        local ok = true
        if self.mode == "legacy" then
            ok = self:HasPathToAllExits()
        end
        if ok then
            generated = true
            break
        end
    end

    self.generated = generated
    return generated
end

function Minefield:_ChooseRandomSpawn()
    self.spawn = {
        x = self.rng:Int(1, self.width),
        y = self.rng:Int(1, self.height),
    }
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
    self.monsterCount = 0
    self.chestCount = 0
    self.eventCount = 0
    self.generatedRandomExitCount = 0

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
                explored = false,   -- 玩家亲自进入过
                cleared = false,    -- 特殊房事件已完成(怪物击杀/宝箱开启等)
            }
        end
    end

    for _, exit in ipairs(self.exits) do
        self:_RegisterExit(exit.id, exit.x, exit.y, exit.randomExit)
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
            if self.mode == "legacy" then
                self:_ReserveRouteTo(exit)
            end
        end
    end
end

function Minefield:_RegisterExit(id, x, y, randomExit)
    if not id or not self:IsInside(x, y) then
        return nil
    end
    local cell = self:GetCell(x, y)
    if not cell then
        return nil
    end
    if cell.mine or cell.spawn then
        return nil
    end
    cell.exitId = id
    cell.roomType = "exit"
    cell.randomExit = randomExit == true
    self.exitLookup[id] = copyCoord(cell)
    return cell
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

function Minefield:_SpecialRoomCount(candidateCount, ratio, minCount, maxCount, remaining)
    local count = math.floor(candidateCount * ratio + 0.5)
    if count < minCount then count = minCount end
    if count > maxCount then count = maxCount end
    if count > remaining then count = math.max(0, remaining) end
    return count
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

    local remaining = #safeCandidates
    local monsterCount = self:_SpecialRoomCount(
        #safeCandidates, self.monsterRoomRatio, self.minMonsterRooms, self.maxMonsterRooms, remaining)
    remaining = remaining - monsterCount

    local chestCount = self:_SpecialRoomCount(
        #safeCandidates, self.chestRoomRatio, self.minChestRooms, self.maxChestRooms, remaining)
    remaining = remaining - chestCount

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

    local eventCount = self:_SpecialRoomCount(
        #safeCandidates, self.eventRoomRatio, self.minEventRooms, self.maxEventRooms, remaining)
    remaining = remaining - eventCount
    for i = 1, eventCount do
        if idx > #safeCandidates then break end
        safeCandidates[idx].roomType = "event"
        idx = idx + 1
    end

    -- 随机撤离房:从剩余候选中选取
    local remainCount = #safeCandidates - idx + 1
    local randomExitCount = self.randomExitCount
    if randomExitCount > remainCount then randomExitCount = math.max(0, remainCount) end

    for i = 1, randomExitCount do
        if idx > #safeCandidates then break end
        local cell = safeCandidates[idx]
        local eid = "random_" .. i
        self:_RegisterExit(eid, cell.x, cell.y, true)
        if self.mode == "normal" then
            table.insert(self.exits, { id = eid, x = cell.x, y = cell.y, randomExit = true })
        end
        idx = idx + 1
    end

    self.monsterCount = monsterCount
    self.chestCount = chestCount
    self.eventCount = eventCount
    self.generatedRandomExitCount = randomExitCount
end

function Minefield:_GenerateManual()
    local manual = self.manualMap or {}
    if manual.width then self.width = clampInt(manual.width, 3, 200) end
    if manual.height then self.height = clampInt(manual.height, 3, 200) end
    if manual.spawn then
        self.spawn = {
            x = clampInt(manual.spawn.x, 1, self.width),
            y = clampInt(manual.spawn.y, 1, self.height),
        }
    end
    self.exits = {}
    self:_BuildEmptyGrid()

    local spawnCell = self:GetCell(self.spawn.x, self.spawn.y)
    if spawnCell then
        spawnCell.spawn = true
        spawnCell.roomType = "normal"
    end

    local function applyMine(point)
        local cell = self:GetCell(point.x, point.y)
        if cell and not cell.spawn then
            cell.mine = true
            cell.roomType = "mine"
            self.mineCount = self.mineCount + 1
        end
    end

    local function applyRoom(point, roomType)
        local cell = self:GetCell(point.x, point.y)
        if cell and not cell.spawn and not cell.mine and not cell.exitId then
            cell.roomType = roomType
            if roomType == "monster" then
                self.monsterCount = self.monsterCount + 1
            elseif roomType == "chest" then
                self.chestCount = self.chestCount + 1
            elseif roomType == "event" then
                self.eventCount = self.eventCount + 1
            end
        end
    end

    for _, point in ipairs(manual.mines or {}) do
        applyMine(point)
    end
    for _, exit in ipairs(manual.exits or {}) do
        local id = exit.id or ("manual_exit_" .. tostring(#self.exits + 1))
        if self:_RegisterExit(id, exit.x, exit.y, exit.randomExit) then
            table.insert(self.exits, { id = id, x = exit.x, y = exit.y, randomExit = exit.randomExit == true })
        end
    end
    for _, point in ipairs(manual.monsters or {}) do
        applyRoom(point, "monster")
    end
    for _, point in ipairs(manual.chests or {}) do
        applyRoom(point, "chest")
    end
    for _, point in ipairs(manual.events or {}) do
        applyRoom(point, "event")
    end
    for _, room in ipairs(manual.rooms or {}) do
        local roomType = room.roomType or room.type or "normal"
        if roomType == "mine" then
            applyMine(room)
        elseif roomType == "exit" then
            local id = room.id or ("manual_exit_" .. tostring(#self.exits + 1))
            if self:_RegisterExit(id, room.x, room.y, room.randomExit) then
                table.insert(self.exits, { id = id, x = room.x, y = room.y, randomExit = room.randomExit == true })
            end
        else
            applyRoom(room, roomType)
        end
    end

    self.targetMineCount = self.mineCount
    self.safeCellCount = self.width * self.height - self.mineCount
    self:_ComputeAdjacency()
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
        table.insert(exits, copyExit(exit))
    end
    return exits
end

function Minefield:GetVisibleExits()
    local exits = {}
    for _, exit in ipairs(self.exits) do
        local view = self:GetCellView(exit.x, exit.y)
        if view and view.exitId then
            table.insert(exits, copyExit(exit))
        end
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
        randomExit = visibleExitId ~= nil and cell.randomExit == true,
        reserved = cell.reserved,
        path = cell.path,
        roomType = cell.revealed and cell.roomType or nil,
        explored = cell.explored,
        cleared = cell.cleared,
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

            if self.expandZeroCells and current.adjacent == 0 and not wasRevealed then
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

-- ============================================================================
-- Cell State API (v0.3 格状态: 未知→已扫描→已探索→已清理)
-- ============================================================================

--- 标记格子为"已探索"(玩家亲自进入). 同时自动 reveal.
--- @return boolean firstTime 是否首次探索(用于协议压力计算)
function Minefield:Explore(x, y)
    local cell = self:GetCell(x, y)
    if not cell then return false end
    if cell.explored then return false end
    cell.explored = true
    -- 探索自动揭示
    if not cell.revealed then
        self:Reveal(x, y)
    end
    return true  -- 首次探索
end

--- 标记格子为"已清理"(特殊房事件完成)
function Minefield:ClearRoom(x, y)
    local cell = self:GetCell(x, y)
    if not cell then return false end
    if cell.cleared then return false end
    cell.cleared = true
    return true
end

--- 检查格子是否已探索
function Minefield:IsExplored(x, y)
    local cell = self:GetCell(x, y)
    return cell ~= nil and cell.explored == true
end

--- 检查格子是否已清理
function Minefield:IsCleared(x, y)
    local cell = self:GetCell(x, y)
    return cell ~= nil and cell.cleared == true
end

--- 获取已探索格数
function Minefield:GetExploredCount()
    local count = 0
    self:ForEachCell(function(cell)
        if cell.explored then count = count + 1 end
    end)
    return count
end

--- 获取格子状态字符串 (供UI显示)
--- @return "unknown"|"scanned"|"explored"|"cleared"
function Minefield:GetCellState(x, y)
    local cell = self:GetCell(x, y)
    if not cell then return "unknown" end
    if cell.cleared then return "cleared" end
    if cell.explored then return "explored" end
    if cell.revealed then return "scanned" end
    return "unknown"
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
