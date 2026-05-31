-- ============================================================================
-- Tutorial.lua - 新手教程系统（固定坐标弹窗版）
-- 教程地图完全固定，由玩家当前所在房间坐标决定展示哪条教程提示。
-- ============================================================================

local GameText = require("systems.GameText")

local Tutorial = {}

-- ============================================================================
-- 状态字段
-- ============================================================================

Tutorial.active = false
Tutorial.currentRoomKey = nil
Tutorial.activePopup = nil
Tutorial.activePopupId = nil
Tutorial.lockInput = false
Tutorial.shown = {}         -- once=true 的弹窗是否已展示
Tutorial.pendingPopup = nil -- showAfterRoomEffect=true 时延迟展示

-- ============================================================================
-- 坐标到弹窗 ID 映射（5x5 教程地图，1-based 坐标）
-- ============================================================================

Tutorial.roomPopups = {
    -- 出生点
    ["1,1"] = "spawn_intro",

    -- 安全格：教数字规则
    ["1,2"] = "number_rule",
    ["2,1"] = "number_rule",

    -- 雷险格：教雷险
    ["1,3"] = "mine_rule",
    ["2,2"] = "mine_rule",
    ["3,1"] = "mine_rule",

    -- 事件格：教 T 交互
    ["1,4"] = "event_rule",
    ["2,3"] = "event_rule",
    ["3,2"] = "event_rule",
    ["4,1"] = "event_rule",

    -- 异常体格
    ["1,5"] = "monster_rule",
    ["2,4"] = "monster_rule",
    ["3,3"] = "monster_rule",
    ["4,2"] = "monster_rule",
    ["5,1"] = "monster_rule",

    -- 物资箱格
    ["2,5"] = "chest_rule",
    ["3,4"] = "chest_rule",
    ["4,3"] = "chest_rule",
    ["5,2"] = "chest_rule",

    -- 小地图操作提示
    ["3,5"] = "map_rule",
    ["5,3"] = "map_rule",

    -- 雷险复查（第4条斜线中的雷房）
    ["4,4"] = "mine_review",

    -- 路线规划
    ["4,5"] = "route_rule",
    ["5,4"] = "route_rule",

    -- 撤离点
    ["5,5"] = "exit_goal",
}

-- ============================================================================
-- 工具函数
-- ============================================================================

local function MakeRoomKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function GetPopupDef(popupId)
    if not popupId then return nil end
    local defs = GameText.tutorial and GameText.tutorial.popupDefs
    if defs and defs[popupId] then
        return defs[popupId]
    end
    return nil
end

-- ============================================================================
-- 核心接口
-- ============================================================================

function Tutorial.Reset()
    Tutorial.active = false
    Tutorial.currentRoomKey = nil
    Tutorial.activePopup = nil
    Tutorial.activePopupId = nil
    Tutorial.lockInput = false
    Tutorial.shown = {}
    Tutorial.pendingPopup = nil
end

function Tutorial.Start()
    Tutorial.active = true
    Tutorial.currentRoomKey = nil
    Tutorial.activePopup = nil
    Tutorial.activePopupId = nil
    Tutorial.lockInput = false
    Tutorial.shown = {}
    Tutorial.pendingPopup = nil
end

function Tutorial.Stop()
    Tutorial.active = false
    Tutorial.currentRoomKey = nil
    Tutorial.activePopup = nil
    Tutorial.activePopupId = nil
    Tutorial.lockInput = false
    Tutorial.pendingPopup = nil
end

function Tutorial.IsActive()
    return Tutorial.active
end

-- ============================================================================
-- 房间进入/离开
-- ============================================================================

--- 玩家进入房间时调用（移动或传送后）
---@param x number 1-based 教程坐标
---@param y number 1-based 教程坐标
---@param room any 房间数据（保留兼容，当前未使用）
---@param reason string|nil "move"|"teleport"|"spawn"
function Tutorial.OnEnterRoom(x, y, room, reason)
    if not Tutorial.active then return end

    local key = MakeRoomKey(x, y)

    -- 同一房间重复调用，不重复刷新
    if Tutorial.currentRoomKey == key then return end

    -- 切房时清掉旧的 roomScoped 提示
    Tutorial.OnLeaveRoom()

    Tutorial.currentRoomKey = key

    local popupId = Tutorial.roomPopups[key]
    if not popupId then
        Tutorial.activePopup = nil
        Tutorial.activePopupId = nil
        Tutorial.lockInput = false
        return
    end

    local popup = GetPopupDef(popupId)
    if not popup then
        Tutorial.activePopup = nil
        Tutorial.activePopupId = nil
        Tutorial.lockInput = false
        return
    end

    -- once=true 且已展示过，不再显示
    if popup.once and Tutorial.shown[popupId] then
        Tutorial.activePopup = nil
        Tutorial.activePopupId = nil
        Tutorial.lockInput = false
        return
    end

    -- showAfterRoomEffect: 延迟到房间效果结算后
    if popup.showAfterRoomEffect then
        Tutorial.pendingPopup = { id = popupId, popup = popup }
        Tutorial.activePopup = nil
        Tutorial.activePopupId = nil
        Tutorial.lockInput = false
        return
    end

    Tutorial.ShowPopup(popupId, popup)
