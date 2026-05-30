-- ============================================================================
-- MiniMap.lua — 左上角扫雷小地图(NanoVG 绘制)
-- 显示格子状态,玩家位置,撤离点
-- ============================================================================

local MiniMap = {}

-- 经典扫雷数字颜色
local NUMBER_COLORS = {
    [1] = { 60, 100, 220 },   -- 蓝
    [2] = { 40, 160, 40 },    -- 绿
    [3] = { 220, 40, 40 },    -- 红
    [4] = { 120, 40, 180 },   -- 紫
    [5] = { 160, 80, 20 },    -- 棕
    [6] = { 40, 160, 160 },   -- 青
    [7] = { 60, 60, 60 },     -- 黑
    [8] = { 120, 120, 120 },  -- 灰
}

-- 配置
MiniMap.cellSize = 0   -- 运行时计算
MiniMap.mapX = 12
MiniMap.mapY = 12
MiniMap.maxSize = 160  -- 小地图最大像素尺寸
MiniMap.padding = 4

-- 邻域感知高亮状态
MiniMap.highlightCells = {}   -- { ["x,y"] = true }
MiniMap.highlightTimer = 0    -- 倒计时(秒)
local HIGHLIGHT_DURATION = 3.0

local imagesLoaded = false
local iconImages = {
    player = -1,
    hidden = -1,
    explored = -1,
    scanned = -1,
    flag = -1,
    trap = -1,
    monster = -1,
    chest = -1,
    exit = -1,
    cleared = -1,
    number1 = -1,
    number2 = -1,
    number3 = -1,
}

function MiniMap.Init(vg)
    if imagesLoaded then return end
    iconImages.player = nvgCreateImage(vg, "Textures/generated/icons/32/00_wanjia_dingwei.png", 0)
    iconImages.hidden = nvgCreateImage(vg, "Textures/generated/icons/32/01_weizhi_ge.png", 0)
    iconImages.explored = nvgCreateImage(vg, "Textures/generated/icons/32/02_yitan_ge.png", 0)
    iconImages.scanned = nvgCreateImage(vg, "Textures/generated/icons/32/03_saomiao_ge.png", 0)
    iconImages.flag = nvgCreateImage(vg, "Textures/generated/icons/32/04_biaoji_qi.png", 0)
    iconImages.trap = nvgCreateImage(vg, "Textures/generated/icons/32/05_dici_xianjing_icon.png", 0)
    iconImages.monster = nvgCreateImage(vg, "Textures/generated/icons/32/06_guaiwu_icon.png", 0)
    iconImages.chest = nvgCreateImage(vg, "Textures/generated/icons/32/07_baoxiang_icon.png", 0)
    iconImages.exit = nvgCreateImage(vg, "Textures/generated/icons/32/08_cheli_icon.png", 0)
    iconImages.cleared = nvgCreateImage(vg, "Textures/generated/icons/32/10_yiqingli_icon.png", 0)
    iconImages.number1 = nvgCreateImage(vg, "Textures/generated/icons/32/11_shuzi_1.png", 0)
    iconImages.number2 = nvgCreateImage(vg, "Textures/generated/icons/32/12_shuzi_2.png", 0)
    iconImages.number3 = nvgCreateImage(vg, "Textures/generated/icons/32/13_shuzi_3.png", 0)
    imagesLoaded = true
end

local function drawIcon(vg, img, cx, cy, size, alpha)
    if img < 0 then return false end
    alpha = alpha or 1.0
    local half = size / 2
    local paint = nvgImagePattern(vg, cx - half, cy - half, size, size, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, cx - half, cy - half, size, size)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    return true
end

--- 设置需要高亮的格子列表
---@param cells table { {x,y}, ... }
function MiniMap.SetHighlight(cells)
    MiniMap.highlightCells = {}
    for _, c in ipairs(cells) do
        MiniMap.highlightCells[tostring(c.x) .. "," .. tostring(c.y)] = true
    end
    MiniMap.highlightTimer = HIGHLIGHT_DURATION
end

--- 更新高亮计时器
function MiniMap.Update(dt)
    if MiniMap.highlightTimer > 0 then
        MiniMap.highlightTimer = MiniMap.highlightTimer - dt
        if MiniMap.highlightTimer < 0 then
            MiniMap.highlightTimer = 0
            MiniMap.highlightCells = {}
        end
    end
end

--- 计算小地图尺寸
---@param fieldWidth number
---@param fieldHeight number
function MiniMap.ComputeLayout(fieldWidth, fieldHeight)
    local maxDim = math.max(fieldWidth, fieldHeight)
    -- 格子少时(教程等小地图)自动放大显示
    local effectiveMaxSize = MiniMap.maxSize
    if maxDim <= 6 then
        effectiveMaxSize = math.max(MiniMap.maxSize, 240)
    end
    MiniMap.cellSize = math.floor((effectiveMaxSize - MiniMap.padding * 2) / maxDim)
    if MiniMap.cellSize < 4 then MiniMap.cellSize = 4 end

    MiniMap.totalW = MiniMap.cellSize * fieldWidth + MiniMap.padding * 2
    MiniMap.totalH = MiniMap.cellSize * fieldHeight + MiniMap.padding * 2
