package.path = table.concat({
    "scripts/?.lua",
    "scripts/?/?.lua",
    "./scripts/?.lua",
    "./scripts/?/?.lua",
}, ";") .. ";" .. package.path

local Minefield = require("systems.Minefield")
local ExtractionRun = require("systems.ExtractionRun")
local Protocol = require("systems.Protocol")
local Balance = require("systems.Balance")
local RunInventory = require("systems.RunInventory")
local Combat = require("systems.Combat")
local Tutorial = require("systems.Tutorial")
local MetaProgress = require("systems.MetaProgress")
local UILayout = require("ui.UILayout")
local UITheme = require("ui.UITheme")
local HUD = require("ui.HUD")

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

local function withMetaProgressMock(saved, fn)
    local oldFileSystem = fileSystem
    local oldFile = File
    local oldCjson = cjson
    local writes = {}

    fileSystem = {
        FileExists = function(_, _)
            return saved ~= nil
        end,
    }
    cjson = {
        decode = function(_)
            return saved
        end,
        encode = function(value)
            writes.last = value
            return "encoded"
        end,
    }
    File = function(_, _)
        return {
            IsOpen = function() return true end,
            ReadString = function() return "{}" end,
            WriteString = function(_, text) writes.text = text end,
            Close = function() end,
        }
    end

    local ok, err = pcall(fn, writes)
    fileSystem = oldFileSystem
    File = oldFile
    cjson = oldCjson
    if not ok then
        error(err, 0)
    end
    return writes
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
    for i = 1, 10 do
        Protocol.AddPressure()
    end
    assertEq(Protocol.GetStatus().level, 4, "protocol level 4 at pressure 20")
    assertEq(Protocol.GetStatus().pressure, 20, "protocol pressure should be 20 after 10 explores")

    -- 再 4 次 = 40 → level 3
    for i = 1, 10 do
        Protocol.AddPressure()
    end
    assertEq(Protocol.GetStatus().level, 3, "protocol level 3 at pressure 40")

    -- 再 4 次 = 60 → level 2
    for i = 1, 10 do
        Protocol.AddPressure()
    end
    assertEq(Protocol.GetStatus().level, 2, "protocol level 2 at pressure 60")

    -- 再 4 次 = 80 → level 1
    for i = 1, 10 do
        Protocol.AddPressure()
    end
    local result = Protocol.AddPressure()
    assertEq(Protocol.GetStatus().level, 1, "protocol level 1 at pressure 80+")
    assertTrue(not result.penalty, "protocol 1 should not apply extra HP penalty")
end

local function testProtocolPenaltyDamageCanKill()
    Protocol.Reset()
    Combat.Reset()
    Combat.hp = 1

    for i = 1, 40 do
        Protocol.AddPressure()
    end

    local result = Protocol.AddPressure()
    assertTrue(not result.penalty, "protocol 1 should not report penalty")

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

local function testV03BalanceCombatRules()
    Combat.Reset()
    local mine = Combat.TakeMineHit()
    assertEq(mine.damage, Balance.mineDamage, "mine damage should come from Balance")

    Combat.Reset()
    local powerBefore = Combat.power
    local powerUp = Combat.TryPowerUp({ seed = 1 }, 1, 1)
    assertEq(powerUp, 0, "normal search should not grant attack power")
    assertEq(Combat.power, powerBefore, "normal search should not change combat power")

    local gained = 0
    for _ = 1, 8 do
        gained = gained + Combat.GrantMonsterKillPower({ fought = true, dead = false, enemy = {} })
    end
    assertEq(gained, Balance.monster.powerGainCap, "monster kill power gain should cap per run")
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
    RunInventory.pendingGold = 23
    RunInventory.safeGold = 7
    RunInventory.gold = RunInventory.pendingGold
    RunInventory.parts = 3

    local options = RunInventory.GetFailureSalvageOptions()
    assertEq(options.safeGold, 7, "failure salvage should keep only safe gold")
    assertEq(options.pendingGoldLost, 23, "failure salvage should lose pending gold")
    assertEq(options.lostParts, 3, "failure salvage should mark all parts as lost")
    assertTrue(not options.canSalvagePart, "failure salvage should not use old part salvage")
    assertEq(options.salvageBonus, 0, "failure salvage bonus should be removed")

    local accept = RunInventory.ApplyFailureSalvage("accept")
    assertEq(accept.gold, 7, "accept salvage should keep safe gold")
    assertEq(accept.parts, 0, "accept salvage should lose parts")
    assertEq(accept.bonus, 0, "accept salvage should not add bonus")

    local salvaged = RunInventory.ApplyFailureSalvage("salvage_part")
    assertEq(salvaged.gold, 7, "part salvage should not add bonus gold")
    assertEq(salvaged.parts, 0, "part salvage should still lose parts")
    assertEq(salvaged.bonus, 0, "part salvage bonus mismatch")
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
    assertTrue(searched.reward.gold >= 0 and searched.reward.gold <= 4, "normal search gold should use tuned 0-4 range")
    assertEq(RunInventory.pendingGold, searched.reward.gold, "normal search should add pending gold")
    assertEq(RunInventory.GetCarriedItemCount(), searched.reward.parts, "carried count should match reward parts")
    if searched.reward.parts > 0 then
        assertTrue(RunInventory.GetCarriedItemValue() > 0, "carried items should have value")
    end

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
    assertEq(reward.looseParts, 0, "item-backed parts should not be loose")
    assertEq(reward.convertedGold, 0, "carried items should not auto-convert to gold")
    assertEq(reward.totalGold, RunInventory.pendingGold + RunInventory.safeGold, "total extraction reward should include pending and safe gold")
end

local function testFailureSalvageWithCarriedItems()
    RunInventory.Reset()
    RunInventory.pendingGold = 12
    RunInventory.safeGold = 5
    RunInventory.gold = RunInventory.pendingGold
    RunInventory.parts = 1
    RunInventory.AddCarriedItem("static_lens", 1, "test")
    local options = RunInventory.GetFailureSalvageOptions()
    assertEq(options.safeGold, 5, "failure should keep only safe gold")
    assertEq(options.pendingGoldLost, 12, "failure should lose pending gold")
    assertEq(options.lostItemCount, 1, "failure should report lost carried item count")
    assertTrue(options.lostItemValue > 0, "failure should report lost carried value")
    local salvage = RunInventory.ApplyFailureSalvage("salvage_part")
    assertEq(salvage.gold, 5, "failure salvage should not add old parts rescue")
    assertTrue(salvage.salvagedItem ~= nil, "failure should auto keep highest value item")
end

local function testTradableLoosePartsOnly()
    RunInventory.Reset()
    RunInventory.parts = 1
    RunInventory.AddCarriedItem("static_lens", 1, "test")
    assertEq(RunInventory.GetLooseParts(), 0, "item-backed parts should not be loose")
    assertEq(RunInventory.GetTradableItemCount("parts"), 0, "trader should not see item-backed parts as virtual parts")

    local removed = RunInventory.RemoveTradableItem("parts", 1)
    assertTrue(not removed, "virtual parts sale should fail when only carried items exist")
    assertEq(RunInventory.GetCarriedItemCount(), 1, "failed virtual sale should keep carried item")

    RunInventory.parts = 2
    assertEq(RunInventory.GetLooseParts(), 1, "extra part should be loose")
    local ok = RunInventory.RemoveTradableItem("parts", 1)
    assertTrue(ok, "virtual parts sale should consume loose part")
    assertEq(RunInventory.parts, 1, "virtual parts sale should leave item-backed part")
    assertEq(RunInventory.GetCarriedItemCount(), 1, "virtual parts sale should not remove concrete item")
end

local function testRemoveConcreteTradableSettlementSafe()
    RunInventory.Reset()
    RunInventory.parts = 1
    RunInventory.AddCarriedItem("static_lens", 1, "test")
    local ok = RunInventory.RemoveTradableItem("static_lens", 1)
    assertTrue(ok, "concrete tradable removal should succeed")
    assertEq(RunInventory.parts, 0, "concrete item removal should also remove its item-backed part")
    assertEq(RunInventory.GetCarriedItemCount(), 0, "concrete item should be removed")
    local reward = RunInventory.GetExtractionReward()
    assertEq(reward.convertedGold, 0, "removed concrete item should not convert on extraction")
