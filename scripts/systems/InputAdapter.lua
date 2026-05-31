-- ============================================================================
-- InputAdapter.lua
-- 统一输入适配层：自动检测平台，PC 用键盘/鼠标，手机用虚拟摇杆+按钮+陀螺仪
-- ============================================================================

local ok_pu, PlatformUtils = pcall(require, "urhox-libs.Platform.PlatformUtils")
if not ok_pu then
    print("WARN: PlatformUtils not available, using fallback detection")
    PlatformUtils = {
        IsMobilePlatform = function()
            -- 简易回退检测：有触摸但无鼠标即为手机
            return input.numTouches > 0 or (input.touchEmulation == true)
        end
    }
end

---@class InputAdapter
local InputAdapter = {}

-- ============================================================================
-- 配置
-- ============================================================================

InputAdapter.config = {
    -- 陀螺仪
    gyroscopeEnabled = false,
    gyroscopeThreshold = 0.15,    -- 死区阈值
    gyroscopeSensitivity = 1.0,   -- 灵敏度倍率

    -- 虚拟摇杆
    joystickRadius = 60,          -- 摇杆外圈半径
    joystickKnobRadius = 22,      -- 摇杆内圈半径
    joystickDeadZone = 0.2,       -- 摇杆死区

    -- 按钮尺寸
    buttonRadius = 28,            -- 功能按钮半径
    buttonGap = 14,               -- 按钮间距
}

-- ============================================================================
-- 状态
-- ============================================================================

local isMobile = false
local isInitialized = false

-- 虚拟摇杆状态
local joystick = {
    active = false,         -- 是否正在触摸
    touchID = -1,           -- 绑定的 touchID
    centerX = 0,            -- 摇杆中心 X (逻辑坐标)
    centerY = 0,            -- 摇杆中心 Y (逻辑坐标)
    knobX = 0,              -- 旋钮当前 X
    knobY = 0,              -- 旋钮当前 Y
    dx = 0,                 -- 归一化方向 -1..+1
    dy = 0,                 -- 归一化方向 -1..+1
    baseX = 0,              -- 固定位置 X
    baseY = 0,              -- 固定位置 Y
}

-- 功能按钮定义
local ACTION_BUTTONS = {
    { id = "attack",  label = "攻击",   key = "F", color = { 220, 80, 60 } },
    { id = "extract", label = "撤离",   key = "E", color = { 80, 200, 120 } },
    { id = "heal",    label = "止血",   key = "Q", color = { 100, 180, 255 } },
    { id = "map",     label = "地图",   key = "M", color = { 200, 180, 80 } },
    { id = "trade",   label = "交互",   key = "T", color = { 180, 140, 220 } },
}

-- 按钮状态
local buttons = {}
for _, def in ipairs(ACTION_BUTTONS) do
    buttons[def.id] = {
        def = def,
        x = 0, y = 0,
        pressed = false,
        justPressed = false,    -- 本帧刚按下
        touchID = -1,
    }
end

-- 陀螺仪状态
local gyro = {
    tiltX = 0,   -- 左右倾斜 -1..+1
    tiltY = 0,   -- 前后倾斜 -1..+1
    dx = 0,
    dy = 0,
}

-- 输出：本帧的移动方向
InputAdapter.moveX = 0      -- -1, 0, +1
InputAdapter.moveY = 0      -- -1, 0, +1
InputAdapter.moveDX = 0     -- 模拟量 (用于平滑移动)
InputAdapter.moveDY = 0

-- 输出：本帧按下的动作
InputAdapter.actions = {}   -- { attack = false, extract = false, heal = false, map = false, trade = false }

-- ============================================================================
-- 初始化
-- ============================================================================

function InputAdapter.Initialize()
    if isInitialized then return end
    isInitialized = true

    isMobile = PlatformUtils.IsMobilePlatform()

    -- 重置动作状态
    for _, def in ipairs(ACTION_BUTTONS) do
        InputAdapter.actions[def.id] = false
    end

    if isMobile then
        -- 订阅触摸事件
        SubscribeToEvent("TouchBegin", "InputAdapter_HandleTouchBegin")
        SubscribeToEvent("TouchMove", "InputAdapter_HandleTouchMove")
        SubscribeToEvent("TouchEnd", "InputAdapter_HandleTouchEnd")
    end
end

function InputAdapter.IsMobile()
    return isMobile
