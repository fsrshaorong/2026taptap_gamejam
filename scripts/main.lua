-- ============================================================================
-- 扫雷搜打撤 — 2026 TapTap GameJam
-- 架构:NanoVG context 绘制场景/地图 + UI 系统做 HUD 叠层
-- ============================================================================

local UI = require("urhox-libs/UI")
local ExtractionRun = require("systems.ExtractionRun")
local RunInventory = require("systems.RunInventory")
local Combat = require("systems.Combat")
local Protocol = require("systems.Protocol")
local MetaProgress = require("systems.MetaProgress")
local MiniMap = require("ui.MiniMap")
local MapOverlay = require("ui.MapOverlay")
local HUD = require("ui.HUD")
local DungeonRoom = require("scenes.DungeonRoom")
local EventSystem = require("systems.EventSystem")

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
local minefield = nil    -- Minefield 引用(run.minefield)

-- 玩家已访问的格子 (v0.3: 由 minefield:Explore() 管理, 此表仅作兼容)
local visitedCells = {}

-- 游戏阶段
local PHASE = {
    MENU = "menu",
    PLAYING = "playing",
    MAP_OPEN = "map_open",
    CONFIRM_EXTRACT = "confirm_extract",
    GAME_OVER = "game_over",
    EXTRACTED = "extracted",
}
local phase = PHASE.MENU

-- 消息
local message = ""
local messageTimer = 0
local blockedWallHintTimer = 0

-- 事件房交易记录(key = "x,y")
local tradedRooms = {}

-- 威压天赋:怪物逃跑窗口
local monsterFleeTimer = 0       -- 逃跑倒计时(秒)
local monsterFleeActive = false  -- 是否处于逃跑窗口中
local MONSTER_FLEE_BASE = 3.0    -- 基础逃跑时间(秒)

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

-- 菜单子页面状态
local menuPage = "main"  -- "main" | "equip" | "talent"

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
    nvgCreateFont(nvgScene, "sans", "Fonts/FusionPixel.otf")
    imgBattlePlayer = nvgCreateImage(nvgScene, "Textures/generated/characters/huli/frames/00_front_idle.png", 0)
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

    -- 背景音乐(循环播放)
    local bgmScene = Scene()
    local bgmNode = bgmScene:CreateChild("BGM")
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
-- 菜单页面管理
-- ============================================================================

--- 返回主菜单(从游戏结束/撤离成功面板)
function ReturnToMenu()
    phase = PHASE.MENU
    setVisible("gameOverPanel", false)
    setVisible("winPanel", false)
    local menu = uiRoot_:FindById("menuOverlay")
    if menu then menu:Show() end
    ShowMenuPage("main")
end

--- 切换菜单子页面
function ShowMenuPage(page)
    menuPage = page
    setVisible("menuPage_main", page == "main")
    setVisible("menuPage_equip", page == "equip")
    setVisible("menuPage_talent", page == "talent")
    setVisible("menuPage_gm", page == "gm")

    if page == "main" then
        RefreshMainMenu()
    elseif page == "equip" then
        RefreshEquipPage()
    elseif page == "talent" then
        RefreshTalentPage()
    elseif page == "gm" then
        RefreshGMPanel()
    end
end

--- 刷新主菜单数据
function RefreshMainMenu()
    local goldLabel = uiRoot_ and uiRoot_:FindById("menuGoldLabel")
    if goldLabel then
        goldLabel:SetText("金币: " .. MetaProgress.GetGold())
    end

    -- 装备信息
    local equipLabel = uiRoot_ and uiRoot_:FindById("menuEquippedLabel")
    if equipLabel then
        local equipped = MetaProgress.GetEquippedItems()
        if #equipped == 0 then
            equipLabel:SetText("装备: 无")
        else
            local names = {}
            for _, id in ipairs(equipped) do
                local def = MetaProgress.GetItemDef(id)
                if def then table.insert(names, def.icon .. def.name) end
            end
            equipLabel:SetText("装备: " .. table.concat(names, " "))
        end
    end

    -- 统计
    local statsLabel = uiRoot_ and uiRoot_:FindById("menuStatsLabel")
    if statsLabel then
        local stats = MetaProgress.GetStats()
        if stats.totalRuns > 0 then
            statsLabel:SetText("出击 " .. stats.totalRuns .. " 次 | 撤离 " .. stats.totalExtractions .. " 次")
        else
            statsLabel:SetText("首次探索, 祝你好运!")
        end
    end
