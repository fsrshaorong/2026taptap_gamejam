-- ============================================================================
-- TextBox.lua
-- Small text fitting helpers shared by menu UI labels and NanoVG HUD drawing.
-- ============================================================================

local TextBox = {}

local function utf8Chars(text)
    text = tostring(text or "")
    local chars = {}
    if utf8 and utf8.offset then
        local ok = pcall(function()
            local i = 1
            while i <= #text do
                local nextIndex = utf8.offset(text, 2, i) or (#text + 1)
                table.insert(chars, string.sub(text, i, nextIndex - 1))
                i = nextIndex
            end
        end)
        if ok then
            return chars
        end
    end
    for i = 1, #text do
        table.insert(chars, string.sub(text, i, i))
    end
    return chars
end

local function charUnit(ch)
    if ch == "\n" then return 0 end
    local byte = string.byte(ch, 1) or 0
    if byte < 128 then
        if ch == " " then return 0.34 end
        if string.match(ch, "[%.,:;!|/%-%+%[%]%(%)xX]") then return 0.42 end
        return 0.56
    end
    return 1.0
end

local function textUnits(text)
    local total = 0
    for _, ch in ipairs(utf8Chars(text)) do
        total = total + charUnit(ch)
    end
    return total
end

local function appendEllipsis(line, maxUnits)
    local suffix = "..."
    local suffixUnits = textUnits(suffix)
    local chars = utf8Chars(line)
    while #chars > 0 and textUnits(table.concat(chars)) + suffixUnits > maxUnits do
        table.remove(chars)
    end
    return table.concat(chars) .. suffix
end

function TextBox.FitText(text, opts)
    opts = opts or {}
    local fontSize = opts.fontSize or 12
    local padding = opts.padding or 0
    local maxWidth = opts.maxWidth or opts.width or 120
    local usableW = math.max(1, maxWidth - padding * 2)
    local maxUnits = math.max(1, usableW / math.max(1, fontSize))
    local lineLimit = math.max(1, opts.lineLimit or 1)
    local ellipsis = opts.ellipsis ~= false
    local chars = utf8Chars(text)
    local lines = {}
    local current = {}
    local currentUnits = 0
    local truncated = false

    local function pushLine()
        table.insert(lines, table.concat(current))
        current = {}
        currentUnits = 0
    end

    for _, ch in ipairs(chars) do
        if ch == "\n" then
            pushLine()
            if #lines >= lineLimit then
                truncated = true
                break
            end
        else
            local unit = charUnit(ch)
            if #current > 0 and currentUnits + unit > maxUnits then
                pushLine()
                if #lines >= lineLimit then
                    truncated = true
                    break
                end
            end
            table.insert(current, ch)
            currentUnits = currentUnits + unit
        end
    end

    if not truncated and (#current > 0 or #lines == 0) then
        table.insert(lines, table.concat(current))
    end

    if #lines > lineLimit then
        truncated = true
        while #lines > lineLimit do
            table.remove(lines)
        end
    end

    if truncated and ellipsis and #lines > 0 then
        lines[#lines] = appendEllipsis(lines[#lines], maxUnits)
    end

    return table.concat(lines, "\n"), {
        lines = lines,
        truncated = truncated,
        maxUnits = maxUnits,
    }
end

function TextBox.DrawTextBox(vg, text, x, y, w, h, opts)
    opts = opts or {}
    local padding = opts.padding or 0
    local fontSize = opts.fontSize or 12
    local lineHeight = opts.lineHeight or (fontSize + 3)
    local lineLimit = opts.lineLimit or math.max(1, math.floor(math.max(1, h - padding * 2) / lineHeight))
    local fitted, info = TextBox.FitText(text, {
        maxWidth = opts.maxWidth or w,
        padding = padding,
        fontSize = fontSize,
        lineLimit = lineLimit,
        ellipsis = opts.ellipsis,
    })
    if not vg then
        return fitted, info
    end

    nvgSave(vg)
    if opts.clip ~= false and type(nvgScissor) == "function" then
        nvgScissor(vg, x, y, w, h)
    end
    nvgFontFace(vg, opts.fontFace or "sans")
    nvgFontSize(vg, fontSize)
    local align = opts.align or "left"
    local textAlign = NVG_ALIGN_TOP
    local tx = x + padding
    if align == "center" then
        textAlign = NVG_ALIGN_CENTER + NVG_ALIGN_TOP
        tx = x + w / 2
    elseif align == "right" then
        textAlign = NVG_ALIGN_RIGHT + NVG_ALIGN_TOP
        tx = x + w - padding
    else
        textAlign = NVG_ALIGN_LEFT + NVG_ALIGN_TOP
    end
    nvgTextAlign(vg, textAlign)
    local color = opts.color or { 210, 220, 220, 230 }
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 230))
    for index, line in ipairs(info.lines or { fitted }) do
        nvgText(vg, tx, y + padding + (index - 1) * lineHeight, line)
    end
    if opts.clip ~= false and type(nvgResetScissor) == "function" then
        nvgResetScissor(vg)
    end
    nvgRestore(vg)
    return fitted, info
end

return TextBox
