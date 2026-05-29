-- ============================================================================
-- ExtractionRun.lua
-- Thin run-state layer for a minesweeper + extraction loop.
-- Minefield owns the board rules; this module owns player position and exits.
-- ============================================================================

local Minefield = require("systems.Minefield")

local ExtractionRun = {}
ExtractionRun.__index = ExtractionRun

local function abs(value)
    if value < 0 then return -value end
    return value
end

local function copyPlayer(player)
    return { x = player.x, y = player.y }
end

function ExtractionRun.New(config)
    local self = setmetatable({}, ExtractionRun)
    self:Init(config or {})
    return self
end

function ExtractionRun:Init(config)
    self.minefield = config.minefield or Minefield.New(config.minefieldConfig or config)

    local spawn = self.minefield:GetSpawn()
    self.player = { x = spawn.x, y = spawn.y }
    self.phase = "running"
    self.exitId = nil
    self.turn = 0
    self.mineHitsAreFatal = config.mineHitsAreFatal == true
    self.moveRequiresRevealed = config.moveRequiresRevealed ~= false
    self.revealOnMove = config.revealOnMove == true

    if config.revealSpawn ~= false then
        self.minefield:Reveal(self.player.x, self.player.y)
    end
end

function ExtractionRun:GetPlayer()
    return copyPlayer(self.player)
end

function ExtractionRun:GetCurrentCell()
    return self.minefield:GetCell(self.player.x, self.player.y)
end

function ExtractionRun:Reveal(x, y)
    if self.phase ~= "running" then
        return { ok = false, status = "not_running" }
    end

    local result = self.minefield:Reveal(x, y)
    if result.hitMine and self.mineHitsAreFatal then
        self.phase = "failed"
        self.minefield:RevealAllMines()
    end
    return result
end

function ExtractionRun:ToggleFlag(x, y)
    if self.phase ~= "running" then
        return { ok = false, status = "not_running" }
    end
    return self.minefield:ToggleFlag(x, y)
end

function ExtractionRun:Move(dx, dy)
    if self.phase ~= "running" then
        return { ok = false, status = "not_running", player = self:GetPlayer() }
    end
    if abs(dx) + abs(dy) ~= 1 then
        return { ok = false, status = "invalid_direction", player = self:GetPlayer() }
    end

    local targetX = self.player.x + dx
    local targetY = self.player.y + dy
    local target = self.minefield:GetCell(targetX, targetY)

    if not target then
        return { ok = false, status = "out_of_bounds", player = self:GetPlayer() }
    end
    if target.flagged then
        return { ok = false, status = "blocked_flagged", player = self:GetPlayer() }
    end
    if self.moveRequiresRevealed and not target.revealed then
        return { ok = false, status = "blocked_hidden", player = self:GetPlayer() }
    end

    if target.mine then
        local wasTriggered = target.revealed == true
        local reveal = wasTriggered and {
            ok = true,
            status = "already_triggered_mine",
            hitMine = false,
            cells = { self.minefield:GetCellView(targetX, targetY, true) },
        } or self.minefield:Reveal(targetX, targetY)

        if self.mineHitsAreFatal then
            self.phase = "failed"
            self.minefield:RevealAllMines()
            return {
                ok = false,
                status = "hit_mine",
                reveal = reveal,
                hitMine = true,
                mineTriggered = not wasTriggered,
                player = self:GetPlayer(),
            }
        end

        self.player.x = targetX
        self.player.y = targetY
        self.turn = self.turn + 1

        return {
            ok = true,
            status = wasTriggered and "entered_triggered_mine" or "hit_mine",
            reveal = reveal,
            hitMine = not wasTriggered,
            mineTriggered = not wasTriggered,
            player = self:GetPlayer(),
            turn = self.turn,
        }
    end

    local revealResult = nil
    if self.revealOnMove and not target.revealed then
        revealResult = self.minefield:Reveal(targetX, targetY)
        if revealResult.hitMine then
            self.phase = "failed"
            self.minefield:RevealAllMines()
            return {
                ok = false,
                status = "hit_mine",
                reveal = revealResult,
                player = self:GetPlayer(),
            }
        end
    end

    self.player.x = targetX
    self.player.y = targetY
    self.turn = self.turn + 1

    local status = self:CanExtract() and "at_exit" or "moved"
    return {
        ok = true,
        status = status,
        reveal = revealResult,
        player = self:GetPlayer(),
        exitId = target.exitId,
        turn = self.turn,
    }
end

function ExtractionRun:MoveTo(x, y)
    local dx = x - self.player.x
    local dy = y - self.player.y
    return self:Move(dx, dy)
end

function ExtractionRun:CanExtract()
    if self.phase ~= "running" then
        return false
    end
    local cell = self:GetCurrentCell()
    return cell ~= nil and cell.exitId ~= nil
end

function ExtractionRun:Extract()
    if not self:CanExtract() then
        return { ok = false, status = "not_at_exit", player = self:GetPlayer() }
    end

    local cell = self:GetCurrentCell()
    self.phase = "extracted"
    self.exitId = cell.exitId
    return {
        ok = true,
        status = "extracted",
        exitId = self.exitId,
        player = self:GetPlayer(),
        turn = self.turn,
    }
end

function ExtractionRun:GetState(revealMines)
    return {
        phase = self.phase,
        player = self:GetPlayer(),
        turn = self.turn,
        exitId = self.exitId,
        canExtract = self:CanExtract(),
        minefield = {
            width = self.minefield.width,
            height = self.minefield.height,
            seed = self.minefield.seed,
            mineCount = self.minefield.mineCount,
            revealedSafeCount = self.minefield.revealedSafeCount,
            safeCellCount = self.minefield.safeCellCount,
            solved = self.minefield:IsSolved(),
            cells = self.minefield:GetVisibleMap(revealMines),
        },
    }
end

return ExtractionRun
