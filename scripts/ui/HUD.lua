-- ============================================================================
-- HUD.lua - 四区布局 HUD 系统(NanoVG 绘制)
-- 布局: 左侧信息栏 + 中央主游戏区 + 右上协议面板 + 底部交互栏
-- ============================================================================

local MiniMap = require("ui.MiniMap")
local Protocol = require("systems.Protocol")
local GameText = require("systems.GameText")
local UITheme = require("ui.UITheme")
local TextBox = require("ui.TextBox")

local HUD = {}

-- ============================================================================
-- 布局常量
-- ============================================================================

local LAYOUT = {
    -- 左侧信息栏
    sidebarWidthRatio = 0.28,
    sidebarMinW = 272,
    sidebarMaxW = 360,
    sidebarPadding = 18,

    -- 底部栏
    bottomBarH = 62,

    -- 右上协议面板
    protocolW = 212,
    protocolH = 132,
    protocolMargin = 18,

    -- 面板样式
    panelBg = { 10, 14, 22, 200 },
    panelBorder = { 60, 64, 58, 140 },
    panelRadius = 6,
}

-- ============================================================================
-- 布局计算
-- ============================================================================

--- 计算 HUD 各区域的像素位置
---@param w number 逻辑宽度
---@param h number 逻辑高度
---@return table layout
function HUD.ComputeLayout(w, h)
    -- 左侧栏宽度
    local sidebarW = math.floor(w * LAYOUT.sidebarWidthRatio)
    sidebarW = math.max(LAYOUT.sidebarMinW, math.min(LAYOUT.sidebarMaxW, sidebarW))

    local bottomH = LAYOUT.bottomBarH

    return {
        -- 左侧信息栏
        sidebar = {
            x = 0, y = 0,
            w = sidebarW, h = h - bottomH,
        },
        -- 中央主游戏区(避开左栏和底栏)
        center = {
            x = sidebarW,
            y = 0,
            w = w - sidebarW,
            h = h - bottomH,
        },
        -- 右上协议面板
        protocol = {
            x = w - LAYOUT.protocolW - LAYOUT.protocolMargin,
            y = LAYOUT.protocolMargin,
            w = LAYOUT.protocolW,
            h = LAYOUT.protocolH,
        },
        -- 底部栏
        bottom = {
            x = 0, y = h - bottomH,
            w = w, h = bottomH,
        },
        danger = {
            x = sidebarW,
            y = h - bottomH - 34,
            w = w - sidebarW,
            h = 28,
        },
        -- 全屏尺寸
        screenW = w,
        screenH = h,
    }
end

-- ============================================================================
-- 面板绘制工具
-- ============================================================================

