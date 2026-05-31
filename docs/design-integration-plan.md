# 接入评估报告：数值与文案一次性接入前判断

> 评估日期：2026-05-31  
> 评估范围：当前仓库可见 Lua/资源/测试/文档，以及用户提供的两份策划案。  
> 策划来源：`D:/WeChat/xwechat_files/wxid_skjcrdpxkw9722_0fab/msg/file/2026-05/数值策划案.txt`、`D:/WeChat/xwechat_files/wxid_skjcrdpxkw9722_0fab/msg/file/2026-05/文案策划案v0.3(1).txt`。  
> 执行边界：本报告只做接入前评估。本次未修改 Lua 功能代码、未替换文案、未改数值、未重构系统。

## 1. 当前工程系统映射

### 地图 / 房间 / 移动

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 地图生成 | `scripts/systems/Minefield.lua` | `Minefield.New`、`Init`、`Generate`、`_GenerateNormal`、`_GenerateManual`、`_AssignSpecialRooms` | 创建网格、出生点、雷房、特殊房、随机撤离点；普通模式按数量/比例分配特殊房，教程/评测模式用手写地图 | 已支持 5x5 手写布局与 10x10 数量配置；本次接入要求不改地图结构、撤离点生成、房间分布 |
| 房间视图 | `scripts/systems/Minefield.lua` | `GetCellView`、`GetVisibleMap` | 控制可见信息：未揭示格不暴露 `roomType`，已揭示后给 HUD/小地图/场景绘制 | 文案接入中的区域提示依赖 `roomType`、`adjacent`、`revealed` |
| 探索/揭示 | `scripts/systems/Minefield.lua` | `Reveal`、`Explore`、`ClearRoom` | 揭示格子、标记 explored、雷房触发后清理状态 | 数值接入中的“探索未知格压力 +2”发生在首次 `Explore` 后 |
| 移动运行 | `scripts/systems/ExtractionRun.lua` | `ExtractionRun.New`、`Move`、`MoveTo`、`CanExtract`、`Extract` | 持有玩家坐标、移动判定、边界/旗标/撤离判定 | 踩雷、撤离确认、失败/成功结算由 `main.lua` 在移动结果上继续处理 |
| 输入与流程 | `scripts/main.lua` | `StartNewGame`、`MovePlayer`、`HandleKeyDown`、`HandleUpdate`、`HandleMouseDown` | 组装 10x10 配置、响应 WASD/方向键/M/F/E/T、触发场景与 HUD 刷新 | 是第二个对话框接入压力、区域提示和文案广播的中心入口 |
| 房间场景 | `scripts/scenes/DungeonRoom.lua` | `Init`、`Draw`、`SetRoomObstacles` | 加载房间背景和道具图、绘制当前房间、玩家、怪物、事件道具、撤离点 | 事件房当前用 `Textures/room_event.png` 加不同事件道具，不是每类事件独立背景 |

### 扫雷数字 / 雷险判定

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 八邻域雷数 | `scripts/systems/Minefield.lua` | `_ComputeAdjacency`、`DIR8` | 只统计 `neighbor.mine`，特殊房不计入数字 | 与 HUD 当前规则“数字 = 周围8格雷险，特殊房不计入数字”一致 |
| 雷房进入 | `scripts/systems/ExtractionRun.lua` | `Move` | 判断目标格是否是 mine，返回 `mine`、`mineAlreadyTriggered` 等状态 | 第二个对话框可在 `main.lua:MovePlayer` 针对 `result.status=="mine"` 增加踩雷压力 |
| 雷伤害 | `scripts/systems/Combat.lua` | `TakeMineHit`、`CONFIG.mineDamage`、`mineDmgReduce`、`mineImmunity` | 当前基础雷伤 25，天赋可减伤，急救包可免疫一次，最小伤害 5 | 目标雷险伤害 30；需评估天赋减伤是否继续保留 |

### HUD 显示

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 左侧栏/协议栏/底栏 | `scripts/ui/HUD.lua` | `ComputeLayout`、`DrawLeftSidebar`、`DrawProtocolPanel`、`DrawBottomBar` | 显示地图、生命、战力、金币、零件、回收包、目标、危险、协议、操作提示 | 需要替换 HUD 文案，并评估是否容纳“待结算币 / 安全结算币 / 回收物” |
| 交互提示 | `scripts/ui/HUD.lua` | `GetInteractHint` | 根据房间类型、搜索状态、敌人、撤离点、事件返回底栏提示 | 可承接稳定区、雷险区、异常体区域、物资区、旅商区、撤离信标区提示 |
| 小地图/大地图 | `scripts/ui/MiniMap.lua`、`scripts/ui/MapOverlay.lua` | `Draw`、`drawRoomIcon` | 绘制格子、数字、旗标、特殊房图标、地图操作提示 | 文案接入涉及大地图标题、操作说明；数值接入通常不碰 |

### 教程文本

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 教程步骤 | `scripts/systems/Tutorial.lua` | `Tutorial.steps`、`Start`、`Advance`、`NotifyAction`、`HandleClick` | 写死教程台词、等待移动/开地图/插旗/搜索等动作 | 需要按《文案策划案v0.3.txt》替换开场教程和扫雷规则说明 |
| 教程地图 | `scripts/systems/Tutorial.lua` | `GetMapConfig` | 5x5 手写地图，左上出生、斜线分布、右下撤离 | 当前已符合最近讨论的 5x5 斜线布局，不建议第二个对话框再改 |
| 教程绘制 | `scripts/ui/HUD.lua` | `DrawTutorialDialog` | 绘制底部教程对话框和 `step.text/subtext` | 长文案有底部面板溢出风险 |
| 教程启动 | `scripts/main.lua` | `StartTutorial`、`StartNewGame`、`HandleMouseDown` | 启动教程局、显示教程对话、完成后返回主菜单 | 若继续修“直接开始探索也有教程”，只应排查状态重置，不应在文案接入中扩功能 |

### 协议压力系统

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 压力状态 | `scripts/systems/Protocol.lua` | `Protocol.level`、`pressure`、`maxPressure`、`THRESHOLDS`、`DESCRIPTIONS` | 压力 0~100 上限、等级 5 到 1、描述“稳定/警戒/压迫/封锁/临界” | 阈值已与目标 0~19/20~39/40~59/60~79/80~100 对齐 |
| 加压 | `scripts/systems/Protocol.lua` | `AddPressure(amount)` | 默认探索 +5，只 clamp 上限 100；到协议 1 返回 `penalty=true` | 目标探索 +2，踩雷 +10，击败怪物 +5，协议 1 不额外扣血 |
| 调用点 | `scripts/main.lua` | `MovePlayer`、`ApplyEventResult` | 首次探索调用 `Protocol.AddPressure()`；事件结果可携带 `pressureDelta` | 第二个对话框需把所有加压来源集中，避免重复加压 |

