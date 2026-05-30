# v0.3 Balance Port Self Check

1. Current branch: `codex/v03-balance-port`
2. Base commit: `20bd720` (`origin/main`, Fix menu layering and tutorial map)
3. Port source: `origin/integrate-v03-balance-text` at `4cad7de`
4. Modified files:
   - `scripts/main.lua`
   - `scripts/systems/Balance.lua`
   - `scripts/systems/GameText.lua`
   - `scripts/systems/Combat.lua`
   - `scripts/systems/EventSystem.lua`
   - `scripts/systems/MetaProgress.lua`
   - `scripts/systems/Protocol.lua`
   - `scripts/systems/RunInventory.lua`
   - `scripts/ui/HUD.lua`
   - `scripts/tests/minefield_selftest.lua`
   - `docs/integration-self-check.md`
   - `docs/design-integration-plan.md`
   - `docs/design-integration-delta.md`
   - `docs/v03-balance-port-self-check.md`
5. Directly adopted from source branch:
   - `scripts/systems/Balance.lua`
   - `scripts/systems/GameText.lua`
   - `scripts/systems/Combat.lua` with interface review
   - `scripts/systems/EventSystem.lua` with interface review
   - `scripts/systems/Protocol.lua` with interface review
   - v0.3 integration docs, with whitespace validation pending
6. Ported by hand on top of main:
   - `scripts/main.lua`
   - `scripts/systems/MetaProgress.lua`
   - `scripts/systems/RunInventory.lua`
   - `scripts/ui/HUD.lua`
   - `scripts/tests/minefield_selftest.lua`
7. Main systems preserved:
   - Logistics terminal and two-level menu entry flow
   - Loadout and emergency bandage consumables
   - Warehouse, recovery, owned items, equipped items compatibility
   - Tutorial fixed 5x5 manual map and tutorial isolation
   - HUD/Q emergency bandage use path
8. Source branch capabilities ported:
   - `Balance` and `GameText` config modules
   - pending/safe run currency semantics
   - protocol pressure values and no Protocol 1 extra HP penalty
   - tuned search, chest, mine, monster, trader, dice, altar, and trap rules
   - extraction and failure settlement semantics
   - P0 player-facing text adapters where compatible
9. TODO:
   - Manual UI text pass for mojibake already present in existing files.
   - Manual playtest required for event panel flow and failure settlement feel.
10. Known risks:
   - `EventSystem.lua` was mostly adopted from the source branch and must be played through.
   - Failure salvage now stores one highest-value carried item; recovery history remains extraction-only.
   - Some tests assert state-level behavior rather than visual text because the UI is generated dynamically.
11. Required validation:
   - `npm.cmd exec --yes --package=luaparse -- luaparse ...`
   - `npm.cmd exec --yes --package=fengari-node-cli -- fengari scripts/tests/minefield_selftest.lua`
   - `git diff --check`
12. Manual playtest flows:
   - Main menu accepts a normal work order from the deploy terminal.
   - Tutorial uses the fixed 5x5 map and does not consume/write meta resources.
   - Search/chest rewards show pending currency and carried items.
   - Trader sells a concrete carried item into safe currency.
   - Failure keeps safe currency and salvages one highest-value item.
