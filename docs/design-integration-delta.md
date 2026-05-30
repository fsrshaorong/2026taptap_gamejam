# 数值与文案接入差异复评

> 复评日期：2026-05-31  
> 对照基准：`docs/design-integration-plan.md`  
> 当前结论先行：当前工作区没有发现数值/文案接入的大规模代码更新。旧报告的大部分判断仍然成立。当前新增变化主要是一个未提交的 `scripts/main.lua` 教程状态重置修复，以及未跟踪的 `docs/design-integration-plan.md`。

## 1. 当前工作区变化概览

### Git 状态摘要

| 检查项 | 当前结果 |
|---|---|
| 分支 | `main...origin/main` |
| `git status` | `M scripts/main.lua`；`?? docs/design-integration-plan.md` |
| `git diff --stat` | `scripts/main.lua | 3 +++` |
| 删除文件 | 未发现 |
| 未跟踪文件 | `docs/design-integration-plan.md` |
| 是否存在未提交 `scripts/main.lua` 修改 | 是 |

### 关键文件存在性

| 文件路径 | 是否存在 | 变化类型 | 可能影响的系统 | 是否与数值/文案接入有关 |
|---|---:|---|---|---|
| `scripts/systems/Balance.lua` | 否 | 不存在 | 数值集中配置 | 是，说明旧报告“建议新增 Balance.lua”仍未落地 |
| `scripts/systems/GameText.lua` | 否 | 不存在 | 文案集中配置 | 是，说明旧报告“建议新增 GameText.lua”仍未落地 |
| `docs/integration-self-check.md` | 否 | 不存在 | 接入自检记录 | 间接相关 |
| `docs/design-integration-plan.md` | 是 | 未跟踪 | 接入评估文档 | 是，当前旧报告本身未纳入 git |
| `docs/design-integration-delta.md` | 本次新增 | 未跟踪 | 差异复评文档 | 是，本报告 |
| `scripts/main.lua` | 是 | 修改 | 教程状态、主流程 | 与本次数值/文案接入无直接关系；修改内容是 `Tutorial.Reset()` |

### `scripts/main.lua` 当前未提交修改

当前 diff 只有 3 行：

- `ReturnToMenu()` 内新增 `Tutorial.Reset()`。
- `StartNewGame(override)` 开头新增 `Tutorial.Reset()` 和空行。

影响判断：这是教程状态 bug 修复方向，不是数值/文案接入。第二轮实施 prompt 应提醒不要把这段未提交修复误判为数值文案接入，也不要无意覆盖。

## 2. 对照旧报告，标记哪些判断已过时

