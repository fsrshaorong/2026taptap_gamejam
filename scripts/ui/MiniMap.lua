-- ============================================================================
-- MiniMap.lua — 左上角扫雷小地图（NanoVG 绘制）
-- 显示格子状态、玩家位置、撤离点
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

--- 计算小地图尺寸
---@param fieldWidth number
---@param fieldHeight number
function MiniMap.ComputeLayout(fieldWidth, fieldHeight)
    local maxDim = math.max(fieldWidth, fieldHeight)
    MiniMap.cellSize = math.floor((MiniMap.maxSize - MiniMap.padding * 2) / maxDim)
    if MiniMap.cellSize < 4 then MiniMap.cellSize = 4 end

    MiniMap.totalW = MiniMap.cellSize * fieldWidth + MiniMap.padding * 2
    MiniMap.totalH = MiniMap.cellSize * fieldHeight + MiniMap.padding * 2
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

            -- 撤离点标记（始终可见）
            if cell.exitId then
                nvgBeginPath(vg)
                nvgRect(vg, cx, cy, cs - 1, cs - 1)
                nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 220))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            end

            -- 特殊房型图标（揭示后才显示）
            local drawnIcon = false
            if cell.revealed and cell.roomType and cs >= 6 then
                if cell.roomType == "chest" then
                    -- 宝箱图标：金色方块
                    nvgBeginPath(vg)
                    nvgRect(vg, cx + cs * 0.2, cy + cs * 0.25, cs * 0.6, cs * 0.5)
                    nvgFillColor(vg, nvgRGBA(255, 200, 50, 240))
                    nvgFill(vg)
                    drawnIcon = true
                elseif cell.roomType == "monster" then
                    -- 怪物图标：红色菱形
                    local mcx = cx + cs / 2
                    local mcy = cy + cs / 2
                    local mr = cs * 0.3
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, mcx, mcy - mr)
                    nvgLineTo(vg, mcx + mr, mcy)
                    nvgLineTo(vg, mcx, mcy + mr)
                    nvgLineTo(vg, mcx - mr, mcy)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(255, 60, 60, 240))
                    nvgFill(vg)
                    drawnIcon = true
                elseif cell.roomType == "mine" and cell.state == "mine" then
                    -- 已触发雷：橙色三角警示
                    local tcx = cx + cs / 2
                    local tcy = cy + cs * 0.3
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, tcx, tcy)
                    nvgLineTo(vg, tcx + cs * 0.3, cy + cs * 0.8)
                    nvgLineTo(vg, tcx - cs * 0.3, cy + cs * 0.8)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(255, 140, 30, 240))
                    nvgFill(vg)
                    drawnIcon = true
                end
            end

            -- 数字（如果格子够大且没有图标覆盖）
            if not drawnIcon and cell.state == "number" and cell.adjacent and cs >= 8 then
                local col = NUMBER_COLORS[cell.adjacent] or { 200, 200, 200 }
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, cs * 0.7)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], 255))
                nvgText(vg, cx + cs / 2, cy + cs / 2, tostring(cell.adjacent))
            end

            -- 旗标图标
            if cell.state == "flagged" and cs >= 6 then
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

    -- 玩家位置标记
    local px = ox + pad + (playerX - 1) * cs + cs / 2
    local py = oy + pad + (playerY - 1) * cs + cs / 2
    local pr = cs * 0.35
    if pr < 2 then pr = 2 end

    nvgBeginPath(vg)
    nvgCircle(vg, px, py, pr + 2)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, px, py, pr)
    nvgFillColor(vg, nvgRGBA(50, 200, 255, 255))
    nvgFill(vg)
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