local function drawPanel(vg, x, y, w, h, alpha, themeKey)
    alpha = alpha or LAYOUT.panelBg[4]
    if themeKey and UITheme.DrawImage(themeKey, x, y, w, h, {
        vg = vg,
        alpha = alpha / 255,
        fallback = false,
    }) then
        return
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, LAYOUT.panelRadius)
    nvgFillColor(vg, nvgRGBA(LAYOUT.panelBg[1], LAYOUT.panelBg[2], LAYOUT.panelBg[3], alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(LAYOUT.panelBorder[1], LAYOUT.panelBorder[2], LAYOUT.panelBorder[3], LAYOUT.panelBorder[4]))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

local function DrawTextBox(vg, text, x, y, w, h, opts)
    return TextBox.DrawTextBox(vg, text, x, y, w, h, opts)
end

local function drawSummaryRow(vg, x, y, row, width)
    UITheme.DrawIcon(row.iconKey or "item.placeholder", x, y, 15, {
        vg = vg,
        fill = { 20, 34, 40, 230 },
        border = { 94, 154, 154, 170 },
        radius = 3,
    })
    DrawTextBox(vg, row.text, x + 20, y, math.max(120, (width or 200) - 20), 17, {
        fontSize = 12,
        lineLimit = 1,
        color = { 190, 210, 220, 230 },
    })
end

-- ============================================================================
-- 协议常量(左侧栏 + 协议面板共用)
-- ============================================================================

local PROTOCOL_COLORS = {
    [5] = { 80, 200, 120 },   -- 绿
    [4] = { 200, 200, 80 },   -- 黄
    [3] = { 240, 160, 40 },   -- 橙
    [2] = { 240, 80, 40 },    -- 红橙
    [1] = { 255, 40, 40 },    -- 红
}

local PROTOCOL_TITLES = {
    [5] = "正常作业",
    [4] = "轻度警戒",
    [3] = "风险作业",
    [2] = "返程建议",
    [1] = "最终广播",
}

local PROTOCOL_DESCS = {
    [5] = "区域稳定, 允许回收.",
    [4] = "异常读数上升.",
    [3] = "深入提高收益和风险.",
    [2] = "撤离窗口缩短.",
    [1] = "撤离是建议.",
}

for level, text in pairs(GameText.protocol.levels) do
    PROTOCOL_TITLES[level] = text.short
    PROTOCOL_DESCS[level] = text.desc
end

-- 协议降级动画状态
HUD.protocolFlashTimer = 0
HUD.lastProtocolLevel = nil

-- ============================================================================
-- 左侧信息栏
-- ============================================================================

--- 绘制左侧信息栏(扫描图 + 状态 + 目标提示)
---@param vg userdata
---@param layout table ComputeLayout 返回值
---@param context table { visibleMap, playerX, playerY, fieldWidth, fieldHeight, combat, inventory, protocol, message, exploredCount }
function HUD.DrawLeftSidebar(vg, layout, context)
    local sb = layout.sidebar
    drawPanel(vg, sb.x, sb.y, sb.w, sb.h, 210, "hud.panel.left")

    local pad = LAYOUT.sidebarPadding
    local contentX = sb.x + pad
    local curY = sb.y + pad
    local hud = context.hud or {}

    -- 标题: 区域扫描图
    nvgFontFace(vg, "sans")
    DrawTextBox(vg, GameText.hud.mapTitle, contentX, curY, sb.w - pad * 2, 22, {
        fontSize = 18,
        lineLimit = 1,
        color = { 180, 200, 230, 255 },
    })
    curY = curY + 24

    -- 小地图(嵌入左侧栏, 随侧边栏宽度缩放)
    if context.visibleMap then
        local mapW = math.min(sb.w - pad * 2, math.max(168, sb.h - 398))

        -- 临时覆盖 MiniMap 参数
        local oldMapX = MiniMap.mapX
        local oldMapY = MiniMap.mapY
        local oldMaxSize = MiniMap.maxSize

        MiniMap.mapX = contentX
        MiniMap.mapY = curY
        MiniMap.maxSize = mapW

        MiniMap.Draw(vg, context.visibleMap, context.playerX or 1, context.playerY or 1,
            context.fieldWidth or 15, context.fieldHeight or 15)

        -- 恢复
        MiniMap.mapX = oldMapX
        MiniMap.mapY = oldMapY
        MiniMap.maxSize = oldMaxSize

        curY = curY + MiniMap.totalH + 8
    end

    -- 图例
    DrawTextBox(vg, GameText.hud.minesweeperRule1, contentX, curY, sb.w - pad * 2, 16, {
        fontSize = 13,
        lineLimit = 1,
        color = { 140, 150, 170, 200 },
    })
    curY = curY + 18
    DrawTextBox(vg, GameText.hud.minesweeperRule2, contentX, curY, sb.w - pad * 2, 16, {
        fontSize = 13,
        lineLimit = 1,
        color = { 140, 150, 170, 200 },
    })
    curY = curY + 23

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, contentX, curY)
    nvgLineTo(vg, contentX + sb.w - pad * 2, curY)
    nvgStrokeColor(vg, nvgRGBA(60, 80, 110, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    curY = curY + 8

    -- 状态信息
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- HP
    local combat = context.combat or {}
    local hp = combat.hp or 0
    local maxHp = combat.maxHp or 100
    local hpRatio = maxHp > 0 and (hp / maxHp) or 0

    -- HP 条背景
    local barW = math.max(118, sb.w - pad * 2 - 76)
    local barH = 14
    local barX = contentX + 62
    nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
    nvgText(vg, contentX, curY, GameText.hud.hp)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, curY + 2, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(40, 20, 20, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, curY + 2, barW * hpRatio, barH, 3)
    nvgFillColor(vg, nvgRGBA(220, 60, 60, 255))
    nvgFill(vg)
    -- HP 数字
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgText(vg, barX + barW / 2, curY + 2 + barH / 2, hp .. "/" .. maxHp)
    curY = curY + barH + 14

    -- 战斗力/待结算/回收物
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    nvgFillColor(vg, nvgRGBA(255, 180, 60, 255))
    DrawTextBox(vg, GameText.hud.power .. (combat.power or 10), contentX, curY, sb.w - pad * 2, 18, {
        fontSize = 16,
        lineLimit = 1,
        color = { 255, 180, 60, 255 },
    })
    curY = curY + 21

    local inv = context.inventory or {}
    DrawTextBox(vg, GameText.hud.pendingGold .. (hud.pendingCurrency or inv.pendingGold or inv.gold or 0), contentX, curY, sb.w - pad * 2, 18, {
        fontSize = 16,
        lineLimit = 1,
        color = { 255, 230, 80, 255 },
    })
    curY = curY + 21

    DrawTextBox(vg, GameText.hud.parts .. (inv.parts or 0), contentX, curY, sb.w - pad * 2, 18, {
        fontSize = 16,
        lineLimit = 1,
        color = { 160, 210, 255, 255 },
    })
    curY = curY + 21

    local consumables = hud.consumableCounts or inv.consumables or {}
    local bandageCount = consumables.emergency_bandage or 0
    if bandageCount > 0 then
        DrawTextBox(vg, "止血贴: x" .. bandageCount, contentX, curY, sb.w - pad * 2, 18, {
            fontSize = 16,
            lineLimit = 1,
            color = { 170, 230, 210, 255 },
        })
        curY = curY + 21
    end

    -- 已锁定 / 回收物 / 已探索 一行显示
    nvgFontSize(vg, 14)
    local rowText = "已锁定:" .. (hud.lockedCurrency or inv.safeGold or 0)
        .. "  回收物:" .. (inv.carriedItemCount or 0) .. "件"
        .. "  探索:" .. (context.exploredCount or 0) .. "格"
    DrawTextBox(vg, rowText, contentX, curY, sb.w - pad * 2, 17, {
        fontSize = 14,
        lineLimit = 1,
        color = { 180, 190, 210, 200 },
    })
    nvgFontSize(vg, 16)
    curY = curY + 24

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, contentX, curY)
    nvgLineTo(vg, contentX + sb.w - pad * 2, curY)
    nvgStrokeColor(vg, nvgRGBA(60, 80, 110, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    curY = curY + 8

    -- 轻量作业包摘要
    DrawTextBox(vg, "作业包摘要", contentX, curY, sb.w - pad * 2, 18, {
        fontSize = 14,
        lineLimit = 1,
        color = { 130, 220, 205, 245 },
    })
    curY = curY + 19

    nvgFontSize(vg, 12)
    local rows = {}
    for _, row in ipairs(hud.consumables or {}) do table.insert(rows, row) end
    for _, row in ipairs(hud.recoveredItems or {}) do table.insert(rows, row) end
    for _, effect in ipairs(hud.equipmentEffects or {}) do
        table.insert(rows, { iconKey = "item.equipment.default", text = effect })
    end
    if #rows == 0 then
        table.insert(rows, { iconKey = "item.recovered.default", text = "暂无待结算回收物" })
    end
    for index = 1, math.min(3, #rows) do
        drawSummaryRow(vg, contentX, curY, rows[index], sb.w - pad * 2)
        curY = curY + 17
    end
    if #rows > 3 then
        DrawTextBox(vg, "另有 " .. (#rows - 3) .. " 项", contentX + 20, curY, sb.w - pad * 2 - 20, 17, {
            fontSize = 12,
            lineLimit = 1,
            color = { 150, 180, 186, 215 },
        })
    end
end

-- ============================================================================
-- 右上协议面板
-- ============================================================================

--- 绘制右上协议面板
---@param vg userdata
---@param layout table
---@param protocolStatus table { level, description, changed }
---@param dt number
function HUD.DrawProtocolPanel(vg, layout, protocolStatus, dt)
    local p = layout.protocol
    local level = protocolStatus.protocolLevel or protocolStatus.level or 5
    local color = PROTOCOL_COLORS[level] or { 180, 180, 180 }

    -- 降级闪烁
    if protocolStatus.changed and HUD.lastProtocolLevel ~= level then
        HUD.protocolFlashTimer = 0.8
    end
    HUD.lastProtocolLevel = level
    if HUD.protocolFlashTimer > 0 then
        HUD.protocolFlashTimer = HUD.protocolFlashTimer - dt
        local flash = math.abs(math.sin(HUD.protocolFlashTimer * 12))
        -- 闪烁边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, p.x - 2, p.y - 2, p.w + 4, p.h + 4, LAYOUT.panelRadius + 2)
        nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(200 * flash)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 面板背景
    drawPanel(vg, p.x, p.y, p.w, p.h, 220, "hud.panel.protocol")

    -- 标题
    nvgFontFace(vg, "sans")
    DrawTextBox(vg, GameText.protocol.panelTitle, p.x + 12, p.y + 10, p.w - 24, 14, {
        fontSize = 11,
        lineLimit = 1,
        color = { 160, 170, 190, 220 },
    })

    -- 大号等级数字
    local numScale = 1.0
    if HUD.protocolFlashTimer > 0 then
        numScale = 1.0 + 0.3 * math.abs(math.sin(HUD.protocolFlashTimer * 8))
    end
    nvgFontSize(vg, 28 * numScale)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
    nvgText(vg, p.x + 12, p.y + 48, "协议 " .. tostring(level))

    -- 阶段名称
    DrawTextBox(vg, PROTOCOL_TITLES[level] or "", p.x + 96, p.y + 39, p.w - 108, 16, {
        fontSize = 12,
        lineLimit = 1,
        align = "right",
        color = { color[1], color[2], color[3], 230 },
    })

    -- 压力值
    DrawTextBox(vg, "封锁压力: " .. (protocolStatus.pressure or 0) .. " / " .. (protocolStatus.pressureMax or protocolStatus.maxPressure or 100), p.x + 12, p.y + 70, p.w - 24, 14, {
        fontSize = 10,
        lineLimit = 1,
        color = { 160, 170, 190, 180 },
    })
    local pressureRatio = math.max(0, math.min(1, (protocolStatus.pressure or 0) / math.max(1, protocolStatus.pressureMax or protocolStatus.maxPressure or 100)))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, p.x + 12, p.y + 88, p.w - 24, 8, 3)
    nvgFillColor(vg, nvgRGBA(36, 45, 52, 230))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, p.x + 12, p.y + 88, (p.w - 24) * pressureRatio, 8, 3)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 245))
    nvgFill(vg)

    DrawTextBox(vg, PROTOCOL_DESCS[level] or "", p.x + 12, p.y + 104, p.w - 24, 22, {
        fontSize = 10,
        lineLimit = 2,
        color = { 172, 185, 192, 205 },
    })