end

--- 刷新装备商店页
function RefreshEquipPage()
    local goldLabel = uiRoot_ and uiRoot_:FindById("equipGoldLabel")
    if goldLabel then
        goldLabel:SetText("金币 " .. MetaProgress.GetGold())
    end

    local listPanel = uiRoot_ and uiRoot_:FindById("equipItemList")
    if not listPanel then return end
    listPanel:RemoveAllChildren()

    for _, item in ipairs(MetaProgress.ITEMS) do
        local owned = MetaProgress.OwnsItem(item.id)
        local equipped = MetaProgress.IsEquipped(item.id)

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
                            text = item.icon .. " " .. item.name,
                            fontSize = 13,
                            fontColor = { 230, 235, 245, 255 },
                        },
                        UI.Label {
                            text = item.desc,
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
    RefreshEquipPage()
end

--- 天赋点击处理
function OnTalentClick(talentId)
    local ok, err = MetaProgress.UnlockTalent(talentId)
    if not ok and err then
        print("[Menu] UnlockTalent failed: " .. err)
    end
    RefreshTalentPage()
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

function StartNewGame(override)
    local config = mergeConfig({
        mode = "normal",
        width = 15,
        height = 15,
        mineDensity = 0.14,
        spawnSafeRadius = 0,
        pathWidth = 0,
        randomExitCount = 2,
        monsterRoomRatio = 0.035,
        chestRoomRatio = 0.025,
        eventRoomRatio = 0.018,
        maxMonsterRooms = 7,
        maxChestRooms = 5,
        maxEventRooms = 3,
        mineHitsAreFatal = false,
        revealOnMove = true,
        moveRequiresRevealed = false,
    }, override)

    run = ExtractionRun.New(config)
    minefield = run.minefield

    -- 标记出生格为已探索(v0.3: 通过 Minefield:Explore 管理)
    visitedCells = {}
    local spawn = minefield:GetSpawn()
    visitedCells[tostring(spawn.x) .. "," .. tostring(spawn.y)] = true
    minefield:Explore(spawn.x, spawn.y)
    RunInventory.Reset()
    Combat.Reset()
    Protocol.Reset()
    DungeonRoom.ResetPlayer()
    tradedRooms = {}
    EventSystem.Reset(minefield.seed or os.time())

    -- 应用装备加成
    local equipBonus = MetaProgress.GetEquipBonus()
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

    -- 应用天赋效果
    local talentEffects = MetaProgress.GetTalentEffects()
    if talentEffects.mineDmgReduce > 0 then
        Combat.mineDmgReduce = talentEffects.mineDmgReduce
    end

    -- 记录出击
    MetaProgress.RecordRun()

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

    ShowMessage("左上角看扫雷数字避雷;WASD 走门, F 搜索, M 地图, E 撤离." .. compassHint)
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
        seed = 20260530,
        mineDensity = 0,
        mineCount = 0,
        randomExitCount = 0,
        spawnSafeRadius = 0,
        manualMap = JUDGE_DEMO_MAP,
    })
end

