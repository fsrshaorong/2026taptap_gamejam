-- ============================================================================
-- 扫雷搜打撤 — 2026 TapTap GameJam
-- 架构:NanoVG context 绘制场景/地图 + UI 系统做 HUD 叠层
-- ============================================================================

local UI = require("urhox-libs/UI")
local ExtractionRun = require("systems.ExtractionRun")
local RunInventory = require("systems.RunInventory")
local Combat = require("systems.Combat")
local Protocol = require("systems.Protocol")
local Balance = require("systems.Balance")
local MetaProgress = require("systems.MetaProgress")
local MiniMap = require("ui.MiniMap")
local MapOverlay = require("ui.MapOverlay")
local HUD = require("ui.HUD")
local DungeonRoom = require("scenes.DungeonRoom")
local EventSystem = require("systems.EventSystem")
local Tutorial = require("systems.Tutorial")

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type userdata
local nvgScene = nil
local uiRoot_ = nil

local screenW = 0
local screenH = 0
local dpr = 1

local function GetSafeDPR()
    local value = graphics:GetDPR()
    if not value or value <= 0 then
        return 1
    end
    return value
end

local function GetLogicalScreenSize()
    return screenW / dpr, screenH / dpr
end

-- 游戏核心
---@type table
local run = nil          -- ExtractionRun 实例
---@type table
local minefield = nil    -- Minefield 引用(run.minefield)

-- 玩家已访问的格子 (v0.3: 由 minefield:Explore() 管理, 此表仅作兼容)
local visitedCells = {}

-- 游戏阶段
local PHASE = {
    MENU = "menu",
    PLAYING = "playing",
    MAP_OPEN = "map_open",
    EVENT_PANEL = "event_panel",
    LOOT_RESULT = "loot_result",
    CONFIRM_EXTRACT = "confirm_extract",
    GAME_OVER = "game_over",
    EXTRACTED = "extracted",
    SETTINGS = "settings",
}
local phase = PHASE.MENU
local extractionSettlementRecorded = false
local failureSettlementRecorded = false

-- 消息
local message = ""
local messageTimer = 0
local messageDuration = 0
local blockedWallHintTimer = 0

-- 事件房交易记录(key = "x,y")
local tradedRooms = {}
local eventPanel = {
    active = false,
    x = 0,
    y = 0,
    selected = 1,
    data = nil,
    message = "",
}
local lootPanel = {
    active = false,
    title = "",
    subtitle = "",
    reward = nil,
    powerUp = 0,
}

-- 威压天赋:怪物逃跑窗口
local monsterFleeTimer = 0       -- 逃跑倒计时(秒)
local monsterFleeActive = false  -- 是否处于逃跑窗口中
local MONSTER_FLEE_BASE = 3.0    -- 基础逃跑时间(秒)

-- 受击屏幕震动
local screenShake = {
    timer = 0,          -- 剩余震动时间
    duration = 0.3,     -- 总时长
    intensity = 8,      -- 最大偏移像素
    offsetX = 0,
    offsetY = 0,
}

-- 设置面板
local settingsPanel = {
    selected = 1,       -- 当前选中项 (1=继续, 2=重新开始, 3=返回主界面)
}

local function triggerScreenShake(intensity, duration)
    screenShake.timer = duration or 0.3
    screenShake.duration = screenShake.timer
    screenShake.intensity = intensity or 8
end

local function updateScreenShake(dt)
    if screenShake.timer > 0 then
        screenShake.timer = screenShake.timer - dt
        if screenShake.timer <= 0 then
            screenShake.timer = 0
            screenShake.offsetX = 0
            screenShake.offsetY = 0
        else
            local progress = screenShake.timer / screenShake.duration
            local strength = screenShake.intensity * progress
            screenShake.offsetX = (math.random() * 2 - 1) * strength
            screenShake.offsetY = (math.random() * 2 - 1) * strength
        end
    end
end

-- VS 战斗演出
local battleState = {
    active = false,       -- 是否在演出中
    phase = "none",       -- "vs" | "result"
    timer = 0,            -- 当前阶段计时
    enemy = nil,          -- 敌人信息 { name, power }
    result = nil,         -- 战斗结果(FightEnemy 返回值)
    cellX = 0,            -- 战斗发生的格子
    cellY = 0,
}
local BATTLE_VS_DURATION = 1.2    -- VS 展示时间
local BATTLE_RESULT_DURATION = 1.5 -- 结果展示时间
local imgBattlePlayer = -1
local imgBattleEnemy = -1

-- Menu state is intentionally shallow: top level opens terminals, deploy pages
-- are the only place that can confirm a normal run.
local menuMode = "main" -- "main" | "deploy" | "settings"
local deployPage = "overview"
local menuPage = "main"  -- "main" | "deployOverview" | "equip" | "talent" | "warehouse" | "requisition" | "loadout" | "recovery" | "gm"
local warehouseSelectedIndex = 1
local warehouseFilter = "all"
local currentRunConfig = nil

local JUDGE_DEMO_MAP = {
    width = 15,
    height = 15,
    spawn = { x = 8, y = 8 },
    mines = {
        { x = 4, y = 3 }, { x = 10, y = 3 }, { x = 12, y = 4 },
        { x = 3, y = 5 }, { x = 6, y = 5 }, { x = 11, y = 6 },
        { x = 5, y = 7 }, { x = 13, y = 7 }, { x = 2, y = 9 },
        { x = 6, y = 10 }, { x = 10, y = 10 }, { x = 14, y = 11 },
        { x = 4, y = 12 }, { x = 9, y = 13 }, { x = 12, y = 14 },
        { x = 6, y = 14 },
    },
    exits = {
        { id = "demo_visible_exit", x = 8, y = 4 },
        { id = "demo_hidden_exit", x = 12, y = 8, randomExit = true },
    },
    monsters = {
        { x = 10, y = 8 }, { x = 6, y = 6 }, { x = 7, y = 12 },
    },
    chests = {
        { x = 6, y = 8 }, { x = 10, y = 12 },
    },
    events = {
        { x = 8, y = 6 }, { x = 5, y = 11 },
    },
}

local function setVisible(id, visible)
    if not uiRoot_ then return end
    local element = uiRoot_:FindById(id)
    if not element then return end
    if visible then
        element:Show()
    else
        element:Hide()
    end
end

local MENU_BG_W = 1672
local MENU_BG_H = 941
local MENU_HOTSPOTS = {
    {
        x = 1100, y = 260, w = 430, h = 135,
        action = function()
            OpenDeployTerminal()
        end,
    },
    {
        x = 1095, y = 395, w = 430, h = 130,
        action = function()
            OpenTutorial()
        end,
    },
    {
        x = 1085, y = 530, w = 430, h = 135,
        action = function()
            OpenSettingsTerminal()
        end,
    },
    {
        x = 1075, y = 670, w = 430, h = 130,
        action = function()
            OpenSettingsTerminal()
        end,
    },
}

local function HandleMenuHotspotClick(mx, my)
    if phase ~= PHASE.MENU or menuPage ~= "main" then return false end

    local viewW = screenW / dpr
    local viewH = screenH / dpr
    local sx = viewW / MENU_BG_W
    local sy = viewH / MENU_BG_H

    for _, spot in ipairs(MENU_HOTSPOTS) do
        local x = spot.x * sx
        local y = spot.y * sy
        local w = spot.w * sx
        local h = spot.h * sy
        if mx >= x and mx <= x + w and my >= y and my <= y + h then
            spot.action()
            return true
        end
    end

    return false
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "扫雷搜打撤"

    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = GetSafeDPR()

    -- 创建 NanoVG context
    nvgScene = nvgCreate(1)
    if not nvgScene then
        print("ERROR: Failed to create NanoVG context")
        return
    end
    nvgCreateFont(nvgScene, "sans", "Fonts/FusionPixel.otf")
    imgBattlePlayer = nvgCreateImage(nvgScene, "Textures/generated/characters/huanxiong/frames/00_front_idle.png", 0)
    imgBattleEnemy = nvgCreateImage(nvgScene, "Textures/enemy_slime.png", 0)

    -- 初始化 UI
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/FusionPixel.otf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化局外进度
    MetaProgress.Init()

    -- 创建 UI
    CreateUI()

    -- 背景音乐(循环播放, bgmScene_ 保持全局引用防止 GC)
    bgmScene_ = Scene()
    local bgmNode = bgmScene_:CreateChild("BGM")
    local bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = SOUND_MUSIC
    local bgmSound = cache:GetResource("Sound", "audio/Hero Immortal.ogg")
    bgmSound.looped = true
    bgmSource:Play(bgmSound)
    bgmSource.gain = 0.5

    -- 初始化菜单显示
    RefreshMainMenu()

    -- 配置放大地图回调
    MapOverlay.onClose = function()
        phase = PHASE.PLAYING
        Tutorial.NotifyAction("close_map")
    end
    MapOverlay.onFlag = function(x, y)
        if run then
            run:ToggleFlag(x, y)
            RefreshMapData()
            Tutorial.NotifyAction("flag")
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
-- 菜单页面管理
-- ============================================================================

function SetMenuMode(mode)
    menuMode = mode or "main"
    if menuMode == "main" then
        deployPage = "overview"
    end
end

function SetDeployPage(page)
    deployPage = page or "overview"
    SetMenuMode("deploy")
end

--- 返回主菜单(从游戏结束/撤离成功面板)
function ReturnToMenu()
    phase = PHASE.MENU
    setVisible("gameOverPanel", false)
    setVisible("winPanel", false)
    local menu = uiRoot_:FindById("menuOverlay")
    if menu then menu:Show() end
    OpenMainMenu()
end

--- 切换菜单子页面
function ShowMenuPage(page)
    menuPage = page
    if page == "main" then
        SetMenuMode("main")
    elseif page == "gm" then
        SetMenuMode("settings")
    else
        SetDeployPage(page == "deployOverview" and "overview" or page)
    end
    setVisible("terminalNavOverlay", page == "main")
    setVisible("menuPage_main", page == "main")
    setVisible("menuPage_deployOverview", page == "deployOverview")
    setVisible("menuPage_equip", page == "equip")
    setVisible("menuPage_talent", page == "talent")
    setVisible("menuPage_warehouse", page == "warehouse")
    setVisible("menuPage_requisition", page == "requisition")
    setVisible("menuPage_loadout", page == "loadout")
    setVisible("menuPage_recovery", page == "recovery")
    setVisible("menuPage_gm", page == "gm")

    if page == "main" then
        RefreshMainMenu()
    elseif page == "deployOverview" then
        RefreshDeployOverview()
    elseif page == "equip" then
        RefreshEquipPage()
    elseif page == "talent" then
        RefreshTalentPage()
    elseif page == "warehouse" then
        RefreshWarehousePage()
    elseif page == "requisition" then
        RefreshRequisitionPage()
    elseif page == "loadout" then
        RefreshLoadoutPage()
    elseif page == "recovery" then
        RefreshRecoveryPage()
    elseif page == "gm" then
        RefreshGMPanel()
    end
end

local function RefreshCurrentMenuPage()
    ShowMenuPage(menuPage)
end

function OpenMainMenu()
    ShowMenuPage("main")
end

function BackToMainMenu()
    OpenMainMenu()
end

function OpenDeployTerminal()
    OpenDeployOverview()
end

function OpenDeployOverview()
    SetDeployPage("overview")
    ShowMenuPage("deployOverview")
end

function OpenDeployWarehouse()
    SetDeployPage("warehouse")
    ShowMenuPage("warehouse")
end

function OpenDeployShop()
    SetDeployPage("requisition")
    ShowMenuPage("requisition")
end

function OpenDeployLoadout()
    SetDeployPage("loadout")
    ShowMenuPage("loadout")
end

function OpenDeployRecovery()
    SetDeployPage("recovery")
    ShowMenuPage("recovery")
end

function OpenDeployTalents()
    SetDeployPage("talent")
    ShowMenuPage("talent")
end

function OpenTutorial()
    StartTutorialRun()
end

function OpenSettingsTerminal()
    ShowMenuPage("gm")
end

function BackFromCurrentMenu()
    if menuMode == "deploy" then
        if deployPage == "overview" then
            OpenMainMenu()
        else
            OpenDeployOverview()
        end
    elseif menuMode == "settings" then
        OpenMainMenu()
    end
end

function HandleMenuEscape()
    BackFromCurrentMenu()
end

--- 刷新主菜单数据
function RefreshMainMenu()
    -- The first-level menu is deliberately quiet. Deploy summaries live on
    -- the deploy overview so main does not leak second-level state.
end

function RefreshDeployOverview()
    local summary = MetaProgress.GetTerminalSummary()

    local goldLabel = uiRoot_ and uiRoot_:FindById("deployGoldLabel")
    if goldLabel then
        goldLabel:SetText("后勤账户: " .. summary.inventory.gold .. " 金币")
    end

    local loadoutLabel = uiRoot_ and uiRoot_:FindById("deployLoadoutLabel")
    if loadoutLabel then
        loadoutLabel:SetText("当前装备 " .. summary.loadout.equipmentText .. " | 本次带入 " .. summary.loadout.consumableText)
    end

    local warehouseLabel = uiRoot_ and uiRoot_:FindById("deployWarehouseLabel")
    if warehouseLabel then
        warehouseLabel:SetText("仓库库存 " .. summary.inventory.warehouseItems .. " 件 | 可售估值 " .. summary.inventory.warehouseValue)
    end

    local recentLabel = uiRoot_ and uiRoot_:FindById("deployRecentLabel")
    if recentLabel then
        recentLabel:SetText(summary.recentText)
    end

    local bonusLabel = uiRoot_ and uiRoot_:FindById("deployBonusLabel")
    if bonusLabel then
        local equipBonus = MetaProgress.GetEquipBonus()
        local talentEffects = MetaProgress.GetTalentEffects()
        local bonuses = {}
        if equipBonus.bonusHP > 0 then table.insert(bonuses, "HP+" .. equipBonus.bonusHP) end
        if equipBonus.bonusPower > 0 then table.insert(bonuses, "战力+" .. equipBonus.bonusPower) end
        if equipBonus.mineImmunity then table.insert(bonuses, "首雷免疫") end
        if equipBonus.showExitHint then table.insert(bonuses, "罗盘提示") end
        if equipBonus.searchBonus > 0 then table.insert(bonuses, "搜索+" .. equipBonus.searchBonus) end
        if talentEffects.mineDmgReduce > 0 then table.insert(bonuses, "雷伤-" .. talentEffects.mineDmgReduce) end
        if talentEffects.failureGoldBonus > 0 then table.insert(bonuses, "保险金+" .. talentEffects.failureGoldBonus) end
        if #bonuses == 0 then
            bonusLabel:SetText("当前主要加成: 无")
        else
            bonusLabel:SetText("当前主要加成: " .. table.concat(bonuses, " | "))
        end
    end
end

function RefreshWarehousePanel()
    RefreshWarehousePage()
end

function RefreshShopPanel()
    RefreshRequisitionPage()
end

function RefreshLoadoutPanel()
    RefreshLoadoutPage()
end

function RefreshTalentPanel()
    RefreshTalentPage()
end