end

local function testMetaProgressLoadRecoveryDefaults()
    withMetaProgressMock({
        gold = 7,
        unlockedTalents = {},
        ownedItems = {},
        equippedItems = {},
        stats = { totalRuns = 2, totalExtractions = 1, totalGoldEarned = 30 },
    }, function()
        MetaProgress.Load()
        local recovery = MetaProgress.GetRecoverySummary()
        local warehouse = MetaProgress.GetWarehouseSummary()
        assertEq(MetaProgress.GetGold(), 7, "old save should keep gold")
        assertEq(recovery.totalItems, 0, "old save should default recovery totalItems")
        assertEq(recovery.totalValue, 0, "old save should default recovery totalValue")
        assertEq(#recovery.recentItems, 0, "old save should default empty recent items")
        assertEq(warehouse.totalItems, 0, "old save should default empty warehouse")
    end)
end

local function testMetaProgressRecordExtractionRecovery()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        local reward = {
            totalGold = 15,
            directGold = 11,
            loosePartsGold = 4,
            carriedItemCount = 2,
            carriedItemValue = 34,
            carriedItems = {
                {
                    itemId = "static_lens",
                    count = 1,
                    def = RunInventory.GetItemDef("static_lens"),
                },
                {
                    itemId = "blackbox_tag",
                    count = 1,
                    def = RunInventory.GetItemDef("blackbox_tag"),
                },
            },
        }
        local receipt = MetaProgress.RecordExtractionReward(reward, { searchedRooms = 2 })
        assertEq(receipt.goldAdded, 15, "receipt should record only direct gold and loose parts gold")
        assertEq(receipt.directGold, 11, "receipt should keep direct gold")
        assertEq(receipt.loosePartsGold, 4, "receipt should keep loose parts gold")
        assertEq(MetaProgress.GetGold(), 15, "carried items should not auto-add meta gold")
        local stats = MetaProgress.GetStats()
        assertEq(stats.totalExtractions, 1, "extraction reward should count extraction")
        assertEq(stats.totalGoldEarned, 15, "extraction reward should count earned gold")
        local recovery = MetaProgress.GetRecoverySummary()
        assertEq(recovery.totalItems, 2, "recovery should count carried items")
        assertEq(recovery.totalValue, 34, "recovery should count carried value")
        assertEq(recovery.totalExtractionsWithItems, 1, "recovery should count item extraction")
        assertEq(#recovery.recentItems, 2, "recovery should keep recent item summaries")
        assertEq(MetaProgress.GetWarehouseItemCount("static_lens"), 1, "successful extraction should store carried item")
        assertEq(MetaProgress.GetWarehouseItemCount("blackbox_tag"), 1, "successful extraction should store all carried items")

        MetaProgress.RecordExtractionReward(reward, nil)
        assertEq(MetaProgress.GetGold(), 15, "same reward table should not double-record")
        assertEq(MetaProgress.GetWarehouseItemCount("static_lens"), 1, "same reward table should not double-store carried items")
    end)
end

local function testMetaProgressRecentRecoveryTrim()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        local reward = {
            totalGold = 0,
            directGold = 0,
            loosePartsGold = 0,
            carriedItemCount = 6,
            carriedItemValue = 60,
            carriedItems = {
                { itemId = "broken_copper_wire", count = 2, def = RunInventory.GetItemDef("broken_copper_wire") },
                { itemId = "dim_capacitor", count = 2, def = RunInventory.GetItemDef("dim_capacitor") },
                { itemId = "static_lens", count = 2, def = RunInventory.GetItemDef("static_lens") },
            },
        }
        MetaProgress.RecordExtractionReward(reward, nil)
        local recovery = MetaProgress.GetRecoverySummary()
        assertEq(recovery.totalItems, 6, "recovery total should keep all items")
        assertEq(#recovery.recentItems, 5, "recent recovery should be trimmed")
    end)
end

local function testMetaProgressFailureDoesNotRecordRecovery()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        MetaProgress.AddGold(12)
        local recovery = MetaProgress.GetRecoverySummary()
        assertEq(MetaProgress.GetGold(), 12, "failure retained gold should still add gold")
        assertEq(recovery.totalItems, 0, "failure gold should not register carried items")
        assertEq(recovery.totalValue, 0, "failure gold should not register carried value")
        assertEq(#recovery.recentItems, 0, "failure gold should not update recent items")
    end)
end

local function testMetaProgressWarehouseSellAndProtection()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        local reward = {
            totalGold = 6,
            directGold = 6,
            loosePartsGold = 0,
            carriedItemCount = 3,
            carriedItemValue = 42,
            carriedItems = {
                { itemId = "static_lens", count = 2, def = RunInventory.GetItemDef("static_lens") },
                { itemId = "dim_capacitor", count = 1, def = RunInventory.GetItemDef("dim_capacitor") },
            },
        }

        MetaProgress.RecordExtractionReward(reward, nil)
        assertEq(MetaProgress.GetWarehouseItemCount("static_lens"), 2, "warehouse should stack carried items")

        MetaProgress.RecordExtractionReward({
            totalGold = 0,
            directGold = 0,
            loosePartsGold = 0,
            carriedItemCount = 1,
            carriedItemValue = 16,
            carriedItems = {
                { itemId = "static_lens", count = 1, def = RunInventory.GetItemDef("static_lens") },
            },
        }, nil)
        assertEq(MetaProgress.GetWarehouseItemCount("static_lens"), 3, "warehouse same item should accumulate")

        local recoveryBefore = MetaProgress.GetRecoverySummary()
        local goldBefore = MetaProgress.GetGold()
        local sold, receipt = MetaProgress.SellWarehouseItem("static_lens", 1)
        assertTrue(sold, "SellWarehouseItem should succeed")
        assertEq(receipt.gold, 16, "selling one item should pay item value")
        assertEq(MetaProgress.GetGold(), goldBefore + 16, "selling should increase gold")
        assertEq(MetaProgress.GetWarehouseItemCount("static_lens"), 2, "selling should reduce warehouse count")

        local zeroSold, zeroReason = MetaProgress.SellWarehouseItem("static_lens", 0)
        assertTrue(not zeroSold, "zero-count sale should fail")
        assertEq(zeroReason, "invalid_count", "zero-count sale should return invalid_count")

        local tooMany = MetaProgress.SellWarehouseItem("static_lens", 99)
        assertTrue(not tooMany, "selling more than owned should fail")
        assertEq(MetaProgress.GetWarehouseItemCount("static_lens"), 2, "failed sale should not reduce count")

        local recoveryAfter = MetaProgress.GetRecoverySummary()
        assertEq(recoveryAfter.totalItems, recoveryBefore.totalItems, "recovery history should not shrink after sale")
        assertEq(recoveryAfter.totalValue, recoveryBefore.totalValue, "recovery value history should not shrink after sale")

        MetaProgress.AddWarehouseItems({
            { id = "unique_badge", name = "Unique Badge", type = "relic", typeName = "Recovered item", value = 99, count = 1, unique = true },
        }, "recovered")
        local uniqueSold, uniqueReason = MetaProgress.SellWarehouseItem("unique_badge", 1)
        assertTrue(not uniqueSold, "unique item should not be directly sellable")
        assertEq(uniqueReason, "unique", "unique sale should return protection reason")
    end)
end

local function testMetaProgressFailureSalvagesHighestItem()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        RunInventory.Reset()
        RunInventory.pendingGold = 9
        RunInventory.safeGold = 4
        RunInventory.gold = RunInventory.pendingGold
        RunInventory.parts = 1
        RunInventory.AddCarriedItem("static_lens", 1, "test")
        local salvage = RunInventory.ApplyFailureSalvage("accept")
        MetaProgress.AddGold(salvage.gold)
        MetaProgress.AddWarehouseItems(salvage.carriedItems, "recovered")
        assertEq(MetaProgress.GetGold(), 4, "failure should only add safe gold")
        assertEq(MetaProgress.GetWarehouseItemCount("static_lens"), 1, "failed run should salvage one highest value item")
    end)
end

