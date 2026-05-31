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
    playerRadius = 24,
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
local imgRoomEvent = -1
local imgRoomMonster = -1
local imgRoomBase = -1
local imgPropChestClosed = -1
local imgPropChestOpen = -1
local imgPropExitDark = -1
local imgPropExitLight = -1
local imgPropMerchant = -1
local imgPropCore = -1
local imgPropTrap = -1
local imgPropParts = -1
local imgPropScanner = -1
local imgPropGold = -1
local imgPropMedkit = -1
local imgPropSupplyBox = -1
local imagesLoaded = false
local PLAYER_FRAME_DIR = "Textures/generated/characters/huanxiong/frames/"

-- 角色动画帧
local animFrames = {
    down = { -1, -1 },
    up = { -1, -1 },
    left = { -1, -1 },
    right = { -1, -1 },
}
local idleFrames = {
    down = -1,
    up = -1,
    left = -1,
    right = -1,
}
local animDir = "down"       -- 当前朝向: down/up/left/right
local animFrame = 1          -- 当前帧索引 1 or 2
local animTimer = 0          -- 帧切换计时器
local animMoving = false     -- 是否正在移动
local animMoveAge = 0        -- 距上次移动的时间(用于自动停止动画)
local ANIM_FRAME_TIME = 0.16 -- 每帧持续时间(秒)
local ANIM_STOP_DELAY = 0.12 -- 停止移动后多久停动画
local ANIM_IDLE_RESET_DELAY = 0.35

local function advanceWalkAnimation(dt)
    local elapsed = tonumber(dt) or 0
    if elapsed <= 0 then return end
    if elapsed > 0.08 then elapsed = 0.08 end
    animTimer = animTimer + elapsed
    while animTimer >= ANIM_FRAME_TIME do
        animTimer = animTimer - ANIM_FRAME_TIME
        animFrame = (animFrame % 2) + 1
    end
end
local animMovedThisFrame = false  -- 本帧是否调用了MovePlayer

--- 初始化图片资源(只调用一次)
function DungeonRoom.Init(vg)
    if imagesLoaded then return end
    imgPlayer = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "00_front_idle.png", 0)
    imgEnemy = nvgCreateImage(vg, "Textures/enemy_slime.png", 0)
    imgRoomSafe = nvgCreateImage(vg, "Textures/room_safe.png", 0)
    imgRoomDanger = nvgCreateImage(vg, "Textures/room_danger.png", 0)
    imgRoomTreasure = nvgCreateImage(vg, "Textures/room_treasure.png", 0)
    imgRoomExit = nvgCreateImage(vg, "Textures/room_exit.png", 0)
    imgRoomEvent = nvgCreateImage(vg, "Textures/room_event.png", 0)
    imgRoomMonster = nvgCreateImage(vg, "Textures/room_monster.png", 0)
    imgRoomBase = nvgCreateImage(vg, "Textures/generated/rooms/fangjian_jichu_1024.png", 0)
    imgPropChestClosed = nvgCreateImage(vg, "Textures/generated/props/03_baoxiang_guan.png", 0)
    imgPropChestOpen = nvgCreateImage(vg, "Textures/generated/props/00_baoxiang_kai.png", 0)
    imgPropExitDark = nvgCreateImage(vg, "Textures/generated/props/01_cheli_zhuangzhi_an.png", 0)
    imgPropExitLight = nvgCreateImage(vg, "Textures/generated/props/02_cheli_zhuangzhi_liang.png", 0)
    imgPropMerchant = nvgCreateImage(vg, "Textures/generated/props/04_shangren_tai.png", 0)
    imgPropCore = nvgCreateImage(vg, "Textures/generated/props/05_yichang_hexin.png", 0)
    imgPropTrap = nvgCreateImage(vg, "Textures/generated/props/06_dici_xianjing.png", 0)
    imgPropParts = nvgCreateImage(vg, "Textures/generated/props/07_lingjian_dui.png", 0)
    imgPropScanner = nvgCreateImage(vg, "Textures/generated/props/08_saomiaoyi.png", 0)
    imgPropGold = nvgCreateImage(vg, "Textures/generated/props/09_jinbi_dui.png", 0)
    imgPropMedkit = nvgCreateImage(vg, "Textures/generated/props/10_yiliaobao.png", 0)
    imgPropSupplyBox = nvgCreateImage(vg, "Textures/generated/props/11_wuzi_xiang.png", 0)
    idleFrames.down = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "00_front_idle.png", 0)
    idleFrames.up = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "01_back_idle.png", 0)
    idleFrames.left = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "02_left_idle.png", 0)
    idleFrames.right = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "03_right_idle.png", 0)
    -- 加载行走动画帧
    animFrames.down[1] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "04_front_walk_1.png", 0)
    animFrames.down[2] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "08_front_walk_2.png", 0)
    animFrames.up[1] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "05_back_walk_1.png", 0)
    animFrames.up[2] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "09_back_walk_2.png", 0)
    animFrames.left[1] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "06_left_walk_1.png", 0)
    animFrames.left[2] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "10_left_walk_2.png", 0)
    animFrames.right[1] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "07_right_walk_1.png", 0)
    animFrames.right[2] = nvgCreateImage(vg, PLAYER_FRAME_DIR .. "11_right_walk_2.png", 0)
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

