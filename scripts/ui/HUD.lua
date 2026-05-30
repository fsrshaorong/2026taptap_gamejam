-- ============================================================================
-- HUD.lua - 四区布局 HUD 系统(NanoVG 绘制)
-- 布局: 左侧信息栏 + 中央主游戏区 + 右上协议面板 + 底部交互栏
-- ============================================================================

local MiniMap = require("ui.MiniMap")
local Protocol = require("systems.Protocol")

local HUD = {}

-- ============================================================================
-- 布局常量
-- ============================================================================

local LAYOUT = {
    -- 左侧信息栏
    sidebarWidthRatio = 0.24,  -- 屏幕宽度 24%
    sidebarMinW = 200,
    sidebarMaxW = 320,
    sidebarPadding = 10,

    -- 底部栏
    bottomBarH = 56,

    -- 右上协议面板
    protocolW = 140,
    protocolH = 100,
    protocolMargin = 10,

    -- 面板样式
    panelBg = { 10, 14, 22, 200 },
    panelBorder = { 50, 70, 110, 140 },
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
            w = sidebarW, h = h,
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
        -- 全屏尺寸
        screenW = w,
        screenH = h,
    }
end

-- ============================================================================
-- 面板绘制工具
-- ============================================================================

local function drawPanel(vg, x, y, w, h, alpha)
    alpha = alpha or LAYOUT.panelBg[4]
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, LAYOUT.panelRadius)
    nvgFillColor(vg, nvgRGBA(LAYOUT.panelBg[1], LAYOUT.panelBg[2], LAYOUT.panelBg[3], alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(LAYOUT.panelBorder[1], LAYOUT.panelBorder[2], LAYOUT.panelBorder[3], LAYOUT.panelBorder[4]))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
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
    [2] = "强制返程建议",
    [1] = "最终广播",
}

local PROTOCOL_DESCS = {
    [5] = "区域稳定, 允许回收.",
    [4] = "异常读数上升.",
    [3] = "深入提高收益和风险.",
    [2] = "撤离窗口缩短.",
    [1] = "立即撤离.",
}

-- 协议降级动画状态
HUD.protocolFlashTimer = 0

-- ============================================================================
-- 左侧信息栏
-- ============================================================================