### 玩家生命 / 攻击力

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 基础属性 | `scripts/systems/Combat.lua` | `Combat.maxHp=100`、`hp=100`、`power=10`、`Reset` | 管理玩家 HP、战力、减伤、免疫 | 目标未要求改基础 HP/攻击，只要求普通搜索不加攻，怪物击败 +1 上限 +5 |
| 伤害 | `scripts/systems/Combat.lua` | `ApplyHpDelta`、`ApplyDamage`、`TakeMineHit`、怪物攻击相关函数 | 统一修改 HP，返回 dead/hp 等 | 协议扣血 bug 已有路径在 `main.lua` 检查 dead；接入时需防止遗漏新扣血路径 |
| 攻击成长 | `scripts/systems/Combat.lua` | `TryPowerUp` | 当前搜索后 20% 概率战力 +3 | 目标改为普通搜索不加，怪物击败 +1，最多 +5 |
| 装备/天赋加成 | `scripts/main.lua`、`scripts/systems/MetaProgress.lua` | `StartNewGame`、`GetEquipBonus`、`GetTalentEffects` | 防护甲 +25 HP、磨刀石 +5 战力、厚皮减雷伤等 | 局外成长价格与收益收束相关，需谨慎 |

### 普通搜索

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 搜索状态 | `scripts/systems/RunInventory.lua` | `GetSearchState`、`CanSearch` | 出生点/撤离点/怪物房/事件房不可搜索；宝箱和普通房可搜索一次 | “事件房取消宝箱”当前已实现：事件房 `reason="event"` 不可搜索 |
| 搜索奖励 | `scripts/systems/RunInventory.lua` | `GetReward`、`buildRewardItems`、`chooseItemId` | 当前普通房金币 `4 + adjacent*2 + roll%6`，45%+ 掉 1 件物品 | 目标普通搜索待结算币 `random(0,2)+floor(周围雷数/2)`，最高 4；掉落表为不掉 55%、低值 35%、普通 8%、稀有 2%、珍贵及以上 0%，高雷数有修正 |
| 搜索入口 | `scripts/main.lua` | `SearchCurrentRoom`、`OpenLootResultPanel` | 执行搜索、加金币/零件/物品、触发宝箱动画、弹结果面板 | 需删除普通搜索加攻调用 `Combat.TryPowerUp` |

### 宝箱奖励

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 宝箱识别 | `scripts/systems/RunInventory.lua` | `GetReward`、`GetSearchState` | `roomType=="chest"` 时可搜索，奖励放大 | 目标宝箱待结算币 `random(3,7)+周围雷数`，最高 11 |
| 宝箱掉落 | `scripts/systems/RunInventory.lua` | `buildRewardItems(isChest=true)`、`chooseItemId` | 宝箱必给 1~3 件，当前表偏高价值 | 目标宝箱必掉 1 件，主表低值 15%、普通 45%、稀有 30%、珍贵 9%、异常 1%；额外掉落：第 2 件低值/普通 25%、消耗品 15%、装备 3% |
| 宝箱表现 | `scripts/scenes/DungeonRoom.lua` | `TriggerChestOpen`、`Draw` | 宝箱开启动画和奖励飘字 | 文案替换时注意“金币/结算币/回收物”不做全局替换 |

### 怪物战斗与怪物奖励

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 怪物生成 | `scripts/systems/Combat.lua` | `TrySpawnEnemy`、`GetEnemy`、`GetEnemyAny` | 怪物房必定生成，普通房不再随机生成 | 与地图 `monster` 房间一一对应 |
| 怪物战斗 | `scripts/systems/Combat.lua` | `PlayerAttackEnemy`、`UpdateEnemy`、`FightEnemy` | 支持即时攻击、怪物攻击、老的强判战斗结果 | 第二个对话框改奖励时要覆盖两个胜利路径 |
| 发奖路径 | `scripts/main.lua`、`scripts/systems/RunInventory.lua` | `CompleteActiveMonsterClear`、`ResolveBattle`、`RunInventory.RecordCombat` | 怪物胜利 result 交给 `RecordCombat` 加金币/零件 | 目标怪物 0~3 待结算币、击败压力 +5、攻击 +1 上限 +5；存在重复发奖风险，需只在 `RecordCombat` 或唯一胜利收口处理 |

### 事件系统：旅商、赌徒、祭坛等

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 事件分配 | `scripts/systems/EventSystem.lua` | `EVENT_TYPES`、`GetEventType` | 事件房懒分配为旅商/赌徒/祭坛/机关，权重 30/25/25/20 | 文案、赌徒、祭坛、旅商售卖规则都在这里接入 |
| 事件选项 | `scripts/systems/EventSystem.lua` | `GetOptions`、`getTraderOptions`、`getDiceOptions`、`getAltarOptions`、`getTrapOptions` | 生成事件面板选项，包含 label/description/cost/reward/risk | 文案集中替换优先级高 |
| 事件执行 | `scripts/systems/EventSystem.lua` | `_ExecTrader`、`_ExecDice`、`_ExecAltar`、`_ExecTrap`、`ExecuteOptionById` | 根据选项返回 `goldDelta/partsDelta/hpDelta/powerDelta/pressureDelta` | 目标旅商售出具体物品 75%、赌徒 20 下注、祭坛递增 HP 均需要改这里 |
| 事件 UI | `scripts/main.lua` | `OpenEventPanel`、`ApplyEventResult`、`DrawEventPanel`、`ConfirmEventOption` | 打开事件面板、应用结果、绘制选项和提示 | 递增祭坛/多次事件会影响是否 `MarkCompleted`、是否关闭面板 |
| 事件画面 | `scripts/scenes/DungeonRoom.lua` | 事件 `evtVisual` 表 | 当前同一事件背景 + 不同道具/颜色/标签 | 若要“看到图里的东西”，优先检查资源路径和事件道具绘制，不属于本次数值文案接入核心 |

