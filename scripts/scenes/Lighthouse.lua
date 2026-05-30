-- ============================================================================
-- Lighthouse.lua — 灯塔场景绘制(NanoVG 像素风)
-- 绘制灯塔,水车,电缆,电池,村庄,海面等组件
-- ============================================================================

local GameState = require("systems.GameState")

local Lighthouse = {}

-- 场景组件位置布局(相对于画布, 百分比)
local LAYOUT = {
    lighthouse = { x = 0.5, y = 0.25, w = 0.12, h = 0.35 },
    waterwheel = { x = 0.25, y = 0.55, w = 0.12, h = 0.12 },
    cable      = { x = 0.38, y = 0.45, w = 0.24, h = 0.04 },
    battery    = { x = 0.72, y = 0.45, w = 0.08, h = 0.06 },
    village    = { x = 0.15, y = 0.72, w = 0.25, h = 0.15 },
    sea        = { x = 0.60, y = 0.72, w = 0.30, h = 0.15 },
}

-- 组件中文名称
local COMP_NAMES = {
    lighthouse = "灯塔",
    waterwheel = "水车",
    cable = "电缆",
    battery = "电池",
    village = "村庄",
    sea = "海面",
}

-- 当前高亮的组件
Lighthouse.hoveredComponent = nil
-- 当前选中的按钮(等待选择目标组件)
Lighthouse.selectedButton = nil

--- 初始化场景
function Lighthouse.Init()
    Lighthouse.hoveredComponent = nil
    Lighthouse.selectedButton = nil
end

--- 绘制整个场景
---@param vg userdata NanoVG context
---@param sceneX number 场景区域起始 X
---@param sceneY number 场景区域起始 Y
---@param sceneW number 场景区域宽度
---@param sceneH number 场景区域高度
function Lighthouse.Draw(vg, sceneX, sceneY, sceneW, sceneH)
    -- 绘制天空背景(根据天数变化)
    Lighthouse.DrawSky(vg, sceneX, sceneY, sceneW, sceneH)

    -- 绘制各组件
    Lighthouse.DrawSea(vg, sceneX, sceneY, sceneW, sceneH)
    Lighthouse.DrawVillage(vg, sceneX, sceneY, sceneW, sceneH)
    Lighthouse.DrawWaterwheel(vg, sceneX, sceneY, sceneW, sceneH)
    Lighthouse.DrawCable(vg, sceneX, sceneY, sceneW, sceneH)
    Lighthouse.DrawBattery(vg, sceneX, sceneY, sceneW, sceneH)
    Lighthouse.DrawLighthouse(vg, sceneX, sceneY, sceneW, sceneH)

    -- 绘制组件高亮
    if Lighthouse.hoveredComponent and Lighthouse.selectedButton then
        Lighthouse.DrawHighlight(vg, sceneX, sceneY, sceneW, sceneH, Lighthouse.hoveredComponent)
    end
end

--- 绘制天空
function Lighthouse.DrawSky(vg, sx, sy, sw, sh)
    local day = GameState.day
    local topColor, botColor

    if day == 1 then
        topColor = {100, 150, 220}  -- 清晨蓝
        botColor = {200, 180, 140}  -- 暖色地平线
    elseif day == 2 then
        topColor = {80, 100, 130}   -- 阴天
        botColor = {120, 120, 110}
    elseif day == 3 then
        topColor = {40, 50, 70}     -- 暴雨
        botColor = {60, 70, 80}
    elseif day == 4 then
        topColor = {15, 20, 40}     -- 夜晚
        botColor = {30, 35, 50}
    else
        topColor = {5, 5, 15}       -- 近黑白
        botColor = {20, 20, 30}
    end

    local paint = nvgLinearGradient(vg, sx, sy, sx, sy + sh,
        nvgRGBA(topColor[1], topColor[2], topColor[3], 255),
        nvgRGBA(botColor[1], botColor[2], botColor[3], 255))
    nvgBeginPath(vg)
    nvgRect(vg, sx, sy, sw, sh)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- 绘制灯塔
function Lighthouse.DrawLighthouse(vg, sx, sy, sw, sh)
    local l = LAYOUT.lighthouse
    local cx = sx + sw * l.x
    local cy = sy + sh * l.y
    local w = sw * l.w
    local h = sh * l.h

    -- 灯塔主体(梯形)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - w * 0.4, cy + h * 0.5)
    nvgLineTo(vg, cx - w * 0.25, cy - h * 0.3)
    nvgLineTo(vg, cx + w * 0.25, cy - h * 0.3)
    nvgLineTo(vg, cx + w * 0.4, cy + h * 0.5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 200, 190, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 80, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 灯塔顶部(灯室)
    local topY = cy - h * 0.3
    nvgBeginPath(vg)
    nvgRect(vg, cx - w * 0.3, topY - h * 0.15, w * 0.6, h * 0.15)
    nvgFillColor(vg, nvgRGBA(60, 60, 70, 255))
    nvgFill(vg)

    -- 灯光效果
    local state = GameState.components.lighthouse
    if state == "on" then
        -- 发光
        nvgBeginPath(vg)
        nvgCircle(vg, cx, topY - h * 0.07, w * 0.2)
        nvgFillColor(vg, nvgRGBA(255, 240, 100, 255))
        nvgFill(vg)
        -- 光晕
        nvgBeginPath(vg)
        nvgCircle(vg, cx, topY - h * 0.07, w * 0.5)
        nvgFillColor(vg, nvgRGBA(255, 240, 100, 60))
        nvgFill(vg)
    elseif state == "overload" then
        -- 过载闪烁(红色)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, topY - h * 0.07, w * 0.25)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 200))
        nvgFill(vg)
        -- 警告光晕
        nvgBeginPath(vg)
        nvgCircle(vg, cx, topY - h * 0.07, w * 0.6)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 40))
        nvgFill(vg)
    end

    -- 状态文字
    Lighthouse.DrawComponentLabel(vg, cx, cy + h * 0.55, "灯塔", state, "lighthouse")
