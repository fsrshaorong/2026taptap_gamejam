-- ============================================================================
-- MapOverlay.lua — 放大地图界面(UI 组件 + NanoVG 绘制)
-- 支持查看,插旗/取消,回传已探索安全格
-- ============================================================================

local UI = require("urhox-libs/UI")

local MapOverlay = {}

-- 图标贴图(64x64)
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

local function ensureImages(vg)
    if imagesLoaded then return end
    iconImages.player   = nvgCreateImage(vg, "Textures/generated/icons/64/00_wanjia_dingwei.png", 0)
    iconImages.hidden   = nvgCreateImage(vg, "Textures/generated/icons/64/01_weizhi_ge.png", 0)
    iconImages.explored = nvgCreateImage(vg, "Textures/generated/icons/64/02_yitan_ge.png", 0)
    iconImages.scanned  = nvgCreateImage(vg, "Textures/generated/icons/64/03_saomiao_ge.png", 0)
    iconImages.flag     = nvgCreateImage(vg, "Textures/generated/icons/64/04_biaoji_qi.png", 0)
    iconImages.trap     = nvgCreateImage(vg, "Textures/generated/icons/64/05_dici_xianjing_icon.png", 0)
    iconImages.monster  = nvgCreateImage(vg, "Textures/generated/icons/64/06_guaiwu_icon.png", 0)
    iconImages.chest    = nvgCreateImage(vg, "Textures/generated/icons/64/07_baoxiang_icon.png", 0)
    iconImages.exit     = nvgCreateImage(vg, "Textures/generated/icons/64/08_cheli_icon.png", 0)
    iconImages.cleared  = nvgCreateImage(vg, "Textures/generated/icons/64/10_yiqingli_icon.png", 0)
    iconImages.number1  = nvgCreateImage(vg, "Textures/generated/icons/64/11_shuzi_1.png", 0)
    iconImages.number2  = nvgCreateImage(vg, "Textures/generated/icons/64/12_shuzi_2.png", 0)
    iconImages.number3  = nvgCreateImage(vg, "Textures/generated/icons/64/13_shuzi_3.png", 0)
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

-- 经典扫雷数字颜色
local NUMBER_COLORS = {
    [1] = { 60, 100, 220 },
    [2] = { 40, 160, 40 },
    [3] = { 220, 40, 40 },
    [4] = { 120, 40, 180 },
    [5] = { 160, 80, 20 },
    [6] = { 40, 160, 160 },
    [7] = { 60, 60, 60 },
    [8] = { 120, 120, 120 },
}

-- 状态
MapOverlay.visible = false
MapOverlay.cellSize = 0
MapOverlay.offsetX = 0
MapOverlay.offsetY = 0
MapOverlay.fieldWidth = 0
MapOverlay.fieldHeight = 0

-- 回调
MapOverlay.onClose = nil       -- function()
MapOverlay.onFlag = nil        -- function(x, y)
MapOverlay.onTeleport = nil    -- function(x, y)

-- 地图数据引用(外部每帧刷新)
MapOverlay.visibleMap = nil
MapOverlay.playerX = 0
MapOverlay.playerY = 0
MapOverlay.visitedCells = nil   -- table: key "x,y" = true 表示曾进入

--- 初始化放大地图布局
---@param fieldWidth number
---@param fieldHeight number
---@param screenW number 逻辑宽
---@param screenH number 逻辑高
function MapOverlay.ComputeLayout(fieldWidth, fieldHeight, screenW, screenH)
    MapOverlay.fieldWidth = fieldWidth
    MapOverlay.fieldHeight = fieldHeight

    -- 计算最佳格子大小(占屏幕 85%)
    local maxW = screenW * 0.85
    local maxH = screenH * 0.75
    local csW = math.floor(maxW / fieldWidth)
    local csH = math.floor(maxH / fieldHeight)
    MapOverlay.cellSize = math.min(csW, csH)
    if MapOverlay.cellSize < 12 then MapOverlay.cellSize = 12 end
    -- 小地图(教程等)允许格子更大, 大地图限制54
    local maxCellSize = (math.max(fieldWidth, fieldHeight) <= 6) and 80 or 54
    if MapOverlay.cellSize > maxCellSize then MapOverlay.cellSize = maxCellSize end

    -- 居中
    local totalW = MapOverlay.cellSize * fieldWidth
    local totalH = MapOverlay.cellSize * fieldHeight
    MapOverlay.offsetX = math.floor((screenW - totalW) / 2)
    MapOverlay.offsetY = math.floor((screenH - totalH) / 2) + 20  -- 留顶部标题
end