function ShowFailurePanel(reason)
    phase = PHASE.GAME_OVER

    local totals = RunInventory.GetTotals()
    local stats = RunInventory.GetRunStats(run)
    local options = RunInventory.GetFailureSalvageOptions()
    local protocol = Protocol.GetStatus()

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
        if totals.parts > 0 then
            if partsLine then partsLine:SetText("零件 " .. totals.parts .. " (将丢失)") end
        else
            if partsLine then partsLine:SetText("没有零件损失") end
        end

        local protocolLine = uiRoot_:FindById("failureProtocolLine")
        if protocolLine then protocolLine:SetText("协议等级:" .. protocol.level .. " / " .. protocol.description) end

        local statsLine = uiRoot_:FindById("failureStatsLine")
        if statsLine then
            statsLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. stats.searchedRooms ..
                " | 触雷:" .. stats.mineHits .. " | 击败:" .. stats.monstersDefeated)
        end
    end

    -- 如果有零件可以抢救, 显示选择面板;否则直接结算并显示重开按钮
    if options.canSalvagePart then
        setVisible("failureChoicePanel", true)
        local salvageInfo = uiRoot_:FindById("failureSalvageInfo")
        if salvageInfo then
            salvageInfo:SetText("可抢救 1 个零件(转为 " .. options.salvageBonus .. " 金币)")
        end
    else
        setVisible("failureChoicePanel", false)
        setVisible("restartAfterFailureButton", true)
        -- 无零件可抢救, 直接结算金币
        local talentBonus = MetaProgress.GetTalentEffects().failureGoldBonus
        local finalGold = totals.gold + talentBonus
        if finalGold > 0 then
            MetaProgress.AddGold(finalGold)
        end
        local goInfo2 = uiRoot_:FindById("gameOverInfo")
        if goInfo2 then
            local reasonLine = uiRoot_:FindById("failureReasonLine")
            if reasonLine then reasonLine:SetText(reason) end

            local goldLine = uiRoot_:FindById("failureGoldLine")
            if goldLine then goldLine:SetText("保留金币:+" .. finalGold .. " (总计 " .. MetaProgress.GetGold() .. ")") end

            local partsLine = uiRoot_:FindById("failurePartsLine")
            if partsLine then partsLine:SetText("零件已全部丢失.") end

            local protocolLine = uiRoot_:FindById("failureProtocolLine")
            if talentBonus > 0 then
                if protocolLine then protocolLine:SetText("天赋保险金 +" .. talentBonus) end
            else
                if protocolLine then protocolLine:SetText("") end
            end

            local statsLine = uiRoot_:FindById("failureStatsLine")
            if statsLine then
                statsLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. stats.searchedRooms ..
                    " | 触雷:" .. stats.mineHits .. " | 击败:" .. stats.monstersDefeated)
            end
        end
    end
end

function ApplyFailureSalvage(choice)
    local salvage = RunInventory.ApplyFailureSalvage(choice)
    local stats = RunInventory.GetRunStats(run)

    setVisible("failureChoicePanel", false)
    setVisible("restartAfterFailureButton", true)

    -- 天赋额外失败保底金币
    local talentBonus = MetaProgress.GetTalentEffects().failureGoldBonus
    local finalGold = salvage.gold + talentBonus

    -- 写入局外金币
    if finalGold > 0 then
        MetaProgress.AddGold(finalGold)
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
        if partsLine then partsLine:SetText("零件已全部丢失.") end

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
                " | 触雷:" .. stats.mineHits .. " | 击败:" .. stats.monstersDefeated)
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
    RunInventory.RecordCombat(result)

    local playerPower = result.playerPower or enemy.playerPower or Combat.power
    local enemyPower = result.enemyPower or enemy.power

    if result.dead then
        ShowFailurePanel("你被 " .. enemy.name .. "(战力" .. enemy.power .. ") 击败!")
    elseif result.playerWin then
        ShowMessage("击败 " .. enemy.name .. "(战力" .. enemy.power .. ")!你毫发无损.")
    else
        ShowMessage("击败 " .. enemy.name .. " 但受伤 -" .. result.damage .. " HP (剩余 " .. Combat.hp .. ")")
    end
    if not result.dead then
        -- v0.3: 标记房间已清理
        if minefield and battleState.cellX then
            minefield:ClearRoom(battleState.cellX, battleState.cellY)
        end
        if result.playerWin then
            ShowMessage("击败 " .. enemy.name .. "! 房间已清理 (我方" .. playerPower .. " vs 敌方" .. enemyPower .. ")")
        else
            ShowMessage("击败 " .. enemy.name .. ", 房间已清理, 代价 -" .. result.damage .. " HP (剩余 " .. result.hp .. ")")
        end
    end
    UpdateHUD()
