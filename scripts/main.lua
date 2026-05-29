-- ============================================================================
-- 《第五天：灯塔》— 2026 TapTap GameJam
-- 主题：「五四三二一」
-- 2D 像素风五日场景解谜游戏
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local GameState = require("systems.GameState")
local ButtonSystem = require("systems.ButtonSystem")
local DayManager = require("systems.DayManager")
local Lighthouse = require("scenes.Lighthouse")

-- NanoVG 上下文（由 UI.Init 创建后获取）
local vg = nil

-- UI 引用
local uiRoot_ = nil
local infoPanel_ = nil
local buttonBar_ = nil

-- 场景绘制区域
local sceneRect = { x = 0, y = 0, w = 0, h = 0 }

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    -- 初始化游戏状态
    GameState.Init()

    -- 初始化 UI 系统
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 获取 NanoVG 上下文（UI 系统创建的）
    vg = UI.GetNVGContext()

    -- 初始化场景
    Lighthouse.Init()

    -- 创建 UI
    CreateUI()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== 《第五天：灯塔》已启动 ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function CreateUI()
    -- 顶部状态栏
    local topBar = UI.Panel {
        id = "topBar",
        width = "100%",
        height = 48,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 16,
        paddingRight = 16,
        backgroundColor = { 15, 15, 25, 220 },
        children = {
            UI.Label {
                id = "dayLabel",
                text = "第 1 天 / 5",
                fontSize = 16,
                fontColor = { 255, 255, 255, 255 },
            },
            UI.Label {
                id = "objectiveLabel",
                text = "目标：点亮灯塔",
                fontSize = 14,
                fontColor = { 200, 200, 100, 255 },
            },
            UI.Button {
                id = "resetBtn",
                text = "重置当天",
                variant = "outline",
                size = "sm",
                onClick = function()
                    if GameState.phase == GameState.PHASE.PLAYING then
                        GameState.ResetCurrentDay()
                        Lighthouse.selectedButton = nil
                        UpdateInfoPanel("当天状态已重置。")
                    end
                end,
            },
        }
    }

    -- NanoVG 场景画布（占中间区域）
    local sceneCanvas = UI.NanoVGCanvas {
        id = "sceneCanvas",
        width = "100%",
        flexGrow = 1,
        onDraw = function(self, ctx, x, y, w, h)
            sceneRect.x = x
            sceneRect.y = y
            sceneRect.w = w
            sceneRect.h = h
            Lighthouse.Draw(ctx, x, y, w, h)
        end,
    }

    -- 底部按钮栏
    buttonBar_ = CreateButtonBar()

    -- 信息面板
    infoPanel_ = UI.Panel {
        id = "infoPanel",
        width = "100%",
        height = 80,
        padding = 10,
        backgroundColor = { 10, 15, 25, 230 },
        borderTopWidth = 1,
        borderColor = { 60, 80, 120, 150 },
        children = {
            UI.Label {
                id = "infoText",
                text = "选择一个按钮，然后点击场景中的组件来操作。",
                fontSize = 13,
                fontColor = { 180, 200, 220, 255 },
                numberOfLines = 3,
            },
        }
    }

    -- 开始菜单覆盖层
    local menuOverlay = UI.Panel {
        id = "menuOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 360,
                padding = 32,
                gap = 16,
                backgroundColor = { 20, 25, 40, 240 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 80, 100, 140, 100 },
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "第五天：灯塔",
                        fontSize = 22,
                        fontColor = { 255, 240, 180, 255 },
                    },
                    UI.Label {
                        text = "你有五个按钮维护一座灯塔。\n每天失去一个按钮。\n第五天，你只剩一个按钮，\n面对自己留下的世界。",
                        fontSize = 13,
                        fontColor = { 180, 180, 200, 220 },
                        textAlign = "center",
                        numberOfLines = 5,
                    },
                    UI.Button {
                        text = "开始",
                        variant = "primary",
                        width = 120,
                        onClick = function()
                            GameState.phase = GameState.PHASE.PLAYING
                            DayManager.StartDay()
                            local overlay = uiRoot_:FindById("menuOverlay")
                            if overlay then overlay:Hide() end
                            UpdateDayUI()
                        end,
                    },
                }
            }
        }
    }

    -- 结局覆盖层（初始隐藏）
    local endingOverlay = UI.Panel {
        id = "endingOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 200 },
        visible = false,
        children = {
            UI.Panel {
                id = "endingContent",
                width = "85%",
                maxWidth = 380,
                padding = 32,
                gap = 16,
                backgroundColor = { 15, 15, 25, 240 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 80, 60, 100 },
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "endingTitle",
                        text = "",
                        fontSize = 20,
                        fontColor = { 255, 220, 140, 255 },
                    },
                    UI.Label {
                        id = "endingDesc",
                        text = "",
                        fontSize = 14,
                        fontColor = { 200, 200, 210, 230 },
                        textAlign = "center",
                        numberOfLines = 6,
                    },
                    UI.Button {
                        text = "重新开始",
                        variant = "outline",
                        onClick = function()
                            GameState.Init()
                            GameState.phase = GameState.PHASE.MENU
                            local overlay = uiRoot_:FindById("endingOverlay")
                            if overlay then overlay:Hide() end
                            local menu = uiRoot_:FindById("menuOverlay")
                            if menu then menu:Show() end
                        end,
                    },
                }
            }
        }
    }

    -- 删除按钮选择覆盖层（初始隐藏）
    local deleteOverlay = UI.Panel {
        id = "deleteOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        visible = false,
        children = {
            UI.Panel {
                id = "deleteContent",
                width = "85%",
                maxWidth = 380,
                padding = 24,
                gap = 12,
                backgroundColor = { 25, 20, 30, 240 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 140, 80, 80, 100 },
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "deleteTitle",
                        text = "选择要永久删除的按钮",
                        fontSize = 16,
                        fontColor = { 255, 180, 180, 255 },
                    },
                    UI.Label {
                        id = "deleteForecast",
                        text = "",
                        fontSize = 12,
                        fontColor = { 180, 180, 200, 200 },
                        numberOfLines = 5,
                    },
                    UI.Panel {
                        id = "deleteButtons",
                        flexDirection = "row",
                        gap = 8,
                        flexWrap = "wrap",
                        justifyContent = "center",
                    },
                    UI.Button {
                        id = "deleteCancel",
                        text = "返回检查场景",
                        variant = "outline",
                        size = "sm",
                        onClick = function()
                            GameState.phase = GameState.PHASE.PLAYING
                            local overlay = uiRoot_:FindById("deleteOverlay")
                            if overlay then overlay:Hide() end
                        end,
                    },
                }
            }
        }
    }

    -- 组合 UI 树
    uiRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        children = {
            topBar,
            sceneCanvas,
            buttonBar_,
            infoPanel_,
            -- 覆盖层
            menuOverlay,
            endingOverlay,
            deleteOverlay,
        }
    }

    UI.SetRoot(uiRoot_)