| 旧报告判断 | 当前实际状态 | 是否过时 | 证据文件/函数 | 对第二轮实施 prompt 的影响 |
|---|---|---:|---|---|
| 尚未有 `Balance.lua` | 仍不存在 | 否 | `scripts/systems/Balance.lua` 不存在 | 仍应新增；强调不要新建第二套路径 |
| 尚未有 `GameText.lua` | 仍不存在 | 否 | `scripts/systems/GameText.lua` 不存在 | 仍应新增；只迁 P0 文案 |
| `Protocol.lua` 探索压力默认 +5 | 仍是 `BASE_EXPLORE_PRESSURE = 5` | 否 | `scripts/systems/Protocol.lua:AddPressure` | 仍需改为 +2，并从 `Balance.lua` 读取 |
| 协议 1 会额外扣血 | 仍会；`AddPressure` 返回 `penalty=level==1`，`main.lua` 扣 1 HP | 否 | `scripts/systems/Protocol.lua:AddPressure`、`scripts/main.lua:MovePlayer` | 仍需移除 penalty 扣血和对应广播 |
| 雷险伤害仍是 25 | 仍是 `mineDamage = 25` | 否 | `scripts/systems/Combat.lua` `CONFIG.mineDamage` | 仍需改为 30 |
| 普通搜索仍会加攻击 | 仍会调用 `Combat.TryPowerUp`，20% 概率 +3 | 否 | `scripts/main.lua:SearchCurrentRoom`、`scripts/systems/Combat.lua:TryPowerUp` | 仍需删除搜索加攻 |
| 怪物击败仍不加攻击 | 仍无击杀成长字段/函数 | 否 | `scripts/systems/Combat.lua:makeReward`、`RunInventory.RecordCombat` | 仍需新增击杀 +1，上限 +5 |
| 怪物金币仍高于 0~3 | 仍是 `12 + enemyPower`，高战力给 1 零件 | 否 | `scripts/systems/Combat.lua:makeReward` | 仍需降到 0~3 待结算币 |
| `RunInventory` 只有 `gold`，没有 `pendingGold/safeGold` | 仍只有 `RunInventory.gold`；失败选项里 `safeGold = RunInventory.gold` 只是旧兼容命名 | 否 | `scripts/systems/RunInventory.lua` | 仍需拆 pending/safe 语义，谨慎兼容 `gold` |
| 失败结算仍保留局内金币 | 仍保留，且测试按旧逻辑断言 | 否 | `RunInventory.GetFailureSalvageOptions`、`ApplyFailureSalvage`、`minefield_selftest.lua` | 仍需改为待结算币失败丢失、安全币保留 |
| 失败未支持自动带回最高 `baseValue` 物品 | 仍未支持；物品也没有 `baseValue` | 否 | `RunInventory.ITEM_DEFS`、`GetFailureSalvageOptions` | 仍需新增 `baseValue` 和自动带回最高价值物 |
| 旅商未支持按 `baseValue * 0.75` 出售具体物品 | 仍未支持；当前卖虚拟 `parts`，价格 15/20 | 否 | `scripts/systems/EventSystem.lua:_ExecTrader` | 仍需具体物品出售和 safeGold 入账 |
| 赌徒未改为 20 待结算币下注 | 仍是 `DICE_BET=10`、4/5/6 赢净 +10 | 否 | `scripts/systems/EventSystem.lua:DICE_*` | 仍需改为 20 下注，1~4 输，5 净 +20，6 净 +60 |
| 祭坛未支持递增献祭 | 仍是一次性 `ALTAR_HP_COST=1`，奖励 +15 金币 +1 回收物，压力 +5 | 否 | `scripts/systems/EventSystem.lua:_ExecAltar` | 仍需 5 档递增、取消额外压力、记录档位 |
| HUD 未显示“待结算 / 已锁定 / 回收物” | 仍显示“金币/零件/回收包”；没有待结算/已锁定 | 否 | `scripts/ui/HUD.lua:DrawLeftSidebar` | 仍需配合货币语义更新 HUD |
| 教程文案未替换 | 仍是旧教程，如“欢迎来到灰尾公司, 新晋回收员.”、“金币、零件和装备” | 否 | `scripts/systems/Tutorial.lua:Tutorial.steps` | 仍需替 P0 教程；注意当前有未提交 `Tutorial.Reset()` |
| 协议文案未替换为调度台 A-7 口吻 | 仍未；HUD 有部分阶段名接近策划，但广播不是 A-7 口吻 | 否 | `scripts/ui/HUD.lua:PROTOCOL_*`、`scripts/main.lua:MovePlayer` | 仍需集中到 `GameText.lua` |
| 主菜单未替换为“灰尾回收” | 仍未作为 UI 标题；菜单按钮仍有“出发探索/新手教程/装备/天赋”等 | 否 | `scripts/main.lua:CreateUI` | 仍需替菜单 P0；保留 GM 开发入口 |
| 局外商店价格未调整 | 仍是防护甲 50、磨刀石 40、急救包 60、罗盘 80、大背包 100 | 否 | `scripts/systems/MetaProgress.lua:ITEMS` | 仍需按策划价和效果调整 |
| 测试未更新 | 仍大量按旧规则断言：失败保留金币、搜索必给金币、赌徒旧规则、祭坛旧规则等 | 否 | `scripts/tests/minefield_selftest.lua` | 第二轮必须同步更新测试 |

