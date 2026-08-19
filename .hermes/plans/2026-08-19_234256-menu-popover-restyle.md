# Menu Popover Restyle Implementation Plan

> **For Cursor (cursor-agent):** Implement this plan task-by-task. Load skill `.agents/skills/godot-ultimate-mode/SKILL.md` (project copy; user-level copy also at `~/.cursor/skills/godot-ultimate-mode`) and follow its gates: Game UI + UX + Animation. Respond in Indonesian for status reports to Ryan. Do NOT touch any logic beyond the popover (no backend, no other views).

**Goal:** Restyle the Menu popover (opened by the rightmost bottom-nav tab) so it matches Scanima's design language — rich glass panel with header, icon rows, and dividers — while keeping its current floating bottom-right position.

**Architecture:** Pure UI restyle. Edit the `MenuPopover` subtree inside `scenes/scan_flow.tscn`, add theme styleboxes/variations to `themes/mobile_theme.tres`, add 2 Lucide SVG icons, add 1 localization key, and make minimal additions to `scripts/menu_popover.gd` (title refresh + backdrop fade). No data wiring, no API changes.

**Tech Stack:** Godot 4.6 (mobile renderer), GDScript, Theme .tres, SVG icons, UiJuice animation helpers.

**Design direction (user-confirmed):** Restyle in place (bottom-right floating panel). New header + 3 icon rows + dividers. 2 new Lucide SVGs allowed (user + settings). NO chevrons (rows mirror SeekerMenuSheet which has none — `ponytail:` keep it simple, chevrons can come later if wanted).

---

## Design tokens (read from `themes/mobile_theme.tres` — use these exact values)

- Surface navy: `Color(0.035, 0.055, 0.125, ~0.97)` (same family as ModalPanel/BottomSheetPanel)
- Row bg: `Color(0.07, 0.105, 0.205, 0.92)` (same family as ResourceChip)
- Row hover bg: `Color(0.105, 0.16, 0.29, 0.98)` (ButtonHover family)
- Accent cyan: `Color(0.278, 0.902, 1, …)` — borders, title eyebrow, hover
- Gold: `Color(1, 0.82, 0.4, …)` — pressed border, pressed icon
- Corner radii: 16 (rows), 28 (panel)
- Fonts: display = ExtResource "2_display" (Oxanium) for the title; body = NunitoSans
- Border style: 2px everywhere; panel gets 3px top accent border (the "outline" nod)
- Shadow: black `Color(0,0,0,0.55)`, size 24, offset `(0, 10)`
- Button focus style: reuse existing `ButtonFocus` sub_resource (gold 4px outline) — consistent with every other button in the game

Existing theme references to copy patterns from: `ModalPanel` (panel), `ResourceChip` (row bg/border), `ButtonHover`/`ButtonPressed` (row states), `EyebrowLabel` (title). `PanelContainer/styles/panel` default is `GlassPanel` — do not change the default; add dedicated variations.

---

## Current state (verified in code)

- `MenuPopover` = full-screen `Control` (z_index 40) inside `scenes/scan_flow.tscn` under `UI`
- `MenuBackdrop` = flat `Button` (invisible click-catcher, closes on press)
- `MenuPanel` = `PanelContainer`, 336 wide, anchored bottom-right (`offset_left=-352, offset_top=-500, offset_right=-16, offset_bottom=-156`), variation `ModalPanel`, contains `MenuColumn` (VBox) with 3 buttons: `MenuProfile` (PrimaryButton), `MenuAtlas`, `MenuSettings` (default buttons, 96px each)
- `scripts/menu_popover.gd`: `show_menu()` sets visible + `UiJuice.pop(_panel, 1.025)` + grab focus; signals `profile_requested`/`atlas_requested`/`settings_requested`; `refresh_localized_ui()` sets the 3 button texts
- Open/close toggle lives in `scripts/scan_flow.gd` (~line 1581: MENU destination toggles `_menu_popover.show_menu()/close()`)
- Tests: `game/tests/test_scan_ui.gd` (instantiates scan_flow.tscn off-tree — already references the popover), `game/tests/test_i18n.gd` (checks all `tr()` keys resolve)
- Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot` (4.6). Run from `game/` dir.

---

## Task 1: Add 2 Lucide SVG icons

**Objective:** Provide `user.svg` (Seeker Profile) and `settings.svg` (Settings) icons matching the existing icon style.

**Files:**
- Create: `game/assets/icons/user.svg`
- Create: `game/assets/icons/settings.svg`

**Steps:**

1. Copy the exact style of `game/assets/icons/library.svg` (24×24 viewBox, `fill="none"`, `stroke="#EAF5FF"`, `stroke-width="2"`, `stroke-linecap="round"`, `stroke-linejoin="round"`) and write the standard Lucide paths:
   - `user.svg`: circle cx=12 cy=8 r=5 + path `M20 21a8 8 0 0 0-16 0`
   - `settings.svg`: gear — use the canonical Lucide settings path set (circle cx=12 cy=12 r=3 + the 8-point gear spokes path; copy from the lucide.dev settings icon, it is MIT/Lucide-licensed and this repo already ships `LICENSE-LUCIDE.txt`)
2. Regenerate imports so Godot picks up the new SVGs:
   Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import`
   Expected: no errors; `user.svg.import` and `settings.svg.import` appear next to the SVGs.

