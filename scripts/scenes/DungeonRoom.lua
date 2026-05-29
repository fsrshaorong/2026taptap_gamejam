-- ============================================================================
-- DungeonRoom.lua
-- Draws the current room, handles room-local player movement, and hit tests
-- door/search interactions. Minefield coordinates stay owned by ExtractionRun.
-- ============================================================================

local DungeonRoom = {}

local CONFIG = {
    margin = 60,
    topOffset = 40,
    bottomSpace = 80,
    doorSize = 40,
    playerRadius = 16,
    moveStep = 12,
    moveSpeed = 300,
    searchW = 58,
    searchH = 36,
    enemyRadius = 22,
}

local playerPos = { x = 0.5, y = 0.5 }

-- 踩雷红闪效果
local mineFlashTimer = 0
local MINE_FLASH_DURATION = 0.6

function DungeonRoom.ResetPlayer()
    playerPos.x = 0.5
    playerPos.y = 0.5
end

--- 触发踩雷红闪效果
function DungeonRoom.TriggerMineFlash()
    mineFlashTimer = MINE_FLASH_DURATION
end

--- 更新红闪计时器（在 HandleUpdate 中调用）
function DungeonRoom.Update(dt)
    if mineFlashTimer > 0 then
        mineFlashTimer = mineFlashTimer - dt
        if mineFlashTimer < 0 then mineFlashTimer = 0 end
    end
end

function DungeonRoom.GetLayout(w, h)
    return {
        x = CONFIG.margin,
        y = CONFIG.margin + CONFIG.topOffset,
        w = w - CONFIG.margin * 2,
        h = h - CONFIG.margin * 2 - CONFIG.bottomSpace,
        doorSize = CONFIG.doorSize,
    }
end

local function getCurrentLayout(screenW, screenH, dpr)
    return DungeonRoom.GetLayout(screenW / dpr, screenH / dpr)
end

function DungeonRoom.PlacePlayerFromEntry(dx, dy, screenW, screenH, dpr)
    local layout = getCurrentLayout(screenW, screenH, dpr)
    local minX = CONFIG.playerRadius / layout.w + 0.035
    local maxX = 1 - minX
    local minY = CONFIG.playerRadius / layout.h + 0.035
    local maxY = 1 - minY

    if dx > 0 then
        playerPos.x = minX
        playerPos.y = 0.5
    elseif dx < 0 then
        playerPos.x = maxX
        playerPos.y = 0.5
    elseif dy > 0 then
        playerPos.x = 0.5
        playerPos.y = minY
    elseif dy < 0 then
        playerPos.x = 0.5
        playerPos.y = maxY
    else
        DungeonRoom.ResetPlayer()
    end
end

local function isAlignedWithDoor(dx, dy, layout)
    local doorHalfX = (layout.doorSize * 0.8 + CONFIG.playerRadius) / layout.w
    local doorHalfY = (layout.doorSize * 0.8 + CONFIG.playerRadius) / layout.h

    if dx ~= 0 then
        return math.abs(playerPos.y - 0.5) <= doorHalfY
    end
    if dy ~= 0 then
        return math.abs(playerPos.x - 0.5) <= doorHalfX
    end
    return false
end

function DungeonRoom.MovePlayer(dx, dy, screenW, screenH, dpr, dt)
    local layout = getCurrentLayout(screenW, screenH, dpr)
    local minX = CONFIG.playerRadius / layout.w
    local maxX = 1 - minX
    local minY = CONFIG.playerRadius / layout.h
    local maxY = 1 - minY

    local elapsed = tonumber(dt)
    local stepPixels = CONFIG.moveStep
    if elapsed and elapsed > 0 then
        if elapsed > 0.05 then elapsed = 0.05 end
        stepPixels = CONFIG.moveSpeed * elapsed
    end

    local stepX = stepPixels / layout.w
    local stepY = stepPixels / layout.h
    local nextX = playerPos.x + dx * stepX
    local nextY = playerPos.y + dy * stepY

    local crossingDoor =
        (dx < 0 and nextX <= minX) or
        (dx > 0 and nextX >= maxX) or
        (dy < 0 and nextY <= minY) or
        (dy > 0 and nextY >= maxY)

    if crossingDoor and isAlignedWithDoor(dx, dy, layout) then
        if dx ~= 0 then playerPos.y = 0.5 end
        if dy ~= 0 then playerPos.x = 0.5 end
        return { action = "enter", dx = dx, dy = dy }
    end

    if nextX < minX then nextX = minX end
    if nextX > maxX then nextX = maxX end
    if nextY < minY then nextY = minY end
    if nextY > maxY then nextY = maxY end

    local blockedByWall = crossingDoor
    playerPos.x = nextX
    playerPos.y = nextY

    if blockedByWall then
        return { action = "blocked_wall" }
    end
    return { action = "moved" }