## 3. 已经完成的接入内容

| 系统 | 状态 | 具体文件和函数 | 说明 |
|---|---|---|---|
| 数值配置 | 未完成 | 无 `Balance.lua` | 数值仍散落在 `Combat.lua`、`Protocol.lua`、`RunInventory.lua`、`EventSystem.lua`、`MetaProgress.lua` |
| 文案配置 | 未完成 | 无 `GameText.lua` | 文案仍硬编码在 `main.lua`、`HUD.lua`、`Tutorial.lua`、`EventSystem.lua` |
| 协议压力 | 部分完成 | `Protocol.lua` | 阈值 20/40/60/80 已符合；探索仍 +5，协议 1 仍扣血，未支持下限 clamp |
| 雷险伤害 | 未完成 | `Combat.lua:CONFIG.mineDamage` | 仍是 25 |
| 搜索奖励 | 未完成 | `RunInventory.GetReward` | 仍是旧金币公式，且搜索后仍可能加攻击 |
| 宝箱奖励 | 未完成 | `RunInventory.GetReward` | 仍是旧宝箱翻倍 +16，掉落仍 1~3 件旧表 |
| 怪物奖励 | 未完成 | `Combat.makeReward` | 仍高金币、高战力掉零件 |
| 战斗成长 | 未完成 | `Combat.lua`、`main.lua` | 未见击杀 +1 / 上限 +5 |
| 旅商 | 部分完成 | `EventSystem._ExecTrader`、`RunInventory.GetTradableItems/RemoveTradableItem` | 有虚拟 parts 交易和具体物品移除底层能力，但事件未按 `baseValue*0.75` 选择物品出售 |
| 赌徒 | 未完成 | `EventSystem._ExecDice` | 仍旧 10 下注规则 |
| 祭坛 | 未完成 | `EventSystem._ExecAltar` | 仍旧一次性 1 HP 换奖励并加压力 |
| `pendingGold / safeGold` | 未完成 | `RunInventory.gold` | 仅有 `safeGold = RunInventory.gold` 的旧失败保留字段，不是真正三层货币 |
| 成功结算 | 部分完成 | `RunInventory.GetExtractionReward`、`MetaProgress.RecordExtractionReward` | 已有撤离入账和物品入仓库链路，但币种语义不符合目标 |
| 失败结算 | 部分完成 | `RunInventory.GetFailureSalvageOptions/ApplyFailureSalvage`、`main.lua:ShowFailurePanel` | 有失败面板和保底，但规则与目标相反：当前保留局内金币，未带出最高价值物 |
| 物品 `baseValue` | 未完成 | `RunInventory.ITEM_DEFS`、`MetaProgress` | 只有 `value`，无 `baseValue/quality` |
| HUD 文案 | 部分完成 | `HUD.lua` | 协议标题有部分接近目标；货币、回收物、底栏和提示仍旧 |
| 教程文案 | 未完成 | `Tutorial.lua` | 仍旧教程文本 |
| 主菜单文案 | 未完成 | `main.lua:CreateUI` | 仍旧按钮与窗口标题 |
| 结算文案 | 未完成 | `main.lua:ShowFailurePanel/ConfirmExtract/DoExtract` | 仍使用安全金币、保留金币、获得金币等旧语义 |
| 局外商店 | 未完成 | `MetaProgress.ITEMS/TALENTS` | 价格和效果未按策划案调整 |
| 测试 | 未完成 | `scripts/tests/minefield_selftest.lua` | 仍按旧规则断言 |
| 教程状态重置 | 已完成但未提交 | `scripts/main.lua:ReturnToMenu/StartNewGame` | 本次复评发现的唯一功能代码变化；与数值/文案接入无直接关系 |