end

local function drawNumberBadge(vg, cx, cy, cs, adjacent)
    if not adjacent or adjacent <= 0 or cs < 8 then return end
    local col = NUMBER_COLORS[adjacent] or { 220, 220, 220 }
    local badgeSize = math.max(6, cs * 0.55)
    local bx = cx + cs - badgeSize - 1
    local by = cy + cs - badgeSize - 1

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, badgeSize, badgeSize, 2)
    nvgFillColor(vg, nvgRGBA(5, 8, 14, 210))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(6, cs * 0.48))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
    nvgText(vg, bx + badgeSize / 2, by + badgeSize / 2, tostring(adjacent))
end

local function drawRoomIcon(vg, cell, cx, cy, cs)
    if not cell.revealed or not cell.roomType or cs < 6 then return false end

    if cell.roomType == "chest" then
        if drawIcon(vg, iconImages.chest, cx + cs / 2, cy + cs / 2, cs * 0.9, 1.0) then
            return true
        end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + cs * 0.18, cy + cs * 0.25, cs * 0.64, cs * 0.48, 2)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 240))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, cx + cs * 0.45, cy + cs * 0.25, cs * 0.1, cs * 0.48)
        nvgFillColor(vg, nvgRGBA(120, 80, 20, 180))
        nvgFill(vg)
        return true
    elseif cell.roomType == "monster" then
        if cell.monsterCleared then
            if drawIcon(vg, iconImages.cleared, cx + cs / 2, cy + cs / 2, cs * 0.9, 1.0) then
                return true
            end
            nvgBeginPath(vg)
            nvgCircle(vg, cx + cs / 2, cy + cs / 2, cs * 0.32)
            nvgFillColor(vg, nvgRGBA(65, 190, 120, 240))
            nvgFill(vg)
            return true
        end
        if drawIcon(vg, iconImages.monster, cx + cs / 2, cy + cs / 2, cs * 0.9, 1.0) then
            return true
        end
        local mcx = cx + cs / 2
        local mcy = cy + cs / 2
        local mr = cs * 0.32
        nvgBeginPath(vg)
        nvgMoveTo(vg, mcx, mcy - mr)
        nvgLineTo(vg, mcx + mr, mcy)
        nvgLineTo(vg, mcx, mcy + mr)
        nvgLineTo(vg, mcx - mr, mcy)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 240))
        nvgFill(vg)
        return true
    elseif cell.roomType == "mine" and cell.state == "mine" then
        if drawIcon(vg, iconImages.trap, cx + cs / 2, cy + cs / 2, cs * 0.9, 1.0) then
            return true
        end
        local tcx = cx + cs / 2
        local tcy = cy + cs * 0.25
        nvgBeginPath(vg)
        nvgMoveTo(vg, tcx, tcy)
        nvgLineTo(vg, tcx + cs * 0.32, cy + cs * 0.78)
        nvgLineTo(vg, tcx - cs * 0.32, cy + cs * 0.78)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 140, 30, 240))
        nvgFill(vg)
        return true
    elseif cell.roomType == "event" then
        if cell.eventCompleted then
            if drawIcon(vg, iconImages.cleared, cx + cs / 2, cy + cs / 2, cs * 0.9, 1.0) then
                return true
            end
        end
        nvgBeginPath(vg)
        nvgCircle(vg, cx + cs / 2, cy + cs / 2, cs * 0.3)
        nvgFillColor(vg, cell.eventCompleted and nvgRGBA(70, 190, 120, 230) or nvgRGBA(60, 200, 210, 240))
        nvgFill(vg)
        return true
    end

    return false
end

