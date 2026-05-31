# Deploy UI Adaptation Pass

Date: 2026-05-31

## Scope

- Main menu keeps the no-text background and removes visible top-left dynamic UI buttons.
- Main menu entry behavior is retained through three logical hotspots: accept work order, tutorial, settings.
- Deploy preparation now has a 1536x864 logical layout basis with letterbox/pillarbox coordinate mapping.
- The deploy overview uses the approved A-level panel, nav, summary, back, and confirm-deploy assets when available.
- Other deploy modules keep their existing gameplay data and list logic, with a shared lightweight deploy shell overlay for navigation, summary, and confirm-deploy access.
- HUD work this pass is asset registration only; full in-run HUD refactor is intentionally deferred.

## Runtime Asset Paths

- `assets/ui/main_menu/main_menu_bg_no_text.png`
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

## Fallbacks

- `UITheme` treats missing images as non-fatal and falls back to NanoVG rectangles/text.
- Existing UI list rows, talent rows, and detailed warehouse/requisition content still use the old dynamic UI drawing because the available row assets contain fixed sample text or require further slicing.
- In-run HUD image skinning is not applied yet; registered key-prompt assets are prepared for a later HUD pass.

## Guardrails

- Runtime code references only project-relative resource paths.
- No `Draw/00_raw` or candidate-sheet folders were copied.
- No gameplay systems, save structure, warehouse rules, requisition rules, loadout validation, or talent math were changed.