function RefreshTerminalSummary()
    RefreshMainMenu()
    if menuPage == "deployOverview" then
        RefreshDeployOverview()
    elseif menuPage == "warehouse" then
        SetTerminalSummaryLabels("warehouse")
    elseif menuPage == "requisition" then
        SetTerminalSummaryLabels("requisition")
    elseif menuPage == "loadout" then
        SetTerminalSummaryLabels("loadout")
    end
end

function RefreshDeployTerminal()
    if menuMode == "deploy" then
        RefreshCurrentMenuPage()
    else
        RefreshMainMenu()
    end
end

local function DisplayIconText(item)
    local iconText = item and item.icon or ""
    if string.find(iconText, "/", 1, true) or string.find(iconText, "\\", 1, true) then
        iconText = ""
    end
    return iconText
end

function SetTerminalSummaryLabels(prefix)
    local summary = MetaProgress.GetTerminalSummary()
    local goldLabel = uiRoot_ and uiRoot_:FindById(prefix .. "GoldLabel")
    if goldLabel then goldLabel:SetText("金币 " .. summary.inventory.gold) end
    local loadoutLabel = uiRoot_ and uiRoot_:FindById(prefix .. "LoadoutLabel")
    if loadoutLabel then
        loadoutLabel:SetText("装备 " .. summary.loadout.equipmentText .. " | 带入 " .. summary.loadout.consumableText)
    end
end

--- 刷新装备商店页
function RefreshEquipPage()
    local goldLabel = uiRoot_ and uiRoot_:FindById("equipGoldLabel")
    if goldLabel then
        goldLabel:SetText("金币 " .. MetaProgress.GetGold())
    end
    SetTerminalSummaryLabels("equip")

    local listPanel = uiRoot_ and uiRoot_:FindById("equipItemList")
    if not listPanel then return end
    listPanel:RemoveAllChildren()

    for _, item in ipairs(MetaProgress.GetShopDisplayList({ type = "equipment" })) do
        local owned = item.owned
        local equipped = item.isEquipped

        local statusText = ""
        local btnText = ""
        local btnVariant = "default"

        if equipped then
            statusText = "[已装备]"
            btnText = "卸下"
        elseif owned then
            statusText = "已拥有"
            btnText = "装备"
            btnVariant = "primary"
        else
            statusText = item.price .. "g"
            btnText = "购买"
            btnVariant = "primary"
        end

        local itemId = item.id  -- 闭包捕获
        local row = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            width = "100%",
            padding = 8,
            backgroundColor = equipped and { 30, 60, 80, 120 } or { 25, 30, 45, 100 },
            borderRadius = 8,
            children = {
                UI.Panel {
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = DisplayIconText(item) .. " " .. item.name,
                            fontSize = 13,
                            fontColor = { 230, 235, 245, 255 },
                        },
                        UI.Label {
                            text = item.effectText or item.description,
                            fontSize = 11,
                            fontColor = { 150, 160, 180, 200 },
                        },
                    }
                },
                UI.Panel {
                    alignItems = "flex-end",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = statusText,
                            fontSize = 11,
                            fontColor = equipped and { 100, 220, 140, 255 } or { 200, 200, 210, 200 },
                        },
                        UI.Button {
                            text = btnText,
                            variant = btnVariant,
                            width = 60,
                            height = 28,
                            onClick = function()
                                OnEquipItemClick(itemId)
                            end,
                        },
                    }
                },
            }
        }
        listPanel:AddChild(row)
    end
end

--- 刷新天赋页
function RefreshTalentPage()
    local goldLabel = uiRoot_ and uiRoot_:FindById("talentGoldLabel")
    if goldLabel then
        goldLabel:SetText("金币 " .. MetaProgress.GetGold())
    end

    local listPanel = uiRoot_ and uiRoot_:FindById("talentList")
    if not listPanel then return end
    listPanel:RemoveAllChildren()

    for _, talent in ipairs(MetaProgress.TALENTS) do
        local unlocked = MetaProgress.HasTalent(talent.id)

        local statusText = unlocked and "[已解锁]" or (talent.price .. "g")
        local talentId = talent.id  -- 闭包捕获

        local row = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            width = "100%",
            padding = 8,
            backgroundColor = unlocked and { 40, 50, 30, 120 } or { 25, 30, 45, 100 },
            borderRadius = 8,
            children = {
                UI.Panel {
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = talent.name .. "(" .. talent.direction .. ")",
                            fontSize = 13,
                            fontColor = unlocked and { 200, 240, 150, 255 } or { 230, 235, 245, 255 },
                        },
                        UI.Label {
                            text = talent.desc,
                            fontSize = 11,
                            fontColor = { 150, 160, 180, 200 },
                        },
                    }
                },
                UI.Panel {
                    alignItems = "flex-end",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = statusText,
                            fontSize = 11,
                            fontColor = unlocked and { 100, 220, 140, 255 } or { 200, 200, 210, 200 },
                        },
                        unlocked and UI.Label { text = "", fontSize = 1 } or UI.Button {
                            text = "解锁",
                            variant = "primary",
                            width = 60,
                            height = 28,
                            onClick = function()
                                OnTalentClick(talentId)
                            end,
                        },
                    }
                },
            }
        }
        listPanel:AddChild(row)
    end
end

--- 装备物品点击处理
function RefreshWarehousePage()
    local goldLabel = uiRoot_ and uiRoot_:FindById("warehouseGoldLabel")
    if goldLabel then
        goldLabel:SetText("金币 " .. MetaProgress.GetGold())
    end
    SetTerminalSummaryLabels("warehouse")

    local summary = MetaProgress.GetWarehouseSummary()
    local summaryLabel = uiRoot_ and uiRoot_:FindById("warehouseSummaryLabel")
    if summaryLabel then
        summaryLabel:SetText("库存 " .. summary.totalItems .. " 件 | 可售估值 " .. summary.totalValue)
    end

    local filterLabel = uiRoot_ and uiRoot_:FindById("warehouseFilterLabel")
    if filterLabel then
        local names = { all = "全部", recovered = "异常回收物", consumable = "消耗品", equipment = "装备" }
        filterLabel:SetText("分类: " .. (names[warehouseFilter] or warehouseFilter))
    end

    local listPanel = uiRoot_ and uiRoot_:FindById("warehouseItemList")
    if not listPanel then return end
    listPanel:RemoveAllChildren()

    local items = MetaProgress.GetWarehouseDisplayList({ category = warehouseFilter })
    if #items == 0 then
        listPanel:AddChild(UI.Label {
            text = "当前分类暂无登记物品。",
            fontSize = 12,
            fontColor = { 160, 170, 190, 220 },
        })
        warehouseSelectedIndex = 1
        return
    end

    if warehouseSelectedIndex < 1 then warehouseSelectedIndex = 1 end
    if warehouseSelectedIndex > #items then warehouseSelectedIndex = #items end

    for index, item in ipairs(items) do
        local selected = index == warehouseSelectedIndex
        local itemId = item.id
        local iconText = item.icon or ""
        if string.find(iconText, "/", 1, true) or string.find(iconText, "\\", 1, true) then
            iconText = ""
        end
        local row = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            width = "100%",
            padding = 8,
            backgroundColor = selected and { 35, 60, 70, 150 } or { 25, 30, 45, 100 },
            borderRadius = 8,
            children = {
                UI.Panel {
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = (iconText ~= "" and (iconText .. " ") or "") .. item.name .. " x" .. item.count,
                            fontSize = 13,
                            fontColor = { 230, 235, 245, 255 },
                        },
                        UI.Label {
                            text = item.typeName .. " / " .. item.rarityName .. " | 价值 " .. item.value .. " | 价格 " .. item.price .. " | 带入 " .. item.loadoutCount,
                            fontSize = 11,
                            fontColor = { 150, 170, 190, 210 },
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    children = {
                        UI.Button {
                            text = "选中",
                            width = 52,
                            height = 28,
                            onClick = function()
                                warehouseSelectedIndex = index
                                RefreshWarehousePage()
                            end,
                        },
                        UI.Button {
                            text = item.canSell and "卖1" or "保护",
                            variant = item.canSell and "primary" or "default",
                            width = 48,
                            height = 28,
                            onClick = function()
                                warehouseSelectedIndex = index
                                OnSellWarehouseItem(itemId, 1)
                            end,
                        },
                        UI.Button {
                            text = item.canSell and "全卖" or "不可售",
                            width = 54,
                            height = 28,
                            onClick = function()
                                warehouseSelectedIndex = index
                                OnSellWarehouseItem(itemId, item.count)
                            end,
                        },
                    },
                },
            },
        }
        listPanel:AddChild(row)
    end
end

function OnEquipItemClick(itemId)
    local owned = MetaProgress.OwnsItem(itemId)
    if owned then
        -- 已拥有 -> 切换装备
        local ok, err = MetaProgress.ToggleEquip(itemId)
        if not ok and err then
            print("[Menu] ToggleEquip failed: " .. err)
        end
    else
        -- 未拥有 -> 购买
        local ok, err = MetaProgress.BuyItem(itemId)
        if not ok and err then
            print("[Menu] BuyItem failed: " .. err)
        end
    end
    RefreshCurrentMenuPage()
    RefreshTerminalSummary()
end

--- 天赋点击处理
function OnTalentClick(talentId)
    local ok, err = MetaProgress.UnlockTalent(talentId)
    if not ok and err then
        print("[Menu] UnlockTalent failed: " .. err)
    end
    RefreshTalentPage()
    RefreshTerminalSummary()
end

function OnSellWarehouseItem(itemId, count)
    local ok, result = MetaProgress.SellWarehouseItem(itemId, count)
    if ok then
        ShowMessage("出售异常回收物，获得结算币 +" .. result.gold .. "。")
    else
        ShowMessage("该物品暂不可出售。")
        print("[Warehouse] Sell failed: " .. tostring(result))
    end
    RefreshWarehousePage()
    RefreshTerminalSummary()
end

function OnSetWarehouseFilter(filter)
    warehouseFilter = filter
    warehouseSelectedIndex = 1
    RefreshWarehousePage()
end

function RefreshRequisitionPage()
    SetTerminalSummaryLabels("requisition")
    local listPanel = uiRoot_ and uiRoot_:FindById("requisitionItemList")
    if not listPanel then return end
    listPanel:RemoveAllChildren()

    for _, item in ipairs(MetaProgress.GetShopDisplayList({ type = "all" })) do
        local itemId = item.id
        local isEquipment = item.type == "equipment"
        local statusText = ""
        local buttonText = ""
        if isEquipment then
            statusText = item.isEquipped and "[已装备]" or (item.owned and "已拥有" or (item.price .. "g"))
            buttonText = item.owned and (item.isEquipped and "卸下" or "装备") or "购买"
        else
            statusText = "库存 " .. item.count .. " | 带入 " .. item.loadoutCount .. " | " .. item.price .. "g"
            buttonText = "买1"
        end

        listPanel:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            width = "100%",
            padding = 8,
            backgroundColor = { 25, 30, 45, 100 },
            borderRadius = 8,
            children = {
                UI.Panel {
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = DisplayIconText(item) .. " " .. item.name,
                            fontSize = 13,
                            fontColor = { 230, 235, 245, 255 },
                        },
                        UI.Label {
                            text = item.typeName .. " | " .. (item.effectText or item.description or ""),
                            fontSize = 11,
                            fontColor = { 150, 170, 190, 210 },
                        },
                    },
                },
                UI.Panel {
                    alignItems = "flex-end",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = statusText,
                            fontSize = 11,
                            fontColor = { 200, 200, 210, 210 },
                        },
                        UI.Button {
                            text = buttonText,
                            variant = "primary",
                            width = 64,
                            height = 28,
                            onClick = function()
                                if isEquipment then
                                    OnEquipItemClick(itemId)
                                else
                                    OnBuyConsumable(itemId, 1)
                                end
                            end,
                        },
                    },
                },
            },
        })
    end
end

function RefreshLoadoutPage()
    SetTerminalSummaryLabels("loadout")
    local listPanel = uiRoot_ and uiRoot_:FindById("loadoutItemList")
    if not listPanel then return end
    listPanel:RemoveAllChildren()

    for _, item in ipairs(MetaProgress.GetLoadoutDisplayList()) do
        local itemId = item.id
        local isConsumable = item.type == "consumable"
        local statusText = isConsumable
            and ("库存 " .. item.count .. " | 带入 " .. item.loadoutCount)
            or (item.isEquipped and "[已装备]" or (item.owned and "已拥有" or "未申领"))

        listPanel:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            width = "100%",
            padding = 8,
            backgroundColor = item.isEquipped and { 30, 60, 80, 120 } or { 25, 30, 45, 100 },
            borderRadius = 8,
            children = {
                UI.Panel {
                    flexShrink = 1,
                    gap = 2,
                    children = {
                        UI.Label {
                            text = DisplayIconText(item) .. " " .. item.name,
                            fontSize = 13,
                            fontColor = { 230, 235, 245, 255 },
                        },
                        UI.Label {
                            text = item.typeName .. " | " .. (item.effectText or item.description or ""),
                            fontSize = 11,
                            fontColor = { 150, 170, 190, 210 },
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    children = isConsumable and {
                        UI.Button {
                            text = "-",
                            width = 32,
                            height = 28,
                            onClick = function()
                                OnSetLoadoutConsumable(itemId, item.loadoutCount - 1)
                            end,
                        },
                        UI.Label {
                            text = statusText,
                            fontSize = 11,
                            fontColor = { 200, 200, 210, 210 },
                        },
                        UI.Button {
                            text = "+",
                            width = 32,
                            height = 28,
                            onClick = function()
                                OnSetLoadoutConsumable(itemId, item.loadoutCount + 1)
                            end,
                        },
                    } or {
                        UI.Label {
                            text = statusText,
                            fontSize = 11,
                            fontColor = { 200, 200, 210, 210 },
                        },
                        UI.Button {
                            text = item.isEquipped and "卸下" or "装备",
                            width = 60,
                            height = 28,
                            onClick = function()
                                OnEquipItemClick(itemId)
                            end,
                        },
                    },
                },
            },
        })
    end
end

function RefreshRecoveryPage()
    local summary = MetaProgress.GetTerminalSummary()
    local label = uiRoot_ and uiRoot_:FindById("recoverySummaryLabel")
    if label then
        label:SetText("累计带回 " .. summary.recovery.totalItems .. " 件 | 历史估值 " .. summary.recovery.totalValue)
    end
    local recent = uiRoot_ and uiRoot_:FindById("recoveryRecentLabel")
    if recent then
        recent:SetText(summary.recentText)
    end
end

function OnBuyConsumable(itemId, count)
    local ok, result = MetaProgress.BuyConsumable(itemId, count)
    if ok then
        ShowMessage("后勤申领成功: " .. itemId .. " x" .. result.count)
    else
        ShowMessage("申领失败: " .. tostring(result))
    end
    RefreshCurrentMenuPage()
    RefreshTerminalSummary()
end

function OnSetLoadoutConsumable(itemId, count)
    local ok, result = MetaProgress.SetLoadoutConsumable(itemId, count)
    if ok then
        if result.clamped then
            ShowMessage("库存不足, 已调整带入数量。")
        else
            ShowMessage("出勤配置已更新。")
        end
    else
        ShowMessage("配置失败: " .. tostring(result))
    end
    RefreshLoadoutPage()
    RefreshTerminalSummary()
