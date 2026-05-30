package.path = table.concat({
    "scripts/?.lua",
    "scripts/?/?.lua",
    "./scripts/?.lua",
    "./scripts/?/?.lua",
}, ";") .. ";" .. package.path

local Minefield = require("systems.Minefield")
local ExtractionRun = require("systems.ExtractionRun")
local Protocol = require("systems.Protocol")
local RunInventory = require("systems.RunInventory")

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
            mode = "legacy",
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

local function testZeroRevealSingleCell()
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
    assertEq(result.status, "revealed", "zero reveal should not auto expand")
    assertEq(#result.cells, 1, "zero reveal should open only the selected cell")
    assertTrue(not field:IsSolved(), "empty board should not be solved by one zero reveal")
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

local function testNonFatalMineRoom()
    local field = Minefield.New({
        width = 5,
        height = 5,
        mineCount = 0,
        seed = 2026,
        spawnSafeRadius = 0,
        pathWidth = 0,
    })
    field:GetCell(4, 3).mine = true
    field.mineCount = 1
    field.safeCellCount = field.width * field.height - field.mineCount
    field:_ComputeAdjacency()

    local run = ExtractionRun.New({
        minefield = field,
        mineHitsAreFatal = false,
        moveRequiresRevealed = false,
        revealOnMove = true,
    })

    local firstHit = run:Move(1, 0)
    assertTrue(firstHit.ok, "non-fatal mine should still move player")
    assertEq(firstHit.status, "hit_mine", "first mine entry should trigger")
    assertTrue(firstHit.mineTriggered, "first mine entry should report triggered")
    assertEq(run.phase, "running", "non-fatal mine should keep run running")
    assertEq(run:GetPlayer().x, 4, "player should enter mine room")

    local back = run:Move(-1, 0)
    assertTrue(back.ok, "leaving triggered mine should work")

    local secondEntry = run:Move(1, 0)
    assertTrue(secondEntry.ok, "re-entering triggered mine should work")
    assertEq(secondEntry.status, "entered_triggered_mine", "triggered mine should not retrigger")
    assertTrue(not secondEntry.mineTriggered, "triggered mine should not report fresh trigger")
end

local function testProtocolProgression()
    Protocol.Reset()
    assertEq(Protocol.GetStatus().level, 5, "protocol should start at level 5")
    assertEq(Protocol.UpdateByExploredRooms(4).level, 4, "protocol level 4 threshold")
    assertEq(Protocol.UpdateByExploredRooms(8).level, 3, "protocol level 3 threshold")
    assertEq(Protocol.UpdateByExploredRooms(12).level, 2, "protocol level 2 threshold")
    assertEq(Protocol.UpdateByExploredRooms(16).level, 1, "protocol level 1 threshold")
end

local function testFailureSalvage()
    RunInventory.Reset()
    RunInventory.gold = 23
    RunInventory.parts = 3

    local options = RunInventory.GetFailureSalvageOptions()
    assertEq(options.safeGold, 23, "failure salvage should keep safe gold")
    assertEq(options.lostParts, 3, "failure salvage should mark all parts as lost")
    assertTrue(options.canSalvagePart, "failure salvage should allow part salvage")
    assertEq(options.salvageBonus, 10, "failure salvage bonus mismatch")

    local accept = RunInventory.ApplyFailureSalvage("accept")
    assertEq(accept.gold, 23, "accept salvage should keep safe gold")
    assertEq(accept.parts, 0, "accept salvage should lose parts")
    assertEq(accept.bonus, 0, "accept salvage should not add bonus")

    local salvaged = RunInventory.ApplyFailureSalvage("salvage_part")
    assertEq(salvaged.gold, 33, "part salvage should add bonus gold")
    assertEq(salvaged.parts, 0, "part salvage should still lose parts")
    assertEq(salvaged.bonus, 10, "part salvage bonus mismatch")
end

local function testNormalModeRandomGeneration()
    local sawDifferentSpawn = false
    for seed = 1, 25 do
        local field = Minefield.New({
            mode = "normal",
            width = 11,
            height = 11,
            mineDensity = 0.18,
            randomExitCount = 2,
            seed = seed,
        })

        local spawn = field:GetSpawn()
        local spawnCell = field:GetCell(spawn.x, spawn.y)
        assertTrue(spawnCell ~= nil, "normal spawn missing for seed " .. seed)
        assertTrue(spawnCell.spawn, "normal spawn flag missing for seed " .. seed)
        assertTrue(not spawnCell.mine, "normal spawn has mine for seed " .. seed)
        assertEq(spawnCell.roomType, "normal", "normal spawn should not overlap special room")

        if spawn.x ~= 6 or spawn.y ~= 6 then
            sawDifferentSpawn = true
        end

        local exits = field:GetExits()
        assertEq(#exits, 2, "normal mode should expose only random exits")
        assertEq(#field:GetVisibleExits(), 0, "normal random exits should not be visible before reveal")
        for _, exit in ipairs(exits) do
            local cell = field:GetCell(exit.x, exit.y)
            assertTrue(cell ~= nil, "normal exit missing cell")
            assertTrue(not cell.mine, "normal exit has mine")
            assertTrue(not cell.spawn, "normal exit overlaps spawn")
            assertEq(cell.roomType, "exit", "normal exit room type mismatch")
            assertTrue(cell.randomExit, "normal exit should be hidden random exit")

            local view = field:GetCellView(exit.x, exit.y)
            assertEq(view.exitId, nil, "unrevealed normal exit should be hidden")

            local reveal = field:Reveal(exit.x, exit.y)
            assertTrue(reveal.ok, "normal exit reveal failed")
            assertEq(field:GetCellView(exit.x, exit.y).exitId, exit.id, "revealed normal exit should become visible")
        end

        assertEq(#field:GetVisibleExits(), 2, "revealed normal exits should be visible")

        assertAdjacency(field)
    end
    assertTrue(sawDifferentSpawn, "normal mode should randomize spawn instead of always using center")
end

local function testJudgeModeManualMap()
    local field = Minefield.New({
        mode = "judge",
        width = 7,
        height = 7,
        manualMap = {
            spawn = { x = 2, y = 2 },
            mines = {
                { x = 1, y = 1 },
                { x = 3, y = 2 },
            },
            exits = {
                { id = "demo_exit", x = 7, y = 7 },
                { id = "demo_hidden_exit", x = 1, y = 7, randomExit = true },
            },
            monsters = {
                { x = 4, y = 4 },
            },
            chests = {
                { x = 5, y = 4 },
            },
            events = {
                { x = 6, y = 4 },
            },
        },
    })

    local spawn = field:GetSpawn()
    assertEq(spawn.x, 2, "judge spawn x mismatch")
    assertEq(spawn.y, 2, "judge spawn y mismatch")
    assertTrue(field:GetCell(2, 2).spawn, "judge spawn flag missing")
    assertTrue(field:GetCell(1, 1).mine, "judge mine missing")
    assertTrue(field:GetCell(3, 2).mine, "judge mine missing")
    assertEq(field.mineCount, 2, "judge mine count mismatch")
    assertEq(field:GetCell(4, 4).roomType, "monster", "judge monster room missing")
    assertEq(field:GetCell(5, 4).roomType, "chest", "judge chest room missing")
    assertEq(field:GetCell(6, 4).roomType, "event", "judge event room missing")
    assertEq(field:GetCell(7, 7).roomType, "exit", "judge exit room missing")
    assertEq(field:GetExits()[1].id, "demo_exit", "judge exit id mismatch")
    assertEq(#field:GetVisibleExits(), 1, "judge hidden exit should start hidden")
    assertEq(field:GetVisibleExits()[1].id, "demo_exit", "judge visible exit mismatch")
    field:Reveal(1, 7)
    assertEq(#field:GetVisibleExits(), 2, "judge hidden exit should become visible after reveal")
    assertAdjacency(field)
end

local tests = {
    { name = "generation connectivity", fn = testGenerationConnectivity },
    { name = "normal mode random generation", fn = testNormalModeRandomGeneration },
    { name = "judge mode manual map", fn = testJudgeModeManualMap },
    { name = "zero reveal single cell", fn = testZeroRevealSingleCell },
    { name = "flag and mine reveal", fn = testFlagAndMineReveal },
    { name = "extraction run", fn = testExtractionRun },
    { name = "non-fatal mine room", fn = testNonFatalMineRoom },
    { name = "protocol progression", fn = testProtocolProgression },
    { name = "failure salvage", fn = testFailureSalvage },
}

for _, test in ipairs(tests) do
    test.fn()
    print("[PASS] " .. test.name)
end

print("[PASS] minefield selftest complete")
