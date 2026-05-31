# 灰尾回收

扫雷、搜刮，然后尽量完整地撤离。

你是一名灰尾临时回收员，在封锁区中依靠区域扫描图判断雷险，搜刮异常回收物，清理或绕开异常体，并在五四三二一撤离协议恶化前找到撤离信标。

## 当前 Demo 核心

- 看数字：数字表示周围 8 个区域中的雷险数量。
- 做判断：异常体、物资、事件和撤离信标不计入雷险数字。
- 拿物资：搜索、物资箱、事件会获得待结算币或异常回收物。
- 找信标：成功撤离后，待结算币入账，物资进入后勤仓库。
- 控风险：失败时待结算币丢失，仅保留已锁定收益和有限物资。

## 核心文档

- `docs/game-design.md`
- `docs/dev-plan.md`

## 核心逻辑

- `scripts/systems/Minefield.lua`
- `scripts/systems/ExtractionRun.lua`
- `scripts/systems/RunInventory.lua`
- `scripts/scenes/DungeonRoom.lua`