### 局内金币 / 零件 / 物品

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 局内货币 | `scripts/systems/RunInventory.lua` | `gold`、`parts`、`GetTotals` | `gold` 当前既当局内即时币，也在失败时安全保留；`parts` 兼具松散零件和物品件数 | 目标需要 pendingGold/safeGold/globalGold 三层语义，当前不够清晰 |
| 局内物品 | `scripts/systems/RunInventory.lua` | `ITEM_DEFS`、`AddCarriedItem`、`GetCarriedItems` | 物品有 `value`、类型、稀有度、描述；进回收包 | 可改名兼容 `baseValue`，但不应破坏现有仓库和测试 |
| 可交易物 | `scripts/systems/RunInventory.lua` | `GetTradableItems`、`RemoveTradableItem` | 当前支持虚拟 `parts` 和具体 `carriedItems` 移除 | 旅商选择具体物品出售具备基础，但 UI 未完全接入 |

### 背包 / 仓库 / 商店 / 局外成长

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 局外金币 | `scripts/systems/MetaProgress.lua` | `GetGold`、`AddGold`、`SpendGold`、`Save`、`Load` | 持久化全局金币 | 结算币最终进入这里；失败是否保留局内币是关键决策 |
| 装备商店 | `scripts/systems/MetaProgress.lua` | `ITEMS`、`BuyItem`、`EquipItem`、`GetEquipBonus` | 当前装备价格 40~100，带入 HP/战力/免疫/罗盘/搜索加成 | 目标装备价格为磨刀石 90、防护背心 110、急救包 120、绝缘套 140、罗盘 160、大背包 220；当前装备效果也与目标不完全一致 |
| 天赋 | `scripts/systems/MetaProgress.lua` | `TALENTS`、`UnlockTalent`、`GetTalentEffects` | 天赋价格 80~120，影响雷伤、怪物逃跑、保险金、议价等 | 需要评估新收益与天赋价格收束 |
| 仓库 | `scripts/systems/MetaProgress.lua` | `AddWarehouseItems`、`GetWarehouseDisplayList`、`SellWarehouseItem` | 成功撤离登记回收物，仓库出售按 full value 入金币 | 目标“旅商出售 75%”不应误伤局外仓库，除非策划明确 |
| 页面 UI | `scripts/main.lua` | `RefreshMenuPage`、`RefreshEquipPage`、`RefreshTalentPage`、`RefreshWarehousePage`、`OnSellWarehouseItem` | 主菜单子页、装备/天赋购买、仓库出售 | 局外文案分散硬编码，第二个对话框适合只替 P0 |

### 成功撤离结算

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 撤离确认 | `scripts/main.lua` | `DoExtract`、`ConfirmExtract`、`CancelExtract` | 在撤离点按 E 显示预计收益，确认后记录局外奖励 | 目标成功结算需明确 pending/safe/回收物入库规则 |
| 奖励计算 | `scripts/systems/RunInventory.lua` | `GetExtractionReward` | `totalGold = RunInventory.gold + looseParts*10`，携带物品入仓库不自动转金币 | 可保留物品入仓库模型，但需改名/文案避免“金币”误导 |
| 持久化 | `scripts/systems/MetaProgress.lua` | `RecordExtractionReward` | 只把 directGold + loosePartsGold 加到全局金币，把 carriedItems 加仓库 | 与三层货币语义接入关联最大 |

### 失败结算

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 失败面板 | `scripts/main.lua` | `ShowFailurePanel`、`ApplyFailureSalvage` | 显示失败原因、保留金币、遗失回收物/零件、可抢救 1 零件 | 目标失败结算要求待结算币丢失、安全结算币保留、背包物资选择 1 件带回；当前 UI 不支持选择物品 |
| 失败规则 | `scripts/systems/RunInventory.lua` | `GetFailureSalvageOptions`、`ApplyFailureSalvage` | 当前金币自动保留，零件/物品丢失，可用 1 零件换 +10 金币 | 可能与目标 pendingGold 失败丢失冲突 |
| 失败入账 | `scripts/main.lua` | `ShowFailurePanel`、`ApplyFailureSalvage` | 给 `MetaProgress.AddGold(finalGold)`，不入仓库 | 当前失败会保留 RunInventory.gold；若目标 pending 失败丢失，则需改 |

### 主菜单 / 结算界面 / 事件弹窗文案

| 项 | 当前文件路径 | 关键函数或表名 | 当前职责 | 与策划案的对应关系 |
|---|---|---|---|---|
| 主菜单 | `scripts/main.lua` | `CreateUI`、`RefreshMenuPage` | 菜单标题、开始/教程/装备/天赋/仓库/GM、统计、金币显示 | 文案集中在 UI 创建和刷新函数 |
| 结算界面 | `scripts/main.lua` | `ShowFailurePanel`、`DoExtract`、`ConfirmExtract`、`CreateUI` 中结算 panel | 成功/失败标题、收益、统计、按钮 | 成功/失败文案 P0；需防 UI 溢出 |
| 事件弹窗 | `scripts/main.lua`、`scripts/systems/EventSystem.lua` | `DrawEventPanel`、`GetOptions`、事件执行函数 | 面板标题、描述、选项、费用、奖励、风险、执行结果 | 事件文案 P0/P1；数值规则改动和文案替换应同批保持一致 |

## 2. 数值接入差异表

