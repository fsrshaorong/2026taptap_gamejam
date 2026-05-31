-- ============================================================================
-- GameText.lua
-- P0 player-facing text for 灰尾回收.
-- Keep this file lightweight: menu / HUD / tutorial / room / event / settlement text only.
-- ============================================================================

local GameText = {}

GameText.title = "灰尾回收"
GameText.subtitle = "扫雷、搜刮，然后尽量完整地撤离。"

GameText.menu = {
    title = "灰尾回收",
    subtitle = "扫雷、搜刮，然后尽量完整地撤离。",
    start = "接受工单",
    tutorial = "新员工说明",
    standardRun = "标准工单",
    judgeRun = "展示工单",
    deploy = "出勤配置",
    requisition = "后勤申领",
    talents = "回收资历",
    warehouse = "后勤仓库",
    settings = "调整终端",
    gm = "调试终端",
    exit = "下班",

    standardDesc = "进入封锁区，完成回收、避险与撤离。收益归你，风险也归你。",
    judgeDesc = "使用固定区域结构，适合快速了解核心流程。公司保证流程完整，不保证员工感受。"
}

GameText.protocol = {
    panelTitle = "调度台 A-7",
    levels = {
        [5] = {
            title = "协议 5",
            short = "正常作业",
            desc = "区域稳定，允许回收。"
        },
        [4] = {
            title = "协议 4",
            short = "轻度警戒",
            desc = "读数上升。保持判断。"
        },
        [3] = {
            title = "协议 3",
            short = "风险作业",
            desc = "高收益区，高事故区。"
        },
        [2] = {
            title = "协议 2",
            short = "返程建议",
            desc = "信标仍在服务中，暂时。"
        },
        [1] = {
            title = "协议 1",
            short = "最终建议",
            desc = "撤离是建议，不撤离是选择。"
        },
    },

    downgrade = "调度台 A-7：协议下降至 ",
    broadcasts = {
        [5] = "调度台 A-7：协议 5。区域读数稳定，继续作业。",
        [4] = "调度台 A-7：协议 4。异常读数上升，请保持职业判断。",
        [3] = "调度台 A-7：协议 3。继续深入将提高收益，也提高事故概率。本条为非强制性建议。",
        [2] = "调度台 A-7：协议 2。建议返程。建议不是命令，但也不是玩笑。",
        [1] = "调度台 A-7：协议 1。撤离是建议。不撤离是自主选择。相关条款已说明。"
    },

    shortPool = {
        "协议下降。",
        "封锁压力上升。",
        "区域读数恶化。",
        "撤离建议已更新。",
        "协议下降一级。这不是命令，这是风险告知。",
        "建议返程。建议不是命令，但也不是玩笑。",
        "公司已尽到提醒义务。剩余义务由员工自行承担。",
        "你已进入高收益区。高事故区。这两个区域通常是同一个。",
        "撤离信标仍在服务中。它不会等你，只是暂时还没走。"
    }
}

GameText.hud = {
    mapTitle = "区域扫描图",
    minesweeperRule1 = "数字 = 周围8格雷险",
    minesweeperRule2 = "异常体/物资/事件/信标不计入",
    hp = "生命",
    power = "战斗力: ",
    pendingGold = "待结算: ",
    safeGold = "已锁定: ",
    parts = "回收物: ",
    bag = "回收包 ",
    explored = "已探索 ",
    protocol = "撤离协议",
    targetTitle = "目标:",
    target = "找到撤离信标",
    nearbyDanger = "周围雷险: ",
    controls = "WASD:移动 M:地图 F:搜索/攻击 E:撤离 T:事件",
    consumable = "消耗品",
    temporaryState = "临时状态"
}

