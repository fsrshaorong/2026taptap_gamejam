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
local Combat = require("systems.Combat")
local Tutorial = require("systems.Tutorial")

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

local function testProtocolPressure()
    Protocol.Reset()
    local status = Protocol.GetStatus()
    assertEq(status.level, 5, "protocol should start at level 5")
    assertEq(status.pressure, 0, "protocol should start at 0 pressure")

    -- 每次探索增加 5 压力, 4次 = 20 → level 4
    for i = 1, 4 do
        Protocol.AddPressure()
    end
    assertEq(Protocol.GetStatus().level, 4, "protocol level 4 at pressure 20")
    assertEq(Protocol.GetStatus().pressure, 20, "protocol pressure should be 20 after 4 explores")

    -- 再 4 次 = 40 → level 3
    for i = 1, 4 do
        Protocol.AddPressure()
    end
    assertEq(Protocol.GetStatus().level, 3, "protocol level 3 at pressure 40")

    -- 再 4 次 = 60 → level 2
    for i = 1, 4 do
        Protocol.AddPressure()
    end
    assertEq(Protocol.GetStatus().level, 2, "protocol level 2 at pressure 60")

    -- 再 4 次 = 80 → level 1
    for i = 1, 4 do
        Protocol.AddPressure()
    end
    local result = Protocol.AddPressure()  -- 85, still level 1
    assertEq(Protocol.GetStatus().level, 1, "protocol level 1 at pressure 80+")
    assertTrue(result.penalty, "protocol 1 should report penalty")
end

local function testProtocolPenaltyDamageCanKill()
    Protocol.Reset()
    Combat.Reset()
    Combat.hp = 1

    for i = 1, 16 do
        Protocol.AddPressure()
    end

    local result = Protocol.AddPressure()
    assertTrue(result.penalty, "protocol 1 should report penalty before applying damage")

    local damage = Combat.ApplyDamage(1)
    assertEq(damage.hp, 0, "protocol penalty should clamp hp to zero")
    assertTrue(damage.dead, "protocol penalty damage should report death at zero hp")
    assertTrue(not Combat.IsAlive(), "combat should not be alive at zero hp")
end

local function testCombatHpDeltaClamps()
    Combat.Reset()
    Combat.hp = 2

    local damage = Combat.ApplyHpDelta(-5)
    assertEq(damage.hp, 0, "negative hp delta should clamp at zero")
    assertTrue(damage.dead, "negative hp delta should report death")

    local heal = Combat.ApplyHpDelta(999)
    assertEq(heal.hp, Combat.maxHp, "positive hp delta should clamp at max hp")
    assertTrue(not heal.dead, "healed player should be alive")
end

local function testCellStateExploreAndClear()
    local field = Minefield.New({
        mode = "judge",
        width = 5,
        height = 5,
        manualMap = {
            spawn = { x = 3, y = 3 },
            monsters = { { x = 4, y = 3 } },
            chests = { { x = 2, y = 3 } },
        },
    })

    -- 初始状态: 所有格都未探索
    assertEq(field:GetCellState(3, 3), "unknown", "spawn should start unknown")
    assertEq(field:IsExplored(3, 3), false, "spawn should not be explored initially")

    -- Reveal 只是 scanned, 不是 explored
    field:Reveal(4, 3)
    assertEq(field:GetCellState(4, 3), "scanned", "revealed but not entered should be scanned")
    assertEq(field:IsExplored(4, 3), false, "scanned cell should not be explored")

    -- Explore 标记为 explored
    local first = field:Explore(3, 3)
    assertTrue(first, "first explore should return true")
    assertEq(field:GetCellState(3, 3), "explored", "entered cell should be explored")
    assertTrue(field:IsExplored(3, 3), "IsExplored should return true")

    -- 重复 explore 返回 false
    local second = field:Explore(3, 3)
    assertTrue(not second, "repeated explore should return false")

    -- Explore 未 reveal 过的格子会自动 reveal
    local firstMonster = field:Explore(4, 3)
    assertTrue(firstMonster, "exploring monster room should return true")
    assertEq(field:GetCellState(4, 3), "explored", "monster room should be explored")
    local cell = field:GetCell(4, 3)
    assertTrue(cell.revealed, "explore should auto-reveal")

    -- ClearRoom 标记为 cleared
    local cleared = field:ClearRoom(4, 3)
    assertTrue(cleared, "first clear should return true")
    assertEq(field:GetCellState(4, 3), "cleared", "cleared room should report cleared state")
    assertTrue(field:IsCleared(4, 3), "IsCleared should return true")

    -- 重复 clear 返回 false
    local secondClear = field:ClearRoom(4, 3)
    assertTrue(not secondClear, "repeated clear should return false")

    -- GetExploredCount
    assertEq(field:GetExploredCount(), 2, "explored count should be 2 (spawn + monster)")

    -- PublicCell 包含 explored/cleared 字段
    local view = field:GetCellView(4, 3)
    assertTrue(view.explored, "public cell view should include explored")
    assertTrue(view.cleared, "public cell view should include cleared")
    local view2 = field:GetCellView(2, 3)
    assertTrue(not view2.explored, "unexplored cell should show explored=false in view")