end

-- ============================================================================
-- 主场景下方雷险标签
-- ============================================================================

function HUD.DrawNearbyDanger(vg, layout, context)
    local d = layout.danger
    local adjacent = context.nearbyMineRisk or context.adjacent or 0
    local state = context.mineRiskState or (context.roomType == "mine" and "danger") or (adjacent >= 2 and "warning") or "normal"
    local triggered = state == "danger"
    local color = triggered and { 255, 100, 78 } or (state == "warning" and { 230, 166, 72 } or { 160, 190, 166 })
    local text = triggered and "周围雷险: 已触发" or (GameText.hud.nearbyDanger .. adjacent)
    local tagX = d.x + d.w / 2 - 110
    local tagW = 220

    UITheme.DrawImage("hud.tag.mineRisk." .. state, tagX, d.y, tagW, d.h, {
        vg = vg,
        fill = { 16, 24, 29, adjacent > 0 and 220 or 170 },
        border = { color[1], color[2], color[3], adjacent > 0 and 190 or 110 },
        radius = 4,
    })

    DrawTextBox(vg, text, tagX + 12, d.y + 7, tagW - 24, d.h - 8, {
        fontSize = 13,
        lineLimit = 1,
        align = "center",
        color = { color[1], color[2], color[3], 245 },
    })
