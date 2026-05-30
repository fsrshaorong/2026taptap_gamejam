-- ============================================================================
-- GameText.lua
-- P0 player-facing text used by the design-integration pass.
-- ============================================================================

local GameText = {}

GameText.title = "灰尾回收"

GameText.protocol = {
    panelTitle = "调度台 A-7",
    levels = {
        [5] = { title = "协议 5", short = "稳定作业", desc = "信号稳定，继续回收。" },
        [4] = { title = "协议 4", short = "轻度偏移", desc = "异常读数上升，注意路线。" },
        [3] = { title = "协议 3", short = "风险作业", desc = "调度建议准备撤离。" },
        [2] = { title = "协议 2", short = "强制返程", desc = "撤离窗口正在收窄。" },
        [1] = { title = "协议 1", short = "立即撤离", desc = "调度台 A-7 要求返程。" },
    },
    downgrade = "调度台 A-7: 协议降至 ",
}

GameText.hud = {
    mapTitle = "区域扫描图",
    minesweeperRule1 = "数字 = 周围8格雷险",
    minesweeperRule2 = "特殊房不计入数字",
    hp = "生命",
    power = "战力: ",
    pendingGold = "待结算币: ",
    safeGold = "已锁定: ",
    parts = "回收物: ",
    bag = "回收包 ",
    explored = "已探索 ",
    targetTitle = "目标:",
    target = "回收物资，前往撤离信标",
    nearbyDanger = "附近雷险: ",
    controls = "WASD:移动  M:地图  F:搜索/攻击  E:撤离  T:事件",
}

GameText.room = {
    stable = "稳定区。继续前进或查看地图。",
    mine = "雷险触发！",
    monster = "检测到异常体活动。靠近后按 F 攻击，也可以绕行。",
    chest = "发现未登记物资箱。按 F 开启。",
    chestOpened = "物资箱已开启。",
    searched = "该区域已搜索。",
    eventNoChest = "事件房没有宝箱，按 T 处理事件。",
    exit = "你抵达撤离信标。按 E 撤离。",
    hiddenExit = "发现隐藏撤离信标。按 E 撤离。",
    search = "发现可回收物。按 F 搜索。",
}

GameText.interact = {
    exit = "[E] 启动撤离信标",
    enemy = "[F] 攻击异常体",
    event = "[T] 事件: ",
    eventDone = "[T] 查看: 事件已完成",
    chest = "[F] 开启未登记物资箱",
    search = "[F] 搜索可回收物",
    searched = "该区域已搜索",
    chestOpened = "物资箱已开启",
}

GameText.events = {
    trader = {
        name = "旅商区",
        enter = "旅商把灯压低了些。按 T 出售一件回收物。",
        done = "旅商收摊了。",
        sellLabel = "出售一件回收物",
        noItem = "没有可出售的回收物。",
    },
    dice = {
        name = "赌徒区",
        enter = "赌徒把骰盅推到你面前。按 T 下注。",
        done = "赌徒已经离开。",
    },
    altar = {
        name = "祭坛区",
        enter = "祭坛仍在低声运转。按 T 献祭生命。",
        done = "祭坛沉默了。",
    },
    trap = {
        name = "机关房",
        enter = "机关房的旧装置还在咬合。按 T 尝试处理。",
        done = "机关已经停机。",
    },
}

GameText.tutorial = {
    click = "(点击继续)",
    waitMove = "[ 等待移动... ]",
    waitMap = "[ 等待打开地图... ]",
    waitFlag = "[ 等待插旗... ]",
    waitCloseMap = "[ 等待关闭地图... ]",
    waitSearch = "[ 等待搜索... ]",
    steps = {
        "欢迎来到灰尾回收。调度台 A-7 已接入。",
        "你的任务是进入异常区域，带回回收物，并活着抵达撤离信标。",
        "使用 WASD 或方向键移动。走到门口会进入下一间房。",
        "左侧数字表示周围 8 格里有多少雷险房。",
        "数字 0 表示周围暂无雷险。数字越大，越需要谨慎推理。",
        "怀疑某格是雷险时，可以在地图上插旗标记。",
        "按 M 打开地图，查看已经扫描过的区域。",
        "地图上的数字同样遵守扫雷规则。",
        "在地图上点击一个格子，给它插上旗子。",
        "标记完成。再次点击可以取消旗子。",
        "关闭地图继续探索。按 M 或 ESC 关闭。",
        "看到可回收物或物资箱时，按 F 搜索。",
        "搜索会获得待结算币和回收物。撤离后才会真正入账。",
        "遇到异常体时，靠近后按 F 攻击；也可以直接绕开。",
        "找到撤离信标后按 E 撤离。活着带回去才算完成任务。",
        "探索未知房会增加协议压力。调度台降级时，请考虑返程。",
        "教程结束。灰尾回收祝你平安返程。",
    },
}

GameText.settlement = {
    extractConfirm = "确认撤离",
    success = "撤离成功",
    failure = "撤离失败",
    pending = "待结算币",
    safe = "已锁定",
    lost = "遗失",
    salvaged = "自动带回",
}

return GameText