local function drawNumberBadge(vg, cx, cy, cs, adjacent)
    if not adjacent or adjacent <= 0 then return end
    local col = NUMBER_COLORS[adjacent] or { 220, 220, 220 }
    local badgeSize = math.max(10, cs * 0.36)
    local bx = cx + cs - badgeSize - 3
    local by = cy + cs - badgeSize - 3

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, badgeSize, badgeSize, 3)
    nvgFillColor(vg, nvgRGBA(5, 8, 14, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(180, 190, 210, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.max(8, cs * 0.24))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
    nvgText(vg, bx + badgeSize / 2, by + badgeSize / 2, tostring(adjacent))
end

local function drawRoomIcon(vg, cell, cx, cy, cs)
    if not cell.revealed or not cell.roomType then return false end
    local ix = cx + cs / 2
    local iy = cy + cs / 2
    local iconSize = cs * 0.7

    if cell.roomType == "chest" then
        if not drawIcon(vg, iconImages.chest, ix, iy, iconSize) then
            -- fallback: NanoVG primitive
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix - cs * 0.22, iy - cs * 0.16, cs * 0.44, cs * 0.32, 3)
            nvgFillColor(vg, nvgRGBA(255, 200, 50, 245))
            nvgFill(vg)
        end
        return true
    elseif cell.roomType == "monster" then
        if not drawIcon(vg, iconImages.monster, ix, iy, iconSize) then
            local r = cs * 0.22
            nvgBeginPath(vg)
            nvgMoveTo(vg, ix, iy - r)
            nvgLineTo(vg, ix + r, iy)
            nvgLineTo(vg, ix, iy + r)
            nvgLineTo(vg, ix - r, iy)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(255, 60, 60, 245))
            nvgFill(vg)
        end
        return true
    elseif cell.roomType == "event" then
        if not drawIcon(vg, iconImages.scanned, ix, iy, iconSize) then
            nvgBeginPath(vg)
            nvgCircle(vg, ix, iy, cs * 0.2)
            nvgFillColor(vg, nvgRGBA(60, 200, 210, 245))
            nvgFill(vg)
        end
        return true
    elseif cell.roomType == "mine" then
        if not drawIcon(vg, iconImages.trap, ix, iy, iconSize) then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, cs * 0.5)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 100, 50, 255))
            nvgText(vg, ix, iy, "*")
        end
        return true
    end

    return false
end

--- 显示放大地图
function MapOverlay.Show()
    MapOverlay.visible = true
end

--- 隐藏放大地图
function MapOverlay.Hide()
    MapOverlay.visible = false
    if MapOverlay.onClose then
        MapOverlay.onClose()
    end
end

