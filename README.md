# 2026taptap_gamejam

当前玩法方向：扫雷地图 + 地牢房间 + 搜打撤。

- 左上角显示完整扫雷小地图，可点击放大。
- 主画面显示当前房间，一个房间对应扫雷地图上的一个格子。
- 房间通过上、下、左、右四个门连接相邻格子。
- 主角经过的安全房间可以通过放大地图传送回去。
- 玩家从地图中心出生，四个角是撤离点。
- 四角撤离点不会是地雷，并保证从中心至少有路可达。

核心文档：

- `docs/game-design.md`
- `docs/dev-plan.md`

核心逻辑：

- `scripts/systems/Minefield.lua`
- `scripts/systems/ExtractionRun.lua`