**Verification:** both `.svg.import` files exist; the import run exits clean.

---

## Task 2: Add theme variations to `mobile_theme.tres`

**Objective:** One new panel stylebox, one title label variation, one rich row-button variation.

**Files:**
- Modify: `game/themes/mobile_theme.tres` (new sub_resources near the other StyleBoxFlat blocks; new variation lines in the `[resource]` table, keep alphabetical-ish grouping as the file already does)

**Steps:**

1. Add `StyleBoxFlat` `MenuPopoverPanel` (place before `[resource]`):
   - content margins: left 28, top 24, right 28, bottom 28
   - `bg_color = Color(0.035, 0.055, 0.125, 0.97)`
   - border_width: left 2, top 3, right 2, bottom 2
   - `border_color = Color(0.278, 0.902, 1, 0.55)`
   - corner_radius = 28 all corners
   - `shadow_color = Color(0, 0, 0, 0.55)`, `shadow_size = 24`, `shadow_offset = Vector2(0, 10)`
2. Add `StyleBoxFlat` `MenuRowNormal`: content margins left 20, top 14, right 20, bottom 14; `bg_color = Color(0.07, 0.105, 0.205, 0.92)`; border_width 2; `border_color = Color(0.278, 0.902, 1, 0.22)`; corner_radius 16
3. Add `StyleBoxFlat` `MenuRowHover`: same margins/radius; `bg_color = Color(0.105, 0.16, 0.29, 0.98)`; border 2px `Color(0.278, 0.902, 1, 0.7)`; `shadow_color = Color(0.157, 0.78, 1, 0.16)`, `shadow_size = 10`, `shadow_offset = Vector2(0, 4)`
4. Add `StyleBoxFlat` `MenuRowPressed`: same margins/radius; `bg_color = Color(0.035, 0.065, 0.14, 1)`; border 2px `Color(1, 0.82, 0.4, 0.95)`
5. Add variation `MenuPopoverPanel` → `PanelContainer/styles/panel = SubResource("MenuPopoverPanel")`
6. Add variation `MenuPopoverTitle` (base_type `&"Label"`): `fonts/font = ExtResource("2_display")`, `font_sizes/font_size = 32`, `colors/font_color = Color(0.97, 0.985, 1, 1)`
7. Add variation `MenuRowButton` (base_type `&"Button"`): `colors/font_color = Color(0.94, 0.965, 1, 1)`, hover/pressed white/gold like the base Button; `colors/icon_normal_color = Color(0.88, 0.93, 1, 1)`, `icon_hover_color = Color(1, 1, 1, 1)`, `icon_pressed_color = Color(1, 0.86, 0.48, 1)`; `constants/icon_max_width = 38`; `font_sizes/font_size = 28`; `styles/disabled = SubResource("ButtonDisabled")`, `styles/focus = SubResource("ButtonFocus")`, `styles/hover = SubResource("MenuRowHover")`, `styles/normal = SubResource("MenuRowNormal")`, `styles/pressed = SubResource("MenuRowPressed")`

**Verification:** `grep -c "MenuPopoverPanel\|MenuRowButton\|MenuPopoverTitle" game/themes/mobile_theme.tres` → 3+ hits; theme parses (Godot import in Task 6 covers this).

---

## Task 3: Add MENU_TITLE localization key

**Objective:** Key for the popover header.

**Files:**
- Modify: `game/locales/ui.csv` (format: `keys,en` header, values quoted)

**Steps:**

1. Add row after `MENU_SETTINGS` (line ~624): `MENU_TITLE,"Menu"`
2. Do NOT hand-edit `ui.en.translation` — Godot regenerates it on import (covered in Task 6).

**Verification:** `grep -n "MENU_TITLE" game/locales/ui.csv` → 1 hit.

---

## Task 4: Restructure the MenuPopover subtree in `scan_flow.tscn`

**Objective:** New panel look: dim backdrop, header + divider, three icon rows.

**Files:**
- Modify: `game/scenes/scan_flow.tscn` (MenuPopover subtree, lines ~283–345)

**Steps:**

1. `MenuPanel` (PanelContainer): change `theme_type_variation` from `&"ModalPanel"` to `&"MenuPopoverPanel"`; keep current anchors/offsets (bottom-right floating position stays); adjust `offset_top` as needed so the taller content fits (content grows: header + divider + 3 rows ≈ 380–440px tall — recompute `offset_top = offset_bottom - height` keeping the same 16px right/bottom gutters; the design is a compact floating panel, do NOT stretch to the screen edges).
2. `MenuColumn` (VBoxContainer): set `theme_override_constants/separation = 14`.
3. Inside `MenuColumn`, BEFORE `MenuProfile`, add:
   - `MenuTitle` — `Label`, `theme_type_variation = &"MenuPopoverTitle"`, `text = "MENU_TITLE"`, `unique_name_in_owner = true`
   - `MenuDivider` — `HSeparator` (theme default `HSeparator/styles/separator` = cyan, already defined)
