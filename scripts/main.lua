-- ============================================================================
-- 扫雷搜打撤 — 2026 TapTap GameJam
-- 架构：NanoVG context 绘制场景/地图 + UI 系统做 HUD 叠层
-- ============================================================================

local UI = require("urhox-libs/UI")
local ExtractionRun = require("systems.ExtractionRun")
local RunInventory = require("systems.RunInventory")
local Combat = require("systems.Combat")
local Protocol = require("systems.Protocol")
local MiniMap = require("ui.MiniMap")
local MapOverlay = require("ui.MapOverlay")
local DungeonRoom = require("scenes.DungeonRoom")

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
local blockedWallHintTimer = 0

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
        mineHitsAreFatal = false,
        revealOnMove = true,
        moveRequiresRevealed = false,
    })
    minefield = run.minefield

    -- 标记出生格为已访问
    visitedCells = {}
    local spawn = minefield:GetSpawn()
    visitedCells[tostring(spawn.x) .. "," .. tostring(spawn.y)] = true
    RunInventory.Reset()
    Combat.Reset()
    Protocol.Reset()
    DungeonRoom.ResetPlayer()

    phase = PHASE.PLAYING

    -- 计算小地图布局
    MiniMap.ComputeLayout(minefield.width, minefield.height)

    ShowMessage("从中心出发，移动角色走进门，前往四角撤离！")
    UpdateHUD()

    -- 隐藏菜单
    local menu = uiRoot_:FindById("menuOverlay")
    if menu then menu:Hide() end
end

--- 移动当前房间里的角色；走到门口后才进入相邻扫雷格。
---@param dx number
---@param dy number
function MoveScenePlayer(dx, dy, dt)
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local result = DungeonRoom.MovePlayer(dx, dy, screenW, screenH, dpr, dt)
    if result.action == "enter" then
        MovePlayer(result.dx, result.dy)
    elseif result.action == "blocked_wall" and blockedWallHintTimer <= 0 then
        ShowMessage("走到门口才能离开房间。")
        blockedWallHintTimer = 0.8
    end
end

--- 通过门进入相邻扫雷格
---@param dx number
---@param dy number
function MovePlayer(dx, dy)
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local result = run:Move(dx, dy)

    if result.ok then
        DungeonRoom.PlacePlayerFromEntry(dx, dy, screenW, screenH, dpr)

        -- 标记为已访问
        local p = result.player
        visitedCells[tostring(p.x) .. "," .. tostring(p.y)] = true

        if result.status == "hit_mine" then
            local mineResult = Combat.TakeMineHit()
            if mineResult.dead then
                phase = PHASE.GAME_OVER
                ShowMessage("踩雷！受到 " .. mineResult.damage .. " 伤害，血量归零！")
                local goPanel = uiRoot_:FindById("gameOverPanel")
                if goPanel then goPanel:Show() end
                local goInfo = uiRoot_:FindById("gameOverInfo")
                if goInfo then goInfo:SetText("踩中地雷，HP 归零") end
            else
                ShowMessage("踩雷！-" .. mineResult.damage .. " HP (剩余 " .. Combat.hp .. ")，该雷房已触发。")
            end
        elseif result.status == "entered_triggered_mine" then
            ShowMessage("穿过已触发的雷房，没有再次受伤。")
        else
            -- 尝试在该格生成敌人
            Combat.TrySpawnEnemy(minefield, p.x, p.y)

            -- 检查是否有敌人并自动战斗
            local enemy = Combat.GetEnemy(p.x, p.y)
            if enemy then
                local fightResult = Combat.FightEnemy(p.x, p.y)
                if fightResult.fought then
                    if fightResult.dead then
                        phase = PHASE.GAME_OVER
                        ShowMessage("你被 " .. enemy.name .. "(战力" .. enemy.power .. ") 击杀！")
                        local goPanel = uiRoot_:FindById("gameOverPanel")
                        if goPanel then goPanel:Show() end
                        local goInfo = uiRoot_:FindById("gameOverInfo")
                        if goInfo then goInfo:SetText("被 " .. enemy.name .. " 击败\n敌方战力: " .. enemy.power .. " | 你的战力: " .. Combat.power) end
                    elseif fightResult.playerWin then
                        ShowMessage("击败 " .. enemy.name .. "(战力" .. enemy.power .. ")！你毫发无损。")
                    else
                        ShowMessage("击败 " .. enemy.name .. " 但受伤 -" .. fightResult.damage .. " HP (剩余 " .. Combat.hp .. ")")
                    end
                end
            elseif result.status == "at_exit" then
                ShowMessage("你到达了撤离点！按 E 撤离。")
            elseif CanSearchCurrentRoom() then
                ShowMessage("安全房间。按 F 或点击箱子搜索物资。")
            else
                -- 显示当前格信息
                local cell = minefield:GetCellView(p.x, p.y)
                if cell and cell.adjacent and cell.adjacent > 0 then
                    ShowMessage("附近有 " .. cell.adjacent .. " 个危险房间。")
                else
                    ShowMessage("安全区域。继续前进或查看地图。")
                end
            end
        end
    else
        if result.status == "hit_mine" then
            ShowMessage("踩雷，撤离失败。")
        elseif result.status == "out_of_bounds" then
            ShowMessage("无法移动，已到达地图边界。")
        elseif result.status == "blocked_flagged" then
            ShowMessage("该格已插旗，先取消旗标才能进入。")
        end
    end

    RefreshMapData()
    UpdateHUD()