local function drawSpriteBottom(vg, img, cx, bottomY, size, alpha)
    if img < 0 then return false end
    alpha = alpha or 1.0
    local half = size / 2
    local x = cx - half
    local y = bottomY - size
    local paint = nvgImagePattern(vg, x, y, size, size, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, size, size)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    return true
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

-- 房间内障碍物(归一化坐标, 圆形碰撞体)
-- 每个元素: { x=归一化X, y=归一化Y, r=归一化半径 }
local roomObstacles = {}

-- 踩雷红闪效果
local mineFlashTimer = 0
local MINE_FLASH_DURATION = 0.6
local chestOpenTimer = 0
local chestRewardBurst = { timer = 0, gold = 0, parts = 0 }
local tradePulseTimer = 0
local exitPulseTimer = 0
local roomTime = 0
local CHEST_OPEN_DURATION = 1.4
local CHEST_REWARD_DURATION = 2.0
local TRADE_PULSE_DURATION = 0.8
local EXIT_PULSE_DURATION = 0.8

function DungeonRoom.ResetPlayer()
    playerPos.x = 0.5
    playerPos.y = 0.5
end

function DungeonRoom.GetPlayerPosition()
    return { x = playerPos.x, y = playerPos.y }
end

--- 触发踩雷红闪效果
function DungeonRoom.TriggerMineFlash()
    mineFlashTimer = MINE_FLASH_DURATION
end

function DungeonRoom.TriggerChestOpen(reward)
    chestOpenTimer = CHEST_OPEN_DURATION
    chestRewardBurst.timer = CHEST_REWARD_DURATION
    chestRewardBurst.gold = reward and reward.gold or 0
    chestRewardBurst.parts = reward and reward.parts or 0
end

function DungeonRoom.TriggerTradePulse()
    tradePulseTimer = TRADE_PULSE_DURATION
end

function DungeonRoom.TriggerExitPulse()
    exitPulseTimer = EXIT_PULSE_DURATION
end

