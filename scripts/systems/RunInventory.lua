-- ============================================================================
-- RunInventory.lua
-- Tracks one extraction run's loot and searched rooms.
-- ============================================================================

local RunInventory = {}

RunInventory.gold = 0
RunInventory.parts = 0
RunInventory.searchedRooms = {}

local function cellKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

function RunInventory.Reset()
    RunInventory.gold = 0
    RunInventory.parts = 0
    RunInventory.searchedRooms = {}
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

    return { gold = gold, parts = parts }
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
    if searched then
        return { canSearch = false, searched = true, reason = "searched" }
    end

    return {
        canSearch = true,
        searched = false,
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
    }
end

return RunInventory
