-- ============================================================================
-- MapOverlay.lua — 放大地图界面（UI 组件 + NanoVG 绘制）
-- 支持查看、插旗/取消、回传已探索安全格
-- ============================================================================

local UI = require("urhox-libs/UI")

local MapOverlay = {}

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

-- 地图数据引用（外部每帧刷新）
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

    -- 计算最佳格子大小（占屏幕 85%）
    local maxW = screenW * 0.85
    local maxH = screenH * 0.75
    local csW = math.floor(maxW / fieldWidth)
    local csH = math.floor(maxH / fieldHeight)
    MapOverlay.cellSize = math.min(csW, csH)
    if MapOverlay.cellSize < 12 then MapOverlay.cellSize = 12 end
    if MapOverlay.cellSize > 36 then MapOverlay.cellSize = 36 end

    -- 居中
    local totalW = MapOverlay.cellSize * fieldWidth
    local totalH = MapOverlay.cellSize * fieldHeight
    MapOverlay.offsetX = math.floor((screenW - totalW) / 2)
    MapOverlay.offsetY = math.floor((screenH - totalH) / 2) + 20  -- 留顶部标题
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

--- 绘制放大地图（在 NanoVGRender 中调用）
---@param vg userdata
---@param screenW number
---@param screenH number
function MapOverlay.Draw(vg, screenW, screenH)
    if not MapOverlay.visible then return end
    if not MapOverlay.visibleMap then return end

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
    nvgText(vg, screenW / 2, oy - 28, "扫雷地图 (点击格子插旗/回传)")

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

            -- 撤离点
            if cell.exitId then
                nvgBeginPath(vg)
                nvgRect(vg, cx + 1, cy + 1, cs - 2, cs - 2)
                nvgStrokeColor(vg, nvgRGBA(80, 255, 80, 240))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
                -- E 标记
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, cs * 0.4)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(80, 255, 80, 200))
                nvgText(vg, cx + cs / 2, cy + cs / 2, "E")
            end

            -- 数字
            if cell.state == "number" and cell.adjacent then
                local col = NUMBER_COLORS[cell.adjacent] or { 200, 200, 200 }
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, cs * 0.6)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
                nvgText(vg, cx + cs / 2, cy + cs / 2, tostring(cell.adjacent))
            end

            -- 旗标
            if cell.state == "flagged" then
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, cs * 0.5)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 220, 50, 255))
                nvgText(vg, cx + cs / 2, cy + cs / 2, "F")
            end

            -- 地雷标记
            if cell.state == "mine" then
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, cs * 0.6)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, cx + cs / 2, cy + cs / 2, "*")
            end

            -- 已访问标记（可传送）
            local key = tostring(x) .. "," .. tostring(y)
            if MapOverlay.visitedCells and MapOverlay.visitedCells[key]
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
    local pr = cs * 0.3

    nvgBeginPath(vg)
    nvgCircle(vg, px, py, pr + 2)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, pr)
    nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
    nvgFill(vg)

    -- 底部提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 200, 220, 200))
    local bottomY = oy + MapOverlay.fieldHeight * cs + 10
    nvgText(vg, screenW / 2, bottomY, "左键: 未知格插旗/取消 | 已探索格回传 | ESC/右键关闭")
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
        -- 点击地图外，关闭
        MapOverlay.Hide()
        return true
    end

    -- 获取格子信息
    local row = MapOverlay.visibleMap[gy]
    if not row then return true end
    local cell = row[gx]
    if not cell then return true end

    -- 逻辑：
    -- 1) 隐藏格 → 插旗
    -- 2) 已插旗 → 取消旗
    -- 3) 已探索安全格 + 已访问 → 传送
    if cell.state == "hidden" or cell.state == "flagged" then
        if MapOverlay.onFlag then
            MapOverlay.onFlag(gx, gy)
        end
    elseif (cell.state == "number" or cell.state == "empty") then
        local key = tostring(gx) .. "," .. tostring(gy)
        if MapOverlay.visitedCells and MapOverlay.visitedCells[key] then
            if MapOverlay.onTeleport then
                MapOverlay.onTeleport(gx, gy)
            end
        end
    end

    return true
end

return MapOverlay