end

--- 创建底部按钮栏
function CreateButtonBar()
    local buttons = {}
    for _, btn in ipairs(GameState.BUTTONS) do
        table.insert(buttons, UI.Button {
            id = "btn_" .. btn.id,
            text = btn.name,
            width = 52,
            height = 52,
            fontSize = 18,
            borderRadius = 8,
            backgroundColor = { btn.color[1], btn.color[2], btn.color[3], 220 },
            fontColor = { 255, 255, 255, 255 },
            onClick = function()
                OnButtonSelect(btn.id)
            end,
        })
    end

    return UI.Panel {
        id = "buttonBar",
        width = "100%",
        height = 64,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 10,
        paddingLeft = 8,
        paddingRight = 8,
        backgroundColor = { 20, 20, 35, 230 },
        borderTopWidth = 1,
        borderColor = { 60, 60, 90, 150 },
        children = buttons,
    }
end

-- ============================================================================
-- 交互逻辑
-- ============================================================================

--- 选择按钮
function OnButtonSelect(buttonId)
    if GameState.phase ~= GameState.PHASE.PLAYING then return end

    if not GameState.availableButtons[buttonId] then
        UpdateInfoPanel("该按钮已被删除。")
        return
    end

    Lighthouse.selectedButton = buttonId

    -- 显示该按钮可操作的组件
    local actions = ButtonSystem.GetAvailableActions(buttonId)
    if #actions == 0 then
        UpdateInfoPanel("【" .. buttonId .. "】当前没有可操作的组件。")
        Lighthouse.selectedButton = nil
        return
    end

    local text = "【" .. GetButtonName(buttonId) .. "】请点击目标组件：\n"
    for _, a in ipairs(actions) do
        text = text .. "  · " .. a.componentName .. " → " .. a.result .. "\n"
    end
    UpdateInfoPanel(text)