## 4. 新增风险点

1. `docs/design-integration-plan.md` 当前是未跟踪文件。若第二轮对话或其他协作者只看 git 已跟踪内容，可能看不到旧报告。
2. `scripts/main.lua` 有未提交教程修复。第二轮实施若大改 `main.lua`，容易覆盖或误合并这 3 行。
3. 当前没有真正的 `pendingGold/safeGold`，但测试和代码里已有 `safeGold = RunInventory.gold` 命名，容易让实施者误以为 safeGold 已接入。
4. 货币语义目前存在“金币 / 结算币 / 零件 / 回收物 / 回收包”混用。接入后如果只替 UI 文案，规则仍会错。
5. 结算入账目前有成功链路 `MetaProgress.RecordExtractionReward` 和失败链路 `MetaProgress.AddGold`。拆 pending/safe 后，存在重复加 safeGold 或错误保留 pendingGold 的风险。
6. 怪物胜利路径仍有 `CompleteActiveMonsterClear` 与 `ResolveBattle` 两条入口，最终走 `RunInventory.RecordCombat`。新增击杀压力和攻击成长必须放唯一收口，避免重复。
7. 旅商当前通过 `goldDelta/partsDelta` 直接改 `RunInventory.gold/parts`。改成具体物品出售后，存在“扣了物品未加 safeGold”或“加了 safeGold 未扣物品”的风险。
8. `Balance.lua` 不存在，因此旧硬编码常量仍会并存到接入完成前。第二轮若只新增配置但漏改调用点，会出现配置无效。
9. `GameText.lua` 不存在，因此旧硬编码文案会长期残留。第二轮若只替一部分 UI，容易出现“灰尾回收”和“扫雷搜打撤/金币/零件”混杂。
10. 测试仍按旧数值断言。第二轮如果实现目标规则但不更新测试，会出现大面积测试失败，难以判断是真 bug 还是旧断言。
11. 局外装备价格尚未改，收益也尚未改；目前不存在“价格改了收益没改”的新不一致，但第二轮需要两者同批。
12. 旧存档字段只认识 `gold`、仓库 item `value`。新增 `pendingGold/safeGold/baseValue/quality` 时必须保持存档 normalize 兼容。

## 5. 第二轮完整实施 prompt 需要删改的内容

### 应删除的指令

- 删除“检查是否已经存在 `Balance.lua` / `GameText.lua` 后沿用”的假设式措辞；当前明确不存在，可以直接要求新增。
- 删除“如果文案策划案缺失则只做占位”的措辞；两份策划案已经提供，第二轮应按策划原文执行 P0。
- 删除“重新评估地图房间数量或教程 5x5 分布”的内容；当前地图分布不属于本轮，且已有测试覆盖。
- 删除“实现失败选择 UI 作为必须项”的硬要求；更稳的做法是先按数值案简化方案自动带出最高 `baseValue` 物品。

### 应保留的指令

- 不改地图结构。
- 不改撤离点生成逻辑。
- 不改房间分布。
- 不删除现有可玩闭环。
- 不做无脑全仓库文本替换。
- 不擅自扩写 P1/P2 大量内容。
- 不把“金币”简单全局替换成“结算币”。
- 优先保证 P0 文案和必须数值落地。
- 更新测试，并用测试区分“旧断言失败”和“新规则回归”。
- 谨慎处理 `scripts/main.lua` 当前未提交的 `Tutorial.Reset()` 修改，不要覆盖。

### 应新增或强化的指令