end

--- 绘制水车
function Lighthouse.DrawWaterwheel(vg, sx, sy, sw, sh)
    local l = LAYOUT.waterwheel
    local cx = sx + sw * l.x
    local cy = sy + sh * l.y
    local r = sw * l.w * 0.4

    local state = GameState.components.waterwheel

    -- 水车圆形
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    nvgFillColor(vg, nvgRGBA(120, 90, 60, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 60, 40, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 叶片
    local bladeColor = state == "stopped" and nvgRGBA(100, 80, 60, 200) or nvgRGBA(180, 140, 80, 255)
    for i = 0, 3 do
        local angle = i * math.pi / 2
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy)
        nvgLineTo(vg, cx + math.cos(angle) * r * 0.9, cy + math.sin(angle) * r * 0.9)
        nvgStrokeColor(vg, bladeColor)
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

    -- 方向指示
    if state == "forward" then
        Lighthouse.DrawComponentLabel(vg, cx, cy + r + 14, "水车", "正转", "waterwheel")
    elseif state == "reverse" then
        Lighthouse.DrawComponentLabel(vg, cx, cy + r + 14, "水车", "反转", "waterwheel")
    else
        Lighthouse.DrawComponentLabel(vg, cx, cy + r + 14, "水车", "停止", "waterwheel")
    end
end

--- 绘制电缆
function Lighthouse.DrawCable(vg, sx, sy, sw, sh)
    local l = LAYOUT.cable
    local x1 = sx + sw * l.x
    local y1 = sy + sh * l.y
    local x2 = x1 + sw * l.w

    local state = GameState.components.cable
    local color
    if state == "main" then
        color = nvgRGBA(60, 200, 60, 255)
    elseif state == "backup" then
        color = nvgRGBA(60, 150, 220, 255)
    elseif state == "broken" then
        color = nvgRGBA(200, 60, 60, 255)
    else
        color = nvgRGBA(100, 100, 100, 150)
    end

    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y1)
    nvgStrokeColor(vg, color)
    nvgStrokeWidth(vg, state == "disconnected" and 2 or 4)
    if state == "broken" then
        nvgLineCap(vg, NVG_BUTT)
        -- 画断点
        local midX = (x1 + x2) / 2
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, midX - 8, y1)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, midX + 8, y1)
        nvgLineTo(vg, x2, y1)
        nvgStroke(vg)
    else
        nvgStroke(vg)
    end

    Lighthouse.DrawComponentLabel(vg, (x1 + x2) / 2, y1 + 16, "电缆", state, "cable")
end