end

function InputAdapter.SetGyroscopeEnabled(enabled)
    InputAdapter.config.gyroscopeEnabled = enabled
end

function InputAdapter.IsGyroscopeEnabled()
    return InputAdapter.config.gyroscopeEnabled
end

-- ============================================================================
-- 布局计算 (每帧/屏幕尺寸变化时调用)
-- ============================================================================

--- 根据逻辑屏幕尺寸计算虚拟控件位置
---@param logicalW number 逻辑宽度
---@param logicalH number 逻辑高度
function InputAdapter.ComputeLayout(logicalW, logicalH)
    local cfg = InputAdapter.config
    local pad = 30

    -- 虚拟摇杆：左下角
    joystick.baseX = pad + cfg.joystickRadius + 20
    joystick.baseY = logicalH - pad - cfg.joystickRadius - 20
    joystick.centerX = joystick.baseX
    joystick.centerY = joystick.baseY
    joystick.knobX = joystick.centerX
    joystick.knobY = joystick.centerY

    -- 功能按钮：右下角，弧形排列
    local btnCount = #ACTION_BUTTONS
    local arcCenterX = logicalW - pad - cfg.buttonRadius - 30
    local arcCenterY = logicalH - pad - cfg.buttonRadius - 30
    local arcRadius = cfg.buttonRadius * 2 + cfg.buttonGap

    -- 主按钮(攻击)在最右下，其他按钮弧形环绕
    buttons["attack"].x = arcCenterX
    buttons["attack"].y = arcCenterY

    -- 其他按钮以扇形排列在攻击按钮周围
    local otherButtons = { "extract", "heal", "map", "trade" }
    local startAngle = math.pi * 0.6   -- 从左上方开始
    local arcSpan = math.pi * 0.8       -- 扇形角度范围
    for i, id in ipairs(otherButtons) do
        local angle = startAngle + (i - 1) * (arcSpan / (#otherButtons - 1))
        buttons[id].x = arcCenterX - math.cos(angle) * arcRadius
        buttons[id].y = arcCenterY - math.sin(angle) * arcRadius
    end
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

--- 每帧调用，更新输入状态
---@param dt number
function InputAdapter.Update(dt)
    -- 重置本帧动作
    for _, def in ipairs(ACTION_BUTTONS) do
        InputAdapter.actions[def.id] = buttons[def.id].justPressed
        buttons[def.id].justPressed = false
    end

    if isMobile then
        -- 从虚拟摇杆读取移动方向
        local cfg = InputAdapter.config
        local dx, dy = 0, 0

        if joystick.active then
            dx = joystick.dx
            dy = joystick.dy
        end

        -- 叠加陀螺仪
        if cfg.gyroscopeEnabled then
            InputAdapter._UpdateGyroscope()
            if math.abs(gyro.dx) > 0 or math.abs(gyro.dy) > 0 then
                dx = dx + gyro.dx
                dy = dy + gyro.dy
                -- 钳制到 -1..+1
                dx = math.max(-1, math.min(1, dx))
                dy = math.max(-1, math.min(1, dy))
            end
        end

        InputAdapter.moveDX = dx
        InputAdapter.moveDY = dy

        -- 量化为离散方向 (阈值 0.3)
        local threshold = 0.3
        if math.abs(dx) > math.abs(dy) then
            InputAdapter.moveX = dx > threshold and 1 or (dx < -threshold and -1 or 0)
            InputAdapter.moveY = 0
        else
            InputAdapter.moveX = 0
            InputAdapter.moveY = dy > threshold and 1 or (dy < -threshold and -1 or 0)
        end
    else
        -- PC: 直接读键盘 (与原来 HandleUpdate 中逻辑一致)
        local dx, dy = 0, 0
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then dy = -1
        elseif input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then dy = 1
        end
        if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then dx = -1
        elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then dx = 1
        end

        InputAdapter.moveX = dx
        InputAdapter.moveY = dy
        InputAdapter.moveDX = dx
        InputAdapter.moveDY = dy

        -- PC 按键动作由 HandleKeyDown 处理，这里不重复
    end
end

-- ============================================================================
-- 陀螺仪
-- ============================================================================

function InputAdapter._UpdateGyroscope()
    local cfg = InputAdapter.config
    gyro.dx = 0
    gyro.dy = 0

    if input.numJoysticks > 0 then
        local joy = input:GetJoystickByIndex(0)
        if joy and joy.numAxes >= 2 then
            local tiltX = joy:GetAxisPosition(0)  -- 左右倾斜
            local tiltY = joy:GetAxisPosition(1)  -- 前后倾斜

            gyro.tiltX = tiltX
            gyro.tiltY = tiltY

            -- 应用死区和灵敏度
            if math.abs(tiltX) > cfg.gyroscopeThreshold then
                gyro.dx = (tiltX - cfg.gyroscopeThreshold * (tiltX > 0 and 1 or -1))
                    / (1 - cfg.gyroscopeThreshold) * cfg.gyroscopeSensitivity
            end
            if math.abs(tiltY) > cfg.gyroscopeThreshold then
                gyro.dy = (tiltY - cfg.gyroscopeThreshold * (tiltY > 0 and 1 or -1))
                    / (1 - cfg.gyroscopeThreshold) * cfg.gyroscopeSensitivity
            end
        end
    end
end

-- ============================================================================
-- 触摸事件处理
-- ============================================================================

---@param eventType string
---@param eventData TouchBeginEventData
function InputAdapter_HandleTouchBegin(eventType, eventData)
    local touchID = eventData:GetInt("TouchID")
    local x = eventData:GetInt("X")
    local y = eventData:GetInt("Y")
    local dpr = graphics:GetDPR()
    if dpr <= 0 then dpr = 1 end
    local lx = x / dpr
    local ly = y / dpr

    -- 检查是否命中功能按钮
    local cfg = InputAdapter.config
    for _, def in ipairs(ACTION_BUTTONS) do
        local btn = buttons[def.id]
        local dist = math.sqrt((lx - btn.x) ^ 2 + (ly - btn.y) ^ 2)
        if dist <= cfg.buttonRadius * 1.3 then  -- 放大点击区域
            btn.pressed = true
            btn.justPressed = true
            btn.touchID = touchID
            return
        end
    end

    -- 检查是否在左半屏（摇杆区域）
    local screenW = graphics:GetWidth() / dpr
    if lx < screenW * 0.45 and not joystick.active then
        joystick.active = true
        joystick.touchID = touchID
        -- 动态定位：以触摸点为中心
        joystick.centerX = lx
        joystick.centerY = ly
        joystick.knobX = lx
        joystick.knobY = ly
        joystick.dx = 0
        joystick.dy = 0
    end
end

---@param eventType string
---@param eventData TouchMoveEventData
function InputAdapter_HandleTouchMove(eventType, eventData)
    local touchID = eventData:GetInt("TouchID")
    local x = eventData:GetInt("X")
    local y = eventData:GetInt("Y")
    local dpr = graphics:GetDPR()
    if dpr <= 0 then dpr = 1 end
    local lx = x / dpr
    local ly = y / dpr

    -- 更新摇杆
    if joystick.active and joystick.touchID == touchID then
        local cfg = InputAdapter.config
        local diffX = lx - joystick.centerX
        local diffY = ly - joystick.centerY
        local dist = math.sqrt(diffX * diffX + diffY * diffY)

        if dist > cfg.joystickRadius then
            -- 限制在圆内
            diffX = diffX / dist * cfg.joystickRadius
            diffY = diffY / dist * cfg.joystickRadius
            dist = cfg.joystickRadius
        end

        joystick.knobX = joystick.centerX + diffX
        joystick.knobY = joystick.centerY + diffY

        -- 归一化
        local norm = dist / cfg.joystickRadius
        if norm < cfg.joystickDeadZone then
            joystick.dx = 0
            joystick.dy = 0
        else
            joystick.dx = (diffX / cfg.joystickRadius)
            joystick.dy = (diffY / cfg.joystickRadius)
        end
    end
end

---@param eventType string
---@param eventData TouchEndEventData
function InputAdapter_HandleTouchEnd(eventType, eventData)
    local touchID = eventData:GetInt("TouchID")

    -- 释放摇杆
    if joystick.active and joystick.touchID == touchID then
        joystick.active = false
        joystick.touchID = -1
        joystick.dx = 0
        joystick.dy = 0
        joystick.knobX = joystick.baseX
        joystick.knobY = joystick.baseY
        joystick.centerX = joystick.baseX
        joystick.centerY = joystick.baseY
    end

    -- 释放按钮
    for _, def in ipairs(ACTION_BUTTONS) do
        local btn = buttons[def.id]
        if btn.touchID == touchID then
            btn.pressed = false
            btn.touchID = -1
        end
    end
end

-- ============================================================================
-- NanoVG 绘制 (手机端虚拟控件)
-- ============================================================================

--- 绘制虚拟操控界面 (在 NanoVGRender 中调用)
---@param vg userdata NanoVG context
function InputAdapter.Draw(vg)
    if not isMobile then return end

    local cfg = InputAdapter.config

    -- 绘制虚拟摇杆
    InputAdapter._DrawJoystick(vg, cfg)

    -- 绘制功能按钮
    InputAdapter._DrawButtons(vg, cfg)

    -- 陀螺仪指示器
    if cfg.gyroscopeEnabled then
        InputAdapter._DrawGyroIndicator(vg)
    end
end

function InputAdapter._DrawJoystick(vg, cfg)
    local alpha = joystick.active and 180 or 100

    -- 外圈
    nvgBeginPath(vg)
    nvgCircle(vg, joystick.centerX, joystick.centerY, cfg.joystickRadius)
    nvgFillColor(vg, nvgRGBA(40, 50, 60, alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(120, 160, 200, alpha))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 方向十字线
    local crossLen = cfg.joystickRadius * 0.6
    nvgBeginPath(vg)
    nvgMoveTo(vg, joystick.centerX - crossLen, joystick.centerY)
    nvgLineTo(vg, joystick.centerX + crossLen, joystick.centerY)
    nvgMoveTo(vg, joystick.centerX, joystick.centerY - crossLen)
    nvgLineTo(vg, joystick.centerX, joystick.centerY + crossLen)
    nvgStrokeColor(vg, nvgRGBA(100, 140, 180, math.floor(alpha * 0.5)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 内圆（旋钮）
    nvgBeginPath(vg)
    nvgCircle(vg, joystick.knobX, joystick.knobY, cfg.joystickKnobRadius)
    nvgFillColor(vg, nvgRGBA(80, 140, 200, alpha + 40))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 210, 255, alpha + 40))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

function InputAdapter._DrawButtons(vg, cfg)
    for _, def in ipairs(ACTION_BUTTONS) do
        local btn = buttons[def.id]
        local alpha = btn.pressed and 220 or 140
        local scale = btn.pressed and 1.1 or 1.0
        local r = cfg.buttonRadius * scale
        local c = def.color

        -- 按钮背景
        nvgBeginPath(vg)
        nvgCircle(vg, btn.x, btn.y, r)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.5)))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 按钮文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, btn.x, btn.y, def.label)
    end
