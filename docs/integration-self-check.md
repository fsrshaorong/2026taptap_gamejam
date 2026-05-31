# 数值与文案接入自检

## 本次新增

- `scripts/systems/Balance.lua`：集中雷险伤害、协议压力、搜索/宝箱/怪物奖励、旅商/赌徒/祭坛、局外商店价格。
- `scripts/systems/GameText.lua`：集中 P0 文案，覆盖协议、HUD 货币名、教程步骤、事件提示、结算关键字。

## 已接入系统

- 协议压力：探索未知格 `+2`，踩雷 `+10`，击败怪物 `+5`，压力 clamp 到 `0~100`，协议 1 不再额外扣血。
- 雷险伤害：基础伤害改为 `30`，仍保留急救包免疫与减伤装备/天赋路径。
- 搜索奖励：普通搜索改为待结算币 `random(0,2)+floor(周围雷数/2)`、最高 `4`；普通搜索不再提升攻击。
- 宝箱奖励：宝箱待结算币改为 `random(3,7)+周围雷数`、最高 `11`。
- 怪物奖励：击败怪物给 `0~3` 待结算币，怪物击杀战力成长 `+1`，上限 `+5`。
- 货币语义：`RunInventory.pendingGold` 为失败丢失，`RunInventory.safeGold` 为失败保留，`RunInventory.gold` 保留为 pending 兼容别名。
- 旅商：出售一件具体回收物，收益为 `floor(baseValue * 0.75)`，进入 `safeGold`，并扣除对应回收物。
- 赌徒：下注 `20` 待结算币；`1~4` 输，`5` 净赚 `20`，`6` 净赚 `60`。
- 祭坛：献祭生命消耗按 `10/15/25/35/50` 递增，返回待结算币与一件回收物；无新增选择 UI。
- 失败结算：失败只保留 `safeGold`，并自动带回 `baseValue` 最高的一件回收物。
- 成功结算：成功入账 `pendingGold + safeGold`，回收物入仓库。
- 局外商店：接入策划价格，并新增无贴图依赖的 `绝缘套` 装备占位。
- 教程/HUD/协议/事件 P0 文案：已接入 `GameText.lua`，保留部分原型 UI 文案未做大段 P1/P2 扩写。
- **新手教程系统（v2 固定坐标弹窗）**：完全重写为坐标驱动，不再是步骤状态机。
  - `Tutorial.lua`：核心改为 `OnEnterRoom(x,y)` → 查 `roomPopups` 映射 → 显示对应弹窗。
  - `GameText.lua`：新增 `popupDefs` 表（10 条弹窗定义：spawn_intro / number_rule / mine_rule / event_rule / monster_rule / chest_rule / map_rule / mine_review / route_rule / exit_goal）。
  - `main.lua`：`MovePlayer` 成功后调用 `OnEnterRoom` + `FlushPendingPopup`；`TeleportTo` 同理；`StartTutorialRun` 触发出生点弹窗；按键/鼠标处理中检查 `IsInputLocked` / `HasBlockingPopup` 实现输入锁。
  - `HUD.lua`：新增 `DrawTutorialPopup`（阻塞=居中遮罩大面板；非阻塞=底部小面板）。
  - 旧接口 `HandleClick` / `NotifyAction` / `GetCurrentStep` 等保留为 no-op，不影响其他系统。

## 明确保留

- 未修改地图结构、撤离点生成逻辑、10x10 房间分布、教程 5x5 地图布局。
- 未替换或新增美术资源。
- 未删除 GM/调试入口。
- 未引入 `RewardResolver.lua`、`SettlementRules.lua` 或第二套配置。

## 验证

- 已运行：`C:\Program Files (x86)\Lua\5.1\lua.exe scripts/tests/minefield_selftest.lua`
- 结果：全部通过，输出 `[PASS] minefield selftest complete`。
- 已运行语法检查：`loadfile('scripts/main.lua')`、`loadfile('scripts/ui/HUD.lua')`、`loadfile('scripts/systems/EventSystem.lua')`、`loadfile('scripts/systems/RunInventory.lua')`
- 结果：`syntax ok`。

## 后续人工试玩重点

- 进入旅商事件，出售具体回收物后确认 HUD 的“已锁定”增加、回收包扣除 1 件，失败后该金额保留。
- 失败时确认待结算币不入账，自动带回最高价值物品。
- 连续击败怪物确认战力最多因击杀成长 `+5`，且怪物奖励不会重复发放。
- 祭坛连续献祭确认 HP 消耗递增，且 HP 不足时不能献祭。
- 成功撤离确认全局金币只增加 `pendingGold + safeGold` 一次，回收物入仓库一次。
