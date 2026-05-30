-- ============================================================================
-- RunInventory.lua
-- Tracks one extraction run's loot and searched rooms.
-- ============================================================================

local RunInventory = {}

RunInventory.gold = 0
RunInventory.parts = 0
RunInventory.searchedRooms = {}
RunInventory.failureSalvage = nil
RunInventory.searchBonus = 0  -- 搜索奖励加成百分比(装备效果)
RunInventory.stats = {}

local function newStats()
    return {
        moves = 0,
        searchedRooms = 0,
        chestRooms = 0,
        mineHits = 0,
        mineImmunityUsed = 0,
        monstersDefeated = 0,
        combatDamage = 0,
        trades = 0,
        eventsCompleted = 0,
        diceEvents = 0,
        altarEvents = 0,
        trapEvents = 0,
    }
end

local function cellKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

function RunInventory.Reset()
    RunInventory.gold = 0
    RunInventory.parts = 0
    RunInventory.searchedRooms = {}
    RunInventory.failureSalvage = nil
    RunInventory.searchBonus = 0
    RunInventory.stats = newStats()
end

function RunInventory.CellKey(x, y)
    return cellKey(x, y)
end

function RunInventory.GetReward(minefield, x, y)
    local cell = minefield:GetCellView(x, y)
    local adjacent = (cell and cell.adjacent) or 0
    local seed = minefield.seed or 1
    local roll = (x * 37 + y * 53 + seed * 7) % 100

    local gold = 6 + adjacent * 3 + (roll % 9)
    local parts = 0
    if roll % 5 == 0 then parts = parts + 1 end
    if adjacent >= 3 then parts = parts + 1 end

    -- 宝箱房奖励加成:金币翻倍, 必给零件
    if cell and cell.roomType == "chest" then
        gold = gold * 2 + 10
        parts = parts + 1
    end

    -- 搜索奖励加成(大背包装备效果)
    if RunInventory.searchBonus > 0 then
        gold = math.floor(gold * (1 + RunInventory.searchBonus / 100))
    end

    return { gold = gold, parts = parts, isChest = (cell and cell.roomType == "chest") }
end

function RunInventory.GetSearchState(minefield, run)
    if not run or not minefield then
        return { canSearch = false, searched = false, reason = "not_ready" }
    end

    local p = run:GetPlayer()
    local cell = minefield:GetCellView(p.x, p.y)
    local key = cellKey(p.x, p.y)
    local searched = RunInventory.searchedRooms[key] == true

    if not cell or not cell.revealed or cell.mine then
        return { canSearch = false, searched = searched, reason = "unsafe" }
    end
    if cell.spawn then
        return { canSearch = false, searched = searched, reason = "spawn" }
    end
    if cell.exitId then
        return { canSearch = false, searched = searched, reason = "exit" }
    end
    -- 怪物房不可搜索(只能战斗)
    if cell.roomType == "monster" then
        return { canSearch = false, searched = searched, reason = "monster" }
    end
    if cell.roomType == "event" then
        return { canSearch = false, searched = false, reason = "event" }
    end
    if searched then
        return { canSearch = false, searched = true, reason = "searched", isChest = (cell.roomType == "chest") }
    end

    return {
        canSearch = true,
        searched = false,
        isChest = (cell.roomType == "chest"),
        reward = RunInventory.GetReward(minefield, p.x, p.y),
    }
end

function RunInventory.CanSearch(minefield, run)
    return RunInventory.GetSearchState(minefield, run).canSearch == true
end

function RunInventory.SearchCurrentRoom(minefield, run)
    local state = RunInventory.GetSearchState(minefield, run)
    if not state.canSearch then
        return {
            ok = false,
            status = state.reason,
            searched = state.searched,
        }
    end

    local p = run:GetPlayer()
    local key = cellKey(p.x, p.y)
    local reward = state.reward

    RunInventory.searchedRooms[key] = true
    RunInventory.gold = RunInventory.gold + reward.gold
    RunInventory.parts = RunInventory.parts + reward.parts
    RunInventory.stats.searchedRooms = RunInventory.stats.searchedRooms + 1
    if reward.isChest then
        RunInventory.stats.chestRooms = RunInventory.stats.chestRooms + 1
    end

    return {
        ok = true,
        status = "searched",
        reward = reward,
        gold = RunInventory.gold,
        parts = RunInventory.parts,
    }
end

function RunInventory.GetSearchedCount()
    local count = 0
    for _ in pairs(RunInventory.searchedRooms) do
        count = count + 1
    end
    return count
end