--- 绘制小地图
---@param vg userdata NanoVG context
---@param visibleMap table Minefield:GetVisibleMap() 返回的二维数组
---@param playerX number 玩家坐标
---@param playerY number 玩家坐标
---@param fieldWidth number 地图宽
---@param fieldHeight number 地图高
function MiniMap.Draw(vg, visibleMap, playerX, playerY, fieldWidth, fieldHeight)
    if not visibleMap then return end
    MiniMap.Init(vg)

    MiniMap.ComputeLayout(fieldWidth, fieldHeight)

    local ox = MiniMap.mapX
    local oy = MiniMap.mapY
    local cs = MiniMap.cellSize
    local pad = MiniMap.padding

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, ox, oy, MiniMap.totalW, MiniMap.totalH, 6)
    nvgFillColor(vg, nvgRGBA(10, 15, 25, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 80, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 格子
    for y = 1, fieldHeight do
        local row = visibleMap[y]
        if not row then break end
        for x = 1, fieldWidth do
            local cell = row[x]
            if not cell then break end

            local cx = ox + pad + (x - 1) * cs
            local cy = oy + pad + (y - 1) * cs

            -- 绘制格子背景
            nvgBeginPath(vg)
            nvgRect(vg, cx, cy, cs - 1, cs - 1)

            if cell.state == "hidden" then
                nvgFillColor(vg, nvgRGBA(60, 65, 80, 255))
            elseif cell.state == "flagged" then
                nvgFillColor(vg, nvgRGBA(180, 50, 50, 255))
            elseif cell.state == "mine" then
                nvgFillColor(vg, nvgRGBA(220, 40, 40, 255))
            elseif cell.state == "empty" then
                nvgFillColor(vg, nvgRGBA(30, 35, 45, 255))
            elseif cell.state == "number" then
                nvgFillColor(vg, nvgRGBA(35, 40, 55, 255))
            else
                nvgFillColor(vg, nvgRGBA(40, 40, 50, 255))
            end
            nvgFill(vg)

            if cell.state == "hidden" then
                drawIcon(vg, iconImages.hidden, cx + cs / 2, cy + cs / 2, cs * 0.9, 0.95)
            elseif cell.state == "empty" then
                drawIcon(vg, iconImages.explored, cx + cs / 2, cy + cs / 2, cs * 0.85, 0.8)
            elseif cell.state == "number" then
                drawIcon(vg, iconImages.scanned, cx + cs / 2, cy + cs / 2, cs * 0.85, 0.45)
            end

            -- 撤离点标记(始终可见)
            if cell.exitId then
                drawIcon(vg, iconImages.exit, cx + cs / 2, cy + cs / 2, cs * 0.9, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, cx, cy, cs - 1, cs - 1)
                if cell.randomExit then
                    nvgStrokeColor(vg, nvgRGBA(255, 230, 80, 240))
                    nvgStrokeWidth(vg, 2.2)
                else
                    nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 220))
                    nvgStrokeWidth(vg, 1.5)
                end
                nvgStroke(vg)
            end

            -- 特殊房型图标(揭示后才显示). 特殊房也保留雷数字角标.
            local drawnIcon = drawRoomIcon(vg, cell, cx, cy, cs)

            -- 数字(如果格子够大且没有图标覆盖)
            if not drawnIcon and cell.state == "number" and cell.adjacent and cs >= 8 then
                local numberIcon = nil
                if cell.adjacent == 1 then numberIcon = iconImages.number1
                elseif cell.adjacent == 2 then numberIcon = iconImages.number2
                elseif cell.adjacent == 3 then numberIcon = iconImages.number3 end
                if not (numberIcon and numberIcon >= 0 and drawIcon(vg, numberIcon, cx + cs / 2, cy + cs / 2, cs * 0.82, 1.0)) then
                    local col = NUMBER_COLORS[cell.adjacent] or { 200, 200, 200 }
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, cs * 0.7)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
                    nvgText(vg, cx + cs / 2, cy + cs / 2, tostring(cell.adjacent))
                end
            elseif drawnIcon and cell.state == "number" then
                drawNumberBadge(vg, cx, cy, cs, cell.adjacent)
            end

            -- 旗标图标
            if cell.state == "flagged" and cs >= 6 then
                if not drawIcon(vg, iconImages.flag, cx + cs / 2, cy + cs / 2, cs * 0.9, 1.0) then
                    nvgBeginPath(vg)
                    local fx = cx + cs * 0.3
                    local fy = cy + cs * 0.2
                    nvgMoveTo(vg, fx, fy)
                    nvgLineTo(vg, fx + cs * 0.4, fy + cs * 0.2)
                    nvgLineTo(vg, fx, fy + cs * 0.4)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(255, 220, 50, 255))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 邻域感知高亮边框
    if MiniMap.highlightTimer > 0 then
        local alpha = math.floor(200 * (MiniMap.highlightTimer / HIGHLIGHT_DURATION))
        -- 脉冲闪烁效果
        local pulse = math.abs(math.sin(MiniMap.highlightTimer * 4)) * 0.5 + 0.5
        alpha = math.floor(alpha * pulse)
        for y = 1, fieldHeight do
            for x = 1, fieldWidth do
                local key = tostring(x) .. "," .. tostring(y)
                if MiniMap.highlightCells[key] then
                    local hx = ox + pad + (x - 1) * cs
                    local hy = oy + pad + (y - 1) * cs
                    nvgBeginPath(vg)
                    nvgRect(vg, hx, hy, cs - 1, cs - 1)
                    nvgStrokeColor(vg, nvgRGBA(255, 220, 80, alpha))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end
            end
        end
    end

    -- 玩家位置标记
    local px = ox + pad + (playerX - 1) * cs + cs / 2
    local py = oy + pad + (playerY - 1) * cs + cs / 2
    local pr = cs * 0.35
    if pr < 2 then pr = 2 end

    if not drawIcon(vg, iconImages.player, px, py, math.max(cs * 1.15, 10), 1.0) then
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pr + 2)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pr)
        nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
        nvgFill(vg)
    end
end

--- 检测点击是否在小地图范围内
---@param mx number 逻辑坐标 X
---@param my number 逻辑坐标 Y
---@return boolean
function MiniMap.HitTest(mx, my)
    return mx >= MiniMap.mapX and mx <= MiniMap.mapX + MiniMap.totalW
       and my >= MiniMap.mapY and my <= MiniMap.mapY + MiniMap.totalH
end

return MiniMap
