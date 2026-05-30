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

-- 图片句柄(Init 时加载)
local imgPlayer = -1
local imgEnemy = -1
local imgRoomSafe = -1
local imgRoomDanger = -1
local imgRoomTreasure = -1
local imgRoomExit = -1
local imagesLoaded = false

--- 初始化图片资源(只调用一次)
function DungeonRoom.Init(vg)
    if imagesLoaded then return end
    imgPlayer = nvgCreateImage(vg, "Textures/player.png", 0)
    imgEnemy = nvgCreateImage(vg, "Textures/enemy_slime.png", 0)
    imgRoomSafe = nvgCreateImage(vg, "Textures/room_safe.png", 0)
    imgRoomDanger = nvgCreateImage(vg, "Textures/room_danger.png", 0)
    imgRoomTreasure = nvgCreateImage(vg, "Textures/room_treasure.png", 0)
    imgRoomExit = nvgCreateImage(vg, "Textures/room_exit.png", 0)
    imgRoomEvent = nvgCreateImage(vg, "Textures/room_event.png", 0)
    imgRoomMonster = nvgCreateImage(vg, "Textures/room_monster.png", 0)
    imagesLoaded = true
end

--- 绘制图片精灵(居中, 指定大小)
local function drawSprite(vg, img, cx, cy, size, alpha)
    if img < 0 then return end
    alpha = alpha or 1.0
    local half = size / 2
    local paint = nvgImagePattern(vg, cx - half, cy - half, size, size, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, cx - half, cy - half, size, size)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制房间背景贴图(平铺填充区域)
local function drawRoomBg(vg, img, x, y, w, h, alpha)
    if img < 0 then return end
    alpha = alpha or 1.0
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 8)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

local playerPos = { x = 0.5, y = 0.5 }

-- 踩雷红闪效果
local mineFlashTimer = 0
local MINE_FLASH_DURATION = 0.6
local chestOpenTimer = 0
local tradePulseTimer = 0
local exitPulseTimer = 0
local roomTime = 0
local CHEST_OPEN_DURATION = 0.9
local TRADE_PULSE_DURATION = 0.8
local EXIT_PULSE_DURATION = 0.8

function DungeonRoom.ResetPlayer()
    playerPos.x = 0.5
    playerPos.y = 0.5
end

--- 触发踩雷红闪效果
function DungeonRoom.TriggerMineFlash()
    mineFlashTimer = MINE_FLASH_DURATION
end

function DungeonRoom.TriggerChestOpen()
    chestOpenTimer = CHEST_OPEN_DURATION
end

function DungeonRoom.TriggerTradePulse()
    tradePulseTimer = TRADE_PULSE_DURATION
end

function DungeonRoom.TriggerExitPulse()
    exitPulseTimer = EXIT_PULSE_DURATION
end