function RunInventory.GetTotals()
    return {
        gold = RunInventory.gold,
        parts = RunInventory.parts,
        searchedRooms = RunInventory.GetSearchedCount(),
        failureSalvage = RunInventory.failureSalvage,
    }
end

function RunInventory.RecordMove()
    RunInventory.stats.moves = RunInventory.stats.moves + 1
end

function RunInventory.RecordMineHit(immuneUsed)
    RunInventory.stats.mineHits = RunInventory.stats.mineHits + 1
    if immuneUsed then
        RunInventory.stats.mineImmunityUsed = RunInventory.stats.mineImmunityUsed + 1
    end
end

function RunInventory.RecordCombat(result)
    if not result or not result.fought then return end
    RunInventory.stats.monstersDefeated = RunInventory.stats.monstersDefeated + 1
    RunInventory.stats.combatDamage = RunInventory.stats.combatDamage + (result.damage or 0)
    if result.reward and not result.dead then
        RunInventory.gold = RunInventory.gold + (result.reward.gold or 0)
        RunInventory.parts = RunInventory.parts + (result.reward.parts or 0)
    end
end

function RunInventory.RecordTrade()
    RunInventory.stats.trades = RunInventory.stats.trades + 1
end

function RunInventory.RecordEvent(eventType)
    RunInventory.stats.eventsCompleted = RunInventory.stats.eventsCompleted + 1
    if eventType == "trader" then
        RunInventory.RecordTrade()
    elseif eventType == "dice" then
        RunInventory.stats.diceEvents = RunInventory.stats.diceEvents + 1
    elseif eventType == "altar" then
        RunInventory.stats.altarEvents = RunInventory.stats.altarEvents + 1
    elseif eventType == "trap" then
        RunInventory.stats.trapEvents = RunInventory.stats.trapEvents + 1
    end
end

function RunInventory.GetRunStats(run)
    return {
        moves = RunInventory.stats.moves,
        searchedRooms = RunInventory.GetSearchedCount(),
        chestRooms = RunInventory.stats.chestRooms,
        mineHits = RunInventory.stats.mineHits,
        mineImmunityUsed = RunInventory.stats.mineImmunityUsed,
        monstersDefeated = RunInventory.stats.monstersDefeated,
        combatDamage = RunInventory.stats.combatDamage,
        trades = RunInventory.stats.trades,
        eventsCompleted = RunInventory.stats.eventsCompleted,
        diceEvents = RunInventory.stats.diceEvents,
        altarEvents = RunInventory.stats.altarEvents,
        trapEvents = RunInventory.stats.trapEvents,
        turns = run and run.turn or 0,
    }
end

--- 撤离成功时的结算:零件按比例转金币
---@param partsToGoldRate? number 每个零件转换的金币数(默认10)
---@return table { totalGold: number, convertedGold: number, directGold: number, parts: number }
function RunInventory.GetExtractionReward(partsToGoldRate)
    partsToGoldRate = partsToGoldRate or 10
    local convertedGold = RunInventory.parts * partsToGoldRate
    return {
        totalGold = RunInventory.gold + convertedGold,
        convertedGold = convertedGold,
        directGold = RunInventory.gold,
        parts = RunInventory.parts,
    }
end

--- 失败保底选项
--- 新机制:金币自动保留(安全资产), 零件全部丢失(风险资产)
--- 保底选择:是否用1个零件换取额外金币(10g)
function RunInventory.GetFailureSalvageOptions()
    local PARTS_SALVAGE_RATE = 10  -- 保底抢救1零件=10金币
    local canSalvagePart = RunInventory.parts >= 1
    return {
        safeGold = RunInventory.gold,       -- 自动保留的金币
        lostParts = RunInventory.parts,     -- 将丢失的零件数
        canSalvagePart = canSalvagePart,    -- 是否有零件可抢救
        salvageBonus = canSalvagePart and PARTS_SALVAGE_RATE or 0,  -- 抢救1零件得到的金币
        currentGold = RunInventory.gold,
        currentParts = RunInventory.parts,
        searchedRooms = RunInventory.GetSearchedCount(),
    }
end

--- 应用保底
---@param choice string "salvage_part"=抢救1零件换金币, "accept"=直接接受结果
function RunInventory.ApplyFailureSalvage(choice)
    local options = RunInventory.GetFailureSalvageOptions()
    local salvage = {
        choice = choice,
        gold = options.safeGold,   -- 金币始终保留
        parts = 0,                  -- 零件全部丢失
        bonus = 0,
    }

    if choice == "salvage_part" and options.canSalvagePart then
        salvage.bonus = options.salvageBonus
        salvage.gold = salvage.gold + options.salvageBonus
    end

    RunInventory.failureSalvage = salvage
    return salvage
end

return RunInventory