end

-- ============================================================================
-- GM 调试功能
-- ============================================================================

function RefreshGMPanel()
    local goldLabel = uiRoot_ and uiRoot_:FindById("gmGoldLabel")
    if goldLabel then
        goldLabel:SetText("当前金币: " .. MetaProgress.GetGold())
    end

    local statusLabel = uiRoot_ and uiRoot_:FindById("gmStatusLabel")
    if statusLabel then
        local equipped = MetaProgress.GetEquippedItems()
        local talentCount = 0
        for _, t in ipairs(MetaProgress.TALENTS) do
            if MetaProgress.HasTalent(t.id) then talentCount = talentCount + 1 end
        end
        local itemCount = 0
        for _, item in ipairs(MetaProgress.ITEMS) do
            if MetaProgress.OwnsItem(item.id) then itemCount = itemCount + 1 end
        end
        statusLabel:SetText(
            "物品: " .. itemCount .. "/" .. #MetaProgress.ITEMS ..
            " | 装备中: " .. #equipped ..
            " | 天赋: " .. talentCount .. "/" .. #MetaProgress.TALENTS
        )
    end
end

function GMUnlockAllItems()
    for _, item in ipairs(MetaProgress.ITEMS) do
        if not MetaProgress.OwnsItem(item.id) then
            MetaProgress.GMGrantItem(item.id)
        end
    end
end

function GMUnlockAllTalents()
    for _, talent in ipairs(MetaProgress.TALENTS) do
        if not MetaProgress.HasTalent(talent.id) then
            MetaProgress.GMGrantTalent(talent.id)
        end
    end
end

function GMEquipAll()
    -- 先解锁全部, 再装备全部(忽略上限)
    GMUnlockAllItems()
    MetaProgress.GMEquipAll()
end

function GMUnequipAll()
    MetaProgress.GMUnequipAll()
end

function GMResetSave()
    MetaProgress.GMReset()
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

local function mergeConfig(base, override)
    if override then
        for key, value in pairs(override) do
            base[key] = value
        end
    end
    return base
end

local function defaultTalentEffects()
    return {
        mineDmgReduce = 0,
        monsterFleeBonus = 0,
        failureGoldBonus = 0,
        tradePrice = 15,
        mapHighlight = false,
    }
end

function GetActiveTalentEffects()
    if currentRunConfig and currentRunConfig.applyMetaProgress == false then
        return defaultTalentEffects()
    end
    return MetaProgress.GetTalentEffects()
end

function StartNormalRun()
    Tutorial.Reset()
    StartNewGame({
        mode = "normal",
        useLoadout = true,
        applyMetaProgress = true,
        allowWarehouseRewards = true,
        allowFailureRewards = true,
    })
end

function ConfirmDeploy()
    local ok, loadout = MetaProgress.ValidateLoadout()
    if not ok then
        ShowMessage("出勤配置校验失败: " .. tostring(loadout))
        return false
    end

    local adjusted = false
    for itemId, count in pairs((loadout and loadout.consumables) or {}) do
        local stock = MetaProgress.GetConsumableCount(itemId)
        if count > stock then
            MetaProgress.SetLoadoutConsumable(itemId, stock)
            adjusted = true
        end
    end
    if adjusted then
        ShowMessage("后勤库存不足，已夹紧本次带入数量。")
        RefreshCurrentMenuPage()
    end

    StartNormalRun()
    return true
end

function StartNewGame(override)
    local config = mergeConfig({
        mode = "normal",
        useLoadout = true,
        applyMetaProgress = true,
        allowWarehouseRewards = true,
        allowFailureRewards = true,
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
        mineHitsAreFatal = false,
        revealOnMove = true,
        moveRequiresRevealed = false,
    }, override)
    currentRunConfig = config

    local loadoutReceipt = { consumables = {} }
    if config.useLoadout ~= false and not config.skipLoadout then
        local ok, receipt = MetaProgress.ConsumeLoadoutForRun()
        if ok and receipt then
            loadoutReceipt = receipt
        end
    end

    run = ExtractionRun.New(config)
    minefield = run.minefield

    -- 标记出生格为已探索(v0.3: 通过 Minefield:Explore 管理)
    visitedCells = {}
    local spawn = minefield:GetSpawn()
    visitedCells[tostring(spawn.x) .. "," .. tostring(spawn.y)] = true
    minefield:Explore(spawn.x, spawn.y)
    RunInventory.Reset()
    RunInventory.SetConsumables(loadoutReceipt.consumables)
    Combat.Reset()
    Protocol.Reset()
    DungeonRoom.ResetPlayer()
    tradedRooms = {}
    EventSystem.Reset(minefield.seed or os.time())
    extractionSettlementRecorded = false
    failureSettlementRecorded = false

    -- 应用装备加成
    local equipBonus = {
        bonusHP = 0,
        bonusPower = 0,
        mineImmunity = false,
        showExitHint = false,
        searchBonus = 0,
    }
    if config.applyMetaProgress ~= false then
        equipBonus = MetaProgress.GetEquipBonus()
        if equipBonus.bonusHP > 0 then
            Combat.maxHp = Combat.maxHp + equipBonus.bonusHP
            Combat.hp = Combat.maxHp
        end
        if equipBonus.bonusPower > 0 then
            Combat.power = Combat.power + equipBonus.bonusPower
        end
        if equipBonus.mineImmunity then
            Combat.mineImmunity = true
        end
        if equipBonus.searchBonus > 0 then
            RunInventory.searchBonus = equipBonus.searchBonus
        end
        if equipBonus.mineDmgReduce and equipBonus.mineDmgReduce > 0 then
            Combat.mineDmgReduce = Combat.mineDmgReduce + equipBonus.mineDmgReduce
        end

        -- 应用天赋效果
        local talentEffects = MetaProgress.GetTalentEffects()
        if talentEffects.mineDmgReduce > 0 then
            Combat.mineDmgReduce = Combat.mineDmgReduce + talentEffects.mineDmgReduce
        end
    end

    -- 记录出击
    if config.applyMetaProgress ~= false then
        MetaProgress.RecordRun()
    end

    phase = PHASE.PLAYING

    -- 罗盘效果:显示撤离点象限提示
    local compassHint = ""
    if equipBonus.showExitHint then
        local exits = minefield:GetVisibleExits()
        if exits and #exits > 0 then
            local hints = {}
            local centerX = math.floor(minefield.width / 2)
            local centerY = math.floor(minefield.height / 2)
            for _, exit in ipairs(exits) do
                local dir = ""
                if exit.y < centerY then dir = "北" else dir = "南" end
                if exit.x < centerX then dir = dir .. "西" else dir = dir .. "东" end
                table.insert(hints, dir)
            end
            compassHint = " 罗盘提示:撤离点在" .. table.concat(hints, ",") .. "方向"
        end
    end

    -- 计算小地图布局
    MiniMap.ComputeLayout(minefield.width, minefield.height)

    local runConsumables = RunInventory.GetConsumables()
    local consumableHint = (runConsumables.emergency_bandage or 0) > 0 and (" 带入止血贴 x" .. runConsumables.emergency_bandage) or ""
    local tutorialHint = config.mode == "tutorial" and " 训练工单:不消耗后勤物资,不登记回收记录." or ""
    ShowMessage("左上角看扫雷数字避雷;WASD 走门, F 搜索, Q 止血贴, M 地图, E 撤离." .. compassHint .. consumableHint .. tutorialHint)
    UpdateHUD()

    -- 隐藏菜单
    local menu = uiRoot_:FindById("menuOverlay")
    if menu then menu:Hide() end
    setVisible("gameOverPanel", false)
    setVisible("winPanel", false)
end

function StartJudgeDemo()
    StartNewGame({
        mode = "judge",
        useLoadout = false,
        applyMetaProgress = false,
        allowWarehouseRewards = false,
        allowFailureRewards = false,
        skipLoadout = true,
        seed = 20260530,
        mineDensity = 0,
        mineCount = 0,
        randomExitCount = 0,
        spawnSafeRadius = 0,
        manualMap = JUDGE_DEMO_MAP,
    })
end

--- 启动新手教程
function StartTutorialRun()
    Tutorial.Reset()
    local config = Tutorial.GetMapConfig()
    config.mode = "tutorial"
    config.useLoadout = false
    config.applyMetaProgress = false
    config.allowWarehouseRewards = false
    config.allowFailureRewards = false
    config.skipLoadout = true
    StartNewGame(config)
    Tutorial.Start()
    ShowMessage("训练工单:不消耗后勤物资,不登记回收记录。")
end

function StartTutorial()
    StartTutorialRun()
end

function ShowFailurePanel(reason)
    phase = PHASE.GAME_OVER

    local totals = RunInventory.GetTotals()
    local stats = RunInventory.GetRunStats(run)
    local options = RunInventory.GetFailureSalvageOptions()
    local protocol = Protocol.GetStatus()
    local allowFailureRewards = not (currentRunConfig and currentRunConfig.allowFailureRewards == false)

    ShowMessage(reason)
    setVisible("gameOverPanel", true)
    setVisible("restartAfterFailureButton", false)

    local goInfo = uiRoot_:FindById("gameOverInfo")
    if goInfo then
        local reasonLine = uiRoot_:FindById("failureReasonLine")
        if reasonLine then reasonLine:SetText(reason) end

        local goldLine = uiRoot_:FindById("failureGoldLine")
        if goldLine then goldLine:SetText("金币 " .. totals.gold .. " (已安全保留)") end

        local partsLine = uiRoot_:FindById("failurePartsLine")
        if totals.carriedItemCount and totals.carriedItemCount > 0 then
            if partsLine then partsLine:SetText("遗失回收物 " .. totals.carriedItemCount .. " 件 (估值 " .. totals.carriedItemValue .. ")") end
        elseif totals.parts > 0 then
            if partsLine then partsLine:SetText("零件 " .. totals.parts .. " (将丢失)") end
        else
            if partsLine then partsLine:SetText("没有零件损失") end
        end

        local protocolLine = uiRoot_:FindById("failureProtocolLine")
        if protocolLine then protocolLine:SetText("协议等级:" .. protocol.level .. " / " .. protocol.description) end

        local statsLine = uiRoot_:FindById("failureStatsLine")
        if statsLine then
            statsLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. stats.searchedRooms ..
                " | 触雷:" .. stats.mineHits .. " | 事件:" .. stats.eventsCompleted)
        end
    end

    if not allowFailureRewards then
        setVisible("failureChoicePanel", false)
        setVisible("restartAfterFailureButton", true)
        local goldLine = uiRoot_:FindById("failureGoldLine")
        if goldLine then goldLine:SetText("训练工单不结算局外金币") end
        local partsLine = uiRoot_:FindById("failurePartsLine")
        if partsLine then partsLine:SetText("训练工单不登记回收记录") end
        local protocolLine = uiRoot_:FindById("failureProtocolLine")
        if protocolLine then protocolLine:SetText("不触发失败保底或保险金") end
        ShowMessage("训练工单失败:已返回结算,不消耗也不登记后勤资源。")
        return
    end

    -- 如果有零件可以抢救, 显示选择面板;否则直接结算并显示重开按钮
    if options.canSalvagePart then
        setVisible("failureChoicePanel", true)
        local salvageInfo = uiRoot_:FindById("failureSalvageInfo")
        if salvageInfo then
            salvageInfo:SetText("遗失回收物 " .. options.lostItemCount .. " 件; 可抢救 1 件折算 " .. options.salvageBonus .. " 金币")
        end
    else
        setVisible("failureChoicePanel", false)
        setVisible("restartAfterFailureButton", true)
        -- 无零件可抢救, 直接结算金币
        local salvage = RunInventory.ApplyFailureSalvage("accept")
        local talentBonus = GetActiveTalentEffects().failureGoldBonus
        local finalGold = (salvage.gold or 0) + talentBonus
        if not failureSettlementRecorded then
            if finalGold > 0 then
                MetaProgress.AddGold(finalGold)
            end
            if salvage.carriedItems and #salvage.carriedItems > 0 then
                MetaProgress.AddWarehouseItems(salvage.carriedItems, "recovered")
                MetaProgress.Save()
            end
            failureSettlementRecorded = true
        end
        local goInfo2 = uiRoot_:FindById("gameOverInfo")
        if goInfo2 then
            local reasonLine = uiRoot_:FindById("failureReasonLine")
            if reasonLine then reasonLine:SetText(reason) end

            local goldLine = uiRoot_:FindById("failureGoldLine")
            if goldLine then goldLine:SetText("保留金币:+" .. finalGold .. " (总计 " .. MetaProgress.GetGold() .. ")") end

            local partsLine = uiRoot_:FindById("failurePartsLine")
            if partsLine then partsLine:SetText("回收包已遗失: " .. options.lostItemCount .. " 件") end

            local protocolLine = uiRoot_:FindById("failureProtocolLine")
            if talentBonus > 0 then
                if protocolLine then protocolLine:SetText("天赋保险金 +" .. talentBonus) end
            else
                if protocolLine then protocolLine:SetText("") end
            end

            local statsLine = uiRoot_:FindById("failureStatsLine")
            if statsLine then
                statsLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. stats.searchedRooms ..
                    " | 触雷:" .. stats.mineHits .. " | 事件:" .. stats.eventsCompleted)
            end
        end
    end
end

function ApplyFailureSalvage(choice)
    if currentRunConfig and currentRunConfig.allowFailureRewards == false then
        setVisible("failureChoicePanel", false)
        setVisible("restartAfterFailureButton", true)
        ShowMessage("训练工单不触发失败保底或保险金。")
        return
    end

    local salvage = RunInventory.ApplyFailureSalvage(choice)
    local stats = RunInventory.GetRunStats(run)

    setVisible("failureChoicePanel", false)
    setVisible("restartAfterFailureButton", true)

    -- 天赋额外失败保底金币
    local talentBonus = GetActiveTalentEffects().failureGoldBonus
    local finalGold = salvage.gold + talentBonus

    -- 写入局外金币
    if not failureSettlementRecorded then
        if finalGold > 0 then
            MetaProgress.AddGold(finalGold)
        end
        if salvage.carriedItems and #salvage.carriedItems > 0 then
            MetaProgress.AddWarehouseItems(salvage.carriedItems, "recovered")
            MetaProgress.Save()
        end
        failureSettlementRecorded = true
    end

    local text = "保留金币:+" .. finalGold .. " (总计 " .. MetaProgress.GetGold() .. ")"
    if salvage.bonus > 0 then
        text = text .. " | 含抢救零件 +" .. salvage.bonus
    end
    if talentBonus > 0 then
        text = text .. " | 天赋保险金 +" .. talentBonus
    end

    local goInfo = uiRoot_:FindById("gameOverInfo")
    if goInfo then
        local reasonLine = uiRoot_:FindById("failureReasonLine")
        if reasonLine then reasonLine:SetText("撤离失败结算") end

        local goldLine = uiRoot_:FindById("failureGoldLine")
        if goldLine then goldLine:SetText("保留金币:+" .. finalGold .. " (总计 " .. MetaProgress.GetGold() .. ")") end

        local partsLine = uiRoot_:FindById("failurePartsLine")
        if partsLine then
            local options = RunInventory.GetFailureSalvageOptions()
            partsLine:SetText("回收包已遗失: " .. options.lostItemCount .. " 件")
        end

        local protocolLine = uiRoot_:FindById("failureProtocolLine")
        if protocolLine then
            local bonusText = ""
            if salvage.bonus > 0 then bonusText = "抢救零件 +" .. salvage.bonus end
            if talentBonus > 0 then
                if bonusText ~= "" then bonusText = bonusText .. " | " end
                bonusText = bonusText .. "天赋保险金 +" .. talentBonus
            end
            protocolLine:SetText(bonusText)
        end

        local statsLine = uiRoot_:FindById("failureStatsLine")
        if statsLine then
            statsLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. stats.searchedRooms ..
                " | 触雷:" .. stats.mineHits .. " | 事件:" .. stats.eventsCompleted)
        end
    end

    ShowMessage(text)