| 策划目标 | 当前代码表现 | 当前代码位置 | 修改复杂度 | 破坏可玩闭环风险 | 第二个对话框是否建议直接执行 |
|---|---|---|---|---|---|
| 雷险伤害：30 | 基础雷伤 25，厚皮天赋再减 10，最小 5；急救包可免疫一次 | `scripts/systems/Combat.lua` `CONFIG.mineDamage`、`TakeMineHit` | 低 | 低 | 建议，保留天赋/免疫语义 |
| 探索未知格压力：+2 | 默认 `BASE_EXPLORE_PRESSURE=5` | `scripts/systems/Protocol.lua`、`scripts/main.lua:MovePlayer` | 低 | 低 | 建议 |
| 踩雷压力：+10 | 当前踩雷只扣血、记统计，不加协议压力 | `scripts/main.lua:MovePlayer` mine 分支 | 低 | 中 | 建议，但要防止首次探索同格时叠加规则超预期；默认叠加“探索 + 踩雷” |
| 击败怪物压力：+5 | 当前击败怪物不加协议压力 | `scripts/main.lua:CompleteActiveMonsterClear`、`ResolveBattle`、`RunInventory.RecordCombat` | 中 | 中 | 建议，需放在唯一胜利收口 |
| 压力 clamp：0~100 | 只 clamp 上限 100；当前没有负加压路径 | `scripts/systems/Protocol.lua:AddPressure` | 低 | 低 | 建议补全下限 0 |
| 协议阈值：0~19 / 20~39 / 40~59 / 60~79 / 80~100 | 已等价：0=>5、20=>4、40=>3、60=>2、80=>1 | `scripts/systems/Protocol.lua` `THRESHOLDS` | 低 | 低 | 不需要改，只建议加测试说明 |
| 协议 1 不额外扣血 | 当前 `AddPressure` 到 level 1 返回 `penalty=true`，`main.lua` 探索未知房时 `Combat.ApplyDamage(1)` | `scripts/systems/Protocol.lua:AddPressure`、`scripts/main.lua:MovePlayer` | 低 | 中 | 建议删除/关闭；注意保留协议广播 |
| 普通搜索不加攻击 | 当前搜索后调用 `Combat.TryPowerUp`，20% 概率 +3 | `scripts/main.lua:SearchCurrentRoom`、`scripts/systems/Combat.lua:TryPowerUp` | 低 | 低 | 建议 |
| 击败怪物攻击力成长：+1，上限 +5 | 当前怪物击败只给金币/零件；无击杀成长；搜索才加攻 | `scripts/systems/Combat.lua`、`scripts/main.lua` 战斗胜利路径 | 中 | 中 | 建议，需新增本局击杀成长计数或在 Combat 中 clamp |
| 普通搜索待结算币：`random(0,2)+floor(周围雷数/2)`，最高 4 | 当前金币 `4 + adjacent*2 + roll%6`，最小 4、上限远高于目标 | `scripts/systems/RunInventory.lua:GetReward` | 中 | 中 | 建议，但需要先落实 pendingGold 命名 |
| 宝箱待结算币：`random(3,7)+周围雷数`，最高 11 | 当前先普通公式，再宝箱 `gold = gold*2 + 16`，收益远高于目标 | `scripts/systems/RunInventory.lua:GetReward` | 中 | 中 | 建议 |
| 怪物金币：0~3 待结算币 | 当前 `12 + enemyPower*1`，高战力额外 1 零件 | `scripts/systems/Combat.lua:makeReward` | 低 | 中 | 建议，与击杀成长同批 |
| 普通搜索掉落表 | 当前普通房 45%+ 掉 1 件，表：断裂铜线/暗淡电容/静电透镜/黑匣标签/低语灯芯；没有品质概率层 | `scripts/systems/RunInventory.lua:chooseItemId`、`buildRewardItems` | 中 | 中 | 建议，但可先用现有物品映射到低值/普通/稀有 |
| 宝箱掉落表 | 当前宝箱必给 1~3 件，表：暗淡电容/黑匣标签/静电透镜/低语灯芯/封存核心碎片；无珍贵/异常品质 | 同上 | 中 | 中 | 建议，但珍贵/异常/装备/消耗品若资产不足需降级映射 |
| 旅商出售：`floor(baseValue * 0.75)` | 当前卖虚拟 `parts`，价格 15/20；已支持具体 carried item 移除但 UI/价格未接 | `scripts/systems/EventSystem.lua:_ExecTrader`、`scripts/systems/RunInventory.lua:RemoveTradableItem` | 中 | 中 | 建议接，但需明确只影响局内旅商 |
| 赌徒规则：20 待结算币下注，1~4 输，5 净赚 20，6 净赚 60 | 当前 10 下注，4/5/6 赢，净 +10；1/2/3 输 -10 | `scripts/systems/EventSystem.lua:DICE_*`、`_ExecDice` | 低 | 低 | 建议 |
| 祭坛规则：10 / 15 / 25 / 35 / 50 HP 递增消耗 | 当前一次性事件：献祭 1 HP，得 15 金币 +1 回收物，压力 +5，完成后关闭 | `scripts/systems/EventSystem.lua:ALTAR_*`、`_ExecAltar` | 中 | 中 | 建议；目标奖励为 +2/+5/+8/+10/+15 待结算币和低值/普通/稀有/珍贵/异常递增物品，且不额外加压力 |
| 成功结算 | 当前 directGold + looseParts*10 入全局金币，携带物入仓库不折金币 | `scripts/systems/RunInventory.lua:GetExtractionReward`、`scripts/systems/MetaProgress.lua:RecordExtractionReward` | 中 | 高 | 建议；目标为待结算币 100% 转全局、安全币保留、背包物资全部入仓库 |
| 失败结算 | 当前 RunInventory.gold 自动保留入全局金币，零件/回收物丢失，可抢救 1 零件 +10 | `scripts/systems/RunInventory.lua:GetFailureSalvageOptions`、`scripts/main.lua:ShowFailurePanel` | 中 | 高 | 建议；目标为待结算币丢失、安全币保留、背包物资选择 1 件带回；UI 来不及时自动带出 baseValue 最高 1 件 |
| 局外商店价格 | 当前装备 40/50/60/80/100，天赋 80/80/100/100/120 | `scripts/systems/MetaProgress.lua:ITEMS/TALENTS` | 中 | 中 | 建议只按数值案装备价格精确替换；消耗品商店当前系统不完整，不建议本轮硬接 |

## 3. 文案接入差异表

> P0 表示直接影响玩家理解闭环和规则；P1 表示影响风格一致性；P2 表示可后续润色。文案案明确当前 Demo 至少使用主菜单、开场、HUD、协议、撤离确认、成功、失败等最小文本集。