- 必须新增并沿用唯一的 `scripts/systems/Balance.lua`；禁止在第二个新文件或局部硬编码里再定义同一数值。
- 必须新增并沿用唯一的 `scripts/systems/GameText.lua`；P0 文案从这里读，剩余硬编码要有明确保留理由。
- 货币字段必须一次性定义清楚：`pendingGold` 为失败丢失，`safeGold` 为失败保留，`MetaProgress.gold` 为全局结算币；`RunInventory.gold` 只能作为兼容别名或彻底迁移，不可语义混用。
- 成功结算必须只入账一次：pending + safe 进入全局，背包物资入仓库，避免 `RecordExtractionReward` 重复记录。
- 失败结算必须不保留 pending；safe 保留；若无选择 UI，自动带出最高 `baseValue` 1 件并显示。
- 旅商必须扣具体物品，并把 `floor(baseValue*0.75)` 加到 safeGold；仓库出售仍按 full value，除非负责人另行确认。
- 怪物击杀的金币、压力、攻击成长必须放同一收口，避免两条战斗路径重复发奖。
- 文案案里的 E 交互提示要适配当前键位 F/T/E，除非第二轮明确要改交互设计。
- 同步更新 `scripts/tests/minefield_selftest.lua` 中旧金币、赌徒、祭坛、失败、搜索、怪物奖励断言。
- 把 `docs/design-integration-plan.md` 和本 delta 报告纳入提交，避免第二轮失去上下文。

## 6. 当前最应该执行的 10 个补丁点

| 补丁点 | 文件 | 为什么仍需要做 | 风险 | 是否影响可玩闭环 |
|---|---|---|---|---|
| 新增集中数值配置 | `scripts/systems/Balance.lua`，接入 `Combat.lua/Protocol.lua/RunInventory.lua/EventSystem.lua/MetaProgress.lua` | 目标数值仍未接入，硬编码散落 | 中 | 是，数值驱动全局体验 |
| 新增 P0 文案配置 | `scripts/systems/GameText.lua`，接入 `main.lua/HUD.lua/Tutorial.lua/EventSystem.lua` | 文案仍硬编码且新旧语义混杂 | 中 | 是，影响规则理解 |
| 改协议压力 | `scripts/systems/Protocol.lua`、`scripts/main.lua` | 探索仍 +5，协议 1 仍扣血，踩雷/击杀未加压 | 高 | 是 |
| 改雷伤和战斗成长 | `scripts/systems/Combat.lua`、`scripts/main.lua` | 雷伤仍 25，搜索仍加攻，怪物未提供 +1 成长 | 中 | 是 |
| 重写普通/宝箱奖励 | `scripts/systems/RunInventory.lua` | 当前收益远高于目标，掉落表未按品质 | 高 | 是 |
| 拆分 pending/safe 货币 | `scripts/systems/RunInventory.lua`、`scripts/main.lua`、`scripts/systems/MetaProgress.lua` | 当前失败错误保留局内金币 | 高 | 是 |
| 改失败结算自动带出最高价值物 | `RunInventory.lua`、`main.lua`、`MetaProgress.lua` | 当前没有目标保底；无 UI 时应自动最高 `baseValue` | 高 | 是 |
| 改旅商具体物品出售 | `EventSystem.lua`、`RunInventory.lua`、`main.lua` | 当前只卖虚拟 parts，不能锁 safeGold | 中 | 是 |
| 改赌徒和祭坛 | `EventSystem.lua` | 赌徒/祭坛仍旧规则，事件特色未落地 | 中 | 是 |
| 更新测试 | `scripts/tests/minefield_selftest.lua` | 测试仍断言旧规则，会阻塞验证 | 中 | 否，但影响交付信心 |

## 7. 当前最不应该碰的 5 个点

1. `scripts/systems/Minefield.lua` 的 10x10 房间数量、教程 5x5 斜线布局和撤离点逻辑。它们已符合此前需求并有测试覆盖。
2. `scripts/scenes/DungeonRoom.lua` 的房间背景和资源路径。事件房独立背景不是本次数值/文案主线。
3. 局外仓库的基本持久化链路 `MetaProgress.AddWarehouseItems/RecordExtractionReward`。应兼容扩展，不要重做。
4. 当前未提交的 `scripts/main.lua` 教程状态重置修复。除非明确处理教程 bug，否则第二轮不要覆盖它。
5. GM 调试入口。可在玩家文案中弱化或隐藏，但不要在数值接入时删除调试能力。