GameText.room = {
    stable = "扫描完成。该区域暂无特殊目标。",
    stableAgain = "已记录区域。",
    stableTip = "安全不代表有钱。很遗憾。",

    mine = "雷险触发！",
    mineDamage = "检测到工伤。当前仍可继续作业。",
    mineConfirmed = "已确认雷险。再次经过不会重复触发。",
    mineMarked = "雷险已确认。",

    monster = "检测到异常体活动。可绕行，可清理。",
    monsterCombat = "躲开预警范围，或靠近后按 F 攻击。",
    monsterCleared = "异常体已清理。区域风险下降。",
    monsterActive = "异常体仍在活动。它看起来没有下班的意思。",

    chest = "发现未登记物资箱。按 F 开启。",
    chestOpened = "物资箱已开启。",
    chestEmpty = "箱子已经空了。后勤部对此深表遗憾。",

    event = "检测到异常事件点。按 T 处理事件。",
    eventNoChest = "事件房没有物资箱，按 T 处理事件。",

    trader = "检测到非公司交易对象。按 T 与旅商交易。",
    traderAgain = "旅商仍在假装合法经营。",

    exit = "撤离信标已接入。按 E 打开撤离确认。",
    hiddenExit = "发现隐藏撤离信标。按 E 打开撤离确认。",
    exitAgain = "信标仍可用。是否结束本次作业？",

    search = "发现可回收物。按 F 搜索。",
    searched = "该区域已搜索。"
}

GameText.interact = {
    generic = "按 E 交互",
    exit = "[E] 打开撤离确认",
    enemy = "[F] 攻击异常体",
    event = "[T] 处理事件: ",
    eventDone = "[T] 查看: 事件已完成",
    chest = "[F] 开启物资箱",
    search = "[F] 搜索可回收物",
    searched = "该区域已搜索",
    chestOpened = "物资箱已开启",
    trader = "[T] 与旅商交易",
    dice = "[T] 与赌徒交涉",
    altar = "[T] 查看祭坛",
    trap = "[T] 处理机关",
    cannotTeleport = "当前状态无法回传",
    combatNoTeleport = "异常体活动中，无法回传",
    unexplored = "该区域尚未探索",
    scannedOnly = "已扫描，但尚未实地确认",
    bagFull = "回收包空间不足",
    resourceNotEnough = "结算币不足",
    done = "已完成",
    cleared = "已清理"
}

GameText.events = {
    trader = {
        name = "狐狸旅商",
        enter = "检测到非公司交易对象。按 T 与旅商交易。",
        intro = "本轮可出售 1 件异常回收物。出售收益将作为已锁定收益保留。",
        done = "旅商收摊了。公司暂未记录此事。",
        sellLabel = "出售一件异常回收物",
        sellFormat = "%s｜估值 %d｜出售价 %d",
        noItem = "异常回收物不足。你不能出售空气，至少今天不行。",
        success = "交易完成。公司不会知道，大概。",
        leave = "结束交易"
    },

    dice = {
        name = "赌徒区",
        enter = "赌徒把骰盅推到你面前。按 T 下注。",
        intro = "下注 20 待结算币。1-4 亏损，5 小赢，6 大赢。收益不会立即入账。",
        done = "赌徒已经离开。",
        label = "下注 20 待结算币",
        disabled = "待结算币不足。狐狸不会借，赌徒也不会。",
        lose = "骰点 %d。下注失败，待结算 -20。",
        smallWin = "骰点 5。小赢一把，待结算 +20。",
        bigWin = "骰点 6。大赢一把，待结算 +60。"
    },

    altar = {
        name = "祭坛区",
        enter = "祭坛仍在低声运转。按 T 献祭生命。",
        intro = "生命消耗逐次增加，奖励也会递增。不会额外增加协议压力。",
        done = "祭坛沉默了。",
        label = "献祭生命",
        continueLabel = "继续献祭",
        leave = "停止献祭",
        disabled = "当前生命不足，祭坛拒收。",
        success = "祭坛响应：生命 -%d，待结算 +%d，异常回收物 +1。",
        maxed = "祭坛已完成全部回应。"
    },

    trap = {
        name = "机关房",
        enter = "机关房的旧装置还在咬合。按 T 尝试处理。",
        intro = "尝试处理旧机关。失败可能造成生命损失或协议压力上升。",
        done = "机关已经停机。",
        label = "处理机关",
        risk = "失败：生命损失 / 协议压力上升"
    }
}