end

--- 威压天赋:逃跑时间到或玩家主动战斗
function ForceFightCurrentEnemy()
    if not run then return end
    local p = run:GetPlayer()
    local enemy = Combat.GetEnemy(p.x, p.y)
    if not enemy then
        monsterFleeActive = false
        return
    end
    StartBattle(enemy, p.x, p.y)
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

        -- 威压逃跑:成功离开房间即视为逃跑成功
        if monsterFleeActive then
            monsterFleeActive = false
            monsterFleeTimer = 0
            ShowMessage("成功逃离怪物!")
        end

        -- 标记为已探索(v0.3: 通过 Minefield:Explore + Protocol 压力)
        local p = result.player
        visitedCells[tostring(p.x) .. "," .. tostring(p.y)] = true
        local firstExplore = minefield:Explore(p.x, p.y)
        if firstExplore then
            local protoResult = Protocol.AddPressure()
            if protoResult.changed then
                ShowMessage("协议降至 " .. protoResult.level .. " - " .. protoResult.description)
            end
            -- Protocol 1 惩罚: 探索未知房扣血
            if protoResult.penalty then
                Combat.hp = Combat.hp - 1
                if Combat.hp > 0 then
                    ShowMessage("临界协议! 探索未知房损失生命! (HP-1)")
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
            end
            DungeonRoom.TriggerMineFlash()
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
                -- 威压天赋:给予逃跑窗口
                local fleeBonus = talentEffects.monsterFleeBonus
                if fleeBonus > 0 then
                    -- 启动逃跑倒计时, 玩家可在窗口内离开房间
                    monsterFleeActive = true
                    monsterFleeTimer = MONSTER_FLEE_BASE + fleeBonus
                    ShowMessage("遭遇 " .. enemy.name .. "(战力" .. enemy.power .. ")!" ..
                        math.floor(monsterFleeTimer) .. "秒内可逃跑, 或按 F 战斗")
                else
                    -- 无天赋直接进入 VS 演出
                    StartBattle(enemy, p.x, p.y)
                end
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
                elseif searchState.isChest then
                    ShowMessage("发现宝箱房!按 F 开启宝箱, 奖励丰厚!")
                elseif searchState.canSearch then
                    if didExpand then
                        ShowMessage("安全区域展开!自动揭示了周围格子.按 F 搜索物资.")
                    else
                        ShowMessage("安全房间.按 F 或点击箱子搜索物资.")
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