| 覆盖项 | 当前文案 | 当前代码位置 | 策划案目标文案 | P0/P1/P2 | 是否适合本次直接替换 | 是否存在 UI 溢出风险 |
|---|---|---|---|---|---|---|
| 主菜单标题与按钮 | 菜单/按钮文案硬编码，包括开始探索、新手教程、装备、天赋、仓库、GM、返回等 | `scripts/main.lua:CreateUI`、`RefreshMenuPage` | 标题“灰尾回收”；副标题“扫雷、搜刮，然后尽量完整地撤离。”；按钮：接受工单/继续作业/标准工单/展示工单/后勤申领/回收资历/后勤仓库/调整终端/下班 | P0 | 适合替标题、按钮；GM 可保留开发入口但不放玩家主流程 | 中，按钮宽度有限 |
| 模式说明 | `左上角看扫雷数字避雷;WASD 走门...`、首次探索提示、统计提示 | `scripts/main.lua:StartNewGame`、`RefreshMenuPage` | 标准工单：“进入封锁区，完成回收、避险与撤离。收益归你，风险也归你。” 展示工单：“使用固定区域结构，适合快速了解核心流程。公司保证流程完整，不保证员工感受。” | P0 | 适合，但当前主菜单未必有模式选择入口 | 中，toast/菜单统计行易挤 |
| 开场教程 | “欢迎来到灰尾公司...”等完整步骤 | `scripts/systems/Tutorial.lua:Tutorial.steps` | 分步教程 1~8：身份、数字、移动、雷险、异常体、物资、撤离、协议；开场极短版为“你是进入封锁区的浣熊回收员。数字表示周围 8 个区域中的雷险数量。搜刮回收物，避开危险，在撤离协议恶化前找到信标。” | P0 | 适合；建议采用分步教程而不是标准版长段落 | 高，教程底栏单行/双行显示 |
| HUD 文案 | “区域扫描图”“生命”“战力”“金币”“零件”“回收包”“已探索”“目标”等 | `scripts/ui/HUD.lua:DrawLeftSidebar` | 区域扫描图、周围雷险：N、当前区域、生命、战斗力、结算币、回收物、回收包、撤离协议、当前目标：找到撤离信标 | P0 | 适合；需与 pending/safe 字段同步 | 高，左侧栏空间紧 |
| 扫雷规则说明 | “数字 = 周围8格雷险”“特殊房不计入数字” | `scripts/ui/HUD.lua`、`scripts/systems/Tutorial.lua`、`EventSystem` 情报选项 | “数字表示周围 8 个区域中的雷险数量。斜向区域也会计入。异常体、物资、事件和撤离点不计入数字。” | P0 | 适合 | 中 |
| 协议 5~1 文案 | `Protocol.lua` 描述：稳定/警戒/压迫/封锁/临界；`HUD.lua` 另有标题/说明表 | `scripts/systems/Protocol.lua`、`scripts/ui/HUD.lua:PROTOCOL_TITLES/DESCS` | 5 正常作业“区域稳定，允许回收。”；4 轻度警戒“读数上升。保持判断。”；3 风险作业“高收益区，高事故区。”；2 返程建议“信标仍在服务中，暂时。”；1 最终建议“撤离是建议，不撤离是选择。” | P0 | 适合，建议集中到 `GameText.lua` | 高，协议面板极窄 |
| 协议降级广播 | “协议降至 X - 描述”“临界协议! 探索未知房损失生命...” | `scripts/main.lua:MovePlayer`、`ApplyEventResult` | 降级广播表：协议 5~1 分别以“调度台 A-7：协议 X...”开头；协议 1 为“撤离是建议。不撤离是自主选择。相关条款已说明。” | P0 | 适合；必须删除协议 1 扣血广播 | 中，toast 有动态拼接 |
| 稳定区提示 | “安全区域展开”“安全区域.继续前进...”等 | `scripts/main.lua:MovePlayer`、`scripts/ui/HUD.lua:GetInteractHint` | 首次“扫描完成。该区域暂无特殊目标。”；再次“已记录区域。”；小提示“安全不代表有钱。很遗憾。” | P0 | 适合 | 中 |
| 雷险区提示 | “踩雷!...”“穿过已触发的雷房...”等 | `scripts/main.lua:MovePlayer`、`DungeonRoom.lua`、`MapOverlay.lua` | “雷险触发！”、“检测到工伤。当前仍可继续作业。”、“已确认雷险。再次经过不会重复触发。”、“雷险已确认。” | P0 | 适合，与雷伤/压力同步 | 中 |
| 异常体区域提示 | “检测到异常体活动...”“靠近后按 F 攻击”等 | `scripts/main.lua:MovePlayer`、`DungeonRoom.lua`、`HUD.lua` | “检测到异常体活动。可绕行，可清理。”、“躲开预警范围，或靠近发动攻击。”、“异常体已清理。区域风险下降。”、“异常体仍在活动。它看起来没有下班的意思。” | P0 | 适合 | 中 |
| 物资区提示 | “发现未登记物资箱。按 F 开启。”“物资箱已开启。”等 | `scripts/main.lua:MovePlayer`、`SearchCurrentRoom`、`OpenLootResultPanel` | “发现未登记物资箱。”、“按 E 开启物资箱。”、“物资箱已开启。”、“箱子已经空了。后勤部对此深表遗憾。” | P0 | 适合，但当前操作键是 F，需先决定是否只改文案还是改交互键 | 中 |
| 旅商区提示 | “遇到旅商! 按 T 用零件换金币.”、“T:打开交易面板”等 | `scripts/systems/EventSystem.lua`、`scripts/scenes/DungeonRoom.lua`、`HUD.lua` | “检测到非公司交易对象。”、“按 E 与旅商交易。”、“旅商仍在假装合法经营。” | P0 | 文案适合；但当前事件键是 T，若不改交互键则目标文案要调整为 T | 高，事件选项描述长 |
| 撤离信标区提示 | “你到达了撤离点! 按 E 撤离.”、“发现隐藏撤离点!” | `scripts/main.lua:MovePlayer`、`DungeonRoom.lua`、`HUD.lua` | “撤离信标已接入。”、“按 E 打开撤离确认。”、“信标仍可用。是否结束本次作业？” | P0 | 适合 | 中 |
| 通用交互提示 | “WASD:移动 M:地图 F:搜索/攻击 E:撤离 T:事件”等 | `scripts/ui/HUD.lua:DrawBottomBar`、`MapOverlay.lua` | 按 E 交互、按 E 开启、按 E 交易、按 E 撤离；当前状态无法回传、异常体活动中无法回传、雷险处理中等 | P0 | 部分适合；和现有 F/T 操作冲突，第二个对话框应优先保持现有键位或同步改交互 | 高，底栏横向空间有限 |
| 旅商事件文案 | 交易选项、急救、情报、兴奋剂、离开、失败原因 | `scripts/systems/EventSystem.lua:getTraderOptions/_ExecTrader` | 狐狸旅商；交易说明“在封锁区里，能提前换成结算币的东西，通常更安全。当然，安全也是要收费的。”；选项：出售异常回收物、购买急救服务、购买雷险提示、购买作业物资、结束交易；结果文案含“交易完成。公司不会知道，大概。” | P0/P1 | 适合 P0；购买作业物资当前系统不稳，可暂不接 | 高 |
| 赌徒事件文案 | “下注 10 结算币”“掷出 4/5/6 获胜...” | `scripts/systems/EventSystem.lua:getDiceOptions/_ExecDice` | 文案案未给完整赌徒事件 P0；数值案给规则：20 待结算币下注，1~4 输，5 净赚 20，6 净赚 60 | P0 | 适合按数值规则改现有文案 | 中 |
| 祭坛事件文案 | “献祭生命”“生命 1”“结算币 +15...” | `scripts/systems/EventSystem.lua:getAltarOptions/_ExecAltar` | 文案案未给完整祭坛事件 P0；数值案给递增 HP 和奖励表 | P0 | 适合按规则生成简洁文案，不扩写剧情 | 高 |
| 机关事件文案 | “处理机关”“成功: 结算币 +25...” | `scripts/systems/EventSystem.lua:getTrapOptions/_ExecTrap`、`DungeonRoom.lua` | 文案案的“旧设施残留/旧设施机关”方向可参考，但未列 Demo 必换机关文案 | P1 | 可小改术语，不应扩写大量 P1/P2 | 中 |
| 撤离确认文案 | “安全金币”“入库回收物估值”“预计金币收益”等 | `scripts/main.lua:DoExtract`、`CreateUI` | “撤离信标已接入。结束本次作业并结算当前收益。”；按钮“结束作业 / 再捡一点” | P0 | 适合，需与结算字段同步 | 高，结算面板固定尺寸 |
| 成功结算文案 | “撤离成功!共获得 X 金币.”、“后勤已登记...” | `scripts/main.lua:ConfirmExtract`、`CreateUI` | 标题“作业完成”；短句可用“你带回了物资，也带回了自己。”；字段：带回结算币、带回异常回收物、最终撤离协议、清理异常体、触发雷险、开启物资箱、本次收益等 | P0 | 适合 | 高 |
| 失败结算文案 | “撤离失败结算”“金币已安全保留”“回收包已遗失”等 | `scripts/main.lua:ShowFailurePanel/ApplyFailureSalvage` | 标题“信号中断”；原因：生命归零“回收员失联。”；说明：结算币属于安全收益，失败后仍会入账；异常回收物风险资产，失败默认丢失；按钮“接受结算 / 返回调度台 / 接受新工单 / 前往后勤申领” | P0 | 适合，但规则必须同步到“选择/自动带出 1 件物资” | 高 |
| 仓库 / 商店 / 局外成长文案 | 装备/天赋名称、描述、价格状态、仓库“卖1/全卖/保护”等 | `scripts/systems/MetaProgress.lua`、`scripts/main.lua:RefreshEquipPage/RefreshTalentPage/RefreshWarehousePage` | 后勤仓库、后勤申领、回收资历/作业许可记录；购买成功“申领成功。请合理使用，不要要求退款。”；结算币不足“后勤部建议你继续上班。” | P1/P2 | 只建议替 P0 标题、按钮、货币名；详细说明看 UI 空间 | 高 |

