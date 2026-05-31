# Deploy UI Adaptation Pass

Date: 2026-05-31

## Scope

- Main menu is restored to the original `Textures/menu_bg.png` background and removes visible top-left dynamic UI buttons.
- Main menu entry behavior is retained through three logical hotspots: accept work order, tutorial, settings.
- Deploy preparation now has a 1536x864 logical layout basis with letterbox/pillarbox coordinate mapping.
- The deploy preparation page is decoupled from the main-menu scene and uses a dark terminal backdrop plus approved A-level panel, nav, summary, back, icon, and confirm-deploy assets when available.
- Warehouse, requisition, loadout, recovery, and talent modules all render into one fixed central display area using a shared filter bar and three-column card grid.
- HUD work this pass is asset registration only; full in-run HUD refactor is intentionally deferred.

## Runtime Asset Paths

- `assets/Textures/menu_bg.png`
- `assets/ui/deploy/ui_button_back_main.png`
- `assets/ui/deploy/ui_button_nav_warehouse.png`
- `assets/ui/deploy/ui_button_nav_requisition.png`
- `assets/ui/deploy/ui_button_nav_loadout.png`
- `assets/ui/deploy/ui_button_nav_recovery.png`
- `assets/ui/deploy/ui_button_nav_talent_selected.png`
- `assets/ui/deploy/ui_button_confirm_deploy_large.png`
- `assets/ui/deploy/ui_panel_deploy_main_blank.png`
- `assets/ui/deploy/ui_panel_deploy_summary_blank.png`
- `assets/ui/deploy/ui_frame_highlight.png`
- `assets/ui/deploy/ui_icon_armor.png`
- `assets/ui/deploy/ui_icon_compass.png`
- `assets/ui/deploy/ui_icon_bandage.png`
- `assets/ui/deploy/ui_icon_backpack.png`
- `assets/ui/common/ui_scrollbar_vertical.png`
- `assets/ui/keys/ui_key_e.png`
- `assets/ui/keys/ui_key_esc.png`
- `assets/ui/keys/ui_key_f.png`
- `assets/ui/keys/ui_key_m.png`
- `assets/ui/keys/ui_key_q.png`
- `assets/ui/keys/ui_key_t.png`
- `assets/ui/main_menu/main_menu_bg_no_text.png` is retained in the project but is not used as the formal main-menu background.

## Fallbacks

- `UITheme` treats missing images as non-fatal and falls back to NanoVG rectangles/text.
- Detailed module content uses dynamic card text over approved blank deploy/card shell assets; old per-module list panels are no longer visible in the deploy flow.
- In-run HUD image skinning is not applied yet; registered key-prompt assets are prepared for a later HUD pass.

## Guardrails

- Runtime code references only project-relative resource paths.
- No `Draw/00_raw` or candidate-sheet folders were copied.
- No gameplay systems, save structure, warehouse rules, requisition rules, loadout validation, or talent math were changed.