function SearchCurrentRoom()
    if phase ~= PHASE.PLAYING then return end
    if not run then return end

    local result = RunInventory.SearchCurrentRoom(minefield, run)
    if not result.ok then
        if result.status == "searched" then
            ShowMessage("这个房间已经搜过了.")
        elseif result.status == "spawn" then
            ShowMessage("出生点没有可带走的物资.")
        elseif result.status == "exit" then
            ShowMessage("这里是撤离点, 准备好就按 E 撤离.")
        else
            ShowMessage("当前房间无法搜索.")
        end
        return
    end

    local reward = result.reward
    if reward.isChest then
        DungeonRoom.TriggerChestOpen()
    end
    -- 搜索后可能获得战斗力加成
    local p = run:GetPlayer()
    local powerUp = Combat.TryPowerUp(minefield, p.x, p.y)

    local msg = reward.isChest and ("宝箱开启! 金币 +" .. reward.gold) or ("搜索完成:金币 +" .. reward.gold)
    if reward.parts > 0 then
        msg = msg .. ", 零件 +" .. reward.parts
    end
    if powerUp > 0 then
        msg = msg .. ", 战斗力 +" .. powerUp
    end
    if reward.isChest then
        -- v0.3: 宝箱开启后标记房间已清理
        minefield:ClearRoom(p.x, p.y)
        ShowMessage(msg .. ". 稀有物资已回收!")
    else
        ShowMessage(msg .. ".")
    end

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
        partsLine:SetText("零件折算:+" .. reward.convertedGold .. " 金币 (" .. totals.parts .. " 个)")
    end

    local totalLine = uiRoot_:FindById("extractTotalLine")
    if totalLine then totalLine:SetText("本次撤离预计:+" .. reward.totalGold .. " 金币") end

    local searchLine = uiRoot_:FindById("extractSearchLine")
    if searchLine then
        searchLine:SetText("探索:" .. CountVisitedCells() .. " | 搜索:" .. totals.searchedRooms ..
            " | 触雷:" .. stats.mineHits .. " | 击败:" .. stats.monstersDefeated)
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

        -- 写入局外金币
        MetaProgress.AddGold(reward.totalGold)
        MetaProgress.RecordExtraction()

        ShowMessage("撤离成功!共获得 " .. reward.totalGold .. " 金币.")
        local confirmPanel = uiRoot_:FindById("extractConfirmPanel")
        if confirmPanel then confirmPanel:Hide() end
        local winPanel = uiRoot_:FindById("winPanel")
        if winPanel then winPanel:Show() end
        local winGoldLine = uiRoot_:FindById("winGoldLine")
        if winGoldLine then
            winGoldLine:SetText("获得金币:+" .. reward.totalGold .. " (总计 " .. MetaProgress.GetGold() .. ")")
        end

        local winConvertLine = uiRoot_:FindById("winConvertLine")
        if winConvertLine then
            if reward.parts > 0 then
                winConvertLine:SetText("局内金币 " .. reward.directGold .. " + 零件 " .. reward.parts .. " 个 -> +" .. reward.convertedGold)
            else
                winConvertLine:SetText("没有零件折算")
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
                " | 交易:" .. stats.trades)
        end
    end
end

--- 取消撤离
function CancelExtract()
    phase = PHASE.PLAYING
    local panel = uiRoot_:FindById("extractConfirmPanel")
    if panel then panel:Hide() end
end

--- 事件房交互（统一入口：旅商/骰子/祭坛/机关）
function DoTrade()
    if not run or not minefield then return end
    local p = run:GetPlayer()
    local cell = minefield:GetCellView(p.x, p.y)
    if not cell or cell.roomType ~= "event" then
        ShowMessage("这里没有可交互的事件.")
        return
    end
    if EventSystem.IsCompleted(p.x, p.y) then
        local def = EventSystem.GetEventDef(EventSystem.GetEventType(p.x, p.y))
        ShowMessage(def and def.doneMsg or "事件已完成.")
        return
    end

    -- 构建上下文
    local totals = RunInventory.GetTotals()
    local ctx = {
        gold = totals.gold,
        parts = totals.parts,
        hp = Combat.hp,
        maxHp = Combat.maxHp,
        tradePrice = MetaProgress.GetTalentEffects().tradePrice,
        power = Combat.power,
    }

    local result = EventSystem.Execute(p.x, p.y, ctx)
    if not result.ok then
        DungeonRoom.TriggerTradePulse()
        ShowMessage(result.msg)
        return
    end

    -- 应用结果
    if result.goldDelta ~= 0 then
        RunInventory.gold = RunInventory.gold + result.goldDelta
    end
    if result.partsDelta ~= 0 then
        RunInventory.parts = RunInventory.parts + result.partsDelta
        if RunInventory.parts < 0 then RunInventory.parts = 0 end
    end
    if result.hpDelta ~= 0 then
        Combat.hp = Combat.hp + result.hpDelta
        if Combat.hp < 0 then Combat.hp = 0 end
        if Combat.hp > Combat.maxHp then Combat.hp = Combat.maxHp end
    end

    -- 向后兼容 tradedRooms（HUD 状态查询可能依赖）
    local key = tostring(p.x) .. "," .. tostring(p.y)
    tradedRooms[key] = true
    RunInventory.RecordTrade()

    -- v0.3: 事件完成后标记房间已清理
    minefield:ClearRoom(p.x, p.y)
    DungeonRoom.TriggerTradePulse()
    ShowMessage(result.msg)

    -- 检查 HP 归零
    if Combat.hp <= 0 then
        ShowFailurePanel("事件导致血量归零!")
        return
    end

    UpdateHUD()
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
    -- 消息现在由 NanoVG HUD 左侧栏显示
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