--- 设置当前房间的障碍物(每帧或切房间时调用)
--- obstacles 基于归一化房间坐标(0~1), 半径也归一化
---@param context table 与 Draw 相同的 context
---@param screenW number
---@param screenH number
---@param dpr number
function DungeonRoom.SetRoomObstacles(context, screenW, screenH, dpr)
    roomObstacles = {}
    if not context or not context.run or not context.minefield then return end

    local layout = DungeonRoom.GetLayout(screenW / dpr, screenH / dpr)
    -- 碰撞半径(像素 → 归一化, 取宽高平均)
    local function pixToNorm(px)
        return px / math.min(layout.w, layout.h)
    end

    local p = context.run:GetPlayer()
    local cell = context.minefield:GetCellView(p.x, p.y)
    local roomType = cell and cell.roomType or "normal"

    -- 宝箱/搜索点: 房间中心
    if context.searchState and (context.searchState.canSearch or context.searchState.searched) then
        roomObstacles[#roomObstacles + 1] = { x = 0.5, y = 0.5, r = pixToNorm(42) }
    end

    -- 撤离装置: 房间上方中间
    if cell and cell.exitId then
        local exitNormY = 54 / layout.h
        roomObstacles[#roomObstacles + 1] = { x = 0.5, y = exitNormY, r = pixToNorm(40) }
    end

    -- 怪物(活着时阻挡)
    local enemy = context.enemy
    if enemy and enemy.alive then
        local pos = enemy.monsterPosition or { x = 0.35, y = 0.45 }
        roomObstacles[#roomObstacles + 1] = { x = pos.x, y = pos.y, r = pixToNorm(32) }
    end

    -- 事件 NPC
    if roomType == "event" then
        roomObstacles[#roomObstacles + 1] = { x = 0.5, y = 0.35, r = pixToNorm(36) }
    end

    -- 已触发地雷(中央装饰, 较小碰撞)
    if roomType == "mine" then
        roomObstacles[#roomObstacles + 1] = { x = 0.5, y = 0.38, r = pixToNorm(30) }
    end
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
    if chestRewardBurst.timer > 0 then
        chestRewardBurst.timer = chestRewardBurst.timer - dt
        if chestRewardBurst.timer < 0 then chestRewardBurst.timer = 0 end
    end
    if tradePulseTimer > 0 then
        tradePulseTimer = tradePulseTimer - dt
        if tradePulseTimer < 0 then tradePulseTimer = 0 end
    end
    if exitPulseTimer > 0 then
        exitPulseTimer = exitPulseTimer - dt
        if exitPulseTimer < 0 then exitPulseTimer = 0 end
    end
    animMoveAge = animMoveAge + dt
    if animMovedThisFrame then
        animMoving = true
        animMoveAge = 0
    elseif animMoveAge > ANIM_STOP_DELAY then
        animMoving = false
    end

    if animMoving then
        advanceWalkAnimation(dt)
    elseif animMoveAge > ANIM_IDLE_RESET_DELAY then
        animTimer = 0
        animFrame = 1
    end

    animMovedThisFrame = false
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
    -- 更新动画方向
    if dx ~= 0 or dy ~= 0 then
        local resumedThisFrame = not animMoving
        animMoving = true
        animMoveAge = 0  -- 重置移动年龄,防止自动停止
        animMovedThisFrame = true
        if math.abs(dx) > math.abs(dy) then
            animDir = dx < 0 and "left" or "right"
        else
            animDir = dy < 0 and "up" or "down"
        end
        if resumedThisFrame then
            advanceWalkAnimation(dt)
        end
    end

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

    -- 障碍物碰撞解算(圆形推开)
    local playerR = CONFIG.playerRadius / math.min(layout.w, layout.h)
    for _, obs in ipairs(roomObstacles) do
        local odx = nextX - obs.x
        local ody = nextY - obs.y
        local dist = math.sqrt(odx * odx + ody * ody)
        local minDist = playerR + obs.r
        if dist < minDist and dist > 0.001 then
            -- 推开到刚好不重叠的位置
            local push = (minDist - dist)
            nextX = nextX + (odx / dist) * push
            nextY = nextY + (ody / dist) * push
        end
    end

    -- 推开后再次钳制到房间边界
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
        local glow = math.floor(200 * flash)
        nvgBeginPath(vg)
        nvgCircle(vg, rect.x + rect.w / 2, rect.y + rect.h / 2, 60 + 40 * (1 - flash))
        nvgFillColor(vg, nvgRGBA(255, 205, 70, glow))
        nvgFill(vg)
        -- 外层光晕
        nvgBeginPath(vg)
        nvgCircle(vg, rect.x + rect.w / 2, rect.y + rect.h / 2, 90 + 50 * (1 - flash))
        nvgFillColor(vg, nvgRGBA(255, 180, 40, math.floor(80 * flash)))
        nvgFill(vg)
    end

    local chestImg = (searchState.searched or flash > 0) and imgPropChestOpen or imgPropChestClosed
    if chestImg >= 0 then
        local cx = rect.x + rect.w / 2
        local bottomY = rect.y + rect.h + 14 - flash * 8
        drawSpriteBottom(vg, chestImg, cx, bottomY, 104, 1.0)
        if chestRewardBurst.timer > 0 then
            local progress = 1.0 - (chestRewardBurst.timer / CHEST_REWARD_DURATION)
            local easeOut = 1.0 - (1.0 - progress) * (1.0 - progress)
            local rise = 120 * easeOut
            local spread = 44 + 36 * easeOut
            local fadeStart = 0.7
            local alpha = progress < fadeStart and 255 or math.floor(255 * math.max(0, (1.0 - progress) / (1.0 - fadeStart)))
            local scale = 1.0 + 0.4 * math.sin(progress * math.pi)
            local iconSize = 56 * scale
            local iconY = rect.y + rect.h - 20 - rise

            -- 大光圈背景
            nvgBeginPath(vg)
            nvgCircle(vg, cx, iconY + 18, 50 + 36 * easeOut)
            nvgFillColor(vg, nvgRGBA(255, 220, 90, math.floor(120 * (1.0 - progress))))
            nvgFill(vg)

            drawSprite(vg, imgPropGold, cx - spread, iconY, iconSize, alpha / 255)
            if chestRewardBurst.parts > 0 then
                drawSprite(vg, imgPropParts, cx + spread, iconY + 4, iconSize, alpha / 255)
            end

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16 + 4 * scale)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 235, 130, alpha))
            nvgText(vg, cx - spread, iconY + 38, "+" .. chestRewardBurst.gold)
            if chestRewardBurst.parts > 0 then
                nvgFillColor(vg, nvgRGBA(170, 230, 255, alpha))
                nvgText(vg, cx + spread, iconY + 42, "+" .. chestRewardBurst.parts)
            end
        end
        if not searchState.searched then
            drawSpriteBottom(vg, imgPropGold, cx - 58, rect.y + rect.h + 22, 46, 0.95)
            drawSpriteBottom(vg, imgPropParts, cx + 58, rect.y + rect.h + 22, 46, 0.95)
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if searchState.searched then
            nvgFillColor(vg, nvgRGBA(170, 160, 145, 180))
            nvgText(vg, cx, rect.y + rect.h + 16, searchState.isChest and "物资箱已开启" or "已搜索")
        else
            nvgFillColor(vg, nvgRGBA(255, 230, 140, 230))
            nvgText(vg, cx, rect.y + rect.h + 16, searchState.isChest and "F 开启物资箱" or "F 搜索")
        end
        return
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
        nvgText(vg, rect.x + rect.w / 2, rect.y + rect.h + 6, searchState.isChest and "物资箱已开启" or "已搜索")
    else
        nvgFillColor(vg, nvgRGBA(255, 230, 140, 230))
        nvgText(vg, rect.x + rect.w / 2, rect.y + rect.h + 6, searchState.isChest and "F 开启物资箱" or "F 搜索")
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

    local exitImg = (activePulse > 0.05) and imgPropExitLight or imgPropExitDark
    if exitImg >= 0 then
        drawSpriteBottom(vg, exitImg, cx, y + 74, 116, 1.0)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 255, 170, 255))
        nvgText(vg, cx, y + 94, cell.randomExit and "隐藏撤离信标" or "撤离信标")
        if activePulse > 0 then
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBA(255, 235, 120, math.floor(255 * activePulse)))
            nvgText(vg, cx, y + 122 - 10 * (1 - activePulse), "信标已点亮")
        end
        return
    end

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
    nvgText(vg, cx, y, cell.randomExit and "隐藏撤离信标" or "撤离信标")

    if activePulse > 0 then
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 235, 120, math.floor(255 * activePulse)))
        nvgText(vg, cx, y + 42 - 10 * (1 - activePulse), "信标已点亮")
    end
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

    -- 背景铺满整个区域(cover 模式: 保持比例, 填满不留黑边)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 255))
    nvgFill(vg)

    local bgImg = (roomBgImg >= 0) and roomBgImg or imgRoomBase
    if bgImg >= 0 then
        -- 宽度填满, 高度完整显示(允许宽度适当拉伸, 上下门不被裁切)
        local paint = nvgImagePattern(vg, 0, 0, w, h, 0, bgImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, paint)
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
        local enemyPos = enemy.monsterPosition or { x = 0.35, y = 0.45 }
        local enemyX = layout.x + layout.w * enemyPos.x
        local enemyY = layout.y + layout.h * enemyPos.y
        local eScale = math.min(layout.w, layout.h) / 400
        eScale = math.max(0.6, math.min(eScale, 1.8))
        local er = CONFIG.enemyRadius * eScale

        if enemy.alive then
            local attackRadius = (enemy.attackRadius or 0.20) * math.min(layout.w, layout.h)
            if enemy.attackPhase == "warning" or enemy.attackPhase == "active" then
                local warningPulse = (math.sin(roomTime * 12) + 1) * 0.5
                local isActive = enemy.attackPhase == "active"
                nvgBeginPath(vg)
                nvgCircle(vg, enemyX, enemyY, attackRadius)
                if isActive then
                    nvgFillColor(vg, nvgRGBA(255, 45, 35, 70))
                    nvgStrokeColor(vg, nvgRGBA(255, 60, 45, 230))
                else
                    nvgFillColor(vg, nvgRGBA(255, 190, 45, 35 + math.floor(35 * warningPulse)))
                    nvgStrokeColor(vg, nvgRGBA(255, 210, 70, 160 + math.floor(70 * warningPulse)))
                end
                nvgFill(vg)
                nvgStrokeWidth(vg, isActive and 4 or 3)
                nvgStroke(vg)
            end

            local threatPulse = (math.sin(roomTime * 6) + 1) * 0.5
            local fleeAlpha = context.monsterFleeActive and 110 or 45
            nvgBeginPath(vg)
            nvgCircle(vg, enemyX, enemyY, er + 18 + threatPulse * 8)
            local hitFlash = enemy.hitFlashTimer or 0
            nvgFillColor(vg, hitFlash > 0 and nvgRGBA(255, 245, 180, 140) or nvgRGBA(210, 30, 40, fleeAlpha))
            nvgFill(vg)

            -- 敌人精灵图
            local enemySize = er * 2.8
            drawSprite(vg, imgEnemy, enemyX, enemyY, enemySize, hitFlash > 0 and 0.65 or 1.0)
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

            local hp = enemy.monsterHP or enemy.monsterMaxHP or enemy.power
            local maxHp = enemy.monsterMaxHP or hp
            local hpRatio = maxHp > 0 and math.max(0, math.min(1, hp / maxHp)) or 0
            local barW = 88
            local barH = 8
            local barX = enemyX - barW / 2
            local barY = enemyY - er - 18
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW, barH, 3)
            nvgFillColor(vg, nvgRGBA(20, 18, 24, 210))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, 3)
            nvgFillColor(vg, nvgRGBA(220, 60, 70, 235))
            nvgFill(vg)

            if context.combat and context.combat.power then
                local delta = context.combat.power - enemy.power
                local riskText = delta >= 0 and ("优势 +" .. delta) or ("危险 " .. delta)
                local riskColor = delta >= 0 and { 90, 230, 120 } or { 255, 90, 70 }
                nvgFontSize(vg, 12)
                nvgFillColor(vg, nvgRGBA(riskColor[1], riskColor[2], riskColor[3], 235))
                nvgText(vg, enemyX, enemyY + er + 40, riskText)
            end

            if context.monsterFleeActive then
                nvgFontSize(vg, 13)
                nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
                local remain = math.max(0, math.ceil(context.monsterFleeTimer or 0))
                nvgText(vg, enemyX, enemyY + er + 56, "逃跑窗口: " .. remain .. "s")
            else
                nvgFontSize(vg, 13)
                nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
                nvgText(vg, enemyX, enemyY + er + 56, "靠近 F 攻击 / 可离开")
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

            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(120, 220, 150, 210))
            nvgText(vg, enemyX, enemyY + er * 0.8 + 24, "房间已清理")
        end
    end

    local playerCX = layout.x + playerPos.x * layout.w
    local playerCY = layout.y + playerPos.y * layout.h
    -- 玩家精灵(带方向动画) - 根据屏幕大小自适应缩放
    local layoutScale = math.min(layout.w, layout.h) / 400
    layoutScale = math.max(0.6, math.min(layoutScale, 1.8))  -- 限制范围避免过大过小
    local playerSize = CONFIG.playerRadius * 2.5 * layoutScale
    local currentImg = imgPlayer  -- 默认静态帧
    if animFrame > 1 or animMovedThisFrame then
        -- 行走时播放动画帧
        local frames = animFrames[animDir]
        if frames and frames[animFrame] >= 0 then
            currentImg = frames[animFrame]
        end
    else
        -- 静止时使用当前朝向 idle 帧, 缺失时回退到默认正面帧.
        local idleImg = idleFrames[animDir]
        if idleImg and idleImg >= 0 then
            currentImg = idleImg
        end
    end
    drawSprite(vg, currentImg, playerCX, playerCY, playerSize, 1.0)
    -- 如果图片加载失败, fallback 圆形
    if currentImg < 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, playerCX, playerCY, CONFIG.playerRadius * layoutScale)
        nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    if enemy and enemy.playerInvincibleTimer and enemy.playerInvincibleTimer > 0 then
        local pulse = (math.sin(roomTime * 18) + 1) * 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, playerCX, playerCY, CONFIG.playerRadius * layoutScale + 8 + pulse * 4)
        nvgStrokeColor(vg, nvgRGBA(120, 210, 255, 170))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    if cell and cell.exitId then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
        nvgText(vg, playerCX, layout.y + 20, "[ 撤离信标 - 按 E 撤离 ]")
    end

    if cell and cell.spawn then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 150))
        nvgText(vg, playerCX, layout.y + layout.h - 10, "出生点")
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

        -- 文字提示(图片已由房间背景展示,不再重复绘制地雷图标)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(220, 90, 70, 230))
        nvgText(vg, cx, cy + 120, "已触发雷险")

        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 140, 130, 180))
        nvgText(vg, cx, cy + 146, "不再触发 - 可安全通过")
    end

    -- 宝箱房标题
    if roomType == "chest" then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 210, 80, 230))
        nvgText(vg, layout.x + layout.w / 2, layout.y + 12, "物资箱区")
    end

    -- 怪物房标题
    if roomType == "monster" and not context.enemy then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 230))
        nvgText(vg, layout.x + layout.w / 2, layout.y + 12, "异常体区域")
    end

    -- 事件房 NPC 绘制
    if roomType == "event" then
        local npcX = layout.x + layout.w * 0.5
        local npcY = layout.y + layout.h * 0.35
        local completed = context.eventTraded
        local eventType = context.eventType or "trader"
        local tradeFlash = tradePulseTimer / TRADE_PULSE_DURATION

        -- 事件类型视觉配置
        local evtVisual = {
            trader = { bodyColor = nvgRGBA(40, 140, 150, 230), hatColor = nvgRGBA(60, 180, 190, 240), accentColor = nvgRGBA(80, 220, 230, 255), label = "旅商", hint = "T:与旅商交易" },
            dice   = { bodyColor = nvgRGBA(180, 120, 40, 230), hatColor = nvgRGBA(220, 160, 50, 240), accentColor = nvgRGBA(255, 200, 80, 255), label = "赌徒", hint = "T:与赌徒交涉" },
            altar  = { bodyColor = nvgRGBA(120, 50, 150, 230), hatColor = nvgRGBA(160, 70, 200, 240), accentColor = nvgRGBA(200, 130, 255, 255), label = "祭坛", hint = "T:查看祭坛" },
            trap   = { bodyColor = nvgRGBA(150, 80, 40, 230), hatColor = nvgRGBA(190, 100, 50, 240), accentColor = nvgRGBA(240, 150, 70, 255), label = "机关", hint = "T:处理机关" },
        }
        local vis = evtVisual[eventType] or evtVisual.trader

        -- 脉冲光环
        if tradeFlash > 0 then
            nvgBeginPath(vg)
            nvgCircle(vg, npcX, npcY, 44 + 24 * (1 - tradeFlash))
            nvgFillColor(vg, nvgRGBA(70, 220, 230, math.floor(120 * tradeFlash)))
            nvgFill(vg)
        end

        -- NPC/物件 身体
        nvgBeginPath(vg)
        nvgCircle(vg, npcX, npcY, 18)
        nvgFillColor(vg, completed and nvgRGBA(50, 60, 60, 160) or vis.bodyColor)
        nvgFill(vg)
        nvgStrokeColor(vg, completed and nvgRGBA(80, 100, 100, 150) or vis.accentColor)
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 顶部标识（帽子/图标）
        nvgBeginPath(vg)
        if eventType == "dice" then
            -- 骰子方块
            nvgRoundedRect(vg, npcX - 10, npcY - 28, 20, 20, 3)
        elseif eventType == "altar" then
            -- 倒三角
            nvgMoveTo(vg, npcX - 12, npcY - 28)
            nvgLineTo(vg, npcX + 12, npcY - 28)
            nvgLineTo(vg, npcX, npcY - 12)
            nvgClosePath(vg)
        elseif eventType == "trap" then
            -- 齿轮状（六角）
            nvgMoveTo(vg, npcX, npcY - 30)
            nvgLineTo(vg, npcX + 10, npcY - 24)
            nvgLineTo(vg, npcX + 10, npcY - 14)
            nvgLineTo(vg, npcX, npcY - 8)
            nvgLineTo(vg, npcX - 10, npcY - 14)
            nvgLineTo(vg, npcX - 10, npcY - 24)
            nvgClosePath(vg)
        else
            -- 旅商三角帽
            nvgMoveTo(vg, npcX - 12, npcY - 14)
            nvgLineTo(vg, npcX, npcY - 28)
            nvgLineTo(vg, npcX + 12, npcY - 14)
            nvgClosePath(vg)
        end
        nvgFillColor(vg, completed and nvgRGBA(60, 70, 70, 150) or vis.hatColor)
        nvgFill(vg)

        -- 眼睛（仅 NPC 类型）
        if eventType == "trader" or eventType == "dice" then
            nvgBeginPath(vg)
            nvgCircle(vg, npcX - 6, npcY - 3, 3)
            nvgCircle(vg, npcX + 6, npcY - 3, 3)
            nvgFillColor(vg, completed and nvgRGBA(100, 120, 120, 150) or nvgRGBA(200, 255, 255, 255))
            nvgFill(vg)
        end

        -- 文字标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if completed then
            nvgFillColor(vg, nvgRGBA(120, 140, 140, 180))
            nvgText(vg, npcX, npcY + 24, "已完成")
        else
            nvgFillColor(vg, vis.accentColor)
            nvgText(vg, npcX, npcY + 24, vis.label)
            -- 交互提示放在 NPC 头顶上方，像素字体+黑色
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, npcX, npcY - 38, vis.hint)
        end

        -- 脉冲文字
        if tradeFlash > 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 220, 90, math.floor(255 * tradeFlash)))
            nvgText(vg, npcX + 54, npcY - 26 - 18 * (1 - tradeFlash), completed and "完成" or "按T")
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