end

--- 点击场景组件
function OnComponentClick(componentId)
    if GameState.phase ~= GameState.PHASE.PLAYING then return end
    if not Lighthouse.selectedButton then
        UpdateInfoPanel("请先选择一个按钮。")
        return
    end

    local success = ButtonSystem.Execute(Lighthouse.selectedButton, componentId)
    if success then
        Lighthouse.selectedButton = nil
        -- 检查目标
        if GameState.CheckObjective() then
            UpdateInfoPanel("目标完成！按 [结束当天] 进入下一天。\n（或继续操作调整状态）")
            ShowEndDayButton()
        end
    end
    UpdateDayUI()
end

--- 显示"结束当天"按钮
function ShowEndDayButton()
    -- 在 info panel 旁边添加一个结束当天按钮
    local existing = uiRoot_:FindById("endDayBtn")
    if not existing then
        local btn = UI.Button {
            id = "endDayBtn",
            text = "结束当天",
            variant = "primary",
            size = "sm",
            position = "absolute",
            bottom = 92,
            right = 16,
            onClick = function()
                if GameState.day >= GameState.maxDay then
                    -- 最后一天直接结局
                    ShowEnding()
                else
                    ShowDeleteOverlay()
                end
            end,
        }
        uiRoot_:AddChild(btn)
    end
end

--- 显示删除按钮面板
function ShowDeleteOverlay()
    GameState.phase = GameState.PHASE.DELETE_CHOOSE
    local overlay = uiRoot_:FindById("deleteOverlay")
    if overlay then overlay:Show() end

    -- 动态生成可删除按钮列表
    local container = uiRoot_:FindById("deleteButtons")
    if container then
        container:RemoveAllChildren()
        local available = GameState.GetAvailableButtons()
        for _, btn in ipairs(available) do
            container:AddChild(UI.Button {
                text = btn.name .. " (" .. btn.id .. ")",
                size = "sm",
                backgroundColor = { btn.color[1], btn.color[2], btn.color[3], 200 },
                fontColor = { 255, 255, 255, 255 },
                onClick = function()
                    -- 显示删除预报
                    local forecast = ButtonSystem.GetDeleteForecast(btn.id)
                    local text = "【删除：" .. btn.name .. "】\n"
                    if #forecast.dependencies > 0 then
                        text = text .. "当前依赖：\n"
                        for _, dep in ipairs(forecast.dependencies) do
                            text = text .. "  [!] " .. dep.component .. ": " .. dep.reason .. "\n"
                        end
                    else
                        text = text .. "当前无组件依赖此按钮。\n"
                    end
                    text = text .. "⚠️ " .. forecast.warnings[1]

                    local forecastLabel = uiRoot_:FindById("deleteForecast")
                    if forecastLabel then forecastLabel:SetText(text) end

                    -- 添加确认按钮
                    local confirmBtn = uiRoot_:FindById("confirmDeleteBtn")
                    if not confirmBtn then
                        container:AddChild(UI.Button {
                            id = "confirmDeleteBtn",
                            text = "确认删除「" .. btn.name .. "」",
                            variant = "primary",
                            size = "sm",
                            backgroundColor = { 180, 50, 50, 255 },
                            onClick = function()
                                GameState.DeleteButton(btn.id)
                                GameState.AddMessage("你永久删除了「" .. btn.name .. "」按钮。")
                                local o = uiRoot_:FindById("deleteOverlay")
                                if o then o:Hide() end
                                -- 隐藏结束当天按钮
                                local edb = uiRoot_:FindById("endDayBtn")
                                if edb then edb:Hide() end
                                -- 更新按钮栏可用状态
                                UpdateButtonBarVisibility()
                                -- 进入下一天
                                DayManager.AdvanceDay()
                                if GameState.phase == GameState.PHASE.ENDING then
                                    ShowEnding()
                                else
                                    UpdateDayUI()
                                    UpdateInfoPanel("新的一天开始了。")
                                end
                            end,
                        })
                    end
                end,
            })
        end
    end