end

-- ============================================================================
-- 底部栏
-- ============================================================================

--- 绘制底部交互提示栏
---@param vg userdata
---@param layout table
---@param context table { interactHint, exitDistance, exitDirection }
function HUD.DrawBottomBar(vg, layout, context)
    local b = layout.bottom
    drawPanel(vg, b.x, b.y, b.w, b.h, 210, "hud.bottomBar")

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 中央: 当前交互提示
    local hint = context.interactHint or ""
    if hint ~= "" then
        DrawTextBox(vg, hint, b.x + 220, b.y + 6, b.w - 440, 18, {
            fontSize = 13,
            lineLimit = 1,
            align = "center",
            color = { 255, 240, 180, 255 },
        })
    end

    local consumables = context.consumables or {}
    local bandageCount = consumables.emergency_bandage or 0
    local commands = {
        { key = "WASD", label = "移动" },
        { key = "M", image = "hud.key.m", label = "扫描图" },
        { key = "F", image = "hud.key.f", label = "搜索/攻击" },
        { key = "E", image = "hud.key.e", label = "撤离" },
        { key = "T", image = "hud.key.t", label = "事件" },
        { key = "Q", image = "hud.key.q", label = "止血贴 x" .. bandageCount },
    }
    local groupW = math.max(96, math.min(118, math.floor((b.w - 132) / #commands)))
    local totalW = #commands * groupW
    local startX = b.x + (b.w - totalW) / 2
    for index, command in ipairs(commands) do
        local x = startX + (index - 1) * groupW
        local keyW = command.image and 20 or 36
        if command.image then
            UITheme.DrawImage(command.image, x, b.y + 31, 20, 20, {
                vg = vg,
                fill = { 22, 34, 42, 230 },
                border = { 100, 150, 160, 180 },
                radius = 3,
            })
        else
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x, b.y + 31, keyW, 20, 3)
            nvgFillColor(vg, nvgRGBA(22, 34, 42, 230))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(100, 150, 160, 180))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            nvgFontSize(vg, 9)
            nvgFillColor(vg, nvgRGBA(210, 226, 226, 240))
            nvgText(vg, x + keyW / 2, b.y + 41, command.key)
        end
        DrawTextBox(vg, command.label, x + keyW + 6, b.y + 34, groupW - keyW - 10, 16, {
            fontSize = 10,
            lineLimit = 1,
            color = { 164, 184, 192, 225 },
        })
    end

    -- 右侧: 撤离距离
    if context.exitDistance then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(100, 255, 150, 230))
        local dirText = context.exitDirection or ""
        nvgText(vg, b.x + b.w - 14, b.y + 13,
            "撤离信标 " .. dirText .. " 距离 " .. context.exitDistance)
    end
