-- ============================================================================
-- 扫雷搜打撤 — 2026 TapTap GameJam
-- 架构：NanoVG context 绘制场景/地图 + UI 系统做 HUD 叠层
-- ============================================================================

local UI = require("urhox-libs/UI")
local Minefield = require("systems.Minefield")
local ExtractionRun = require("systems.ExtractionRun")
local MiniMap = require("ui.MiniMap")
local MapOverlay = require("ui.MapOverlay")

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type userdata
local nvgScene = nil
local uiRoot_ = nil

local screenW = 0
local screenH = 0
local dpr = 1

-- 游戏核心
---@type table
local run = nil          -- ExtractionRun 实例
---@type table
local minefield = nil    -- Minefield 引用（run.minefield）

-- 玩家已访问的格子 { ["x,y"] = true }
local visitedCells = {}

-- 房间内角色位置。扫雷坐标由 run.player 记录，这里只控制当前房间里的表现位置。
local playerRoomPos = { x = 0.5, y = 0.5 }

local ROOM = {
    margin = 60,
    topOffset = 40,
    bottomSpace = 80,
    doorSize = 36,
    playerRadius = 16,
    moveStep = 34,
}

-- 游戏阶段
local PHASE = {
    MENU = "menu",
    PLAYING = "playing",
    MAP_OPEN = "map_open",
    GAME_OVER = "game_over",
    EXTRACTED = "extracted",
}
local phase = PHASE.MENU