end

--- 启动 VS 战斗演出(替代直接结算)
---@param enemy table 敌人信息
---@param cx number 格子 x
---@param cy number 格子 y
function StartBattle(enemy, cx, cy)
    battleState.active = true
    battleState.phase = "vs"
    battleState.timer = BATTLE_VS_DURATION
    battleState.enemy = { name = enemy.name, power = enemy.power, playerPower = Combat.power }
    battleState.result = nil
    battleState.cellX = cx
    battleState.cellY = cy
end

--- VS 演出阶段结束, 执行实际战斗结算
function ResolveBattle()
    local fightResult = Combat.FightEnemy(battleState.cellX, battleState.cellY)
    battleState.result = fightResult
    battleState.phase = "result"
    battleState.timer = BATTLE_RESULT_DURATION
end

--- 战斗演出完全结束, 处理后续
function FinishBattle()
    local result = battleState.result
    local enemy = battleState.enemy
    battleState.active = false
    battleState.phase = "none"

    if not result or not result.fought then return end
    Combat.GrantMonsterKillPower(result)
    RunInventory.RecordCombat(result)
    if result.pressureDelta and result.pressureDelta > 0 then
        Protocol.AddPressure(result.pressureDelta)
    end

    local playerPower = result.playerPower or enemy.playerPower or Combat.power
    local enemyPower = result.enemyPower or enemy.power

    local reward = result.reward or { gold = 0, parts = 0 }
    local rewardText = ""
    if (reward.gold or 0) > 0 then
        rewardText = rewardText .. " 获得结算币 +" .. reward.gold
    end
    if (reward.parts or 0) > 0 then
        rewardText = rewardText .. " 零件 +" .. reward.parts
    end

    if result.dead then
        ShowFailurePanel("你被 " .. enemy.name .. "(战力" .. enemy.power .. ") 击败!")
    elseif result.playerWin then
        ShowMessage("异常体已清理." .. rewardText)
    else
        ShowMessage("强行清理成功, 生命 -" .. result.damage .. "." .. rewardText)
    end
    if not result.dead then
        -- v0.3: 标记房间已清理
        if minefield and battleState.cellX then
            minefield:ClearRoom(battleState.cellX, battleState.cellY)
        end
        if result.playerWin then
            ShowMessage("异常体已清理. 区域风险下降. (我方" .. playerPower .. " vs 威胁" .. enemyPower .. ")" .. rewardText)
        else
            ShowMessage("强行清理成功, 生命 -" .. result.damage .. " HP (剩余 " .. result.hp .. ")." .. rewardText)
        end
    end
    UpdateHUD()
end

local function buildRewardText(reward)
    reward = reward or { gold = 0, parts = 0 }
    local rewardText = ""
    if (reward.gold or 0) > 0 then
        rewardText = rewardText .. " 获得结算币 +" .. reward.gold
    end
    if (reward.parts or 0) > 0 then
        rewardText = rewardText .. " 零件 +" .. reward.parts
    end
    return rewardText
end

local function CompleteActiveMonsterClear(result, cx, cy)
    if not result or not result.fought then return end
    Combat.GrantMonsterKillPower(result)
    RunInventory.RecordCombat(result)
    if result.pressureDelta and result.pressureDelta > 0 then
        Protocol.AddPressure(result.pressureDelta)
    end
    if minefield then
        minefield:ClearRoom(cx, cy)
    end
    local enemyName = result.enemy and result.enemy.name or "异常体"
    ShowMessage(enemyName .. " 已清理. 区域风险下降." .. buildRewardText(result.reward))
    UpdateHUD()
end

--- 主动清理当前异常体
function ForceFightCurrentEnemy()
    if not run then return end
    local p = run:GetPlayer()
    local enemy = Combat.GetEnemy(p.x, p.y)
    if not enemy then
        monsterFleeActive = false
        monsterFleeTimer = 0
        return
    end
    monsterFleeActive = false
    monsterFleeTimer = 0
    StartBattle(enemy, p.x, p.y)
end

function AttackCurrentEnemy()
    if not run then return end
    local p = run:GetPlayer()
    local enemy = Combat.GetEnemy(p.x, p.y)
    if not enemy then
        SearchCurrentRoom()
        return
    end

    local attack = Combat.PlayerAttackEnemy(p.x, p.y, DungeonRoom.GetPlayerPosition())
    if not attack.ok then
        if attack.status == "too_far" then
            ShowMessage("距离过远. 靠近异常体后按 F 攻击.")
        elseif attack.status == "cooldown" then
            ShowMessage("攻击冷却中.")
        end
        return
    end

    if attack.killed then
        CompleteActiveMonsterClear(attack.result, p.x, p.y)
    else
        local hpText = (attack.hp or 0) .. "/" .. (attack.maxHp or 0)
        ShowMessage("命中异常体 -" .. attack.damage .. " HP (" .. hpText .. ").")
    end
end

function UpdateCurrentMonsterCombat(dt)
    if phase ~= PHASE.PLAYING or not run or not minefield or battleState.active then return end
    local p = run:GetPlayer()
    local enemy = Combat.GetEnemy(p.x, p.y)
    if not enemy then return end

    local result = Combat.UpdateEnemy(p.x, p.y, dt, DungeonRoom.GetPlayerPosition())
    if result.playerHit then
        triggerScreenShake(10, 0.35)
        if result.dead then
            ShowFailurePanel("被异常体攻击击倒! 受到 " .. result.damage .. " 伤害.")
        else
            ShowMessage("被异常体攻击命中! -" .. result.damage .. " HP (剩余 " .. result.hp .. ").")
        end
        UpdateHUD()
    end
end

--- 获取中央游戏区的 "虚拟屏幕" 物理尺寸(供 DungeonRoom 使用)
---@return number centerPhysW
---@return number centerPhysH
function GetCenterAreaPhysSize()
    local w = screenW / dpr
    local h = screenH / dpr
    local layout = HUD.ComputeLayout(w, h)
    return math.floor(layout.center.w * dpr), math.floor(layout.center.h * dpr)
end

--- 移动当前房间里的角色;走到门口后才进入相邻扫雷格.
---@param dx number
---@param dy number
function MoveScenePlayer(dx, dy, dt)
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local cpW, cpH = GetCenterAreaPhysSize()
    local p = run:GetPlayer()
    DungeonRoom.SetRoomObstacles({
        run = run,
        minefield = minefield,
        searchState = GetSearchState(),
        enemy = Combat.GetEnemyAny(p.x, p.y),
    }, cpW, cpH, dpr)
    local result = DungeonRoom.MovePlayer(dx, dy, cpW, cpH, dpr, dt)
    if result.action == "enter" then
        MovePlayer(result.dx, result.dy)
    elseif result.action == "blocked_wall" and blockedWallHintTimer <= 0 then
        ShowMessage("走到门口才能离开房间.")
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
        RunInventory.RecordMove()
        local cpW, cpH = GetCenterAreaPhysSize()
        DungeonRoom.PlacePlayerFromEntry(dx, dy, cpW, cpH, dpr)

        -- 教程:通知移动完成
        Tutorial.NotifyAction("move")

        if monsterFleeActive then
            monsterFleeActive = false
            monsterFleeTimer = 0
        end

        -- 标记为已探索(v0.3: 通过 Minefield:Explore + Protocol 压力)
        local p = result.player
        visitedCells[tostring(p.x) .. "," .. tostring(p.y)] = true
        local firstExplore = minefield:Explore(p.x, p.y)
        if firstExplore then
            local protoResult = Protocol.AddPressure(Balance.pressure.explore)
            if protoResult.changed then
                ShowMessage("协议降至 " .. protoResult.level .. " - " .. protoResult.description)
            end
            -- Protocol 1 惩罚: 探索未知房扣血
            if protoResult.penalty then
                local penaltyDamage = Combat.ApplyDamage(1)
                if penaltyDamage.dead then
                    ShowFailurePanel("临界协议! 探索未知房损失生命, 血量归零!")
                    RefreshMapData()
                    UpdateHUD()
                    return
                else
                    ShowMessage("临界协议! 探索未知房损失生命! (HP-1, 剩余 " .. penaltyDamage.hp .. ")")
                end
            end
        end

        -- 邻域感知天赋:高亮 8 邻域
        local talentEffects = MetaProgress.GetTalentEffects()
        if talentEffects.mapHighlight then
            local neighbors = {}
            for ndx = -1, 1 do
                for ndy = -1, 1 do
                    if not (ndx == 0 and ndy == 0) then
                        local nx, ny = p.x + ndx, p.y + ndy
                        if minefield:IsInside(nx, ny) then
                            table.insert(neighbors, { x = nx, y = ny })
                        end
                    end
                end
            end
            MiniMap.SetHighlight(neighbors)
        end

        if result.status == "hit_mine" then
            local mineResult = Combat.TakeMineHit()
            if result.mineTriggered then
                RunInventory.RecordMineHit(mineResult.immuneUsed)
                local minePressure = Protocol.AddPressure(Balance.pressure.mine)
                if minePressure.changed then
                    ShowMessage("协议降至 " .. minePressure.level .. " - " .. minePressure.description)
                end
            end
            DungeonRoom.TriggerMineFlash()
            if not mineResult.immuneUsed then
                triggerScreenShake(12, 0.4)
            end
            if mineResult.dead then
                ShowFailurePanel("踩雷!受到 " .. mineResult.damage .. " 伤害, 血量归零!")
            elseif mineResult.immuneUsed then
                ShowMessage("急救包发动!踩雷免疫一次伤害!")
            else
                ShowMessage("踩雷!-" .. mineResult.damage .. " HP (剩余 " .. Combat.hp .. "), 该雷房已触发.")
            end
        elseif result.status == "entered_triggered_mine" then
            ShowMessage("穿过已触发的雷房, 不再触发.")
        else
            -- 0格自动展开:如果 Reveal 触发了 BFS 展开, 高亮展开区域
            local didExpand = false
            if result.reveal and result.reveal.status == "expanded" and result.reveal.cells then
                local expandedCells = {}
                for _, c in ipairs(result.reveal.cells) do
                    if not (c.x == p.x and c.y == p.y) then
                        table.insert(expandedCells, { x = c.x, y = c.y })
                    end
                end
                if #expandedCells > 0 then
                    MiniMap.SetHighlight(expandedCells)
                    didExpand = true
                end
            end

            -- 尝试在该格生成敌人
            Combat.TrySpawnEnemy(minefield, p.x, p.y)

            -- 检查是否有敌人
            local enemy = Combat.GetEnemy(p.x, p.y)
            if enemy then
                monsterFleeActive = false
                monsterFleeTimer = 0
                ShowMessage("检测到异常体活动. 可绕行, 可战斗. 靠近后按 F 攻击, 躲开预警范围. 威胁:" ..
                    enemy.power .. " 战力:" .. Combat.power)
            elseif result.status == "at_exit" then
                local cell = minefield:GetCellView(p.x, p.y)
                DungeonRoom.TriggerExitPulse()
                MiniMap.SetHighlight({ { x = p.x, y = p.y } })
                if cell and cell.randomExit then
                    ShowMessage("发现隐藏撤离点! 信标已点亮, 按 E 撤离.")
                else
                    ShowMessage("你到达了撤离点! 按 E 撤离.")
                end
            else
                -- 根据房型显示不同提示
                local cell = minefield:GetCellView(p.x, p.y)
                local searchState = GetSearchState()
                if cell and cell.roomType == "event" then
                    ShowMessage(EventSystem.GetEnterMessage(p.x, p.y))
                elseif searchState.searched and searchState.isChest then
                    ShowMessage("物资箱已开启.")
                elseif searchState.searched then
                    ShowMessage("该区域已搜索.")
                elseif searchState.isChest then
                    ShowMessage("发现未登记物资箱。按 F 开启。")
                elseif searchState.canSearch then
                    if didExpand then
                        ShowMessage("安全区域展开!发现可回收物。按 F 搜索。")
                    else
                        ShowMessage("发现可回收物。按 F 搜索。")
                    end
                elseif didExpand then
                    ShowMessage("安全区域展开!自动揭示了周围格子.")
                elseif cell and cell.adjacent and cell.adjacent > 0 then
                    ShowMessage("附近有 " .. cell.adjacent .. " 个危险房间.")
                else
                    ShowMessage("安全区域.继续前进或查看地图.")
                end
            end
        end
    else
        if result.status == "hit_mine" then
            ShowMessage("踩雷, 撤离失败.")
        elseif result.status == "out_of_bounds" then
            ShowMessage("无法移动, 已到达地图边界.")
        elseif result.status == "blocked_flagged" then
            ShowMessage("该格已插旗, 先取消旗标才能进入.")
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

function OpenLootResultPanel(reward, powerUp)
    reward = reward or {}
    lootPanel.active = true
    lootPanel.reward = reward
    lootPanel.powerUp = powerUp or 0
    lootPanel.title = reward.isChest and "未登记物资箱" or "搜索结果"
    lootPanel.subtitle = reward.isChest and "高价值物资已放入临时回收包" or "可回收物已放入临时回收包"
    phase = PHASE.LOOT_RESULT
end

function CloseLootResultPanel()
    local reward = lootPanel.reward or {}
    local itemCount = reward.parts or 0
    local value = reward.itemValue or 0
    lootPanel.active = false
    lootPanel.reward = nil
    phase = PHASE.PLAYING
    if itemCount > 0 then
        ShowMessage("回收包 +" .. itemCount .. " 件, 估值 +" .. value .. ".")
    else
        ShowMessage("结算币已记录, 未发现可携带回收物.")
    end
    UpdateHUD()
end