end

-- ============================================================================
-- 交互提示计算
-- ============================================================================

--- 根据当前房间状态生成交互提示
---@param context table { roomType, searchState, hasEnemy, enemyAlive, hasExit, canTrade }
---@return string
function HUD.GetInteractHint(context)
    if context.hasExit then
        return GameText.interact.exit
    end
    if context.hasEnemy and context.enemyAlive then
        if context.playerPower and context.enemyPower then
            local hpText = ""
            if context.enemyHP and context.enemyMaxHP then
                hpText = " HP " .. context.enemyHP .. "/" .. context.enemyMaxHP
            end
            return "[F] 攻击异常体  我方 " .. context.playerPower .. " / 威胁 " .. context.enemyPower .. hpText .. "  可直接离开"
        end
        return "[F] 攻击异常体  /  可直接离开"
    end
    if context.hasEnemy then
        return GameText.interact.cleared
    end
    if context.canTrade then
        if context.eventName then
            return GameText.interact.event .. context.eventName
        end
        return GameText.interact.trader
    end
    if context.tradeUnavailable then
        return GameText.events.trader.noItem
    end
    if context.eventTraded then
        if context.eventName then
            return "[T] 查看: " .. context.eventName .. "已完成"
        end
        return "[T] 查看: 事件已完成"
    end
    local searchState = context.searchState or {}
    if searchState.searched and context.roomType == "chest" then
        return "物资箱已开启"
    end
    if searchState.searched then
        return "该区域已搜索"
    end
    if context.roomType == "chest" and searchState.canSearch then
        return GameText.interact.chest
    end
    if searchState.canSearch then
        return GameText.interact.search
    end
    if searchState.searching then
        return "搜索中..."
    end
    return ""
end