end

function DungeonRoom.GetDoors(layout, playerCell, minefield)
    return {
        { dir = "上", dx = 0, dy = -1, x = layout.x + layout.w / 2 - layout.doorSize / 2, y = layout.y - 5 },
        { dir = "下", dx = 0, dy = 1, x = layout.x + layout.w / 2 - layout.doorSize / 2, y = layout.y + layout.h - layout.doorSize + 5 },
        { dir = "左", dx = -1, dy = 0, x = layout.x - 5, y = layout.y + layout.h / 2 - layout.doorSize / 2 },
        { dir = "右", dx = 1, dy = 0, x = layout.x + layout.w - layout.doorSize + 5, y = layout.y + layout.h / 2 - layout.doorSize / 2 },
    }
end

function DungeonRoom.GetSearchPointRect(layout)
    return {
        x = layout.x + layout.w * 0.68 - CONFIG.searchW / 2,
        y = layout.y + layout.h * 0.58 - CONFIG.searchH / 2,
        w = CONFIG.searchW,
        h = CONFIG.searchH,
    }
end

local function drawSearchPoint(vg, layout, searchState)
    if not searchState then return end
    if not searchState.canSearch and not searchState.searched then
        return
    end

    local rect = DungeonRoom.GetSearchPointRect(layout)
    local bodyColor = searchState.searched and nvgRGBA(75, 65, 55, 180) or nvgRGBA(145, 95, 45, 240)
    local lidColor = searchState.searched and nvgRGBA(95, 85, 75, 180) or nvgRGBA(190, 135, 65, 255)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, rect.x, rect.y + rect.h * 0.25, rect.w, rect.h * 0.75, 4)
    nvgFillColor(vg, bodyColor)
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(65, 45, 25, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, rect.x + 4, rect.y, rect.w - 8, rect.h * 0.35, 4)
    nvgFillColor(vg, lidColor)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, rect.x + rect.w * 0.45, rect.y + rect.h * 0.25, rect.w * 0.1, rect.h * 0.7)
    nvgFillColor(vg, nvgRGBA(210, 180, 85, searchState.searched and 120 or 240))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if searchState.searched then
        nvgFillColor(vg, nvgRGBA(170, 160, 145, 180))
        nvgText(vg, rect.x + rect.w / 2, rect.y + rect.h + 6, "已搜索")
    else
        nvgFillColor(vg, nvgRGBA(255, 230, 140, 230))
        nvgText(vg, rect.x + rect.w / 2, rect.y + rect.h + 6, "F 搜索")
    end
end

local function drawExitDevice(vg, layout, cell)
    if not cell or not cell.exitId then return end

    local cx = layout.x + layout.w / 2
    local y = layout.y + 54

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 58, y - 18, 116, 36, 6)
    nvgFillColor(vg, nvgRGBA(25, 95, 65, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 255, 140, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 255, 170, 255))
    nvgText(vg, cx, y, "撤离装置")
end

local function drawRoomGrid(vg, layout)
    nvgStrokeColor(vg, nvgRGBA(70, 80, 105, 80))
    nvgStrokeWidth(vg, 1)
    for i = 1, 5 do
        local x = layout.x + layout.w * i / 6
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, layout.y + 8)
        nvgLineTo(vg, x, layout.y + layout.h - 8)
        nvgStroke(vg)
    end
    for i = 1, 3 do
        local y = layout.y + layout.h * i / 4
        nvgBeginPath(vg)
        nvgMoveTo(vg, layout.x + 8, y)
        nvgLineTo(vg, layout.x + layout.w - 8, y)
        nvgStroke(vg)
    end
end

local function doorColorFor(cell)
    if cell and cell.flagged then
        return nvgRGBA(205, 55, 55, 230)
    end
    if cell and cell.revealed then
        return nvgRGBA(65, 165, 90, 230)
    end
    return nvgRGBA(95, 95, 135, 230)
end