## 8. 测试与验证建议

### 需要运行的现有测试

- `scripts/tests/minefield_selftest.lua`：当前主要覆盖地图、教程布局、事件、结算、仓库、战斗奖励。
- 若项目有启动命令，还应做一次实际启动 smoke test，确认新增 `require("systems.Balance")` / `require("systems.GameText")` 路径可加载。

### 需要新增或更新的测试

- `Protocol.AddPressure`：探索 +2，踩雷 +10，击杀 +5，压力 clamp 0~100，协议 1 不扣血。
- `Combat.TakeMineHit`：基础雷伤 30，厚皮减伤和急救包免疫仍可用。
- 普通搜索奖励：待结算币最高 4，不再触发 `TryPowerUp`。
- 宝箱奖励：待结算币最高 11，必掉 1 件物品，额外掉落按可实现范围断言。
- 怪物奖励：金币 0~3，击杀攻击 +1，上限 +5，击杀压力 +5，不重复发奖。
- 旅商：出售具体物品扣除背包物品，safeGold 增加 `floor(baseValue*0.75)`。
- 赌徒：20 待结算币下注，1~4 -20，5 +20，6 +60。
- 祭坛：5 档 HP 消耗 10/15/25/35/50，HP 必须大于消耗，最低留 1 HP，不加压力。
- 成功结算：pending + safe 只入全局一次，物资入仓库。
- 失败结算：pending 丢失，safe 保留，自动带出最高 `baseValue` 1 件。
- 旧存档兼容：没有 `baseValue/quality/pendingGold/safeGold` 的存档能 normalize。

### 需要手动试玩验证的流程

- 开始标准局：HUD 是否显示待结算/已锁定/回收物，操作提示是否仍对应 F/T/E。
- 普通搜索、宝箱、怪物击杀各触发一次：奖励弹窗和 HUD 是否一致。
- 踩雷四次左右：雷伤、压力、死亡结算是否正确。
- 进入旅商事件：出售具体物品后 safeGold 是否显示并在失败后保留。
- 赌徒和祭坛事件：结果文案、货币变化、HP 变化是否一致。
- 成功撤离：结算面板、全局金币、仓库入库是否一致。
- 失败结算：是否自动抢救最高价值物，pending 是否丢失。
- 新手教程：文案是否换成策划 P0，且直接开始探索不会出现教程对话。

### 只能手动看 UI 的内容

- 主菜单“灰尾回收”标题、副标题、按钮是否溢出。
- HUD 左侧栏新增字段是否拥挤。
- 协议面板 5~1 文案是否能放下。
- 教程底部对话框长句是否换行合理。
- 事件面板中旅商物品列表、祭坛递增说明是否遮挡。
- 成功/失败结算面板字段是否互相覆盖。

## 9. 最终结论

1. 当前仍适合执行“一次性受控接入”，因为核心代码尚未被半接入污染，旧报告大部分判断仍有效。
2. 第二轮 prompt 应基于旧 prompt 小改，而不是重写一份完全不同的 prompt。需要强化当前发现：`Balance.lua/GameText.lua` 仍不存在、`scripts/main.lua` 有未提交教程修复、旧报告本身未跟踪。
3. 当前不适合把任务拆成大重构；仍应按“新增轻量配置 + 精确替换数值/文案 + 同步测试”的方式执行。
4. 当前最关键阻塞点是三层货币语义：`pendingGold/safeGold/globalGold` 如何兼容现有 `RunInventory.gold`、失败结算、成功入账和旧存档。
5. 建议转交策划/技术负责人确认：是否保留 F/T/E 当前键位、旅商本轮是否必须多件出售、失败是否接受自动抢救最高价值物、是否新增高品质物品资源、消耗品商店是否本轮实际落地。
