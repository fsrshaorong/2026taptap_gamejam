-- ============================================================================
-- UITheme.lua
-- Small image registry for optional UI skinning. Missing images fall back to
-- simple NanoVG rectangles/text and never block gameplay.
-- ============================================================================

---@diagnostic disable: undefined-global

local UITheme = {}

local registry = {}
local images = {}
local currentVg = nil

local DEFAULT_ASSETS = {
    ["deploy.panel.main"] = "ui/deploy/ui_panel_deploy_main_blank.png",
    ["deploy.panel.summary"] = "ui/deploy/ui_panel_deploy_summary_blank.png",
    ["deploy.panel.background"] = "ui/common/ui_panel_terminal_main.png",
    ["deploy.button.confirm"] = "ui/deploy/ui_button_confirm_deploy_large.png",
    ["deploy.button.return"] = "ui/deploy/ui_button_back_main.png",
    ["deploy.tab.active"] = "ui/deploy/ui_frame_highlight.png",
    ["deploy.tab.inactive"] = "ui/common/ui_button_blank_dark.png",
    ["deploy.card.normal"] = "ui/common/ui_button_blank_dark.png",
    ["deploy.card.selected"] = "ui/deploy/ui_frame_highlight.png",
    ["deploy.card.disabled"] = "ui/common/ui_button_blank_dark.png",
    ["deploy.filter.active"] = "ui/deploy/ui_frame_highlight.png",
    ["deploy.filter.inactive"] = "ui/common/ui_button_blank_dark.png",
    ["deploy.divider.warning"] = "ui/common/ui_bar_blank_dark.png",
    ["deploy.scrollbar"] = "ui/common/ui_scrollbar_vertical.png",

    ["hud.panel.left"] = "ui/hud/ui_panel_left.png",
    ["hud.panel.protocol"] = "ui/hud/ui_panel_protocol.png",
    ["hud.tag.mineRisk.normal"] = "ui/hud/ui_mine_risk_tag.png",
    ["hud.tag.mineRisk.warning"] = "ui/hud/ui_mine_risk_tag.png",
    ["hud.tag.mineRisk.danger"] = "ui/hud/ui_mine_risk_tag.png",
    ["hud.bottomBar"] = "ui/hud/ui_bottom_bar.png",
    ["hud.keyPrompt"] = "ui/common/ui_button_blank_dark.png",
    ["hud.icon.backpack"] = "ui/hud/ui_icon_backpack.png",
    ["hud.bar.frame"] = "ui/hud/ui_bar_frame.png",
    ["hud.bar.warning"] = "ui/hud/ui_bar_warning.png",
    ["hud.key.q"] = "ui/keys/ui_key_q.png",
    ["hud.key.e"] = "ui/keys/ui_key_e.png",
    ["hud.key.f"] = "ui/keys/ui_key_f.png",
    ["hud.key.m"] = "ui/keys/ui_key_m.png",
    ["hud.key.t"] = "ui/keys/ui_key_t.png",

    ["item.equipment.default"] = "item_equipment/item_equipment_goggles.png",
    ["item.equipment.armor"] = "ui/deploy/ui_icon_armor.png",
    ["item.equipment.whetstone"] = "item_equipment/item_equipment_flashlight.png",
    ["item.equipment.medkit"] = "item_consumable/item_consumable_medkit.png",
    ["item.equipment.compass"] = "ui/deploy/ui_icon_compass.png",
    ["item.equipment.backpack"] = "ui/deploy/ui_icon_backpack.png",
    ["item.equipment.insulated_gloves"] = "item_equipment/item_equipment_goggles.png",
    ["item.consumable.default"] = "item_consumable/item_consumable_medkit.png",
    ["item.consumable.emergency_bandage"] = "ui/deploy/ui_icon_bandage.png",
    ["item.recovered.default"] = "item_recovered/item_recovered_ore.png",
    ["item.talent.default"] = "ui/deploy/ui_frame_highlight.png",
    ["item.currency.settlement"] = "ui/common/ui_icon_account_gold.png",
    ["item.placeholder"] = "ui/deploy/ui_frame_highlight.png",
}

local ITEM_ICON_KEYS = {
    armor = "item.equipment.armor",
    whetstone = "item.equipment.whetstone",
    medkit = "item.equipment.medkit",
    compass = "item.equipment.compass",
    backpack = "item.equipment.backpack",
    insulated_gloves = "item.equipment.insulated_gloves",
    emergency_bandage = "item.consumable.emergency_bandage",
}

local DEFAULT_ICON_KEYS = {
    equipment = "item.equipment.default",
    consumable = "item.consumable.default",
    recovered = "item.recovered.default",
    relic = "item.recovered.default",
    tool = "item.recovered.default",
    record = "item.recovered.default",
    talent = "item.talent.default",
    currency = "item.currency.settlement",
}

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

function UITheme.RegisterDefaults()
    for key, path in pairs(DEFAULT_ASSETS) do
        UITheme.Register(key, path)
    end
end

function UITheme.GetRegisteredPath(key)
    return registry[key]
end

function UITheme.ResolveIconPath(iconKey)
    local resolvedKey = iconKey
    if not registry[resolvedKey] then
        resolvedKey = "item.placeholder"
    end
    return registry[resolvedKey], resolvedKey
end

function UITheme.GetItemIconKey(item)
    item = item or {}
    local display = item.display or {}
    local requestedKey = display.iconKey or item.iconKey
    if requestedKey and registry[requestedKey] then
        return requestedKey
    end

    local itemId = item.id or item.itemId
    local mappedKey = ITEM_ICON_KEYS[itemId]
    if mappedKey and registry[mappedKey] then
        return mappedKey
    end

    local category = display.category or item.category
    local fallbackKey = DEFAULT_ICON_KEYS[category]
        or DEFAULT_ICON_KEYS[item.type]
        or DEFAULT_ICON_KEYS[item.source]
        or "item.placeholder"
    return registry[fallbackKey] and fallbackKey or "item.placeholder"
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
    local border = opts.border or { 70, 74, 70, 150 }
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
    local vg = opts.vg or currentVg or nvgScene
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
    opts.fill = opts.fill or (opts.hot and { 62, 54, 36, 230 } or { 18, 24, 28, 230 })
    opts.border = opts.border or (opts.hot and { 214, 174, 86, 230 } or { 70, 74, 70, 150 })
    return UITheme.DrawImage(key, x, y, w, h, opts)
end

function UITheme.DrawIcon(iconKey, x, y, size, opts)
    local resolvedKey = iconKey
    if type(iconKey) == "table" then
        resolvedKey = UITheme.GetItemIconKey(iconKey)
    elseif not registry[resolvedKey] then
        resolvedKey = "item.placeholder"
    end
    return UITheme.DrawImage(resolvedKey, x, y, size, size, opts)
end

UITheme.RegisterDefaults()

return UITheme