function SearchCurrentRoom()
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local result = RunInventory.SearchCurrentRoom(minefield, run)
    if not result.ok then
        if result.status == "searched" then
            ShowMessage("这个房间已经搜过了.")
        elseif result.status == "spawn" then
            ShowMessage("出生点没有可带走的物资.")
        elseif result.status == "event" then
            ShowMessage("事件房没有宝箱，按 T 处理事件。")
        elseif result.status == "exit" then
            ShowMessage("这里是撤离点, 准备好就按 E 撤离.")
        else
            ShowMessage("当前房间无法搜索.")
        end
        return
    end

    local reward = result.reward
    DungeonRoom.TriggerChestOpen(reward)

    -- 教程:通知搜索完成
    Tutorial.NotifyAction("search")

    -- 搜索后可能获得战斗力加成
    local p = run:GetPlayer()
    local powerUp = Combat.TryPowerUp(minefield, p.x, p.y)

    local msg = reward.isChest and ("宝箱开启! 金币 +" .. reward.gold) or ("搜索完成:金币 +" .. reward.gold)
    if reward.parts > 0 then
        msg = msg .. ", 回收物 +" .. reward.parts
    end
    if powerUp > 0 then
        msg = msg .. ", 战斗力 +" .. powerUp
    end
    if reward.isChest then
        -- v0.3: 宝箱开启后标记房间已清理
        minefield:ClearRoom(p.x, p.y)
        ShowMessage(msg .. ".")
    else
        ShowMessage(msg .. ".")
    end

    OpenLootResultPanel(reward, powerUp)
    UpdateHUD()
end

--- 传送到已探索的安全格
function TeleportTo(x, y)
    if not run then return end
    if not minefield:IsExplored(x, y) then
        ShowMessage("只能传送到已探索的安全房间.")
        return
    end

    -- 直接设置玩家位置
    run.player.x = x
    run.player.y = y
    DungeonRoom.ResetPlayer()

    if CanSearchCurrentRoom() then
        ShowMessage("传送成功.这个房间还有物资可搜.")
    else
        ShowMessage("传送成功!")
    end
    MapOverlay.Hide()
    phase = PHASE.PLAYING
    RefreshMapData()
    UpdateHUD()
end

--- 撤离确认
function DoExtract()
    if not run then return end
    if not run:CanExtract() then
        ShowMessage("当前位置无法撤离.")
        return
    end
    -- 弹出确认面板
    phase = PHASE.CONFIRM_EXTRACT
    DungeonRoom.TriggerExitPulse()
    local totals = RunInventory.GetTotals()
    local stats = RunInventory.GetRunStats(run)
    local protocol = Protocol.GetStatus()
    local reward = RunInventory.GetExtractionReward()

    -- 更新确认面板信息. 分成多个 Label, 避免像素字体把换行符画成缺字方块.
    local goldLine = uiRoot_:FindById("extractGoldLine")
    if goldLine then goldLine:SetText("安全金币:+" .. totals.gold) end

    local partsLine = uiRoot_:FindById("extractPartsLine")
    if partsLine then
        partsLine:SetText("入库回收物估值:+" .. reward.carriedItemValue .. " (" .. reward.carriedItemCount .. " 件)")
    end

    local totalLine = uiRoot_:FindById("extractTotalLine")
    if totalLine then
        totalLine:SetText("预计金币收益:+" .. reward.totalGold .. " 金币")
    end

    local searchLine = uiRoot_:FindById("extractSearchLine")
    if searchLine then
        searchLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. totals.searchedRooms ..
            " | 事件:" .. stats.eventsCompleted)
    end

    local protocolLine = uiRoot_:FindById("extractProtocolLine")
    if protocolLine then
        protocolLine:SetText("协议等级:" .. protocol.level .. " (" .. protocol.description .. ")")
    end

    local panel = uiRoot_:FindById("extractConfirmPanel")
    if panel then panel:Show() end
end

--- 确认撤离(实际执行)
function ConfirmExtract()
    if not run then return end
    local result = run:Extract()
    if result.ok then
        phase = PHASE.EXTRACTED
        local reward = RunInventory.GetExtractionReward()
        local stats = RunInventory.GetRunStats(run)
        local allowWarehouseRewards = not (currentRunConfig and currentRunConfig.allowWarehouseRewards == false)

        local receipt = nil
        if allowWarehouseRewards and not extractionSettlementRecorded then
            receipt = MetaProgress.RecordExtractionReward(reward, stats)
            extractionSettlementRecorded = true
        else
            receipt = { goldAfter = MetaProgress.GetGold(), itemCount = 0, itemValue = 0 }
        end

        if allowWarehouseRewards then
            ShowMessage("撤离成功!共获得 " .. reward.totalGold .. " 金币.")
        else
            ShowMessage("训练工单完成:不消耗后勤物资,不登记回收记录。")
        end
        local confirmPanel = uiRoot_:FindById("extractConfirmPanel")
        if confirmPanel then confirmPanel:Hide() end
        local winPanel = uiRoot_:FindById("winPanel")
        if winPanel then winPanel:Show() end
        local winGoldLine = uiRoot_:FindById("winGoldLine")
        if winGoldLine then
            if allowWarehouseRewards then
                winGoldLine:SetText("获得金币:+" .. reward.totalGold .. " (总计 " .. (receipt.goldAfter or MetaProgress.GetGold()) .. ")")
            else
                winGoldLine:SetText("训练工单:局外金币 +0")
            end
        end

        local winConvertLine = uiRoot_:FindById("winConvertLine")
        if winConvertLine then
            if not allowWarehouseRewards then
                winConvertLine:SetText("训练工单不会写入后勤仓库或回收资历")
            elseif reward.carriedItemCount > 0 then
                local looseText = reward.looseParts > 0 and (" | 零散零件折算 +" .. reward.loosePartsGold) or ""
                winConvertLine:SetText("后勤已登记: " .. reward.carriedItemCount .. " 件 | 估值 +" .. reward.carriedItemValue .. looseText .. " | " .. reward.carriedSummary)
            elseif reward.looseParts > 0 then
                winConvertLine:SetText("局内金币 " .. reward.directGold .. " + 零散零件 " .. reward.looseParts .. " 个 -> +" .. reward.convertedGold)
            else
                winConvertLine:SetText("没有回收物折算")
            end
        end

        local winStatsLine = uiRoot_:FindById("winStatsLine")
        if winStatsLine then
            winStatsLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. stats.searchedRooms ..
                " | 回合:" .. result.turn)
        end

        local winRiskLine = uiRoot_:FindById("winRiskLine")
        if winRiskLine then
            winRiskLine:SetText("触雷:" .. stats.mineHits .. " | 击败:" .. stats.monstersDefeated ..
                " | 事件:" .. stats.eventsCompleted .. " | 交易:" .. stats.trades)
        end
    end
end

--- 取消撤离
function CancelExtract()
    phase = PHASE.PLAYING
    local panel = uiRoot_:FindById("extractConfirmPanel")
    if panel then panel:Hide() end
end

local function GetEventContext()
    local totals = RunInventory.GetTotals()
    return {
        gold = totals.gold,
        pendingGold = totals.pendingGold,
        safeGold = totals.safeGold,
        parts = totals.looseParts or 0,
        tradableItems = RunInventory.GetTradableItems(),
        hp = Combat.hp,
        maxHp = Combat.maxHp,
        tradePrice = GetActiveTalentEffects().tradePrice,
        power = Combat.power,
    }
end

local function RefreshEventPanel()
    if not eventPanel.active then return end
    eventPanel.data = EventSystem.GetOptions(eventPanel.x, eventPanel.y, GetEventContext())
    local count = #(eventPanel.data.options or {})
    if count < 1 then
        eventPanel.selected = 1
    elseif eventPanel.selected > count then
        eventPanel.selected = count
    elseif eventPanel.selected < 1 then
        eventPanel.selected = 1
    end
end

local function CloseEventPanel(msg)
    eventPanel.active = false
    eventPanel.data = nil
    eventPanel.message = ""
    phase = PHASE.PLAYING
    if msg and msg ~= "" then
        ShowMessage(msg)
    end
end

local function ApplyEventResult(result, x, y)
    if not result then return end
    local displayMsg = result.msg or ""
    if not result.ok then
        eventPanel.message = displayMsg ~= "" and displayMsg or "条件不足."
        ShowMessage(eventPanel.message)
        RefreshEventPanel()
        return
    end

    if result.goldDelta ~= 0 then
        RunInventory.AddPendingGold(result.goldDelta)
    end
    if result.pendingGoldDelta and result.pendingGoldDelta ~= 0 then
        RunInventory.AddPendingGold(result.pendingGoldDelta)
    end
    if result.safeGoldDelta and result.safeGoldDelta ~= 0 then
        RunInventory.AddSafeGold(result.safeGoldDelta)
    end
    if result.partsDelta ~= 0 then
        RunInventory.parts = RunInventory.parts + result.partsDelta
        if RunInventory.parts < 0 then RunInventory.parts = 0 end
    end
    if result.sellItemId then
        RunInventory.RemoveTradableItem(result.sellItemId, result.sellCount or 1)
    end
    if result.rewardItemQuality then
        RunInventory.AddRewardItemByQuality(result.rewardItemQuality, "event")
    end
    for _, rewardItem in ipairs(result.rewardItems or {}) do
        local count = math.max(1, math.floor(tonumber(rewardItem.count) or 1))
        for _ = 1, count do
            RunInventory.AddRewardItemByQuality(rewardItem.quality, "event")
        end
    end
    if result.hpDelta ~= 0 then
        Combat.ApplyHpDelta(result.hpDelta)
    end
    if result.powerDelta and result.powerDelta ~= 0 then
        Combat.power = Combat.power + result.powerDelta
    end
    if result.pressureDelta and result.pressureDelta > 0 then
        local protoResult = Protocol.AddPressure(result.pressureDelta)
        local pressureMsg = "协议压力 +" .. result.pressureDelta
        if protoResult.changed then
            pressureMsg = pressureMsg .. ", 协议降至 " .. protoResult.level .. " - " .. protoResult.description
        end
        displayMsg = (displayMsg ~= "" and (displayMsg .. " ") or "") .. pressureMsg .. "."
    end

    if result.completed then
        local key = tostring(x) .. "," .. tostring(y)
        tradedRooms[key] = true
        RunInventory.RecordEvent(result.eventType)
        if minefield then
            minefield:ClearRoom(x, y)
        end
        DungeonRoom.TriggerTradePulse()
    end

    if Combat.hp <= 0 then
        CloseEventPanel()
        ShowFailurePanel("事件导致血量归零!")
        return
    end

    if result.closePanel then
        CloseEventPanel(displayMsg)
    else
        eventPanel.message = displayMsg
        ShowMessage(eventPanel.message)
        RefreshEventPanel()
    end
    UpdateHUD()
end

function ConfirmEventOption()
    if not eventPanel.active or not eventPanel.data then return end
    local options = eventPanel.data.options or {}
    local selected = options[eventPanel.selected]
    if not selected then return end
    local result = EventSystem.ExecuteOptionById(eventPanel.x, eventPanel.y, selected.id, GetEventContext())
    ApplyEventResult(result, eventPanel.x, eventPanel.y)
end

--- 事件房交互（打开统一事件面板）
function DoTrade()
    if not run or not minefield then return end
    local p = run:GetPlayer()
    local cell = minefield:GetCellView(p.x, p.y)
    if not cell or cell.roomType ~= "event" then
        ShowMessage("这里没有可交互的事件.")
        return
    end
    eventPanel.active = true
    eventPanel.x = p.x
    eventPanel.y = p.y
    eventPanel.selected = 1
    eventPanel.message = ""
    phase = PHASE.EVENT_PANEL
    RefreshEventPanel()
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
    messageTimer = 3.0
    messageDuration = 3.0
end

local function UseEmergencyBandage()
    local ok, result = RunInventory.UseConsumable("emergency_bandage", {
        hp = Combat.hp,
        maxHp = Combat.maxHp,
        applyHpDelta = function(delta)
            return Combat.ApplyHpDelta(delta)
        end,
    })
    if ok then
        ShowMessage("使用应急止血贴, 生命 +" .. result.heal .. "。剩余 " .. result.count .. "。")
        UpdateHUD()
    elseif result == "hp_full" then
        ShowMessage("生命已满, 暂不需要止血贴。")
    elseif result == "not_enough" then
        ShowMessage("没有可用的应急止血贴。")
    else
        ShowMessage("当前无法使用止血贴。")
    end
end

function CountVisitedCells()
    if minefield then
        return minefield:GetExploredCount()
    end
    return 0
end

function UpdateHUD()
    if not run then return end
    -- v0.3: 协议由 Protocol.AddPressure() 在探索时实时驱动, 此处不再主动更新
    -- HUD 数据由 NanoVG 每帧实时读取, 无需再手动更新 UI Label
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

--- 绘制 VS 战斗演出
function DrawBattleOverlay(vg, w, h)
    local combat = Combat.GetStatus()
    local enemy = battleState.enemy
    if not enemy then return end

    -- 半透明背景遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    local cx = w / 2
    local cy = h / 2

    if battleState.phase == "vs" then
        -- === VS 阶段:展示双方 ===
        local progress = 1.0 - (battleState.timer / BATTLE_VS_DURATION)
        local slideIn = math.min(1.0, progress * 3.0) -- 快速滑入

        -- 玩家侧(左)
        local playerX = cx - 120 * slideIn
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 玩家精灵
        if imgBattlePlayer >= 0 then
            local sz = 64
            local paint = nvgImagePattern(vg, playerX - sz/2, cy - 20 - sz/2, sz, sz, 0, imgBattlePlayer, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, playerX - sz/2, cy - 20 - sz/2, sz, sz)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgCircle(vg, playerX, cy - 20, 36)
            nvgFillColor(vg, nvgRGBA(40, 120, 200, 220))
            nvgFill(vg)
        end

        -- 玩家战力
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
        nvgText(vg, playerX, cy + 28, "战力 " .. combat.power)

        -- 玩家血量
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(255, 140, 140, 230))
        nvgText(vg, playerX, cy + 46, "HP " .. combat.hp .. "/" .. combat.maxHp)

        -- VS 文字(中间脉冲)
        local pulse = math.abs(math.sin(progress * math.pi * 3)) * 0.3 + 0.7
        nvgFontSize(vg, 42 * pulse)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, math.floor(255 * pulse)))
        nvgText(vg, cx, cy - 10, "VS")

        -- 敌人侧(右)
        local enemyX = cx + 120 * slideIn

        -- 敌人精灵
        if imgBattleEnemy >= 0 then
            local sz = 64
            local paint = nvgImagePattern(vg, enemyX - sz/2, cy - 20 - sz/2, sz, sz, 0, imgBattleEnemy, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, enemyX - sz/2, cy - 20 - sz/2, sz, sz)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgCircle(vg, enemyX, cy - 20, 36)
            nvgFillColor(vg, nvgRGBA(180, 40, 40, 220))
            nvgFill(vg)
        end

        -- 敌人名称
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 180, 100, 255))
        nvgText(vg, enemyX, cy + 28, enemy.name)

        -- 敌人战力
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, 255))
        nvgText(vg, enemyX, cy + 46, "战力 " .. enemy.power)

        local delta = combat.power - enemy.power
        local compareText = delta >= 0 and ("优势 +" .. delta) or ("危险 " .. delta)
        local compareColor = delta >= 0 and { 90, 240, 130 } or { 255, 90, 70 }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 62, cy + 64, 124, 24, 5)
        nvgFillColor(vg, nvgRGBA(12, 16, 26, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(compareColor[1], compareColor[2], compareColor[3], 170))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(compareColor[1], compareColor[2], compareColor[3], 245))
        nvgText(vg, cx, cy + 76, compareText)

        -- 底部提示
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, math.floor(150 + 80 * pulse)))
        nvgText(vg, cx, cy + 106, "按任意键跳过")

    elseif battleState.phase == "result" then
        -- === 结果阶段 ===
        local result = battleState.result
        if not result then return end

        local progress = 1.0 - (battleState.timer / BATTLE_RESULT_DURATION)
        local scaleIn = math.min(1.0, progress * 4.0)
        local playerPower = result.playerPower or enemy.playerPower or combat.power
        local enemyPower = result.enemyPower or enemy.power

        if result.playerWin then
            -- 胜利
            nvgFontSize(vg, 36 * scaleIn)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(80, 255, 120, 255))
            nvgText(vg, cx, cy - 20, "胜利!")

            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(200, 255, 200, 220))
            nvgText(vg, cx, cy + 20, "战力 " .. combat.power .. " >= " .. enemy.power .. ", 无伤通过")
        elseif result.dead then
            -- 死亡
            nvgFontSize(vg, 36 * scaleIn)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 50, 50, 255))
            nvgText(vg, cx, cy - 20, "败北...")

            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(255, 150, 150, 220))
            nvgText(vg, cx, cy + 20, "受到 " .. result.damage .. " 伤害, 血量归零")
        else
            -- 惨胜
            nvgFontSize(vg, 36 * scaleIn)
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
            nvgText(vg, cx, cy - 20, "惨胜")

            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(255, 220, 150, 220))
            nvgText(vg, cx, cy + 20, "击败敌人, 损失 -" .. result.damage .. " HP (剩余 " .. result.hp .. ")")
        end

        -- 底部提示
        local statusText = result.dead
            and ("我方 " .. playerPower .. " / 敌方 " .. enemyPower .. "  战败")
            or ("我方 " .. playerPower .. " / 敌方 " .. enemyPower .. "  房间已清理")
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(210, 220, 240, 220))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, cx, cy + 42, statusText)

        local pulse = math.abs(math.sin(progress * math.pi * 2)) * 0.4 + 0.6
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, math.floor(150 + 80 * pulse)))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, cx, cy + 60, "按任意键继续")
    end
