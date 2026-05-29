package.path = table.concat({
    "scripts/?.lua",
    "scripts/?/?.lua",
    "./scripts/?.lua",
    "./scripts/?/?.lua",
}, ";") .. ";" .. package.path

local Minefield = require("systems.Minefield")
local ExtractionRun = require("systems.ExtractionRun")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "assertEq failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "assertTrue failed", 2)
    end
end

local function countAdjacentMines(field, x, y)
    local count = 0
    for yy = y - 1, y + 1 do
        for xx = x - 1, x + 1 do
            if not (xx == x and yy == y) then
                local neighbor = field:GetCell(xx, yy)
                if neighbor and neighbor.mine then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function assertAdjacency(field)
    field:ForEachCell(function(cell)
        assertEq(cell.adjacent, countAdjacentMines(field, cell.x, cell.y), "bad adjacent count at " .. cell.x .. "," .. cell.y)
    end)
end

local function findCell(field, predicate)
    local found = nil
    field:ForEachCell(function(cell)
        if not found and predicate(cell) then
            found = cell
        end
    end)
    return found
end

local function testGenerationConnectivity()
    for seed = 1, 50 do
        local field = Minefield.New({
            width = 15,
            height = 15,
            mineDensity = 0.18,
            seed = seed,
            spawnSafeRadius = 1,
            pathWidth = 1,
        })

        local spawn = field:GetSpawn()
        assertTrue(not field:GetCell(spawn.x, spawn.y).mine, "spawn has mine for seed " .. seed)

        for _, exit in ipairs(field:GetExits()) do
            assertTrue(not field:GetCell(exit.x, exit.y).mine, "exit has mine for seed " .. seed .. ": " .. exit.id)
        end

        local ok, details = field:HasPathToAllExits()
        assertTrue(ok, "exit unreachable for seed " .. seed)
        for id, reachable in pairs(details) do
            assertTrue(reachable, "exit " .. id .. " unreachable for seed " .. seed)
        end

        assertEq(field.mineCount, field.targetMineCount, "mine count mismatch for seed " .. seed)
        assertAdjacency(field)
    end
end

local function testZeroRevealExpansion()
    local field = Minefield.New({
        width = 5,
        height = 5,
        mineCount = 0,
        seed = 123,
        spawnSafeRadius = 1,
        pathWidth = 0,
    })

    local result = field:Reveal(3, 3)
    assertTrue(result.ok, "zero reveal failed")
    assertEq(result.status, "expanded", "zero reveal should expand")
    assertEq(#result.cells, 25, "zero reveal should open whole empty board")
    assertTrue(field:IsSolved(), "empty board should be solved")
end

local function testFlagAndMineReveal()
    local field = Minefield.New({
        width = 9,
        height = 9,
        mineCount = 10,
        seed = 42,
        spawnSafeRadius = 1,
        pathWidth = 0,
    })

    local mine = findCell(field, function(cell) return cell.mine end)
    assertTrue(mine ~= nil, "expected at least one mine")

    local flag = field:ToggleFlag(mine.x, mine.y)
    assertTrue(flag.ok, "flag mine failed")
    assertEq(flag.status, "flagged", "flag status mismatch")

    local blocked = field:Reveal(mine.x, mine.y)
    assertEq(blocked.status, "flagged", "flagged cell should not reveal")

    local unflag = field:ToggleFlag(mine.x, mine.y)
    assertTrue(unflag.ok, "unflag mine failed")
    assertEq(unflag.status, "unflagged", "unflag status mismatch")

    local hit = field:Reveal(mine.x, mine.y)
    assertTrue(hit.ok, "mine reveal should return ok with hit state")
    assertTrue(hit.hitMine, "mine reveal should report hitMine")
    assertEq(hit.status, "hit_mine", "mine reveal status mismatch")
end

local function revealPath(field, path)
    for _, point in ipairs(path) do
        local result = field:Reveal(point.x, point.y)
        assertTrue(result.ok, "path reveal failed at " .. point.x .. "," .. point.y)
        assertTrue(not result.hitMine, "path reveal hit mine at " .. point.x .. "," .. point.y)
    end
end

local function testExtractionRun()
    local run = ExtractionRun.New({
        width = 11,
        height = 11,
        mineDensity = 0.2,
        seed = 777,
        spawnSafeRadius = 1,
        pathWidth = 0,
        moveRequiresRevealed = true,
    })

    local path = run.minefield:FindPathToExit("nw")
    assertTrue(path ~= nil and #path > 1, "expected path to nw exit")
    revealPath(run.minefield, path)

    for i = 2, #path do
        local prev = path[i - 1]
        local nextPoint = path[i]
        local move = run:Move(nextPoint.x - prev.x, nextPoint.y - prev.y)
        assertTrue(move.ok, "move failed at step " .. i .. ": " .. tostring(move.status))
    end

    assertTrue(run:CanExtract(), "player should be at exit")
    local extracted = run:Extract()
    assertTrue(extracted.ok, "extract failed")
    assertEq(extracted.status, "extracted", "extract status mismatch")
    assertEq(extracted.exitId, "nw", "wrong exit id")
end

local tests = {
    { name = "generation connectivity", fn = testGenerationConnectivity },
    { name = "zero reveal expansion", fn = testZeroRevealExpansion },
    { name = "flag and mine reveal", fn = testFlagAndMineReveal },
    { name = "extraction run", fn = testExtractionRun },
}

for _, test in ipairs(tests) do
    test.fn()
    print("[PASS] " .. test.name)
end

print("[PASS] minefield selftest complete")