--- 计算最近撤离点方向和距离
---@param playerX number
---@param playerY number
---@param exits table { {x, y}, ... }
---@return number|nil distance
---@return string direction
function HUD.CalcExitDistance(playerX, playerY, exits)
    if not exits or #exits == 0 then return nil, "" end

    local minDist = math.huge
    local closestExit = nil
    for _, e in ipairs(exits) do
        local dist = math.abs(playerX - e.x) + math.abs(playerY - e.y)
        if dist < minDist then
            minDist = dist
            closestExit = e
        end
    end

    if not closestExit then return nil, "" end

    -- 方向
    local dx = closestExit.x - playerX
    local dy = closestExit.y - playerY
    local dir = ""
    if dy < 0 then dir = dir .. "北" end
    if dy > 0 then dir = dir .. "南" end
    if dx > 0 then dir = dir .. "东" end
    if dx < 0 then dir = dir .. "西" end
    if dir == "" then dir = "此处" end

    return minDist, dir
end

-- ============================================================================
-- 教程对话框
-- ============================================================================

--- 绘制教程对话框(底部半透明面板)
---@param vg userdata
---@param screenW number
---@param screenH number
---@param step table { text, subtext, type }
function HUD.DrawTutorialDialog(vg, screenW, screenH, step)
    if not step then return end

    -- 底部对话框区域
    local panelH = 90
    local panelW = math.min(screenW * 0.8, 520)
    local px = (screenW - panelW) / 2
    local py = screenH - panelH - 30

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(15, 20, 30, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 180, 220, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 左侧小图标(对话气泡)
    local iconX = px + 24
    local iconY = py + panelH / 2
    nvgBeginPath(vg)
    nvgCircle(vg, iconX, iconY, 14)
    nvgFillColor(vg, nvgRGBA(60, 160, 200, 200))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, iconX, iconY, "?")

    -- 主文本
    local textX = px + 52
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 245, 255, 255))
    nvgText(vg, textX, py + panelH * 0.4, step.text or "")

    -- 副文本/提示
    if step.subtext and step.subtext ~= "" then
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(160, 200, 230, 200))
        nvgText(vg, textX, py + panelH * 0.7, step.subtext)
    end

    -- 步骤指示器(右下角)
    -- 由调用方在外部传入 stepIndex/totalSteps 更好, 这里用简单脉冲提示可点击
    if step.type == "dialog" then
        local pulse = (math.sin(os.clock() * 4) + 1) * 0.5
        local triX = px + panelW - 24
        local triY = py + panelH - 20
        nvgBeginPath(vg)
        nvgMoveTo(vg, triX - 5, triY - 4)
        nvgLineTo(vg, triX + 5, triY)
        nvgLineTo(vg, triX - 5, triY + 4)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(200, 230, 255, math.floor(120 + 135 * pulse)))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 教程弹窗（新系统: 阻塞居中 / 非阻塞底部）
-- ============================================================================

--- 简易多行文本绘制（按 \n 分割）
---@param vg userdata
---@param x number
---@param y number
---@param lineHeight number
---@param lines string
local function drawMultilineText(vg, x, y, lineHeight, lines)
    local lineNum = 0
    for line in (lines .. "\n"):gmatch("(.-)\n") do
        nvgText(vg, x, y + lineNum * lineHeight, line)
        lineNum = lineNum + 1
    end
    return lineNum
end