GameText.tutorial = {
    click = "(点击继续)",
    waitMove = "[ 等待移动... ]",
    waitMap = "[ 等待打开地图... ]",
    waitFlag = "[ 等待标记雷险... ]",
    waitCloseMap = "[ 等待关闭地图... ]",
    waitSearch = "[ 等待搜索... ]",

    steps = {
        "欢迎入职灰尾回收。调度台 A-7 已接入。",
        "你是封锁区临时回收员。进入区域，搜刮物资，找到撤离信标。",
        "使用 WASD 或方向键移动。你只能通过上下左右出口进入相邻区域。",
        "数字表示周围 8 个区域中的雷险数量，斜向区域也会计入。",
        "斜向区域只参与雷险计算，不能直接通行。",
        "异常体、物资、事件和撤离信标不计入数字。",
        "数字 0 表示周围暂无雷险。数字越大，越需要谨慎推理。",
        "怀疑某格是雷险时，可以在地图上插旗标记。",
        "按 M 打开区域扫描图，查看已经扫描过的区域。",
        "地图上的数字同样遵守扫雷规则。",
        "在地图上点击一个格子，给它标记雷险。",
        "标记完成。再次点击可以取消标记。",
        "关闭地图继续探索。按 M 或 ESC 关闭。",
        "看到可回收物或物资箱时，按 F 搜索或开启。",
        "搜索会获得待结算币和回收物。成功撤离后才会真正入账。",
        "雷险区会造成伤害；已触发雷险会被标记，再次经过不会重复触发。",
        "遇到异常体时，靠近后按 F 攻击；也可以直接绕开。",
        "找到撤离信标后按 E 撤离。活着带回去才算完成任务。",
        "探索未知区域会提高封锁压力。五四三二一撤离协议下降时，建议考虑返程。",
        "公司不会替你做决定。合同会。",
        "教程结束。灰尾回收祝你平安返程。"
    }
}

GameText.rewards = {
    pendingGold = "待结算 +%d",
    safeGold = "已锁定 +%d",
    settlementGold = "结算币 +%d",
    item = "发现异常回收物：%s",
    highValueItem = "发现高价值异常回收物：%s",
    uniqueItem = "档案级回收物已登记：%s",
    consumable = "获得作业消耗品：%s",
    equipment = "获得作业装备：%s",
    temporaryState = "获得临时状态：%s",
    noLoot = "没有发现可带走的东西。后勤部对此深表遗憾。"
}

GameText.extraction = {
    title = "撤离信标已接入",
    desc = "结束本次作业并结算当前收益。成功撤离后，待结算币、已锁定收益与异常回收物将带回后勤仓库。",
    confirm = "结束作业",
    cancel = "再捡一点",
    expected = "预计入账结算币",
    pending = "待结算收益",
    safe = "已锁定收益",
    items = "异常回收物",
    protocol = "当前撤离协议"
}

GameText.settlement = {
    extractConfirm = "撤离信标已接入",

    success = "作业完成",
    successDesc = "你带回了物资，也带回了自己。",
    successGold = "结算币入账",
    successItems = "带回异常回收物",

    failure = "信号中断",
    failureReason = "回收员失联。",
    failureDesc = "公司正在努力把这解释为流程问题。",
    pending = "待结算币",
    safe = "已锁定收益",
    lost = "已丢失",
    kept = "已保留",
    salvaged = "抢救条款已自动带回",
    lostItems = "遗失物资",

    accept = "接受结算",
    newRun = "接受新工单",
    back = "返回调度台",
    shop = "前往后勤申领"
}

GameText.meta = {
    account = "后勤账户：结算币 ",
    requisition = "后勤申领",
    warehouse = "后勤仓库",
    talents = "回收资历",
    permitRecord = "作业许可记录",
    loadout = "出勤配置",
    recovery = "回收档案",
    gold = "结算币",
    sell = "出售异常回收物，获得结算币",
    uniqueWarning = "这是唯一回收物。出售后可能无法再次获得。",
    appraise = "后勤部正在估价。请不要晃动它。"
}

-- ============================================================================
-- 固定坐标教程弹窗定义
-- ============================================================================

