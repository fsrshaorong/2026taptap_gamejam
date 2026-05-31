-- ============================================================================
-- UILayout.lua
-- Lightweight logical-coordinate adapter for menu and terminal UI.
-- ============================================================================

local UILayout = {}

local BASE_W = 1536
local BASE_H = 864

local viewportW = BASE_W
local viewportH = BASE_H
local scale = 1
local offsetX = 0
local offsetY = 0

local function recompute()
    local sx = viewportW / BASE_W
    local sy = viewportH / BASE_H
    scale = math.min(sx, sy)
    if scale <= 0 then scale = 1 end
    offsetX = (viewportW - BASE_W * scale) / 2
    offsetY = (viewportH - BASE_H * scale) / 2
end

function UILayout.SetBaseSize(w, h)
    BASE_W = tonumber(w) or BASE_W
    BASE_H = tonumber(h) or BASE_H
    recompute()
end

function UILayout.SetViewport(w, h)
    viewportW = tonumber(w) or viewportW
    viewportH = tonumber(h) or viewportH
    recompute()
end

function UILayout.GetScale()
    return scale
end

function UILayout.GetOffset()
    return offsetX, offsetY
end

function UILayout.GetBaseSize()
    return BASE_W, BASE_H
end

function UILayout.GetViewport()
    return viewportW, viewportH
end

function UILayout.ToScreen(x, y, w, h)
    local sx = offsetX + (x or 0) * scale
    local sy = offsetY + (y or 0) * scale
    if w == nil and h == nil then
        return sx, sy
    end
    return sx, sy, (w or 0) * scale, (h or 0) * scale
end

function UILayout.ToLogic(mx, my)
    return ((mx or 0) - offsetX) / scale, ((my or 0) - offsetY) / scale
end

function UILayout.ContainsLogic(x, y, rect)
    if not rect then return false end
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function UILayout.IsInsideBase(x, y)
    return x >= 0 and x <= BASE_W and y >= 0 and y <= BASE_H
end

UILayout.SetViewport(BASE_W, BASE_H)

return UILayout