local function testDisplayAdaptersProtectEquipmentAndConsumables()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        local consumable = RunInventory.GetItemDisplayData("emergency_bandage")
        assertEq(consumable.type, "consumable", "run display adapter should expose consumable type")
        assertEq(consumable.source, "recovered", "run display adapter should expose recovered source")

        local equipment = MetaProgress.GetItemDisplayData("armor")
        assertEq(equipment.type, "equipment", "meta display adapter should expose equipment fallback")
        assertTrue(equipment.unique, "equipment display fallback should be unique/protected")

        MetaProgress.AddWarehouseItems({
            { itemId = "emergency_bandage", count = 1, def = RunInventory.GetItemDef("emergency_bandage") },
            { id = "legacy_armor", name = "Legacy Armor", type = "equipment", typeName = "Equipment", value = 50, count = 1, source = "equipment", unique = true },
        }, nil)
        local bandage = MetaProgress.GetWarehouseItemDisplayData("emergency_bandage")
        local armor = MetaProgress.GetWarehouseItemDisplayData("legacy_armor")
        assertTrue(bandage ~= nil and not bandage.canSell, "consumables should display but not sell as recovery loot")
        assertTrue(armor ~= nil and not armor.canSell, "equipment fallback should display but not sell as recovery loot")
    end)
end

local function testMetaProgressLoadConsumableAndLoadoutDefaults()
    withMetaProgressMock({
        gold = 25,
        unlockedTalents = {},
        ownedItems = {},
        equippedItems = {},
        stats = {},
        recovery = nil,
        warehouse = nil,
    }, function()
        MetaProgress.Load()
        assertEq(MetaProgress.GetConsumableCount("emergency_bandage"), 0, "old save should default consumable stock")
        local loadoutSummary = MetaProgress.GetLoadoutSummary()
        assertEq(loadoutSummary.consumableCount, 0, "old save should default loadout")
        assertEq(loadoutSummary.equipmentText, loadoutSummary.emptyEquipmentHint, "old save should explain empty equipment")
        assertEq(loadoutSummary.consumablesText, loadoutSummary.emptyConsumablesHint, "old save should explain empty consumables")
        assertEq(loadoutSummary.effectsText, loadoutSummary.emptyEffectsHint, "old save should explain empty effects")
        assertEq(MetaProgress.GetTerminalSummary().inventory.gold, 25, "terminal summary should read old save gold")
    end)
end