--- 绘制放大地图(在 NanoVGRender 中调用)
---@param vg userdata
---@param screenW number
---@param screenH number
function MapOverlay.Draw(vg, screenW, screenH)
    if not MapOverlay.visible then return end
    if not MapOverlay.visibleMap then return end

    ensureImages(vg)

    local cs = MapOverlay.cellSize
    local ox = MapOverlay.offsetX
    local oy = MapOverlay.offsetY

    -- 暗色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, screenW / 2, oy - 28, "区域扫描图 (点击格子标记雷险/回传)")

    -- 格子
    for y = 1, MapOverlay.fieldHeight do
        local row = MapOverlay.visibleMap[y]
        if not row then break end
        for x = 1, MapOverlay.fieldWidth do
            local cell = row[x]
            if not cell then break end

            local cx = ox + (x - 1) * cs
            local cy = oy + (y - 1) * cs

            -- 背景
            nvgBeginPath(vg)
            nvgRect(vg, cx + 1, cy + 1, cs - 2, cs - 2)

            if cell.state == "hidden" then
                nvgFillColor(vg, nvgRGBA(70, 75, 95, 255))
            elseif cell.state == "flagged" then
                nvgFillColor(vg, nvgRGBA(160, 50, 50, 255))
            elseif cell.state == "mine" then
                nvgFillColor(vg, nvgRGBA(220, 40, 40, 255))
            elseif cell.state == "empty" then
                nvgFillColor(vg, nvgRGBA(35, 40, 55, 255))
            elseif cell.state == "number" then
                nvgFillColor(vg, nvgRGBA(40, 45, 60, 255))
            else
                nvgFillColor(vg, nvgRGBA(50, 50, 60, 255))
            end
            nvgFill(vg)

            -- 边框
            nvgStrokeColor(vg, nvgRGBA(50, 55, 70, 200))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)

            -- 隐藏格贴图
            if cell.state == "hidden" then
                drawIcon(vg, iconImages.hidden, cx + cs / 2, cy + cs / 2, cs * 0.7, 0.8)
            end

            -- 撤离点
            if cell.exitId then
                nvgBeginPath(vg)
                nvgRect(vg, cx + 1, cy + 1, cs - 2, cs - 2)
                if cell.randomExit then
                    nvgStrokeColor(vg, nvgRGBA(255, 220, 70, 255))
                    nvgStrokeWidth(vg, 3)
                else
                    nvgStrokeColor(vg, nvgRGBA(80, 255, 80, 240))
                    nvgStrokeWidth(vg, 2)
                end
                nvgStroke(vg)
                -- 撤离图标
                if not drawIcon(vg, iconImages.exit, cx + cs / 2, cy + cs / 2, cs * 0.7) then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, cs * 0.4)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    if cell.randomExit then
                        nvgFillColor(vg, nvgRGBA(255, 230, 95, 230))
                    else
                        nvgFillColor(vg, nvgRGBA(80, 255, 80, 200))
                    end
                    nvgText(vg, cx + cs / 2, cy + cs / 2, "E")
                end
            end

            local specialIcon = false
            if not cell.exitId then
                specialIcon = drawRoomIcon(vg, cell, cx, cy, cs)
            end

            -- 数字
            if cell.state == "number" and cell.adjacent then
                if specialIcon or cell.exitId then
                    drawNumberBadge(vg, cx, cy, cs, cell.adjacent)
                else
                    -- 尝试使用数字贴图(1-3有专用贴图)
                    local numIcon = nil
                    if cell.adjacent == 1 then numIcon = iconImages.number1
                    elseif cell.adjacent == 2 then numIcon = iconImages.number2
                    elseif cell.adjacent == 3 then numIcon = iconImages.number3
                    end
                    if not (numIcon and drawIcon(vg, numIcon, cx + cs / 2, cy + cs / 2, cs * 0.7)) then
                        local col = NUMBER_COLORS[cell.adjacent] or { 200, 200, 200 }
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, cs * 0.6)
                        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
                        nvgText(vg, cx + cs / 2, cy + cs / 2, tostring(cell.adjacent))
                    end
                end
            end

            -- 旗标
            if cell.state == "flagged" then
                if not drawIcon(vg, iconImages.flag, cx + cs / 2, cy + cs / 2, cs * 0.7) then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, cs * 0.5)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 220, 50, 255))
                    nvgText(vg, cx + cs / 2, cy + cs / 2, "F")
                end
            end

            -- 地雷标记
            if cell.state == "mine" then
                if not drawIcon(vg, iconImages.trap, cx + cs / 2, cy + cs / 2, cs * 0.7) then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, cs * 0.6)
                    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                    nvgText(vg, cx + cs / 2, cy + cs / 2, "*")
                end
            end

            -- 已探索标记(可传送) - v0.3: 使用 cell.explored 字段
            if cell.explored
               and cell.state ~= "hidden" and cell.state ~= "flagged"
               and cell.state ~= "mine" then
                -- 右下角小圆点表示可传送
                nvgBeginPath(vg)
                nvgCircle(vg, cx + cs - 5, cy + cs - 5, 3)
                nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
                nvgFill(vg)
            end
        end
    end

    -- 玩家位置
    local px = ox + (MapOverlay.playerX - 1) * cs + cs / 2
    local py = oy + (MapOverlay.playerY - 1) * cs + cs / 2

    if not drawIcon(vg, iconImages.player, px, py, cs * 0.8) then
        local pr = cs * 0.3
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pr + 2)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, pr)
        nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
        nvgFill(vg)
    end

    -- 底部提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 200, 220, 200))
    local bottomY = oy + MapOverlay.fieldHeight * cs + 10
    nvgText(vg, screenW / 2, bottomY, "左键: 未知格标记雷险/取消 | 已探索格回传 | ESC/右键关闭")
end

--- 处理放大地图的点击
---@param mx number 逻辑坐标
---@param my number 逻辑坐标
---@param button number 鼠标按钮
---@return boolean 是否消费了事件
function MapOverlay.HandleClick(mx, my, button)
    if not MapOverlay.visible then return false end

    -- 右键或 ESC 关闭
    if button == MOUSEB_RIGHT then
        MapOverlay.Hide()
        return true
    end

    local cs = MapOverlay.cellSize
    local ox = MapOverlay.offsetX
    local oy = MapOverlay.offsetY

    -- 计算格子坐标
    local gx = math.floor((mx - ox) / cs) + 1
    local gy = math.floor((my - oy) / cs) + 1

    if gx < 1 or gx > MapOverlay.fieldWidth or gy < 1 or gy > MapOverlay.fieldHeight then
        -- 点击地图外, 关闭
        MapOverlay.Hide()
        return true
    end

    -- 获取格子信息
    local row = MapOverlay.visibleMap[gy]
    if not row then return true end
    local cell = row[gx]
    if not cell then return true end

    -- 逻辑:
    -- 1) 隐藏格 -> 插旗
    -- 2) 已插旗 -> 取消旗
    -- 3) 已探索安全格 + 已访问 -> 传送
    if cell.state == "hidden" or cell.state == "flagged" then
        if MapOverlay.onFlag then
            MapOverlay.onFlag(gx, gy)
        end
    elseif (cell.state == "number" or cell.state == "empty") then
        -- v0.3: 使用 cell.explored 判断是否可传送
        if cell.explored then
            if MapOverlay.onTeleport then
                MapOverlay.onTeleport(gx, gy)
            end
        end
    end

    return true
end

return MapOverlay