end

local function testZeroExpansionDisabledByDefault()
    -- 默认 expandZeroCells = false, 0邻域格不应连锁展开
    local field = Minefield.New({
        width = 5,
        height = 5,
        mineCount = 0,
        seed = 42,
        spawnSafeRadius = 0,
        pathWidth = 0,
    })

    local result = field:Reveal(1, 1)
    assertTrue(result.ok, "reveal 0-adjacent cell failed")
    assertEq(#result.cells, 1, "0-adjacent reveal should NOT expand (expandZeroCells defaults false)")

    -- 验证只有 (1,1) 被 reveal 了
    assertTrue(field:GetCell(1, 1).revealed, "target cell should be revealed")
    assertTrue(not field:GetCell(2, 1).revealed, "neighbor should NOT be revealed by default")
    assertTrue(not field:GetCell(1, 2).revealed, "neighbor should NOT be revealed by default")
end

local function testTeleportRequiresExplored()
    -- 模拟传送规则: scanned 不可传送, explored 才可
    local field = Minefield.New({
        mode = "judge",
        width = 5,
        height = 5,
        manualMap = {
            spawn = { x = 3, y = 3 },
        },
    })

    -- Reveal (scan) 不等于 explore
    field:Reveal(2, 3)
    assertTrue(not field:IsExplored(2, 3), "scanned cell should not be explorable for teleport")

    -- Explore 后可传送
    field:Explore(2, 3)
    assertTrue(field:IsExplored(2, 3), "explored cell should be valid for teleport")
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

local function testSearchedChestState()
    RunInventory.Reset()
    local field = Minefield.New({
        mode = "judge",
        width = 5,
        height = 5,
        manualMap = {
            spawn = { x = 2, y = 2 },
            chests = {
                { x = 3, y = 2 },
            },
        },
    })
    local run = ExtractionRun.New({
        minefield = field,
        moveRequiresRevealed = false,
        revealOnMove = true,
    })

    local move = run:Move(1, 0)
    assertTrue(move.ok, "move to chest room failed")
    local before = RunInventory.GetSearchState(field, run)
    assertTrue(before.canSearch and before.isChest, "chest should be searchable before search")

    local searched = RunInventory.SearchCurrentRoom(field, run)
    assertTrue(searched.ok, "chest search failed")
    assertTrue(searched.reward.parts >= 1, "chest should grant at least one carried item")
    assertTrue(RunInventory.GetCarriedItemCount() >= 1, "chest search should add carried items")
    local after = RunInventory.GetSearchState(field, run)
    assertTrue(after.searched and after.isChest, "searched chest should keep chest marker")
end

local function testItemDefinitionsReadable()
    local defs = RunInventory.GetAllItemDefs()
    assertTrue(#defs >= 4, "expected several item definitions")
    local def = RunInventory.GetItemDef("broken_copper_wire")
    assertTrue(def ~= nil, "broken copper wire definition missing")
    assertEq(def.name, "断裂铜线", "item display name mismatch")
    assertEq(RunInventory.GetTradableItemDisplayName("broken_copper_wire"), "断裂铜线", "tradable item display name mismatch")
    assertTrue(not RunInventory.HasItemIcon("missing_item"), "missing icon fallback should not crash")
end

local function makeSearchRun(roomType)
    local manualMap = {
        spawn = { x = 2, y = 2 },
    }
    if roomType == "chest" then
        manualMap.chests = { { x = 3, y = 2 } }
    end
    local field = Minefield.New({
        mode = "judge",
        seed = 4,
        width = 5,
        height = 5,
        manualMap = manualMap,
    })
    local run = ExtractionRun.New({
        minefield = field,
        moveRequiresRevealed = false,
        revealOnMove = true,
    })
    local move = run:Move(1, 0)
    assertTrue(move.ok, "move to search room failed")
    return field, run
end

local function testNormalSearchGeneratesCarriedItem()
    RunInventory.Reset()
    local field, run = makeSearchRun("normal")
    local searched = RunInventory.SearchCurrentRoom(field, run)
    assertTrue(searched.ok, "normal search should succeed")
    assertTrue(searched.reward.gold > 0, "normal search should grant gold")
    assertTrue(#searched.reward.items >= 1, "seeded normal search should grant a concrete item")
    assertEq(RunInventory.GetCarriedItemCount(), searched.reward.parts, "carried count should match reward parts")
    assertTrue(RunInventory.GetCarriedItemValue() > 0, "carried items should have value")

    local repeated = RunInventory.SearchCurrentRoom(field, run)
    assertTrue(not repeated.ok, "searched room should not repeat rewards")
    assertEq(repeated.status, "searched", "repeat search should report searched")
    assertEq(RunInventory.GetCarriedItemCount(), searched.reward.parts, "repeat search should not add carried items")
end

local function testChestRewardBeatsNormalSearch()
    RunInventory.Reset()
    local normalField, normalRun = makeSearchRun("normal")
    local normal = RunInventory.SearchCurrentRoom(normalField, normalRun)
    local normalValue = normal.reward.gold + normal.reward.itemValue

    RunInventory.Reset()
    local chestField, chestRun = makeSearchRun("chest")
    local chest = RunInventory.SearchCurrentRoom(chestField, chestRun)
    local chestValue = chest.reward.gold + chest.reward.itemValue

    assertTrue(chest.reward.isChest, "chest reward should be marked")
    assertTrue(chest.reward.parts >= 1, "chest should guarantee carried item")
    assertTrue(chestValue > normalValue, "chest reward should be stronger than normal search")
end

local function testCarriedItemsExtractionNoDuplicateParts()
    RunInventory.Reset()
    local field, run = makeSearchRun("chest")
    local searched = RunInventory.SearchCurrentRoom(field, run)
    assertTrue(searched.ok, "chest search should succeed")
    local reward = RunInventory.GetExtractionReward()
    assertEq(reward.carriedItemCount, RunInventory.parts, "seeded chest should have only item-backed parts")
    assertEq(reward.convertedGold, reward.carriedItemValue, "item-backed parts should not be counted twice")
    assertEq(reward.totalGold, RunInventory.gold + reward.carriedItemValue, "total extraction reward mismatch")
end

local function testFailureSalvageWithCarriedItems()
    RunInventory.Reset()
    RunInventory.gold = 12
    RunInventory.parts = 1
    RunInventory.AddCarriedItem("static_lens", 1, "test")
    local options = RunInventory.GetFailureSalvageOptions()
    assertEq(options.safeGold, 12, "failure should keep direct gold")
    assertEq(options.lostItemCount, 1, "failure should report lost carried item count")
    assertTrue(options.lostItemValue > 0, "failure should report lost carried value")
    local salvage = RunInventory.ApplyFailureSalvage("salvage_part")
    assertEq(salvage.gold, 22, "failure salvage should still support old parts rescue")
end

local function testEventRoomNotSearchable()
    RunInventory.Reset()
    local field = Minefield.New({
        mode = "judge",
        width = 5,
        height = 5,
        manualMap = {
            spawn = { x = 2, y = 2 },
            events = {
                { x = 3, y = 2 },
            },
        },
    })
    local run = ExtractionRun.New({
        minefield = field,
        moveRequiresRevealed = false,
        revealOnMove = true,
    })

    local move = run:Move(1, 0)
    assertTrue(move.ok, "move to event room failed")

    RunInventory.searchedRooms[RunInventory.CellKey(3, 2)] = true
    local state = RunInventory.GetSearchState(field, run)
    assertTrue(not state.canSearch, "event room should not be searchable")
    assertTrue(not state.searched, "event room should not render as searched chest")
    assertEq(state.reason, "event", "event room blocked reason mismatch")

    local searched = RunInventory.SearchCurrentRoom(field, run)
    assertTrue(not searched.ok, "event room search should fail")
    assertEq(searched.status, "event", "event room search status mismatch")
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
        assertTrue(field.monsterCount >= 2 and field.monsterCount <= 7, "normal monster room count out of tuned range")
        assertTrue(field.chestCount >= 2 and field.chestCount <= 5, "normal chest room count out of tuned range")
        assertTrue(field.eventCount >= 1 and field.eventCount <= 3, "normal event room count out of tuned range")
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
            assertTrue(field:GetCellView(exit.x, exit.y).randomExit, "revealed normal exit should keep randomExit marker")
        end

        assertEq(#field:GetVisibleExits(), 2, "revealed normal exits should be visible")

        assertAdjacency(field)
    end
    assertTrue(sawDifferentSpawn, "normal mode should randomize spawn instead of always using center")
end

local function testNormalRunTunedSpecialCounts()
    for seed = 1, 25 do
        local field = Minefield.New({
            mode = "normal",
            width = 10,
            height = 10,
            mineCount = 20,
            spawnSafeRadius = 0,
            pathWidth = 0,
            randomExitCount = 2,
            monsterRoomRatio = 0.10,
            chestRoomRatio = 0.10,
            eventRoomRatio = 0.10,
            minMonsterRooms = 10,
            minChestRooms = 10,
            minEventRooms = 10,
            maxMonsterRooms = 10,
            maxChestRooms = 10,
            maxEventRooms = 10,
            seed = seed,
        })

        assertEq(field.mineCount, 20, "10x10 normal mine count mismatch")
        assertEq(field.monsterCount, 10, "10x10 normal monster room count mismatch")
        assertEq(field.chestCount, 10, "10x10 normal chest room count mismatch")
        assertEq(field.eventCount, 10, "10x10 normal event room count mismatch")
        assertEq(#field:GetExits(), 2, "10x10 normal exit count mismatch")
    end
end

local function testTutorialMapDiagonalLayout()
    local field = Minefield.New(Tutorial.GetMapConfig())

    assertEq(field.width, 5, "tutorial width mismatch")
    assertEq(field.height, 5, "tutorial height mismatch")
    assertEq(field.mineCount, 4, "tutorial mine count mismatch")
    assertEq(field.eventCount, 4, "tutorial event room count mismatch")
    assertEq(field.monsterCount, 5, "tutorial monster room count mismatch")
    assertEq(field.chestCount, 4, "tutorial chest room count mismatch")
    assertEq(#field:GetExits(), 1, "tutorial exit count mismatch")

    local expected = {
        [1] = { "spawn", "normal", "mine", "event", "monster" },
        [2] = { "normal", "mine", "event", "monster", "chest" },
        [3] = { "mine", "event", "monster", "chest", "normal" },
        [4] = { "event", "monster", "chest", "mine", "normal" },
        [5] = { "monster", "chest", "normal", "normal", "exit" },
    }

    for y = 1, 5 do
        for x = 1, 5 do
            local cell = field:GetCell(x, y)
            local want = expected[x][y]
            if want == "spawn" then
                assertTrue(cell.spawn, "tutorial spawn mismatch at " .. x .. "," .. y)
                assertEq(cell.roomType, "normal", "tutorial spawn room type mismatch")
            elseif want == "mine" then
                assertTrue(cell.mine, "tutorial mine missing at " .. x .. "," .. y)
                assertEq(cell.roomType, "mine", "tutorial mine room type mismatch")
            elseif want == "exit" then
                assertEq(cell.exitId, "tutorial_exit", "tutorial exit mismatch at " .. x .. "," .. y)
                assertEq(cell.roomType, "exit", "tutorial exit room type mismatch")
            else
                assertEq(cell.roomType, want, "tutorial room type mismatch at " .. x .. "," .. y)
            end
        end
    end
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
    assertTrue(field:GetCellView(1, 7).randomExit, "judge hidden exit should keep randomExit marker")
    assertAdjacency(field)
end

local function testCombatResultSignals()
    Combat.Reset()
    Combat.power = 12
    Combat.hp = 100
    Combat.enemies["1,1"] = { name = "test enemy", power = 9, alive = true }

    local win = Combat.FightEnemy(1, 1)
    assertTrue(win.fought, "combat should fight alive enemy")
    assertTrue(win.playerWin, "stronger player should win cleanly")
    assertTrue(win.cleared, "combat result should mark room cleared")
    assertEq(win.playerPower, 12, "combat result should include player power")
    assertEq(win.enemyPower, 9, "combat result should include enemy power")
    assertEq(win.damage, 0, "winning combat should not cost hp")
    assertTrue(win.reward and win.reward.gold > 0, "combat result should include gold reward")
    assertEq(win.reward.parts, 0, "low threat combat should not force part reward")
    assertTrue(not Combat.enemies["1,1"].alive, "enemy should be cleared after fight")

    local repeated = Combat.FightEnemy(1, 1)
    assertTrue(not repeated.fought, "cleared enemy should not fight twice")

    Combat.Reset()
    Combat.power = 6
    Combat.hp = 100
    Combat.enemies["2,2"] = { name = "test brute", power = 14, alive = true }

    local costly = Combat.FightEnemy(2, 2)
    assertTrue(costly.fought, "combat should fight stronger enemy")
    assertTrue(not costly.playerWin, "weaker player should pay hp cost")
    assertTrue(costly.cleared, "stronger enemy should still be cleared")
    assertEq(costly.playerPower, 6, "costly combat should include player power")
    assertEq(costly.enemyPower, 14, "costly combat should include enemy power")
    assertEq(costly.damage, 8, "combat damage should be power gap")
    assertEq(costly.hp, 92, "combat hp should reflect damage")
    assertTrue(costly.reward and costly.reward.gold > 0, "costly combat should still pay reward")
end

local function testMonsterActiveCombatLoop()
    Combat.Reset()
    Combat.power = 10
    Combat.enemies["3,3"] = { name = "test anomaly", power = 10, alive = true }

    local tooFar = Combat.PlayerAttackEnemy(3, 3, { x = 0.95, y = 0.95 })
    assertEq(tooFar.status, "too_far", "far player should not hit monster")

    local firstHit = Combat.PlayerAttackEnemy(3, 3, { x = 0.35, y = 0.45 })
    assertTrue(firstHit.ok and firstHit.hit, "close player should hit monster")
    assertEq(firstHit.damage, 10, "monster hit should use player combat power")
    assertTrue(firstHit.enemy.monsterHP < firstHit.enemy.monsterMaxHP, "monster hp should decrease")

    local cooldown = Combat.PlayerAttackEnemy(3, 3, { x = 0.35, y = 0.45 })
    assertEq(cooldown.status, "cooldown", "monster attack should respect player cooldown")

    local killed = nil
    for _ = 1, 8 do
        if not Combat.enemies["3,3"].alive then break end
        Combat.enemies["3,3"].playerAttackCooldown = 0
        killed = Combat.PlayerAttackEnemy(3, 3, { x = 0.35, y = 0.45 })
    end
    assertTrue(killed and killed.killed, "repeated hits should kill monster")
    assertTrue(killed.result and killed.result.reward and killed.result.reward.gold > 0, "killed monster should produce reward result")
    assertTrue(not Combat.enemies["3,3"].alive, "monster should be marked dead after hp reaches zero")
end

local function testMonsterWarningAttackDamage()
    Combat.Reset()
    Combat.hp = 100
    Combat.enemies["4,4"] = { name = "test caster", power = 12, alive = true }
    local enemy = Combat.GetEnemyAny(4, 4)
    enemy.attackPhase = "active"
    enemy.attackTimer = 0.2
    enemy.attackHitResolved = false
    enemy.playerInvincibleTimer = 0

    local hit = Combat.UpdateEnemy(4, 4, 0.01, { x = enemy.monsterPosition.x, y = enemy.monsterPosition.y })
    assertTrue(hit.playerHit, "active warning area should damage player inside range")
    assertEq(hit.damage, enemy.monsterDamage, "monster active hit should use monster damage")
    assertEq(Combat.hp, 100 - enemy.monsterDamage, "monster hit should reduce hp once")

    local noRepeat = Combat.UpdateEnemy(4, 4, 0.01, { x = enemy.monsterPosition.x, y = enemy.monsterPosition.y })
    assertTrue(not noRepeat.playerHit, "monster should not damage every frame during same active attack")

    Combat.Reset()
    Combat.hp = 100
    Combat.enemies["5,5"] = { name = "test caster", power = 12, alive = true }
    local enemy2 = Combat.GetEnemyAny(5, 5)
    enemy2.attackPhase = "active"
    enemy2.attackTimer = 0.2
    enemy2.attackHitResolved = false
    local avoided = Combat.UpdateEnemy(5, 5, 0.01, { x = 0.95, y = 0.95 })
    assertTrue(not avoided.playerHit, "player outside active warning area should avoid damage")
    assertEq(Combat.hp, 100, "avoiding warning area should preserve hp")
end

local function testRunStats()
    RunInventory.Reset()
    local field = Minefield.New({
        mode = "judge",
        width = 5,
        height = 5,
        manualMap = {
            spawn = { x = 2, y = 2 },
            chests = {
                { x = 3, y = 2 },
            },
        },
    })
    local run = ExtractionRun.New({
        minefield = field,
        moveRequiresRevealed = false,
        revealOnMove = true,
    })

    local move = run:Move(1, 0)
    assertTrue(move.ok, "move to chest room failed for stats")
    RunInventory.RecordMove()
    local searched = RunInventory.SearchCurrentRoom(field, run)
    assertTrue(searched.ok, "stats chest search failed")
    RunInventory.RecordMineHit(true)
    RunInventory.RecordCombat({ fought = true, damage = 7 })
    RunInventory.RecordTrade()

    local stats = RunInventory.GetRunStats(run)
    assertEq(stats.moves, 1, "stats should count moves")
    assertEq(stats.searchedRooms, 1, "stats should count searched rooms")
    assertEq(stats.chestRooms, 1, "stats should count chest rooms")
    assertEq(stats.mineHits, 1, "stats should count mine hits")
    assertEq(stats.mineImmunityUsed, 1, "stats should count mine immunity")
    assertEq(stats.monstersDefeated, 1, "stats should count defeated monsters")
    assertEq(stats.combatDamage, 7, "stats should sum combat damage")
    assertEq(stats.trades, 1, "stats should count trades")
    assertEq(stats.turns, 1, "stats should include run turns")
end

local function testCombatRewardInventory()
    RunInventory.Reset()
    RunInventory.RecordCombat({
        fought = true,
        damage = 3,
        reward = { gold = 25, parts = 1 },
    })

    local totals = RunInventory.GetTotals()
    assertEq(totals.gold, 25, "combat reward should add gold")
    assertEq(totals.parts, 1, "combat reward should add parts")

    local stats = RunInventory.GetRunStats(nil)
    assertEq(stats.monstersDefeated, 1, "rewarded combat should still count defeated monster")
    assertEq(stats.combatDamage, 3, "rewarded combat should still count damage")
end

-- ============================================================================
-- EventSystem tests
-- ============================================================================

local EventSystem = require("systems.EventSystem")

local function testEventTypeDeterminism()
    EventSystem.Reset(42)
    local t1 = EventSystem.GetEventType(3, 5)
    local t2 = EventSystem.GetEventType(3, 5)
    assertEq(t1, t2, "same coords same seed should give same event type")

    -- Different coords may give different type (not guaranteed, but reset state)
    EventSystem.Reset(42)
    local t3 = EventSystem.GetEventType(3, 5)
    assertEq(t1, t3, "after reset with same seed, same coord should match")

    -- Different seed should change assignment
    EventSystem.Reset(999)
    -- The type may or may not differ, but the system shouldn't crash
    local t4 = EventSystem.GetEventType(3, 5)
    assert(t4 == "trader" or t4 == "dice" or t4 == "altar" or t4 == "trap",
        "event type must be one of the four valid types")
end

local function testEventCompletedState()
    EventSystem.Reset(100)
    assert(not EventSystem.IsCompleted(1, 1), "should not be completed initially")
    EventSystem.MarkCompleted(1, 1)
    assert(EventSystem.IsCompleted(1, 1), "should be completed after marking")
    assert(not EventSystem.IsCompleted(2, 2), "other coords unaffected")
end

local function testEventExecTrader()
    EventSystem.Reset(50)
    -- Force the assignment to trader by finding a coord that gives "trader"
    -- We'll directly assign for testing
    EventSystem.assignedEvents["10,10"] = "trader"

    -- Not enough parts
    local r1 = EventSystem.Execute(10, 10, { gold = 100, parts = 0, hp = 3, maxHp = 5, tradePrice = 20, power = 5 })
    assert(not r1.ok, "trader should fail with 0 parts")
    assertEq(r1.goldDelta, 0, "no gold change on fail")

    -- Enough parts
    local r2 = EventSystem.Execute(10, 10, { gold = 100, parts = 2, hp = 3, maxHp = 5, tradePrice = 20, power = 5 })
    assert(r2.ok, "trader should succeed with parts")
    assertEq(r2.goldDelta, 20, "should gain tradePrice gold")
    assertEq(r2.partsDelta, -1, "should spend 1 part")
    assertEq(r2.hpDelta, 0, "no hp change for trader")

    -- Already completed
    local r3 = EventSystem.Execute(10, 10, { gold = 100, parts = 2, hp = 3, maxHp = 5, tradePrice = 20, power = 5 })
    assert(not r3.ok, "completed event should fail")

    local state = EventSystem.GetEventState(10, 10)
    assertEq(state.optionState.completedOption, "sell_parts", "completed trader should remember selected option")
end

local function testEventTraderOptionsAndAdapter()
    EventSystem.Reset(51)
    EventSystem.assignedEvents["11,11"] = "trader"

    local tradables = EventSystem.getTradableItems({ parts = 3 })
    assertEq(tradables[1].id, "parts", "virtual tradable should expose parts id")
    assertEq(tradables[1].count, 3, "virtual tradable should expose current parts")
    assertEq(EventSystem.getTradeDisplayName("parts"), "异常回收物", "parts display name mismatch")

    local menu = EventSystem.GetOptions(11, 11, { gold = 0, parts = 0, hp = 100, maxHp = 100, tradePrice = 15, power = 10 })
    assertEq(#menu.options, 5, "trader should expose five options")
    assertTrue(menu.options[1].enabled == false, "sell parts should be disabled without parts")
    assertEq(menu.options[1].disabledReason, "异常回收物不足", "sell disabled reason mismatch")
    assertTrue(menu.options[2].enabled == false, "heal should be disabled at full hp")
    assertEq(menu.options[2].disabledReason, "生命已满", "heal full hp reason mismatch")

    local ok, reason = EventSystem.canExecuteTrade(menu.options[1], menu.state)
    assertTrue(not ok, "canExecuteTrade should reject disabled option")
    assertEq(reason, "异常回收物不足", "canExecuteTrade disabled reason mismatch")
end

local function testEventExecTraderHealFull()
    EventSystem.Reset(52)
    EventSystem.assignedEvents["12,12"] = "trader"

    local full = EventSystem.ExecuteOptionById(12, 12, "heal", { gold = 20, parts = 0, hp = 100, maxHp = 100, tradePrice = 15, power = 10 })
    assertTrue(not full.ok, "trader heal should fail at full hp")
    assertEq(full.msg, "生命已满", "trader heal full hp message mismatch")

    local poor = EventSystem.ExecuteOptionById(12, 12, "heal", { gold = 0, parts = 0, hp = 50, maxHp = 100, tradePrice = 15, power = 10 })
    assertTrue(not poor.ok, "trader heal should fail without gold")
    assertEq(poor.msg, "结算币不足", "trader heal insufficient gold message mismatch")
end

local function testEventExecDice()
    EventSystem.Reset(50)
    EventSystem.assignedEvents["20,20"] = "dice"

    -- Not enough gold
    local r1 = EventSystem.Execute(20, 20, { gold = 5, parts = 1, hp = 3, maxHp = 5, tradePrice = 15, power = 5 })
    assert(not r1.ok, "dice should fail with insufficient gold")

    -- Enough gold - should produce a result (win or lose)
    local r2 = EventSystem.Execute(20, 20, { gold = 50, parts = 1, hp = 3, maxHp = 5, tradePrice = 15, power = 5 })
    assert(r2.ok, "dice should succeed with enough gold")
    assert(r2.goldDelta == 10 or r2.goldDelta == -10, "dice should net +10 (win) or -10 (lose), got: " .. r2.goldDelta)
    assertEq(r2.partsDelta, 0, "dice no parts change")
    assertEq(r2.hpDelta, 0, "dice no hp change")
end

local function testEventExecAltar()
    EventSystem.Reset(50)
    EventSystem.assignedEvents["30,30"] = "altar"

    -- Not enough HP (hp <= cost)
    local r1 = EventSystem.Execute(30, 30, { gold = 10, parts = 0, hp = 1, maxHp = 5, tradePrice = 15, power = 5 })
    assert(not r1.ok, "altar should fail with hp <= cost")

    -- Enough HP
    local r2 = EventSystem.Execute(30, 30, { gold = 10, parts = 0, hp = 3, maxHp = 5, tradePrice = 15, power = 5 })
    assert(r2.ok, "altar should succeed with hp > cost")
    assertEq(r2.hpDelta, -1, "altar costs 1 hp")
    assertEq(r2.goldDelta, 15, "altar gives 15 gold")
    assertEq(r2.partsDelta, 1, "altar gives 1 part")
    assertEq(r2.pressureDelta, 5, "altar should raise pressure")
end

local function testEventExecTrap()
    EventSystem.Reset(50)
    EventSystem.assignedEvents["40,40"] = "trap"

    -- Low power - fail
    local r1 = EventSystem.Execute(40, 40, { gold = 10, parts = 0, hp = 3, maxHp = 5, tradePrice = 15, power = 3 })
    assert(r1.ok, "trap always 'succeeds' (executes), even on fail check")
    assertEq(r1.goldDelta, 0, "trap fail gives no gold")
    assertEq(r1.hpDelta, -1, "trap fail costs 1 hp")
    assertEq(r1.pressureDelta, 5, "trap fail should raise pressure")

    -- Reset for high power test
    EventSystem.Reset(50)
    EventSystem.assignedEvents["40,40"] = "trap"

    -- High power - success
    local r2 = EventSystem.Execute(40, 40, { gold = 10, parts = 0, hp = 3, maxHp = 5, tradePrice = 15, power = 10 })
    assert(r2.ok, "trap should succeed")
    assertEq(r2.goldDelta, 25, "trap success gives 25 gold")
    assertEq(r2.partsDelta, 2, "trap success gives 2 parts")
    assertEq(r2.hpDelta, 0, "trap success no hp cost")
    assertEq(r2.pressureDelta, 0, "trap success should not raise pressure")
end

local function testEventStatsRecordEvent()
    RunInventory.Reset()
    RunInventory.RecordEvent("trader")
    RunInventory.RecordEvent("dice")
    RunInventory.RecordEvent("altar")
    RunInventory.RecordEvent("trap")

    local stats = RunInventory.GetRunStats(nil)
    assertEq(stats.eventsCompleted, 4, "event stats should count all completed events")
    assertEq(stats.trades, 1, "event stats should count trader as trade")
    assertEq(stats.diceEvents, 1, "event stats should count dice")
    assertEq(stats.altarEvents, 1, "event stats should count altar")
    assertEq(stats.trapEvents, 1, "event stats should count trap")
end

local function testEventEnterMessage()
    EventSystem.Reset(77)
    EventSystem.assignedEvents["5,5"] = "dice"

    local msg1 = EventSystem.GetEnterMessage(5, 5)
    assert(msg1:find("赌徒"), "enter message should mention event name")

    EventSystem.MarkCompleted(5, 5)
    local msg2 = EventSystem.GetEnterMessage(5, 5)
    assert(msg2:find("离开"), "done message should indicate event is over")
end

local tests = {
    { name = "generation connectivity", fn = testGenerationConnectivity },
    { name = "normal mode random generation", fn = testNormalModeRandomGeneration },
    { name = "judge mode manual map", fn = testJudgeModeManualMap },
    { name = "zero reveal single cell", fn = testZeroRevealSingleCell },
    { name = "flag and mine reveal", fn = testFlagAndMineReveal },
    { name = "extraction run", fn = testExtractionRun },
    { name = "non-fatal mine room", fn = testNonFatalMineRoom },
    { name = "protocol pressure", fn = testProtocolPressure },
    { name = "protocol penalty damage can kill", fn = testProtocolPenaltyDamageCanKill },
    { name = "combat hp delta clamps", fn = testCombatHpDeltaClamps },
    { name = "cell state explore and clear", fn = testCellStateExploreAndClear },
    { name = "zero expansion disabled by default", fn = testZeroExpansionDisabledByDefault },
    { name = "teleport requires explored", fn = testTeleportRequiresExplored },
    { name = "failure salvage", fn = testFailureSalvage },
    { name = "searched chest state", fn = testSearchedChestState },
    { name = "item definitions readable", fn = testItemDefinitionsReadable },
    { name = "normal search generates carried item", fn = testNormalSearchGeneratesCarriedItem },
    { name = "chest reward beats normal search", fn = testChestRewardBeatsNormalSearch },
    { name = "carried items extraction no duplicate parts", fn = testCarriedItemsExtractionNoDuplicateParts },
    { name = "failure salvage with carried items", fn = testFailureSalvageWithCarriedItems },
    { name = "event room not searchable", fn = testEventRoomNotSearchable },
    { name = "10x10 tuned special counts", fn = testNormalRunTunedSpecialCounts },
    { name = "tutorial map diagonal layout", fn = testTutorialMapDiagonalLayout },
    { name = "combat result signals", fn = testCombatResultSignals },
    { name = "monster active combat loop", fn = testMonsterActiveCombatLoop },
    { name = "monster warning attack damage", fn = testMonsterWarningAttackDamage },
    { name = "run stats", fn = testRunStats },
    { name = "combat reward inventory", fn = testCombatRewardInventory },
    { name = "event type determinism", fn = testEventTypeDeterminism },
    { name = "event completed state", fn = testEventCompletedState },
    { name = "event exec trader", fn = testEventExecTrader },
    { name = "event trader options and adapter", fn = testEventTraderOptionsAndAdapter },
    { name = "event exec trader heal full", fn = testEventExecTraderHealFull },
    { name = "event exec dice", fn = testEventExecDice },
    { name = "event exec altar", fn = testEventExecAltar },
    { name = "event exec trap", fn = testEventExecTrap },
    { name = "event stats record event", fn = testEventStatsRecordEvent },
    { name = "event enter message", fn = testEventEnterMessage },
}

for _, test in ipairs(tests) do
    test.fn()
    print("[PASS] " .. test.name)
end

print("[PASS] minefield selftest complete")