-- 消息
local message = ""
local messageTimer = 0

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "扫雷搜打撤"

    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = graphics:GetDPR()

    -- 创建 NanoVG context
    nvgScene = nvgCreate(1)
    if not nvgScene then
        print("ERROR: Failed to create NanoVG context")
        return
    end
    nvgCreateFont(nvgScene, "sans", "Fonts/MiSans-Regular.ttf")

    -- 初始化 UI
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 创建 UI
    CreateUI()

    -- 配置放大地图回调
    MapOverlay.onClose = function()
        phase = PHASE.PLAYING
    end
    MapOverlay.onFlag = function(x, y)
        if run then
            run:ToggleFlag(x, y)
            RefreshMapData()
        end
    end
    MapOverlay.onTeleport = function(x, y)
        if run then
            TeleportTo(x, y)
        end
    end

    -- 订阅事件
    SubscribeToEvent(nvgScene, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== 扫雷搜打撤 已启动 ===")
end

function Stop()
    UI.Shutdown()
    if nvgScene then
        nvgDelete(nvgScene)
        nvgScene = nil
    end
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

function StartNewGame()
    run = ExtractionRun.New({
        width = 15,
        height = 15,
        mineDensity = 0.16,
        spawnSafeRadius = 1,
        pathWidth = 0,
        revealOnMove = true,
        moveRequiresRevealed = false,
    })
    minefield = run.minefield

    -- 标记出生格为已访问
    visitedCells = {}
    local spawn = minefield:GetSpawn()
    visitedCells[tostring(spawn.x) .. "," .. tostring(spawn.y)] = true
    ResetRoomPlayer()

    phase = PHASE.PLAYING

    -- 计算小地图布局
    MiniMap.ComputeLayout(minefield.width, minefield.height)

    ShowMessage("从中心出发，移动角色走进门，前往四角撤离！")
    UpdateHUD()

    -- 隐藏菜单
    local menu = uiRoot_:FindById("menuOverlay")
    if menu then menu:Hide() end
end

--- 取得当前房间绘制布局
---@param w number|nil
---@param h number|nil
---@return table
function GetRoomLayout(w, h)
    w = w or (screenW / dpr)
    h = h or (screenH / dpr)

    return {
        x = ROOM.margin,
        y = ROOM.margin + ROOM.topOffset,
        w = w - ROOM.margin * 2,
        h = h - ROOM.margin * 2 - ROOM.bottomSpace,
        doorSize = ROOM.doorSize,
    }
end

function ResetRoomPlayer()
    playerRoomPos.x = 0.5
    playerRoomPos.y = 0.5
end

--- 进入相邻房间后，把角色放在新房间的入口处。
---@param dx number
---@param dy number
function PlaceRoomPlayerFromEntry(dx, dy)
    local layout = GetRoomLayout()
    local minX = ROOM.playerRadius / layout.w + 0.03
    local maxX = 1 - minX
    local minY = ROOM.playerRadius / layout.h + 0.03
    local maxY = 1 - minY

    if dx > 0 then
        playerRoomPos.x = minX
        playerRoomPos.y = 0.5
    elseif dx < 0 then
        playerRoomPos.x = maxX
        playerRoomPos.y = 0.5
    elseif dy > 0 then
        playerRoomPos.x = 0.5
        playerRoomPos.y = minY
    elseif dy < 0 then
        playerRoomPos.x = 0.5
        playerRoomPos.y = maxY
    else
        ResetRoomPlayer()
    end
end

function IsAlignedWithDoor(dx, dy, layout)
    local doorHalfX = (layout.doorSize / 2 + ROOM.playerRadius) / layout.w
    local doorHalfY = (layout.doorSize / 2 + ROOM.playerRadius) / layout.h

    if dx ~= 0 then
        return math.abs(playerRoomPos.y - 0.5) <= doorHalfY
    end
    if dy ~= 0 then
        return math.abs(playerRoomPos.x - 0.5) <= doorHalfX
    end
    return false
end

--- 移动当前房间里的角色；走到门口后才进入相邻扫雷格。
---@param dx number
---@param dy number
function MoveScenePlayer(dx, dy)
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local layout = GetRoomLayout()
    local minX = ROOM.playerRadius / layout.w
    local maxX = 1 - minX
    local minY = ROOM.playerRadius / layout.h
    local maxY = 1 - minY

    local stepX = ROOM.moveStep / layout.w
    local stepY = ROOM.moveStep / layout.h
    local nextX = playerRoomPos.x + dx * stepX
    local nextY = playerRoomPos.y + dy * stepY

    local crossingDoor =
        (dx < 0 and nextX <= minX) or
        (dx > 0 and nextX >= maxX) or
        (dy < 0 and nextY <= minY) or
        (dy > 0 and nextY >= maxY)

    if crossingDoor then
        if IsAlignedWithDoor(dx, dy, layout) then
            MovePlayer(dx, dy)
            return
        end
        ShowMessage("走到门口才能离开房间。")
    end

    if nextX < minX then nextX = minX end
    if nextX > maxX then nextX = maxX end
    if nextY < minY then nextY = minY end
    if nextY > maxY then nextY = maxY end

    playerRoomPos.x = nextX
    playerRoomPos.y = nextY
end

--- 通过门进入相邻扫雷格
---@param dx number
---@param dy number
function MovePlayer(dx, dy)
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local result = run:Move(dx, dy)

    if result.ok then
        PlaceRoomPlayerFromEntry(dx, dy)

        -- 标记为已访问
        local p = result.player
        visitedCells[tostring(p.x) .. "," .. tostring(p.y)] = true

        if result.status == "at_exit" then
            ShowMessage("你到达了撤离点！按 E 撤离。")
        else
            -- 显示当前格信息
            local cell = minefield:GetCellView(p.x, p.y)
            if cell and cell.adjacent and cell.adjacent > 0 then
                ShowMessage("附近有 " .. cell.adjacent .. " 个危险房间。")
            else
                ShowMessage("安全区域。继续前进或查看地图。")
            end
        end
    else
        if result.status == "hit_mine" then
            phase = PHASE.GAME_OVER
            ShowMessage("你踩中了地雷！游戏结束。")
            local goPanel = uiRoot_:FindById("gameOverPanel")
            if goPanel then goPanel:Show() end
        elseif result.status == "out_of_bounds" then
            ShowMessage("无法移动，已到达地图边界。")
        elseif result.status == "blocked_flagged" then
            ShowMessage("该格已插旗，先取消旗标才能进入。")
        end
    end

    RefreshMapData()
    UpdateHUD()
end

--- 传送到已访问的安全格
function TeleportTo(x, y)
    if not run then return end
    local key = tostring(x) .. "," .. tostring(y)
    if not visitedCells[key] then
        ShowMessage("只能传送到已访问的安全房间。")
        return
    end

    -- 直接设置玩家位置
    run.player.x = x
    run.player.y = y
    ResetRoomPlayer()

    ShowMessage("传送成功！")
    MapOverlay.Hide()
    phase = PHASE.PLAYING
    RefreshMapData()
    UpdateHUD()
end

--- 撤离
function DoExtract()
    if not run then return end
    local result = run:Extract()
    if result.ok then
        phase = PHASE.EXTRACTED
        ShowMessage("撤离成功！回合数：" .. result.turn)
        local winPanel = uiRoot_:FindById("winPanel")
        if winPanel then winPanel:Show() end
    else
        ShowMessage("当前位置无法撤离。")
    end
end

--- 刷新地图数据给 MiniMap 和 MapOverlay
function RefreshMapData()
    if not run then return end
    MapOverlay.visibleMap = minefield:GetVisibleMap()
    MapOverlay.playerX = run.player.x
    MapOverlay.playerY = run.player.y
    MapOverlay.visitedCells = visitedCells
end

function ShowMessage(text)
    message = text
    messageTimer = 4.0
    local label = uiRoot_:FindById("messageLabel")
    if label then label:SetText(text) end
end

function UpdateHUD()
    if not run then return end
    local p = run:GetPlayer()
    local statusLabel = uiRoot_:FindById("statusLabel")
    if statusLabel then
        local canEx = run:CanExtract()
        local statusText = "位置: (" .. p.x .. "," .. p.y .. ") | 回合: " .. run.turn
        if canEx then
            statusText = statusText .. " | [撤离点]"
        end
        statusLabel:SetText(statusText)
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if not nvgScene then return end

    local w = screenW / dpr
    local h = screenH / dpr

    nvgBeginFrame(nvgScene, screenW, screenH, dpr)

    if phase == PHASE.PLAYING or phase == PHASE.GAME_OVER or phase == PHASE.EXTRACTED then
        -- 绘制房间场景背景
        DrawRoomScene(nvgScene, w, h)

        -- 绘制小地图
        if minefield then
            local visMap = minefield:GetVisibleMap()
            local p = run:GetPlayer()
            MiniMap.Draw(nvgScene, visMap, p.x, p.y, minefield.width, minefield.height)
        end
    elseif phase == PHASE.MAP_OPEN then
        -- 绘制放大地图
        RefreshMapData()
        MapOverlay.ComputeLayout(minefield.width, minefield.height, w, h)
        MapOverlay.Draw(nvgScene, w, h)
    end

    nvgEndFrame(nvgScene)
end

--- 绘制当前房间场景
function DrawRoomScene(vg, w, h)
    if not run then return end

    local p = run:GetPlayer()
    local cell = minefield:GetCellView(p.x, p.y)

    -- 房间背景色（根据数字变化氛围）
    local adj = (cell and cell.adjacent) or 0
    local bgR = 20 + adj * 8
    local bgG = 25 - adj * 2
    local bgB = 40 + adj * 5
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 255))
    nvgFill(vg)

    -- 房间框
    local layout = GetRoomLayout(w, h)
    local roomX = layout.x
    local roomY = layout.y
    local roomW = layout.w
    local roomH = layout.h

    nvgBeginPath(vg)
    nvgRoundedRect(vg, roomX, roomY, roomW, roomH, 8)
    nvgFillColor(vg, nvgRGBA(25, 30, 45, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 120, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 四个方向门
    local doorSize = layout.doorSize
    local doors = {
        { dir = "上", dx = 0, dy = -1, x = roomX + roomW / 2 - doorSize / 2, y = roomY - 4 },
        { dir = "下", dx = 0, dy = 1, x = roomX + roomW / 2 - doorSize / 2, y = roomY + roomH - doorSize + 4 },
        { dir = "左", dx = -1, dy = 0, x = roomX - 4, y = roomY + roomH / 2 - doorSize / 2 },
        { dir = "右", dx = 1, dy = 0, x = roomX + roomW - doorSize + 4, y = roomY + roomH / 2 - doorSize / 2 },
    }

    for _, door in ipairs(doors) do
        local nx = p.x + door.dx
        local ny = p.y + door.dy

        if minefield:IsInside(nx, ny) then
            local neighborCell = minefield:GetCellView(nx, ny)
            local doorColor

            if neighborCell and neighborCell.flagged then
                doorColor = nvgRGBA(200, 50, 50, 220) -- 插旗：红色危险门
            elseif neighborCell and neighborCell.revealed then
                doorColor = nvgRGBA(60, 160, 80, 220) -- 已探索：绿色
            else
                doorColor = nvgRGBA(100, 100, 130, 220) -- 未知
            end

            nvgBeginPath(vg)
            nvgRoundedRect(vg, door.x, door.y, doorSize, doorSize, 4)
            nvgFillColor(vg, doorColor)
            nvgFill(vg)

            -- 方向文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgText(vg, door.x + doorSize / 2, door.y + doorSize / 2, door.dir)
        end
    end

    -- 房间内玩家
    local playerCX = roomX + playerRoomPos.x * roomW
    local playerCY = roomY + playerRoomPos.y * roomH
    nvgBeginPath(vg)
    nvgCircle(vg, playerCX, playerCY, 16)
    nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 数字显示（当前格的邻近地雷数）
    if cell and cell.adjacent and cell.adjacent > 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 200))
        nvgText(vg, playerCX, playerCY + 40, "附近危险: " .. cell.adjacent)
    end

    -- 撤离点标记
    if cell and cell.exitId then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
        nvgText(vg, playerCX, roomY + 20, "[ 撤离点 - 按 E 撤离 ]")
    end

    -- 出生点标记
    if cell and cell.spawn then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 150))
        nvgText(vg, playerCX, roomY + roomH - 10, "出生点")
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function CreateUI()
    -- 顶部 HUD
    local hud = UI.Panel {
        id = "hud",
        position = "absolute",
        top = 0, left = 0, right = 0,
        height = 36,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 180,  -- 留出小地图空间
        paddingRight = 12,
        backgroundColor = { 10, 12, 20, 180 },
        pointerEvents = "none",
        children = {
            UI.Label {
                id = "statusLabel",
                text = "",
                fontSize = 12,
                fontColor = { 200, 210, 230, 255 },
            },
            UI.Label {
                id = "messageLabel",
                text = "",
                fontSize = 12,
                fontColor = { 255, 220, 100, 255 },
                flexShrink = 1,
            },
        }
    }

    -- 底部操作提示
    local bottomBar = UI.Panel {
        id = "bottomBar",
        position = "absolute",
        bottom = 0, left = 0, right = 0,
        height = 44,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 12,
        backgroundColor = { 10, 12, 20, 200 },
        children = {
            UI.Label {
                text = "WASD/方向键:移动角色",
                fontSize = 11,
                fontColor = { 160, 170, 190, 220 },
            },
            UI.Label {
                text = "M:地图",
                fontSize = 11,
                fontColor = { 160, 170, 190, 220 },
            },
            UI.Label {
                text = "E:撤离",
                fontSize = 11,
                fontColor = { 100, 255, 100, 220 },
            },
            UI.Label {
                text = "ESC:关闭地图",
                fontSize = 11,
                fontColor = { 160, 170, 190, 220 },
            },
        }
    }

    -- 开始菜单
    local menuOverlay = UI.Panel {
        id = "menuOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 5, 8, 15, 220 },
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 380,
                padding = 36,
                gap = 20,
                backgroundColor = { 20, 25, 40, 240 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 60, 80, 120, 120 },
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "扫雷搜打撤",
                        fontSize = 24,
                        fontColor = { 255, 240, 180, 255 },
                    },
                    UI.Label {
                        text = "你在一座由扫雷格子组成的地牢中醒来。\n数字告诉你附近有多少危险房间。\n到达四角撤离点即可逃出。",
                        fontSize = 13,
                        fontColor = { 180, 190, 210, 220 },
                        textAlign = "center",
                        numberOfLines = 4,
                    },
                    UI.Button {
                        text = "开始探索",
                        variant = "primary",
                        width = 140,
                        onClick = function()
                            StartNewGame()
                        end,
                    },
                }
            }
        }
    }

    -- 游戏结束面板
    local gameOverPanel = UI.Panel {
        id = "gameOverPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        visible = false,
        children = {
            UI.Panel {
                width = "80%",
                maxWidth = 320,
                padding = 28,
                gap = 16,
                backgroundColor = { 40, 15, 15, 240 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 200, 50, 50, 100 },
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "游戏结束",
                        fontSize = 22,
                        fontColor = { 255, 80, 80, 255 },
                    },
                    UI.Label {
                        text = "你踩中了地雷...",
                        fontSize = 14,
                        fontColor = { 200, 180, 180, 220 },
                    },
                    UI.Button {
                        text = "再来一次",
                        variant = "primary",
                        onClick = function()
                            local panel = uiRoot_:FindById("gameOverPanel")
                            if panel then panel:Hide() end
                            StartNewGame()
                        end,
                    },
                }
            }
        }
    }

    -- 撤离成功面板
    local winPanel = UI.Panel {
        id = "winPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        visible = false,
        children = {
            UI.Panel {
                width = "80%",
                maxWidth = 320,
                padding = 28,
                gap = 16,
                backgroundColor = { 10, 35, 20, 240 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 50, 200, 80, 100 },
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "撤离成功！",
                        fontSize = 22,
                        fontColor = { 80, 255, 120, 255 },
                    },
                    UI.Label {
                        id = "winInfo",
                        text = "",
                        fontSize = 14,
                        fontColor = { 200, 220, 200, 220 },
                        textAlign = "center",
                        numberOfLines = 3,
                    },
                    UI.Button {
                        text = "再来一次",
                        variant = "primary",
                        onClick = function()
                            local panel = uiRoot_:FindById("winPanel")
                            if panel then panel:Hide() end
                            StartNewGame()
                        end,
                    },
                }
            }
        }
    }

    uiRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            hud,
            bottomBar,
            menuOverlay,
            gameOverPanel,
            winPanel,
        }
    }

    UI.SetRoot(uiRoot_)
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = graphics:GetDPR()

    local dt = eventData["TimeStep"]:GetFloat()
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
        if messageTimer <= 0 then
            message = ""
            local label = uiRoot_:FindById("messageLabel")
            if label then label:SetText("") end
        end
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- 放大地图模式下
    if phase == PHASE.MAP_OPEN then
        if key == KEY_ESCAPE or key == KEY_M then
            MapOverlay.Hide()
            phase = PHASE.PLAYING
        end
        return
    end

    -- 菜单或结束阶段忽略
    if phase ~= PHASE.PLAYING then return end

    -- 移动房间里的角色；走进门后才切换扫雷格
    if key == KEY_W or key == KEY_UP then
        MoveScenePlayer(0, -1)
    elseif key == KEY_S or key == KEY_DOWN then
        MoveScenePlayer(0, 1)
    elseif key == KEY_A or key == KEY_LEFT then
        MoveScenePlayer(-1, 0)
    elseif key == KEY_D or key == KEY_RIGHT then
        MoveScenePlayer(1, 0)
    elseif key == KEY_E then
        DoExtract()
    elseif key == KEY_M then
        -- 打开放大地图
        phase = PHASE.MAP_OPEN
        MapOverlay.visible = true
        RefreshMapData()
        local w = screenW / dpr
        local h = screenH / dpr
        MapOverlay.ComputeLayout(minefield.width, minefield.height, w, h)
    end
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local mx = eventData["X"]:GetInt() / dpr
    local my = eventData["Y"]:GetInt() / dpr

    -- 放大地图交互
    if phase == PHASE.MAP_OPEN then
        MapOverlay.HandleClick(mx, my, button)
        return
    end

    if phase ~= PHASE.PLAYING then return end

    -- 点击小地图打开放大视图
    if MiniMap.HitTest(mx, my) then
        phase = PHASE.MAP_OPEN
        MapOverlay.visible = true
        RefreshMapData()
        local w = screenW / dpr
        local h = screenH / dpr
        MapOverlay.ComputeLayout(minefield.width, minefield.height, w, h)
        return
    end

    -- 点击房间门移动
    if button == MOUSEB_LEFT and run then
        local doorHit = HitTestDoor(mx, my)
        if doorHit then
            MovePlayer(doorHit.dx, doorHit.dy)
        end
    end