end

function GetSearchState()
    return RunInventory.GetSearchState(minefield, run)
end

function CanSearchCurrentRoom()
    return RunInventory.CanSearch(minefield, run)
end

function SearchCurrentRoom()
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local result = RunInventory.SearchCurrentRoom(minefield, run)
    if not result.ok then
        if result.status == "searched" then
            ShowMessage("这个房间已经搜过了。")
        elseif result.status == "spawn" then
            ShowMessage("出生点没有可带走的物资。")
        elseif result.status == "exit" then
            ShowMessage("这里是撤离点，准备好就按 E 撤离。")
        else
            ShowMessage("当前房间无法搜索。")
        end
        return
    end

    local reward = result.reward
    -- 搜索后可能获得战斗力加成
    local p = run:GetPlayer()
    local powerUp = Combat.TryPowerUp(minefield, p.x, p.y)

    local msg = "搜索完成：金币 +" .. reward.gold
    if reward.parts > 0 then
        msg = msg .. "，零件 +" .. reward.parts
    end
    if powerUp > 0 then
        msg = msg .. "，战斗力 +" .. powerUp
    end
    ShowMessage(msg .. "。")

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
    DungeonRoom.ResetPlayer()

    if CanSearchCurrentRoom() then
        ShowMessage("传送成功。这个房间还有物资可搜。")
    else
        ShowMessage("传送成功！")
    end
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
        local totals = RunInventory.GetTotals()

        ShowMessage("撤离成功！带出金币 " .. totals.gold .. "，零件 " .. totals.parts .. "。")
        local winPanel = uiRoot_:FindById("winPanel")
        if winPanel then winPanel:Show() end
        local winInfo = uiRoot_:FindById("winInfo")
        if winInfo then
            winInfo:SetText("带出金币：" .. totals.gold ..
                "\n带出零件：" .. totals.parts ..
                "\n搜索房间：" .. totals.searchedRooms .. " | 回合：" .. result.turn)
        end
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

function CountVisitedCells()
    local count = 0
    for _ in pairs(visitedCells) do
        count = count + 1
    end
    return count
end

function UpdateHUD()
    if not run then return end
    local totals = RunInventory.GetTotals()
    local combat = Combat.GetStatus()
    Protocol.UpdateByExploredRooms(CountVisitedCells())

    local hpLabel = uiRoot_:FindById("hpLabel")
    if hpLabel then hpLabel:SetText("HP: " .. combat.hp .. "/" .. combat.maxHp) end

    local powerLabel = uiRoot_:FindById("powerLabel")
    if powerLabel then powerLabel:SetText("战力: " .. combat.power) end

    local goldLabel = uiRoot_:FindById("goldLabel")
    if goldLabel then goldLabel:SetText("金币: " .. totals.gold) end

    local partsLabel = uiRoot_:FindById("partsLabel")
    if partsLabel then partsLabel:SetText("零件: " .. totals.parts) end

    local turnLabel = uiRoot_:FindById("turnLabel")
    if turnLabel then
        local text = "回合: " .. run.turn
        if run:CanExtract() then text = text .. " [撤离点]" end
        turnLabel:SetText(text)
    end

    local protocolLabel = uiRoot_:FindById("protocolLabel")
    if protocolLabel then protocolLabel:SetText(Protocol.GetHUDText()) end
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
        local p = run:GetPlayer()
        DungeonRoom.Draw(nvgScene, w, h, {
            run = run,
            minefield = minefield,
            searchState = GetSearchState(),
            enemy = Combat.GetEnemyAny(p.x, p.y),
            combat = Combat.GetStatus(),
        })

        -- 绘制小地图
        if minefield then
            local visMap = minefield:GetVisibleMap()
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