local function testUnifiedDisplayAndWarehouseCategories()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        MetaProgress.AddGold(100)
        local bought = MetaProgress.BuyConsumable("emergency_bandage", 2)
        assertTrue(bought, "should buy consumables")
        MetaProgress.RecordExtractionReward({
            totalGold = 0,
            directGold = 0,
            loosePartsGold = 0,
            carriedItemCount = 1,
            carriedItemValue = 16,
            carriedItems = {
                { itemId = "static_lens", count = 1, def = RunInventory.GetItemDef("static_lens") },
            },
        }, nil)
        MetaProgress.BuyItem("armor")
        local recovered = MetaProgress.GetUnifiedItemDisplayData("static_lens", "warehouse")
        local equipment = MetaProgress.GetUnifiedItemDisplayData("armor", "equipment")
        local consumable = MetaProgress.GetUnifiedItemDisplayData("emergency_bandage", "consumable")
        assertEq(recovered.source, "recovered", "recovered display source mismatch")
        assertEq(equipment.type, "equipment", "equipment display type mismatch")
        assertEq(consumable.type, "consumable", "consumable display type mismatch")
        assertEq(consumable.count, 2, "consumable display should show stock")
        assertEq(recovered.display.category, "recovered", "recovered adapter category mismatch")
        assertEq(equipment.display.category, "equipment", "equipment adapter category mismatch")
        assertEq(consumable.display.category, "consumable", "consumable adapter category mismatch")
        assertTrue(equipment.display.iconKey ~= "", "equipment adapter should expose icon key")
        assertTrue(consumable.display.iconKey ~= "", "consumable adapter should expose icon key")
        assertTrue(type(consumable.display.typeLabel) == "string", "display adapter should expose type label")
        assertTrue(type(consumable.display.rarityLabel) == "string", "display adapter should expose rarity label")

        local equipmentList = MetaProgress.GetWarehouseDisplayList({ category = "equipment" })
        assertTrue(#equipmentList >= 1, "equipment category should show old equipment")
        for _, item in ipairs(equipmentList) do
            assertTrue(not item.canSell, "equipment category should not be sellable")
        end
        local consumableList = MetaProgress.GetWarehouseDisplayList({ category = "consumable" })
        assertTrue(#consumableList >= 1, "consumable category should show consumables")
        for _, item in ipairs(consumableList) do
            assertTrue(not item.canSell, "consumable category should not be sellable")
        end
    end)
end

local function testRunInventoryHUDSummary()
    RunInventory.Reset()
    RunInventory.AddPendingGold(18)
    RunInventory.AddSafeGold(7)
    RunInventory.AddCarriedItem("static_lens", 1, "search")
    RunInventory.AddConsumable("emergency_bandage", 2)
    local summary = RunInventory.GetHUDSummary({
        protocol = { level = 4, pressure = 12, maxPressure = 100, description = "轻度警戒" },
        nearbyMineRisk = 3,
        equipmentEffects = { "生命 +20" },
    })
    assertEq(summary.pendingCurrency, 18, "hud summary pending currency")
    assertEq(summary.lockedCurrency, 7, "hud summary locked currency")
    assertEq(summary.protocolLevel, 4, "hud summary protocol level")
    assertEq(summary.pressure, 12, "hud summary pressure")
    assertEq(summary.mineRiskState, "warning", "hud summary mine risk state")
    assertEq(#summary.recoveredItems, 1, "hud summary recovered row")
    assertEq(#summary.consumables, 1, "hud summary consumable row")
    assertTrue(summary.recoveredItems[1].iconKey ~= "", "hud recovered row should expose icon key")
    assertTrue(summary.consumables[1].iconKey ~= "", "hud consumable row should expose icon key")
end

local function testConsumablePurchaseLoadoutAndRunUse()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        MetaProgress.AddGold(100)
        local bought, receipt = MetaProgress.BuyConsumable("emergency_bandage", 3)
        assertTrue(bought, "consumable purchase should succeed")
        assertEq(receipt.total, 3, "consumable stock should stack")

        local configured, loadoutReceipt = MetaProgress.SetLoadoutConsumable("emergency_bandage", 2)
        assertTrue(configured, "loadout set should succeed")
        assertEq(loadoutReceipt.count, 2, "loadout should store selected count")
        assertEq(MetaProgress.GetConsumableCount("emergency_bandage"), 3, "setting loadout should not consume stock")

        local clampedOk, clamped = MetaProgress.SetLoadoutConsumable("emergency_bandage", 99)
        assertTrue(clampedOk, "oversized loadout should be safely handled")
        assertEq(clamped.count, 3, "oversized loadout should clamp to stock")

        local consumedOk, runLoadout = MetaProgress.ConsumeLoadoutForRun()
        assertTrue(consumedOk, "consume loadout should succeed")
        assertEq(runLoadout.consumables.emergency_bandage, 3, "run loadout should receive consumables")
        assertEq(MetaProgress.GetConsumableCount("emergency_bandage"), 0, "starting run should consume stock")

        RunInventory.Reset()
        RunInventory.SetConsumables(runLoadout.consumables)
        local hp = 50
        local maxHp = 100
        local used, useReceipt = RunInventory.UseConsumable("emergency_bandage", {
            hp = hp,
            maxHp = maxHp,
            applyHpDelta = function(delta)
                hp = math.min(maxHp, hp + delta)
                return { hp = hp, delta = delta }
            end,
        })
        assertTrue(used, "bandage should be usable in run")
        assertEq(useReceipt.heal, 25, "bandage should heal configured minimum")
        assertEq(RunInventory.GetConsumableCount("emergency_bandage"), 2, "using should reduce run count")

        local fullUse, fullReason = RunInventory.UseConsumable("emergency_bandage", { hp = 100, maxHp = 100 })
        assertTrue(not fullUse, "full hp use should fail")
        assertEq(fullReason, "hp_full", "full hp should return hp_full")

        RunInventory.SetConsumables({})
        local emptyUse, emptyReason = RunInventory.UseConsumable("emergency_bandage", { hp = 50, maxHp = 100 })
        assertTrue(not emptyUse, "empty use should fail")
        assertEq(emptyReason, "not_enough", "empty use should return not_enough")
    end)
end

local function testUILayoutRoundTrip()
    local cases = {
        { w = 1536, h = 864 },
        { w = 1920, h = 1080 },
        { w = 1280, h = 720 },
        { w = 1600, h = 900 },
        { w = 1366, h = 768 },
    }

    local baseW, baseH = UILayout.GetBaseSize()
    assertEq(baseW, 1536, "ui layout base width")
    assertEq(baseH, 864, "ui layout base height")

    for _, c in ipairs(cases) do
        UILayout.SetViewport(c.w, c.h)
        local sx, sy, sw, sh = UILayout.ToScreen(120, 80, 360, 180)
        local lx, ly = UILayout.ToLogic(sx, sy)
        assertTrue(math.abs(lx - 120) < 0.001, "layout x round trip at " .. c.w .. "x" .. c.h)
        assertTrue(math.abs(ly - 80) < 0.001, "layout y round trip at " .. c.w .. "x" .. c.h)
        assertTrue(sw > 0 and sh > 0, "layout screen size should be positive")
        assertTrue(UILayout.ContainsLogic(130, 90, { x = 120, y = 80, w = 360, h = 180 }), "layout hit test")
        local deployX, deployY = UILayout.ToLogic(UILayout.ToScreen(260, 292))
        assertTrue(UILayout.ContainsLogic(deployX, deployY, { x = 230, y = 148, w = 820, h = 612 }), "deploy central hit at " .. c.w .. "x" .. c.h)
        assertTrue(UILayout.ContainsLogic(deployX, deployY, { x = 260, y = 292, w = 760, h = 320 }), "deploy card hot area at " .. c.w .. "x" .. c.h)
    end
end

local function testUIThemeMissingImageSafe()
    UITheme.RegisterDefaults()
    assertEq(UITheme.GetRegisteredPath("deploy.panel.main"), "ui/deploy/ui_panel_deploy_main_blank.png", "deploy panel registry path")
    assertEq(UITheme.GetRegisteredPath("hud.panel.left"), "ui/hud/ui_panel_left.png", "hud panel registry path")
    assertEq(UITheme.GetItemIconKey({ id = "emergency_bandage", type = "consumable" }), "item.consumable.emergency_bandage", "consumable icon resolution")
    local recoveredPath = UITheme.ResolveIconPath(UITheme.GetItemIconKey({ id = "static_lens", type = "relic", source = "recovered" }))
    assertEq(recoveredPath, "item_recovered/item_recovered_ore.png", "recovered icon fallback path")
    assertTrue(UITheme.LoadImage("missing_test_asset", "ui/missing/nope.png") == false, "missing image should not load")
    assertTrue(UITheme.Has("missing_test_asset") == false, "missing image should not be reported as present")
    assertTrue(UITheme.GetImage("missing_test_asset") == -1, "missing image should use sentinel")
end

local function testMainEntrySourceContract()
    local oldPreload = package.preload["urhox-libs/UI"]
    local oldLoaded = package.loaded["urhox-libs/UI"]
    local buttons = {}

    local function makeNode(spec)
        spec = spec or {}
        spec.visible = spec.visible ~= false
        function spec:FindById(id)
            if self.id == id then return self end
            for _, child in ipairs(self.children or {}) do
                if type(child) == "table" and child.FindById then
                    local found = child:FindById(id)
                    if found then return found end
                end
            end
            return nil
        end
        function spec:Show() self.visible = true end
        function spec:Hide() self.visible = false end
        function spec:SetText(text) self.text = text end
        function spec:AddChild(child)
            self.children = self.children or {}
            table.insert(self.children, child)
        end
        function spec:RemoveAllChildren() self.children = {} end
        return spec
    end

    package.loaded["urhox-libs/UI"] = nil
    package.preload["urhox-libs/UI"] = function()
        return {
            Panel = function(spec) return makeNode(spec) end,
            Label = function(spec) return makeNode(spec) end,
            Button = function(spec)
                local node = makeNode(spec)
                table.insert(buttons, node)
                return node
            end,
            SetRoot = function(root) _G.__testUiRoot = root end,
            Shutdown = function() end,
        }
    end

    local chunk, loadErr = loadfile("scripts/main.lua")
    assertTrue(chunk ~= nil, "main.lua should load: " .. tostring(loadErr))
    local ok, runErr = pcall(chunk)
    assertTrue(ok, "main.lua should initialize with UI stub: " .. tostring(runErr))

    assertTrue(type(OpenMainMenu) == "function", "main menu wrapper should exist")
    assertTrue(type(OpenDeployTerminal) == "function", "deploy terminal wrapper should exist")
    assertTrue(type(ConfirmDeploy) == "function", "confirm deploy wrapper should exist")
    assertTrue(type(StartNormalRun) == "function", "normal run wrapper should exist")
    assertTrue(type(StartTutorialRun) == "function", "tutorial wrapper should exist")

    CreateUI()
    OpenMainMenu()

    local mainPage = _G.__testUiRoot:FindById("menuPage_main")
    assertTrue(mainPage ~= nil, "main page should exist")
    assertEq(mainPage.backgroundImage, "Textures/menu_bg.png", "main page should use original menu background")
    assertTrue(mainPage.backgroundImage ~= "Textures/menu_bg_no_text.png", "main page should not use no-text texture")

    local directStartCount = 0
    local capturedStartConfig = nil
    local oldStartNewGame = StartNewGame
    local oldStartTutorial = StartTutorial
    StartNewGame = function(config)
        directStartCount = directStartCount + 1
        capturedStartConfig = config
    end
    StartTutorial = function() error("UI should not call StartTutorial directly") end

    local function collectVisibleButtons(node, inheritedVisible, out)
        if not node then return end
        local visible = inheritedVisible and node.visible ~= false
        if visible and node.onClick and node.text then
            out[node.text] = (out[node.text] or 0) + 1
        end
        for _, child in ipairs(node.children or {}) do
            collectVisibleButtons(child, visible, out)
        end
    end

    local function visibleButtons()
        local out = {}
        collectVisibleButtons(_G.__testUiRoot, true, out)
        return out
    end

    local function visibleIds()
        local out = {}
        local function collect(node, inheritedVisible)
            if not node then return end
            local visible = inheritedVisible and node.visible ~= false
            if visible and node.id then
                out[node.id] = true
            end
            for _, child in ipairs(node.children or {}) do
                collect(child, visible)
            end
        end
        collect(_G.__testUiRoot, true)
        return out
    end

    local function findActionRect(action, itemId)
        local rects = GetDeployTerminalHitRects()
        for _, rect in ipairs(rects.actions or {}) do
            if rect.action == action and (not itemId or rect.itemId == itemId) then
                return rect
            end
        end
        return nil
    end

    local mainButtons = visibleButtons()
    assertTrue(mainButtons["接受工单"] == nil, "main should not show top-left accept button")
    assertTrue(mainButtons["展示工单"] == nil, "main should not show top-left tutorial button")
    assertTrue(mainButtons["调整终端"] == nil, "main should not show top-left settings button")
    assertTrue(mainButtons["后勤仓库"] == nil, "main should not show warehouse entry")
    assertTrue(mainButtons["后勤申领"] == nil, "main should not show requisition entry")
    assertTrue(mainButtons["出勤配置"] == nil, "main should not show loadout entry")
    assertTrue(mainButtons["回收资历"] == nil, "main should not show recovery entry")
    assertEq(GetMainMenuHotspotCount(), 3, "main should keep three logical hotspots")
    assertTrue(_G.__testUiRoot:FindById("menuGoldLabel") == nil, "main should not define gold summary label")
    assertTrue(_G.__testUiRoot:FindById("menuWarehouseLabel") == nil, "main should not define warehouse summary label")
    assertTrue(_G.__testUiRoot:FindById("menuLoadoutLabel") == nil, "main should not define loadout summary label")

    OpenDeployTerminal()
    assertEq(directStartCount, 0, "top-level accept should open deploy terminal, not start a run")

    local deployIds = visibleIds()
    assertTrue(deployIds["deployNavWarehouseButton"] ~= nil, "deploy should keep warehouse entry hit target")
    assertTrue(deployIds["deployNavRequisitionButton"] ~= nil, "deploy should keep requisition entry hit target")
    assertTrue(deployIds["deployNavLoadoutButton"] ~= nil, "deploy should keep loadout entry hit target")
    assertTrue(deployIds["deployNavRecoveryButton"] ~= nil, "deploy should keep recovery entry hit target")
    assertTrue(deployIds["deployConfirmButton"] ~= nil, "deploy should keep confirm deploy hit target")
    assertTrue(deployIds["deployBackButton"] ~= nil, "deploy should keep return to main hit target")
    assertEq(_G.__testUiRoot:FindById("menuPage_deployOverview").visible, true, "accept should open deploy overview")

    local deployPageNode = _G.__testUiRoot:FindById("menuPage_deployOverview")
    assertTrue(deployPageNode.backgroundImage ~= "Textures/menu_bg.png", "deploy terminal should not reuse main menu background")
    assertTrue(deployPageNode.backgroundImage ~= "ui/main_menu/main_menu_bg_no_text.png", "deploy terminal should not reuse no-text main background")

    local layout = GetDeployTerminalLayoutInfo()
    assertTrue(layout.rootPanel.x >= 0 and layout.rootPanel.y >= 0, "deploy root panel should start inside base")
    assertTrue(layout.rootPanel.x + layout.rootPanel.w <= 1536, "deploy root panel should fit base width")
    assertTrue(layout.rootPanel.y + layout.rootPanel.h <= 864, "deploy root panel should fit base height")
    local central = _G.__testUiRoot:FindById("deployCentralDisplay")
    local legacyCentral = _G.__testUiRoot:FindById("deployOverviewLegacyPanel")
    local filterBar = _G.__testUiRoot:FindById("deployFilterBar")
    local cardGrid = _G.__testUiRoot:FindById("deployCardGrid")
    local summaryPanel = _G.__testUiRoot:FindById("deploySummaryFixedPanel")
    local confirmButton = _G.__testUiRoot:FindById("deployConfirmButton")
    local navBar = _G.__testUiRoot:FindById("deployModuleNavBar")
    local detailLabel = _G.__testUiRoot:FindById("deployCardDetailLabel")
    local summaryEquipment = _G.__testUiRoot:FindById("deploySummaryEquipmentLabel")
    assertEq(central.left, layout.central.x, "central display x should be fixed")
    assertEq(central.top, layout.central.y, "central display y should be fixed")
    assertEq(central.width, layout.central.w, "central display width should be fixed")
    assertEq(central.height, layout.central.h, "central display height should be fixed")
    assertTrue(central.backgroundImage == nil, "central display should not depend on a large background asset")
    assertTrue(legacyCentral.visible == false, "legacy deploy overview panel should be hidden")
    assertTrue(filterBar ~= nil, "central display should have filter bar")
    assertTrue(cardGrid ~= nil, "central display should have card grid")
    assertEq(summaryPanel.left, layout.summary.x, "summary panel x should be fixed")
    assertEq(summaryPanel.top, layout.summary.y, "summary panel y should be fixed")
    assertEq(confirmButton.width, layout.confirm.w, "confirm deploy button width should be fixed")
    assertEq(confirmButton.height, layout.confirm.h, "confirm deploy button height should be fixed")
    assertEq(navBar.left, layout.nav.x, "deploy nav x should be fixed")
    assertEq(navBar.top, layout.nav.y, "deploy nav y should be fixed")
    assertEq(detailLabel.width, layout.detail.w - 24, "detail text should use a bounded text box")
    assertEq(summaryEquipment.width, layout.summary.w - 36, "summary text should use a bounded text box")
    assertEq(layout.columns, 3, "deploy card grid should use three columns")
    assertEq(layout.rowsVisible, 2, "deploy card grid should expose two visible rows before scrolling")
    assertTrue(layout.central.x >= layout.rootPanel.x and layout.central.y >= layout.rootPanel.y, "central should be root-relative inside root")
    assertTrue(layout.rightRail.x >= layout.rootPanel.x and layout.rightRail.y >= layout.rootPanel.y, "right rail should be root-relative inside root")
    assertTrue(layout.detail.x + layout.detail.w <= layout.central.x + layout.central.w, "detail should fit central")
    assertTrue(layout.rightRail.x + layout.rightRail.w <= 1536 - layout.safe, "right rail should stay inside safe area")
    assertTrue(layout.confirm.x + layout.confirm.w <= 1536 - layout.safe, "confirm deploy should stay inside safe area")
    assertTrue(layout.central.x + layout.central.w < layout.rightRail.x - layout.gap, "central display should keep right rail gap")
    assertTrue(layout.summary.x + layout.summary.w <= 1536 - layout.safe, "summary should stay inside safe area")
    assertTrue(layout.nav.x + layout.nav.w <= 1536 - layout.safe, "tab bar should stay inside safe area")
    assertEq(layout.confirm.x, math.floor(layout.rightRail.x + (layout.rightRail.w - layout.confirm.w) / 2), "confirm deploy should be centered in right rail")
    assertEq(layout.confirm.y, layout.rightRail.y + layout.rightRail.h - layout.confirm.h - 28, "confirm deploy should be anchored in right rail")

    local layoutCases = {
        { w = 1536, h = 864 },
        { w = 1920, h = 1080 },
        { w = 1600, h = 900 },
        { w = 1366, h = 768 },
        { w = 1280, h = 720 },
    }
    for _, c in ipairs(layoutCases) do
        UILayout.SetViewport(c.w, c.h)
        local confirmX, confirmY, confirmW, confirmH = UILayout.ToScreen(layout.confirm.x, layout.confirm.y, layout.confirm.w, layout.confirm.h)
        local rootX, rootY, rootW, rootH = UILayout.ToScreen(layout.rootPanel.x, layout.rootPanel.y, layout.rootPanel.w, layout.rootPanel.h)
        local railX, railY, railW, railH = UILayout.ToScreen(layout.rightRail.x, layout.rightRail.y, layout.rightRail.w, layout.rightRail.h)
        local centralX, centralY, centralW, centralH = UILayout.ToScreen(layout.central.x, layout.central.y, layout.central.w, layout.central.h)
        local detailX, detailY, detailW, detailH = UILayout.ToScreen(layout.detail.x, layout.detail.y, layout.detail.w, layout.detail.h)
        local summaryX, summaryY, summaryW, summaryH = UILayout.ToScreen(layout.summary.x, layout.summary.y, layout.summary.w, layout.summary.h)
        local cardGridX, cardGridY, cardGridW, cardGridH = UILayout.ToScreen(layout.cardArea.x, layout.cardArea.y, layout.cardArea.w, layout.cardArea.h)
        assertTrue(rootX >= 0 and rootY >= 0 and rootX + rootW <= c.w and rootY + rootH <= c.h, "root panel should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(railX >= 0 and railY >= 0 and railX + railW <= c.w and railY + railH <= c.h, "right rail should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(centralX >= 0 and centralY >= 0 and centralX + centralW <= c.w and centralY + centralH <= c.h, "central panel should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(detailX >= 0 and detailY >= 0 and detailX + detailW <= c.w and detailY + detailH <= c.h, "detail panel should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(summaryX >= 0 and summaryY >= 0 and summaryX + summaryW <= c.w and summaryY + summaryH <= c.h, "summary panel should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(cardGridX >= 0 and cardGridY >= 0 and cardGridX + cardGridW <= c.w and cardGridY + cardGridH <= c.h, "card grid should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(confirmX >= 0 and confirmY >= 0, "confirm deploy should start on screen at " .. c.w .. "x" .. c.h)
        assertTrue(confirmX + confirmW <= c.w and confirmY + confirmH <= c.h, "confirm deploy should fit screen at " .. c.w .. "x" .. c.h)
        local hudLayout = HUD.ComputeLayout(c.w, c.h)
        assertTrue(hudLayout.sidebar.x >= 0 and hudLayout.sidebar.y >= 0 and hudLayout.sidebar.x + hudLayout.sidebar.w <= c.w and hudLayout.sidebar.y + hudLayout.sidebar.h <= c.h, "HUD left should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(hudLayout.protocol.x >= 0 and hudLayout.protocol.y >= 0 and hudLayout.protocol.x + hudLayout.protocol.w <= c.w and hudLayout.protocol.y + hudLayout.protocol.h <= c.h, "HUD right should fit screen at " .. c.w .. "x" .. c.h)
        assertTrue(hudLayout.bottom.x >= 0 and hudLayout.bottom.y >= 0 and hudLayout.bottom.x + hudLayout.bottom.w <= c.w and hudLayout.bottom.y + hudLayout.bottom.h <= c.h, "HUD bottom should fit screen at " .. c.w .. "x" .. c.h)
        local cardX, cardY = UILayout.ToScreen(layout.cardArea.x + 3, layout.cardArea.y + 3)
        local logicX, logicY = UILayout.ToLogic(cardX, cardY)
        assertTrue(UILayout.ContainsLogic(logicX, logicY, layout.cardArea), "card hotspot should round trip at " .. c.w .. "x" .. c.h)
    end
    UILayout.SetViewport(1536, 864)

    for _, module in ipairs(GetDeployTerminalModules()) do
        RefreshDeployModulePage(module.id)
        local moduleLayout = GetDeployTerminalLayoutInfo()
        local expectedVisibleCards = math.min(moduleLayout.cardCount, moduleLayout.columns * moduleLayout.rowsVisible)
        assertEq(moduleLayout.module, module.id, "deploy module should refresh into central display")
        assertEq(moduleLayout.hitRectCount, expectedVisibleCards, "visible card hit rects should match central grid")
        assertEq(#(_G.__testUiRoot:FindById("deployFilterBar").children or {}), #GetDeployTerminalFilters(module.id), "filter bar should match module filters")
    end

    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        MetaProgress.AddConsumable("emergency_bandage", 4)
        MetaProgress.AddWarehouseItems({
            { id = "ui_static_lens", name = "UI Static Lens", type = "relic", typeName = "Recovered item", value = 16, count = 2, source = "recovered" },
            { id = "ui_dim_capacitor", name = "UI Dim Capacitor", type = "relic", typeName = "Recovered item", value = 9, count = 1, source = "recovered" },
            { id = "ui_echo_wire", name = "UI Echo Wire", type = "tool", typeName = "Recovered item", value = 7, count = 1, source = "recovered" },
            { id = "ui_black_sand", name = "UI Black Sand", type = "record", typeName = "Recovered item", value = 5, count = 1, source = "recovered" },
            { id = "ui_glass_tag", name = "UI Glass Tag", type = "relic", typeName = "Recovered item", value = 4, count = 1, source = "recovered" },
            { id = "ui_cold_coin", name = "UI Cold Coin", type = "tool", typeName = "Recovered item", value = 3, count = 1, source = "recovered" },
            { id = "ui_spare_signal", name = "UI Spare Signal", type = "record", typeName = "Recovered item", value = 2, count = 1, source = "recovered" },
        }, "recovered")
        RefreshDeployModulePage("warehouse")
        SetDeployFilter("consumable")
        local beforeWarehouseLoadout = MetaProgress.GetLoadout().consumables.emergency_bandage or 0
        local warehouseInc = findActionRect("loadout_inc", "emergency_bandage")
        assertTrue(warehouseInc ~= nil, "warehouse should register bandage + action")
        assertEq(warehouseInc.module, "warehouse", "warehouse + action should carry module")
        assertTrue(warehouseInc.visualRect ~= nil and warehouseInc.hitRect ~= nil, "warehouse + action should expose visual and hit rects")
        local incOk = HandleDeployCardClickAt(warehouseInc.x + 1, warehouseInc.y + 1)
        assertTrue(incOk, "warehouse bandage + should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "warehouse", "warehouse + should stay in warehouse")
        assertEq(MetaProgress.GetLoadout().consumables.emergency_bandage or 0, beforeWarehouseLoadout + 1, "warehouse + should increase loadout")

        local warehouseDec = findActionRect("loadout_dec", "emergency_bandage")
        assertTrue(warehouseDec ~= nil, "warehouse should register bandage - action")
        local decOk = HandleDeployCardClickAt(warehouseDec.x + 1, warehouseDec.y + 1)
        assertTrue(decOk, "warehouse bandage - should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "warehouse", "warehouse - should stay in warehouse")
        assertEq(MetaProgress.GetLoadout().consumables.emergency_bandage or 0, beforeWarehouseLoadout, "warehouse - should reduce loadout")

        RefreshDeployModulePage("loadout")
        SetDeployFilter("consumable")
        local beforeLoadoutCount = MetaProgress.GetLoadout().consumables.emergency_bandage or 0
        local loadoutInc = findActionRect("loadout_inc", "emergency_bandage")
        assertTrue(loadoutInc ~= nil, "loadout should register bandage + action")
        local loadoutIncOk = HandleDeployCardClickAt(loadoutInc.x + 1, loadoutInc.y + 1)
        assertTrue(loadoutIncOk, "loadout bandage + should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "loadout", "loadout + should stay in loadout")
        assertEq(MetaProgress.GetLoadout().consumables.emergency_bandage or 0, beforeLoadoutCount + 1, "loadout + should increase loadout")

        local loadoutDec = findActionRect("loadout_dec", "emergency_bandage")
        assertTrue(loadoutDec ~= nil, "loadout should register bandage - action")
        local loadoutDecOk = HandleDeployCardClickAt(loadoutDec.x + 1, loadoutDec.y + 1)
        assertTrue(loadoutDecOk, "loadout bandage - should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "loadout", "loadout - should stay in loadout")
        assertEq(MetaProgress.GetLoadout().consumables.emergency_bandage or 0, beforeLoadoutCount, "loadout - should reduce loadout")

        RefreshDeployModulePage("warehouse")
        SetDeployFilter("recovered")

        local warehouseLayout = GetDeployTerminalLayoutInfo()
        local rects = GetDeployTerminalHitRects()
        assertTrue(warehouseLayout.actionRectCount > 0, "warehouse cards should expose action hit rects")
        assertTrue(#rects.actions > 0, "debug action rect copy should include sell buttons")

        local sellRect = nil
        for _, rect in ipairs(rects.actions) do
            if rect.action == "sell" then
                sellRect = rect
                break
            end
        end
        assertTrue(sellRect ~= nil, "warehouse should register a sell action rect")
        assertEq(sellRect.module, "warehouse", "sell rect should record module")
        assertEq(sellRect.actionType, "sell", "sell rect should record action type")
        assertTrue(sellRect.visibleIndex ~= nil and sellRect.scrollIndex ~= nil, "sell rect should record visible and scroll indices")
        assertTrue(UILayout.ContainsLogic(sellRect.x + 1, sellRect.y + 1, layout.cardArea), "sell rect should be inside card area")
        assertEq(sellRect.w, 58, "sell click rect width should match button visual width")
        assertEq(sellRect.h, 24, "sell click rect height should match button visual height")

        local beforeGold = MetaProgress.GetGold()
        local beforeCount = MetaProgress.GetWarehouseItemCount(sellRect.itemId)
        local dispatched, dispatchResult = HandleDeployCardClickAt(sellRect.x + 1, sellRect.y + 1)
        assertTrue(dispatched, "clicking sell rect should dispatch")
        assertTrue(dispatchResult and dispatchResult.gold and dispatchResult.gold > 0, "sell dispatch should return sale receipt")
        assertEq(GetDeployTerminalLayoutInfo().module, "warehouse", "sell should stay in warehouse")
        assertEq(MetaProgress.GetGold(), beforeGold + dispatchResult.gold, "UI sell dispatch should increase gold")
        assertEq(MetaProgress.GetWarehouseItemCount(sellRect.itemId), beforeCount - 1, "UI sell dispatch should reduce warehouse count")

        MetaProgress.AddGold(1000)
        OpenDeployShop()
        SetDeployFilter("consumable")
        local buyRect = findActionRect("buy", "emergency_bandage")
        assertTrue(buyRect ~= nil, "requisition should register consumable buy action")
        local beforeBandage = MetaProgress.GetConsumableCount("emergency_bandage")
        local buyDispatched = HandleDeployCardClickAt(buyRect.x + 1, buyRect.y + 1)
        assertTrue(buyDispatched, "clicking buy rect should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "requisition", "buy should stay in requisition")
        assertEq(MetaProgress.GetConsumableCount("emergency_bandage"), beforeBandage + 1, "buy should add consumable stock")

        OpenDeployShop()
        SetDeployFilter("equipment")
        local buyEquipRect = findActionRect("equip_or_buy", "armor")
        assertTrue(buyEquipRect ~= nil, "requisition should register equipment buy action")
        local equipBuyDispatched = HandleDeployCardClickAt(buyEquipRect.x + 1, buyEquipRect.y + 1)
        assertTrue(equipBuyDispatched, "clicking equipment buy rect should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "requisition", "equipment buy should stay in requisition")
        assertTrue(MetaProgress.OwnsItem("armor"), "equipment buy should unlock armor ownership")
        local equipRect = findActionRect("equip_or_buy", "armor")
        assertTrue(equipRect ~= nil, "owned equipment should keep equip action")
        local equipDispatched = HandleDeployCardClickAt(equipRect.x + 1, equipRect.y + 1)
        assertTrue(equipDispatched, "clicking equipment equip rect should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "requisition", "equip should stay in requisition")
        assertTrue(MetaProgress.IsEquipped("armor"), "equip action should toggle armor on")

        OpenDeployTalents()
        SetDeployFilter("all")
        local unlockRect = findActionRect("unlock", "talent_map")
        assertTrue(unlockRect ~= nil, "talent should register unlock action")
        local unlockDispatched = HandleDeployCardClickAt(unlockRect.x + 1, unlockRect.y + 1)
        assertTrue(unlockDispatched, "clicking unlock rect should dispatch")
        assertEq(GetDeployTerminalLayoutInfo().module, "talent", "unlock should stay in talent")
        assertTrue(MetaProgress.HasTalent("talent_map"), "unlock action should unlock talent")

        RefreshDeployModulePage("warehouse")
        SetDeployFilter("all")
        ScrollDeployCards(1)
        local scrolledLayout = GetDeployTerminalLayoutInfo()
        local scrolledRects = GetDeployTerminalHitRects()
        assertTrue(scrolledLayout.actionRectCount > 0, "scrolled warehouse should keep action rects")
        assertTrue(scrolledLayout.actionRectCount <= scrolledLayout.hitRectCount * 3, "invisible cards should not keep action rects")
        for _, rect in ipairs(scrolledRects.actions) do
            assertTrue(UILayout.ContainsLogic(rect.x + 1, rect.y + 1, layout.cardArea), "scrolled action rect should stay in card area")
            assertTrue(rect.scrollIndex > scrolledLayout.scroll * scrolledLayout.columns, "scrolled action rect should belong to visible page")
        end
    end)

    local function assertNoAbsoluteBackgrounds(node)
        if not node then return end
        if node.backgroundImage then
            assertTrue(string.find(node.backgroundImage, ":\\", 1, true) == nil, "runtime UI background should be project-relative: " .. node.backgroundImage)
        end
        for _, child in ipairs(node.children or {}) do
            assertNoAbsoluteBackgrounds(child)
        end
    end
    assertNoAbsoluteBackgrounds(_G.__testUiRoot)

    OpenTutorial()
    assertEq(directStartCount, 1, "tutorial should enter through StartTutorialRun config")
    assertEq(capturedStartConfig.mode, "tutorial", "tutorial start config should stay tutorial mode")
    assertEq(capturedStartConfig.useLoadout, false, "tutorial should not use loadout")
    assertEq(capturedStartConfig.applyMetaProgress, false, "tutorial should not apply meta")
    assertEq(capturedStartConfig.allowWarehouseRewards, false, "tutorial should not write warehouse rewards")
    assertEq(capturedStartConfig.allowFailureRewards, false, "tutorial should not write failure rewards")
    assertEq(capturedStartConfig.skipLoadout, true, "tutorial should skip loadout")
    assertTrue(capturedStartConfig.manualMap ~= nil, "tutorial should keep fixed manual map")

    StartNewGame = oldStartNewGame
    StartTutorial = oldStartTutorial
    package.preload["urhox-libs/UI"] = oldPreload
    package.loaded["urhox-libs/UI"] = oldLoaded
end

local function testEquipmentRequiresEquippedForBonus()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        MetaProgress.AddGold(200)

        local boughtArmor = MetaProgress.BuyItem("armor")
        assertTrue(boughtArmor, "armor purchase should succeed")
        assertEq(MetaProgress.GetEquipBonus().bonusHP, 0, "owned armor should not apply until equipped")

        local equippedArmor = MetaProgress.ToggleEquip("armor")
        assertTrue(equippedArmor, "armor equip should succeed")
        assertEq(MetaProgress.GetEquipBonus().bonusHP, Balance.shop.armor.bonusHP, "equipped armor should add max HP")

        local boughtWhetstone = MetaProgress.BuyItem("whetstone")
        assertTrue(boughtWhetstone, "whetstone purchase should succeed")
        assertEq(MetaProgress.GetEquipBonus().bonusPower, 0, "owned whetstone should not apply until equipped")

        local equippedWhetstone = MetaProgress.ToggleEquip("whetstone")
        assertTrue(equippedWhetstone, "whetstone equip should succeed")
        assertEq(MetaProgress.GetEquipBonus().bonusPower, Balance.shop.whetstone.bonusPower, "equipped whetstone should add power")
    end)
end

local function testConsumableLoadoutZeroDoesNotEnterRun()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        MetaProgress.AddGold(100)
        local bought = MetaProgress.BuyConsumable("emergency_bandage", 2)
        assertTrue(bought, "bandage purchase should succeed")

        local ok, runLoadout = MetaProgress.ConsumeLoadoutForRun()
        assertTrue(ok, "empty loadout consume should succeed")
        assertEq(runLoadout.consumables.emergency_bandage, nil, "loadout=0 should carry no bandages")
        assertEq(MetaProgress.GetConsumableCount("emergency_bandage"), 2, "loadout=0 should not consume stock")

        MetaProgress.SetLoadoutConsumable("emergency_bandage", 2)
        local ok2, runLoadout2 = MetaProgress.ConsumeLoadoutForRun()
        assertTrue(ok2, "configured loadout should consume")
        assertEq(runLoadout2.consumables.emergency_bandage, 2, "configured loadout should enter run")
        assertEq(MetaProgress.GetConsumableCount("emergency_bandage"), 0, "configured loadout should reduce stock")
    end)
end

local function testMetaProgressGrowthEffectsStillApply()
    withMetaProgressMock(nil, function()
        MetaProgress.GMReset()
        MetaProgress.AddGold(500)
        local bought = MetaProgress.BuyItem("armor")
        assertTrue(bought, "should buy armor with extracted gold")
        local equipped = MetaProgress.ToggleEquip("armor")
        assertTrue(equipped, "should equip bought armor")
        assertEq(MetaProgress.GetEquipBonus().bonusHP, Balance.shop.armor.bonusHP, "armor should still grant HP")

        local unlocked = MetaProgress.UnlockTalent("talent_mine")
        assertTrue(unlocked, "should unlock mine talent with extracted gold")
        assertEq(MetaProgress.GetTalentEffects().mineDmgReduce, 10, "mine talent should still apply")
    end)
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
    local config = Tutorial.GetMapConfig()
    assertEq(config.mode, "tutorial", "tutorial config should use tutorial mode")
    assertEq(config.seed, 777, "tutorial seed mismatch")
    assertTrue(config.manualMap ~= nil, "tutorial config should include fixed manual map")
    assertEq(config.manualMap.width, 5, "tutorial manual map width mismatch")
    assertEq(config.manualMap.height, 5, "tutorial manual map height mismatch")

    local field = Minefield.New(config)

    assertEq(field.width, 5, "tutorial width mismatch")
    assertEq(field.height, 5, "tutorial height mismatch")
    assertEq(field.mode, "tutorial", "tutorial field mode mismatch")
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

    local normalField = Minefield.New({
        mode = "normal",
        width = 10,
        height = 10,
        seed = 777,
        randomExitCount = 2,
    })
    assertEq(normalField.width, 10, "normal mode should keep normal width")
    assertEq(normalField.height, 10, "normal mode should keep normal height")
    assertTrue(normalField.manualMap == nil, "normal mode should not receive tutorial manual map")
    assertTrue(#normalField:GetExits() ~= #field:GetExits() or normalField.width ~= field.width,
        "normal mode should differ from fixed tutorial map")
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
    assertTrue(win.reward and win.reward.gold >= 0 and win.reward.gold <= Balance.monster.goldMax, "combat result should include tuned gold reward")
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
    assertTrue(costly.reward and costly.reward.gold >= 0 and costly.reward.gold <= Balance.monster.goldMax, "costly combat should still pay tuned reward")
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
    assertTrue(killed.result and killed.result.reward and killed.result.reward.gold >= 0, "killed monster should produce reward result")
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

    local r1 = EventSystem.Execute(10, 10, { pendingGold = 100, tradableItems = {}, hp = 3, maxHp = 5, power = 5 })
    assert(r1.ok, "default trader action should leave when no item exists")
    assertEq(r1.completed, false, "leave should not complete trader")

    local item = { itemId = "static_lens", name = "Static Lens", count = 1, baseValue = 16, value = 16 }
    local r2 = EventSystem.Execute(10, 10, { pendingGold = 100, tradableItems = { item }, hp = 3, maxHp = 5, power = 5 })
    assert(r2.ok, "trader should sell concrete item")
    assertEq(r2.safeGoldDelta, 12, "trader should pay floor(baseValue * 0.75)")
    assertEq(r2.sellItemId, "static_lens", "trader should request concrete item removal")
    assertEq(r2.hpDelta, 0, "no hp change for trader")

    -- Already completed
    local r3 = EventSystem.Execute(10, 10, { pendingGold = 100, tradableItems = { item }, hp = 3, maxHp = 5, power = 5 })
    assert(not r3.ok, "completed event should fail")

    local state = EventSystem.GetEventState(10, 10)
    assertEq(state.optionState.completedOption, "sell_item:static_lens", "completed trader should remember selected option")
end

local function testEventTraderOptionsAndAdapter()
    EventSystem.Reset(51)
    EventSystem.assignedEvents["11,11"] = "trader"

    local tradables = EventSystem.getTradableItems({ tradableItems = { { itemId = "static_lens", count = 1 } } })
    assertEq(tradables[1].itemId, "static_lens", "tradable adapter should expose concrete item")
    assertEq(tradables[1].count, 1, "tradable adapter should expose item count")

    local menu = EventSystem.GetOptions(11, 11, { pendingGold = 0, tradableItems = {}, hp = 100, maxHp = 100, power = 10 })
    assertEq(#menu.options, 2, "trader without items should expose disabled placeholder and leave")
    assertTrue(menu.options[1].enabled == false, "no item placeholder should be disabled")

    local ok, reason = EventSystem.canExecuteTrade(menu.options[1], menu.state)
    assertTrue(not ok, "canExecuteTrade should reject disabled option")
    assertTrue(reason ~= nil, "canExecuteTrade should return disabled reason")
end

local function testEventExecTraderHealFull()
    EventSystem.Reset(52)
    EventSystem.assignedEvents["12,12"] = "trader"

    local full = EventSystem.ExecuteOptionById(12, 12, "heal", { pendingGold = 20, tradableItems = {}, hp = 100, maxHp = 100, power = 10 })
    assertTrue(not full.ok, "removed trader heal option should fail")
end

local function testEventExecDice()
    EventSystem.Reset(50)
    EventSystem.assignedEvents["20,20"] = "dice"

    -- Not enough gold
    local r1 = EventSystem.Execute(20, 20, { pendingGold = 5, hp = 3, maxHp = 5, power = 5 })
    assert(not r1.ok, "dice should fail with insufficient gold")

    -- Enough gold - should produce a result (win or lose)
    local r2 = EventSystem.Execute(20, 20, { pendingGold = 50, hp = 3, maxHp = 5, power = 5 })
    assert(r2.ok, "dice should succeed with enough gold")
    assert(r2.pendingGoldDelta == -20 or r2.pendingGoldDelta == 20 or r2.pendingGoldDelta == 60, "dice should use tuned net results, got: " .. r2.pendingGoldDelta)
    assertEq(r2.partsDelta, 0, "dice no parts change")
    assertEq(r2.hpDelta, 0, "dice no hp change")
end

local function testEventExecAltar()
    EventSystem.Reset(50)
    EventSystem.assignedEvents["30,30"] = "altar"

    -- Not enough HP (hp <= cost)
    local r1 = EventSystem.Execute(30, 30, { pendingGold = 10, hp = 10, maxHp = 100, power = 5 })
    assert(not r1.ok, "altar should fail with hp <= cost")

    -- Enough HP
    local r2 = EventSystem.Execute(30, 30, { pendingGold = 10, hp = 30, maxHp = 100, power = 5 })
    assert(r2.ok, "altar should succeed with hp > cost")
    assertEq(r2.hpDelta, -10, "altar first cost should be 10 hp")
    assertTrue(r2.pendingGoldDelta > 0, "altar should give pending gold")
    assertTrue(r2.rewardItemQuality ~= nil, "altar should return reward item quality")
    assertEq(r2.pressureDelta, 0, "altar tuned rule should not add pressure")
end

local function testEventExecTrap()
    EventSystem.Reset(50)
    EventSystem.assignedEvents["40,40"] = "trap"

    -- Low power - fail
    local r1 = EventSystem.Execute(40, 40, { pendingGold = 10, hp = 3, maxHp = 5, power = 3 })
    assert(r1.ok, "trap always 'succeeds' (executes), even on fail check")
    assertEq(r1.goldDelta, 0, "trap fail gives no gold")
    assertEq(r1.hpDelta, -1, "trap fail costs 1 hp")
    assertEq(r1.pressureDelta, 5, "trap fail should raise pressure")

    -- Reset for high power test
    EventSystem.Reset(50)
    EventSystem.assignedEvents["40,40"] = "trap"

    -- High power - success
    local r2 = EventSystem.Execute(40, 40, { pendingGold = 10, hp = 3, maxHp = 5, power = 10 })
    assert(r2.ok, "trap should succeed")
    assertEq(r2.pendingGoldDelta, 25, "trap success gives pending gold")
    assertTrue(#(r2.rewardItems or {}) == 2, "trap success gives reward item descriptors")
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
    { name = "v0.3 balance combat rules", fn = testV03BalanceCombatRules },
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
    { name = "tradable loose parts only", fn = testTradableLoosePartsOnly },
    { name = "remove concrete tradable settlement safe", fn = testRemoveConcreteTradableSettlementSafe },
    { name = "meta progress load recovery defaults", fn = testMetaProgressLoadRecoveryDefaults },
    { name = "meta progress record extraction recovery", fn = testMetaProgressRecordExtractionRecovery },
    { name = "meta progress recent recovery trim", fn = testMetaProgressRecentRecoveryTrim },
    { name = "meta progress failure does not record recovery", fn = testMetaProgressFailureDoesNotRecordRecovery },
    { name = "meta progress warehouse sell and protection", fn = testMetaProgressWarehouseSellAndProtection },
    { name = "meta progress failure salvages highest item", fn = testMetaProgressFailureSalvagesHighestItem },
    { name = "display adapters protect equipment and consumables", fn = testDisplayAdaptersProtectEquipmentAndConsumables },
    { name = "meta progress load consumable and loadout defaults", fn = testMetaProgressLoadConsumableAndLoadoutDefaults },
    { name = "unified display and warehouse categories", fn = testUnifiedDisplayAndWarehouseCategories },
    { name = "run inventory hud summary adapter", fn = testRunInventoryHUDSummary },
    { name = "consumable purchase loadout and run use", fn = testConsumablePurchaseLoadoutAndRunUse },
    { name = "ui layout round trip", fn = testUILayoutRoundTrip },
    { name = "ui theme missing image safe", fn = testUIThemeMissingImageSafe },
    { name = "main entry source contract", fn = testMainEntrySourceContract },
    { name = "equipment requires equipped for bonus", fn = testEquipmentRequiresEquippedForBonus },
    { name = "consumable loadout zero does not enter run", fn = testConsumableLoadoutZeroDoesNotEnterRun },
    { name = "meta progress growth effects still apply", fn = testMetaProgressGrowthEffectsStillApply },
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