end

--- 检测点击是否命中门
---@param mx number
---@param my number
---@return table|nil {dx, dy}
function HitTestDoor(mx, my)
    local w = screenW / dpr
    local h = screenH / dpr

    local layout = GetRoomLayout(w, h)
    local roomX = layout.x
    local roomY = layout.y
    local roomW = layout.w
    local roomH = layout.h
    local doorSize = layout.doorSize

    local p = run:GetPlayer()

    local doors = {
        { dx = 0, dy = -1, x = roomX + roomW / 2 - doorSize / 2, y = roomY - 4 },
        { dx = 0, dy = 1, x = roomX + roomW / 2 - doorSize / 2, y = roomY + roomH - doorSize + 4 },
        { dx = -1, dy = 0, x = roomX - 4, y = roomY + roomH / 2 - doorSize / 2 },
        { dx = 1, dy = 0, x = roomX + roomW - doorSize + 4, y = roomY + roomH / 2 - doorSize / 2 },
    }

    for _, door in ipairs(doors) do
        local nx = p.x + door.dx
        local ny = p.y + door.dy
        if minefield:IsInside(nx, ny) then
            if mx >= door.x and mx <= door.x + doorSize and my >= door.y and my <= door.y + doorSize then
                return { dx = door.dx, dy = door.dy }
            end
        end
    end

    return nil
end