function DungeonRoom.Draw(vg, w, h, context)
    local run = context.run
    local minefield = context.minefield
    if not run or not minefield then return end

    local p = run:GetPlayer()
    local cell = minefield:GetCellView(p.x, p.y)
    local adj = (cell and cell.adjacent) or 0
    local roomType = cell and cell.roomType or "normal"

    -- 房间背景色根据房型变化
    local bgR, bgG, bgB = 18 + adj * 8, 24 + math.max(0, 3 - adj), 38 + adj * 5
    local roomStrokeR, roomStrokeG, roomStrokeB = 90, 100, 130
    local roomFillR, roomFillG, roomFillB = 25, 30, 45

    if roomType == "mine" then
        -- 已触发雷房：暗红色调
        bgR, bgG, bgB = 40, 15, 15
        roomFillR, roomFillG, roomFillB = 45, 20, 20
        roomStrokeR, roomStrokeG, roomStrokeB = 160, 60, 50
    elseif roomType == "chest" then
        -- 宝箱房：暖金色调
        bgR, bgG, bgB = 30, 25, 12
        roomFillR, roomFillG, roomFillB = 35, 30, 18
        roomStrokeR, roomStrokeG, roomStrokeB = 180, 150, 60
    elseif roomType == "monster" then
        -- 怪物房：暗紫色调
        bgR, bgG, bgB = 28, 15, 30
        roomFillR, roomFillG, roomFillB = 32, 20, 38
        roomStrokeR, roomStrokeG, roomStrokeB = 140, 60, 150
    end

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 255))
    nvgFill(vg)

    local layout = DungeonRoom.GetLayout(w, h)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, layout.x, layout.y, layout.w, layout.h, 8)
    nvgFillColor(vg, nvgRGBA(roomFillR, roomFillG, roomFillB, 210))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(roomStrokeR, roomStrokeG, roomStrokeB, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    drawRoomGrid(vg, layout)

    for _, door in ipairs(DungeonRoom.GetDoors(layout, p, minefield)) do
        local nx = p.x + door.dx
        local ny = p.y + door.dy
        if minefield:IsInside(nx, ny) then
            local neighbor = minefield:GetCellView(nx, ny)
            local color = doorColorFor(neighbor)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, door.x, door.y, layout.doorSize, layout.doorSize, 5)
            nvgFillColor(vg, color)
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(220, 225, 240, 90))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, door.x + layout.doorSize / 2, door.y + layout.doorSize / 2, door.dir)
        end
    end

    drawSearchPoint(vg, layout, context.searchState)
    drawExitDevice(vg, layout, cell)

    -- 绘制敌人（活着=红色威胁，死了=灰色倒地）
    local enemy = context.enemy
    if enemy then
        local enemyX = layout.x + layout.w * 0.35
        local enemyY = layout.y + layout.h * 0.45
        local er = CONFIG.enemyRadius

        if enemy.alive then
            -- 活着的敌人：红色大圆 + 角 + 眼睛
            nvgBeginPath(vg)
            nvgCircle(vg, enemyX, enemyY, er)
            nvgFillColor(vg, nvgRGBA(180, 35, 35, 240))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 80, 60, 255))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)

            -- 两只角
            nvgBeginPath(vg)
            nvgMoveTo(vg, enemyX - 10, enemyY - er + 2)
            nvgLineTo(vg, enemyX - 6, enemyY - er - 10)
            nvgLineTo(vg, enemyX - 2, enemyY - er + 2)
            nvgFillColor(vg, nvgRGBA(255, 100, 50, 255))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, enemyX + 2, enemyY - er + 2)
            nvgLineTo(vg, enemyX + 6, enemyY - er - 10)
            nvgLineTo(vg, enemyX + 10, enemyY - er + 2)
            nvgFillColor(vg, nvgRGBA(255, 100, 50, 255))
            nvgFill(vg)

            -- 眼睛（红色发光）
            nvgBeginPath(vg)
            nvgCircle(vg, enemyX - 7, enemyY - 3, 4)
            nvgCircle(vg, enemyX + 7, enemyY - 3, 4)
            nvgFillColor(vg, nvgRGBA(255, 220, 50, 255))
            nvgFill(vg)

            -- 嘴巴
            nvgBeginPath(vg)
            nvgMoveTo(vg, enemyX - 8, enemyY + 7)
            nvgLineTo(vg, enemyX - 4, enemyY + 11)
            nvgLineTo(vg, enemyX, enemyY + 8)
            nvgLineTo(vg, enemyX + 4, enemyY + 11)
            nvgLineTo(vg, enemyX + 8, enemyY + 7)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 255))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- 名字和战力
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 90, 70, 255))
            nvgText(vg, enemyX, enemyY + er + 8, enemy.name)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(255, 180, 100, 230))
            nvgText(vg, enemyX, enemyY + er + 24, "战力: " .. enemy.power)
        else
            -- 已击败的敌人：灰色 + X 标记
            nvgBeginPath(vg)
            nvgCircle(vg, enemyX, enemyY, er * 0.8)
            nvgFillColor(vg, nvgRGBA(60, 55, 55, 160))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 90, 90, 180))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)

            -- X 标记
            local xr = er * 0.4
            nvgBeginPath(vg)
            nvgMoveTo(vg, enemyX - xr, enemyY - xr)
            nvgLineTo(vg, enemyX + xr, enemyY + xr)
            nvgMoveTo(vg, enemyX + xr, enemyY - xr)
            nvgLineTo(vg, enemyX - xr, enemyY + xr)
            nvgStrokeColor(vg, nvgRGBA(180, 60, 60, 200))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)

            -- 已击败文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(140, 130, 130, 180))
            nvgText(vg, enemyX, enemyY + er * 0.8 + 6, "已击败")
        end
    end

    local playerCX = layout.x + playerPos.x * layout.w
    local playerCY = layout.y + playerPos.y * layout.h
    nvgBeginPath(vg)
    nvgCircle(vg, playerCX, playerCY, CONFIG.playerRadius)
    nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    if cell and cell.adjacent and cell.adjacent > 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 210))
        nvgText(vg, playerCX, playerCY + 40, "附近危险: " .. cell.adjacent)
    end

    if cell and cell.exitId then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
        nvgText(vg, playerCX, layout.y + 20, "[ 撤离点 - 按 E 撤离 ]")
    end

    if cell and cell.spawn then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 150))
        nvgText(vg, playerCX, layout.y + layout.h - 10, "出生点")
    end

    -- 绘制血量条（玩家头顶）
    local combat = context.combat
    if combat then
        local barW = 50
        local barH = 6
        local barX = playerCX - barW / 2
        local barY = playerCY - CONFIG.playerRadius - 14
        local hpRatio = combat.hp / combat.maxHp

        -- 血条背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(40, 10, 10, 200))
        nvgFill(vg)

        -- 血条前景
        local r = math.floor(255 * (1 - hpRatio))
        local g = math.floor(200 * hpRatio)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 3)
        nvgFillColor(vg, nvgRGBA(r, g, 30, 240))
        nvgFill(vg)

        -- 血条边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgStrokeColor(vg, nvgRGBA(180, 180, 180, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    -- 已触发雷房提示文字
    if roomType == "mine" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 100, 80, 200))
        nvgText(vg, layout.x + layout.w / 2, layout.y + layout.h - 12, "⚠ 已触发雷房 · 不再触发")
    end

    -- 宝箱房标题
    if roomType == "chest" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 210, 80, 230))
        nvgText(vg, layout.x + layout.w / 2, layout.y + 12, "宝箱房")
    end

    -- 怪物房标题
    if roomType == "monster" and not context.enemy then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 230))
        nvgText(vg, layout.x + layout.w / 2, layout.y + 12, "怪物房")
    end

    -- 踩雷红闪叠层（渐消）
    if mineFlashTimer > 0 then
        local alpha = math.floor(180 * (mineFlashTimer / MINE_FLASH_DURATION))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(220, 30, 20, alpha))
        nvgFill(vg)
    end
end

function DungeonRoom.HitTestSearchPoint(mx, my, screenW, screenH, dpr, searchState)
    if not searchState or (not searchState.canSearch and not searchState.searched) then
        return false
    end
    local rect = DungeonRoom.GetSearchPointRect(getCurrentLayout(screenW, screenH, dpr))
    return mx >= rect.x and mx <= rect.x + rect.w and my >= rect.y and my <= rect.y + rect.h
end

function DungeonRoom.HitTestDoor(mx, my, screenW, screenH, dpr, run, minefield)
    if not run or not minefield then return nil end

    local layout = getCurrentLayout(screenW, screenH, dpr)
    local p = run:GetPlayer()

    for _, door in ipairs(DungeonRoom.GetDoors(layout, p, minefield)) do
        local nx = p.x + door.dx
        local ny = p.y + door.dy
        if minefield:IsInside(nx, ny) then
            if mx >= door.x and mx <= door.x + layout.doorSize and
               my >= door.y and my <= door.y + layout.doorSize then
                return { dx = door.dx, dy = door.dy }
            end
        end
    end

    return nil
end

return DungeonRoom
