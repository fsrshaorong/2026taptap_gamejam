-- ============================================================================
-- UITheme.lua
-- Small image registry for optional UI skinning. Missing images fall back to
-- simple NanoVG rectangles/text and never block gameplay.
-- ============================================================================

local UITheme = {}

local registry = {}
local images = {}
local currentVg = nil

local function canLoad()
    return type(nvgCreateImage) == "function"
end

local function isLoaded(img)
    return type(img) == "number" and img >= 0
end

function UITheme.LoadImage(key, path)
    if not key or key == "" then return false end
    registry[key] = path
    if not canLoad() or not path or path == "" then
        images[key] = -1
        return false
    end
    local ok, img = pcall(nvgCreateImage, currentVg, path, 0)
    if ok and isLoaded(img) then
        images[key] = img
        return true
    end
    images[key] = -1
    return false
end

function UITheme.GetImage(key)
    return images[key]
end

function UITheme.Has(key)
    return isLoaded(images[key])
end

function UITheme.Register(key, path)
    registry[key] = path
end

function UITheme.SetContext(vg)
    currentVg = vg
end

function UITheme.LoadRegistered(vg)
    if not canLoad() then return end
    currentVg = vg or currentVg
    for key, path in pairs(registry) do
        if not isLoaded(images[key]) and path then
            local ok, img = pcall(nvgCreateImage, currentVg, path, 0)
            images[key] = (ok and isLoaded(img)) and img or -1
        end
    end
end

local function drawFallback(vg, x, y, w, h, opts)
    opts = opts or {}
    local fill = opts.fill or { 20, 28, 38, 220 }
    local border = opts.border or { 90, 160, 190, 150 }
    local radius = opts.radius or 6
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, radius)
    nvgFillColor(vg, nvgRGBA(fill[1], fill[2], fill[3], fill[4] or 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(border[1], border[2], border[3], border[4] or 150))
    nvgStrokeWidth(vg, opts.strokeWidth or 1)
    nvgStroke(vg)
    if opts.text and opts.text ~= "" then
        nvgFontFace(vg, opts.fontFace or "sans")
        nvgFontSize(vg, opts.fontSize or 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local color = opts.fontColor or { 230, 240, 235, 235 }
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 235))
        nvgText(vg, x + w / 2, y + h / 2, opts.text)
    end
end

function UITheme.DrawImage(key, x, y, w, h, opts)
    opts = opts or {}
    local vg = opts.vg or nvgScene
    if not vg then return false end
    local img = images[key]
    if isLoaded(img) then
        local alpha = opts.alpha or 1.0
        local paint = nvgImagePattern(vg, x, y, w, h, 0, img, alpha)
        nvgBeginPath(vg)
        if opts.radius and opts.radius > 0 then
            nvgRoundedRect(vg, x, y, w, h, opts.radius)
        else
            nvgRect(vg, x, y, w, h)
        end
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        return true
    end
    if opts.fallback ~= false then
        drawFallback(vg, x, y, w, h, opts)
    end
    return false
end

function UITheme.DrawImageButton(key, x, y, w, h, opts)
    opts = opts or {}
    opts.fill = opts.fill or (opts.hot and { 35, 78, 96, 230 } or { 18, 28, 40, 230 })
    opts.border = opts.border or (opts.hot and { 160, 230, 230, 230 } or { 90, 160, 190, 150 })
    return UITheme.DrawImage(key, x, y, w, h, opts)
end

return UITheme