end

--- 离开房间时调用（内部在 OnEnterRoom 中自动调用）
function Tutorial.OnLeaveRoom()
    if Tutorial.pendingPopup then
        Tutorial.pendingPopup = nil
    end

    if Tutorial.activePopup and Tutorial.activePopup.roomScoped then
        Tutorial.activePopup = nil
        Tutorial.activePopupId = nil
    end

    if not Tutorial.activePopup or not Tutorial.activePopup.blocking then
        Tutorial.lockInput = false
    end
end

--- 房间效果结算后调用（如踩雷伤害处理完毕后）
function Tutorial.FlushPendingPopup()
    if not Tutorial.active then return end
    if not Tutorial.pendingPopup then return end

    local pending = Tutorial.pendingPopup
    Tutorial.pendingPopup = nil
    Tutorial.ShowPopup(pending.id, pending.popup)
end

-- ============================================================================
-- 弹窗显示/确认
-- ============================================================================

function Tutorial.ShowPopup(popupId, popup)
    Tutorial.activePopupId = popupId
    Tutorial.activePopup = popup
    if popup.blocking then
        Tutorial.lockInput = true
    else
        Tutorial.lockInput = false
    end
end

--- 确认当前阻塞弹窗
function Tutorial.ConfirmPopup()
    if not Tutorial.activePopup then return end

    if Tutorial.activePopup.once and Tutorial.activePopupId then
        Tutorial.shown[Tutorial.activePopupId] = true
    end

    Tutorial.activePopup = nil
    Tutorial.activePopupId = nil
    Tutorial.lockInput = false
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function Tutorial.IsInputLocked()
    return Tutorial.active and Tutorial.lockInput == true
end

function Tutorial.HasBlockingPopup()
    return Tutorial.activePopup ~= nil and Tutorial.activePopup.blocking == true
end

function Tutorial.HasPopup()
    return Tutorial.activePopup ~= nil
end

function Tutorial.GetActivePopup()
    return Tutorial.activePopup
end

function Tutorial.GetActivePopupId()
    return Tutorial.activePopupId
end

-- ============================================================================
-- 旧接口兼容（no-op，防止 main.lua 旧调用崩溃）
-- ============================================================================

function Tutorial.NotifyAction(actionName)
    -- Legacy no-op: fixed-room tutorial no longer depends on action gates.
end

function Tutorial.HandleClick()
    -- Legacy no-op: replaced by ConfirmPopup().
    return false
end

function Tutorial.GetCurrentStep()
    -- Legacy: 返回 activePopup 的兼容格式
    if Tutorial.activePopup then
        return {
            text = Tutorial.activePopup.title or "",
            subtext = Tutorial.activePopup.blocking and (Tutorial.activePopup.confirmText or "Enter / Space / 点击 继续") or "",
            type = Tutorial.activePopup.blocking and "dialog" or "info",
        }
    end
    return nil
end

--- 兼容旧 Update/Draw/KeyPressed 接口
function Tutorial.Update(dt) end
function Tutorial.Draw(vg) end
function Tutorial.KeyPressed(key) end
function Tutorial.OnMove() end
function Tutorial.OnMapOpened() end
function Tutorial.OnFlagPlaced() end
function Tutorial.OnSearch() end
function Tutorial.OnAttack() end

-- ============================================================================
-- 教程地图配置（保持不变）
-- ============================================================================

--- 教程专用地图配置(5x5小地图,固定布局,安全体验)
---@return table 传给 StartNewGame 的 override 参数
function Tutorial.GetMapConfig()
    return {
        mode = "tutorial",
        width = 5,
        height = 5,
        mineCount = 4,
        spawnSafeRadius = 1,
        pathWidth = 0,
        randomExitCount = 0,
        maxMonsterRooms = 5,
        maxChestRooms = 4,
        maxEventRooms = 4,
        minMonsterRooms = 5,
        minChestRooms = 4,
        minEventRooms = 4,
        mineHitsAreFatal = false,
        revealOnMove = true,
        moveRequiresRevealed = false,
        seed = 777,
        manualMap = {
            width = 5,
            height = 5,
            spawn = { x = 1, y = 1 },
            mines = {
                { x = 1, y = 3 }, { x = 2, y = 2 }, { x = 3, y = 1 },
                { x = 4, y = 4 },
            },
            events = {
                { x = 1, y = 4 }, { x = 2, y = 3 }, { x = 3, y = 2 }, { x = 4, y = 1 },
            },
            monsters = {
                { x = 1, y = 5 }, { x = 2, y = 4 }, { x = 3, y = 3 }, { x = 4, y = 2 }, { x = 5, y = 1 },
            },
            chests = {
                { x = 2, y = 5 }, { x = 3, y = 4 }, { x = 4, y = 3 }, { x = 5, y = 2 },
            },
            exits = {
                { id = "tutorial_exit", x = 5, y = 5 },
            },
        },
    }
end

return Tutorial