## 4. 接口冻结建议

| 接口 | 是否必要 | 是否可以不新建、直接沿用现有文件 | 最小字段结构 | 接入点 | 风险 | 推荐最终做法 |
|---|---|---|---|---|---|---|
| `Balance.lua` | 必要 | 可以不新建，但不推荐继续散落常量 | `mineDamage`、`pressure.explore/mine/monster/max`、`protocol.thresholds`、`rewards.search/chest/monster`、`events.dice/altar/trader`、`shopPrices` | `Combat.lua`、`Protocol.lua`、`RunInventory.lua`、`EventSystem.lua`、`MetaProgress.lua` | 新增 require 路径错误会直接启动失败；一次性迁移太大易漏 | 新建，先放必须数值；保留旧函数结构，只把常量读表 |
| `GameText.lua` | 必要 | 可以不新建，但硬编码太分散 | `menu`、`hud`、`tutorial.steps`、`protocol.titles/descs`、`messages`、`events`、`settlement` | `main.lua`、`HUD.lua`、`Tutorial.lua`、`EventSystem.lua`、`MapOverlay.lua` | 全量迁移文案工作量大，容易打断原型闭环 | 新建但只迁 P0 文案；P1/P2 仍可暂留硬编码 |
| `ItemCatalog.lua` | 中等必要 | 可沿用 `RunInventory.ITEM_DEFS` | `id/name/type/rarity/baseValue/value/icon/description/dropTags` | `RunInventory.lua`、`MetaProgress.lua` 仓库展示、旅商出售 | 拆出后仓库存档兼容需注意 | 第二个对话框可先不新建，给 `ITEM_DEFS` 增加 `baseValue = value` 兼容 |
| `RewardResolver.lua` | 中等必要 | 可以沿用 `RunInventory.GetReward` 与 `Combat.makeReward` | `ResolveSearch(cell,rng)`、`ResolveChest(cell,rng)`、`ResolveMonster(enemy,ctx)` | `RunInventory.GetReward`、`Combat.makeReward/RecordCombat` | 独立模块会增加接线面，48H 原型可能不值 | 不新建，先在 `RunInventory`/`Combat` 内按 Balance 重写；后续再抽 |
| `SettlementRules.lua` | 中等必要 | 可以沿用 `RunInventory.GetExtractionReward/GetFailureSalvageOptions` | `BuildSuccess(runInventory)`、`BuildFailure(runInventory, choice)` | `main.lua` 成功/失败面板，`MetaProgress.RecordExtractionReward` | 结算与存档强耦合，抽模块易漏 metaRecorded 防重复 | 第二个对话框不新建，先把规则收敛在 `RunInventory.lua` |
| `RunCurrency` 或扩展 `RunInventory` | 必要 | 推荐扩展现有 `RunInventory`，不新建独立模块 | `pendingGold`、`safeGold`、兼容 `gold`、`carriedItems`、`looseParts` | 所有搜索/宝箱/怪物/事件/结算/HUD | 最高风险；当前大量 UI 和测试读 `RunInventory.gold` | 扩展 `RunInventory`，保留 `gold` 作为兼容别名或派生，第二个对话框先明确语义再改 |

## 5. 关键风险点