-- ============================================================================
-- UI 构建
-- ============================================================================

function CreateUI()
    -- 右上角状态面板（竖排）
    local statusPanel = UI.Panel {
        id = "statusPanel",
        position = "absolute",
        top = 10, right = 10,
        padding = 10,
        gap = 4,
        backgroundColor = { 10, 12, 20, 190 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 60, 80, 120, 100 },
        pointerEvents = "none",
        children = {
            UI.Label {
                id = "hpLabel",
                text = "HP: 100/100",
                fontSize = 12,
                fontColor = { 255, 100, 100, 255 },
            },
            UI.Label {
                id = "powerLabel",
                text = "战力: 10",
                fontSize = 12,
                fontColor = { 255, 180, 60, 255 },
            },
            UI.Label {
                id = "goldLabel",
                text = "金币: 0",
                fontSize = 12,
                fontColor = { 255, 230, 80, 255 },
            },
            UI.Label {
                id = "partsLabel",
                text = "零件: 0",
                fontSize = 12,
                fontColor = { 160, 210, 255, 255 },
            },
            UI.Label {
                id = "turnLabel",
                text = "回合: 0",
                fontSize = 12,
                fontColor = { 180, 190, 210, 220 },
            },
            UI.Label {
                id = "protocolLabel",
                text = "协议: 5 / 稳定",
                fontSize = 12,
                fontColor = { 255, 210, 90, 240 },
            },
        }
    }

    -- 顶部消息栏
    local messageBar = UI.Panel {
        id = "messageBar",
        position = "absolute",
        top = 0, left = 180, right = 120,
        height = 32,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 10, 12, 20, 160 },
        pointerEvents = "none",
        children = {
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
                text = "F:搜索",
                fontSize = 11,
                fontColor = { 255, 220, 120, 220 },
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
                        id = "gameOverInfo",
                        text = "你踩中了地雷...",
                        fontSize = 14,
                        fontColor = { 200, 180, 180, 220 },
                        textAlign = "center",
                        numberOfLines = 2,
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
            statusPanel,
            messageBar,
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
    if blockedWallHintTimer > 0 then
        blockedWallHintTimer = blockedWallHintTimer - dt
    end
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
        if messageTimer <= 0 then
            message = ""
            local label = uiRoot_:FindById("messageLabel")
            if label then label:SetText("") end
        end
    end

    -- 连续移动：按住方向键时按帧平滑移动角色
    if phase == PHASE.PLAYING and run then
        local dx, dy = 0, 0
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then dy = -1
        elseif input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then dy = 1
        elseif input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then dx = -1
        elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then dx = 1
        end

        if dx ~= 0 or dy ~= 0 then
            MoveScenePlayer(dx, dy, dt)
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

    -- 功能键（移动已改为 Update 中连续检测）
    if key == KEY_W or key == KEY_UP or key == KEY_S or key == KEY_DOWN
       or key == KEY_A or key == KEY_LEFT or key == KEY_D or key == KEY_RIGHT then
        return
    elseif key == KEY_E then
        DoExtract()
    elseif key == KEY_F then
        SearchCurrentRoom()
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
        if DungeonRoom.HitTestSearchPoint(mx, my, screenW, screenH, dpr, GetSearchState()) then
            SearchCurrentRoom()
            return
        end

        local doorHit = DungeonRoom.HitTestDoor(mx, my, screenW, screenH, dpr, run, minefield)
        if doorHit then
            MovePlayer(doorHit.dx, doorHit.dy)
        end
    end
end