end

-- ============================================================================
-- 设置面板
-- ============================================================================

local SETTINGS_OPTIONS = {
    { label = "继续游戏",   action = "resume" },
    { label = "重新开始",   action = "restart" },
    { label = "返回主界面", action = "menu" },
}

function DrawSettingsPanel(vg, w, h)
    local panelW = math.min(340, w - 60)
    local panelH = 260
    local x = (w - panelW) / 2
    local y = (h - panelH) / 2

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(16, 22, 32, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 160, 200, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(230, 240, 255, 255))
    nvgText(vg, x + panelW / 2, y + 36, "设置")

    -- 选项按钮
    local btnW = panelW - 60
    local btnH = 44
    local startY = y + 74
    local gap = 12

    for i, opt in ipairs(SETTINGS_OPTIONS) do
        local btnX = x + (panelW - btnW) / 2
        local btnY = startY + (i - 1) * (btnH + gap)
        local isSelected = (i == settingsPanel.selected)

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 6)
        if isSelected then
            nvgFillColor(vg, nvgRGBA(40, 100, 140, 220))
            nvgStrokeColor(vg, nvgRGBA(100, 200, 240, 255))
            nvgStrokeWidth(vg, 2)
        else
            nvgFillColor(vg, nvgRGBA(30, 40, 55, 180))
            nvgStrokeColor(vg, nvgRGBA(60, 80, 100, 140))
            nvgStrokeWidth(vg, 1)
        end
        nvgFill(vg)
        nvgStroke(vg)

        -- 按钮文字
        nvgFontSize(vg, 17)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isSelected then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 200, 215, 220))
        end
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, opt.label)
    end

    -- 底部提示
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 160, 180, 160))
    nvgText(vg, x + panelW / 2, y + panelH - 20, "ESC 关闭  |  ↑↓ 选择  |  Enter 确认")
end

--- 执行设置面板选项
local function ExecuteSettingsOption()
    local opt = SETTINGS_OPTIONS[settingsPanel.selected]
    if not opt then return end

    if opt.action == "resume" then
        phase = PHASE.PLAYING
    elseif opt.action == "restart" then
        ConfirmDeploy()
    elseif opt.action == "menu" then
        ReturnToMenu()
    end
    settingsPanel.selected = 1
end

function DrawEventPanel(vg, w, h)
    if not eventPanel.active or not eventPanel.data then return end

    local data = eventPanel.data
    local options = data.options or {}
    local panelW = math.min(620, w - 90)
    local panelH = math.min(math.max(430, 190 + #options * 50), h - 50)
    local x = (w - panelW) / 2
    local y = (h - panelH) / 2

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 145))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, panelW, panelH, 8)
    nvgFillColor(vg, nvgRGBA(18, 24, 34, 238))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(90, 180, 190, 210))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(235, 250, 255, 255))
    nvgText(vg, x + 28, y + 22, data.title or "事件")

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(170, 205, 210, 230))
    nvgText(vg, x + 28, y + 56, data.description or "")

    local listY = y + 96
    local rowH = 50
    local maxRows = math.floor((panelH - 188) / rowH)
    if maxRows < 1 then maxRows = 1 end
    local startIndex = 1
    if #options > maxRows then
        startIndex = eventPanel.selected - math.floor(maxRows / 2)
        if startIndex < 1 then startIndex = 1 end
        if startIndex > #options - maxRows + 1 then
            startIndex = #options - maxRows + 1
        end
    end
    local endIndex = math.min(#options, startIndex + maxRows - 1)

    if #options > maxRows then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(150, 170, 180, 210))
        nvgText(vg, x + panelW - 28, y + 62, "选项 " .. startIndex .. "-" .. endIndex .. " / " .. #options)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    end

    for i = startIndex, endIndex do
        local opt = options[i]
        local oy = listY + (i - startIndex) * rowH
        local selected = i == eventPanel.selected
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + 24, oy, panelW - 48, rowH - 6, 6)
        if selected then
            nvgFillColor(vg, nvgRGBA(55, 90, 105, 235))
        else
            nvgFillColor(vg, nvgRGBA(28, 38, 50, 210))
        end
        nvgFill(vg)
        if selected then
            nvgStrokeColor(vg, nvgRGBA(120, 235, 230, 230))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        local enabled = opt.enabled ~= false
        nvgFontSize(vg, 14)
        nvgFillColor(vg, enabled and nvgRGBA(245, 240, 200, 255) or nvgRGBA(120, 125, 130, 210))
        nvgText(vg, x + 40, oy + 8, (selected and "> " or "  ") .. (opt.label or "选项"))

        nvgFontSize(vg, 10)
        nvgFillColor(vg, enabled and nvgRGBA(165, 185, 195, 230) or nvgRGBA(105, 110, 118, 190))
        local meta = "成本: " .. (opt.cost or "无") .. "   收益: " .. (opt.reward or "无") .. "   风险: " .. (opt.risk or "无")
        if not enabled and opt.disabledReason then
            meta = meta .. "   [" .. opt.disabledReason .. "]"
        end
        nvgText(vg, x + 40, oy + 27, meta)
    end

    local selected = options[eventPanel.selected]
    if selected then
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(200, 220, 220, 230))
        nvgText(vg, x + 28, y + panelH - 70, selected.description or "")
    end
    if eventPanel.message and eventPanel.message ~= "" then
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(255, 185, 120, 245))
        nvgText(vg, x + 28, y + panelH - 44, eventPanel.message)
    end

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(150, 165, 180, 220))
    nvgText(vg, x + panelW - 28, y + panelH - 30, "W/S 或 ↑/↓ 选择   T/Enter 确认   Esc 返回")
end

local ITEM_RARITY_COLORS = {
    common = { 180, 200, 210 },
    uncommon = { 120, 220, 170 },
    rare = { 115, 180, 255 },
}

local function rarityColor(rarity)
    return ITEM_RARITY_COLORS[rarity or "common"] or ITEM_RARITY_COLORS.common
end

local function drawLootItemCard(vg, stack, x, y, w, h)
    local def = stack and stack.def or RunInventory.GetItemDef(stack and stack.itemId)
    if not def then return end
    local color = rarityColor(def.rarity)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 7)
    nvgFillColor(vg, nvgRGBA(24, 31, 42, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 190))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local iconSize = 56
    local iconX = x + 14
    local iconY = y + 16
    nvgBeginPath(vg)
    nvgRoundedRect(vg, iconX, iconY, iconSize, iconSize, 6)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 48))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
    nvgText(vg, iconX + iconSize / 2, iconY + iconSize / 2, "物")

    local textX = iconX + iconSize + 14
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(240, 245, 235, 255))
    local countText = (stack.count or 1) > 1 and (" x" .. stack.count) or ""
    nvgText(vg, textX, y + 14, def.name .. countText)

    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
    nvgText(vg, textX, y + 37, def.typeName .. " · " .. def.rarityName)

    local descY = y + 58
    if def.effectText and def.effectText ~= "" then
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(215, 230, 170, 230))
        nvgText(vg, textX, descY, def.effectText)
        descY = descY + 18
    end

    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(175, 188, 196, 220))
    nvgText(vg, textX, descY, def.description or "")

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 230))
    nvgText(vg, x + w - 12, y + 14, "估值 " .. tostring((def.value or 0) * (stack.count or 1)))
end

function DrawLootResultPanel(vg, w, h)
    if not lootPanel.active or not lootPanel.reward then return end

    local reward = lootPanel.reward
    local items = reward.items or {}
    local panelW = math.min(680, w - 80)
    local panelH = math.min(math.max(360, 210 + math.max(1, #items) * 108), h - 50)
    local x = (w - panelW) / 2
    local y = (h - panelH) / 2

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, panelW, panelH, 8)
    nvgFillColor(vg, nvgRGBA(17, 23, 32, 242))
    nvgFill(vg)
    nvgStrokeColor(vg, reward.isChest and nvgRGBA(240, 190, 90, 220) or nvgRGBA(90, 170, 190, 210))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(242, 246, 235, 255))
    nvgText(vg, x + 26, y + 22, lootPanel.title)

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(180, 205, 210, 230))
    nvgText(vg, x + 26, y + 54, lootPanel.subtitle)

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(255, 226, 120, 245))
    local summary = "结算币 +" .. (reward.gold or 0) .. "    回收物 " .. (reward.parts or 0) .. " 件    估值 +" .. (reward.itemValue or 0)
    if lootPanel.powerUp and lootPanel.powerUp > 0 then
        summary = summary .. "    战力 +" .. lootPanel.powerUp
    end
    nvgText(vg, x + 26, y + 78, summary)

    local listY = y + 112
    local cardH = 96
    if #items == 0 then
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 190, 200, 220))
        nvgText(vg, x + 26, listY + 20, "未发现可携带回收物。")
    else
        local maxCards = math.floor((panelH - 168) / (cardH + 10))
        if maxCards < 1 then maxCards = 1 end
        for i = 1, math.min(#items, maxCards) do
            local stack = {
                itemId = items[i].itemId,
                count = items[i].count,
                def = RunInventory.GetItemDef(items[i].itemId),
            }
            drawLootItemCard(vg, stack, x + 24, listY + (i - 1) * (cardH + 10), panelW - 48, cardH)
        end
    end

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(155, 170, 180, 220))
    nvgText(vg, x + panelW - 26, y + panelH - 30, "Enter / F / Esc 确认放入临时回收包")
end