end

function InputAdapter._DrawGyroIndicator(vg)
    -- 小指示器，显示当前陀螺仪倾斜方向
    local indicatorX = 70
    local indicatorY = 60
    local indicatorR = 18

    nvgBeginPath(vg)
    nvgCircle(vg, indicatorX, indicatorY, indicatorR)
    nvgFillColor(vg, nvgRGBA(30, 40, 50, 120))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 200, 180, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 倾斜方向点
    local dotX = indicatorX + gyro.tiltX * indicatorR * 0.8
    local dotY = indicatorY + gyro.tiltY * indicatorR * 0.8
    nvgBeginPath(vg)
    nvgCircle(vg, dotX, dotY, 4)
    nvgFillColor(vg, nvgRGBA(100, 255, 180, 200))
    nvgFill(vg)

    -- 标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(150, 200, 180, 180))
    nvgText(vg, indicatorX, indicatorY + indicatorR + 4, "陀螺仪")
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取摇杆状态 (供外部渲染或调试)
function InputAdapter.GetJoystickState()
    return joystick
end

--- 获取某按钮的状态
---@param id string
---@return boolean pressed 是否被按住
function InputAdapter.IsButtonPressed(id)
    return buttons[id] and buttons[id].pressed or false
end

--- 检查本帧某动作是否被触发 (支持 PC 键盘 + 手机按钮)
---@param id string "attack"|"extract"|"heal"|"map"|"trade"
---@return boolean
function InputAdapter.IsActionTriggered(id)
    return InputAdapter.actions[id] or false
end

--- 获取按钮列表 (供外部自定义绘制)
function InputAdapter.GetButtons()
    return buttons
end

return InputAdapter