1. 当前金币系统不能完整表达 `pendingGold / safeGold / globalGold` 三层语义。`RunInventory.gold` 当前既是局内可消费币，又在失败时自动保留，并在成功时作为 directGold 入全局。
2. 当前失败结算会保留 `RunInventory.gold`。策划目标明确为“待结算币失败丢失、安全结算币保留”，因此当前逻辑会错误保留局内收益。
3. 当前背包/物品系统有 `value`，没有 `baseValue` 字段。可以兼容新增 `baseValue`，但不能直接改名，否则仓库出售、估值、存档规范化会受影响。
4. 当前旅商默认卖虚拟 `parts`，不是选择具体物品。虽然 `RunInventory.RemoveTradableItem(itemId)` 已支持具体物品，但事件 UI 尚未给玩家选择具体物品。
5. 当前失败没有“选择 1 件物品保留”的 UI。只有“抢救 1 零件换 10 金币”的按钮逻辑。
6. 若没有失败选择 UI，数值案允许自动保留 `baseValue` 最高物品。技术上可行，但需要在失败结算文案中明确“抢救条款自动执行”，避免玩家误解。
7. 当前 HUD 左侧栏已经显示生命、战力、金币、零件、回收包、探索、目标、危险、协议；新增“待结算币 / 安全结算币 / 回收物”会有明显溢出风险。
8. 当前事件系统支持事件状态和选项状态，但多数事件执行后立即 `MarkCompleted`。赌徒和祭坛若要多次或递增，需要改完成条件和 optionState。
9. 当前怪物击杀奖励有两个胜利路径：即时攻击 `CompleteActiveMonsterClear` 和旧战斗 `ResolveBattle`，最终都可能调用 `RunInventory.RecordCombat`。新增压力/攻击成长要放在唯一收口，避免重复。
10. 当前协议 1 扣血由 `Protocol.AddPressure` 返回 `penalty`，再由 `main.lua:MovePlayer` 扣血；没有发现其他协议 1 扣血路径，但事件压力广播也读 `AddPressure` 结果，移除 penalty 时要查完整调用。
11. 当前局外商店价格和效果均与数值案不一致。价格目标上调到 90~220，但当前收益将明显收紧，必须同步处理旅商、仓库出售和失败抢救条款，否则成长节奏可能断档。
12. 当前主菜单、结算、教程、HUD、事件文本没有集中管理，散落在 `main.lua`、`HUD.lua`、`Tutorial.lua`、`EventSystem.lua`、`DungeonRoom.lua`、`MetaProgress.lua`。
13. 文案策划案 P0 文案较完整，但部分目标键位写“E 交互/开启/交易”，当前游戏实际使用 F 搜索/攻击、T 事件、E 撤离；若不改交互键，文案需要本地化为现有键位。
14. 事件房背景当前是统一 `Textures/room_event.png`，具体旅商/赌徒/祭坛/机关靠前景道具和标签区分；若目标是每类事件独立背景，需要额外资源与映射，不属于纯文案数值。
15. 当前 tests 中已有大量旧数值断言；第二个对话框必须同步更新 `scripts/tests/minefield_selftest.lua`，否则测试会大量失败。

## 6. 需要人工决策的问题

问题：策划文案中的通用交互键统一写 E，但当前游戏 F 搜索/攻击、T 事件、E 撤离。第二个对话框是否允许同步改交互键？  
默认建议：不改键位，只把目标文案适配为当前键位。  
原因：改键位会影响教程、HUD、事件、鼠标点击和玩家肌肉记忆，超出数值/文案接入的稳定边界。  
不回答时的执行方案：保留 F/T/E 现有操作，文案用“F 搜索/攻击、T 事件、E 撤离”。

问题：旅商是否必须支持“出售多件”，还是本轮只支持选择 1 件出售后事件完成？  
默认建议：本轮支持选择 1 件出售后事件完成。  
原因：数值案写“单个旅商事件可出售多件，但事件房只触发一次”，多件出售需要更复杂的事件面板循环和二次确认。  
不回答时的执行方案：先接 1 件出售，保留 `optionState` 扩展位。

问题：失败选择 1 件物资是否必须做 UI？  
默认建议：本轮先采用数值案简化方案，自动带出 `baseValue` 最高的 1 件。  
原因：失败选择 UI 需要列表、确认、仓库入账和溢出检查，风险高于数值接入本身。  
不回答时的执行方案：自动带出最高价值 1 件，并在失败面板明确显示。

问题：是否新增珍贵/异常/唯一等高价值物品资源，还是用现有物品池映射品质？  
默认建议：用现有物品池先映射品质，不新增图片资源。  
原因：新增物品会牵涉图标、仓库展示、掉落资产和测试，当前任务要求保障闭环。  
不回答时的执行方案：给现有 `ITEM_DEFS` 补 `baseValue/quality`，珍贵/异常掉落先降级到现有最高价值物或占位。

问题：消耗品商店和消耗品掉落是否本轮实现？  
默认建议：不作为本轮必做，只保留价格和文案接口。  
原因：当前没有完整稳定的局内消耗品使用系统，硬接会变成新功能开发。  
不回答时的执行方案：`Balance.lua` 记录消耗品价格，掉落表先不实际掉消耗品。

问题：局外装备效果是否按数值案一起改？例如磨刀石 +5 当前目标 +2、防护甲 +25 当前目标 +20。  
默认建议：价格和效果一起改。  
原因：只改价格不改效果会让性价比和设计意图偏离。  
不回答时的执行方案：按数值案装备效果调整已有装备；不存在的绝缘套用现有厚皮/雷伤减免语义承接。

问题：仓库出售是否仍按 full value，还是也要应用旅商 75%？  
默认建议：仓库仍按 full value，旅商按 75%。  
原因：数值案把旅商定位为局内提前锁定安全收益，代价是 25% 折价；局外仓库出售是成功带回后的兑现。  
不回答时的执行方案：`MetaProgress.SellWarehouseItem` 不打折。

问题：赌徒结果使用真随机还是当前坐标/种子确定性随机？  
默认建议：继续确定性随机。  
原因：当前项目自测依赖可复现，确定性结果更好验证。  
不回答时的执行方案：沿用 `x/y/seed/pendingGold` hash 方式映射 1~6。

问题：怪物击败 +1 攻击上限 +5，是本局成长上限还是总战力上限？  
默认建议：本局怪物成长额外最多 +5，不限制装备/基础战力。  
原因：否则局外装备会被意外削弱。  
不回答时的执行方案：新增 `Combat.monsterPowerBonus` 或等价字段，最多 5。

问题：踩雷压力 +10 是否与探索未知格 +2 同时触发？  
默认建议：同时触发。  
原因：进入未知雷房既产生探索压力，也产生踩雷惩罚，数值案行为分工也把两者分列。  
不回答时的执行方案：首次进入雷房压力 +12；已触发雷房再次经过不加。

问题：P1/P2 文案是否允许第二个对话框大量润色？  
默认建议：不允许，只替 P0 和策划案明确原文。  
原因：48H 原型稳定性优先，避免 UI 溢出和风格偏移。  
不回答时的执行方案：只迁主菜单、教程、HUD、协议、房型提示、旅商、撤离、结算、局外标题等 P0/P1 少量必要文本。

问题：事件房是否需要每类独立背景图？  
默认建议：本次不做，只保留统一事件背景和前景道具/标签。  
原因：这是资源接入，不是数值/文案接入，且当前 `DungeonRoom.lua` 已用统一 `room_event.png`。  
不回答时的执行方案：不改背景，只保证事件文案和道具标签清楚。