end

--- 显示结局
function ShowEnding()
    GameState.phase = GameState.PHASE.ENDING
    local ending = DayManager.GetEnding()

    local overlay = uiRoot_:FindById("endingOverlay")
    if overlay then overlay:Show() end

    local title = uiRoot_:FindById("endingTitle")
    if title then title:SetText("结局：" .. ending.title) end

    local desc = uiRoot_:FindById("endingDesc")
    if desc then desc:SetText(ending.description) end
end

-- ============================================================================
-- UI 更新
-- ============================================================================

function UpdateInfoPanel(text)
    local label = uiRoot_:FindById("infoText")
    if label then label:SetText(text) end
end

function UpdateDayUI()
    local dayLabel = uiRoot_:FindById("dayLabel")
    if dayLabel then
        dayLabel:SetText("第 " .. GameState.day .. " 天 / 5")
    end

    local objLabel = uiRoot_:FindById("objectiveLabel")
    if objLabel then
        local prefix = GameState.dayObjectiveComplete and "✓ " or "目标："
        objLabel:SetText(prefix .. GameState.dayObjective)
    end
end

function UpdateButtonBarVisibility()
    for _, btn in ipairs(GameState.BUTTONS) do
        local uiBtn = uiRoot_:FindById("btn_" .. btn.id)
        if uiBtn then
            if GameState.availableButtons[btn.id] then
                uiBtn:Show()
            else
                uiBtn:Hide()
            end
        end
    end
end

function GetButtonName(buttonId)
    for _, btn in ipairs(GameState.BUTTONS) do
        if btn.id == buttonId then return btn.name end
    end
    return buttonId
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    -- 游戏逻辑更新（如有动画等）
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    if GameState.phase ~= GameState.PHASE.PLAYING then return end

    -- 检测是否点击了场景组件
    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()

    -- 转换到场景区域坐标
    local dpr = graphics:GetDPR()
    local localX = mx / dpr - sceneRect.x
    local localY = my / dpr - sceneRect.y

    if localX >= 0 and localX <= sceneRect.w and localY >= 0 and localY <= sceneRect.h then
        local compId = Lighthouse.HitTest(localX, localY, sceneRect.w, sceneRect.h)
        if compId then
            OnComponentClick(compId)
        end
    end
end

---@param eventType string
---@param eventData MouseMoveEventData
function HandleMouseMove(eventType, eventData)
    if GameState.phase ~= GameState.PHASE.PLAYING then return end

    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()

    local dpr = graphics:GetDPR()
    local localX = mx / dpr - sceneRect.x
    local localY = my / dpr - sceneRect.y

    if localX >= 0 and localX <= sceneRect.w and localY >= 0 and localY <= sceneRect.h then
        local compId = Lighthouse.HitTest(localX, localY, sceneRect.w, sceneRect.h)
        Lighthouse.hoveredComponent = compId

        -- 显示操作预报
        if compId and Lighthouse.selectedButton then
            local action = ButtonSystem.GetAction(Lighthouse.selectedButton, compId)
            if action then
                UpdateInfoPanel("【" .. GetButtonName(Lighthouse.selectedButton) .. " → " ..
                    compId .. "】\n结果：" .. action.result .. "\n风险：" .. action.risk)
            else
                UpdateInfoPanel("「" .. GetButtonName(Lighthouse.selectedButton) .. "」无法对此组件操作。")
            end
        end
    else
        Lighthouse.hoveredComponent = nil
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        Lighthouse.selectedButton = nil
        UpdateInfoPanel("已取消选择。")
    elseif key == KEY_R then
        if GameState.phase == GameState.PHASE.PLAYING then
            GameState.ResetCurrentDay()
            Lighthouse.selectedButton = nil
            UpdateInfoPanel("当天状态已重置。")
            UpdateDayUI()
        end
    end
end