--- 绘制教程弹窗（新系统）
---@param vg userdata
---@param screenW number
---@param screenH number
---@param popup table  Tutorial.GetActivePopup() 返回的弹窗定义
function HUD.DrawTutorialPopup(vg, screenW, screenH, popup)
    if not popup then return end

    if popup.blocking then
        -- ========== 阻塞弹窗: 半透明遮罩 + 居中大面板 ==========
        -- 遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenW, screenH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
        nvgFill(vg)

        -- 面板尺寸
        local panelW = math.min(screenW * 0.75, 440)
        local padX = 28
        local padTop = 24
        local padBot = 20
        local titleSize = 18
        local bodySize = 14
        local lineH = bodySize * 1.55
        local confirmSize = 13

        -- 预计算正文行数
        local bodyLines = 0
        if popup.body then
            for _ in (popup.body .. "\n"):gmatch("(.-)\n") do
                bodyLines = bodyLines + 1
            end
        end

        local panelH = padTop + titleSize + 12 + (bodyLines * lineH) + 18 + confirmSize + padBot
        local px = (screenW - panelW) / 2
        local py = (screenH - panelH) / 2

        -- 面板背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py, panelW, panelH, 12)
        nvgFillColor(vg, nvgRGBA(18, 24, 38, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 170, 230, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 标题
        local titleY = py + padTop + titleSize / 2
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, titleSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
        nvgText(vg, screenW / 2, titleY, popup.title or "提示")

        -- 正文
        local bodyY = titleY + titleSize / 2 + 14
        nvgFontSize(vg, bodySize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(230, 240, 255, 240))
        if popup.body then
            drawMultilineText(vg, px + padX, bodyY, lineH, popup.body)
        end

        -- 确认提示（底部居中，脉冲动画）
        local pulse = (math.sin(os.clock() * 3.5) + 1) * 0.5
        local confirmY = py + panelH - padBot - confirmSize / 2
        nvgFontSize(vg, confirmSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, math.floor(140 + 115 * pulse)))
        local confirmText = popup.confirmText or "[ 点击 / Enter 继续 ]"
        nvgText(vg, screenW / 2, confirmY, confirmText)
    else
        -- ========== 非阻塞弹窗: 底部小面板 ==========
        local panelW = math.min(screenW * 0.7, 400)
        local padX = 20
        local padY = 14
        local titleSize = 14
        local bodySize = 12.5
        local lineH = bodySize * 1.5

        -- 预计算正文行数
        local bodyLines = 0
        if popup.body then
            for _ in (popup.body .. "\n"):gmatch("(.-)\n") do
                bodyLines = bodyLines + 1
            end
        end

        local panelH = padY + titleSize + 8 + (bodyLines * lineH) + padY
        local px = (screenW - panelW) / 2
        local py = screenH - panelH - 24

        -- 面板背景（半透明，不阻挡游戏操作）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py, panelW, panelH, 8)
        nvgFillColor(vg, nvgRGBA(12, 18, 28, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(70, 140, 190, 150))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 标题
        local titleY = py + padY + titleSize / 2
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, titleSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(80, 190, 240, 240))
        nvgText(vg, px + padX, titleY, popup.title or "提示")

        -- 正文
        local bodyY = titleY + titleSize / 2 + 8
        nvgFontSize(vg, bodySize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(210, 225, 245, 220))
        if popup.body then
            drawMultilineText(vg, px + padX, bodyY, lineH, popup.body)
        end
    end
end

-- ============================================================================
-- 居中播报(Toast)
-- ============================================================================

--- 绘制居中播报消息(一闪即逝效果)
---@param vg userdata
---@param layout table
---@param message string
---@param timer number 剩余时间
---@param duration number 总时长
function HUD.DrawCenterToast(vg, layout, message, timer, duration)
    if not message or message == "" or timer <= 0 then return end

    local screenW = layout.screenW or (layout.center.x + layout.center.w)
    local screenH = layout.screenH or (layout.center.h)
    -- 偏右下，大约在游戏场景宝箱位置(避开左侧栏)
    local sidebarW = screenW * 0.24
    local cx = sidebarW + (screenW - sidebarW) * 0.5
    local cy = screenH * 0.52

    -- 淡入淡出: 前0.3秒淡入, 后0.8秒淡出
    local alpha = 1.0
    local elapsed = duration - timer
    local fadeIn = 0.25
    local fadeOut = 0.8
    if elapsed < fadeIn then
        alpha = elapsed / fadeIn
    elseif timer < fadeOut then
        alpha = timer / fadeOut
    end

    -- 轻微上浮动画
    local offsetY = 0
    if timer < fadeOut then
        offsetY = (1 - timer / fadeOut) * -8
    end

    local a = math.floor(alpha * 255)

    -- 背景条
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local bounds = {}
    local tw = nvgTextBounds(vg, cx, cy, message, bounds)
    local pw, ph = tw + 28, 32
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - pw / 2, cy + offsetY - ph / 2, pw, ph, 6)
    nvgFillColor(vg, nvgRGBA(10, 12, 20, math.floor(alpha * 180)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 100, math.floor(alpha * 80)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 文本
    nvgFillColor(vg, nvgRGBA(255, 235, 140, a))
    nvgText(vg, cx, cy + offsetY, message)
end

return HUD