function HandleNanoVGRender(eventType, eventData)
    if not nvgScene then return end

    local w, h = GetLogicalScreenSize()

    -- NanoVG expects logical window size plus DPR. The HUD layout, mouse input,
    -- and scene helpers already use logical pixels, so keep the frame in the
    -- same coordinate space to avoid packaged builds rendering text smaller.
    nvgBeginFrame(nvgScene, w, h, dpr)

    if phase == PHASE.PLAYING or phase == PHASE.EVENT_PANEL or phase == PHASE.LOOT_RESULT or phase == PHASE.CONFIRM_EXTRACT or phase == PHASE.GAME_OVER or phase == PHASE.EXTRACTED or phase == PHASE.SETTINGS then
        local hudLayout = HUD.ComputeLayout(w, h)
        local p = run:GetPlayer()
        local cell = minefield and minefield:GetCellView(p.x, p.y) or nil

        -- 预计算共用数据
        local visMap = minefield and minefield:GetVisibleMap() or nil
        if visMap then
            for y, row in ipairs(visMap) do
                for x, mapCell in ipairs(row) do
                    if mapCell.roomType == "monster" then
                        local mapEnemy = Combat.GetEnemyAny(x, y)
                        mapCell.monsterCleared = mapEnemy ~= nil and mapEnemy.alive == false
                    elseif mapCell.roomType == "event" then
                        mapCell.eventCompleted = EventSystem.IsCompleted(x, y)
                    end
                end
            end
        end
        local combatStatus = Combat.GetStatus()
        local invTotals = RunInventory.GetTotals()
        local invStatus = {
            gold = invTotals.gold,
            parts = invTotals.parts,
            carriedItemCount = invTotals.carriedItemCount,
            carriedItemValue = invTotals.carriedItemValue,
            consumables = invTotals.consumables,
        }

        -- 中央游戏区(带偏移和裁剪)
        local c = hudLayout.center
        nvgSave(nvgScene)
        nvgScissor(nvgScene, c.x, c.y, c.w, c.h)
        nvgTranslate(nvgScene, c.x + screenShake.offsetX, c.y + screenShake.offsetY)
        DungeonRoom.Draw(nvgScene, c.w, c.h, {
            run = run,
            minefield = minefield,
            searchState = GetSearchState(),
            enemy = Combat.GetEnemyAny(p.x, p.y),
            combat = combatStatus,
            eventTraded = EventSystem.IsCompleted(p.x, p.y),
            eventType = (cell and cell.roomType == "event") and EventSystem.GetEventType(p.x, p.y) or nil,
            inventory = invStatus,
            tradePrice = GetActiveTalentEffects().tradePrice,
            monsterFleeActive = monsterFleeActive,
            monsterFleeTimer = monsterFleeTimer,
        })
        nvgRestore(nvgScene)

        -- HUD: 左侧信息栏
        local exploredCount = Protocol.exploredRooms or 0

        local dt = 1.0 / 60.0
        HUD.DrawLeftSidebar(nvgScene, hudLayout, {
            visibleMap = visMap,
            playerX = p.x,
            playerY = p.y,
            fieldWidth = minefield and minefield.width or 15,
            fieldHeight = minefield and minefield.height or 15,
            combat = combatStatus,
            inventory = invStatus,
            exploredCount = exploredCount,
            message = message,
            adjacent = cell and cell.adjacent or 0,
            roomType = cell and cell.roomType or "normal",
            protocolStatus = Protocol.GetStatus(),
            dt = dt,
        })

        -- HUD: 底部交互栏
        local roomType = cell and cell.roomType or "normal"
        local enemy = Combat.GetEnemyAny(p.x, p.y)
        local eventCompleted = EventSystem.IsCompleted(p.x, p.y)
        local eventDef = nil
        if roomType == "event" then
            eventDef = EventSystem.GetEventDef(EventSystem.GetEventType(p.x, p.y))
        end
        local interactHint = HUD.GetInteractHint({
            roomType = roomType,
            searchState = GetSearchState(),
            hasEnemy = enemy ~= nil,
            enemyAlive = enemy and enemy.alive or false,
            enemyPower = enemy and enemy.power or nil,
            enemyHP = enemy and enemy.monsterHP or nil,
            enemyMaxHP = enemy and enemy.monsterMaxHP or nil,
            playerPower = combatStatus.power,
            hasExit = cell and cell.exitId ~= nil,
            canTrade = roomType == "event" and not eventCompleted,
            eventName = eventDef and eventDef.name or nil,
            tradeUnavailable = false,
            eventTraded = eventCompleted,
        })

        -- 计算撤离距离
        local exitDist, exitDir = nil, ""
        if minefield then
            local exits = minefield:GetVisibleExits()
            exitDist, exitDir = HUD.CalcExitDistance(p.x, p.y, exits)
        end

        HUD.DrawBottomBar(nvgScene, hudLayout, {
            interactHint = interactHint,
            exitDistance = exitDist,
            exitDirection = exitDir,
            consumables = invTotals.consumables,
        })

        -- VS 战斗演出叠加层
        if battleState.active then
            DrawBattleOverlay(nvgScene, w, h)
        end
        if phase == PHASE.EVENT_PANEL then
            DrawEventPanel(nvgScene, w, h)
        end
        if phase == PHASE.LOOT_RESULT then
            DrawLootResultPanel(nvgScene, w, h)
        end
        if phase == PHASE.SETTINGS then
            DrawSettingsPanel(nvgScene, w, h)
        end
    elseif phase == PHASE.MAP_OPEN then
        -- 绘制放大地图
        RefreshMapData()
        MapOverlay.ComputeLayout(minefield.width, minefield.height, w, h)
        MapOverlay.Draw(nvgScene, w, h)
    end

    -- 教程对话框(绘制在游戏内容上层)
    if Tutorial.IsActive() then
        local step = Tutorial.GetCurrentStep()
        HUD.DrawTutorialDialog(nvgScene, w, h, step)
    end

    -- 居中播报(始终绘制在最上层)
    HUD.DrawCenterToast(nvgScene, { screenW = w, screenH = h }, message, messageTimer, messageDuration)

    nvgEndFrame(nvgScene)
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function CreateUI()
    -- (statusPanel, messageBar, bottomBar 已迁移到 NanoVG HUD, 不再创建)

    -- 开始菜单(三屏结构:主菜单 / 装备商店 / 天赋面板)
    local menuOverlay = UI.Panel {
        id = "menuOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 5, 8, 15, 230 },
        children = {
            -- === 主菜单页 ===
            UI.Panel {
                id = "menuPage_main",
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundImage = "Textures/menu_bg.png",
                backgroundFit = "fill",
                children = {
                    -- 右侧按钮区域，对应图片中"灰尾公司"招牌位置
                    UI.Panel {
                        visible = false,
                        position = "absolute",
                        right = "5%",
                        top = "28%",
                        width = "22%",
                        gap = 10,
                        alignItems = "stretch",
                        children = {
                            UI.Button {
                                text = "出发探索",
                                variant = "primary",
                                height = 40,
                                onClick = function()
                                    OpenDeployTerminal()
                                end,
                            },
                            UI.Button {
                                text = "新手教程",
                                height = 40,
                                onClick = function()
                                    OpenTutorial()
                                end,
                            },
                            UI.Button {
                                text = "调整终端",
                                height = 40,
                                onClick = function()
                                    OpenSettingsTerminal()
                                end,
                            },
                        }
                    },
                }
            },
            UI.Panel {
                id = "menuPage_deployOverview",
                visible = false,
                width = "92%",
                maxWidth = 620,
                padding = 24,
                gap = 10,
                backgroundColor = { 18, 26, 36, 242 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 90, 160, 210, 120 },
                children = {
                    UI.Label { text = "出勤准备", fontSize = 20, fontColor = { 180, 230, 255, 255 } },
                    UI.Label { id = "deployGoldLabel", text = "后勤账户: 0 金币", fontSize = 13, fontColor = { 255, 220, 100, 240 } },
                    UI.Label { id = "deployLoadoutLabel", text = "当前装备 无 | 本次带入 无", fontSize = 12, fontColor = { 190, 210, 230, 230 } },
                    UI.Label { id = "deployWarehouseLabel", text = "仓库库存 0 件 | 可售估值 0", fontSize = 12, fontColor = { 170, 210, 220, 220 } },
                    UI.Label { id = "deployRecentLabel", text = "最近带回: 无", fontSize = 12, fontColor = { 170, 185, 200, 220 } },
                    UI.Label { id = "deployBonusLabel", text = "当前主要加成: 无", fontSize = 12, fontColor = { 210, 220, 170, 230 } },
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 8,
                        marginTop = 8,
                        children = {
                            UI.Button { text = "后勤仓库", width = 100, height = 30, onClick = function() OpenDeployWarehouse() end },
                            UI.Button { text = "后勤申领", width = 100, height = 30, onClick = function() OpenDeployShop() end },
                            UI.Button { text = "出勤配置", width = 100, height = 30, onClick = function() OpenDeployLoadout() end },
                            UI.Button { text = "回收资历", width = 100, height = 30, onClick = function() OpenDeployRecovery() end },
                            UI.Button { text = "天赋", width = 80, height = 30, onClick = function() OpenDeployTalents() end },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 10,
                        children = {
                            UI.Button { text = "确认出发", variant = "primary", width = 120, height = 36, onClick = function() ConfirmDeploy() end },
                            UI.Button { text = "返回主界面", width = 120, height = 36, onClick = function() BackToMainMenu() end },
                        },
                    },
                },
            },
            -- === GM 调试面板 ===
            UI.Panel {
                id = "menuPage_gm",
                visible = false,
                width = "90%",
                maxWidth = 400,
                padding = 24,
                gap = 10,
                backgroundColor = { 40, 20, 20, 240 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 200, 80, 80, 120 },
                children = {
                    UI.Label {
                        text = "🔧 GM 调试面板",
                        fontSize = 18,
                        fontColor = { 255, 100, 100, 255 },
                    },
                    UI.Label {
                        id = "gmGoldLabel",
                        text = "当前金币: 0",
                        fontSize = 13,
                        fontColor = { 255, 220, 80, 255 },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 8,
                        width = "100%",
                        children = {
                            UI.Button {
                                text = "+100 金币",
                                width = 100,
                                onClick = function()
                                    MetaProgress.AddGold(100)
                                    RefreshGMPanel()
                                end,
                            },
                            UI.Button {
                                text = "+500 金币",
                                width = 100,
                                onClick = function()
                                    MetaProgress.AddGold(500)
                                    RefreshGMPanel()
                                end,
                            },
                            UI.Button {
                                text = "+9999 金币",
                                width = 100,
                                onClick = function()
                                    MetaProgress.AddGold(9999)
                                    RefreshGMPanel()
                                end,
                            },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 8,
                        width = "100%",
                        children = {
                            UI.Button {
                                text = "解锁全部物品",
                                width = 120,
                                onClick = function()
                                    GMUnlockAllItems()
                                    RefreshGMPanel()
                                end,
                            },
                            UI.Button {
                                text = "解锁全部天赋",
                                width = 120,
                                onClick = function()
                                    GMUnlockAllTalents()
                                    RefreshGMPanel()
                                end,
                            },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 8,
                        width = "100%",
                        children = {
                            UI.Button {
                                text = "装备全部物品",
                                width = 120,
                                onClick = function()
                                    GMEquipAll()
                                    RefreshGMPanel()
                                end,
                            },
                            UI.Button {
                                text = "清空装备",
                                width = 100,
                                onClick = function()
                                    GMUnequipAll()
                                    RefreshGMPanel()
                                end,
                            },
                        }
                    },
                    UI.Button {
                        text = "重置存档",
                        width = 120,
                        onClick = function()
                            GMResetSave()
                            RefreshGMPanel()
                        end,
                    },
                    UI.Label {
                        id = "gmStatusLabel",
                        text = "",
                        fontSize = 11,
                        fontColor = { 200, 200, 200, 200 },
                    },
                    UI.Button {
                        text = "返回",
                        width = 100,
                        marginTop = 8,
                        onClick = function()
                            BackToMainMenu()
                        end,
                    },
                }
            },
            -- === 装备商店页 ===
            UI.Panel {
                id = "menuPage_equip",
                visible = false,
                width = "90%",
                maxWidth = 400,
                padding = 24,
                gap = 10,
                backgroundColor = { 20, 25, 40, 240 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 60, 120, 180, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = "装备商店",
                                fontSize = 18,
                                fontColor = { 160, 210, 255, 255 },
                            },
                            UI.Label {
                                id = "equipGoldLabel",
                                text = "金币 0",
                                fontSize = 13,
                                fontColor = { 255, 220, 80, 255 },
                            },
                        }
                    },
                    UI.Label {
                        text = "选择携带进入地牢的装备(最多 2 件)",
                        fontSize = 11,
                        fontColor = { 140, 150, 170, 180 },
                    },
                    UI.Panel {
                        id = "equipItemList",
                        gap = 6,
                        width = "100%",
                        marginTop = 4,
                        children = {}
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        marginTop = 8,
                        children = {
                            UI.Button {
                                text = "天赋",
                                width = 80,
                                onClick = function()
                                    OpenDeployTalents()
                                end,
                            },
                            UI.Button {
                                text = "仓库",
                                width = 80,
                                onClick = function()
                                    OpenDeployWarehouse()
                                end,
                            },
                            UI.Button {
                                text = "返回",
                                width = 80,
                                onClick = function()
                                    OpenDeployOverview()
                                end,
                            },
                        },
                    },
                }
            },
            -- === 天赋面板页 ===
            UI.Panel {
                id = "menuPage_talent",
                visible = false,
                width = "90%",
                maxWidth = 400,
                padding = 24,
                gap = 10,
                backgroundColor = { 20, 25, 40, 240 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 120, 100, 60, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = "天赋",
                                fontSize = 18,
                                fontColor = { 255, 220, 100, 255 },
                            },
                            UI.Label {
                                id = "talentGoldLabel",
                                text = "金币 0",
                                fontSize = 13,
                                fontColor = { 255, 220, 80, 255 },
                            },
                        }
                    },
                    UI.Label {
                        text = "永久解锁, 机制型增强",
                        fontSize = 11,
                        fontColor = { 140, 150, 170, 180 },
                    },
                    UI.Panel {
                        id = "talentList",
                        gap = 6,
                        width = "100%",
                        marginTop = 4,
                        children = {}
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        marginTop = 8,
                        children = {
                            UI.Button {
                                text = "装备",
                                width = 80,
                                onClick = function()
                                    OpenDeployShop()
                                end,
                            },
                            UI.Button {
                                text = "仓库",
                                width = 80,
                                onClick = function()
                                    OpenDeployWarehouse()
                                end,
                            },
                            UI.Button {
                                text = "返回",
                                width = 80,
                                onClick = function()
                                    OpenDeployOverview()
                                end,
                            },
                        },
                    },
                }
            },
            -- === 后勤仓库页 ===
            UI.Panel {
                id = "menuPage_requisition",
                visible = false,
                width = "92%",
                maxWidth = 620,
                padding = 24,
                gap = 10,
                backgroundColor = { 20, 25, 40, 240 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 80, 140, 190, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label { text = "后勤申领", fontSize = 18, fontColor = { 170, 220, 255, 255 } },
                            UI.Label { id = "requisitionGoldLabel", text = "金币 0", fontSize = 13, fontColor = { 255, 220, 80, 255 } },
                        },
                    },
                    UI.Label { id = "requisitionLoadoutLabel", text = "装备 无 | 带入 无", fontSize = 11, fontColor = { 150, 170, 190, 210 } },
                    UI.Panel { id = "requisitionItemList", gap = 6, width = "100%", marginTop = 4, children = {} },
                    UI.Button { text = "返回", width = 80, marginTop = 8, onClick = function() OpenDeployOverview() end },
                },
            },
            UI.Panel {
                id = "menuPage_loadout",
                visible = false,
                width = "92%",
                maxWidth = 620,
                padding = 24,
                gap = 10,
                backgroundColor = { 18, 28, 34, 242 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 90, 180, 150, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label { text = "出勤配置", fontSize = 18, fontColor = { 180, 235, 210, 255 } },
                            UI.Label { id = "loadoutGoldLabel", text = "金币 0", fontSize = 13, fontColor = { 255, 220, 80, 255 } },
                        },
                    },
                    UI.Label { id = "loadoutLoadoutLabel", text = "装备 无 | 带入 无", fontSize = 11, fontColor = { 150, 190, 175, 220 } },
                    UI.Panel { id = "loadoutItemList", gap = 6, width = "100%", marginTop = 4, children = {} },
                    UI.Button { text = "返回", width = 80, marginTop = 8, onClick = function() OpenDeployOverview() end },
                },
            },
            UI.Panel {
                id = "menuPage_recovery",
                visible = false,
                width = "90%",
                maxWidth = 460,
                padding = 24,
                gap = 10,
                backgroundColor = { 24, 28, 36, 242 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 130, 170, 120, 120 },
                children = {
                    UI.Label { text = "回收资历", fontSize = 18, fontColor = { 210, 235, 170, 255 } },
                    UI.Label { id = "recoverySummaryLabel", text = "累计带回 0 件 | 历史估值 0", fontSize = 13, fontColor = { 200, 220, 210, 230 } },
                    UI.Label { id = "recoveryRecentLabel", text = "最近带回: 无", fontSize = 12, fontColor = { 170, 185, 200, 220 } },
                    UI.Button { text = "返回", width = 80, marginTop = 8, onClick = function() OpenDeployOverview() end },
                },
            },
            UI.Panel {
                id = "menuPage_warehouse",
                visible = false,
                width = "92%",
                maxWidth = 560,
                padding = 24,
                gap = 10,
                backgroundColor = { 18, 28, 34, 242 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 90, 150, 170, 120 },
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = "后勤仓库",
                                fontSize = 18,
                                fontColor = { 170, 230, 235, 255 },
                            },
                            UI.Label {
                                id = "warehouseGoldLabel",
                                text = "金币 0",
                                fontSize = 13,
                                fontColor = { 255, 220, 80, 255 },
                            },
                        },
                    },
                    UI.Label {
                        id = "warehouseSummaryLabel",
                        text = "库存 0 件 | 可售估值 0",
                        fontSize = 11,
                        fontColor = { 150, 170, 190, 210 },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        children = {
                            UI.Label { id = "warehouseFilterLabel", text = "分类: 全部", fontSize = 11, fontColor = { 150, 170, 190, 210 } },
                            UI.Button { text = "全部", width = 50, height = 26, onClick = function() OnSetWarehouseFilter("all") end },
                            UI.Button { text = "回收", width = 50, height = 26, onClick = function() OnSetWarehouseFilter("recovered") end },
                            UI.Button { text = "消耗", width = 50, height = 26, onClick = function() OnSetWarehouseFilter("consumable") end },
                            UI.Button { text = "装备", width = 50, height = 26, onClick = function() OnSetWarehouseFilter("equipment") end },
                        },
                    },
                    UI.Label { id = "warehouseLoadoutLabel", text = "装备 无 | 带入 无", fontSize = 11, fontColor = { 150, 170, 190, 210 } },
                    UI.Panel {
                        id = "warehouseItemList",
                        gap = 6,
                        width = "100%",
                        marginTop = 4,
                        children = {},
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        marginTop = 8,
                        children = {
                            UI.Button {
                                text = "装备",
                                width = 80,
                                onClick = function()
                                    OpenDeployShop()
                                end,
                            },
                            UI.Button {
                                text = "天赋",
                                width = 80,
                                onClick = function()
                                    OpenDeployTalents()
                                end,
                            },
                            UI.Button {
                                text = "返回",
                                width = 80,
                                onClick = function()
                                    OpenDeployOverview()
                                end,
                            },
                        },
                    },
                },
            },
            UI.Panel {
                id = "terminalNavOverlay",
                position = "absolute",
                left = 18,
                top = 18,
                width = 150,
                gap = 8,
                padding = 12,
                backgroundColor = { 10, 18, 28, 225 },
                borderRadius = 10,
                borderWidth = 1,
                borderColor = { 100, 180, 220, 120 },
                children = {
                    UI.Button { text = "接受工单", variant = "primary", height = 38, onClick = function() OpenDeployTerminal() end },
                    UI.Button { text = "展示工单", height = 30, onClick = function() OpenTutorial() end },
                    UI.Button { text = "调整终端", height = 30, onClick = function() OpenSettingsTerminal() end },
                },
            },
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
                    UI.Panel {
                        id = "gameOverInfo",
                        gap = 5,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "failureReasonLine",
                                text = "撤离失败",
                                fontSize = 13,
                                fontColor = { 230, 190, 190, 235 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "failureGoldLine",
                                text = "金币 0 (已安全保留)",
                                fontSize = 13,
                                fontColor = { 255, 220, 120, 235 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "failurePartsLine",
                                text = "零件 0 (将丢失)",
                                fontSize = 12,
                                fontColor = { 210, 190, 170, 220 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "failureProtocolLine",
                                text = "协议等级:5",
                                fontSize = 12,
                                fontColor = { 180, 190, 210, 220 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "failureStatsLine",
                                text = "探索:0 | 搜索:0 | 触雷:0 | 击败:0",
                                fontSize = 12,
                                fontColor = { 190, 200, 210, 220 },
                                textAlign = "center",
                            },
                        }
                    },
                    UI.Panel {
                        id = "failureChoicePanel",
                        gap = 10,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "failureSalvageInfo",
                                text = "可抢救零件",
                                fontSize = 13,
                                fontColor = { 255, 210, 150, 230 },
                            },
                            UI.Button {
                                id = "salvagePartButton",
                                text = "抢救 1 零件换金币",
                                variant = "primary",
                                width = 170,
                                onClick = function()
                                    ApplyFailureSalvage("salvage_part")
                                end,
                            },
                            UI.Button {
                                id = "acceptLossButton",
                                text = "放弃零件",
                                width = 170,
                                onClick = function()
                                    ApplyFailureSalvage("accept")
                                end,
                            },
                        }
                    },
                    UI.Button {
                        id = "restartAfterFailureButton",
                        text = "返回主菜单",
                        variant = "primary",
                        visible = false,
                        onClick = function()
                            ReturnToMenu()
                        end,
                    },
                }
            }
        }
    }

    -- 撤离确认面板
    local extractConfirmPanel = UI.Panel {
        id = "extractConfirmPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        children = {
            UI.Panel {
                width = "80%",
                maxWidth = 300,
                padding = 24,
                gap = 14,
                backgroundColor = { 12, 30, 45, 240 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 60, 160, 220, 120 },
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "确认撤离?",
                        fontSize = 20,
                        fontColor = { 100, 220, 255, 255 },
                    },
                    UI.Panel {
                        id = "extractConfirmInfo",
                        gap = 5,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "extractGoldLine",
                                text = "安全金币:+0",
                                fontSize = 13,
                                fontColor = { 255, 230, 120, 240 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "extractPartsLine",
                                text = "零件折算:+0 金币 (0 个)",
                                fontSize = 13,
                                fontColor = { 170, 220, 255, 230 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "extractTotalLine",
                                text = "本次撤离预计:+0 金币",
                                fontSize = 14,
                                fontColor = { 120, 255, 150, 245 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "extractSearchLine",
                                text = "已搜索房间:0 | 协议等级:5",
                                fontSize = 12,
                                fontColor = { 180, 195, 215, 220 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "extractProtocolLine",
                                text = "协议等级:5",
                                fontSize = 12,
                                fontColor = { 150, 185, 220, 210 },
                                textAlign = "center",
                            },
                        }
                    },
                    UI.Label {
                        text = "撤离后零件将转换为金币带出",
                        fontSize = 12,
                        fontColor = { 140, 200, 140, 200 },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        marginTop = 6,
                        children = {
                            UI.Button {
                                text = "确认撤离",
                                variant = "primary",
                                onClick = function() ConfirmExtract() end,
                            },
                            UI.Button {
                                text = "继续探索",
                                onClick = function() CancelExtract() end,
                            },
                        }
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
                        text = "撤离成功!",
                        fontSize = 22,
                        fontColor = { 80, 255, 120, 255 },
                    },
                    UI.Panel {
                        id = "winInfo",
                        gap = 5,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "winGoldLine",
                                text = "获得金币:+0 (总计 0)",
                                fontSize = 14,
                                fontColor = { 200, 255, 200, 240 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "winConvertLine",
                                text = "局内金币 0 + 零件 0 个 -> +0",
                                fontSize = 12,
                                fontColor = { 160, 220, 180, 220 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "winStatsLine",
                                text = "搜索房间:0 | 回合:0",
                                fontSize = 12,
                                fontColor = { 180, 205, 190, 220 },
                                textAlign = "center",
                            },
                            UI.Label {
                                id = "winRiskLine",
                                text = "触雷:0 | 击败:0 | 交易:0",
                                fontSize = 12,
                                fontColor = { 160, 210, 190, 215 },
                                textAlign = "center",
                            },
                        }
                    },
                    UI.Button {
                        text = "返回主菜单",
                        variant = "primary",
                        onClick = function()
                            ReturnToMenu()
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
            -- statusPanel, messageBar, bottomBar 已迁移到 NanoVG HUD
            menuOverlay,
            gameOverPanel,
            extractConfirmPanel,
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
    dpr = GetSafeDPR()

    local dt = eventData["TimeStep"]:GetFloat()
    if blockedWallHintTimer > 0 then
        blockedWallHintTimer = blockedWallHintTimer - dt
    end
    DungeonRoom.Update(dt)
    MiniMap.Update(dt)
    updateScreenShake(dt)
    UpdateCurrentMonsterCombat(dt)

    -- VS 战斗演出计时
    if battleState.active then
        battleState.timer = battleState.timer - dt
        if battleState.timer <= 0 then
            if battleState.phase == "vs" then
                -- VS 展示结束, 执行结算
                ResolveBattle()
            elseif battleState.phase == "result" then
                -- 结果展示结束
                FinishBattle()
            end
        end
    end

    -- 旧逃跑倒计时兼容:到时只关闭提示, 不再强制战斗.
    if monsterFleeActive and monsterFleeTimer > 0 then
        monsterFleeTimer = monsterFleeTimer - dt
        if monsterFleeTimer <= 0 then
            monsterFleeActive = false
            monsterFleeTimer = 0
        end
    end

    if messageTimer > 0 then
        messageTimer = messageTimer - dt
        if messageTimer <= 0 then
            message = ""
            local label = uiRoot_:FindById("messageLabel")
            if label then label:SetText("") end
        end
    end

    -- 连续移动:按住方向键时按帧平滑移动角色(战斗演出中禁止)
    if phase == PHASE.PLAYING and run and not battleState.active then
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
            Tutorial.NotifyAction("close_map")
        end
        return
    end

    if phase == PHASE.EVENT_PANEL then
        local count = eventPanel.data and #(eventPanel.data.options or {}) or 0
        if key == KEY_ESCAPE then
            CloseEventPanel("事件交互取消.")
        elseif key == KEY_W or key == KEY_UP then
            if count > 0 then
                eventPanel.selected = eventPanel.selected - 1
                if eventPanel.selected < 1 then eventPanel.selected = count end
            end
        elseif key == KEY_S or key == KEY_DOWN then
            if count > 0 then
                eventPanel.selected = eventPanel.selected + 1
                if eventPanel.selected > count then eventPanel.selected = 1 end
            end
        elseif key == KEY_T or key == KEY_RETURN then
            ConfirmEventOption()
        end
        return
    end

    if phase == PHASE.LOOT_RESULT then
        if key == KEY_ESCAPE or key == KEY_RETURN or key == KEY_F then
            CloseLootResultPanel()
        end
        return
    end

    -- 撤离确认面板
    if phase == PHASE.CONFIRM_EXTRACT then
        if key == KEY_E or key == KEY_RETURN then
            ConfirmExtract()
        elseif key == KEY_ESCAPE then
            CancelExtract()
        end
        return
    end

    -- 设置面板
    if phase == PHASE.SETTINGS then
        if key == KEY_ESCAPE then
            phase = PHASE.PLAYING
            settingsPanel.selected = 1
        elseif key == KEY_W or key == KEY_UP then
            settingsPanel.selected = settingsPanel.selected - 1
            if settingsPanel.selected < 1 then settingsPanel.selected = #SETTINGS_OPTIONS end
        elseif key == KEY_S or key == KEY_DOWN then
            settingsPanel.selected = settingsPanel.selected + 1
            if settingsPanel.selected > #SETTINGS_OPTIONS then settingsPanel.selected = 1 end
        elseif key == KEY_RETURN then
            ExecuteSettingsOption()
        end
        return
    end

    if phase == PHASE.MENU then
        if key == KEY_ESCAPE then
            HandleMenuEscape()
        end
        return
    end

    -- 菜单或结束阶段忽略
    if phase ~= PHASE.PLAYING then return end

    -- 战斗演出中:任意键可跳过当前阶段
    if battleState.active then
        if battleState.phase == "vs" then
            ResolveBattle()
        elseif battleState.phase == "result" then
            FinishBattle()
        end
        return
    end

    -- ESC 打开设置面板
    if key == KEY_ESCAPE then
        phase = PHASE.SETTINGS
        settingsPanel.selected = 1
        return
    end

    -- 功能键(移动已改为 Update 中连续检测)
    if key == KEY_W or key == KEY_UP or key == KEY_S or key == KEY_DOWN
       or key == KEY_A or key == KEY_LEFT or key == KEY_D or key == KEY_RIGHT then
        return
    elseif key == KEY_E then
        DoExtract()
    elseif key == KEY_F then
        local p = run and run:GetPlayer() or nil
        local enemy = p and Combat.GetEnemy(p.x, p.y) or nil
        if enemy then
            AttackCurrentEnemy()
        else
            SearchCurrentRoom()
        end
    elseif key == KEY_Q then
        UseEmergencyBandage()
    elseif key == KEY_T then
        DoTrade()
    elseif key == KEY_M then
        -- 打开放大地图
        phase = PHASE.MAP_OPEN
        MapOverlay.visible = true
        RefreshMapData()
        -- 教程:通知打开地图
        Tutorial.NotifyAction("open_map")
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

    -- 教程对话框点击(优先消耗)
    if button == MOUSEB_LEFT and Tutorial.IsActive() then
        if Tutorial.HandleClick() then
            -- 教程完成后回到菜单
            if not Tutorial.IsActive() then
                ReturnToMenu()
                ShowMessage("教程完成! 可以开始正式探索了.")
            end
            return
        end
    end

    -- 放大地图交互
    if phase == PHASE.MAP_OPEN then
        MapOverlay.HandleClick(mx, my, button)
        return
    end

    if button == MOUSEB_LEFT and HandleMenuHotspotClick(mx, my) then
        return
    end

    if phase == PHASE.LOOT_RESULT and button == MOUSEB_LEFT then
        CloseLootResultPanel()
        return
    end

    -- 设置面板点击
    if phase == PHASE.SETTINGS and button == MOUSEB_LEFT then
        local sw = screenW / dpr
        local sh = screenH / dpr
        local panelW = math.min(340, sw - 60)
        local panelH = 260
        local px = (sw - panelW) / 2
        local py = (sh - panelH) / 2
        local btnW = panelW - 60
        local btnH = 44
        local startY = py + 74
        local gap = 12
        local btnX = px + (panelW - btnW) / 2

        local clicked = false
        for i = 1, #SETTINGS_OPTIONS do
            local btnY = startY + (i - 1) * (btnH + gap)
            if mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH then
                settingsPanel.selected = i
                ExecuteSettingsOption()
                clicked = true
                break
            end
        end
        -- 点击面板外区域关闭
        if not clicked then
            if mx < px or mx > px + panelW or my < py or my > py + panelH then
                phase = PHASE.PLAYING
                settingsPanel.selected = 1
            end
        end
        return
    end

    if phase ~= PHASE.PLAYING then return end

    -- 战斗演出中:点击跳过
    if battleState.active then
        if battleState.phase == "vs" then
            ResolveBattle()
        elseif battleState.phase == "result" then
            FinishBattle()
        end
        return
    end

    -- 点击左侧栏小地图打开放大视图(使用侧栏区域检测)
    local w = screenW / dpr
    local h = screenH / dpr
    local hudLayout = HUD.ComputeLayout(w, h)
    local sb = hudLayout.sidebar
    if mx >= sb.x and mx <= sb.x + sb.w and my >= sb.y and my <= sb.y + sb.h then
        -- 点击侧边栏任意位置打开地图
        phase = PHASE.MAP_OPEN
        MapOverlay.visible = true
        RefreshMapData()
        Tutorial.NotifyAction("open_map")
        MapOverlay.ComputeLayout(minefield.width, minefield.height, w, h)
        return
    end

    -- 中央游戏区的点击检测(坐标需减去中央区偏移)
    local c = hudLayout.center
    local cmx = mx - c.x  -- 相对于中央游戏区的坐标
    local cmy = my - c.y

    if button == MOUSEB_LEFT and run then
        -- 只处理中央区域内的点击
        if cmx >= 0 and cmx <= c.w and cmy >= 0 and cmy <= c.h then
            -- 将中央区尺寸转为 "虚拟全屏" 给 DungeonRoom (它内部用 screenW/dpr 计算)
            local centerPhysW = math.floor(c.w * dpr)
            local centerPhysH = math.floor(c.h * dpr)

            if DungeonRoom.HitTestSearchPoint(cmx, cmy, centerPhysW, centerPhysH, dpr, GetSearchState()) then
                SearchCurrentRoom()
                return
            end

            local doorHit = DungeonRoom.HitTestDoor(cmx, cmy, centerPhysW, centerPhysH, dpr, run, minefield)
            if doorHit then
                MovePlayer(doorHit.dx, doorHit.dy)
            end
        end
    end
end