GameText.tutorial.popupDefs = {
    spawn_intro = {
        title = "新员工说明",
        body = table.concat({
            "欢迎入职灰尾回收。",
            "",
            "你是封锁区临时回收员。",
            "本次目标是读取区域扫描图，",
            "避开雷险，搜刮物资，",
            "并找到撤离信标。",
            "",
            "调度台 A-7：",
            "公司建议你带回物资。",
            "更建议你带回自己。"
        }, "\n"),
        blocking = true,
        once = true,
        roomScoped = false,
        confirmText = "开始作业",
    },

    number_rule = {
        title = "区域扫描图",
        body = table.concat({
            "房间数字表示周围 8 个区域中的",
            "雷险数量。",
            "",
            "上下左右和斜向都会计入数字。",
            "异常体、物资、事件和撤离信标",
            "不计入该数字。",
            "",
            "调度台 A-7：",
            "数字通常不会骗人。",
            "公司系统另行计算。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
    },

    mine_rule = {
        title = "雷险区",
        body = table.concat({
            "雷险区会造成伤害，",
            "并提高封锁压力。",
            "",
            "封锁压力升高时，",
            "五四三二一撤离协议可能下降。",
            "",
            "已触发的雷险会被记录，",
            "再次经过不会重复触发。",
            "",
            "调度台 A-7：",
            "协议下降不是惩罚。",
            "只是公司提前声明提醒过你。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
        showAfterRoomEffect = true,
    },

    event_rule = {
        title = "狐狸旅商",
        body = table.concat({
            "旅商可以将异常回收物",
            "折价出售为已锁定收益。",
            "",
            "已锁定收益即使作业失败",
            "也会保留。",
            "",
            "调度台 A-7：",
            "公司不会知道，大概。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
    },

    monster_rule = {
        title = "异常体区域",
        body = table.concat({
            "异常体区域可以绕行，",
            "也可以清理。",
            "",
            "靠近后按 F 攻击。",
            "清理异常体会获得奖励，",
            "但也会提高封锁压力。",
            "",
            "调度台 A-7：",
            "高收益区和高事故区",
            "通常是同一个地方。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
    },

    chest_rule = {
        title = "物资箱",
        body = table.concat({
            "发现物资箱时，按 F 开启。",
            "",
            "物资箱通常比普通搜索",
            "更有价值，",
            "但收益仍需成功撤离后结算。",
            "",
            "调度台 A-7：",
            "箱子归你，风险也归你。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
    },

    map_rule = {
        title = "区域扫描图操作",
        body = table.concat({
            "按 M 打开区域扫描图。",
            "",
            "你可以查看已探索区域，",
            "也可以标记怀疑存在雷险的位置。",
            "",
            "点击已探索区域，",
            "可以回传到对应房间。",
            "",
            "调度台 A-7：",
            "回头不是失败。失联才是。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
    },

    mine_review = {
        title = "雷险复查",
        body = table.concat({
            "再次遇到雷险时，",
            "先观察周围数字。",
            "",
            "如果路线风险过高，",
            "可以打开区域扫描图重新规划，",
            "或回传到已探索区域。",
            "",
            "调度台 A-7：",
            "第二次踩中同类风险时，",
            "系统会将其归类为经验不足。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
        showAfterRoomEffect = true,
    },

    route_rule = {
        title = "路线规划",
        body = table.concat({
            "区域扫描图可以帮助你",
            "重新规划路线。",
            "",
            "已探索区域可以点击回传，",
            "适合在协议下降后调整路径。",
            "",
            "调度台 A-7：",
            "合理返程不影响绩效。",
            "失联会。"
        }, "\n"),
        blocking = false,
        once = false,
        roomScoped = true,
    },

    exit_goal = {
        title = "撤离信标",
        body = table.concat({
            "到达撤离信标后，",
            "按 E 打开撤离确认。",
            "",
            "成功撤离会结算待结算收益，",
            "并带回回收包中的异常回收物。",
            "",
            "五四三二一撤离协议",
            "表示当前封锁区风险。",
            "协议数字越低，",
            "调度台越不建议继续深入。",
            "",
            "调度台 A-7：",
            "撤离是建议。",
            "不撤离是自主选择。",
            "相关条款已说明。"
        }, "\n"),
        blocking = true,
        once = true,
        roomScoped = false,
        confirmText = "我知道了",
    },
}

return GameText