--- 更新红闪计时器(在 HandleUpdate 中调用)
function DungeonRoom.Update(dt)
    roomTime = roomTime + dt
    if mineFlashTimer > 0 then
        mineFlashTimer = mineFlashTimer - dt
        if mineFlashTimer < 0 then mineFlashTimer = 0 end
    end
    if chestOpenTimer > 0 then
        chestOpenTimer = chestOpenTimer - dt
        if chestOpenTimer < 0 then chestOpenTimer = 0 end
    end
    if tradePulseTimer > 0 then
        tradePulseTimer = tradePulseTimer - dt
        if tradePulseTimer < 0 then tradePulseTimer = 0 end
    end
    if exitPulseTimer > 0 then
        exitPulseTimer = exitPulseTimer - dt
        if exitPulseTimer < 0 then exitPulseTimer = 0 end
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
        x = layout.x + layout.w * 0.5 - CONFIG.searchW / 2,
        y = layout.y + layout.h * 0.5 - CONFIG.searchH / 2,
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
    local flash = chestOpenTimer / CHEST_OPEN_DURATION
    local bodyColor = searchState.searched and nvgRGBA(75, 65, 55, 180) or nvgRGBA(145, 95, 45, 240)
    local lidColor = searchState.searched and nvgRGBA(95, 85, 75, 180) or nvgRGBA(190, 135, 65, 255)
    if flash > 0 then
        bodyColor = nvgRGBA(185, 120, 45, 240)
        lidColor = nvgRGBA(255, 205, 80, 255)
    end

    if flash > 0 then
        local glow = math.floor(150 * flash)
        nvgBeginPath(vg)
        nvgCircle(vg, rect.x + rect.w / 2, rect.y + rect.h / 2, 42 + 28 * (1 - flash))
        nvgFillColor(vg, nvgRGBA(255, 205, 70, glow))
        nvgFill(vg)
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, rect.x, rect.y + rect.h * 0.25, rect.w, rect.h * 0.75, 4)
    nvgFillColor(vg, bodyColor)
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(65, 45, 25, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgBeginPath(vg)
    local lidLift = flash * 10
    nvgRoundedRect(vg, rect.x + 4, rect.y - lidLift, rect.w - 8, rect.h * 0.35, 4)
    nvgFillColor(vg, lidColor)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, rect.x + rect.w * 0.45, rect.y + rect.h * 0.25, rect.w * 0.1, rect.h * 0.7)
    nvgFillColor(vg, nvgRGBA(210, 180, 85, searchState.searched and 120 or 240))
    nvgFill(vg)

    if flash > 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 235, 120, math.floor(255 * flash)))
        nvgText(vg, rect.x + rect.w / 2, rect.y - 20 - 18 * (1 - flash), "+")

        for i = -1, 1 do
            local coinX = rect.x + rect.w / 2 + i * 18
            local coinY = rect.y + 8 - (1 - flash) * (18 + math.abs(i) * 8)
            nvgBeginPath(vg)
            nvgCircle(vg, coinX, coinY, 5)
            nvgFillColor(vg, nvgRGBA(255, 210, 70, math.floor(230 * flash)))
            nvgFill(vg)
        end
    end

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
    local idlePulse = (math.sin(roomTime * 3.0) + 1) * 0.5
    local activePulse = exitPulseTimer / EXIT_PULSE_DURATION
    local glowAlpha = math.floor(45 + idlePulse * 45 + activePulse * 120)
    local glowRadius = 56 + idlePulse * 10 + activePulse * 24

    nvgBeginPath(vg)
    nvgCircle(vg, cx, y, glowRadius)
    nvgFillColor(vg, nvgRGBA(60, 235, 140, glowAlpha))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 58, y - 18, 116, 36, 6)
    nvgFillColor(vg, nvgRGBA(25, 95 + math.floor(idlePulse * 20), 65, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 255, 140, 220 + math.floor(activePulse * 35)))
    nvgStrokeWidth(vg, 2 + activePulse * 2)
    nvgStroke(vg)

    for i = 0, 2 do
        local dotX = cx - 30 + i * 30
        local dotAlpha = 120 + math.floor(100 * ((math.sin(roomTime * 5 + i) + 1) * 0.5))
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, y + 22, 3)
        nvgFillColor(vg, nvgRGBA(120, 255, 170, dotAlpha))
        nvgFill(vg)
    end

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
        -- 已触发雷房:暗红色调
        bgR, bgG, bgB = 40, 15, 15
        roomFillR, roomFillG, roomFillB = 45, 20, 20
        roomStrokeR, roomStrokeG, roomStrokeB = 160, 60, 50
    elseif roomType == "chest" then
        -- 宝箱房:暖金色调
        bgR, bgG, bgB = 30, 25, 12
        roomFillR, roomFillG, roomFillB = 35, 30, 18
        roomStrokeR, roomStrokeG, roomStrokeB = 180, 150, 60
    elseif roomType == "monster" then
        -- 怪物房:暗紫色调
        bgR, bgG, bgB = 28, 15, 30
        roomFillR, roomFillG, roomFillB = 32, 20, 38
        roomStrokeR, roomStrokeG, roomStrokeB = 140, 60, 150
    elseif roomType == "event" then
        -- 事件房:暗蓝绿色调
        bgR, bgG, bgB = 12, 25, 30
        roomFillR, roomFillG, roomFillB = 18, 32, 40
        roomStrokeR, roomStrokeG, roomStrokeB = 60, 160, 180
    end

    local layout = DungeonRoom.GetLayout(w, h)

    -- 房间背景贴图(全屏覆盖)
    DungeonRoom.Init(vg)
    local roomBgImg = imgRoomSafe
    if roomType == "mine" then roomBgImg = imgRoomDanger
    elseif roomType == "chest" then roomBgImg = imgRoomTreasure
    elseif roomType == "monster" then roomBgImg = imgRoomMonster
    elseif roomType == "event" then roomBgImg = imgRoomEvent
    end
    if cell and cell.exitId then roomBgImg = imgRoomExit end

    if roomBgImg >= 0 then
        -- 全屏绘制背景图
        local paint = nvgImagePattern(vg, 0, 0, w, h, 0, roomBgImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 255))
        nvgFill(vg)
    end

    -- 房间边框(已隐藏, 全屏背景不需要)

    drawRoomGrid(vg, layout)

    if context.monsterFleeActive then
        local pulse = (math.sin(roomTime * 10) + 1) * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, layout.x + 5, layout.y + 5, layout.w - 10, layout.h - 10, 8)
        nvgStrokeColor(vg, nvgRGBA(255, 70, 60, 130 + math.floor(90 * pulse)))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    -- 门按钮视觉已隐藏(点击检测保留在 HitTest 中)

    drawSearchPoint(vg, layout, context.searchState)
    drawExitDevice(vg, layout, cell)

    -- 绘制敌人(活着=红色威胁, 死了=灰色倒地)
    local enemy = context.enemy
    if enemy then
        local enemyX = layout.x + layout.w * 0.35
        local enemyY = layout.y + layout.h * 0.45
        local er = CONFIG.enemyRadius

        if enemy.alive then
            local threatPulse = (math.sin(roomTime * 6) + 1) * 0.5
            local fleeAlpha = context.monsterFleeActive and 110 or 45
            nvgBeginPath(vg)
            nvgCircle(vg, enemyX, enemyY, er + 18 + threatPulse * 8)
            nvgFillColor(vg, nvgRGBA(210, 30, 40, fleeAlpha))
            nvgFill(vg)

            -- 敌人精灵图
            local enemySize = er * 2.8
            drawSprite(vg, imgEnemy, enemyX, enemyY, enemySize, 1.0)
            -- fallback
            if imgEnemy < 0 then
                nvgBeginPath(vg)
                nvgCircle(vg, enemyX, enemyY, er)
                nvgFillColor(vg, nvgRGBA(180, 35, 35, 240))
                nvgFill(vg)
            end

            -- 名字和战力
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 90, 70, 255))
            nvgText(vg, enemyX, enemyY + er + 8, enemy.name)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(255, 180, 100, 230))
            nvgText(vg, enemyX, enemyY + er + 24, "战力: " .. enemy.power)

            if context.monsterFleeActive then
                nvgFontSize(vg, 13)
                nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
                local remain = math.max(0, math.ceil(context.monsterFleeTimer or 0))
                nvgText(vg, enemyX, enemyY + er + 42, "逃跑窗口: " .. remain .. "s")
            end
        else
            -- 已击败的敌人:灰色 + X 标记
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
    -- 玩家精灵
    local playerSize = CONFIG.playerRadius * 2.5
    drawSprite(vg, imgPlayer, playerCX, playerCY, playerSize, 1.0)
    -- 如果图片加载失败, fallback 圆形
    if imgPlayer < 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, playerCX, playerCY, CONFIG.playerRadius)
        nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    if cell and cell.adjacent and cell.adjacent > 0 and roomType ~= "mine" then
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

    -- 绘制血量条(玩家头顶)
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

    -- 已触发雷房:中央显示地雷标志 + 提示
    if roomType == "mine" then
        local cx = layout.x + layout.w / 2
        local cy = layout.y + layout.h * 0.38
        local flash = mineFlashTimer / MINE_FLASH_DURATION

        if flash > 0 then
            for i = 1, 2 do
                local radius = 28 + (1 - flash) * (34 + i * 18)
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy, radius)
                nvgStrokeColor(vg, nvgRGBA(255, 95, 60, math.floor(180 * flash / i)))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end
        end

        -- 地雷图标(大圆 + 刺)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 20)
        nvgFillColor(vg, nvgRGBA(60, 30, 30, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 70, 50, 220))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 十字线
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - 26)
        nvgLineTo(vg, cx, cy + 26)
        nvgMoveTo(vg, cx - 26, cy)
        nvgLineTo(vg, cx + 26, cy)
        nvgStrokeColor(vg, nvgRGBA(200, 70, 50, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 地面裂纹
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 42, cy + 18)
        nvgLineTo(vg, cx - 18, cy + 9)
        nvgLineTo(vg, cx - 4, cy + 22)
        nvgMoveTo(vg, cx + 12, cy + 18)
        nvgLineTo(vg, cx + 34, cy + 8)
        nvgLineTo(vg, cx + 48, cy + 24)
        nvgMoveTo(vg, cx - 8, cy - 26)
        nvgLineTo(vg, cx + 6, cy - 42)
        nvgLineTo(vg, cx + 18, cy - 30)
        nvgStrokeColor(vg, nvgRGBA(190, 75, 60, 150))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(220, 90, 70, 230))
        nvgText(vg, cx, cy + 30, "已触发地雷")

        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 140, 130, 180))
        nvgText(vg, cx, cy + 56, "不再触发 - 安全通过")
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

    -- 事件房 NPC 绘制
    if roomType == "event" then
        local npcX = layout.x + layout.w * 0.5
        local npcY = layout.y + layout.h * 0.35
        local traded = context.eventTraded
        local tradeFlash = tradePulseTimer / TRADE_PULSE_DURATION

        if tradeFlash > 0 then
            nvgBeginPath(vg)
            nvgCircle(vg, npcX, npcY, 44 + 24 * (1 - tradeFlash))
            nvgFillColor(vg, nvgRGBA(70, 220, 230, math.floor(120 * tradeFlash)))
            nvgFill(vg)
        end

        -- 小摊位
        nvgBeginPath(vg)
        nvgRoundedRect(vg, npcX - 44, npcY + 42, 88, 20, 4)
        nvgFillColor(vg, traded and nvgRGBA(45, 55, 55, 170) or nvgRGBA(55, 115, 120, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, traded and nvgRGBA(80, 95, 95, 130) or nvgRGBA(100, 220, 210, 190))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- NPC 身体(蓝绿色圆形)
        nvgBeginPath(vg)
        nvgCircle(vg, npcX, npcY, 18)
        nvgFillColor(vg, traded and nvgRGBA(50, 60, 60, 160) or nvgRGBA(40, 140, 150, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, traded and nvgRGBA(80, 100, 100, 150) or nvgRGBA(80, 220, 230, 255))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- NPC 帽子
        nvgBeginPath(vg)
        nvgMoveTo(vg, npcX - 12, npcY - 14)
        nvgLineTo(vg, npcX, npcY - 28)
        nvgLineTo(vg, npcX + 12, npcY - 14)
        nvgClosePath(vg)
        nvgFillColor(vg, traded and nvgRGBA(60, 70, 70, 150) or nvgRGBA(60, 180, 190, 240))
        nvgFill(vg)

        -- NPC 眼睛
        nvgBeginPath(vg)
        nvgCircle(vg, npcX - 6, npcY - 3, 3)
        nvgCircle(vg, npcX + 6, npcY - 3, 3)
        nvgFillColor(vg, traded and nvgRGBA(100, 120, 120, 150) or nvgRGBA(200, 255, 255, 255))
        nvgFill(vg)

        -- 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if traded then
            nvgFillColor(vg, nvgRGBA(120, 140, 140, 180))
            nvgText(vg, npcX, npcY + 24, "交易完成")
        else
            nvgFillColor(vg, nvgRGBA(100, 230, 240, 240))
            nvgText(vg, npcX, npcY + 24, "旅商")
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(180, 220, 220, 200))
            nvgText(vg, npcX, npcY + 42, "按 T 交易")
        end

        if tradeFlash > 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 90, math.floor(255 * tradeFlash)))
            nvgText(vg, npcX + 54, npcY - 26 - 18 * (1 - tradeFlash), "+金")
        end
    end

    -- 踩雷红闪叠层(渐消)
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