--- 绘制左侧信息栏(扫描图 + 状态 + 目标提示)
---@param vg userdata
---@param layout table ComputeLayout 返回值
---@param context table { visibleMap, playerX, playerY, fieldWidth, fieldHeight, combat, inventory, protocol, message, exploredCount }
function HUD.DrawLeftSidebar(vg, layout, context)
    local sb = layout.sidebar
    drawPanel(vg, sb.x, sb.y, sb.w, sb.h, 210)

    local pad = LAYOUT.sidebarPadding
    local contentX = sb.x + pad
    local curY = sb.y + pad

    -- 标题: 区域扫描图
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 200, 230, 255))
    nvgText(vg, contentX, curY, "区域扫描图")
    curY = curY + 21

    -- 小地图(嵌入左侧栏)
    if context.visibleMap then
        local mapW = sb.w - pad * 2
        -- 重新计算小地图尺寸适配侧边栏
        local maxDim = math.max(context.fieldWidth or 15, context.fieldHeight or 15)
        local cellSize = math.floor(mapW / maxDim)
        if cellSize < 4 then cellSize = 4 end
        local actualMapW = cellSize * (context.fieldWidth or 15)
        local actualMapH = cellSize * (context.fieldHeight or 15)

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

        curY = curY + actualMapH + 8
    end

    -- 图例
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(140, 150, 170, 200))
    nvgText(vg, contentX, curY, "数字 = 周围8格雷险")
    curY = curY + 16
    nvgText(vg, contentX, curY, "特殊房不计入数字")
    curY = curY + 21

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, contentX, curY)
    nvgLineTo(vg, contentX + sb.w - pad * 2, curY)
    nvgStrokeColor(vg, nvgRGBA(60, 80, 110, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    curY = curY + 8

    -- 状态信息
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- HP
    local combat = context.combat or {}
    local hp = combat.hp or 0
    local maxHp = combat.maxHp or 100
    local hpRatio = maxHp > 0 and (hp / maxHp) or 0

    -- HP 条背景
    local barW = sb.w - pad * 2 - 58
    local barH = 12
    local barX = contentX + 56
    nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
    nvgText(vg, contentX, curY, "生命")
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, curY + 2, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(40, 20, 20, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, curY + 2, barW * hpRatio, barH, 3)
    nvgFillColor(vg, nvgRGBA(220, 60, 60, 255))
    nvgFill(vg)
    -- HP 数字
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgText(vg, barX + barW / 2, curY + 2 + barH / 2, hp .. "/" .. maxHp)
    curY = curY + barH + 12

    -- 战斗力/金币/零件
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    nvgFillColor(vg, nvgRGBA(255, 180, 60, 255))
    nvgText(vg, contentX, curY, "战力: " .. (combat.power or 10))
    curY = curY + 19

    local inv = context.inventory or {}
    nvgFillColor(vg, nvgRGBA(255, 230, 80, 255))
    nvgText(vg, contentX, curY, "金币: " .. (inv.gold or 0))
    curY = curY + 19

    nvgFillColor(vg, nvgRGBA(160, 210, 255, 255))
    nvgText(vg, contentX, curY, "零件: " .. (inv.parts or 0))
    curY = curY + 19

    nvgFillColor(vg, nvgRGBA(150, 230, 190, 255))
    nvgText(vg, contentX, curY, "回收包: " .. (inv.carriedItemCount or 0) .. " 件 / 估值 " .. (inv.carriedItemValue or 0))
    curY = curY + 19

    nvgFillColor(vg, nvgRGBA(180, 190, 210, 200))
    nvgText(vg, contentX, curY, "已探索: " .. (context.exploredCount or 0) .. " 格")
    curY = curY + 24

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, contentX, curY)
    nvgLineTo(vg, contentX + sb.w - pad * 2, curY)
    nvgStrokeColor(vg, nvgRGBA(60, 80, 110, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    curY = curY + 8

    -- 当前目标
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(120, 230, 160, 255))
    nvgText(vg, contentX, curY, "目标:")
    curY = curY + 17
    nvgFillColor(vg, nvgRGBA(200, 220, 200, 220))
    nvgText(vg, contentX, curY, "搜刮物资, 前往撤离点")
    curY = curY + 21

    -- 附近危险
    local adjacent = context.adjacent or 0
    if adjacent > 0 and context.roomType ~= "mine" then
        nvgFontSize(vg, 14)
        local dangerColor = adjacent >= 3 and nvgRGBA(255, 80, 60, 255) or nvgRGBA(255, 200, 80, 255)
        nvgFillColor(vg, dangerColor)
        nvgText(vg, contentX, curY, "附近危险: " .. adjacent .. " 格")
        curY = curY + 21
    end

    -- 协议等级(内联)
    local protocolStatus = context.protocolStatus
    if protocolStatus then
        local level = protocolStatus.level or 5
        local pColor = PROTOCOL_COLORS[level] or { 180, 180, 180 }
        local pTitle = PROTOCOL_TITLES[level] or ""

        -- 降级闪烁
        local dt = context.dt or (1.0 / 60.0)
        if protocolStatus.changed then
            HUD.protocolFlashTimer = 0.8
        end
        if HUD.protocolFlashTimer > 0 then
            HUD.protocolFlashTimer = HUD.protocolFlashTimer - dt
        end

        -- 分隔线
        nvgBeginPath(vg)
        nvgMoveTo(vg, contentX, curY)
        nvgLineTo(vg, contentX + sb.w - pad * 2, curY)
        nvgStrokeColor(vg, nvgRGBA(60, 80, 110, 100))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        curY = curY + 8

        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(160, 170, 190, 220))
        nvgText(vg, contentX, curY, "协议等级")

        -- 等级数字(右侧对齐)
        local numScale = 1.0
        if HUD.protocolFlashTimer > 0 then
            numScale = 1.0 + 0.2 * math.abs(math.sin(HUD.protocolFlashTimer * 8))
        end
        nvgFontSize(vg, 22 * numScale)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(pColor[1], pColor[2], pColor[3], 255))
        nvgText(vg, contentX + sb.w - pad * 2, curY - 4, tostring(level))

        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        curY = curY + 16

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(pColor[1], pColor[2], pColor[3], 200))
        nvgText(vg, contentX, curY, pTitle)
        curY = curY + 16

        nvgFillColor(vg, nvgRGBA(160, 170, 190, 160))
        nvgText(vg, contentX, curY, PROTOCOL_DESCS[level] or "")
        curY = curY + 18
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
    local level = protocolStatus.level or 5
    local color = PROTOCOL_COLORS[level] or { 180, 180, 180 }

    -- 降级闪烁
    if protocolStatus.changed then
        HUD.protocolFlashTimer = 0.8
    end
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
    drawPanel(vg, p.x, p.y, p.w, p.h, 220)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(160, 170, 190, 220))
    nvgText(vg, p.x + p.w / 2, p.y + 8, "54321 协议")

    -- 大号等级数字
    local numScale = 1.0
    if HUD.protocolFlashTimer > 0 then
        numScale = 1.0 + 0.3 * math.abs(math.sin(HUD.protocolFlashTimer * 8))
    end
    nvgFontSize(vg, 32 * numScale)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 255))
    nvgText(vg, p.x + p.w / 2, p.y + 44, tostring(level))

    -- 阶段名称
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
    nvgText(vg, p.x + p.w / 2, p.y + 64, PROTOCOL_TITLES[level] or "")

    -- 短描述
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(160, 170, 190, 180))
    nvgText(vg, p.x + p.w / 2, p.y + 80, PROTOCOL_DESCS[level] or "")
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
    drawPanel(vg, b.x, b.y, b.w, b.h, 210)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 中央: 当前交互提示
    local hint = context.interactHint or ""
    if hint ~= "" then
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 240, 180, 255))
        nvgText(vg, b.x + b.w / 2, b.y + b.h / 2 - 8, hint)
    end

    -- 底部次要操作
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(140, 150, 170, 180))
    nvgText(vg, b.x + b.w / 2, b.y + b.h / 2 + 12, "WASD:移动  M:地图  F:搜索/攻击  E:撤离  T:事件")

    -- 右侧: 撤离距离
    if context.exitDistance then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(100, 255, 150, 230))
        local dirText = context.exitDirection or ""
        nvgText(vg, b.x + b.w - 14, b.y + b.h / 2,
            "撤离点 " .. dirText .. " 距离 " .. context.exitDistance)
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
        return "[E] 启动撤离信标"
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
        return "异常体已清理"
    end
    if context.canTrade then
        if context.eventName then
            return "[T] 事件: " .. context.eventName
        end
        return "[T] 交易: 1零件换金币"
    end
    if context.tradeUnavailable then
        return "旅商需要 1 个零件"
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
        return "[F] 开启未登记物资箱"
    end
    if searchState.canSearch then
        return "[F] 搜索可回收物"
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