4. `MenuProfile`: change variation to `&"MenuRowButton"`, add `icon = ExtResource` pointing to `user.svg`, `alignment = 0` (left), keep `custom_minimum_size = Vector2(0, 96)` and the `MENU_SEEKER_PROFILE` text and `unique_name_in_owner`.
5. `MenuAtlas`: same treatment with `library.svg` (existing asset — reuse, do not copy the file).
6. `MenuSettings`: same treatment with `settings.svg`.
7. Keep `MenuBackdrop` exactly as-is (flat click-catcher).
8. Add backdrop dim: insert a `ColorRect` named `MenuDim` as the FIRST child of `MenuPopover` (before `MenuBackdrop`), full-rect anchors (0..1), `color = Color(0, 0, 0, 0.45)`, `mouse_filter = 2` (IGNORE — clicks must reach `MenuBackdrop`), `unique_name_in_owner = true`. `ponytail:` if the dim causes any focus/input regression, drop it and keep the invisible backdrop — it is polish, not the core ask.

**Verification:** tscn has exactly 3 `MenuRowButton` rows + `MenuTitle` + `MenuDivider` + `MenuDim`; `MenuPanel` uses `MenuPopoverPanel`.

---

## Task 5: Minimal `menu_popover.gd` additions

**Objective:** Refresh the title label on locale change; fade the dim in on open.

**Files:**
- Modify: `game/scripts/menu_popover.gd`

**Steps:**

1. Add `@onready var _title: Label = %MenuTitle` and `@onready var _dim: ColorRect = %MenuDim`.
2. In `refresh_localized_ui()`: add `_title.text = tr("MENU_TITLE")`.
3. In `show_menu()`: before `UiJuice.pop(...)`, set `_dim.modulate.a = 0.0` then tween to `1.0` over ~0.15s (`create_tween()`, `set_trans(Tween.TRANS_QUAD)`); keep `UiJuice.pop(_panel, 1.025)` and `_profile.grab_focus()`.
4. Leave `close()` instant (existing behavior). Do not add open/close animation for the panel itself beyond the existing pop.
5. Do not touch signals, `_choose_*`, or focus logic.

**Verification:** script compiles (Task 6 covers); `MENU_TITLE` resolves in `test_i18n.gd`.

---

## Task 6: Full verification

**Objective:** Prove the restyle parses, tests pass, and the popover opens cleanly.

**Steps:**

1. Import + compile check:
   Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import`
   Expected: exit 0, no script/parse errors (this regenerates `ui.en.translation` from the csv and the new `.svg.import` files).
2. Run the UI contract test (instantiates `scan_flow.tscn`, covers popover wiring):
   Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://tests/test_scan_ui.gd`
   Expected: exits 0 with all checks passing. If the test asserts popover button texts/visibility, it must still pass; if it fails because of the new nodes, FIX THE TEST minimally (the popover contract — signals, texts, toggle — must remain intact).
3. Run the i18n test (new `MENU_TITLE` key):
   Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://tests/test_i18n.gd`
   Expected: exits 0.
4. Visual check (requires the desktop app — do it last, report the result honestly):
   - Open the project in the Godot editor (`/Applications/Godot.app` → import `game/project.godot`) or run `--path game`; press the Menu tab in the bottom nav; confirm: floating panel bottom-right, dim backdrop, Oxanium "MENU" header, cyan divider, 3 rows with icons (user / library / settings), cyan hover glow, gold pressed, focus ring on the first row, tap-outside closes.
   - If GodotIQ is available in the running editor, use it for a screenshot instead of manual play.
5. Commit with a clear message, e.g. `feat(ui): restyle Menu popover to Scanima design language`.

---

## Acceptance criteria (Ryan will eyeball these)

- [ ] Panel stays floating bottom-right (no full-screen sheet, no position change)
- [ ] Header "MENU" in Oxanium + divider — visible and on-brand
- [ ] 3 rows with icons (user, library, settings), left-aligned, 96px tall
- [ ] Hover = cyan glow, pressed = gold border, focus ring visible (keyboard/gamepad nav)
- [ ] Dim backdrop fades in; pop animation retained; tap-outside closes
- [ ] Localized text still updates on locale change; `test_scan_ui.gd` + `test_i18n.gd` pass
- [ ] No logic/backend/other-view changes (diff limited to the popover + theme + icons + csv)

---

## Risks / tradeoffs / open questions

- **Panel height:** content is taller than before; if the panel overflows the safe area on small screens, shrink row height to 88px rather than moving the panel (mobile tap target ≥ 96px is the current contract — test_scan_ui asserts `TOUCH_MIN = 96.0`, so prefer keeping 96px and shrinking only if the test allows).
- **Dim backdrop:** purely visual; if it interferes with input routing, drop `MenuDim` (Task 4 step 8 note).
- **Icon import:** new SVGs need the `.import` files; Task 6 step 1 regenerates them. If headless import is flaky, open the editor once so Godot imports the assets.
- **No chevrons** by design (matches SeekerMenuSheet rows). Future polish can add a right chevron via `flip_h` of `chevron-left.svg`.