function HandleNanoVGRender(eventType, eventData)
    if not nvgScene then return end

    local w = screenW / dpr
    local h = screenH / dpr

    nvgBeginFrame(nvgScene, screenW, screenH, dpr)

    if phase == PHASE.PLAYING or phase == PHASE.CONFIRM_EXTRACT or phase == PHASE.GAME_OVER or phase == PHASE.EXTRACTED then
        local hudLayout = HUD.ComputeLayout(w, h)
        local p = run:GetPlayer()
        local cell = minefield and minefield:GetCellView(p.x, p.y) or nil

        -- 预计算共用数据
        local visMap = minefield and minefield:GetVisibleMap() or nil
        local combatStatus = Combat.GetStatus()
        local invTotals = RunInventory.GetTotals()
        local invStatus = { gold = invTotals.gold, parts = invTotals.parts }

        -- 中央游戏区(带偏移和裁剪)
        local c = hudLayout.center
        nvgSave(nvgScene)
        nvgScissor(nvgScene, c.x, c.y, c.w, c.h)
        nvgTranslate(nvgScene, c.x, c.y)
        DungeonRoom.Draw(nvgScene, c.w, c.h, {
            run = run,
            minefield = minefield,
            searchState = GetSearchState(),
            enemy = Combat.GetEnemyAny(p.x, p.y),
            combat = combatStatus,
            eventTraded = EventSystem.IsCompleted(p.x, p.y),
            eventType = (cell and cell.roomType == "event") and EventSystem.GetEventType(p.x, p.y) or nil,
            inventory = invStatus,
            tradePrice = MetaProgress.GetTalentEffects().tradePrice,
            monsterFleeActive = monsterFleeActive,
            monsterFleeTimer = monsterFleeTimer,
        })
        nvgRestore(nvgScene)

        -- HUD: 左侧信息栏
        local exploredCount = Protocol.exploredRooms or 0

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
        })

        -- HUD: 右上协议面板
        local dt = 1.0 / 60.0
        HUD.DrawProtocolPanel(nvgScene, hudLayout, Protocol.GetStatus(), dt)

        -- HUD: 底部交互栏
        local roomType = cell and cell.roomType or "normal"
        local enemy = Combat.GetEnemyAny(p.x, p.y)
        local eventCompleted = EventSystem.IsCompleted(p.x, p.y)
        local interactHint = HUD.GetInteractHint({
            roomType = roomType,
            searchState = GetSearchState(),
            hasEnemy = enemy ~= nil,
            enemyAlive = enemy and enemy.alive or false,
            enemyPower = enemy and enemy.power or nil,
            playerPower = combatStatus.power,
            hasExit = cell and cell.exitId ~= nil,
            canTrade = roomType == "event" and not eventCompleted,
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
        })

        -- VS 战斗演出叠加层
        if battleState.active then
            DrawBattleOverlay(nvgScene, w, h)
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
                width = "85%",
                maxWidth = 380,
                padding = 32,
                gap = 16,
                backgroundColor = { 20, 25, 40, 240 },
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 60, 80, 120, 120 },
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "扫雷搜打撤",
                        fontSize = 26,
                        fontColor = { 255, 240, 180, 255 },
                    },
                    UI.Label {
                        text = "扫雷情报驱动的撤离地牢",
                        fontSize = 12,
                        fontColor = { 140, 150, 170, 200 },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        marginTop = 4,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "menuGoldLabel",
                                text = "金币: 0",
                                fontSize = 14,
                                fontColor = { 255, 220, 80, 255 },
                            },
                        }
                    },
                    UI.Panel {
                        id = "menuEquippedInfo",
                        marginTop = 2,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "menuEquippedLabel",
                                text = "装备: 无",
                                fontSize = 12,
                                fontColor = { 160, 200, 255, 200 },
                            },
                        }
                    },
                    UI.Button {
                        text = "出发探索",
                        variant = "primary",
                        width = 180,
                        marginTop = 8,
                        onClick = function()
                            StartNewGame()
                        end,
                    },
                    UI.Button {
                        text = "评审演示",
                        width = 180,
                        onClick = function()
                            StartJudgeDemo()
                        end,
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 12,
                        marginTop = 4,
                        children = {
                            UI.Button {
                                text = "装备",
                                width = 90,
                                onClick = function()
                                    ShowMenuPage("equip")
                                end,
                            },
                            UI.Button {
                                text = "天赋",
                                width = 90,
                                onClick = function()
                                    ShowMenuPage("talent")
                                end,
                            },
                        }
                    },
                    UI.Label {
                        id = "menuStatsLabel",
                        text = "",
                        fontSize = 11,
                        fontColor = { 120, 130, 150, 180 },
                        marginTop = 6,
                    },
                    UI.Button {
                        text = "🔧 GM",
                        width = 60,
                        height = 24,
                        marginTop = 4,
                        onClick = function()
                            ShowMenuPage("gm")
                        end,
                    },
                }
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
                            ShowMenuPage("main")
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
                    UI.Button {
                        text = "返回",
                        width = 100,
                        marginTop = 8,
                        onClick = function()
                            ShowMenuPage("main")
                        end,
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
                    UI.Button {
                        text = "返回",
                        width = 100,
                        marginTop = 8,
                        onClick = function()
                            ShowMenuPage("main")
                        end,
                    },
                }
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
    dpr = graphics:GetDPR()

    local dt = eventData["TimeStep"]:GetFloat()
    if blockedWallHintTimer > 0 then
        blockedWallHintTimer = blockedWallHintTimer - dt
    end
    DungeonRoom.Update(dt)
    MiniMap.Update(dt)

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

    -- 威压天赋逃跑倒计时
    if monsterFleeActive and monsterFleeTimer > 0 then
        monsterFleeTimer = monsterFleeTimer - dt
        if monsterFleeTimer <= 0 then
            -- 时间到, 强制战斗
            monsterFleeActive = false
            monsterFleeTimer = 0
            ForceFightCurrentEnemy()
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

    -- 功能键(移动已改为 Update 中连续检测)
    if key == KEY_W or key == KEY_UP or key == KEY_S or key == KEY_DOWN
       or key == KEY_A or key == KEY_LEFT or key == KEY_D or key == KEY_RIGHT then
        return
    elseif key == KEY_E then
        DoExtract()
    elseif key == KEY_F then
        -- 威压逃跑窗口中:F 键主动战斗
        if monsterFleeActive then
            monsterFleeActive = false
            monsterFleeTimer = 0
            ForceFightCurrentEnemy()
        else
            SearchCurrentRoom()
        end
    elseif key == KEY_T then
        DoTrade()
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