--- 绘制电池
function Lighthouse.DrawBattery(vg, sx, sy, sw, sh)
    local l = LAYOUT.battery
    local cx = sx + sw * l.x
    local cy = sy + sh * l.y
    local w = sw * l.w
    local h = sh * l.h

    local state = GameState.components.battery

    -- 电池外框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - w / 2, cy - h / 2, w, h, 3)
    nvgStrokeColor(vg, nvgRGBA(180, 180, 180, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 电量填充
    local fillColor
    local fillRatio = 0
    if state == "full" then
        fillColor = nvgRGBA(60, 200, 60, 255)
        fillRatio = 0.85
    elseif state == "empty" then
        fillColor = nvgRGBA(200, 60, 60, 255)
        fillRatio = 0.1
    else -- broken
        fillColor = nvgRGBA(100, 100, 100, 255)
        fillRatio = 0
    end

    if fillRatio > 0 then
        nvgBeginPath(vg)
        local fillW = (w - 4) * fillRatio
        nvgRect(vg, cx - w / 2 + 2, cy - h / 2 + 2, fillW, h - 4)
        nvgFillColor(vg, fillColor)
        nvgFill(vg)
    end

    -- 电池正极头
    nvgBeginPath(vg)
    nvgRect(vg, cx + w / 2, cy - h * 0.2, w * 0.15, h * 0.4)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
    nvgFill(vg)

    Lighthouse.DrawComponentLabel(vg, cx, cy + h / 2 + 14, "电池", state, "battery")
end

--- 绘制村庄
function Lighthouse.DrawVillage(vg, sx, sy, sw, sh)
    local l = LAYOUT.village
    local x = sx + sw * l.x
    local y = sy + sh * l.y
    local w = sw * l.w
    local h = sh * l.h

    local state = GameState.components.village

    -- 地面
    nvgBeginPath(vg)
    nvgRect(vg, x, y + h * 0.6, w, h * 0.4)
    nvgFillColor(vg, nvgRGBA(60, 100, 40, 255))
    nvgFill(vg)

    -- 房屋(3个小方块)
    for i = 0, 2 do
        local hx = x + w * 0.15 + i * w * 0.3
        local hy = y + h * 0.3
        local hw = w * 0.2
        local hh = h * 0.35

        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, hw, hh)
        nvgFillColor(vg, nvgRGBA(160, 130, 100, 255))
        nvgFill(vg)

        -- 屋顶
        nvgBeginPath(vg)
        nvgMoveTo(vg, hx - 2, hy)
        nvgLineTo(vg, hx + hw / 2, hy - hh * 0.4)
        nvgLineTo(vg, hx + hw + 2, hy)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(140, 60, 40, 255))
        nvgFill(vg)

        -- 窗户灯光
        if state == "safe" then
            nvgBeginPath(vg)
            nvgRect(vg, hx + hw * 0.3, hy + hh * 0.3, hw * 0.4, hh * 0.3)
            nvgFillColor(vg, nvgRGBA(255, 220, 100, 200))
            nvgFill(vg)
        elseif state == "burning" then
            -- 火焰效果
            nvgBeginPath(vg)
            nvgRect(vg, hx, hy - 5, hw, hh + 5)
            nvgFillColor(vg, nvgRGBA(255, 100, 30, 150))
            nvgFill(vg)
        end
    end

    Lighthouse.DrawComponentLabel(vg, x + w / 2, y + h + 14, "村庄", state, "village")
end

--- 绘制海面
function Lighthouse.DrawSea(vg, sx, sy, sw, sh)
    local l = LAYOUT.sea
    local x = sx + sw * l.x
    local y = sy + sh * l.y
    local w = sw * l.w
    local h = sh * l.h

    local state = GameState.components.sea

    -- 海面
    local seaColor
    if state == "calm" then
        seaColor = nvgRGBA(40, 100, 160, 200)
    elseif state == "storm" then
        seaColor = nvgRGBA(30, 60, 100, 220)
    else -- lost
        seaColor = nvgRGBA(20, 40, 70, 240)
    end

    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, seaColor)
    nvgFill(vg)

    -- 波浪线
    nvgBeginPath(vg)
    for i = 0, 5 do
        local wx = x + i * w / 5
        local wy = y + h * 0.3 + math.sin(i * 1.5) * 4
        if i == 0 then
            nvgMoveTo(vg, wx, wy)
        else
            nvgLineTo(vg, wx, wy)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(100, 180, 220, 150))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 船只
    if state == "storm" or state == "lost" then
        local bx = x + w * 0.6
        local by = y + h * 0.5
        nvgBeginPath(vg)
        nvgMoveTo(vg, bx - 10, by)
        nvgLineTo(vg, bx + 10, by)
        nvgLineTo(vg, bx + 7, by + 6)
        nvgLineTo(vg, bx - 7, by + 6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(160, 120, 80, 255))
        nvgFill(vg)
        -- 桅杆
        nvgBeginPath(vg)
        nvgMoveTo(vg, bx, by)
        nvgLineTo(vg, bx, by - 12)
        nvgStrokeColor(vg, nvgRGBA(140, 100, 60, 255))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    Lighthouse.DrawComponentLabel(vg, x + w / 2, y + h + 14, "海面", state, "sea")
end

--- 绘制组件标签
function Lighthouse.DrawComponentLabel(vg, x, y, name, state, compId)
    local isHovered = (Lighthouse.hoveredComponent == compId)
    local isTarget = (Lighthouse.selectedButton ~= nil)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    if isHovered and isTarget then
        nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
    else
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 200))
    end
    nvgText(vg, x, y, name .. ":" .. tostring(state))
end

--- 绘制组件高亮框
function Lighthouse.DrawHighlight(vg, sx, sy, sw, sh, compId)
    local l = LAYOUT[compId]
    if not l then return end

    local x = sx + sw * (l.x - l.w / 2)
    local y = sy + sh * (l.y - l.h / 2)
    local w = sw * l.w
    local h = sh * l.h

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 4, y - 4, w + 8, h + 8, 4)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 100, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

--- 根据屏幕坐标判断点击了哪个组件
---@param mx number 鼠标 X(相对场景区域)
---@param my number 鼠标 Y(相对场景区域)
---@param sceneW number 场景宽
---@param sceneH number 场景高
---@return string|nil 组件 ID
function Lighthouse.HitTest(mx, my, sceneW, sceneH)
    for compId, l in pairs(LAYOUT) do
        local cx = sceneW * l.x
        local cy = sceneH * l.y
        local hw = sceneW * l.w / 2
        local hh = sceneH * l.h / 2

        if mx >= cx - hw - 10 and mx <= cx + hw + 10 and
           my >= cy - hh - 10 and my <= cy + hh + 10 then
            return compId
        end
    end
    return nil
end

return Lighthouse