问题：是否接受新增 `Balance.lua` 和 `GameText.lua` 两个轻量配置文件？  
默认建议：接受。  
原因：能避免继续散落常量和文案，第二个对话框执行更可控。  
不回答时的执行方案：新建这两个文件，但只迁移 P0/必须数值。

## 7. 第二个对话框推荐执行路线

这不是分阶段重构，而是一次性受控替换。内部顺序如下：

| 顺序 | 修改文件 | 执行内容 | 自检方式 |
|---|---|---|---|
| 1 | `scripts/systems/Balance.lua`（新增） | 放入必须数值：雷伤、压力增量、协议阈值、搜索/宝箱/怪物金币、赌徒、祭坛、旅商 75%、商店价格占位 | 启动前 `lua` require 语法检查；确认没有改地图字段 |
| 2 | `scripts/systems/GameText.lua`（新增） | 放入 P0 文案：HUD 货币名、协议 5~1、教程步骤、事件 P0、成功/失败结算、撤离确认 | 检查长文本长度；不迁 P1/P2 大段润色 |
| 3 | `scripts/systems/Protocol.lua` | 从 Balance 读取探索压力 +2、clamp 0~100、阈值，移除/关闭协议 1 penalty 扣血语义 | 单测：压力 0/19/20/39/40/59/60/79/80/100 等级正确；level 1 不返回扣血 |
| 4 | `scripts/main.lua` | `MovePlayer` 调整：首次探索调用 +2；踩雷分支追加 +10；协议广播不再扣血；击败怪物收口追加 +5 | 手动跑：探索、踩雷、击败怪物压力数正确；血量不会因协议 1 掉到 0 后卡死 |
| 5 | `scripts/systems/Combat.lua` | 雷伤 30；删除搜索加攻依赖；怪物奖励改 0~3；新增怪物击败战力 +1、上限 +5 的状态/函数 | 单测：雷伤、免疫、厚皮仍工作；击杀 6 只加 5 |
| 6 | `scripts/systems/RunInventory.lua` | 扩展 pending/safe 语义；普通搜索/宝箱金币公式；普通/宝箱掉落表按文档；保留 `gold` 兼容或明确映射 | 单测：普通最高 4、宝箱最高 11、事件房不可搜索、重复搜索不发奖 |
| 7 | `scripts/systems/EventSystem.lua` | 旅商具体物品出售 75%；赌徒 20 下注与 1~6 结果；祭坛递增 HP；文案引用 GameText P0 | 单测：旅商价格、赌徒 1~4/5/6、祭坛档位和死亡保护 |
| 8 | `scripts/main.lua` 事件/结算 UI | 事件选项显示具体物品；成功/失败结算使用新币种；失败规则按决策执行；不做全局“金币”替换 | 手动检查事件面板、成功面板、失败面板无空字段 |
| 9 | `scripts/ui/HUD.lua`、`scripts/ui/MapOverlay.lua`、`scripts/ui/MiniMap.lua`、`scripts/systems/Tutorial.lua` | 接入 P0 文案：HUD 标签、协议标题说明、地图提示、教程步骤；保留布局 | 1280x720/常用窗口下观察是否溢出；教程逐步点击 |
| 10 | `scripts/systems/MetaProgress.lua`、`scripts/main.lua` 局外页 | 仅按文档调整价格和 P0 文案；仓库 full value 是否保留按决策 | 旧存档加载、购买/装备/出售仓库物不报错 |
| 11 | `scripts/tests/minefield_selftest.lua` | 更新旧数值断言，新增关键规则测试 | 运行自测，确保地图分布、事件房不可搜索、结算不重复 |
| 12 | 全局自检 | `rg` 检查残留关键旧文案/旧数值；试玩一局成功、一局失败、一局教程 | 确认可玩闭环：开始 -> 探索 -> 搜索/事件/战斗 -> 撤离或失败 -> 回主菜单 |

必须遵守的边界：

- 不改地图结构。
- 不改撤离点生成逻辑。
- 不改房间分布。
- 不删除现有可玩闭环。
- 不做无脑全仓库文本替换。
- 不擅自扩写 P1/P2 大量内容。
- 不把“金币”简单全局替换成“结算币”。
- 优先保证 P0 文案和必须数值落地。

## 8. 最终摘要

### 最推荐第二个对话框直接执行的 10 个改动

1. 新增 `Balance.lua`，集中必须数值。
2. 新增 `GameText.lua`，集中 P0 文案。
3. 雷险伤害从 25 改 30，保留天赋减伤和急救包免疫。
4. 探索未知格压力从 +5 改 +2。
5. 踩雷增加压力 +10。
6. 击败怪物增加压力 +5。
7. 移除协议 1 额外扣血。
8. 普通搜索不再加攻击力。
9. 击败怪物攻击 +1，上限本局 +5。
10. 普通/宝箱/怪物金币按目标公式下调，并同步结算文案。

### 最不建议第二个对话框碰的 5 个点

1. 不改 10x10 和教程 5x5 房间分布。
2. 不改随机撤离点生成逻辑。
3. 不重做局外仓库系统。
4. 不把所有“金币”全文替换为“结算币”。
5. 不新增大量 P1/P2 文案或扩写剧情。

### 最高风险的 5 个点

1. `pendingGold / safeGold / globalGold` 三层货币语义改动。
2. 失败结算从“金币安全保留”改成“待结算币丢失、安全币保留、物资抢救 1 件”。
3. 旅商具体物品出售 UI 与 75% 价格。
4. 祭坛递增多次交互状态与死亡保护。
5. 怪物奖励/压力/攻击成长在双战斗路径下重复结算。

### 需要转交给策划/负责人确认的问题

- 是否允许第二个对话框把文案案中的 E 交互文案适配为当前 F/T/E 键位，而不改键位。
- 旅商本轮是支持出售 1 件后完成，还是必须做多件出售循环。
- 失败抢救 1 件物资是否必须做选择 UI，还是接受自动带出最高 `baseValue` 物品。
- 是否新增珍贵/异常/唯一物品资源，还是先用现有物品池映射品质。
- 消耗品商店和消耗品掉落是否本轮实际实现，还是只保留配置接口。
- P1/P2 文案是否允许本轮接入，还是只替 P0 和少量必要标题。

### 第二个对话框能否一次性完成完整接入

可以一次性完成“必须数值 + P0 文案 + 结算语义”的受控接入。两份策划案已经足够支撑主线接入；剩余风险主要来自交互键位、旅商多件出售、失败选择 UI、消耗品系统和高品质物品资源是否要同步扩展。
