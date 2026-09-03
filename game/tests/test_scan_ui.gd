extends SceneTree

## Free contract test for the production mobile shell. The scene is instantiated
## off-tree, so no authentication or network requests run.

const TOUCH_MIN := 96.0
const BATTLE_SCALE := preload("res://scripts/battle_scale.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _requested_delete_id := ""
var _requested_evolve_row: Dictionary = {}
var _requested_synthesis_id := ""
var _requested_rename_id := ""
var _requested_gallery_appeal_id := ""
var _requested_profile_id := ""
var _requested_summon_id := ""
var _requested_summon_synced := false
var _requested_summon_hunger := 0.0
var _home_action := ""
var _home_care_action := ""
var _home_care_blocked := ""
var _preview_requests := 0
var _help_title := ""
var _help_body := ""
var _item_picker_opens := false


func _initialize() -> void:
	# Jalur yang sama dengan `scan_flow._enter_tree()`; shell di sini hidup di luar
	# pohon, jadi tanpa ini relay gulir sentuh tidak pernah terpasang saat diuji.
	UiJuice.install_touch_scroll(self)
	var packed := load("res://scenes/scan_flow.tscn") as PackedScene
	_check(packed != null, "scan_flow.tscn must load")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	_check(scene != null, "scan_flow.tscn must instantiate")
	if scene == null:
		_finish()
		return

	var sleep_delay: float = float(scene.call("sleep_completion_delay", {
		"sleep_started_at": "2026-08-13T00:00:00+00:00",
		"care_synced_at": "2026-08-13T05:59:00+00:00",
	}))
	_check(absf(sleep_delay - 61.0) < 0.1, "sleep timer targets the six-hour server deadline")
	_check(
		float(scene.call("sleep_completion_delay", {})) < 0.0,
		"awake Anima does not schedule a sleep completion sync"
	)

	_check_full_rect(scene.find_child("SafeMargin", true, false) as Control, "safe margin")
	for name in [
		"HomeView", "ScanView", "BattleView", "CollectionView", "SynthesisLabView",
		"AnimaDetailsView", "SeekerProfileView", "AtlasView",
	]:
		var view := scene.find_child(name, true, false) as Control
		_check(view != null, "%s must exist" % name)
		if view != null:
			_check_full_rect(view, name)

	var home := scene.find_child("HomeView", true, false) as Control
	var scan := scene.find_child("ScanView", true, false) as Control
	var battle := scene.find_child("BattleView", true, false) as Control
	var collection := scene.find_child("CollectionView", true, false) as Control
	var synthesis := scene.find_child("SynthesisLabView", true, false) as Control
	var details := scene.find_child("AnimaDetailsView", true, false) as Control
	var seeker_profile := scene.find_child("SeekerProfileView", true, false) as Control
	var atlas := scene.find_child("AtlasView", true, false) as Control
	_check(home != null and home.visible, "Home is the default destination")
	_check(scan != null and not scan.visible, "Scan starts hidden")
	_check(battle != null and not battle.visible, "Battle starts hidden")
	_check(collection != null and not collection.visible, "Collection starts hidden")
	_check(synthesis != null and not synthesis.visible, "Synthesis Lab starts hidden")
	_check(details != null and not details.visible, "Details starts hidden")
	_check(seeker_profile != null and not seeker_profile.visible, "Seeker profile starts hidden")
	_check(atlas != null and not atlas.visible, "Atlas starts hidden")
	for scroll_name in [
		"ScanScroll", "HomeControlsScroll", "DetailsScroll", "SynthesisIncubatingScroll",
		"BattleLobbyScroll", "TeamBuilderScroll", "TeamLobbyScroll", "ExpeditionMenuScroll",
	]:
		_check(
			scene.find_child(scroll_name, true, false) is ScrollContainer,
			"%s protects short mobile viewports" % scroll_name
		)
	for content_name in [
		"HomeControlsContent", "LobbyColumn", "TeamBuilder", "TeamLobby",
		"ExpeditionMenuContent", "IncubatingColumn",
	]:
		var scroll_content := scene.find_child(content_name, true, false) as Control
		_check(
			scroll_content != null and scroll_content.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
			"%s fills its vertical scroll viewport" % content_name
		)
	var scan_scroll := scene.find_child("ScanScroll", true, false) as ScrollContainer
	var profile_popover := scene.find_child("ProfileActionPopover", true, false) as Control
	var seeker_popover := scene.find_child("SeekerActionPopover", true, false) as Control
	_check(
		scan_scroll != null and scan_scroll.anchor_right == 1.0 and scan_scroll.anchor_bottom == 1.0
		and scan_scroll.offset_right == 0.0 and scan_scroll.offset_bottom == 0.0,
		"Scan scroll fills the destination instead of collapsing to zero height"
	)
	_check(
		profile_popover != null and profile_popover.anchor_right == 1.0
		and profile_popover.anchor_bottom == 1.0 and profile_popover.offset_right == 0.0
		and profile_popover.offset_bottom == 0.0,
		"Profile popover clamps against the whole safe viewport"
	)
	_check(
		seeker_popover != null and seeker_popover.anchor_right == 1.0
		and seeker_popover.anchor_bottom == 1.0 and seeker_popover.offset_right == 0.0
		and seeker_popover.offset_bottom == 0.0,
		"Seeker Profile popover clamps against the whole safe viewport"
	)
	_check(
		not (scene.find_child("BattleContent", true, false).get_parent() is ScrollContainer)
		and not (scene.find_child("TeamArena", true, false).get_parent() is ScrollContainer),
		"active combat arenas stay fixed while menu states scroll"
	)

	for name in [
		"ScanButton", "HomeNavButton", "ScanNavButton", "BattleNavButton",
		"CollectionNavButton", "MenuNavButton",
		"FeedButton", "CleanButton", "SleepButton", "PlayButton", "ProfileMenuButton",
		"ProfileActionRename", "ProfileActionDelete", "GalleryPublishButton",
		"EvolveAnimaButton", "SynthesisAnimaButton",
		"SynthesisSourceACard",
		"SynthesisSourceBCard", "SynthesisPickerBack", "SynthesisDominantA", "SynthesisBalanced",
		"SynthesisDominantB", "SynthesisReviewButton", "SynthesisConfirmButton", "SynthesisResultButton",
		"AtlasLoadMore",
		"HomePrimaryAction", "CollectionEmptyAction", "CollectionProfileButton",
		"CollectionSummonButton", "BattlePickProfileButton", "BattlePickBattleButton",
		"BattleStartButton", "BattleTeamButton", "BattleExpeditionButton", "BattleStrikeButton",
		"BattleSurgeButton", "BattleGuardButton", "BattleItemButton", "BattleForfeitButton", "BattleRetryButton",
		"BattleLeaveButton",
		"TeamBackButton", "TeamSaveButton", "TeamEditButton", "TeamDefenseButton",
		"TeamRefreshButton", "TeamStartButton", "TeamAttackButton", "TeamSpecialButton",
		"TeamGuardButton", "TeamItemButton", "TeamSwitchButton", "TeamForfeitButton",
		"TeamSwitchSlot0", "TeamSwitchSlot1", "TeamSwitchSlot2", "TeamSwitchSlot3",
		"TeamRetryButton", "TeamLeaveButton",
		"ExpeditionChoiceAbandon",
		"OnboardingSubmit", "SeekerProfileBack", "SeekerProfileMenu",
		"SeekerActionRename", "SeekerActionDelete",
		"ChapterPush", "MenuProfile", "MenuAtlas", "MenuSettings",
		"SeekerAccount", "SeekerHelp",
	]:
		var button := scene.find_child(name, true, false) as Button
		_check(button != null, "%s must exist" % name)
		if button != null:
			_check(
				button.custom_minimum_size.y >= TOUCH_MIN,
				"%s must be at least %.0f px tall" % [name, TOUCH_MIN]
			)

	_check(scene.find_child("AnimaNavButton", true, false) == null, "Anima Profile is not a bottom nav tab")
	var menu_nav := scene.find_child("MenuNavButton", true, false) as Button
	var menu_label := menu_nav.find_child("Label", true, false) as Label if menu_nav != null else null
	_check(
		menu_label != null and (menu_label.text == "NAV_MENU" or menu_label.text == tr("NAV_MENU")),
		"Menu tab is the launcher instead of a profile destination"
	)
	var menu_popover := scene.find_child("MenuPopover", true, false) as Control
	_check(menu_popover != null and not menu_popover.visible, "Menu popover starts closed")
	var menu_source := FileAccess.get_file_as_string("res://scripts/menu_popover.gd")
	_check(
		menu_source.find("size = get_viewport_rect().size") >= 0,
		"Menu popover fills the viewport when opened from a CanvasLayer"
	)
	var list := scene.find_child("AnimaList", true, false) as ItemList
	_check(list != null, "AnimaList must exist")
	if list != null:
		_check(list.max_columns >= 2, "collection keeps at least two columns")
		_check_eq(list.fixed_icon_size, Vector2i(128, 128), "collection thumbnails are 128 px")
	var scan_flow := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var backend_flow := FileAccess.get_file_as_string("res://scripts/backend.gd")
	_check(
		scan_flow.find("_prepare_signed_battle_art") >= 0
		and scan_flow.find("ATLAS_DEST") >= 0,
		"scan_flow wires atlas destination and signed battle art"
	)
	_check(backend_flow.find("func atlas(") >= 0, "Backend exposes atlas transport")
	_check(
		scan_flow.find("CareRules.collection_pose") >= 0
		and scan_flow.find("begin_visit()") >= 0
		and scan_flow.find("_populate_collection()") >= 0,
		"Collection thumbnails project Sleep, Hungry, Dirty, or Idle when the tab opens"
	)
	_check(
		scan_flow.find("_queue_thumbnail_backfill(row, anima_id, stage)") >= 0
		and scan_flow.find("_thumbnail_backfill_inflight.has(art_key)") >= 0,
		"a roster row with no cached art queues a background backfill instead of staying placeholder forever"
	)
	var backfill_start := scan_flow.find("func _run_thumbnail_backfill")
	var backfill_end := scan_flow.find("func _update_hud_identity", backfill_start)
	var backfill_body := (
		scan_flow.substr(backfill_start, backfill_end - backfill_start)
		if backfill_start >= 0 and backfill_end > backfill_start
		else ""
	)
	_check(
		backfill_body.find("await _prepare_anima_art(") >= 0
		and backfill_body.find("_populate_collection.call_deferred()") >= 0
		and backfill_body.find("GameState.session_epoch != account_epoch") >= 0,
		"backfill downloads real art serially, repopulates on arrival, and abandons on account switch"
	)
	_check(
		scan_flow.find("_thumbnail_backfill_queue.clear()") >= 0
		and scan_flow.find("_thumbnail_backfill_inflight.clear()") >= 0,
		"account reset clears the backfill queue so a new account doesn't inherit stale attempts"
	)
	var present_start := scan_flow.find("func _present(")
	var present_merge_end := scan_flow.find("}, true)", present_start)
	var present_merge_body := (
		scan_flow.substr(present_start, present_merge_end - present_start)
		if present_start >= 0 and present_merge_end > present_start
		else ""
	)
	_check(
		present_merge_body.find("\"sheet_path\": sheet_path") >= 0,
		"Discovery Scan (cache_hit) carries sheet_path into _current_anima, or Collection can never find its art"
	)
	_check(
		scan_flow.find("_warn_if_boot_is_slow()") >= 0
		and scan_flow.find("func _warn_if_boot_is_slow") >= 0
		and scan_flow.find("STATUS_LOADING_SLOW") >= 0,
		"a slow boot swaps the Loading screen to a still-connecting hint instead of a silent indefinite spinner"
	)
	var active_start := scan_flow.find("func _active_row")
	var active_end := scan_flow.find("func _sync_collection_preview", active_start)
	var active_body := (
		scan_flow.substr(active_start, active_end - active_start)
		if active_start >= 0 and active_end > active_start
		else ""
	)
	_check(
		active_body.find("active_anima_id") >= 0,
		"boot prefers the server-summoned companion over last_anima"
	)
	var collection_sheet := scene.find_child("CollectionSheetOverlay", true, false) as Control
	var collection_panel := scene.find_child("CollectionSheetPanel", true, false) as PanelContainer
	_check(collection_sheet != null and not collection_sheet.visible, "Collection sheet starts hidden")
	_check(
		collection_panel != null
		and collection_panel.anchor_top == 1.0
		and collection_panel.anchor_bottom == 1.0,
		"Collection sheet stays bottom anchored"
	)

	var margin := scene.find_child("SafeMargin", true, false) as MarginContainer
	_check(margin != null and margin.theme != null, "mobile theme must be attached")
	if margin != null and margin.theme != null:
		_check(margin.theme.default_font_size >= 32, "default font is readable at the 2x baseline")
		_check(margin.theme.default_font != null, "commercial UI font must be bundled")
		for variation in [
			"PrimaryButton", "VibeSelected", "DangerButton", "CareDock", "BottomNavPanel", "NavTabButton", "ToastPanel",
			"NeedChip", "NeedChipLow",
		]:
			_check(
				margin.theme.get_type_variation_base(StringName(variation)) != StringName(),
				"theme must provide %s" % variation
			)
		# The nav lives inside SafeMargin but the design draws it edge to edge, so
		# it bleeds back out by exactly the margins the shell applied. Two
		# mechanisms are needed and only one of them is obvious: expand margins
		# stretch what the StyleBox paints, but a NEGATIVE content margin cannot
		# move the children, because StyleBox.get_margin() reads any negative
		# content margin as "unset" and silently substitutes the style margin.
		# The Bleed MarginContainer is what actually widens the child rect.
		var shell_script := load("res://scripts/scan_flow.gd")
		var side: float = shell_script.BASE_MARGIN
		var bottom: float = shell_script.HUD_TOP_PAD
		var nav_panel := margin.theme.get_stylebox(&"panel", &"BottomNavPanel") as StyleBoxFlat
		_check(nav_panel != null, "the bottom nav keeps a flat panel to bleed from")
		if nav_panel != null:
			_check(
				is_equal_approx(nav_panel.expand_margin_left, side)
				and is_equal_approx(nav_panel.expand_margin_right, side)
				and is_equal_approx(nav_panel.expand_margin_bottom, bottom),
				"the nav bar paints out to the screen edges the shell margins reserved"
			)
			_check(
				nav_panel.content_margin_left >= 0.0 and nav_panel.content_margin_bottom >= 0.0,
				"it never tries to negate those margins through the StyleBox"
			)
		# The selected tab is exported art too, not a StyleBoxFlat approximation:
		# the design's pill is a vertical gradient at 20% alpha and StyleBoxFlat
		# has no gradient, so a flat fill would always be a guess. Drawn 1:1 from
		# a 2x texture, hence no texture_margin_* — 9-slice corners would render
		# at authoring pixels and double the radius.
		var pill := margin.theme.get_stylebox(&"pressed", &"NavTabButton") as StyleBoxTexture
		_check(pill != null, "the selected tab is drawn from a texture, not a flat box")
		if pill != null:
			_check(
				pill.texture != null
				and pill.texture.resource_path == "res://assets/ui/nav_tab_selected.png",
				"and that texture is the committed asset from the design"
			)
			_check(
				is_equal_approx(pill.texture_margin_left, 0.0)
				and is_equal_approx(pill.texture_margin_top, 0.0),
				"it stretches whole instead of nine-slicing a 2x source"
			)
			# 114.8px cell minus 7.4 a side is the design's 100px pill.
			_check(
				pill.expand_margin_left < 0.0
				and is_equal_approx(pill.expand_margin_left, pill.expand_margin_right),
				"and it shrinks symmetrically to the design's pill width"
			)
		var nav_text := margin.theme.get_color(&"font_shadow_color", &"NavTabLabel")
		_check(
			nav_text.a == 0.0,
			"nav labels drop the global Label shadow the design does not draw"
		)
		var bleed := scene.find_child("Bleed", true, false) as MarginContainer
		_check(bleed != null, "a Bleed container carries the nav's children past the safe margin")
		if bleed != null:
			_check(
				bleed.get_theme_constant(&"margin_left") == int(-side)
				and bleed.get_theme_constant(&"margin_right") == int(-side)
				and bleed.get_theme_constant(&"margin_bottom") == int(-bottom),
				"and it widens them by the same amount the panel paints"
			)

	var background := scene.find_child("Background", true, false) as Node2D
	_check(background != null and background.get_script() != null, "procedural background remains attached")
	_check(scene.find_child("TopHud", true, false) is PanelContainer, "compact resource HUD must exist")
	var brand := scene.find_child("Brand", true, false) as Label
	var resources := scene.find_child("Resources", true, false) as HBoxContainer
	var cores_chip := scene.find_child("CoresChip", true, false) as PanelContainer
	var bits_chip := scene.find_child("BitsChip", true, false) as PanelContainer
	_check(brand != null, "HUD exposes the Seeker identity label")
	_check(
		scene.find_child("AnimasChip", true, false) == null
		and resources != null and resources.get_child_count() == 2,
		"HUD keeps only Cores and Bits resource chips",
	)
	_check(cores_chip != null and cores_chip.get_script() != null, "HUD uses the shared Cores chip")
	_check(bits_chip != null and bits_chip.get_script() != null, "HUD uses the shared Bits chip")
	var bottom_nav := scene.find_child("BottomNav", true, false) as BottomNav
	var battle_badge := scene.find_child("BattleNewBadge", true, false) as Label
	bottom_nav.set_battle_badge(true)
	_check(battle_badge.visible, "new chapter state reaches the persistent Battle nav badge")
	bottom_nav.set_battle_badge(false)
	var shop := scene.find_child("ShopButton", true, false) as PanelContainer
	var bag := scene.find_child("BagButton", true, false) as PanelContainer
	_check(shop != null and shop.get_script() != null, "Shop uses the same chip as Bits")
	_check(bag != null and bag.get_script() != null, "Bag uses the same chip as Shop")
	_check(
		shop.get_parent() != bits_chip.get_parent()
		and shop.get_parent() != null
		and String(shop.get_parent().name) == "RightButtons",
		"Shop sits in the HUD's own bottom row instead of splitting the resource row"
	)
	_check(
		bag.get_parent() == shop.get_parent(),
		"Bag sits on the same row as Shop"
	)
	_check(
		shop.custom_minimum_size.y >= TOUCH_MIN and bag.custom_minimum_size == shop.custom_minimum_size,
		"Shop and Bag keep the 96px press target and stay the same size"
	)
	# The two HUD badges are the one deliberate exception to the 48dp floor:
	# read-only counters sized to the design, not primary actions.
	_check(
		cores_chip.custom_minimum_size.y == 59.0
		and bits_chip.custom_minimum_size.y == 59.0,
		"HUD badges stay compact so the header reads as a bar, not a slab"
	)
	_check(
		bits_chip.custom_minimum_size.y < shop.custom_minimum_size.y,
		"the compact badges never drag the Shop and Bag press targets down with them"
	)
	for chip in [cores_chip, bits_chip, shop, bag]:
		var column := chip.get_node_or_null("Column") as BoxContainer
		_check(
			column != null and column.alignment == BoxContainer.ALIGNMENT_CENTER,
			"%s centers its content inside the press target" % chip.name
		)
		# `Column` must stay a plain BoxContainer: a VBoxContainer rejects
		# `vertical = false` and keeps stacking, so the badges would quietly
		# stay two-line with only a console error to show for it.
		_check(
			column != null and column.get_class() == "BoxContainer",
			"%s can still flip its axis at runtime" % chip.name
		)
	for action in [shop, bag]:
		_check(
			(action.get_node("Column") as BoxContainer).vertical,
			"%s keeps its icon above the label like a nav tab" % action.name
		)
	_check(
		shop.find_child("Icon", true, false) is TextureRect,
		"Shop chip has an icon slot"
	)
	_check(
		bag.find_child("Icon", true, false) is TextureRect,
		"Bag chip has an icon slot"
	)
	# Shop and Bag are actions, so they read like the nav tabs do — painted icon
	# over a label, no surface. The three badges beside them are counters and
	# keep theirs, which is the whole reason the split lives in two theme
	# variations rather than one. A dropped variation puts the boxes back and
	# nothing on screen complains. The stylebox is resolved through the theme
	# rather than `get_theme_stylebox()` because this shell is never added to the
	# tree, and a detached Control answers with the plain PanelContainer default
	# no matter which variation it wears — the assertion would pass on Bits and
	# fail on Shop for reasons that have nothing to do with either.
	var chip_theme := load("res://themes/mobile_theme.tres") as Theme
	for chip in [shop, bag, cores_chip, bits_chip]:
		var surfaced := not (
			chip_theme.get_stylebox(&"panel", chip.theme_type_variation) is StyleBoxEmpty
		)
		var is_badge: bool = chip != shop and chip != bag
		_check(
			surfaced == is_badge,
			"%s wears %s" % [
				chip.name,
				"the surface that marks a counter" if is_badge else "its icon without a container",
			]
		)
	_check(
		scene.find_child("BagGutter", true, false) == null
		and scene.find_child("ShopGutter", true, false) == null,
		"non-Home headers do not reserve space for hidden Bag and Shop buttons"
	)
	var battle_pick := scene.find_child("BattlePickSheet", true, false) as Control
	_check(
		battle_pick != null and battle_pick.z_index >= 20,
		"Battle picker paints above immersive fighters and terminal result panels"
	)
	var shop_sheet_node := scene.find_child("ShopSheet", true, false) as Control
	_check(
		shop_sheet_node != null and shop_sheet_node.z_index >= 20,
		"ShopSheet (battle item picker) paints above Anima sprites (z_index 3 & 2)"
	)
	_check(scene.find_child("ScanCount", true, false) == null, "HUD no longer labels scan charges as a count")
	_check(scene.find_child("BottomNav", true, false) is PanelContainer, "bottom navigation must exist")
	var toast := scene.find_child("StatusPanel", true, false) as PanelContainer
	_check(toast != null, "floating feedback must exist")
	if toast != null:
		_check_eq(toast.anchor_top, 0.0, "toast pins below the HUD instead of mid-screen")
		_check_eq(toast.anchor_bottom, 0.0, "toast does not stretch through the Anima")
	var toast_layer := scene.find_child("ToastLayer", true, false) as Control
	var shop_sheet := scene.find_child("ShopSheet", true, false) as Control
	_check(
		toast_layer != null
		and shop_sheet != null
		and toast_layer.get_parent() == shop_sheet.get_parent()
		and toast_layer.get_index() > shop_sheet.get_index(),
		"toasts paint above the Shop sheet so NO_BITS stays visible"
	)
	# Shop and Bag used to share the toast layer, which meant the sheet's own
	# backdrop dimmed the whole shell except the two buttons that opened it.
	# They need opposite sides of the sheet: chips under it, toast over it.
	# Shop now lives several rows deep inside TopHud instead of a flat overlay,
	# so this walks up to whichever ancestor is a direct sibling of the sheet.
	var shop_shell_ancestor := shop.get_parent()
	while (
		shop_shell_ancestor != null
		and shop_shell_ancestor.get_parent() != shop_sheet.get_parent()
	):
		shop_shell_ancestor = shop_shell_ancestor.get_parent()
	_check(
		shop_shell_ancestor != null
		and shop_shell_ancestor.get_parent() == shop_sheet.get_parent()
		and shop_shell_ancestor.get_index() < shop_sheet.get_index(),
		"the sheet backdrop dims Shop and Bag along with the rest of the shell"
	)
	# The flip side of that order: every sheet now paints over the chips, so a
	# sheet left visible while closed would swallow the taps that open it.
	for sheet_name in [
		"ShopSheet",
		"BattlePickSheet",
		"PhotoSourceSheet",
		"SeekerMenuSheet",
		"SeekerOnboardingSheet",
	]:
		var idle := scene.find_child(sheet_name, true, false) as Control
		_check(
			idle != null and not idle.visible,
			"%s starts hidden so it never eats a Shop or Bag tap" % sheet_name
		)
	_check(scene.find_child("PoseRow", true, false) == null, "debug pose controls must not ship in production")
	var shell_modal := scene.find_child("ShellModal", true, false) as Control
	var modal_panel := scene.find_child("ModalPanel", true, false) as PanelContainer
	var modal_input := scene.find_child("ModalInput", true, false) as LineEdit
	var modal_cancel := scene.find_child("CancelButton", true, false) as Button
	var modal_primary := scene.find_child("PrimaryButton", true, false) as Button
	var modal_choice_cancel := scene.find_child("ChoiceCancelButton", true, false) as Button
	_check(shell_modal != null and not shell_modal.visible, "shared shell modal starts hidden")
	_check(
		shell_modal.z_index >= 10,
		"shell modal paints above battle sprites so Retreat confirm stays readable"
	)
	_check(
		modal_panel != null and modal_panel.theme_type_variation == &"ModalPanel",
		"all blocking dialogs share one modal chrome"
	)
	_check(
		modal_primary != null
		and modal_primary.custom_minimum_size.y >= TOUCH_MIN
		and modal_cancel != null
		and modal_cancel.custom_minimum_size.y >= TOUCH_MIN
		and modal_choice_cancel != null
		and modal_choice_cancel.custom_minimum_size.y >= TOUCH_MIN,
		"shared modal actions meet the touch target"
	)
	_check(
		modal_input != null
		and modal_input.max_length == 32
		and modal_input.custom_minimum_size.y >= TOUCH_MIN,
		"shared input mode enforces the server name length and touch target"
	)
	var modal_probe := (load("res://scenes/ui/ui_modal.tscn") as PackedScene).instantiate()
	await process_frame
	root.add_child(modal_probe)
	modal_probe.open_info("first", "first body", "Continue")
	await create_timer(0.35).timeout
	# Continue closes and reopens in one frame. The dismiss fade lasts 0.18 s, so
	# wait it out: if the reopen were treated as "already shown", the pending fade
	# would hide the next Anima's stats and the Expedition queue would never reach
	# Return to Map.
	modal_probe.close()
	modal_probe.open_info("second", "second body", "Continue")
	await create_timer(0.35).timeout
	var probe_title := modal_probe.find_child("ModalTitle", true, false) as Label
	var probe_hero := modal_probe.find_child("ModalHero", true, false) as Label
	_check(
		modal_probe.visible and probe_title != null and probe_title.text == "second",
		"a dialog reopened during its own fade stays up, so the Level Up queue advances"
	)
	_check(
		probe_hero != null and not probe_hero.visible,
		"dialogs without a hero line hide the slot instead of leaving a gap"
	)
	modal_probe.open_info("third", "third body", "Continue", "Lv. 4")
	_check(
		probe_hero != null and probe_hero.visible and probe_hero.text == "Lv. 4",
		"the hero slot carries the Level Up number above the title's stat rows"
	)
	modal_probe.queue_free()

	var shell_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		shell_source.find("var show_chrome := _destination == BottomNav.HOME and not immersive") >= 0
		and shell_source.find("_shop_button.visible = show_chrome") >= 0
		and shell_source.find("_bag_button.visible = show_chrome") >= 0
		and shell_source.find("_top_hud.visible = not immersive") >= 0
		and shell_source.find("_bottom_nav.visible = not immersive") >= 0
		and shell_source.find("is_duel_arena_open()") >= 0
		and shell_source.find("GameState.shop_locked()") >= 0
		and shell_source.find("ERROR_SHOP_IN_BATTLE") >= 0
		and shell_source.find("_confirm_retreat.bind(\"duel\")") >= 0
		and shell_source.find("_confirm_retreat.bind(\"team\")") >= 0
		and shell_source.find("_confirm_retreat.bind(\"expedition\")") >= 0
		and shell_source.find("BATTLE_RETREAT_CONFIRM") >= 0
		and shell_source.find("BATTLE_RETREAT_CONFIRM_EXPEDITION") >= 0
		and shell_source.find("show_retreat_banner()") >= 0,
		"Bag and Shop only appear on Home, Shop locks mid-run, and Retreat asks first"
	)
	var anima_info := scene.find_child("AnimaInfo", true, false) as VBoxContainer
	var right_buttons := scene.find_child("RightButtons", true, false) as HBoxContainer
	_check(
		anima_info != null
		and right_buttons != null
		and anima_info.size_flags_horizontal & Control.SIZE_EXPAND != 0
		and right_buttons.get_parent() == anima_info.get_parent(),
		"Anima info expands so Bag and Shop are pinned to the HUD's own right edge"
	)
	_check(
		anima_info != null
		and shell_source.find("_anima_info.mouse_filter = Control.MOUSE_FILTER_STOP") >= 0
		and shell_source.find("_anima_info.gui_input.connect(_on_hud_anima_input)") >= 0
		and shell_source.find("_show_collection_profile(_current_anima)") >= 0,
		"tapping the HUD's anima name opens its Profile, same as before it moved off the Stage"
	)
	var boot_start := shell_source.find("func _boot()")
	var boot_end := shell_source.find("\n\nfunc _reload_roster", boot_start)
	var boot_body := (
		shell_source.substr(boot_start, boot_end - boot_start)
		if boot_start >= 0 and boot_end > boot_start
		else ""
	)
	_check(
		boot_body.find("STATUS_INITIALIZING") < 0,
		"Home loading copy replaces the redundant initialization toast"
	)
	var submit_start := shell_source.find("func _submit_pending_battle")
	var submit_end := shell_source.find("func _forfeit_battle", submit_start)
	var submit_body := (
		shell_source.substr(submit_start, submit_end - submit_start)
		if submit_start >= 0 and submit_end > submit_start
		else ""
	)
	var unlock_at := submit_body.find("_set_busy(false)")
	_check(
		unlock_at >= 0
		and submit_body.find("await _refresh_catalog()") < 0
		and shell_source.find("_battle_view.set_busy(false)") >= 0,
		"Battle unlocks after the event log so a follow-up Special can send"
	)
	_check(
		shell_source.find("_animas_chip") < 0
		and shell_source.find("_atlas_view.collection_requested.connect(_open_collection)") >= 0,
		"Collection remains reachable without duplicating it in the top HUD",
	)
	_check(
		shell_source.find("NOTIFICATION_WM_GO_BACK_REQUEST") >= 0
		and shell_source.find("_handle_back(true)") >= 0
		and shell_source.find("_atlas_view.is_detail_open()") >= 0
		and shell_source.find("_atlas_view.close_detail()") >= 0
		and shell_source.find("_close_open_bottom_sheet()") >= 0
		and shell_source.find("sheet.is_visible_in_tree()") >= 0
		and shell_source.find("STATUS_NEED_CORE") >= 0,
		"Android back closes Atlas and every remaining visible bottom sheet"
	)
	# Both kebabs are overlays the shell owns the exit for. A popover left open
	# while the player leaves the screen paints over whatever comes next, and
	# that is invisible to the views themselves.
	_check(
		shell_source.find("_seeker_profile_view.is_action_menu_open()") >= 0
		and shell_source.find("_details_view.close_action_menu(false)") >= 0
		and shell_source.find("_seeker_profile_view.close_action_menu(false)") >= 0,
		"Android back and destination changes close both Profile kebabs"
	)
	_check(
		shell_source.find("_shell_modal.open_input(") >= 0
		and shell_source.find("tr(\"ACTION_CANCEL\")") >= 0
		and shell_source.find("tr(\"ANIMA_RENAME_SKIP\")") < 0,
		"rename uses the shared input modal with Cancel"
	)
	if margin != null and margin.theme != null:
		_check_eq(
			margin.theme.get_color("font_focus_color", "PrimaryButton"),
			margin.theme.get_color("font_color", "PrimaryButton"),
			"focused primary labels retain readable dark contrast"
		)
		_check_eq(
			margin.theme.get_color("font_pressed_color", "PrimaryButton"),
			margin.theme.get_color("font_color", "PrimaryButton"),
			"pressed primary labels stay dark on cyan"
		)
		_check_eq(
			margin.theme.get_color("font_hover_pressed_color", "PrimaryButton"),
			margin.theme.get_color("font_color", "PrimaryButton"),
			"hover-pressed primary labels stay dark on cyan"
		)
		var primary_font := margin.theme.get_font("font", "PrimaryButton")
		_check(primary_font is FontVariation, "PrimaryButton uses a weighted Nunito cut")
		if primary_font is FontVariation:
			_check_eq(
				int((primary_font as FontVariation).variation_opentype.get(2003265652, 0)),
				700,
				"PrimaryButton is wght 700 so cyan chips stay readable"
			)
		_check_eq(
			margin.theme.get_color("font_pressed_color", "VibeSelected"),
			margin.theme.get_color("font_color", "VibeSelected"),
			"selected Vibe labels stay dark on cyan"
		)
		var vibe_fill := margin.theme.get_stylebox("normal", "VibeSelected") as StyleBoxFlat
		_check(
			vibe_fill != null and vibe_fill.content_margin_left <= 8.0,
			"selected Vibe chips keep CTA padding off the five-up row"
		)

	var scan_button := scene.find_child("ScanButton", true, false) as Button
	if scan_button != null:
		_check_eq(scan_button.theme_type_variation, &"PrimaryButton", "Scan remains the signature CTA")
	var scan_nav := scene.find_child("ScanNavButton", true, false) as Button
	if scan_nav != null:
		_check_eq(scan_nav.theme_type_variation, &"NavTabButton", "every tab wears the same chrome")
		# The old bright Scan pill baked near-black ink into the scene, so the
		# moment the emphasis dropped the whole tab went invisible. This shell
		# tree is never added to the SceneTree, so what it asserts is precisely
		# the shipped default rather than anything _paint() fixed up.
		var scan_ink := scan_nav.find_child("Icon", true, false) as TextureRect
		var scan_text := scan_nav.find_child("Label", true, false) as Label
		if scan_ink != null and scan_text != null:
			_check_eq(scan_ink.modulate, BottomNav.ICON_IDLE, "Scan ships readable ink, not stage paint")
			_check_eq(
				scan_text.get_theme_color(&"font_color"),
				BottomNav.INK_IDLE,
				"its label ships the same readable ink"
			)

	var juice_probe := Button.new()
	juice_probe.custom_minimum_size = Vector2(120.0, 96.0)
	root.add_child(juice_probe)
	await process_frame
	UiJuice.install_button(juice_probe)
	_check(juice_probe.has_meta(&"_scanima_juice_installed"), "button motion installs idempotently")
	juice_probe.scale = Vector2(0.5, 0.5)
	UiJuice.reveal(juice_probe)
	await _await_juice_settled(juice_probe)
	_check(absf(juice_probe.scale.x - 1.0) < 0.05, "reveal animates scale to normal")
	var meter_probe := ProgressBar.new()
	meter_probe.custom_minimum_size = Vector2(240.0, 32.0)
	root.add_child(meter_probe)
	await process_frame
	meter_probe.value = 0.0
	UiJuice.tween_meter(meter_probe, 73.0)
	await _await_juice_settled(meter_probe, UiJuice.META_METER_TWEEN)
	_check_eq(meter_probe.value, 73.0, "meter tween reaches target value")
	meter_probe.free()
	juice_probe.free()

	for cue_path in [
		"res://assets/audio/ui/ui_tap.ogg",
		"res://assets/audio/ui/ui_care.ogg",
		"res://assets/audio/ui/ui_confirm.ogg",
		"res://assets/audio/ui/ui_back.ogg",
	]:
		_check(ResourceLoader.exists(cue_path), "%s is imported" % cue_path.get_file())
	var nav_probe := Button.new()
	nav_probe.name = "HomeNavButton"
	nav_probe.theme_type_variation = &"NavTabButton"
	var care_probe := Button.new()
	care_probe.theme_type_variation = &"CareFeedButton"
	var confirm_probe := Button.new()
	confirm_probe.theme_type_variation = &"PrimaryButton"
	var back_probe := Button.new()
	back_probe.name = "CancelButton"
	_check_eq(UiJuice.button_cue(nav_probe), &"tap", "nav uses the glass tap")
	_check_eq(UiJuice.button_cue(care_probe), &"care", "Care Dock uses the pluck")
	_check_eq(UiJuice.button_cue(confirm_probe), &"confirm", "PrimaryButton uses confirm")
	_check_eq(UiJuice.button_cue(back_probe), &"back", "Cancel uses the back click")
	root.add_child(nav_probe)
	await process_frame
	UiJuice.install_button(nav_probe)
	UiJuice.play_button(nav_probe)
	var click_player := root.get_node_or_null("UiClickPlayer") as AudioStreamPlayer
	_check(click_player != null, "first in-tree tap mounts a shared UI player")
	if click_player != null:
		_check(click_player.playing, "nav tap starts the shared player")
		# The mix is tuned by ear, so pin the ordering rather than the numbers:
		# chrome under gameplay, gameplay over the music bed.
		_check(
			UiJuice.VOLUME_DB < Sfx.VOLUME_DB,
			"UI clicks stay quieter than gameplay one-shots"
		)
		_check(
			click_player.volume_db <= UiJuice.VOLUME_DB,
			"a per-cue trim only ever pulls a click down"
		)
		var loudest_ui: float = UiJuice.CUE_TRIM_DB.values().max()
		var loudest_sfx: float = Sfx.CUE_TRIM_DB.values().max()
		_check(
			loudest_ui <= 0.0 and UiJuice.VOLUME_DB + loudest_ui < AudioServer.get_bus_volume_db(0),
			"no UI trim pushes a peak-normalised click into clipping"
		)
		_check(
			Sfx.VOLUME_DB + loudest_sfx
				> AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),
			"gameplay one-shots sit above the music bed"
		)
	nav_probe.free()
	care_probe.free()
	confirm_probe.free()
	back_probe.free()

	for sfx_path in [
		"res://assets/audio/sfx/sfx_strike.ogg",
		"res://assets/audio/sfx/sfx_surge.ogg",
		"res://assets/audio/sfx/sfx_guard.ogg",
		"res://assets/audio/sfx/sfx_item.ogg",
		"res://assets/audio/sfx/sfx_feed.ogg",
		"res://assets/audio/sfx/sfx_hit_super.ogg",
		"res://assets/audio/sfx/sfx_hit_resist.ogg",
		"res://assets/audio/sfx/sfx_portal.ogg",
		"res://assets/audio/sfx/sfx_level_up.ogg",
	]:
		_check(ResourceLoader.exists(sfx_path), "%s is imported" % sfx_path.get_file())
	var presenter_source := FileAccess.get_file_as_string("res://scripts/anima_presenter.gd")
	var incubator_source := FileAccess.get_file_as_string("res://scripts/incubator_effect.gd")
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		presenter_source.find("func play_fx") >= 0
		and presenter_source.find("Sfx.play(Sfx.CUE_SURGE") > presenter_source.find("func play_fx"),
		"Attack/Special SFX stays on play_fx, not on the Attack button"
	)
	_check(
		presenter_source.find("func guard_shimmer") >= 0
		and presenter_source.find("Sfx.play(Sfx.CUE_GUARD)") > presenter_source.find("func guard_shimmer"),
		"Guard SFX stays on guard_shimmer"
	)
	_check(
		presenter_source.find("func care_feedback") >= 0
		and presenter_source.find("Sfx.play(Sfx.CUE_FEED)") > presenter_source.find("func care_feedback")
		and presenter_source.find("Sfx.play(Sfx.CUE_ITEM)") > presenter_source.find("func care_feedback"),
		"Feed and item SFX stay on care_feedback"
	)
	_check(
		presenter_source.find("func hit_react") >= 0
		and presenter_source.find("Sfx.play_effectiveness") > presenter_source.find("func hit_react"),
		"effectiveness SFX stays on hit_react"
	)
	_check(
		incubator_source.find("func start_portal") >= 0
		and incubator_source.find("Sfx.play(Sfx.CUE_PORTAL)") > incubator_source.find("func start_portal"),
		"portal SFX stays on start_portal for Summon and Switch"
	)
	var level_presenter := flow_source.find("func _present_level_up_outcome")
	_check(
		level_presenter >= 0
		and flow_source.substr(level_presenter, 900).find("Sfx.play(Sfx.CUE_LEVEL_UP)") >= 0,
		"Level Up SFX plays when the queued shell outcome is actually presented"
	)
	var outcome_presenter := flow_source.find("func _present_next_outcome_dialog")
	_check(
		outcome_presenter >= 0
		and flow_source.substr(outcome_presenter, 2400).find("Sfx.play(Sfx.CUE_LEVEL_UP)") >= 0,
		"Synthesis complete uses the Level Up cue on the global success dialog"
	)
	Sfx.play(Sfx.CUE_STRIKE)
	var sfx_host := root.get_node_or_null("SfxHost")
	_check(sfx_host != null, "first gameplay cue mounts the shared SFX host")

	var care_dock := scene.find_child("CareDock", true, false) as PanelContainer
	_check(care_dock != null, "CareDock must exist")
	if care_dock != null:
		_check(not care_dock.visible, "care stays hidden before an Anima loads")
	_check(scene.find_child("CareSummary", true, false) is Label, "EXP summary has a label")
	_check(
		scene.find_child("LevelUpBanner", true, false) == null,
		"the standalone Level Up banner is gone; one dialog carries the copy"
	)
	var celebrate_at := flow_source.find("func _celebrate_level_up")
	_check(
		celebrate_at >= 0
		and flow_source.substr(celebrate_at, 900).find("_enqueue_outcome_dialog(") >= 0
		and flow_source.find("func _hide_level_up_later") < 0,
		"Level Up enters the global FIFO instead of a screen-local banner"
	)
	_check(
		flow_source.find(
			"tr(\"LEVEL_UP_TITLE\") % LocaleManager.display_name(anima)"
		) >= 0,
		"the Level Up dialog names the Anima in its own title"
	)
	var modal_theme := load("res://themes/mobile_theme.tres") as Theme
	var hero_size := modal_theme.get_font_size("font_size", "ModalHero") if modal_theme != null else 0
	var modal_title_size := modal_theme.get_font_size("font_size", "ModalTitle") if modal_theme != null else 0
	var modal_body_size := modal_theme.get_font_size("font_size", "BodyLabel") if modal_theme != null else 0
	_check(
		hero_size > modal_title_size and modal_title_size > modal_body_size,
		"Lv. N dominates the Level Up title, which still outranks the stat rows"
	)
	_check(
		modal_theme != null
		and modal_theme.get_font("font", "ModalHero") != null
		and modal_theme.get_font("font", "ModalHero").resource_path
		== "res://assets/fonts/Oxanium-Variable.ttf",
		"the hero Level uses the Oxanium display font"
	)
	_check(
		flow_source.find(
			"tr(\"LEVEL_UP_TO\") % LocaleManager.format_integer(level)"
		) >= 0,
		"the Level Up hero slot carries the new Level, not a wrapped form name"
	)
	# Seeker Onboarding lives on its own node, not ShellModal, so a Synthesis/
	# Evolution outcome resumed at boot can otherwise open right on top of an
	# unfinished onboarding form instead of waiting its turn.
	_check(
		outcome_presenter >= 0
		and flow_source.substr(outcome_presenter, 700).find(
			"_shell_modal.visible or _seeker_onboarding_sheet.visible"
		) >= 0,
		"queued outcome dialogs wait for Seeker Onboarding to close, not just ShellModal"
	)
	var complete_profile_start := flow_source.find("func _complete_seeker_profile")
	var complete_profile_end := flow_source.find("\n\nfunc ", complete_profile_start)
	var complete_profile_body := (
		flow_source.substr(complete_profile_start, complete_profile_end - complete_profile_start)
		if complete_profile_start >= 0 and complete_profile_end > complete_profile_start
		else ""
	)
	_check(
		complete_profile_body.find("_seeker_onboarding_sheet.close()") >= 0
		and complete_profile_body.find("call_deferred(\"_present_queued_dialogs_after_modal\")") >= 0,
		"finishing Seeker Onboarding re-checks the queued outcome dialog, not just the chapter popup"
	)
	var handle_back_start := flow_source.find("func _handle_back")
	var handle_back_end := flow_source.find("\n\nfunc ", handle_back_start)
	var handle_back_body := (
		flow_source.substr(handle_back_start, handle_back_end - handle_back_start)
		if handle_back_start >= 0 and handle_back_end > handle_back_start
		else ""
	)
	var onboarding_back_at := handle_back_body.find("_seeker_onboarding_sheet.close()")
	_check(
		onboarding_back_at >= 0
		and handle_back_body.substr(onboarding_back_at, 120).find(
			"call_deferred(\"_present_queued_dialogs_after_modal\")"
		) >= 0,
		"backing out of Seeker Onboarding also re-checks the queued outcome dialog"
	)
	var choice_selected_start := flow_source.find("func _modal_choice_selected")
	var choice_selected_end := flow_source.find("\n\nfunc ", choice_selected_start)
	var choice_selected_body := (
		flow_source.substr(choice_selected_start, choice_selected_end - choice_selected_start)
		if choice_selected_start >= 0 and choice_selected_end > choice_selected_start
		else ""
	)
	_check(
		choice_selected_body.find("if context != &\"sign_in_google\":\n\t\treturn") < 0
		and choice_selected_body.find("if context == &\"sign_in_google\":") >= 0,
		"an unrecognized choice-dialog context still flushes the outcome queue instead of stalling it"
	)
	for name in ["NeedHunger", "NeedEnergy", "NeedHygiene", "NeedExp"]:
		var meter := scene.find_child(name, true, false) as ProgressBar
		_check(meter != null, "%s must exist" % name)
		if meter != null:
			_check_eq(meter.max_value, 100.0, "%s uses the 0–100 range" % name)

	var script := scene.get_script() as GDScript
	var normalized: Dictionary = script.normalize_anima_data({
		"stats": {"hp": 61, "atk": 42, "def": 55, "spd": 48, "special": 70},
	})
	_check_eq(
		(normalized["base_stats"] as Dictionary).get("special"),
		70,
		"Vision stats still normalize for the profile"
	)
	_check_eq(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		720,
		"viewport tetap 720 supaya tombol 96 px tidak mengecil"
	)
	_check_eq(
		int(ProjectSettings.get_setting("display/window/size/viewport_height")),
		1602,
		"viewport tinggi mengikuti Xiaomi 14 20:9"
	)
	_check_eq(
		str(ProjectSettings.get_setting("display/window/stretch/aspect")),
		"expand",
		"stretch expand exposes real portrait and landscape viewport sizes"
	)
	for size in [Vector2(720, 1280), Vector2(720, 1602), Vector2(360, 640), Vector2(412, 915), Vector2(1080, 1920), Vector2(1600, 900), Vector2(2340, 1080)]:
		var pos: Vector2 = script.stage_position_for(size)
		_check(is_equal_approx(pos.x, size.x * 0.5), "Stage stays horizontally centered at %s" % size)
		_check(pos.y > 0.0 and pos.y < size.y, "Stage stays inside %s" % size)
		# Aspect yang menjauh dari aspect art membuat `cover` memotong tinggi, jadi
		# satu ratio viewport akan menggeser kaki keluar dari lantai yang digambar.
		# Yang harus tetap konstan adalah baris art-nya.
		var landscape: bool = size.x > size.y
		var art_size: Vector2 = (
			HomeBackground.HOME_BACKGROUND_NIGHT_LANDSCAPE
			if landscape
			else HomeBackground.HOME_BACKGROUND_NIGHT
		).get_size()
		var art: Rect2 = HomeBackground.floor_aligned_cover_rect(art_size, size)
		var art_row := (pos.y - art.position.y) / art.size.y
		_check(
			is_equal_approx(art_row, 0.69 if landscape else 0.68),
			"Home Stage lands on the authored dais row at %s" % size
		)

	# Home menggambar sel sheet pada ukuran pikselnya, jadi tanpa normalisasi yang
	# menentukan besar Anima adalah resolusi sheet. Angka di bawah diambil dari
	# ritual produksi 22 Agustus 2026: Rookie Hydron 180 cm datang 517 px, Adult
	# Drowake 225 cm datang 312 px, dan Home menggambar Drowake 40% lebih kecil
	# walau ia 25% lebih tinggi.
	for size in [Vector2(720, 1602), Vector2(412, 915), Vector2(2340, 1080)]:
		var rookie_scale: float = script.stage_scale_for(180.0, 517.0, size)
		var adult_scale: float = script.stage_scale_for(225.0, 312.0, size)
		var rookie_px := rookie_scale * 517.0
		var adult_px := adult_scale * 312.0
		_check(
			adult_px > rookie_px,
			"Home draws the taller evolved Anima taller at %s" % size
		)
		# Sheet yang resolusinya beda tidak boleh mengubah ukuran di layar sama
		# sekali; yang boleh mengubahnya hanya tinggi badan.
		_check(
			is_equal_approx(
				script.stage_scale_for(180.0, 517.0, size) * 517.0,
				script.stage_scale_for(180.0, 312.0, size) * 312.0
			),
			"Home size ignores sheet resolution at %s" % size
		)
		_check(
			script.stage_scale_for(240.0, 400.0, size) * 400.0
			> script.stage_scale_for(120.0, 400.0, size) * 400.0,
			"Home size still grows with body height at %s" % size
		)
		var art: Rect2 = script.home_art_rect(size)
		_check(
			rookie_px < art.size.y * 0.42 and rookie_px > art.size.y * 0.12,
			"Home body stays inside its span clamp at %s" % size
		)
		# Kalibrasi pertama memakai satu sheet 517 px yang ternyata terbesar di
		# roster, jadi delapan dari sembilan Anima membengkak sampai +81%. Anima
		# setinggi median roster (90 cm) harus kembali ke sekitar 310 px yang
		# sudah dilihat pemain, bukan melar ke ukuran sheet outlier itu.
		var median_px: float = script.stage_scale_for(90.0, 312.0, size) * 312.0
		_check(
			absf(median_px / art.size.y - 310.0 / 1602.0) < 0.02,
			"Home keeps a median-height Anima at the size players already saw at %s" % size
		)
		# Rentang tinggi nyata 55–225 cm harus tetap terbaca tanpa pembanding di
		# lobby; kurva arena 0,42 memampatkannya jadi 1,8x dan enam Anima 55–95 cm
		# tampak seukuran.
		var tiny_px: float = script.stage_scale_for(55.0, 219.0, size) * 219.0
		var tall_px: float = script.stage_scale_for(225.0, 312.0, size) * 312.0
		_check(
			tall_px / tiny_px > 2.2,
			"Home spreads the real height range at %s — got %.2fx" % [
				size, tall_px / tiny_px
			]
		)
	# Manifest lama tanpa render_metrics tidak boleh tiba-tiba diskalakan.
	_check_eq(
		script.stage_scale_for(180.0, 0.0, Vector2(720, 1602)),
		1.0,
		"Home leaves a metric-less manifest at native size"
	)

	var incubator := scene.find_child("Incubator", true, false) as Node2D
	_check(incubator != null, "Stage keeps its Incubator")
	if incubator != null:
		_check(not incubator.visible, "Incubator starts hidden")
		_check_eq(incubator.position, Vector2.ZERO, "Incubator shares the Stage ground anchor")
	var anima := scene.find_child("Anima", true, false) as AnimatedSprite2D
	_check(anima != null and not anima.visible, "cached art stays hidden until server care is known")
	var home_stage := scene.find_child("Stage", true, false) as Node2D
	var home_shadow := scene.call("_make_home_ground_shadow", home_stage) as Sprite2D
	_check(
		home_shadow != null
		and home_shadow.texture is GradientTexture2D
		and home_shadow.z_index == anima.z_index
		and home_shadow.get_index() < anima.get_index()
		and not home_shadow.visible,
		"Home draws its soft contact shadow above the background and before the Anima"
	)
	var first_effect := scene.find_child("FirstAnimaEffect", true, false) as Node2D
	_check(first_effect != null and not first_effect.visible, "first-Anima scanner starts hidden")
	_test_care_feedback_is_immediate()
	_test_collection_routes_are_explicit()
	_test_atlas_publish_offers_sign_in()
	_test_sign_in_choice_follows_guest_roster()
	_test_hatch_offers_rename()
	_test_header_uses_seeker_identity(scene)
	await _test_compact_shared_toast(scene)
	_test_present_toast_respects_sleep()
	_test_battle_reward_is_authoritative()
	_test_battle_art_has_no_global_toast()
	_test_battle_turn_prediction(scene)
	_test_home_tap_interaction(scene)
	_test_wake_tap_gesture(scene)

	await _check_music(scene)
	_check_home_background(scene)

	_test_synthesis_history_cache(scene)
	scene.free()
	await _test_anima_tap_reactions()
	await _test_item_grids_clip_to_one_line()
	await _test_card_grids_fill_width()
	await _test_autowrap_labels_have_wrap_width()
	await _test_shared_components()
	await _test_fly_to_animation()
	await _test_consumable_flight_to_anima()
	await _test_scan_phase_visuals()
	await _test_scan_rejection_dialog()
	await _test_seeker_ui()
	await _test_battle_view()
	await _test_team_battle_view()
	await _test_expedition_view()
	await _test_battle_pick_sheet()
	await _test_collection_bottom_sheet()
	await _test_collection_row_hygiene()
	await _test_atlas_view()
	await _test_profile_info_rows()
	await _test_anima_delete_action()
	await _test_evolve_profile_cta()
	await _test_evolution_history_section()
	await _test_synthesis_lab_state()
	await _test_synthesis_profile_ui()
	await _test_home_care_actions()
	await _test_bottom_nav_busy()
	await _test_incubator_effect()
	await _test_loading_screen()
	_finish()


## Autowrap `Label` minimum heights are computed against the control's WIDTH,
## and a known Godot regression (godotengine/godot#83546) measures them before
## the container sort has handed them one -- the label wraps at width ~0 and
## reports an absurd height, which is why a sheet opens too tall and then "fits
## after reopening". Measured on the Collection preview: a one-line meta label
## reported 312 px and pushed the panel minimum to 897 px; with a wrap-width
## floor it reports 67 px and the panel settles at 660 px.
##
## So: an autowrap label that shares a row with a fixed-width sibling must carry
## a wrap-width floor, and a label that never needs to wrap must not opt into
## autowrap at all. Both are cheap to get wrong again while adding a badge --
## which is exactly how this regressed.
## A grid cell in an `ItemList` has room for exactly the lines it was measured
## for. Left to its own devices the item text wrapped, got the first line
## ellipsised, and drew the SECOND line outside the cell, on top of the art of
## the row underneath -- seen on device as "Drakabyss · Lv. 6 · Flow · …"
## followed by a stray "lant". Cells that hold player-supplied names must pin
## themselves to one clipped line so no name length can leak.
func _test_item_grids_clip_to_one_line() -> void:
	var offenders: Array[String] = []
	for scene_path in [
		"res://scenes/ui/battle_pick_sheet.tscn",
		"res://scenes/ui/collection_view.tscn",
	]:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var probe := packed.instantiate()
		for node in probe.find_children("*", "ItemList", true, false):
			var list := node as ItemList
			# Single-column rosters get the full width and are not at risk.
			if list.max_columns < 2:
				continue
			if (
				list.max_text_lines != 1
				or list.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS
			):
				offenders.append("%s/%s" % [scene_path.get_file(), list.name])
		probe.queue_free()
	_check(
		offenders.is_empty(),
		"multi-column item grids clip to one ellipsised line, not on %s" % [offenders]
	)
	await process_frame


## A card grid with a pinned column count leaves the extra width of a wide
## screen unused on its right, so the roster reads as shoved against the left
## edge. Reported from a 633x1024 desktop window, which resolves to a ~990 px
## logical viewport on the 720x1602 base: Collection filled two 290 px columns
## of ~930 px and Atlas three 208 px ones.
##
## Deriving the columns from the real width is only half of it, because both
## controls punish the obvious arithmetic, each in its own way. This test walks
## one viewport narrow -> wide -> narrow, because the second narrow pass is the
## only place a latched column count shows up.
func _test_card_grids_fill_width() -> void:
	# GridContainer puts the gap between columns, so a width holding n cells
	# plus n-1 gaps must report exactly n -- one pixel short must report n-1.
	_check_eq(UiJuice.grid_columns_for(290.0, 290.0, 12.0), 1, "a lone cell needs no gap")
	_check_eq(UiJuice.grid_columns_for(591.0, 290.0, 12.0), 1, "a cell without its gap does not count")
	_check_eq(UiJuice.grid_columns_for(592.0, 290.0, 12.0), 2, "two cells and one gap fit exactly")
	_check_eq(UiJuice.grid_columns_for(0.0, 290.0, 12.0), 1, "an unsized grid still reports one column")

	# A list that has never been laid out must keep what the scene drew.
	# Collection and the Battle picker both sit hidden until opened, so width 0
	# is the state the fit runs in first, and answering it would collapse a
	# two-column grid to one.
	var unsized := ItemList.new()
	unsized.max_columns = 2
	unsized.fixed_column_width = 290
	UiJuice.fit_item_grid(unsized, 290.0)
	_check(
		unsized.max_columns == 2 and unsized.fixed_column_width == 290,
		"an unsized list keeps the scene's columns instead of collapsing to one"
	)
	unsized.free()

	var swatch := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	swatch.fill(Color.RED)
	var icon := ImageTexture.create_from_image(swatch)
	var atlas_rows: Array[Dictionary] = []
	var roster: Array[Dictionary] = []
	for index in 12:
		atlas_rows.append({
			"form_id": "grid-fill-%d" % index,
			"discovered": true,
			"display_name": "Card %d" % index,
			"element": "plant",
			"stage": 1,
		})
		roster.append({
			"id": "grid-fill-%d" % index,
			"nickname": "Card %d" % index,
			"element": "spark",
		})

	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1602)
	root.add_child(viewport)
	var collection := (
		load("res://scenes/ui/collection_view.tscn") as PackedScene
	).instantiate() as Control
	viewport.add_child(collection)
	collection.visible = true
	collection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	collection.set_rows(roster, "", func(_row: Dictionary) -> Texture2D: return icon)
	var atlas := (
		load("res://scenes/ui/atlas_view.tscn") as PackedScene
	).instantiate() as Control
	viewport.add_child(atlas)
	atlas.visible = true
	atlas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atlas.show_demo(atlas_rows, icon)
	var list := collection.find_child("AnimaList", true, false) as ItemList
	var grid := atlas.find_child("AtlasGrid", true, false) as GridContainer

	var collection_columns: Array[int] = []
	var atlas_columns: Array[int] = []
	for width: int in [720, 1440, 720]:
		viewport.size = Vector2i(width, 1602)
		# Columns feed a grid's height, height decides whether the scroll bar
		# shows, and the bar takes width back -- so let the fit settle, and
		# fail if it never does rather than sampling mid-trade.
		for _settle in 5:
			await process_frame

		# Not `max_columns`: that is only an upper bound. ItemList drops
		# `current_columns` on its own when a row overflows by even a pixel,
		# and it keeps the oversized cells while doing so -- which is what
		# pooled a whole card's worth of width at the right edge. Read the row
		# it actually drew, by counting the items sharing the first item's y.
		var drawn := 1
		while drawn < list.item_count and is_equal_approx(
			list.get_item_rect(drawn).position.y, list.get_item_rect(0).position.y
		):
			drawn += 1
		collection_columns.append(drawn)
		_check_eq(
			drawn, list.max_columns,
			"Collection draws every column it asked for at %d px" % width
		)
		# Whatever is left at the right must be too small for one more card,
		# measured off the drawn row rather than off the fit's own arithmetic.
		var right_gap := list.size.x - list.get_item_rect(drawn - 1).end.x
		_check(
			right_gap < float(list.fixed_column_width),
			"Collection leaves under one card unused at %d px (%.1f of %d)" % [
				width, right_gap, list.fixed_column_width
			]
		)

		atlas_columns.append(grid.columns)
		var last_in_row := grid.get_child(grid.columns - 1) as Control
		_check(
			last_in_row != null
			and last_in_row.position.x + last_in_row.size.x >= grid.size.x - 1.0,
			"Atlas cards stretch to the grid's right edge at %d px" % width
		)
		# `AtlasScroll` disables horizontal scrolling, so the grid's minimum
		# width climbs to `columns x CARD_MIN.x` and propagates up. Measured on
		# `Column`, not on the view root: the root is a plain Control, which
		# never aggregates a child's minimum, while a Container clamps itself up
		# to it and spills past the screen -- filters and tabs clipped on both
		# edges, exactly as reported.
		var column := atlas.get_node("Column") as Control
		_check(
			column.size.x <= float(width),
			"Atlas fits the viewport at %d px (content is %.0f wide)" % [width, column.size.x]
		)
	_check(
		collection_columns[1] > collection_columns[0]
		and collection_columns[2] == collection_columns[0],
		"Collection follows the width both ways, got %s" % [collection_columns]
	)
	_check(
		atlas_columns[1] > atlas_columns[0] and atlas_columns[2] == atlas_columns[0],
		"Atlas follows the width both ways, got %s" % [atlas_columns]
	)

	# Fewer cards than the screen has room for. An empty column still takes its
	# share of the width, so columns capped only by the width leave a roster of
	# four huddled at the left with the rest of the screen idle -- the same
	# complaint, arriving from the other direction. Capping the columns at the
	# card count hands that width to the cells that exist instead.
	viewport.size = Vector2i(1440, 1602)
	collection.set_rows(
		roster.slice(0, 4), "", func(_row: Dictionary) -> Texture2D: return icon
	)
	atlas.show_demo(atlas_rows.slice(0, 4), icon)
	for _settle in 5:
		await process_frame
	_check_eq(list.max_columns, 4, "Collection spreads a short roster over one row")
	_check(
		list.size.x - list.get_item_rect(3).end.x < float(list.fixed_column_width),
		"a short Collection roster still reaches the right edge"
	)
	_check_eq(grid.columns, 4, "Atlas spreads a short library over one row")
	var last_card := grid.get_child(3) as Control
	_check(
		last_card.position.x + last_card.size.x >= grid.size.x - 1.0,
		"a short Atlas library still reaches the right edge"
	)
	viewport.queue_free()
	await process_frame


func _test_autowrap_labels_have_wrap_width() -> void:
	var offenders: Array[String] = []
	for scene_path in [
		"res://scenes/ui/collection_view.tscn",
		"res://scenes/ui/battle_pick_sheet.tscn",
		"res://scenes/ui/anima_details_view.tscn",
		"res://scenes/ui/seeker_profile_view.tscn",
	]:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var probe := packed.instantiate()
		# Scoped to bottom-sheet panels on purpose: those are sized FROM their
		# content, so one bad minimum becomes a visibly wrong sheet height. A
		# full-screen view has a ScrollContainer that absorbs the same mistake.
		for panel in probe.find_children("*", "PanelContainer", true, false):
			if (panel as PanelContainer).theme_type_variation != &"BottomSheetPanel":
				continue
			for label in panel.find_children("*", "Label", true, false):
				var text_label := label as Label
				if text_label.autowrap_mode == TextServer.AUTOWRAP_OFF:
					continue
				if text_label.custom_minimum_size.x <= 0.0:
					offenders.append("%s/%s" % [scene_path.get_file(), text_label.name])
		probe.queue_free()
	_check(
		offenders.is_empty(),
		"autowrap labels inside a content-sized sheet carry a wrap-width floor, missing on %s"
			% [offenders]
	)
	await process_frame


func _test_shared_components() -> void:
	var modal = (load("res://scenes/ui/ui_modal.tscn") as PackedScene).instantiate()
	root.add_child(modal)
	await process_frame
	var modal_input := modal.find_child("ModalInput", true, false) as LineEdit
	var modal_cancel := modal.find_child("CancelButton", true, false) as Button
	var modal_primary := modal.find_child("PrimaryButton", true, false) as Button
	var modal_choice_cancel := modal.find_child("ChoiceCancelButton", true, false) as Button
	var modal_dismiss := modal.find_child("DismissButton", true, false) as Button
	var modal_portrait := modal.find_child("ModalPortrait", true, false) as TextureRect
	modal.open_info("Info", "Short body", "Got It")
	_check(
		modal.visible and not modal_input.visible and not modal_cancel.visible
		and modal_portrait != null and not modal_portrait.visible,
		"UiModal info mode is compact and leaves no empty portrait slot"
	)
	var reveal_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	reveal_image.fill(Color.CYAN)
	var reveal_texture := ImageTexture.create_from_image(reveal_image)
	modal.open_result("Complete", "New Result", "View", "Synthera", reveal_texture, false)
	# Satu frame saja -- headless scripting tidak menjamin delta per tick pendek,
	# jadi menunggu frame kedua untuk menangkap tween "di tengah jalan" rapuh:
	# delta yang besar bisa membuatnya sudah selesai. Frame pertama sudah cukup
	# membuktikan entrance-nya dimulai (nilai reveal awal, belum di-tween ke identity).
	await process_frame
	_check(
		modal_portrait.visible and modal_portrait.texture == reveal_texture
		and modal_portrait.scale.x < 0.9 and modal_portrait.modulate.a < 1.0,
		"UiModal Result mode reveals the generated portrait with entrance motion"
	)
	modal.request_cancel()
	await create_timer(0.25).timeout
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	modal.call("_unhandled_input", cancel_event)
	await process_frame
	_check(
		modal.visible and modal_dismiss != null and modal_dismiss.disabled,
		"locked Result dialog ignores backdrop, Android Back, and request_cancel"
	)
	modal_primary.pressed.emit()
	await create_timer(0.25).timeout
	_check(not modal.visible, "locked Result dialog still closes from its explicit action")
	modal.open_result_choice(
		"Evolution Complete", "New form", "Summon", "Rename", "Drowake", reveal_texture, false
	)
	await process_frame
	_check(
		modal_primary.visible and modal_primary.text == "Summon"
		and modal_cancel.visible and modal_cancel.text == "Rename"
		and not modal_choice_cancel.visible and modal_dismiss.disabled,
		"result choice exposes exactly Summon and Rename while backdrop stays locked"
	)
	modal.request_cancel()
	await create_timer(0.25).timeout
	_check(modal.visible, "locked result choice ignores Android Back and backdrop")
	modal_cancel.pressed.emit()
	await create_timer(0.25).timeout
	_check(not modal.visible, "result choice closes from its explicit secondary action")
	modal.open_info("Failed", "Failure details", "Close", "", false)
	await process_frame
	modal.request_cancel()
	await create_timer(0.25).timeout
	_check(
		modal.visible and modal_dismiss.disabled,
		"locked failure dialog cannot be skipped by tapping outside"
	)
	modal_primary.pressed.emit()
	await create_timer(0.25).timeout
	_check(not modal.visible, "locked failure dialog closes from its acknowledgement button")
	modal.open_confirm("Retry", "Failure body", "Retry", "Close", false, false)
	modal.request_cancel()
	await create_timer(0.25).timeout
	_check(modal.visible, "locked confirm blocks backdrop and Android Back")
	modal_cancel.pressed.emit()
	await create_timer(0.25).timeout
	_check(not modal.visible, "locked confirm still honors its explicit Close button")
	modal.open_confirm("Delete", "Danger body", "Delete", "Cancel", true)
	_check(not modal_portrait.visible, "non-Result dialogs reset the optional portrait slot")
	_check(
		modal_cancel.visible and modal_primary.theme_type_variation == &"DangerButton",
		"UiModal danger-confirm mode exposes safe cancel and danger action"
	)
	modal.open_choice("Google", "Choose", "Keep Guest", "Move Guest", "Cancel")
	await process_frame
	_check(
		modal_primary.visible
		and modal_primary.text == "Keep Guest"
		and modal_cancel.visible
		and modal_cancel.text == "Move Guest"
		and modal_choice_cancel.visible
		and modal_choice_cancel.text == "Cancel"
		and modal_primary.has_focus(),
		"UiModal choice mode exposes two actions plus Cancel and focuses the safe default"
	)
	modal.open_input("Rename", "Prompt", "Velumi", "Save", "Cancel", "Name")
	_check(
		modal_input.visible and modal_input.text == "Velumi" and modal_cancel.visible,
		"UiModal input mode exposes the current value and Cancel"
	)
	var modal_body_scroll := modal.find_child("ModalBodyScroll", true, false) as ScrollContainer
	modal.open_info("Long", "Readable detail\n".repeat(30), "Close")
	await process_frame
	await process_frame
	_check(
		modal_body_scroll != null
		and modal_body_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and modal_body_scroll.custom_minimum_size.y <= modal.get_viewport_rect().size.y * 0.42 + 1.0,
		"long modal copy scrolls inside a viewport-capped body while actions stay fixed"
	)
	var revision_before_resize: int = modal.get("_fit_revision")
	modal.get_viewport().size_changed.emit()
	await process_frame
	_check(
		int(modal.get("_fit_revision")) > revision_before_resize,
		"a viewport resize while the modal is open re-fits through the guarded async path, not a synchronous race"
	)
	modal.close()
	await create_timer(0.25).timeout
	_check(not modal.visible, "UiModal closes after its dismiss animation")

	var chip = (load("res://scenes/ui/resource_chip.tscn") as PackedScene).instantiate()
	root.add_child(chip)
	await process_frame
	chip.set_value_text("7")
	chip.set_name_text("Animas")
	chip.set_interactive(true, "Open Collection")
	var chip_action := chip.find_child("ActionButton", true, false) as Button
	var chip_name := chip.find_child("Name", true, false) as Label
	var chip_icon := chip.find_child("Icon", true, false) as TextureRect
	_check(
		chip_action.visible and chip.custom_minimum_size.y >= TOUCH_MIN,
		"ResourceChip can expose a touch-safe action overlay"
	)
	_check(chip_name != null and chip_name.visible, "ResourceChip shows a name when set")
	chip.set_name_text("")
	_check(chip_name != null and not chip_name.visible, "empty ResourceChip name is hidden so Shop can center")
	_check(chip_icon != null and not chip_icon.visible, "ResourceChip icon stays hidden until set")
	chip.set_icon(load("res://assets/icons/scanima/shop.svg") as Texture2D)
	var chip_column := chip.get_node_or_null("Column") as BoxContainer
	_check(chip_icon != null and chip_icon.visible and chip_icon.texture != null, "ResourceChip can show a Shop icon")
	_check(
		chip.get_global_rect().encloses(chip.icon_global_rect())
		and chip.icon_global_rect().size != chip.get_global_rect().size,
		"icon_global_rect() targets the icon's own smaller box, not the whole chip -- Shop/Bag reserve room below it for a label"
	)
	_check(
		chip_column != null and chip_column.get_theme_constant("separation") >= 8,
		"Shop icon keeps a gap above the label"
	)
	# The HUD counters read as one phrase — "30 Bits" — so the same chip has to
	# lay out horizontally on request. This is asserted on a live chip because
	# `Column` resolves at `_ready()`, and the shell inspected above never
	# enters the tree.
	chip.set_inline(true)
	_check(
		chip_column != null and not chip_column.vertical,
		"ResourceChip can put the value beside its label for the HUD counters"
	)
	chip.set_inline(false)
	_check(
		chip_column != null and chip_column.vertical,
		"ResourceChip goes back to icon-over-label for Shop and Bag"
	)
	# ActionButton is a full-rect overlay on a panel that already has a border.
	# Inheriting `ButtonFocus` draws a 4px gold stadium around the text after
	# "Got It" returns focus — the chip looks selected when nothing is. Empty
	# styles on `ChipActionButton` kill the ring; `flat` alone is not enough,
	# Godot still paints focus on flat buttons.
	var chip_theme := load("res://themes/mobile_theme.tres") as Theme
	_check(
		chip_theme.get_stylebox(&"focus", &"ChipActionButton") is StyleBoxEmpty,
		"chip action overlay does not inherit the gold ButtonFocus ring"
	)
	chip_action.grab_focus()
	_check(
		chip_action.get_theme_stylebox("focus") is StyleBoxEmpty,
		"a focused resource chip still has no leftover outline"
	)
	_check(
		chip_theme.get_font_size("font_size", "ResourceValueLabel") >= 30
		and chip_theme.get_font_size("font_size", "ResourceNameLabel") >= 22,
		"HUD counter type fills the badge instead of floating in the middle"
	)

	var sheet = (load("res://scenes/ui/ui_bottom_sheet.tscn") as PackedScene).instantiate()
	root.add_child(sheet)
	await process_frame
	sheet.open()
	_check(sheet.visible, "UiBottomSheet opens through shared chrome")
	# `BottomSheetPanel` carries 2 px side borders, and a full-bleed panel draws
	# them in the outermost pixel column where a curved phone screen eats them --
	# read on device as the sheet being cut off rather than bordered. Checked
	# AFTER the entrance animation settles on purpose: assigning `position`
	# rewrites a Control's offsets, so a rest position of x=0 silently undid the
	# inset once the tween landed, leaving the first frame correct and every
	# frame after it wrong.
	await create_timer(0.50).timeout
	var sheet_panel := sheet.panel() as Control
	_check(
		sheet_panel != null
		and is_equal_approx(sheet_panel.offset_left, UiJuice.SHEET_SIDE_INSET)
		and is_equal_approx(sheet_panel.offset_right, -UiJuice.SHEET_SIDE_INSET),
		"the sheet keeps its side inset so its border is not lost off-screen"
	)
	_check(
		sheet_panel != null and is_equal_approx(sheet_panel.position.x, UiJuice.SHEET_SIDE_INSET),
		"and the entrance animation settles at the inset instead of resetting it to 0"
	)
	sheet.close()
	await create_timer(0.30).timeout
	_check(not sheet.visible, "UiBottomSheet closes after its dismiss animation")

	var fresh = (load("res://scenes/ui/ui_bottom_sheet.tscn") as PackedScene).instantiate()
	root.add_child(fresh)
	await fresh.open()
	await _await_juice_settled(fresh)
	var fresh_panel := fresh.panel() as Control
	var fresh_column := fresh_panel.find_child("Column", true, false) as VBoxContainer
	var fresh_content := fresh_panel.find_child("ContentSlot", true, false) as VBoxContainer
	var fresh_backdrop := fresh.find_child("Backdrop", true, false) as ColorRect
	_check(
		fresh.visible
		and fresh_panel != null
		and is_equal_approx(fresh_panel.offset_bottom, 0.0)
		and fresh_panel.offset_top < 0.0,
		"first bottom-sheet open sits on the bottom edge even before layout"
	)
	_check(
		fresh_panel.theme_type_variation == &"BottomSheetPanel"
		and fresh_column.get_theme_constant("separation") == 8
		and fresh_content.get_theme_constant("separation") == 16,
		"bottom sheets share compact handle spacing and an 8dp content rhythm"
	)
	_check(
		fresh_backdrop != null and is_equal_approx(fresh_backdrop.color.a, 0.68),
		"bottom-sheet scrim keeps the underlying destination legible"
	)
	var sheet_script := load("res://scripts/ui_bottom_sheet.gd") as GDScript
	_check_eq(
		sheet_script.scaled_safe_bottom(
			Vector2(720, 1280),
			Vector2(1440, 3200),
			Rect2(0, 100, 1440, 3000)
		),
		40.0,
		"bottom-sheet safe padding converts physical pixels into viewport coordinates"
	)
	fresh.close()
	fresh.queue_free()

	var shop_sheet = (load("res://scenes/ui/shop_sheet.tscn") as PackedScene).instantiate()
	root.add_child(shop_sheet)
	await process_frame
	var catalog := [
		{
			"id": "byte_berry",
			"kind": "food",
			"use_type": "food",
			"name_key": "CATALOG_BYTE_BERRY",
			"price": 1,
			"effect": "hunger",
			"effect_value": 10,
			"sprite_sheet": "food",
			"sprite_index": 0,
		},
		{
			"id": "pulse_cell",
			"kind": "item",
			"use_type": "energy",
			"name_key": "CATALOG_PULSE_CELL",
			"price": 8,
			"effect": "energy",
			"effect_value": 20,
			"sprite_sheet": "item",
			"sprite_index": 0,
		},
		{
			"id": "vital_patch",
			"kind": "item",
			"use_type": "battle",
			"name_key": "CATALOG_VITAL_PATCH",
			"price": 12,
			"effect": "heal_hp_pct",
			"effect_value": 35,
			"sprite_sheet": "item",
			"sprite_index": 1,
		},
	]
	var inventory := [
		{"item_id": "byte_berry", "quantity": 2},
		{"item_id": "pulse_cell", "quantity": 1},
		{"item_id": "vital_patch", "quantity": 1},
	]
	var animated_bag = (load("res://scenes/ui/shop_sheet.tscn") as PackedScene).instantiate()
	root.add_child(animated_bag)
	await process_frame
	animated_bag.set_meta("test_opened", false)
	animated_bag.opened.connect(func() -> void: animated_bag.set_meta("test_opened", true))
	animated_bag.set_catalog(catalog, inventory, 0)
	animated_bag.open_bag("item")
	_check(
		not bool(animated_bag.get_meta("test_opened")),
		"dynamic Bag waits for container layout before its first-open tween"
	)
	var animated_panel := animated_bag.panel() as Control
	var stayed_attached := true
	var animation_deadline := Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < animation_deadline:
		await process_frame
		if animated_panel.get_global_rect().end.y < animated_bag.get_global_rect().end.y - 1.0:
			stayed_attached = false
	_check(
		bool(animated_bag.get_meta("test_opened"))
		and stayed_attached
		and absf(animated_panel.get_global_rect().end.y - animated_bag.get_global_rect().end.y) < 1.0,
		"Bag first-open animation stays attached and settles flush with the bottom edge"
	)
	animated_bag.close()
	await create_timer(0.3).timeout
	animated_bag.queue_free()

	shop_sheet.set_catalog(catalog, inventory, 0)
	shop_sheet.open_shop("item")
	await process_frame
	var shop_panel := shop_sheet.panel() as Control
	var shop_scroll := shop_sheet.find_child("ShopScroll", true, false) as ScrollContainer
	var shop_list := shop_sheet.find_child("ShopList", true, false) as VBoxContainer
	var food_tab := shop_sheet.find_child("ShopFoodTab", true, false) as Button
	var item_tab := shop_sheet.find_child("ShopItemTab", true, false) as Button
	_check(
		shop_panel.theme_type_variation == &"BottomSheetPanel"
		and is_equal_approx(shop_scroll.custom_minimum_size.y, 560.0)
		and shop_panel.size.y <= shop_sheet.size.y * shop_sheet.max_height_ratio + 1.0
		and shop_list.get_theme_constant("separation") == 16,
		"Shop gives the catalog a tall viewport without exceeding the sheet height cap"
	)
	_check(
		food_tab.theme_type_variation == &""
		and item_tab.theme_type_variation == &"PrimaryButton",
		"Shop tab emphasis follows the selected category"
	)
	var zero_balance_buttons := 0
	var all_zero_balance_disabled := true
	for node in shop_list.find_children("*", "Button", true, false):
		var buy := node as Button
		if buy == null or buy.is_queued_for_deletion():
			continue
		zero_balance_buttons += 1
		all_zero_balance_disabled = all_zero_balance_disabled and buy.disabled
	_check(
		zero_balance_buttons == 2 and all_zero_balance_disabled,
		"Shop disables every purchase when the player has 0 Bits"
	)
	shop_sheet.set_catalog(catalog, inventory, 10)
	await process_frame
	var affordable_buy: Button = null
	var expensive_buy: Button = null
	for node in shop_list.find_children("*", "Button", true, false):
		var buy := node as Button
		if buy == null or buy.is_queued_for_deletion():
			continue
		if buy.text == tr("SHOP_BUY") % "8":
			affordable_buy = buy
		elif buy.text == tr("SHOP_BUY") % "12":
			expensive_buy = buy
	_check(
		affordable_buy != null and not affordable_buy.disabled
		and expensive_buy != null and expensive_buy.disabled,
		"Shop enables only prices covered by the authoritative Bits balance"
	)
	_check(
		_sheet_button_labels(shop_sheet).find(tr("SHOP_USE")) < 0,
		"Shop sells items without a Use action"
	)

	# Loading state + anti-spam for a purchase: the row being bought reads
	# "Buying...", every other Buy button and both tabs lock with it, and the
	# icon snapshot the fly-to-Bag animation needs is still readable before any
	# of that happens.
	var pulse_snapshot: Dictionary = shop_sheet.icon_snapshot_for("pulse_cell")
	_check(
		pulse_snapshot.get("texture") is Texture2D
		and (pulse_snapshot.get("rect", Rect2()) as Rect2).size.x > 0.0,
		"icon_snapshot_for hands back a real rect and texture while the row is still on screen"
	)
	_check(
		shop_sheet.icon_snapshot_for("does-not-exist").is_empty(),
		"icon_snapshot_for returns nothing for an item that isn't on screen"
	)
	shop_sheet.set_pending("pulse_cell")
	await process_frame
	var buy_buttons: Array[Button] = []
	for node in shop_list.find_children("*", "Button", true, false):
		var buy := node as Button
		if buy != null and not buy.is_queued_for_deletion():
			buy_buttons.append(buy)
	var buying_count := 0
	var all_disabled := true
	for buy in buy_buttons:
		if buy.text == tr("SHOP_BUYING"):
			buying_count += 1
		all_disabled = all_disabled and buy.disabled
	_check(
		buying_count == 1 and all_disabled and buy_buttons.size() == 2,
		"exactly the item being bought reads Buying..., and every Buy button locks with it"
	)
	_check(food_tab.disabled and item_tab.disabled, "tabs stay locked while a purchase is in flight")
	shop_sheet.set_pending("")
	await process_frame
	_check(
		not food_tab.disabled and not item_tab.disabled,
		"tabs unlock again once the purchase settles"
	)

	shop_sheet.open_bag("food")
	await process_frame
	_check(
		food_tab.theme_type_variation == &"PrimaryButton"
		and item_tab.theme_type_variation == &"",
		"Bag tab emphasis updates without leaving the old tab highlighted"
	)
	_check(
		_sheet_button_labels(shop_sheet).find(tr("CARE_FEED")) >= 0,
		"Bag food rows expose Feed"
	)
	_check(
		is_equal_approx(shop_scroll.custom_minimum_size.y, 560.0),
		"Bag shares the taller catalog viewport"
	)
	shop_sheet.open_bag("item")
	await process_frame
	var bag_item_labels := _sheet_button_labels(shop_sheet)
	_check(bag_item_labels.find(tr("SHOP_USE")) >= 0, "Bag energy rows expose Use")
	_check(
		_live_row_count(shop_sheet.find_child("ShopList", true, false)) == 2,
		"Bag items tab lists owned energy and battle items"
	)
	var battle_row: Control = null
	for child in shop_sheet.find_child("ShopList", true, false).get_children():
		var row := child as Control
		if row == null or row.is_queued_for_deletion():
			continue
		if _control_labels(row).find(tr("CATALOG_VITAL_PATCH")) >= 0:
			battle_row = row
			break
	_check(
		battle_row != null and _sheet_button_labels(battle_row).find(tr("SHOP_USE")) < 0,
		"Bag battle items have no Use button"
	)
	shop_sheet.set_catalog([], [], 0)
	shop_sheet.open_bag("food")
	await process_frame
	_check(
		not shop_scroll.visible and shop_panel.size.y < 560.0,
		"empty Bag stays compact instead of reserving a blank catalog viewport"
	)
	shop_sheet.open_battle()
	await process_frame
	var battle_empty := shop_sheet.find_child("ShopEmpty", true, false) as Label
	var battle_cta := shop_sheet.find_child("ShopEmptyCta", true, false) as Button
	_check(
		battle_empty != null
		and battle_empty.visible
		and battle_empty.text == tr("SHOP_BATTLE_EMPTY")
		and battle_cta != null
		and not battle_cta.visible,
		"empty Battle item sheet never offers Shop"
	)

	var compact_host := Control.new()
	compact_host.size = Vector2(720, 720)
	root.add_child(compact_host)
	var compact_sheet = (load("res://scenes/ui/shop_sheet.tscn") as PackedScene).instantiate()
	compact_host.add_child(compact_sheet)
	await process_frame
	compact_sheet.set_catalog(catalog, inventory, 10)
	compact_sheet.open_shop("item")
	await process_frame
	await process_frame
	var compact_panel := compact_sheet.panel() as Control
	var compact_scroll := compact_sheet.find_child("ShopScroll", true, false) as ScrollContainer
	_check(
		compact_panel.size.y <= compact_host.size.y * compact_sheet.max_height_ratio + 1.0
		and compact_scroll.custom_minimum_size.y < 560.0,
		"Shop shrinks its catalog viewport instead of clipping on a short display"
	)
	compact_host.queue_free()

	var skeleton = (load("res://scenes/ui/ui_skeleton.tscn") as PackedScene).instantiate()
	root.add_child(skeleton)
	skeleton.set_loading(true)
	_check(
		skeleton.visible and skeleton.get("_pulse") != null,
		"UiSkeleton pulses while authoritative data is still loading"
	)
	skeleton.set_loading(false)
	_check(not skeleton.visible, "UiSkeleton clears when authoritative data arrives")

	modal.queue_free()
	chip.queue_free()
	sheet.queue_free()
	shop_sheet.queue_free()
	skeleton.queue_free()
	await process_frame


func _test_care_feedback_is_immediate() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _commit_care")
	var end := source.find("\n\nfunc _resume_pending_care", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	var feedback := body.find("_anima.care_feedback(")
	var request := body.find("await _send_pending_care")
	_check(feedback >= 0 and request > feedback, "care reacts before its network response")
	_check(
		body.find("set_busy(true)") < 0,
		"the Care Dock stays lit while its care action is in flight"
	)
	_check(
		body.find("GameState.pending_care.is_empty()") >= 0
		and body.find("GameState.begin_care") > body.find("GameState.pending_care.is_empty()"),
		"a second care action is refused where every caller passes, including Bag"
	)
	# Bag opens straight from BagButton without passing through Care Dock's
	# own need_is_full check (home_view.gd _request_feed) -- the guard has to
	# live here too, or a full need still fires the flight animation and hits
	# the server for nothing, even though the server itself rejects the write.
	var hunger_guard := body.find("CareRules.need_is_full(_current_anima.get(\"care\"), \"hunger\")")
	var energy_guard := body.find("CareRules.need_is_full(_current_anima.get(\"care\"), \"energy\")")
	_check(
		hunger_guard >= 0 and energy_guard >= 0
		and hunger_guard < body.find("GameState.begin_care")
		and energy_guard < body.find("GameState.begin_care"),
		"feeding or using an item when its need is already full is refused before anything flies or hits the server"
	)
	var send_start := source.find("func _send_pending_care")
	var send_end := source.find("func _sync_active_care", send_start)
	var send_body := (
		source.substr(send_start, send_end - send_start)
		if send_start >= 0 and send_end > send_start
		else ""
	)
	var apply_at := send_body.find("_apply_care_response")
	_check(
		apply_at >= 0 and send_body.find("await _refresh_catalog") < 0,
		"care meters update without waiting on a catalog refetch"
	)
	var buy_start := source.find("func _send_pending_purchase")
	var buy_end := source.find("func _refresh_catalog", buy_start)
	var buy_body := (
		source.substr(buy_start, buy_end - buy_start)
		if buy_start >= 0 and buy_end > buy_start
		else ""
	)
	_check(
		buy_body.find("Catalog.with_quantity") >= 0
		and buy_body.find("await _refresh_catalog") < 0,
		"a purchase applies the shop quantity without a second round trip"
	)
	_check(
		buy_body.find("set_busy(true)") < 0,
		"the Shop stays interactive while a purchase is in flight"
	)
	var tap_start := source.find("func _buy_catalog_item")
	var tap_end := source.find("func _resume_pending_purchase", tap_start)
	var tap_body := (
		source.substr(tap_start, tap_end - tap_start)
		if tap_start >= 0 and tap_end > tap_start
		else ""
	)
	var optimistic_at := tap_body.find("_apply_optimistic_purchase(item_id, price)")
	_check(
		optimistic_at >= 0 and tap_body.find("await _send_pending_purchase") > optimistic_at,
		"Bits and bag quantity move before the purchase response"
	)
	_check(
		tap_body.find("_say_success(tr(\"FEEDBACK_PURCHASE\"), true)") < 0,
		"the optimistic purchase path shows the fly-to-Bag animation instead of a toast"
	)
	_check(
		tap_body.find("GameState.profile[\"bits\"] = bits_before") >= 0,
		"a rejected purchase puts the Bits it predicted back"
	)
	var resume_purchase_start := source.find("func _resume_pending_purchase")
	var resume_purchase_end := source.find("func _send_pending_purchase", resume_purchase_start)
	var resume_purchase_body := (
		source.substr(resume_purchase_start, resume_purchase_end - resume_purchase_start)
		if resume_purchase_start >= 0 and resume_purchase_end > resume_purchase_start
		else ""
	)
	_check(
		resume_purchase_body.find("_say_success(tr(\"FEEDBACK_PURCHASE\"), true)") >= 0,
		"a purchase resumed after a restart still toasts -- there's no sheet or icon left to animate"
	)
	_test_optimistic_care()
	_test_summon_overlaps_portal()
	_test_sleeping_consume_guard()


## Feed dan Use Item tidak boleh diam-diam mengonsumsi item saat Anima tidur --
## Bag memanggil `_commit_care` langsung tanpa lewat Care Dock, jadi gerbangnya
## harus duduk di sana, dan `_use_catalog_item` harus memeriksanya sebelum
## menutup sheet supaya toast-nya tidak muncul sesudah sheet-nya sudah hilang.
func _test_sleeping_consume_guard() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var commit_start := source.find("func _commit_care")
	var commit_end := source.find("\n\nfunc _resume_pending_care", commit_start)
	var commit_body := (
		source.substr(commit_start, commit_end - commit_start)
		if commit_start >= 0 and commit_end > commit_start
		else ""
	)
	var guard_at := commit_body.find(
		"(action == \"feed\" or action == \"use_item\") and _is_sleeping(_current_anima)"
	)
	_check(guard_at >= 0, "_commit_care refuses feed/use_item on a sleeping Anima, and only those two")
	_check(
		guard_at >= 0 and commit_body.find("tr(\"ERROR_SLEEPING_CONSUME\")", guard_at) > guard_at,
		"the sleeping guard tells the player to wake the Anima first"
	)
	_check(
		guard_at >= 0 and commit_body.find("GameState.begin_care", guard_at) > guard_at,
		"the sleeping guard runs before any care request is queued"
	)

	var use_start := source.find("func _use_catalog_item")
	var use_end := source.find("\n\nfunc _resume_pending_purchase", use_start)
	var use_body := (
		source.substr(use_start, use_end - use_start)
		if use_start >= 0 and use_end > use_start
		else ""
	)
	var use_guard_at := use_body.find("_is_sleeping(_current_anima)")
	var use_close_at := use_body.find("_shop_sheet.close()")
	_check(
		use_guard_at >= 0 and use_close_at > use_guard_at,
		"Bag checks the sleeping guard before closing the sheet, so the toast has somewhere to land"
	)

	# _fly_purchased_item must restore _bag_button.z_index to the constant 0,
	# not to a `previous_z` captured at call time -- a second purchase's
	# animation can start before the first one lands (the network round trip
	# can resolve faster than the 0,4 s flight), and capturing z_index then
	# would capture the first animation's 61, permanently stranding the Bag
	# icon above the rest of the chrome once both callbacks have fired.
	var fly_start := source.find("func _fly_purchased_item")
	var fly_end := source.find("\n\nfunc ", fly_start)
	var fly_body := (
		source.substr(fly_start, fly_end - fly_start)
		if fly_start >= 0 and fly_end > fly_start
		else ""
	)
	_check(
		fly_body.find("var previous_z") < 0,
		"the z_index restore doesn't capture a value that a second purchase could race"
	)
	_check(
		fly_body.find("_bag_button.z_index = 0") >= 0,
		"the z_index restore always lands on the known-good constant"
	)
	_check(
		fly_body.find("_bag_button.icon_global_rect()") >= 0
		and fly_body.find("_bag_button.get_global_rect()") < 0,
		"landing targets the chip's icon, not its full rect -- the chip reaches" +
		" well past the icon to make room for the label under it"
	)


## Mengganti companion memutar dissolve dan portal lebih dulu, jadi round trip
## `summon` habis di balik animasi yang memang harus jalan. Sprite tetap tidak
## ditukar sebelum server mengizinkan.
func _test_summon_overlaps_portal() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _activate_anima_inner(")
	var end := source.find("\n\n\n", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	var dispatch := body.find("_dispatch_summon(")
	var dissolve := body.find("await _anima.summon_dissolve()")
	var portal := body.find("await _incubator.start_portal()")
	var settled := body.find("await _await_summon()")
	var swap := body.find("_anima.apply(loaded)", settled)
	_check(
		dispatch >= 0 and dissolve > dispatch and portal > dissolve,
		"the summon request leaves before the transition it hides behind"
	)
	_check(
		settled > portal and swap > settled,
		"the sprite only swaps once the server has allowed the summon"
	)
	_check(
		body.find("await _anima.summon_reveal()", settled) < swap,
		"a refused summon closes the portal and brings the old companion back"
	)


## Meter bergerak di frame yang sama dengan tap. Angkanya berasal dari CareRules
## dan katalog server, jadi yang diuji di sini pemetaan aksi ke meter dan
## gerbang aksi yang tidak boleh menebak.
func _test_optimistic_care() -> void:
	var shell: GDScript = load("res://scripts/scan_flow.gd")
	var row := {
		"id": "care-optimistic",
		"care": {"hunger": 50.0, "energy": 40.0, "hygiene": 30.0, "bond": 0.0},
		"care_synced_at": Time.get_datetime_string_from_system(true) + "Z",
	}
	var catalog: Array = [
		{"id": "berry", "use_type": "food", "effect": "hunger", "effect_value": 25},
	]
	var cleaned: Dictionary = shell.optimistic_care(row, "care-optimistic", "clean", "", catalog)
	_check(
		absf(float(cleaned["hygiene"]) - 65.0) < 1.0 and absf(float(cleaned["hunger"]) - 50.0) < 1.0,
		"Clean paints Hygiene immediately and leaves the other meters alone"
	)
	var played: Dictionary = shell.optimistic_care(row, "care-optimistic", "play", "", catalog)
	_check(
		absf(float(played["energy"]) - 35.0) < 1.0,
		"Play spends its Energy on screen before the server confirms"
	)
	var fed: Dictionary = shell.optimistic_care(row, "care-optimistic", "feed", "berry", catalog)
	_check(
		absf(float(fed["hunger"]) - 75.0) < 1.0,
		"Feed restores the catalog value the client already holds"
	)
	_check(
		(shell.optimistic_care(row, "care-optimistic", "feed", "unknown", catalog) as Dictionary)
		.is_empty(),
		"an unknown food guesses nothing and waits for the server"
	)
	_check(
		(shell.optimistic_care(row, "care-optimistic", "sleep", "", catalog) as Dictionary).is_empty()
		and (shell.optimistic_care({}, "", "clean", "", catalog) as Dictionary).is_empty(),
		"Sleep and an unloaded Anima leave the meters untouched"
	)


func _test_home_tap_interaction(scene: Node) -> void:
	var shell_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		shell_source.find("event is InputEventScreenTouch") >= 0
		and shell_source.find("event is InputEventMouseButton") >= 0,
		"Home interaction accepts native touch and mouse input"
	)
	_check(
		shell_source.find("_anima.hit_test(press_position)") >= 0,
		"Home interaction reacts only when the Anima sprite is hit"
	)
	# Container memakai MOUSE_FILTER_STOP secara default, jadi tap di atas Stage
	# ditelan GUI sebelum _unhandled_input. Seluruh rantai di atas Anima wajib
	# tembus klik, kalau tidak interaksinya mati tanpa galat apa pun.
	for path in [
		"UI/SafeMargin",
		"UI/SafeMargin/Shell",
		"UI/SafeMargin/Shell/ViewStack",
		"UI/SafeMargin/Shell/ViewStack/HomeView",
		"UI/SafeMargin/Shell/ViewStack/HomeView/Column",
		"UI/SafeMargin/Shell/ViewStack/HomeView/Column/StageSpace",
	]:
		var control := scene.get_node_or_null(path) as Control
		_check(
			control != null and control.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"%s stays click-through so stage taps reach the Anima" % String(path).get_file()
		)
	var care_dock := scene.find_child("CareDock", true, false) as Control
	_check(
		care_dock != null and care_dock.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"care controls still capture their own taps"
	)


## Tap-to-wake: satu cara kedua membangunkan Anima selain tombol Wake, dengan
## target acak 3-6 yang di-roll ulang tiap sesi tidur. Diam total (tidak
## menghitung, bukan hanya menolak) selama evolving/dormant/pending_care lain
## masih terbang -- sama seperti gerbang yang sudah dipegang `_commit_care`.
func _test_wake_tap_gesture(scene: Node) -> void:
	var previous_anima: Dictionary = scene.get("_current_anima")
	var previous_taps: int = scene.get("_wake_taps")
	var previous_target: int = scene.get("_wake_taps_target")

	scene.set("_wake_taps", 0)
	scene.set("_wake_taps_target", 0)
	scene.set("_current_anima", {"id": "wake-tap-test", "status": "ready"})
	_check(
		not bool(scene.call("_register_sleep_tap")) and int(scene.get("_wake_taps")) == 0,
		"an awake Anima never starts counting wake taps"
	)

	var sleeping_row: Dictionary = (scene.get("_current_anima") as Dictionary).duplicate(true)
	sleeping_row["sleep_started_at"] = "2026-08-24T00:00:00+00:00"
	scene.set("_current_anima", sleeping_row)

	var taps := 0
	var woke := false
	while taps < 20 and not woke:
		woke = bool(scene.call("_register_sleep_tap"))
		taps += 1
	_check(woke, "enough taps on a sleeping Anima eventually wake it")
	_check(taps >= 3 and taps <= 6, "the wake target lands in 3-6 (got %d)" % taps)
	_check(
		int(scene.get("_wake_taps")) == 0 and int(scene.get("_wake_taps_target")) == 0,
		"the counter and its rolled target both clear the instant the target is hit"
	)

	# RNG isn't seeded here, so both ends of the range must be sampled directly
	# rather than trusted from one roll -- an off-by-one would only ever miss
	# one edge of 3..6, not the middle.
	var seen_targets: Dictionary = {}
	for _i in 80:
		scene.set("_wake_taps", 0)
		scene.set("_wake_taps_target", 0)
		var t := 0
		var reached := false
		while t < 20 and not reached:
			reached = bool(scene.call("_register_sleep_tap"))
			t += 1
		seen_targets[t] = true
	for target in seen_targets.keys():
		_check(target >= 3 and target <= 6, "no roll lands outside 3-6 (got %d)" % target)
	_check(seen_targets.has(3), "the roll can land on the minimum of 3 taps")
	_check(seen_targets.has(6), "the roll can land on the maximum of 6 taps")

	scene.set("_current_anima", sleeping_row)
	scene.set("_wake_taps", 0)
	scene.set("_wake_taps_target", 0)
	var evolving_row := sleeping_row.duplicate(true)
	evolving_row["status"] = "evolving"
	scene.set("_current_anima", evolving_row)
	_check(
		not bool(scene.call("_register_sleep_tap")) and int(scene.get("_wake_taps")) == 0,
		"a tap during evolution never counts toward waking"
	)

	var dormant_row := sleeping_row.duplicate(true)
	dormant_row["dormant_since"] = "2026-08-20T00:00:00+00:00"
	scene.set("_current_anima", dormant_row)
	_check(
		not bool(scene.call("_register_sleep_tap")) and int(scene.get("_wake_taps")) == 0,
		"a tap on a Dormant Anima never counts toward waking"
	)

	scene.set("_current_anima", sleeping_row)
	# GameState is an autoload, unresolvable as a bare identifier from this
	# script -- it's the `--script` entry point itself, compiled before
	# autoloads exist. Same workaround as test_client_state.gd: fetch the
	# running node instead of naming the global.
	var game_state := get_root().get_node("GameState")
	var pending_before: Variant = game_state.get("pending_care")
	game_state.set("pending_care", {"anima_id": "someone-else", "action": "feed"})
	_check(
		not bool(scene.call("_register_sleep_tap")) and int(scene.get("_wake_taps")) == 0,
		"a tap while another care action is in flight never counts toward waking"
	)
	game_state.set("pending_care", pending_before)

	scene.set("_wake_taps", 2)
	scene.set("_wake_taps_target", 5)
	scene.call("_reset_wake_taps")
	_check(
		int(scene.get("_wake_taps")) == 0 and int(scene.get("_wake_taps_target")) == 0,
		"_reset_wake_taps clears both the count and its rolled target"
	)

	scene.set("_current_anima", previous_anima)
	scene.set("_wake_taps", previous_taps)
	scene.set("_wake_taps_target", previous_target)


func _test_anima_tap_reactions() -> void:
	var presenter = load("res://scripts/anima_presenter.gd").new()
	root.add_child(presenter)
	await process_frame

	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var frames := SpriteFrames.new()
	for pose in ["idle", "sleep", "defeated"]:
		frames.add_animation(StringName(pose))
		frames.add_frame(StringName(pose), texture)
	presenter.sprite_frames = frames
	presenter.offset = Vector2(0.0, -32.0)
	presenter.set_pose("idle")

	var center: Vector2 = presenter.get_global_transform_with_canvas() * Vector2(0.0, -32.0)
	_check(presenter.hit_test(center), "Anima hit test accepts a tap on the sprite")
	_check(
		not presenter.hit_test(center + Vector2(400.0, 0.0)),
		"Anima hit test ignores taps beside the sprite"
	)

	presenter.react_to_tap()
	var hop: float = await _lowest_sample(0.4, func() -> float: return presenter.position.y)
	_check(hop < -4.0, "tapping an awake Anima hops it")

	presenter.set_pose("sleep")
	presenter.react_to_tap()
	var bob: float = await _lowest_sample(0.4, func() -> float: return presenter.rotation)
	_check(bob < -0.01, "tapping a sleeping Anima gives a sleepy bob")

	presenter.set_pose("defeated")
	presenter.react_to_tap()
	var accent: float = await _lowest_sample(0.4, func() -> float: return -presenter.scale.y)
	_check(accent < -1.02, "tapping a Dormant Anima gives a weak accent")

	presenter.queue_free()
	await process_frame


## Frame delta headless tidak stabil, jadi puncak animasi diukur lewat sampling,
## bukan dengan menebak satu titik waktu.
func _lowest_sample(seconds: float, sampler: Callable) -> float:
	var lowest: float = sampler.call()
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		lowest = minf(lowest, sampler.call())
	return lowest


## Satu ikon terbang sekali pakai: berpindah dari titik awal ke pusat target,
## memanggil `on_arrive` tepat sekali, lalu membuang dirinya. Payoff-nya di
## Bag bergantung pada busur ini benar-benar sampai, bukan cuma spawn lalu diam.
func _test_fly_to_animation() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	await process_frame

	# 341x341 on purpose, matching CatalogAtlas.CELL: the real bug this guards
	# only shows up when the texture's NATIVE size is bigger than the
	# requested display box. An 8x8 texture (smaller than the 72x72 box) would
	# never trigger TextureRect's minimum-size clamp and would have let this
	# regression straight through, which is exactly how it shipped the first
	# time -- confirmed by reproducing it directly: without
	# `expand_mode = EXPAND_IGNORE_SIZE`, requesting (72, 96) on a texture this
	# size renders at (341, 341) instead, because `Control.size`'s setter
	# clamps up to `get_minimum_size()`, which for a plain TextureRect defaults
	# to the texture's own size.
	var image := Image.create(341, 341, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var from_rect := Rect2(Vector2(20.0, 20.0), Vector2(72.0, 72.0))
	var to_rect := Rect2(Vector2(400.0, 500.0), Vector2(48.0, 48.0))
	var target_center := to_rect.get_center()

	var arrived := [0]
	UiJuice.fly_to(host, texture, from_rect, to_rect, func() -> void: arrived[0] += 1)
	await process_frame

	var flyer: TextureRect = null
	for child in host.get_children():
		if child is TextureRect:
			flyer = child
	_check(flyer != null, "fly_to spawns its one-shot flyer under the host")
	_check(
		flyer != null and flyer.size == from_rect.size,
		"the flyer renders at the requested box size, not clamped up to the texture's native size"
	)
	_check(
		flyer != null and flyer.z_index > 0,
		"the flyer draws above the sheet chrome it flies past"
	)

	# A plain `_lowest_sample` callable would still be invoked once more the
	# frame the flyer frees itself -- Godot logs a hard engine error when a
	# lambda's captured Node has been freed, even guarded by
	# `is_instance_valid()` inside the body. The while-guard here checks
	# `arrived[0]` before ever touching `flyer` again, so a freed node is
	# never passed to a lambda call in the first place.
	var closest := INF
	var peak_scale := 0.0
	var last_scale := 1.0
	var sample_deadline := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < sample_deadline and arrived[0] == 0:
		await process_frame
		if arrived[0] == 0 and is_instance_valid(flyer):
			# `global_position` here, not `position`: the tween drives
			# `global_position` directly (see fly_to's docstring for why), and
			# reading `.position` right back lags a frame behind it -- Control
			# only recomputes its cached local position lazily, so sampling
			# `.position` on the same frame the tween just wrote
			# `global_position` measures stale data, not what's actually drawn.
			closest = minf(
				closest, (flyer.global_position + flyer.size * 0.5).distance_to(target_center)
			)
			peak_scale = maxf(peak_scale, flyer.scale.x)
			last_scale = flyer.scale.x
	# The sample one frame before arrival is the closest reachable without
	# racing the freed node (see the comment above), not the true t=1 position,
	# and headless frame steps track real wall-clock deltas -- how many frames
	# land before arrival (and therefore how close the last one gets) varies
	# run to run with machine load. A fixed pixel threshold measured on one run
	# already flaked on a second run (0.7 px vs 12.5 px for the same rects), so
	# the bound here is relative to how far the flyer actually had to travel,
	# not an absolute pixel count tuned to whichever frame happened to land.
	var initial_distance := from_rect.get_center().distance_to(target_center)
	_check(
		closest < initial_distance * 0.1,
		"the flyer's visual center actually converges on the target's center"
	)
	_check(arrived[0] == 1, "fly_to calls its arrival callback exactly once")
	_check(
		peak_scale > 1.15,
		"the flyer bulges up mid-flight instead of just shrinking in a straight line (peak %.2f)" % peak_scale
	)
	_check(
		last_scale < 0.7,
		"the flyer has shrunk back down toward its landing scale by the time it arrives (last %.2f)" % last_scale
	)
	_check(
		not is_instance_valid(flyer) or flyer.is_queued_for_deletion(),
		"the flyer frees itself once it lands"
	)

	host.queue_free()

	var missing_arrived := [0]
	UiJuice.fly_to(host, null, from_rect, to_rect, func() -> void: missing_arrived[0] += 1)
	_check(
		missing_arrived[0] == 1,
		"a missing texture or a freed host still resolves the arrival callback instead of hanging"
	)


## Feed dan item energi masing-masing terbang lewat arc dari sheet yang baru
## menutup, diserap ke tubuh Anima, dan HANYA di titik itu bob/kilau/burst-nya
## menyala -- beda untuk keduanya supaya tidak terasa seperti animasi yang
## sama dipakai ulang.
func _test_consumable_flight_to_anima() -> void:
	# body_viewport_rect(): satu-satunya penyeberangan Node2D -> ruang
	# viewport yang disahkan untuk Anima. Anchor terpisah dengan skala
	# terkendali, sama seperti `AnimaBody` di scan_flow.gd, supaya assert skala
	# di bawah benar-benar menguji transform kanvas, bukan sekadar "non-zero".
	var anchor := Node2D.new()
	root.add_child(anchor)
	var presenter = load("res://scripts/anima_presenter.gd").new()
	anchor.add_child(presenter)
	await process_frame

	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.add_frame(&"idle", texture)
	presenter.sprite_frames = frames
	presenter.set_pose("idle")
	presenter.visible = true

	anchor.scale = Vector2.ONE
	var rect_1x: Rect2 = presenter.body_viewport_rect()
	anchor.scale = Vector2(2.0, 2.0)
	var rect_2x: Rect2 = presenter.body_viewport_rect()
	anchor.scale = Vector2.ONE
	_check(rect_1x.size != Vector2.ZERO, "body_viewport_rect returns a real box for a loaded pose")
	_check(
		is_equal_approx(rect_2x.size.x, rect_1x.size.x * 2.0),
		"body_viewport_rect scales with the Home body anchor -- a raw opaque_local_rect() would not"
	)

	# Feed: satu hop tinggi (HOP_HEIGHT_PX). Item: dua bob rendah. Different
	# depth AND rhythm, both checked, because matching just one would let a
	# regression collapse them back into the same reaction.
	presenter.care_feedback("feed")
	# Checked before the sample wait below: the tint tween is a short single
	# blip (0.30s total) that can finish and go invalid before a 0.35s hop
	# sample loop returns, which would fail this for timing, not for logic.
	_check(
		presenter.get("_care_tint") != null and presenter.get("_care_tint").is_valid(),
		"feed leaves a live tint tween of its own -- not just the hop"
	)
	var feed_hop: float = await _lowest_sample(0.35, func() -> float: return presenter.position.y)
	_check(feed_hop < -4.0, "feeding hops the Anima")
	var feed_burst: CPUParticles2D = null
	for child in anchor.get_children():
		if child is CPUParticles2D:
			feed_burst = child
	_check(feed_burst != null and feed_burst.emitting, "feed fires an impact burst")
	var feed_color: Color = feed_burst.color if feed_burst != null else Color.BLACK

	await create_timer(0.5).timeout

	presenter.care_feedback("item")
	var item_bob: float = await _lowest_sample(0.35, func() -> float: return presenter.position.y)
	_check(item_bob < -2.0, "using an energy item bobs the Anima")
	_check(
		feed_hop < item_bob - 1.0,
		(
			"feed's single hop reaches noticeably deeper than item's low bobs (feed %.2f vs item %.2f)"
			% [feed_hop, item_bob]
		)
	)
	var item_burst: CPUParticles2D = null
	for child in anchor.get_children():
		if child is CPUParticles2D:
			item_burst = child
	_check(
		item_burst != null and item_burst.color != feed_color,
		"item's burst is tinted differently from feed's"
	)
	# Snapshot value-typed color and the shared texture resource NOW -- both
	# `feed_burst`/`item_burst` alias the same reused `_burst_particles` node,
	# so reading `.color`/`.texture` off them after clean() reassigns those
	# properties would silently read clean's own values back.
	var item_color: Color = item_burst.color if item_burst != null else Color.BLACK
	var feed_texture: Texture2D = feed_burst.texture if feed_burst != null else null

	await create_timer(0.5).timeout

	presenter.care_feedback("clean")
	var clean_burst: CPUParticles2D = null
	for child in anchor.get_children():
		if child is CPUParticles2D:
			clean_burst = child
	_check(
		clean_burst != null and clean_burst.emitting and clean_burst.color != feed_color
		and clean_burst.color != item_color,
		"clean fires its own tinted burst, distinct from feed and item"
	)
	_check(
		clean_burst != null and clean_burst.texture != feed_texture,
		"clean's bubble burst uses a ring texture, not feed/item's solid spark"
	)
	_check(
		clean_burst != null and clean_burst.gravity.y < 0.0,
		"clean's bubbles float upward (negative gravity) instead of falling like feed/item's sparks"
	)
	# Regression pin: a stray Gradient point index once left the ring
	# texture's true offset-1.0 point at Gradient's own default (opaque
	# white), which rendered as a solid white square behind the ring instead
	# of a transparent corner.
	var bubble_image: Image = clean_burst.texture.get_image() if clean_burst != null else null
	_check(
		bubble_image != null and bubble_image.get_pixel(0, 0).a < 0.02,
		"the bubble texture's corners are transparent, not a leftover opaque square"
	)

	presenter.queue_free()
	anchor.queue_free()
	await process_frame

	# arc_px bends fly_to's PATH, not its coordinate space -- straight flights
	# (arc_px = 0, the default) must be untouched, which is why
	# _test_fly_to_animation()'s assertions above still hold unmodified.
	var arc_host := Control.new()
	arc_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(arc_host)
	await process_frame
	var arc_image := Image.create(341, 341, false, Image.FORMAT_RGBA8)
	arc_image.fill(Color.WHITE)
	var arc_texture := ImageTexture.create_from_image(arc_image)
	var arc_from := Rect2(Vector2(40.0, 900.0), Vector2(72.0, 72.0))
	var arc_to := Rect2(Vector2(340.0, 300.0), Vector2(96.0, 96.0))
	var arc_target := arc_to.get_center()
	var arc_start := arc_from.get_center()
	var straight_len := arc_start.distance_to(arc_target)
	var arc_arrived := [0]
	UiJuice.fly_to(
		arc_host, arc_texture, arc_from, arc_to,
		func() -> void: arc_arrived[0] += 1,
		UiJuice.FLY_TO_ARC_PX, 0.0
	)
	await process_frame
	var arc_flyer: TextureRect = null
	for child in arc_host.get_children():
		if child is TextureRect:
			arc_flyer = child
	_check(arc_flyer != null, "an arced flight still spawns its one-shot flyer")

	var max_deviation := 0.0
	var arc_closest := INF
	var arc_last_alpha := 1.0
	var deadline := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < deadline and arc_arrived[0] == 0:
		await process_frame
		if arc_arrived[0] == 0 and is_instance_valid(arc_flyer):
			var center: Vector2 = arc_flyer.global_position + arc_flyer.size * 0.5
			# Perpendicular distance from the straight start->target segment --
			# a real lob bulges away from that line at its apex; a straight
			# tween never leaves it (up to floating-point noise).
			var along := arc_target - arc_start
			var t := (center - arc_start).dot(along) / (straight_len * straight_len)
			var closest_on_line: Vector2 = arc_start + along * clampf(t, 0.0, 1.0)
			max_deviation = maxf(max_deviation, center.distance_to(closest_on_line))
			arc_closest = minf(arc_closest, center.distance_to(arc_target))
			arc_last_alpha = arc_flyer.modulate.a
	_check(
		max_deviation > 20.0,
		"an arced flight actually bulges off the straight line (peak deviation %.1f px)" % max_deviation
	)
	_check(
		arc_closest < straight_len * 0.1,
		"an arced flight still converges on the target despite the detour"
	)
	_check(arc_arrived[0] == 1, "an arced flight calls its arrival callback exactly once")
	_check(
		arc_last_alpha < 0.2,
		"fade_to = 0.0 genuinely absorbs the icon instead of parking it at fly_to's default 0.85 alpha"
	)
	_check(
		not is_instance_valid(arc_flyer) or arc_flyer.is_queued_for_deletion(),
		"an arced flight's flyer frees itself once it lands"
	)
	arc_host.queue_free()

	# Source scan: the snapshot has to happen before the sheet frees the row
	# it lives on, and both non-battle branches must defer their reaction to
	# the flight landing rather than firing it at tap time.
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var use_body := _func_body(flow_source, "func _use_catalog_item(")
	_check(
		use_body.find("icon_snapshot_for(") >= 0
		and use_body.find("icon_snapshot_for(") < use_body.find("_shop_sheet.close()"),
		"the row's icon is snapshotted before the sheet closes and frees it"
	)
	_check(
		use_body.find("_fly_consumable_to_anima(icon_snapshot, \"feed\")") >= 0
		and use_body.find("_fly_consumable_to_anima(icon_snapshot, \"item\")") >= 0,
		"both Feed and energy-item branches hand their reaction to the flight, not care_feedback directly"
	)
	var commit_body := _func_body(flow_source, "func _commit_care(")
	_check(
		commit_body.find("on_react: Callable") >= 0 and commit_body.find("on_react.call()") >= 0,
		"_commit_care can defer its reaction to a caller-supplied hook"
	)


func _test_scan_phase_visuals() -> void:
	var packed := load("res://scenes/ui/scan_view.tscn") as PackedScene
	var view := packed.instantiate()
	root.add_child(view)
	view.visible = true
	await process_frame
	await process_frame
	view.call("_align_idle_graphic")
	await process_frame
	var idle_graphic := view.find_child("IdleGraphic", true, false) as TextureRect
	var preview := view.find_child("PreviewPanel", true, false) as PanelContainer
	var overlay := view.find_child("ScanOverlay", true, false) as Control
	_check(idle_graphic != null and idle_graphic.visible, "idle Scan shows the camera graphic")
	_check(overlay != null and not overlay.visible, "scan overlay starts hidden")
	await process_frame
	var discovery := idle_graphic.get_parent() as Control
	var half := idle_graphic.size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		half = Vector2(86.0, 86.0)
	var icon_center := idle_graphic.global_position + idle_graphic.size * 0.5
	if idle_graphic.size.x <= 0.0:
		icon_center = idle_graphic.global_position + half
	var chamber_local := discovery.get_global_transform_with_canvas().affine_inverse() * (
		ScanimaBackground.chamber_center(view.get_viewport_rect().size)
	)
	chamber_local += ScanView.CAMERA_OPTICAL_OFFSET
	chamber_local.x = clampf(chamber_local.x, half.x, maxf(half.x, discovery.size.x - half.x))
	chamber_local.y = clampf(chamber_local.y, half.y, maxf(half.y, discovery.size.y - half.y))
	_check(
		icon_center.distance_to(discovery.global_position + chamber_local) < 2.0,
		"idle camera sits on the chamber ring"
	)
	var subtitle := view.find_child("Subtitle", true, false) as Label
	var phase_badge := view.find_child("ScanPhase", true, false) as Label
	var status := view.find_child("ScanStatus", true, false) as Label
	_check(
		subtitle != null
		and not subtitle.visible
		and phase_badge != null
		and not phase_badge.visible
		and status != null
		and not status.visible,
		"idle Scan hides subtitle and ready-status copy"
	)

	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	view.show_preview(ImageTexture.create_from_image(image))
	view.set_phase(&"analyzing")
	await process_frame
	_check(preview.visible, "analysis keeps the captured photo visible")
	_check(not idle_graphic.visible, "analysis hides the idle camera graphic")
	_check(overlay.visible and overlay.is_processing(), "analysis animates a scanner over the photo")

	view.clear_preview()
	view.set_phase(&"synthesizing")
	_check(not preview.visible, "synthesis clears the captured photo")
	_check(not idle_graphic.visible, "synthesis keeps the camera graphic hidden")
	_check(not overlay.visible, "synthesis leaves only the Incubator visual")
	view.set_phase(&"idle")
	_check(idle_graphic.visible, "returning idle restores the camera graphic")
	var scan_button := view.find_child("ScanButton", true, false) as Button
	var hint := view.find_child("ScanPhaseHint", true, false) as Label
	view.set_cores(0)
	_check(
		scan_button != null and scan_button.self_modulate.a < 0.5
		and hint != null and hint.text == tr("SCAN_NO_CORE_HINT"),
		"empty Cores dim Scan and explain the lock"
	)
	view.set_cores(1)
	_check(
		is_equal_approx(scan_button.self_modulate.a, 1.0)
		and hint.text == tr("SCAN_CAMERA_HINT"),
		"a remaining Core restores the Scan CTA"
	)
	var vibe_block := view.find_child("VibeBlock", true, false) as Control
	_check(vibe_block != null and vibe_block.visible, "idle Scan shows the optional Vibe selector")
	_check_eq(view.vibe(), "natural", "fresh Scan defaults to Natural")
	view.set_status(tr("STATUS_SCAN_READY"))
	_check_eq(
		(view.find_child("ScanStatus", true, false) as Label).text,
		tr("STATUS_SCAN_READY"),
		"Scan still writes in-page status"
	)
	_check(
		not (view.find_child("ScanStatus", true, false) as Label).visible,
		"idle Scan does not paint ready-status as a third headline"
	)
	for slug in ["natural", "cute", "brave", "wild", "sinister"]:
		var vibe_button := view.find_child("Vibe%s" % slug.capitalize(), true, false) as Button
		_check(
			vibe_button != null
			and vibe_button.custom_minimum_size.y >= TOUCH_MIN
			and vibe_button.focus_mode == Control.FOCUS_ALL
			and vibe_button.autowrap_mode == TextServer.AUTOWRAP_OFF
			and not vibe_button.text.is_empty(),
			"%s Vibe stays a 96px labelled focus target" % slug
		)
	view.set_vibe("cute")
	var cute_button := view.find_child("VibeCute", true, false) as Button
	_check(
		view.vibe() == "cute"
		and cute_button != null
		and cute_button.theme_type_variation == &"VibeSelected",
		"choosing Cute marks that chip without requiring another Scan tap"
	)
	view.set_phase(&"analyzing")
	_check(not vibe_block.visible, "analysis hides Vibe so the choice cannot change mid-scan")
	_check(
		phase_badge.visible and status.visible,
		"analysis restores phase copy"
	)
	view.set_phase(&"idle")
	_check(vibe_block.visible and view.vibe() == "cute", "returning idle keeps the chosen Vibe")
	view.reset_vibe()
	_check_eq(view.vibe(), "natural", "a finished Scan returns the selector to Natural")
	var sign_in_requests: Array[String] = []
	view.sign_in_requested.connect(func() -> void: sign_in_requests.append("sign_in"))
	view.set_sign_in_required(true)
	_check(
		scan_button.text == tr("SCAN_SIGN_IN_ACTION")
		and not hint.visible
		and not scan_button.disabled,
		"used guest Scan becomes an active Google sign-in CTA"
	)
	scan_button.pressed.emit()
	_check_eq(sign_in_requests.size(), 1, "guest Scan CTA requests sign-in instead of camera")

	view.queue_free()
	await process_frame


func _test_scan_rejection_dialog() -> void:
	var packed := load("res://scenes/scan_flow.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var modal := scene.find_child("ShellModal", true, false) as UiModal
	_check(modal != null, "ShellModal exists in scan_flow")
	if modal != null:
		var modal_title := modal.find_child("ModalTitle", true, false) as Label
		var modal_body := modal.find_child("ModalBody", true, false) as Label
		var modal_primary := modal.find_child("PrimaryButton", true, false) as Button

		# Pemicuan scan rejection dialog dengan contoh reason "human_face"
		var test_reason := "human_face"
		var locale_manager := root.get_node("LocaleManager")
		var friendly: String = locale_manager.gate_reason(test_reason)
		scene.call("_show_scan_rejected_dialog", test_reason, friendly)
		await process_frame

		_check(modal.visible, "Scan rejection dialog opens modal")
		_check_eq(modal_title.text, tr("SCAN_REJECTED_TITLE"), "Scan rejection dialog shows correct title")
		_check(
			modal_body.text.find(friendly) >= 0 and modal_body.text.find(test_reason) >= 0,
			"Scan rejection dialog body explains both friendly message and LLM reason code"
		)
		_check_eq(modal_primary.text, tr("SCAN_REJECTED_CLOSE"), "Scan rejection dialog close button uses Got It")

		# Tutup modal
		modal_primary.pressed.emit()
		await create_timer(0.25).timeout
		_check(not modal.visible, "Scan rejection dialog closes on action button press")

	scene.queue_free()
	await process_frame


func _test_seeker_ui() -> void:
	var flow_script := load("res://scripts/scan_flow.gd") as GDScript
	_check(
		not flow_script.profile_value_present({"guest_scan_used_at": null}, &"guest_scan_used_at"),
		"database null must not lock a fresh guest Scan"
	)
	_check(
		not flow_script.profile_value_present({"seeker_name": null}, &"seeker_name"),
		"database null must leave Seeker onboarding incomplete"
	)
	_check(
		not flow_script.profile_value_present({"account_upgraded_at": null}, &"account_upgraded_at"),
		"database null must keep the idempotent Google grant retry enabled"
	)
	var onboarding = (
		load("res://scenes/ui/seeker_onboarding_sheet.tscn") as PackedScene
	).instantiate()
	root.add_child(onboarding)
	await process_frame
	var submitted: Array[Dictionary] = []
	onboarding.submit_requested.connect(
		func(name: String, birth_year: Variant, gender: Variant, avatar: Variant) -> void:
			submitted.append({
				"name": name,
				"birth_year": birth_year,
				"gender": gender,
				"avatar": avatar,
			})
	)
	onboarding.show_for_profile()
	# The figure is decided in the same sheet as the name, as one row inside the
	# one submit -- and it opens already answered, so a Seeker who does not care
	# about it can go straight back to their first Anima.
	var avatar_row := onboarding.find_child("SeekerAvatar", true, false) as SeekerAvatarPicker
	_check_eq(
		_live_row_count(avatar_row),
		SeekerRoster.SLUGS.size(),
		"onboarding shows the whole Seeker Roster in one row of the sheet it already had"
	)
	_check(
		_marked_avatar_slugs(avatar_row) == PackedStringArray([SeekerRoster.DEFAULT_SLUG]),
		"the onboarding picker opens with the default figure already chosen"
	)
	var onboarding_panel := onboarding.panel() as Control
	var onboarding_scroll := onboarding.find_child("ContentScroll", true, false) as ScrollContainer
	_check(
		onboarding_scroll != null
		and onboarding_panel.theme_type_variation == &"BottomSheetPanel",
		"Seeker onboarding scrolls inside the shared bottom-sheet surface"
	)
	onboarding._fit_scroll_to_host(600.0)
	_check(
		onboarding_panel.get_combined_minimum_size().y <= 600.0 * onboarding.max_height_ratio + 1.0,
		"Seeker onboarding stays operable in a short landscape viewport"
	)
	onboarding.fit_to_content()
	var seeker_name_edit := onboarding.find_child("SeekerName", true, false) as LineEdit
	var seeker_name_label := onboarding.find_child("NameLabel", true, false) as Label
	var onboarding_feedback := (
		onboarding.find_child("OnboardingFeedback", true, false) as Label
	)
	var onboarding_submit := onboarding.find_child("OnboardingSubmit", true, false) as Button
	seeker_name_edit.text = "Nova Seeker"
	onboarding_submit.pressed.emit()
	_check_eq(submitted.size(), 0, "Seeker names containing spaces never reach the server")
	_check(
		onboarding_feedback.visible
		and onboarding_feedback.text == tr("SEEKER_NAME_INVALID")
		and onboarding_feedback.theme_type_variation == &"ErrorLabel"
		and seeker_name_label.theme_type_variation == &"ErrorLabel"
		and seeker_name_edit.theme_type_variation == &"ErrorLineEdit",
		"invalid Seeker name highlights the label, field, and inline error in red"
	)
	seeker_name_edit.text = "Nova_13"
	seeker_name_edit.text_changed.emit(seeker_name_edit.text)
	onboarding.show_error(tr("SEEKER_NAME_TAKEN"))
	_check(
		onboarding_feedback.text == tr("SEEKER_NAME_TAKEN")
		and seeker_name_edit.theme_type_variation == &"ErrorLineEdit",
		"a taken Seeker name uses the same prominent field error state"
	)
	seeker_name_edit.text = "Nova_14"
	seeker_name_edit.text_changed.emit(seeker_name_edit.text)
	_check(
		not onboarding_feedback.visible
		and seeker_name_edit.theme_type_variation == &"",
		"editing the rejected Seeker name clears its stale error state"
	)
	seeker_name_edit.text = "Nova_13"
	(onboarding.find_child("BirthYear", true, false) as LineEdit).text = "2000"
	(onboarding.find_child("Gender", true, false) as OptionButton).select(2)
	onboarding_submit.pressed.emit()
	_check_eq(submitted.size(), 1, "Seeker onboarding emits one normalized submission")
	if not submitted.is_empty():
		_check_eq(submitted[0].name, "Nova_13", "Seeker name reaches the server boundary")
		_check_eq(submitted[0].birth_year, 2000, "optional birth year remains numeric")
		_check_eq(submitted[0].gender, "man", "optional gender uses the server enum")
		# Untouched means unanswered, exactly like a blank birth year: the figure
		# travels as null so the server can tell "chose the default" apart from
		# "left it alone" -- and, either way, the name still lands.
		_check(
			typeof(submitted[0].avatar) == TYPE_NIL,
			"submitting without touching the picker still completes, and sends no figure"
		)

	# Gender and the figure are separate answers and must stay that way
	# (ADR-0001). Checked in both directions -- either one alone would still let
	# an appearance be derived from what the player said about themselves.
	var gender_select := onboarding.find_child("Gender", true, false) as OptionButton
	gender_select.select(1)
	gender_select.item_selected.emit(1)
	_check(
		_marked_avatar_slugs(avatar_row) == PackedStringArray([SeekerRoster.DEFAULT_SLUG]),
		"answering Gender never moves the figure the Seeker is about to submit"
	)
	var other := avatar_row.get_child(SeekerRoster.SLUGS.size() - 1) as Button
	var other_slug := str(other.get_meta("avatar", ""))
	# Mirrors a real tap on a toggle: Godot flips pressed first and reports the
	# tap after, so the row is handed a moment with two figures marked.
	other.button_pressed = true
	other.pressed.emit()
	_check(
		gender_select.selected == 1
		and _marked_avatar_slugs(avatar_row) == PackedStringArray([other_slug])
		and not other_slug.is_empty(),
		"picking a figure marks that one alone and leaves the Gender answer alone"
	)
	onboarding_submit.pressed.emit()
	_check_eq(submitted.size(), 2, "the figure rides the same single submit, with no extra step")
	if submitted.size() > 1:
		_check_eq(submitted[1].avatar, other_slug, "the figure the Seeker picked is what is sent")
		_check_eq(submitted[1].gender, "woman", "the Gender answer still travels in its own field")
	onboarding.set_busy(true)
	_check(
		other.disabled,
		"a submit in flight locks the figure row with the rest of the form"
	)
	onboarding.set_busy(false)

	# A Seeker can reach Profile and pick a figure before ever naming themselves,
	# and then the sheet has to open on the figure they are already wearing --
	# otherwise the default would sit there ready to overwrite their choice. It
	# still counts as untouched, so leaving it alone sends null and the server
	# keeps what it has.
	onboarding.show_for_profile(other_slug)
	_check(
		_marked_avatar_slugs(avatar_row) == PackedStringArray([other_slug]),
		"reopening seeds the picker with the figure already stored, not the default"
	)
	onboarding_submit.pressed.emit()
	_check_eq(submitted.size(), 3, "the seeded sheet still submits")
	if submitted.size() > 2:
		_check(
			typeof(submitted[2].avatar) == TYPE_NIL,
			"a seeded figure left untouched is not resent, so the stored one survives"
		)

	var menu = (load("res://scenes/ui/seeker_menu_sheet.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	menu.show_menu(true, true, true)
	_check(
		(menu.find_child("SeekerMenuTitle", true, false) as Label).text == tr("SETTINGS_TITLE"),
		"Settings menu uses the shared title"
	)
	_check(
		(menu.find_child("ChapterPush", true, false) as CheckButton).visible
		and (menu.find_child("ChapterPush", true, false) as CheckButton).button_pressed,
		"OS chapter push is an explicit opt-in shown only when its native adapter exists"
	)
	# Settings is preference-only now; account identity lives on Seeker Profile.
	_check(
		menu.find_child("SeekerAccount", true, false) == null
		and menu.find_child("DeleteAccount", true, false) == null,
		"Settings carries no account action to sit oddly beside Music"
	)
	_check(
		menu.find_child("ContentScroll", true, false) is ScrollContainer,
		"Seeker menu still scrolls safely on short screens"
	)
	_check(
		(menu.find_child("MusicEnabled", true, false) as CheckButton).button_pressed,
		"music plays by default and can be turned off from Settings"
	)
	menu.show_menu(false, false, false)
	_check(
		(menu.find_child("SeekerMenuTitle", true, false) as Label).text
			== tr("SETTINGS_TITLE"),
		"Settings title stays stable for guest accounts"
	)
	_check(
		not (menu.find_child("MusicEnabled", true, false) as CheckButton).button_pressed,
		"a muted player reopens Settings with music still off"
	)

	var profile = (load("res://scenes/ui/seeker_profile_view.tscn") as PackedScene).instantiate()
	root.add_child(profile)
	await process_frame
	profile.set_profile({
		"seeker_name": "Nova_13",
		"seeker_xp": 20,
		"anima_count": 2,
		"species_count": 2,
		"battle_victories": 4,
		"created_at": "2026-08-14T00:00:00Z",
	})
	var rows := profile.find_child("SeekerRows", true, false) as VBoxContainer
	_check_eq(rows.get_child_count(), 6, "Seeker profile shows six server-authoritative stats")
	_check(
		(profile.find_child("SeekerProfileName", true, false) as Label).text == "Nova_13",
		"Seeker profile shows the unique name"
	)
	profile.set_trophies_loading(true)
	var trophy_section := profile.find_child("TrophySection", true, false) as VBoxContainer
	var trophy_skeleton := profile.find_child("TrophySkeleton", true, false) as UiSkeleton
	var trophy_grid := profile.find_child("TrophyGrid", true, false) as GridContainer
	var trophy_empty := profile.find_child("TrophyEmpty", true, false) as Label
	_check(
		trophy_section.visible
		and trophy_skeleton.visible
		and trophy_skeleton.get("_pulse") != null
		and not trophy_grid.visible
		and not trophy_empty.visible
		and trophy_skeleton.get_child(0).get_child_count() == 3,
		"Trophy Showcase shows a pulsing three-slot skeleton until Cores arrive"
	)
	var trophy_rows: Array[Dictionary] = []
	for index in 4:
		trophy_rows.append({"expedition_trophies": {
			"id": "60000000-0000-4000-8000-00000000000%d" % index,
			"display_name": "Trail Trophy %d" % (index + 1),
		}})
	profile.set_trophies(trophy_rows)
	_check(
		trophy_grid.visible
		and not trophy_empty.visible
		and not trophy_skeleton.visible
		and trophy_grid.get_child_count() == 4,
		"Trophy Showcase renders one art card per owned Core"
	)
	var first_card := trophy_grid.get_child(0).get_child(0) as TextureRect
	_check(
		first_card.texture == null and first_card.custom_minimum_size.y > 0.0,
		"a Core card reserves its art slot before the PNG lands"
	)
	profile.set_trophies(trophy_rows)
	_check(
		trophy_grid.get_child(0).get_child(0) == first_card,
		"repainting the same Cores keeps the cards instead of rebuilding them"
	)
	var core_art := ImageTexture.create_from_image(
		Image.create(8, 8, false, Image.FORMAT_RGBA8)
	)
	profile.set_trophy_art("60000000-0000-4000-8000-000000000000", core_art)
	_check(first_card.texture == core_art, "Core art drops into the card it belongs to")
	profile.set_trophies([])
	var trophy_title := trophy_section.find_child("Title", false, false) as Label
	_check(
		trophy_empty.visible and not trophy_grid.visible and not trophy_skeleton.visible,
		"an account without a Core sees the earn-one hint instead of an empty grid"
	)
	_check(
		trophy_title.theme_type_variation == &"SectionLabel"
		and trophy_empty.theme_type_variation == &"MutedLabel"
		and trophy_empty.get_theme_font_size(&"font_size")
			< trophy_title.get_theme_font_size(&"font_size"),
		"Trophy empty copy is a child caption under the section title"
	)
	profile.set_trophies_loading(true)
	profile.hide_trophies()
	_check(
		not trophy_section.visible and not trophy_skeleton.visible,
		"a failed Core fetch without cache hides Trophy Showcase instead of leaving the skeleton"
	)
	profile.set_profile({"seeker_name": null})
	_check(
		(profile.find_child("SeekerProfileName", true, false) as Label).text
			== tr("SEEKER_UNNAMED"),
		"incomplete profile never renders a null wire value"
	)

	onboarding.queue_free()
	menu.queue_free()
	profile.queue_free()
	await process_frame
	await _test_seeker_account_actions()
	await _test_seeker_avatar_choice()


## Sign in with Google, Sign Out, dan Delete Account pindah dari Settings ke
## sini: yang dijaga adalah dua invarian yang selamat dari pindah rumah — guest
## tidak boleh bisa menghapus akunnya sendiri (Core dan Bits gratis akan bisa
## di-reset berulang), dan panel kebab tidak boleh keluar dari layar.
func _test_seeker_account_actions() -> void:
	var host := SubViewport.new()
	host.size = Vector2i(720, 1602)
	root.add_child(host)
	var profile = (load("res://scenes/ui/seeker_profile_view.tscn") as PackedScene).instantiate()
	host.add_child(profile)
	profile.visible = true
	profile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var account := profile.find_child("SeekerAccount", true, false) as Button
	var menu_button := profile.find_child("SeekerProfileMenu", true, false) as Button
	var popover := profile.find_child("SeekerActionPopover", true, false) as Control
	var panel := profile.find_child("SeekerActionPanel", true, false) as Control
	var rename := profile.find_child("SeekerActionRename", true, false) as Button
	var delete_button := profile.find_child("SeekerActionDelete", true, false) as Button
	var backdrop := profile.find_child("SeekerActionBackdrop", true, false) as Control
	profile.set_account(true)
	_check(
		account.text == tr("SEEKER_SIGN_IN_GOOGLE") and not delete_button.visible,
		"a guest sees Google sign-in and cannot delete the anonymous account"
	)
	profile.set_account(false)
	_check(
		account.text == tr("SEEKER_SIGN_OUT") and delete_button.visible,
		"a linked account swaps to Sign Out and keeps Delete Account reachable"
	)
	_check(
		delete_button.get_theme_color(&"font_color") != rename.get_theme_color(&"font_color"),
		"Delete Account reads as the destructive row, not another neutral one"
	)
	var requested := {"account": 0, "rename": 0, "delete": 0}
	profile.account_requested.connect(func() -> void: requested.account += 1)
	profile.rename_requested.connect(func() -> void: requested.rename += 1)
	profile.delete_account_requested.connect(func() -> void: requested.delete += 1)
	account.pressed.emit()
	_check_eq(requested.account, 1, "the account row asks the shell once per tap")
	menu_button.pressed.emit()
	await process_frame
	_check(
		popover.visible
		and Rect2(Vector2.ZERO, profile.size).encloses(Rect2(panel.position, panel.size)),
		"the Seeker kebab panel stays inside the screen it is anchored to"
	)
	_check(
		backdrop != null and backdrop.mouse_filter == Control.MOUSE_FILTER_STOP,
		"an outside tap can dismiss the Seeker kebab"
	)
	rename.pressed.emit()
	_check(
		requested.rename == 1 and not popover.visible,
		"choosing Rename closes the kebab instead of leaving it over the modal"
	)
	menu_button.pressed.emit()
	await process_frame
	delete_button.pressed.emit()
	_check(
		requested.delete == 1 and not popover.visible,
		"choosing Delete Account closes the kebab before the confirmation opens"
	)
	menu_button.pressed.emit()
	await process_frame
	profile.set_busy(true)
	_check(
		not popover.visible and menu_button.disabled and account.disabled,
		"a request in flight closes the kebab and locks both account entry points"
	)
	host.queue_free()
	await process_frame


## Tiga hal yang pemain rasakan, diperiksa pada scene Profile sungguhan: potret
## itu dirinya dan memakai pose profil (bukan pose idle yang dipakai arena),
## picker menandai figur yang sedang ia pakai, dan penggantian terlihat tanpa
## membuka ulang layar.
func _test_seeker_avatar_choice() -> void:
	var host := SubViewport.new()
	host.size = Vector2i(720, 1602)
	root.add_child(host)
	var profile = (load("res://scenes/ui/seeker_profile_view.tscn") as PackedScene).instantiate()
	host.add_child(profile)
	profile.visible = true
	profile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var portrait := profile.find_child("SeekerPortrait", true, false) as TextureRect

	# `null` berarti belum memilih, dan yang tergambar tetap seseorang.
	profile.set_profile({"seeker_name": "Nova_13", "seeker_avatar": null})
	var pose_index := SeekerSheet.KNOWN_POSES.find("profile")
	var profile_cell := Vector2(
		float((pose_index % 3) * SeekerRoster.CELL),
		float((pose_index / 3) * SeekerRoster.CELL)
	)
	var atlas := portrait.texture as AtlasTexture
	_check(
		atlas != null and atlas.region.position == profile_cell,
		"the Profile portrait draws a Seeker Avatar in its profile pose"
	)
	_check(
		portrait.texture == SeekerRoster.portrait(SeekerRoster.DEFAULT_SLUG)
		and profile.avatar_slug() == SeekerRoster.DEFAULT_SLUG,
		"a Seeker who has not chosen yet still gets the default figure drawn"
	)

	var kebab := profile.find_child("SeekerProfileMenu", true, false) as Button
	var change := profile.find_child("SeekerActionAvatar", true, false) as Button
	var sheet := profile.find_child("SeekerAvatarSheet", true, false) as UiBottomSheet
	var grid := profile.find_child("SeekerAvatarGrid", true, false) as GridContainer
	kebab.pressed.emit()
	await process_frame
	change.pressed.emit()
	await process_frame
	await process_frame
	_check(
		sheet.visible and not profile.is_action_menu_open(),
		"Change Seeker Avatar opens the picker from the kebab it lives in"
	)
	_check_eq(
		_live_row_count(grid),
		SeekerRoster.SLUGS.size(),
		"the picker shows every roster figure at once, so they can be compared"
	)
	_check(
		_marked_avatar_slugs(grid) == PackedStringArray([SeekerRoster.DEFAULT_SLUG]),
		"the picker marks exactly the figure the Seeker is wearing"
	)

	# Stands in for the shell's optimistic half: `_change_seeker_avatar()` paints
	# before it awaits anything, and the source scan at the end of this test is
	# what pins that it still does. Wired BEFORE the tap on purpose, so the
	# repaint below is driven by the tap rather than by the test reaching for the
	# setter afterwards -- the latter would pass even if tapping did nothing.
	#
	# Dictionary, not a String: GDScript lambdas capture locals by value, so a
	# captured String would record the tap into a copy the test cannot read.
	var chosen := {"slug": ""}
	profile.avatar_chosen.connect(func(slug: String) -> void:
		chosen.slug = slug
		profile.set_avatar(slug)
	)
	var second := grid.get_child(1) as Button
	var second_slug := str(second.get_meta("avatar", ""))
	# Mirrors what Godot does to a toggle button on a real tap: the pressed state
	# flips first and the tap is reported after, so the handler is handed a moment
	# where two figures are marked and has to tidy it up.
	second.button_pressed = true
	second.pressed.emit()
	await process_frame
	_check(
		str(chosen.slug) == second_slug and not second_slug.is_empty(),
		"tapping a figure asks the shell to write that slug"
	)
	# The point of the optimistic paint: the Profile is still the screen the
	# player is looking at, and it already shows the new figure. Exactly one
	# figure may be marked -- the toggle Godot flipped on tap must not survive
	# alongside the mark the handler sets.
	_check(
		portrait.texture == SeekerRoster.portrait(second_slug)
		and _marked_avatar_slugs(grid) == PackedStringArray([second_slug]),
		"the tap alone moves the portrait and the mark, without reopening the screen"
	)

	# What the shell does when the write turns out not to have landed: the same
	# setter, handed the value it started from.
	profile.set_avatar(null)
	_check(
		portrait.texture == SeekerRoster.portrait(SeekerRoster.DEFAULT_SLUG)
		and _marked_avatar_slugs(grid) == PackedStringArray([SeekerRoster.DEFAULT_SLUG]),
		"a rejected write puts the previous figure back on the portrait and in the picker"
	)

	# Nothing here may spend anything, so nothing here may dim the screen: the
	# rollback is what makes the optimistic paint honest, not a busy state.
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var change_body := _func_body(flow_source, "func _change_seeker_avatar(")
	_check(
		change_body.find("_set_busy(") < 0
		and change_body.find("LoadingScreen.show_screen(") < 0
		and change_body.find("set_avatar(previous)") >= 0
		and change_body.find("gender") < 0
		and change_body.find("birth_year") < 0,
		"changing an avatar stays optimistic, rolls back, and never touches demographics"
	)
	host.queue_free()
	await process_frame


## Satu figur boleh tertandai, dan "tertandai" menuntut kedua penandanya sepakat.
## Plat terpilih tanpa state toggle (atau sebaliknya) tetap terbaca salah oleh
## pemain, jadi ia masuk daftar dengan namanya sendiri dan menggagalkan
## perbandingan alih-alih lolos diam-diam.
func _marked_avatar_slugs(grid: GridContainer) -> PackedStringArray:
	var marked := PackedStringArray()
	for child in grid.get_children():
		var button := child as Button
		if button == null:
			continue
		var slug := str(button.get_meta("avatar", ""))
		if button.button_pressed != (button.theme_type_variation == &"VibeSelected"):
			marked.append("%s (half-marked)" % slug)
		elif button.button_pressed:
			marked.append(slug)
	return marked


func _test_battle_view() -> void:
	# The view reads durable pending bookmarks at ready time; isolate this UI test
	# from whichever Battle the developer currently has saved in user://.
	var game_state := get_root().get_node("GameState")
	game_state.set(&"pending_battle", {})
	game_state.set(&"pending_team_battle", {})
	game_state.set(&"pending_expedition", {})
	var packed := load("res://scenes/ui/battle_view.tscn") as PackedScene
	var view := packed.instantiate()
	root.add_child(view)
	await process_frame
	var battle_script := load("res://scripts/battle_view.gd") as GDScript
	var team_script := load("res://scripts/team_battle_view.gd") as GDScript
	_check(
		not battle_script.static_background_uses_landscape(Vector2(720, 900))
		and battle_script.static_background_uses_landscape(Vector2(1600, 900))
		and not team_script.static_background_uses_landscape(Vector2(720, 900))
		and team_script.static_background_uses_landscape(Vector2(1600, 900)),
		"Duel and Team Battle select static art from the live arena aspect"
	)

	var lobby := view.find_child("BattleLobbyPanel", true, false) as Control
	var header := view.find_child("Header", true, false) as Control
	var page_title := view.find_child("Title", true, false) as Label
	var page_subtitle := view.find_child("Subtitle", true, false) as Label
	var content := view.find_child("BattleContent", true, false) as Control
	var result := view.find_child("BattleResultPanel", true, false) as Control
	var start := view.find_child("BattleStartButton", true, false) as Button
	var team_button := view.find_child("BattleTeamButton", true, false) as Button
	var expedition_button := view.find_child("BattleExpeditionButton", true, false) as Button
	var expedition_badge := view.find_child("ExpeditionNewBadge", true, false) as Label
	var lobby_name := view.find_child("BattleLobbyName", true, false) as Label
	var lobby_meta := view.find_child("BattleLobbyMeta", true, false) as Label
	var strike := view.find_child("BattleStrikeButton", true, false) as Button
	var surge := view.find_child("BattleSurgeButton", true, false) as Button
	var guard := view.find_child("BattleGuardButton", true, false) as Button
	var item := view.find_child("BattleItemButton", true, false) as Button
	var strike_commit := view.find_child("BattleStrikeCommit", true, false) as ColorRect
	var surge_commit := view.find_child("BattleSurgeCommit", true, false) as ColorRect
	var guard_commit := view.find_child("BattleGuardCommit", true, false) as ColorRect
	var item_commit := view.find_child("BattleItemCommit", true, false) as ColorRect
	var forfeit := view.find_child("BattleForfeitButton", true, false) as Button
	var turn := view.find_child("BattleTurn", true, false) as Label
	var player_hp := view.find_child("BattlePlayerHp", true, false) as ProgressBar
	var bot_hp := view.find_child("BattleBotHp", true, false) as ProgressBar
	var player_hp_value := view.find_child("BattlePlayerHpValue", true, false) as Label
	var bot_hp_value := view.find_child("BattleBotHpValue", true, false) as Label
	var daily_reward := view.find_child("BattleDailyReward", true, false) as Label
	var player_element := view.find_child("BattlePlayerElement", true, false) as Control
	var bot_element := view.find_child("BattleBotElement", true, false) as Control
	var feedback := view.find_child("BattleFeedback", true, false) as Label
	var effectiveness := view.find_child("BattleEffectiveness", true, false) as Control
	var event_plate := view.find_child("BattleEventPlate", true, false) as PanelContainer
	var fighter_hud_plate := view.find_child("FighterHudPlate", true, false) as PanelContainer
	var fighter_hud := view.find_child("FighterHud", true, false) as HBoxContainer
	var effectiveness_label := view.find_child(
		"BattleEffectivenessLabel", true, false
	) as Label
	var result_title := view.find_child("BattleResultTitle", true, false) as Label
	var result_body := view.find_child("BattleResultBody", true, false) as Label
	var retry := view.find_child("BattleRetryButton", true, false) as Button
	var arena := view.find_child("BattleArena", true, false) as Control
	var footer := view.find_child("BattleFooter", true, false) as Control
	var player_anchor := view.find_child("BattlePlayerAnchor", true, false) as Node2D
	var player_sprite := view.find_child("BattlePlayerSprite", true, false) as AnimaPresenter
	var bot_sprite := view.find_child("BattleBotSprite", true, false) as AnimaPresenter

	_check(
		fighter_hud_plate != null
		and fighter_hud != null
		and fighter_hud.get_parent() == fighter_hud_plate
		and fighter_hud_plate.has_theme_stylebox_override(&"panel"),
		"Duel wraps both fighter names and HP bars in one readable arena plate"
	)
	_check(
		team_button.visible and not team_button.disabled,
		"Team entry is ready immediately from last-known availability"
	)
	view.set_team_available(false)
	_check(team_button.disabled, "an authoritative refusal can lock Team Battle")
	view.set_team_available(true)
	_check(
		expedition_button.visible and not expedition_button.disabled,
		"Expedition entry is ready immediately from last-known availability"
	)
	view.set_expedition_pending(true)
	_check(
		expedition_button.visible
		and not expedition_button.disabled
		and expedition_button.text == tr("EXPEDITION_CONTINUE")
		and team_button.disabled
		and start.disabled,
		"an open run exposes only Continue Expedition from the Battle lobby"
	)
	view.set_expedition_pending(false)
	view.set_team_pending(true)
	_check(
		team_button.visible
		and not team_button.disabled
		and team_button.text == tr("TEAM_CONTINUE")
		and expedition_button.disabled
		and start.disabled,
		"an unfinished Team Battle exposes one explicit continuation entry"
	)
	view.set_team_pending(false)
	view.set_expedition_new(true)
	_check(expedition_badge.visible, "unopened chapter marks the Expedition entry as New")
	view.set_expedition_new(false)
	var anima := {
		"id": "battle-player",
		"nickname": "Velumi",
		"status": "ready",
		"element": "spark",
		"stage": 1,
		"care": {"hunger": 100.0, "energy": 100.0, "hygiene": 100.0, "bond": 50.0},
		"base_stats": {"hp": 60, "atk": 55, "def": 50, "spd": 65, "special": 58},
	}
	view.set_lobby(anima)
	_check(lobby.visible and not content.visible and not result.visible, "Battle opens in its lobby")
	_check(not view.is_duel_arena_open(), "the Battle lobby is not an immersive arena")
	_check(header.visible, "Battle lobby keeps its page title and explanation")
	var resume_requests := [0]
	view.resume_requested.connect(func() -> void: resume_requests[0] += 1)
	view.set_duel_pending(true)
	_check(
		start.text == tr("BATTLE_CONTINUE")
		and lobby_meta.text == tr("BATTLE_PENDING")
		and not start.disabled
		and team_button.disabled
		and expedition_button.disabled,
		"an unfinished Duel waits behind an explicit Continue Battle action"
	)
	start.pressed.emit()
	_check_eq(resume_requests[0], 1, "Continue Battle emits one safe resume request")
	view.set_duel_pending(false)
	_check(
		page_title != null and page_title.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT
		and page_subtitle != null and page_subtitle.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
		"Battle title and subtitle align left like Collection"
	)
	_check(not start.disabled, "ready awake active Anima can start Battle")
	var normal_daily_reward := {
		"earned": 2,
		"limit": 3,
		"remaining": 1,
		"bits_earned": 16,
		"bits_limit": 100,
		"bits_remaining": 84,
		"rewarded": false,
		"server_now": "2026-08-13T23:59:00.000000+00:00",
		"reset_at": "2026-08-14T00:00:00+00:00",
	}
	view.set_daily_reward(normal_daily_reward)
	_check(start.text == tr("BATTLE_START"), "rewarded lobby offers one Battle action")
	var training_daily_reward: Dictionary = normal_daily_reward.duplicate(true)
	training_daily_reward["earned"] = 7
	training_daily_reward["remaining"] = 0
	training_daily_reward["bits_earned"] = 24
	training_daily_reward["bits_remaining"] = 76
	view.set_daily_reward(training_daily_reward)
	_check(
		start.text == tr("BATTLE_TRAIN")
		and lobby_meta.text == tr("BATTLE_LOBBY_TRAINING_BITS") % ["24", "100"],
		"daily win cap changes the single lobby action to Train for Bits"
	)
	var bits_capped_reward: Dictionary = training_daily_reward.duplicate(true)
	bits_capped_reward["bits_earned"] = 100
	bits_capped_reward["bits_remaining"] = 0
	bits_capped_reward["bits_limit"] = 100
	view.set_daily_reward(bits_capped_reward)
	_check(
		start.text == tr("BATTLE_TRAIN")
		and lobby_meta.text == tr("BATTLE_LOBBY_TRAINING") % ["100", "100"],
		"Bits cap explains Training with no remaining Bits"
	)
	_check(
		is_equal_approx(float(view.reward_reset_delay(training_daily_reward)), 60.0),
		"Training status schedules reset from server timestamps"
	)
	view.set_daily_reward(normal_daily_reward)
	anima["sleep_started_at"] = "2026-08-13T00:00:00Z"
	view.set_lobby(anima)
	_check(
		not start.disabled and start.text == tr("BATTLE_CHOOSE_ANIMA"),
		"sleeping Anima offers Choose Anima instead of a dead Battle button"
	)
	anima.erase("sleep_started_at")
	anima["dormant_since"] = "2026-08-13T00:00:00Z"
	view.set_lobby(anima)
	_check(
		not start.disabled and start.text == tr("BATTLE_CHOOSE_ANIMA"),
		"Dormant Anima offers Choose Anima"
	)
	anima.erase("dormant_since")
	anima["care"]["energy"] = 19.0
	view.set_daily_reward(training_daily_reward)
	view.set_lobby(anima)
	_check(
		not start.disabled and start.text == tr("BATTLE_CHOOSE_ANIMA")
		and lobby_name.text == tr("BATTLE_LOBBY_TITLE_LOW_ENERGY")
		and lobby_meta.text == tr("BATTLE_ANIMA_LOW_ENERGY"),
		"Energy below 20 keeps the reason and swaps the CTA to Choose Anima"
	)
	anima["care"]["energy"] = 20.0
	view.set_daily_reward(normal_daily_reward)
	view.set_lobby(anima)
	_check(not start.disabled, "exactly 20 Energy remains eligible for Battle")
	anima["care"]["hunger"] = 39.0
	view.set_lobby(anima)
	_check(
		not start.disabled
		and start.text == tr("BATTLE_START")
		and lobby_meta.text.find(tr("BATTLE_HUNGRY_PENALTY")) >= 0,
		"Hunger below 40 still allows Battle and warns that stats drop"
	)
	anima["care"]["hunger"] = 40.0
	anima["care"]["hygiene"] = 10.0
	view.set_lobby(anima)
	_check(
		not start.disabled
		and start.text == tr("BATTLE_START")
		and lobby_meta.text.find(tr("BATTLE_DIRTY_PENALTY")) >= 0,
		"low Hygiene still allows Battle and warns that stats drop"
	)
	anima["care"]["hygiene"] = 80.0
	view.set_lobby(anima)
	_check(not start.disabled, "Hunger 40 remains eligible for Battle")

	view.set_loading("BATTLE_CONNECTING")
	_check(
		lobby.visible and not start.visible,
		"Battle start hides the lobby CTA while connecting"
	)
	view.set_error("BATTLE_ERROR_GENERIC")
	_check(
		lobby.visible and not start.visible
		and lobby_name.text == tr("BATTLE_ERROR_TITLE"),
		"a failed start surfaces the error without leaving the lobby"
	)
	view.set_busy(false)
	_check(
		lobby.visible and start.visible and not start.disabled,
		"set_busy(false) restores the Battle Start button after a failed connect"
	)

	view.set_loading("BATTLE_RESUMING")
	_check(lobby.visible and start.disabled, "Battle resume exposes a locked loading state")

	var placeholder := PlaceholderSheet.build()
	var texture := ImageTexture.create_from_image(placeholder["image"])
	var loaded := AnimaLoader.build(texture, placeholder["manifest"])
	var session := {
		"id": "battle-session",
		"status": "active",
		"turn_number": 1,
		"version": 0,
		"player_snapshot": {
			"id": "battle-player", "name": "Velumi", "element": "spark", "stage": 1,
			"strike_name": "D-Pad Jab", "surge_name": "Pocket Beam",
		},
		"bot_snapshot": {
			"name": "Unknown Anima", "element": "flow", "stage": 1,
		},
		"daily_reward": {
			"earned": 2, "limit": 3, "remaining": 1, "rewarded": false,
			"bits_earned": 16, "bits_limit": 100, "bits_remaining": 84,
			"server_now": "2026-08-13T23:59:00.000000+00:00",
			"reset_at": "2026-08-14T00:00:00+00:00",
		},
		"state": {
			"player": {"hp": 220, "max_hp": 220, "momentum": 3, "spd": 20},
			"bot": {"hp": 205, "max_hp": 205, "momentum": 3, "spd": 45},
		},
	}
	view.set_session(session, loaded, loaded)
	await process_frame
	session["item_used_id"] = null
	view.set_session(session, loaded, loaded)
	_item_picker_opens = false
	view.item_picker_requested.connect(func() -> void: _item_picker_opens = true)
	view.call("_request_item")
	_check(not item.disabled, "unused Item stays enabled")
	_check(_item_picker_opens, "unused Item opens the battle picker")
	session["item_used_id"] = "power_chip"
	view.set_session(session, loaded, loaded)
	_item_picker_opens = false
	view.call("_request_item")
	_check(
		not item.disabled and _item_picker_opens,
		"item stays reusable every turn; a past item_used_id no longer blocks it"
	)
	session.erase("item_used_id")
	view.set_session(session, loaded, loaded)
	_check(
		player_sprite.sprite_frames.has_animation("fx_strike")
		and player_sprite.sprite_frames.has_animation("fx_surge"),
		"sheet Battle harus membawa sel VFX strike dan surge"
	)
	player_sprite.set_pose("attack")
	player_sprite.play_fx("fx_strike")
	var strike_fx := player_sprite.get("_fx") as Sprite2D
	_check(
		player_sprite.current_pose() == "attack"
		and strike_fx != null
		and strike_fx.visible
		and strike_fx.texture != null
		and strike_fx.get_parent() == player_anchor,
		"Attack menampilkan pose Battle plus overlay fx_strike"
	)
	var strike_tex := strike_fx.texture
	player_sprite.play_fx("fx_surge")
	_check(
		player_sprite.current_pose() == "attack"
		and strike_fx.visible
		and strike_fx.texture != strike_tex
		and strike_fx.get_parent() == player_anchor,
		"Special menampilkan pose Battle plus overlay fx_surge yang berbeda"
	)
	player_sprite.set_pose(AnimaLoader.DEFAULT_POSE)
	var active_arena_height := arena.size.y
	var active_ground_y := player_anchor.position.y
	_check(content.visible and not lobby.visible and not result.visible, "active turn replaces the lobby")
	var arena_panel := view.find_child("ArenaPanel", true, false) as PanelContainer
	var arena_background := view.find_child("BattleArenaBackground", true, false) as TextureRect
	var dock_fill := view.find_child("DockFill", true, false) as Panel
	_check(
		arena_panel != null
		and arena_panel.get_theme_stylebox("panel") is StyleBoxEmpty,
		"Duel arena drops the modal frame so it can take Expedition zone art"
	)
	_check(arena_background != null, "Duel stage has an Expedition-style background slot")
	var duel_material := arena_background.material as ShaderMaterial
	var daylight := load("res://scripts/local_daylight.gd") as GDScript
	_check(
		arena_background != null
		and arena_background.visible
		and arena_background.texture == load(
			"res://assets/backgrounds/duel_background.png"
		)
		and duel_material.get_shader_parameter("day_texture") == load(
			"res://assets/backgrounds/duel_day_background.png"
		)
		and is_equal_approx(
			float(duel_material.get_shader_parameter("daylight_blend")),
			daylight.daylight_blend()
		)
		and arena_background.size.x >= arena.size.x
		and arena_background.size.y >= arena.size.y,
		"Duel smoothly blends local daylight while cover-cropping without gaps"
	)
	_check(
		is_equal_approx(
			arena_background.position.y,
			-(arena_background.size.y - arena.size.y)
			* BattleScale.STATIC_BACKGROUND_VERTICAL_PAN
		),
		"Duel static art uses the shared lowered framing without moving its ground line"
	)
	_check(dock_fill != null, "Duel footer wears the Expedition dock plate")
	_check(surge.theme_type_variation == &"", "Duel Special is not a PrimaryButton so the four actions match")
	_check(
		player_anchor.get_node_or_null("GroundShadow") != null,
		"Duel fighters get the same ground shadow as Expedition"
	)
	_check(view.is_duel_arena_open(), "an active Duel session is an immersive arena")
	_check(
		not header.visible
		and arena.is_ancestor_of(forfeit)
		and forfeit.flat
		and forfeit.custom_minimum_size.y >= TOUCH_MIN,
		"active Battle uses a quiet Forfeit action with a full touch target inside its HUD"
	)
	var duel_actions := view.find_child("Actions", true, false) as GridContainer
	_check(
		not feedback.visible
		and is_equal_approx(footer.custom_minimum_size.y, 216.0)
		and duel_actions != null
		and duel_actions.columns == 2
		and duel_actions.get_child_count() == 4,
		"Battle command footer uses a readable 2x2 action grid without idle copy"
	)
	_check(player_sprite.flip_h and not bot_sprite.flip_h, "Battle fighters face each other")
	_check(
		is_equal_approx(
			active_ground_y,
			active_arena_height * BATTLE_SCALE.GROUND_Y_RATIO
		),
		"Duel fighters plant their opaque feet on the shared BattleScale ground line"
	)

	# Figur Seeker pemain di Duel: cermin Team Battle di arena 2×2. Dicari
	# terbatas pada layer Duel, bukan rekursif dari view — scene ini juga
	# meng-embed TeamBattleView dan ExpeditionView yang punya node senama.
	var bot_anchor := view.find_child("BattleBotAnchor", true, false) as Node2D
	var duel_layer := arena.find_child("DuelFighterLayer", false, false) as Node2D
	view.set_player_avatar(_boss_seeker_loaded())
	await process_frame
	var duel_avatar := duel_layer.find_child("PlayerSeeker", false, false) as AnimatedSprite2D
	var duel_avatar_shadow := duel_layer.find_child(
		"PlayerSeekerShadow", false, false
	) as Sprite2D
	_check(
		duel_avatar != null and duel_avatar.visible and duel_avatar.sprite_frames != null
		and duel_avatar.flip_h
		and duel_avatar_shadow != null and duel_avatar_shadow.visible,
		"the player's Seeker Avatar stands in the Duel arena facing the bot"
	)
	_check(
		bot_anchor != null
		and is_equal_approx(duel_avatar.position.y, active_ground_y)
		and is_equal_approx(duel_avatar.position.y, bot_anchor.position.y),
		"the Duel figure shares the one ground line both fighters stand on"
	)
	# Ambangnya milik `BattleScale.anima_behind_seeker()` dan sudah dijaga
	# `test_game_rules`; yang diperiksa di sini wiring-nya. 120 cm bawaan sudah
	# melewati 60% dari 165 cm, jadi figurnya melangkah ke depan Anima-nya
	# sendiri alih-alih kehilangan siluetnya di belakang, dan bayangannya ikut
	# pindah lane bersamanya.
	_check(
		duel_avatar.z_index > player_sprite.z_index
		and duel_avatar.z_index > bot_sprite.z_index
		and duel_avatar_shadow.z_index == duel_avatar.z_index
		and duel_layer.get_index() < fighter_hud_plate.get_index(),
		"the Duel figure steps in front of an Anima as tall as itself, still under the HUD plate"
	)
	# Anima cebol tidak menutupi siapa pun, jadi figurnya kembali ke belakang:
	# lane-nya ikut tinggi petarung, bukan dipatok sekali saat figur dipasang.
	session["player_snapshot"]["body_height_cm"] = 25
	view.set_session(session, loaded, loaded)
	await process_frame
	_check(
		duel_avatar.z_index < player_sprite.z_index
		and duel_avatar_shadow.z_index == duel_avatar.z_index,
		"the Duel figure drops behind a knee-high Anima"
	)
	session["player_snapshot"].erase("body_height_cm")
	view.set_session(session, loaded, loaded)
	await process_frame
	# Satu figur, bukan dua: bot Duel tidak punya Seeker, dan pemeriksaannya
	# menghitung presenter alih-alih menebak nama node yang belum ada.
	var duel_seeker_count := 0
	for child in duel_layer.get_children():
		if child is SeekerPresenter:
			duel_seeker_count += 1
	_check(duel_seeker_count == 1, "the Duel bot never gets a Seeker figure of its own")
	# Struktural, jadi ia berlaku di portrait maupun landscape: figur hidup di
	# dalam arena yang meng-clip isinya, dan arena digambar sebelum footer.
	_check(
		arena.clip_contents
		and arena.get_parent().get_index() < footer.get_index()
		and arena.is_ancestor_of(duel_avatar),
		"the Duel figure can never cover the action dock, at any aspect"
	)
	_check(
		is_equal_approx(BATTLE_SCALE.STATIC_BACKGROUND_VERTICAL_PAN, 0.5)
		and is_equal_approx(
			float(view.get_script().get_script_constant_map().get("DUEL_BACKGROUND_MAX_SCALE", 0.0)),
			1.0
		),
		"static Duel background preserves expanded sky without camera crop"
	)
	_check(
		result.get_parent() == footer and result.z_index > player_anchor.z_index,
		"Battle result overlays the fixed footer above both fighters"
	)
	_check_eq(player_hp.value, 220.0, "Battle HUD displays authoritative HP")
	var battle_script_resource := view.get_script() as GDScript
	var battle_constants := battle_script_resource.get_script_constant_map()
	var hp_full_color: Color = battle_constants.get("HP_FULL_COLOR", Color.CYAN)
	var hp_warning_color: Color = battle_constants.get("HP_WARNING_COLOR", Color.ORANGE)
	var hp_empty_color: Color = battle_constants.get("HP_EMPTY_COLOR", Color.RED)
	var full_hp_fill := player_hp.get_theme_stylebox("fill") as StyleBoxFlat
	_check(
		full_hp_fill != null and full_hp_fill.bg_color.is_equal_approx(hp_full_color),
		"full HP uses the blue Battle state"
	)
	battle_script_resource.call("apply_hp_bar_state", player_hp, 110.0, 220.0)
	var half_hp_fill := player_hp.get_theme_stylebox("fill") as StyleBoxFlat
	_check(
		half_hp_fill != null and half_hp_fill.bg_color.is_equal_approx(hp_warning_color),
		"HP changes directly to orange at 50 percent"
	)
	battle_script_resource.call("apply_hp_bar_state", player_hp, 44.0, 220.0)
	var critical_hp_fill := player_hp.get_theme_stylebox("fill") as StyleBoxFlat
	_check(
		critical_hp_fill != null and critical_hp_fill.bg_color.is_equal_approx(hp_empty_color),
		"HP changes directly to red at 20 percent"
	)
	battle_script_resource.call("apply_hp_bar_state", player_hp, 0.0, 220.0)
	var empty_hp_fill := player_hp.get_theme_stylebox("fill") as StyleBoxFlat
	_check(
		empty_hp_fill != null and empty_hp_fill.bg_color.is_equal_approx(hp_empty_color),
		"empty HP remains red"
	)
	battle_script_resource.call("apply_hp_bar_state", player_hp, 220.0, 220.0)
	_check(
		player_hp_value.text == "220 / 220"
		and bot_hp_value.text == "205 / 205"
		and player_hp_value.get_parent() == player_hp.get_parent()
		and bot_hp_value.get_parent() == bot_hp.get_parent(),
		"Duel overlays exact HP inside each bar like Team Battle and Expedition"
	)
	_check(
		not turn.visible
		and not daily_reward.visible
		and not player_element.visible
		and not bot_element.visible
		and view.find_child("TurnSpacer", true, false) != null,
		"Duel keeps the action arena free of reward counters and element labels"
	)
	var element_icons_left := 0
	for file in DirAccess.get_files_at("res://assets/icons"):
		if file.begins_with("element-"):
			element_icons_left += 1
	_check(
		element_icons_left == 0
		and view.find_child("BattlePlayerElementIcon", true, false) == null
		and view.find_child("BattleBotElementIcon", true, false) == null,
		"elements stay label-only: no element icon node and no element icon asset"
	)
	_check(
		view.find_child("PlayerCard", true, false) == null
		and view.find_child("BotCard", true, false) == null,
		"fighter HUD is one versus strip without separate bordered cards"
	)
	_check(
		player_hp.fill_mode == ProgressBar.FILL_END_TO_BEGIN
		and bot_hp.fill_mode == ProgressBar.FILL_BEGIN_TO_END,
		"both HP meters drain from the outer screen edge inward like a fighting game"
	)
	view.call("_show_effectiveness", 1.5)
	_check(
		effectiveness.visible and effectiveness_label.text == tr("BATTLE_EFFECTIVE"),
		"advantaged attacks show a Super effective indicator"
	)
	view.show_retreat_banner()
	_check(
		effectiveness.visible and effectiveness_label.text == tr("BATTLE_RETREATING"),
		"Retreat processing uses the same arena event plate as Super effective"
	)
	view.set_loading("BATTLE_RESUMING")
	_check(not effectiveness.visible, "set_loading clears a stale retreat banner")
	view.show_retreat_banner()
	view.set_session(session, loaded, loaded)
	_check(not effectiveness.visible, "set_session clears a stale retreat banner")
	view.show_retreat_banner()
	view.set_lobby(anima)
	_check(not effectiveness.visible, "set_lobby clears a stale retreat banner")
	view.set_session(session, loaded, loaded)
	_check(
		effectiveness.offset_left >= 15.0
		and effectiveness.offset_right <= -15.0,
		"Duel event copy keeps a full-width band below the HUD"
	)
	_check(
		event_plate != null
		and event_plate.clip_contents
		and event_plate.theme_type_variation == &"BattleEventPlate"
		and effectiveness_label.get_parent() == event_plate
		and effectiveness_label.autowrap_mode != TextServer.AUTOWRAP_OFF
		and effectiveness_label.max_lines_visible == 2,
		"Duel event copy stays inside a clipped wrapping plate"
	)
	_check(
		float(view.get_script().get_script_constant_map().get("ACTION_CUE_SEC", 0.0)) >= 1.4
		and effectiveness_label.get_theme_font("font") is FontVariation
		and effectiveness_label.get_theme_font_size("font_size") >= 32,
		"Duel event plate keeps its readability hold after the Attack pose appears"
	)
	_check(
		str(view.call("_actor_name", "player")) == "Velumi"
		and not str(view.call("_actor_name", "player")).contains(tr("LEVEL_SHORT")),
		"Duel event plate names omit Level"
	)
	view.call("_show_effectiveness", 0.67)
	_check(
		effectiveness.visible and effectiveness_label.text == tr("BATTLE_NOT_EFFECTIVE"),
		"resisted attacks show a Not very effective indicator"
	)
	view.call("_show_effectiveness", 1.0)
	_check(not effectiveness.visible, "neutral attacks do not show a misleading indicator")
	var battle_source := FileAccess.get_file_as_string("res://scripts/battle_view.gd")
	var duel_attack_fn := battle_source.substr(battle_source.find("func _play_attack"), 4200)
	_check(
		duel_attack_fn.find("_present_banner") >= 0
		and duel_attack_fn.find("_present_banner")
		< duel_attack_fn.find("await _hide_effectiveness()")
		and duel_attack_fn.find("await _hide_effectiveness()")
		< duel_attack_fn.find("attacker.set_pose(\"attack\")")
		and duel_attack_fn.find("attacker.set_pose(\"attack\")")
		< duel_attack_fn.find("attacker.play_fx"),
		"Duel hides action copy before Attack pose and VFX"
	)
	_check(
		duel_attack_fn.find("await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)") >= 0
		and duel_attack_fn.find("await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)")
		< duel_attack_fn.find("attacker.set_pose(\"idle\")")
		and duel_attack_fn.find("attacker.set_pose(\"idle\")")
		< duel_attack_fn.find("if not effect_key.is_empty()"),
		"Duel Attack returns to Idle on impact before effectiveness copy"
	)
	_check(
		battle_source.find("func item_banner_text") >= 0
		and battle_source.find("care_feedback(\"item\")") >= 0
		and battle_source.find("_present_banner(item_banner_text(event)") >= 0
		and battle_source.find("func _present_banner") >= 0,
		"Item banners name the effect and shine the Anima"
	)
	var guard_copy := battle_source.find("BATTLE_EVENT_GUARD")
	var initiative_at := battle_source.find("func _announce_initiative")
	var initiative_present := battle_source.find("_present_banner", initiative_at)
	var initiative_hide := battle_source.find("_hide_effectiveness", initiative_present)
	_check(
		guard_copy >= 0
		and battle_source.find("_hide_effectiveness", guard_copy) > guard_copy
		and initiative_present > initiative_at
		and initiative_hide > initiative_present
		and initiative_hide < battle_source.find("func _apply_state"),
		"Guard and initiative hold the plate before hiding it"
	)
	var duel_ko := battle_source.substr(
		battle_source.find("\"knockout\":", battle_source.find("func play_events")), 420
	)
	_check(
		duel_ko.find("set_pose(\"defeated\")") >= 0
		and duel_ko.find("set_pose(\"defeated\")") < duel_ko.find("_present_banner"),
		"Duel faint pose lands with the knockout plate"
	)
	_check(
		battle_source.find("bracing.guard_shimmer()") >= 0
		and battle_source.find("bracing.guard_shimmer()") < guard_copy,
		"Duel shimmers the bracing body on the frame the Guard plate appears"
	)
	_check(
		battle_source.find("_effectiveness.pivot_offset") >= 0
		and battle_source.find("_effectiveness_badge") < 0,
		"Duel banner scales from the band center without tilting the plate"
	)
	view.call("_show_banner", "Attack +35%!", Color(1.0, 0.82, 0.4, 1.0), true)
	_check(
		effectiveness.visible and effectiveness_label.text == "Attack +35%!",
		"using an item reuses the Super effective banner for its effect"
	)
	_check_eq(strike.text, "D-Pad Jab", "Attack button uses the generated move name")
	_check(
		surge.text == tr("BATTLE_ACTION_SURGE_COST") % ["Pocket Beam", "3", "3"],
		"Special button shows the generated name plus PP"
	)
	_check(
		not daily_reward.visible,
		"active Duel keeps daily caps out of the turn-by-turn arena"
	)
	_check(
		view.find_child("BattleMomentum", true, false) == null,
		"no redundant PP label survives outside the Special button"
	)
	_check(
		not strike.disabled and not surge.disabled and not guard.disabled and item != null and not item.disabled,
		"active turn unlocks four actions"
	)
	player_sprite.set_pose("attack")
	bot_sprite.set_pose("attack")
	var bot_impact := bot_sprite.to_global(bot_sprite.offset)
	player_sprite.play_fx("fx_strike", bot_impact)
	var travel_fx := player_sprite.get("_fx") as Sprite2D
	var strike_impact := player_anchor.to_local(bot_impact)
	_check(
		travel_fx != null
		and travel_fx.position.distance_to(player_sprite.position)
			< travel_fx.position.distance_to(strike_impact),
		"VFX starts at the attacker before traveling into the opponent"
	)
	await create_timer(0.24).timeout
	_check(player_sprite.position.x > 0.0, "player attack lunges toward the right-side rival")
	_check(bot_sprite.position.x < 0.0, "rival attack lunges toward the left-side player")
	await create_timer(AnimaPresenter.FX_TRAVEL_SEC - 0.20).timeout
	_check(
		is_instance_valid(travel_fx)
		and travel_fx.position.distance_to(strike_impact) < 24.0,
		"VFX Attack/Special masuk ke tubuh lawan"
	)
	player_sprite.set_pose("idle")
	bot_sprite.set_pose("idle")

	view.set_loading("BATTLE_RESUMING")
	_check(
		not lobby.visible and content.visible and not feedback.visible,
		"active Battle retry keeps one arena state instead of overlapping the lobby"
	)
	view.set_error("AUTH_EXPIRED")
	_check(
		not lobby.visible and content.visible and result.visible,
		"expired auth shows one recoverable Battle overlay"
	)
	view.set_session(session, loaded, loaded)

	session["state"]["player"]["momentum"] = 1
	view.set_session(session, loaded, loaded)
	_check(not surge.disabled, "one PP is still enough for one Special")
	_check(
		surge.text == tr("BATTLE_ACTION_SURGE_COST") % ["Pocket Beam", "1", "3"],
		"Special button counter follows the authoritative PP"
	)
	session["state"]["player"]["momentum"] = 0
	view.set_session(session, loaded, loaded)
	_check(surge.disabled, "Special is disabled once PP runs out")
	_check(
		feedback.text != tr("BATTLE_NO_MOMENTUM"),
		"empty PP no longer prints a Guard hint in the dock"
	)
	var training_active: Dictionary = session.duplicate(true)
	training_active["state"]["player"]["momentum"] = 1
	training_active["daily_reward"] = training_daily_reward.duplicate(true)
	view.set_session(training_active, loaded, loaded)
	_check(
		not feedback.visible and not daily_reward.visible,
		"Training also keeps daily counters outside the action arena"
	)
	view.begin_action("strike")
	_check(
		not strike.disabled and not surge.disabled and not guard.disabled and not item.disabled
		and strike.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and surge.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and guard.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and item.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"pending turn blocks repeat input without making every action look disabled"
	)
	_check(
		strike_commit.visible and not surge_commit.visible and not guard_commit.visible
		and not item_commit.visible
		and not feedback.visible
		and surge.self_modulate.a < strike.self_modulate.a,
		"selected Battle action locks on the button without Resolving copy"
	)

	# Pose sisi pemain hidup di tengah `play_events()` lalu kembali idle, jadi
	# nilai akhirnya saja tidak membuktikan apa pun. Kolektor jalan berdampingan.
	var duel_avatar_poses := {}
	_collect_poses(duel_avatar, duel_avatar_poses)
	await view.play_events([
		{
			"type": "attack", "actor": "player", "target": "bot", "action": "strike",
			"damage": 12, "target_hp": 193, "element_multiplier": 1.0,
		},
		{
			"type": "attack", "actor": "player", "target": "bot", "action": "surge",
			"damage": 18, "target_hp": 175, "element_multiplier": 1.0,
		},
		{
			"type": "attack", "actor": "bot", "target": "player", "action": "strike",
			"damage": 15, "target_hp": 205, "element_multiplier": 1.0,
		},
	], session)
	duel_avatar_poses["stop"] = true
	_check(
		duel_avatar_poses.has("attack_command")
		and duel_avatar_poses.has("special_command")
		and duel_avatar_poses.has("concern_hit"),
		"the Duel figure commands its own Attack and Special, and worries when hit"
	)
	_check(
		duel_avatar.animation == "intro_idle",
		"an unfinished Duel leaves the player figure calm between turns"
	)

	var won: Dictionary = session.duplicate(true)
	won["status"] = "won"
	won["state"]["bot"]["hp"] = 0
	won["daily_reward"] = {
		"earned": 3, "limit": 3, "remaining": 0, "rewarded": true,
		"bits_earned": 24, "bits_limit": 100, "bits_remaining": 76,
	}
	won["last_reward"] = {"bits": 8, "care_score": 4, "battle_wins": 1}
	await view.play_events([
		{
			"type": "attack", "actor": "player", "target": "bot", "action": "strike",
			"damage": 205, "target_hp": 0, "critical": false, "element": 1.0,
		},
		{"type": "knockout", "actor": "bot"},
		{"type": "finished", "result": "won"},
	], won)
	await process_frame
	_check(result.visible and content.visible, "win event log reveals the result panel")
	_check(
		player_sprite.current_pose() == "happy",
		"menang Battle memakai pose Happy"
	)
	_check(
		duel_avatar.animation == "victory",
		"a won Duel leaves the player figure celebrating"
	)
	_check(
		battle_source.find("_player_sprite.victory_celebration(_companion_level())") >= 0,
		"Duel win hands the player sprite a celebration sized to its evolution stage"
	)
	var victory_hop := player_sprite.get("_feedback") as Tween
	_check(
		victory_hop != null and victory_hop.get_loops_left() == -1,
		"Hatchling win keeps bouncing until the next pose"
	)
	_check(result.size.y >= 236.0, "Battle result grows upward and stays clear of bottom navigation")
	_check(
		bot_hp_value.text == "0 / 205",
		"terminal Battle HUD keeps the exact defeated HP visible"
	)
	_check(
		not daily_reward.visible
		and result_title.text == tr("BATTLE_WIN_TITLE")
		and result_body.text == tr("BATTLE_WIN_BODY") % ["8", "Velumi", "4"],
		"rewarded Duel names the Anima that received EXP"
	)
	var leave := view.find_child("BattleLeaveButton", true, false) as Button
	var exits := [0]
	view.exit_requested.connect(func() -> void: exits[0] += 1)
	_check(
		leave != null and leave.visible
		and tr(leave.text) == tr("BATTLE_RETURN_LOBBY")
		and view.can_leave_result(),
		"terminal Duel offers an explicit way out of its result"
	)
	leave.pressed.emit()
	_check(exits[0] == 1, "Duel leave button asks the shell to close the session")
	_check(
		retry.text == tr("BATTLE_AGAIN") and result_body.text.find("\n") < 0,
		"a rested companion keeps the plain rematch CTA"
	)
	var spent: Dictionary = anima.duplicate(true)
	spent["care"]["energy"] = CareRules.BATTLE_ENERGY_COST - 1.0
	view.set_companion(spent)
	var low_energy_line := tr("BATTLE_RESULT_BLOCKED") % tr("BATTLE_PICK_LOW_ENERGY")
	_check(
		retry.text == tr("BATTLE_CHOOSE_ANIMA")
		and result_body.text == tr("BATTLE_WIN_BODY") % ["8", "Velumi", "4"]
			+ "\n" + low_energy_line
		and low_energy_line.length() < 40,
		"a drained companion swaps the rematch CTA for Choose Anima plus one short reason"
	)
	var picks := [0]
	var resumes_before: int = resume_requests[0]
	view.choose_anima_requested.connect(func() -> void: picks[0] += 1)
	retry.pressed.emit()
	_check(
		picks[0] == 1 and resume_requests[0] == resumes_before,
		"the blocked CTA opens the picker instead of a rematch the server would refuse"
	)
	view.set_companion(anima)
	_check(
		retry.text == tr("BATTLE_AGAIN"),
		"feeding the companion restores the rematch CTA without leaving the result"
	)
	retry.pressed.emit()
	_check(
		picks[0] == 1 and resume_requests[0] == resumes_before + 1,
		"an eligible CTA still starts a rematch"
	)

	var ready_again: Dictionary = anima.duplicate(true)
	ready_again.erase("dormant_since")
	view.set_lobby(ready_again)
	_check(
		start.text == tr("BATTLE_TRAIN"),
		"returning after the third reward immediately offers Training"
	)
	_check(
		not view.can_leave_result(),
		"the lobby has nothing to leave, so Android back stays with the shell"
	)
	view.set_session(won, loaded, loaded)
	_check_eq(arena.size.y, active_arena_height, "result overlay must not resize the arena")
	_check_eq(
		player_anchor.position.y,
		active_ground_y,
		"result overlay must not move the fighters"
	)

	var training_win: Dictionary = won.duplicate(true)
	training_win["daily_reward"] = training_daily_reward.duplicate(true)
	training_win["daily_reward"]["bits_earned"] = 32
	training_win["daily_reward"]["bits_remaining"] = 68
	training_win["last_reward"] = {"bits": 8, "care_score": 0, "battle_wins": 0}
	view.set_session(training_win, loaded, loaded)
	_check(
		not daily_reward.visible
		and result_title.text == tr("BATTLE_TRAINING_TITLE")
		and result_body.text == tr("BATTLE_TRAINING_BITS_BODY") % "8"
		and retry.text == tr("BATTLE_TRAIN_AGAIN"),
		"Training wins explain earned Bits in the result without arena counters"
	)

	var lost: Dictionary = session.duplicate(true)
	lost["status"] = "lost"
	lost["state"]["player"]["hp"] = 0
	view.set_session(lost, loaded, loaded)
	_check(result.visible, "loss session restores its terminal result")
	_check(
		duel_avatar.animation == "defeat",
		"a lost Duel leaves the player figure defeated"
	)
	view.set_error("BATTLE_EXPIRED")
	_check(
		result.visible and content.visible and not lobby.visible,
		"resume failure keeps one recoverable result overlay"
	)

	view.queue_free()
	await process_frame
	# Portrait dan landscape keduanya: dock Duel dan arena-nya berubah bentuk di
	# antara keduanya, jadi "dock tidak bergeser" hanya terbukti kalau figurnya
	# ikut diperiksa pada kedua aspect.
	for duel_viewport_size in [Vector2i(720, 1602), Vector2i(1600, 900)]:
		await _test_duel_seeker_avatar_layout(packed, loaded, session, duel_viewport_size)


## Arena Duel di dalam `root` headless melapor lebar 0, jadi jepit tepi kamera
## dan pergeseran dock tidak bisa dibuktikan di sana — angka pad-nya akan selalu
## nol. Geometri karena itu diperiksa pada viewport sungguhan, prosedur yang sama
## seperti bug layout lain di shell ini.
func _test_duel_seeker_avatar_layout(
	packed: PackedScene,
	loaded: Dictionary,
	session: Dictionary,
	viewport_size: Vector2i
) -> void:
	var host := SubViewport.new()
	host.size = viewport_size
	root.add_child(host)
	var view := packed.instantiate()
	host.add_child(view)
	view.visible = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_session(session, loaded, loaded)
	await process_frame
	var arena := view.find_child("BattleArena", true, false) as Control
	var layer := arena.find_child("DuelFighterLayer", false, false) as Node2D
	var player_anchor := view.find_child("BattlePlayerAnchor", true, false) as Node2D
	var actions := view.find_child("Actions", true, false) as GridContainer
	var hud_plate := view.find_child("FighterHudPlate", true, false) as Control
	var footer := view.find_child("BattleFooter", true, false) as Control
	_check(
		arena.size.x > 0.0,
		"the Duel arena has a real camera viewport to pin against at %s" % viewport_size
	)
	var anima_screen_before := layer.position.x + player_anchor.position.x * layer.scale.x
	var dock_height := footer.size.y
	var dock_position := actions.global_position
	var hud_position := hud_plate.global_position
	var avatar_loaded := _boss_seeker_loaded()
	view.set_player_avatar(avatar_loaded)
	await process_frame
	var avatar := layer.find_child("PlayerSeeker", false, false) as AnimatedSprite2D
	# Kamera memang membingkai ulang saat figur datang — kolomnya ikut menentukan
	# bingkai, dan tanpa itu figur mendarat di atas Anima. Yang tidak boleh
	# bergerak adalah chrome-nya: dock 2×2 dan pelat HUD di luar arena.
	_check(
		is_equal_approx(footer.size.y, dock_height)
		and actions.global_position.is_equal_approx(dock_position)
		and hud_plate.global_position.is_equal_approx(hud_position),
		"the Duel figure never moves the 2x2 dock or the HUD plate at %s" % viewport_size
	)
	# Kolomnya dicadangkan di sisi kiri, jadi pusat bingkai bergeser ke kanan:
	# Anima yang minggir memberi tempat, bukan komposisi shot-nya yang dipindah
	# (anchor-nya tetap di `PLAYER_SHOT_X`).
	_check(
		layer.position.x + player_anchor.position.x * layer.scale.x > anima_screen_before,
		"reserving the figure's column slides the Duel frame away from it at %s"
			% viewport_size
	)
	# Dihitung ulang di sini alih-alih dibaca dari view: kalau rumus jepitnya
	# bergeser, angka yang diharapkan tidak ikut bergeser diam-diam.
	var avatar_width := BattleScale.seeker_reference_width(avatar_loaded)
	var avatar_body := BattleScale.seeker_opaque_center(avatar_loaded)
	# `flip_h` mencerminkan sel terhadap origin, jadi pusat badan pindah tanda.
	var avatar_center_x := layer.position.x + (
		avatar.position.x - avatar_body * absf(avatar.scale.x)
	) * layer.scale.x
	var avatar_screen_w := avatar_width * absf(avatar.scale.x) * layer.scale.x
	var pad := arena.size.x * BattleScale.SEEKER_CAMERA_EDGE_PAD_RATIO
	_check(
		pad > 1.0
		and avatar_width > 1.0
		and absf(avatar_center_x - (pad + avatar_screen_w * 0.5)) < 1.0,
		"the Duel figure pins to its own screen edge after the camera zooms, at %s"
			% viewport_size
	)
	_check(
		avatar_center_x < arena.size.x * 0.5
		and player_anchor.position.x < arena.size.x * 0.5,
		"the Duel figure shares the player Anima's half of the screen at %s" % viewport_size
	)
	# Inti keluhannya: badan figur dan badan Anima tidak boleh saling menembus
	# lebih dari sedikit. Diukur di ruang layer pada sisi yang berhadapan saja —
	# tepi kiri Anima terhadap tepi kanan figur. `SEEKER_COLUMN_GAP_SCALE` (0,75)
	# sengaja mencadangkan kolom yang lebih sempit dari kebutuhan udara penuh
	# supaya figur dan Anima terasa dekat; overlap yang tersisa ditanggung
	# z-order `player_seeker_z()` dan dipagari di sini supaya tidak melebar diam-
	# diam kalau formulanya berubah. Hanya bisa dibuktikan di viewport sungguhan:
	# di `root` headless arena melapor lebar 0 dan setiap pad jadi nol.
	var player_sprite := view.find_child("BattlePlayerSprite", true, false) as AnimaPresenter
	var player_screen_left := layer.position.x + (
		player_anchor.position.x
		- player_sprite.opaque_local_rect().size.x * absf(player_anchor.scale.x) * 0.5
	) * layer.scale.x
	var max_overlap := avatar_screen_w * 0.2
	_check(
		player_screen_left - (avatar_center_x + avatar_screen_w * 0.5) >= -max_overlap,
		"the Duel Anima and figure never overlap more than a fifth of the figure's width at %s"
			% viewport_size
	)
	host.queue_free()
	await process_frame


func _test_team_battle_view() -> void:
	var packed := load("res://scenes/ui/team_battle_view.tscn") as PackedScene
	var view := packed.instantiate()
	root.add_child(view)
	await process_frame
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var resume_start := flow_source.find("func _resume_team_battle")
	var resume_end := flow_source.find("\n\nfunc _retry_team_battle", resume_start)
	var resume_body := flow_source.substr(
		resume_start, resume_end - resume_start
	) if resume_start >= 0 and resume_end > resume_start else ""
	var hub_start := flow_source.find("func _load_team_battle_hub")
	var hub_end := flow_source.find("\n\nfunc _save_team_battle_roster", hub_start)
	var hub_body := flow_source.substr(
		hub_start, hub_end - hub_start
	) if hub_start >= 0 and hub_end > hub_start else ""
	_check(
		resume_body.find('res.error in ["TEAM_BATTLE_NOT_FOUND", "INVALID_SESSION_ID"]') >= 0
		and resume_body.find("GameState.finish_team_battle()") >= 0
		and flow_source.find("if _busy or _team_battle_demo_active:") >= 0
		and flow_source.find("_team_battle_demo_active = true") >= 0,
		"invalid or demo Team Battle sessions cannot trap the persisted hub state"
	)
	_check(
		hub_body.find("set_builder(_roster, _team_battle_team)") >= 0
		and hub_body.find("_refresh_team_battle_candidates") < 0,
		"Team Battle always reviews the saved roster before requesting rivals"
	)
	var retry_body := _func_body(flow_source, "func _retry_team_battle(")
	var candidates_body := _func_body(flow_source, "func _refresh_team_battle_candidates(")
	_check(
		retry_body.find("set_builder(_roster, _team_battle_team)") >= 0
		and retry_body.find("_load_team_battle_hub") < 0
		and candidates_body.find("set_builder(_roster, _team_battle_team)") >= 0,
		"Next Battle, Try Again, and empty-team recovery reopen one ordered Team builder",
	)
	var back := view.find_child("TeamBackButton", true, false) as Button
	var back_icon := view.find_child("TeamBackIcon", true, false) as TextureRect
	_check(
		back.flat and back.text.is_empty() and back_icon.texture != null
		and back_icon.position.y < 16.0,
		"Team Battle header uses a compact chevron Back control"
	)
	var roster: Array[Dictionary] = []
	var members: Array[Dictionary] = []
	var player_state: Array[Dictionary] = []
	var opponent_state: Array[Dictionary] = []
	var player_snapshots: Array[Dictionary] = []
	var opponent_snapshots: Array[Dictionary] = []
	var placeholder := PlaceholderSheet.build()
	var thumbnail := ImageTexture.create_from_image(placeholder["image"])
	var loaded := AnimaLoader.build(thumbnail, placeholder["manifest"])
	view.set_thumbnail_provider(func(_row: Dictionary) -> Texture2D: return thumbnail)
	var art_cache := {}
	for index in 4:
		var anima_id := "00000000-0000-4000-8000-00000000000%d" % index
		var row := {
			"id": anima_id,
			"nickname": "Team %d" % (index + 1),
			"status": "ready",
			"element": "metal",
			"care": {"energy": 80.0, "hunger": 80.0, "hygiene": 80.0},
			"care_score": index,
		}
		roster.append(row)
		members.append({"slot": index, "anima_id": anima_id, "nickname": row.nickname})
		var fighter := {
			"anima_id": anima_id,
			"name": row.nickname,
			"slot": index,
			"level": index + 1,
			"hp": 50,
			"max_hp": 50,
			"momentum": 3,
			"momentum_max": 3,
			"strike_name": "Team Tap",
			"surge_name": "Team Burst",
			"body_height_cm": 75 if index == 0 else 180 if index == 1 else 90,
		}
		player_state.append(fighter)
		player_snapshots.append({"anima_id": anima_id, "care_score": 4 if index == 0 else 0})
		art_cache[anima_id] = loaded
		var rival_id := "10000000-0000-4000-8000-00000000000%d" % index
		var rival := fighter.duplicate(true)
		rival["anima_id"] = rival_id
		rival["name"] = "Rival %d" % (index + 1)
		opponent_state.append(rival)
		opponent_snapshots.append({"anima_id": rival_id})
		art_cache[rival_id] = loaded
	var unavailable := roster[0].duplicate(true)
	unavailable["id"] = "00000000-0000-4000-8000-000000000009"
	unavailable["nickname"] = "Tired Team"
	unavailable["care"] = {"energy": 5.0, "hunger": 80.0, "hygiene": 80.0}
	roster.append(unavailable)
	var team := {
		"id": "20000000-0000-4000-8000-000000000001",
		"kind": "team_battle",
		"members": members,
	}
	var saved_three := team.duplicate(true)
	saved_three["members"] = members.slice(0, 3)
	view.set_builder(roster, saved_three)
	var roster_list := view.find_child("TeamRosterList", true, false) as ItemList
	var team_roster := roster_list as TeamRosterList
	var save := view.find_child("TeamSaveButton", true, false) as Button
	var builder_meta := view.find_child("TeamBuilderMeta", true, false) as Label
	_check(roster_list.item_count == 5, "Team builder lists the current roster")
	_check(
		team_roster.get_chosen_indices_ordered() == [0, 1, 2] and not save.disabled,
		"a saved three-member team restores pick order and can continue"
	)
	_check(
		builder_meta.text.contains(tr("TEAM_ROSTER_LEAD_HINT")),
		"Team builder explains that slot 1 leads battle"
	)
	_check(roster_list.is_item_disabled(4), "unavailable Anima cannot be selected for a Team")
	_check(
		roster_list.get_item_icon(0) == thumbnail
		and roster_list.get_item_text(0).contains(tr("TEAM_ROSTER_READY"))
		and roster_list.get_item_text(4).contains(tr("BATTLE_PICK_LOW_ENERGY")),
		"Team builder shows Anima art and concise readiness"
	)
	var cleared: Array[int] = []
	team_roster.set_chosen_order(cleared)
	_tap_roster_item(roster_list, 1)
	_check(
		team_roster.get_chosen_indices_ordered() == [1] and save.disabled,
		"one selected Anima does not meet the Team minimum"
	)
	_tap_roster_item(roster_list, 0)
	_check(
		team_roster.get_chosen_indices_ordered() == [1, 0] and not save.disabled,
		"two selected Anima enable Team Save in tap order"
	)
	var ordered_ids: Array = view.call("_selected_roster_ids")
	_check(
		ordered_ids.size() == 2
		and ordered_ids[0] == str(roster[1].get("id", ""))
		and ordered_ids[1] == str(roster[0].get("id", "")),
		"save payload leads with the first tapped Anima"
	)
	_tap_roster_item(roster_list, 2)
	_check(
		not save.disabled
		and team_roster.get_chosen_indices_ordered() == [1, 0, 2],
		"three selected Anima keep Team Save enabled in tap order"
	)
	_tap_roster_item(roster_list, 3)
	var selected_style := roster_list.get_theme_stylebox("selected_focus") as StyleBoxFlat
	var cursor_style := roster_list.get_theme_stylebox("cursor")
	_check(
		not save.disabled
		and team_roster.get_chosen_indices_ordered() == [1, 0, 2, 3]
		and roster_list.get_script().resource_path == "res://scripts/team_roster_list.gd"
		and selected_style.border_color.a > 0.0
		and roster_list.get_theme_color("font_selected_color").a == 1.0
		and cursor_style is StyleBoxEmpty
		and roster_list.get_theme_stylebox("hovered") is StyleBoxEmpty,
		"four taps keep four numbered slots and enable Save without a stale count"
	)
	_check_toggle_select_mode(roster_list, "the Team builder")
	_tap_roster_item(roster_list, 4)
	_check(
		not save.disabled
		and team_roster.get_chosen_indices_ordered() == [1, 0, 2, 3],
		"a blocked Anima never joins the ordered pick"
	)
	_tap_roster_item(roster_list, 1)
	_check(
		not save.disabled
		and team_roster.get_chosen_indices_ordered() == [0, 2, 3]
		and not roster_list.is_selected(1),
		"three members remain valid after removing the lead slot"
	)
	_tap_roster_item(roster_list, 2)
	_check(
		not save.disabled and team_roster.get_chosen_indices_ordered() == [0, 3],
		"two members remain a valid Team"
	)
	_tap_roster_item(roster_list, 3)
	_check(
		save.disabled and team_roster.get_chosen_indices_ordered() == [0],
		"dropping to one member disables Team Save"
	)
	_tap_roster_item(roster_list, 1)
	_check(
		not save.disabled and team_roster.get_chosen_indices_ordered() == [0, 1],
		"re-tapping restores the two-member minimum in pick order"
	)
	_check(
		team_roster.has_method("get_chosen_indices_ordered")
		and team_roster.has_method("set_chosen_order")
		and team_roster.has_method("indices_for_anima_ids"),
		"TeamRosterList exposes ordered pick and restore APIs"
	)
	# Pick order and paint agree only if the tap reaches the list at all. Under
	# SELECT_MULTI a deselect press was swallowed and the release collapsed the
	# paint to that single card, so the emitted-signal taps above all passed
	# while players saw one badge where three had been.
	await _test_roster_list_real_taps()
	await _test_item_list_drag_scroll()
	var daily := {
		"earned": 1, "limit": 2, "bits_earned": 8, "bits_limit": 40,
	}
	var candidates := [{
		"id": "30000000-0000-4000-8000-000000000001",
		"roster": opponent_state,
		"reward_tier": "even",
		"reward_bits": 8,
	}]
	view.set_lobby(team, daily, candidates, false)
	var rivals := view.find_child("TeamRivalList", true, false) as ItemList
	var start := view.find_child("TeamStartButton", true, false) as Button
	var builder_back := view.find_child("TeamBuilderBack", true, false) as Button
	var lobby_scroll := view.find_child("TeamLobbyScroll", true, false) as ScrollContainer
	_check(
		builder_back != null
		and builder_back.flat
		and builder_back.custom_minimum_size.y >= 96.0
		and builder_back.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and save.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and builder_back.get_parent() == save.get_parent(),
		"Team builder gives Back and Save equal full-width shares",
	)
	view.call("_edit_team")
	var builder_scroll := view.find_child("TeamBuilderScroll", true, false) as ScrollContainer
	view.set_busy(true)
	builder_back.pressed.emit()
	_check(
		builder_back.disabled and builder_scroll.visible and not lobby_scroll.visible,
		"Team builder Back cannot leave while Save is still committing",
	)
	view.set_busy(false)
	_tap_roster_item(roster_list, 0)
	builder_back.pressed.emit()
	_check(
		lobby_scroll.visible and not view.find_child("TeamBuilderScroll", true, false).visible,
		"Team builder Back returns to the rival lobby instead of closing Team Battle",
	)
	view.call("_edit_team")
	_check(
		team_roster.get_chosen_indices_ordered() == [0, 1, 2, 3],
		"reopening Team builder restores the saved order after cancelled edits",
	)
	builder_back.pressed.emit()
	_check(rivals.item_count == 1 and start.disabled, "Team lobby requires a rival selection")
	view.call("_select_candidate", 0)
	_check(not start.disabled, "selecting one rival enables Team Battle")
	var session := {
		"id": "40000000-0000-4000-8000-000000000001",
		"status": "active",
		"turn_number": 1,
		"version": 1,
		"item_used_id": null,
		"player_snapshot": player_snapshots,
		"opponent_snapshot": opponent_snapshots,
		"state": {
			"status": "active",
			"turn": 1,
			"player": {
				"active_slot": 0,
				"forced_switch": false,
				"item_used": false,
				"roster": player_state,
			},
			"opponent": {
				"active_slot": 0,
				"forced_switch": false,
				"item_used": false,
				"roster": opponent_state,
			},
		},
	}
	view.set_session(session, art_cache)
	_check(view.is_arena_open(), "set_session opens the immersive arena")
	var arena_background := view.find_child("TeamArenaBackground", true, false) as TextureRect
	var battle_stage := view.find_child("TeamBattleStage", true, false) as Control
	_check(
		arena_background != null
		and arena_background.visible
		and arena_background.texture == load(
			"res://assets/backgrounds/team_battle_background.png"
		)
		and arena_background.size.x >= battle_stage.size.x
		and arena_background.size.y >= battle_stage.size.y,
		"Team Battle uses its generated arena and cover-crops it without gaps"
	)
	_check(
		is_equal_approx(
			arena_background.position.y,
			-(arena_background.size.y - battle_stage.size.y)
			* BattleScale.STATIC_BACKGROUND_VERTICAL_PAN
		),
		"Team Battle shares the lowered static framing without changing fighter placement"
	)
	var header := view.get_node("Column/Header") as Control
	var turn := view.find_child("TeamTurn", true, false) as Label
	var forfeit := view.find_child("TeamForfeitButton", true, false) as Button
	var arena_hud := view.find_child("ArenaHud", true, false) as PanelContainer
	var arena_panel := view.find_child("ArenaPanel", true, false)
	var player_anchor := view.find_child("TeamPlayerAnchor", true, false)
	var player_shadow := player_anchor.find_child("GroundShadow", false, false)
	var opponent_shadow := view.find_child("TeamOpponentAnchor", true, false).find_child(
		"GroundShadow", false, false
	)
	var player_portal := player_anchor.find_child("SummonPortal", false, false)
	var arena_fighter := view.find_child("TeamPlayerSprite", true, false) as Node2D
	var effectiveness := view.find_child("TeamEffectiveness", true, false) as Control
	var event_plate := view.find_child("TeamEventPlate", true, false) as PanelContainer
	var effectiveness_label := view.find_child(
		"TeamEffectivenessLabel", true, false
	) as Label
	_check(
		not header.visible
		and not turn.visible
		and forfeit.visible
		and forfeit.custom_minimum_size.y >= TOUCH_MIN
		and forfeit.get_parent() != null
		and forfeit.get_parent().name == "SupportRow"
		and forfeit.get_index() == 3
		and not forfeit.flat,
		"active arena hides page chrome; Retreat closes the Team support row"
	)
	_check(
		arena_hud != null
		and arena_hud.offset_right >= -16.0
		and arena_panel == null
		and player_shadow != null
		and opponent_shadow != null
		and int(player_shadow.z_index) >= 0
		and int(opponent_shadow.z_index) >= 0
		and player_portal != null
		and arena_fighter != null
		and int(arena_fighter.z_index) > int(player_portal.z_index),
		"arena is borderless, HUD is full width, and Anima draws in front of the summon portal"
	)
	var shadow_texture := player_shadow.texture as GradientTexture2D
	_check(
		shadow_texture != null
		and shadow_texture.gradient.colors[0].a <= 0.45,
		"arena ground shadows stay subtle under every fighter"
	)
	var primary_row := view.find_child("PrimaryRow", true, false) as HBoxContainer
	var support_row := view.find_child("SupportRow", true, false) as HBoxContainer
	view.set_expedition_mode(true)
	await process_frame
	view.set_arena_location("The Sugarworks — Zone 1")
	_check(
		turn.visible
		and turn.text.contains("Sugarworks")
		and arena_hud.offset_top >= 40.0
		and primary_row.get_child_count() == 3
		and support_row.get_child_count() == 3
		and is_equal_approx(
			player_anchor.position.y,
			battle_stage.size.y * BATTLE_SCALE.GROUND_Y_RATIO
		),
		"Expedition keeps its approved 3+3 dock and lower ground line"
	)
	view.set_expedition_mode(false)
	await process_frame
	view.set_arena_location("")
	view.call("_show_effectiveness", 1.5)
	_check(
		effectiveness.visible and effectiveness_label.text == tr("BATTLE_EFFECTIVE"),
		"Team Battle shows Super effective in the arena"
	)
	_check(
		event_plate != null
		and event_plate.clip_contents
		and event_plate.theme_type_variation == &"BattleEventPlate"
		and effectiveness_label.get_parent() == event_plate
		and effectiveness_label.autowrap_mode != TextServer.AUTOWRAP_OFF
		and effectiveness_label.max_lines_visible == 2
		and float(view.get_script().get_script_constant_map().get("ACTION_CUE_SEC", 0.0)) >= 1.4,
		"Team Battle and Expedition share the readable event plate"
	)
	view.call("_show_effectiveness", 0.67)
	_check(
		effectiveness.visible and effectiveness_label.text == tr("BATTLE_NOT_EFFECTIVE"),
		"Team Battle shows Not very effective in the arena"
	)
	view.call("_show_effectiveness", 1.0)
	_check(not effectiveness.visible, "neutral Team attacks do not show a matchup banner")
	view.show_retreat_banner()
	_check(
		effectiveness.visible and effectiveness_label.text == tr("BATTLE_RETREATING"),
		"Team Retreat processing uses the same arena event plate as Super effective"
	)
	var actions := view.find_child("TeamActions", true, false) as VBoxContainer
	var switch_panel := view.find_child("TeamSwitchPanel", true, false) as VBoxContainer
	var special := view.find_child("TeamSpecialButton", true, false) as Button
	var attack := view.find_child("TeamAttackButton", true, false) as Button
	var feedback := view.find_child("TeamFeedback", true, false) as Label
	var player_slots := view.find_child("TeamPlayerSlots", true, false) as Label
	var player_name := view.find_child("TeamPlayerName", true, false) as Label
	_check(
		actions.visible
		and primary_row != null
		and support_row != null
		and primary_row.get_child_count() == 2
		and support_row.get_child_count() == 4
		and support_row.get_child(0) == view.find_child("TeamGuardButton", true, false)
		and special.theme_type_variation == &""
		and attack.custom_minimum_size.y >= TOUCH_MIN
		and special.custom_minimum_size.y >= TOUCH_MIN
		and not special.disabled
		and is_equal_approx(
			player_anchor.position.y,
			battle_stage.size.y * BATTLE_SCALE.GROUND_Y_RATIO
		)
		and is_equal_approx(
			float(view.get_script().get_script_constant_map().get("TEAM_BACKGROUND_MAX_SCALE", 0.0)),
			1.0
		),
		"Team arena preserves expanded sky and plants opaque feet on the shared ground line"
	)
	_check(
		player_slots.get_index() < player_name.get_index(),
		"party pips sit above the active Anima name"
	)
	_check(
		player_name.text.begins_with("Team 1") and player_name.text.contains(tr("LEVEL_SHORT")),
		"arena HUD names the active Anima with its Level"
	)
	_check(
		not feedback.visible and not player_slots.text.contains("Team 1"),
		"idle arena hides the choose-action prompt and keeps party pips nameless"
	)
	_check(
		str(view.call("_actor_name", "player")) == "Team 1"
		and not str(view.call("_actor_name", "player")).contains(tr("LEVEL_SHORT")),
		"event plate names omit Level"
	)
	var damage := view.find_child("TeamDamage", true, false) as Label
	_check(
		damage != null
		and damage.unique_name_in_owner
		and damage.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Team and Expedition show floating damage"
	)
	var team_source := FileAccess.get_file_as_string("res://scripts/team_battle_view.gd")
	_check(
		team_source.find("shadow.centered = true") >= 0
		and team_source.find("shadow.position = Vector2.ZERO") >= 0,
		"all generated Battle shadows use their node position as the visual center"
	)
	var attack_fn := team_source.substr(team_source.find("func _play_attack"), 3600)
	_check(
		team_source.find("BATTLE_EVENT_ITEM") >= 0
		and team_source.find("BATTLE_EVENT_ATTACK") >= 0
		and team_source.find("BATTLE_EVENT_TIMEOUT") >= 0
		and team_source.find("await _announce_initiative(events)") >= 0
		and team_source.find("BATTLE_INITIATIVE") >= 0,
		"Team event copy reuses the Duel plate strings"
	)
	_check(
		attack_fn.find("_present_banner") >= 0
		and attack_fn.find("_present_banner") < attack_fn.find("await _hide_effectiveness()")
		and attack_fn.find("await _hide_effectiveness()")
		< attack_fn.find("actor.set_pose(\"attack\")")
		and attack_fn.find("actor.set_pose(\"attack\")") < attack_fn.find("actor.play_fx")
		and team_source.find("_effectiveness_badge") < 0,
		"Team and Expedition hide action copy before Attack pose and VFX"
	)
	_check(
		attack_fn.find("await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)") >= 0
		and attack_fn.find("await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)")
		< attack_fn.find("actor.set_pose(\"idle\")")
		and attack_fn.find("actor.set_pose(\"idle\")")
		< attack_fn.find("if not effect_key.is_empty()"),
		"Team and Expedition return Attack to Idle on impact before effectiveness copy"
	)
	# Anchor on play_events: the first "guard": in the file is a COMMIT_COLORS
	# entry, and a window opened there checks nothing about the event handler.
	var guard_fn := team_source.substr(
		team_source.find("\"guard\":", team_source.find("func play_events")), 500
	)
	_check(
		guard_fn.find("concern_hit") < 0,
		"Boss Seeker does not look damaged when her Anima Guards"
	)
	_check(
		guard_fn.find("bracing.guard_shimmer()") >= 0
		and guard_fn.find("bracing.guard_shimmer()") < guard_fn.find("BATTLE_EVENT_GUARD"),
		"Team and Expedition shimmer the bracing body with the Guard plate"
	)
	_check(
		attack_fn.find("_react_seeker_attack(event)") >= 0
		and attack_fn.find("_react_seeker_attack(event)") < attack_fn.find("target.hit_react(element_multiplier)")
		and attack_fn.find("target.hit_react(element_multiplier)") < attack_fn.find("_play_damage")
		and attack_fn.find("_play_damage") < attack_fn.find("_restore_seeker_idle()")
		and attack_fn.find("_restore_seeker_idle()")
		< attack_fn.find("if not effect_key.is_empty()"),
		"Boss Seeker reacts on impact and returns Idle before effectiveness copy"
	)
	view.open_mode()
	view.call("_open_switch_picker", false)
	var switch_grid := view.find_child("SwitchButtons", true, false) as GridContainer
	var switch_slot := view.find_child("TeamSwitchSlot0", true, false) as Button
	_check(switch_panel.visible and actions.visible, "Switch opens the picker without hiding the action dock")
	await process_frame
	var overlay := view.find_child("SwitchOverlay", true, false) as Control
	var sheet := view.find_child("SwitchSheet", true, false) as PanelContainer
	_check(
		overlay != null
		and overlay.get_parent() == view
		and overlay.clip_contents
		and overlay.z_index > 2
		and overlay.visible
		and overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and sheet != null
		and sheet.theme_type_variation == &"BottomSheetPanel"
		and overlay.size.y >= view.size.y - 1.0
		and is_equal_approx(sheet.get_global_rect().position.x, view.get_global_rect().position.x)
		and switch_panel.get_global_rect().size.y >= 128.0
		and sheet.get_global_rect().end.y <= view.get_global_rect().end.y + 1.0,
		"Switch picker sits in a full-width bottom sheet without a dim scrim"
	)
	var switch_cancel := view.find_child("TeamSwitchCancel", true, false) as Button
	_check(
		switch_grid != null
		and switch_grid.columns == 2
		and switch_slot.icon != null
		and switch_slot.text.contains(tr("TEAM_SWITCH_ACTIVE"))
		and switch_slot.text.contains("Lv.")
		and switch_slot.find_child("Hp", true, false) != null,
		"Switch cards keep art, Level, HP, and status readable without a horizontal overflow"
	)
	_check(
		switch_cancel.visible and switch_cancel.custom_minimum_size.y >= TOUCH_MIN,
		"voluntary Switch exposes a 96px Cancel control"
	)
	_check(
		view.handle_back() and not switch_panel.visible and actions.visible,
		"Cancel/back closes the voluntary Switch picker and restores actions"
	)
	view.call("_open_switch_picker", false)
	switch_cancel.pressed.emit()
	_check(
		not switch_panel.visible and actions.visible,
		"tapping Cancel dismisses the Switch picker without sending a turn"
	)
	view.begin_action("strike")
	_check(
		not attack.disabled
		and attack.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and not feedback.visible
		and special.self_modulate.a < attack.self_modulate.a,
		"Team Battle locks the tapped action on the button without Resolving copy"
	)
	view.set_busy(false)
	var switched := session.duplicate(true)
	switched["state"]["player"]["active_slot"] = 1
	var switch_camera_layer := player_anchor.get_parent() as Node2D
	var camera_before := switch_camera_layer.scale
	var previous_layout: Dictionary = view.call("_fighter_layout")
	view.call("_apply_side", switched, "player", true, false)
	var refit := view.call(
		"_reframe_for_switch", switched, previous_layout, true
	) as Tween
	_check(
		refit != null
		and refit.is_running()
		and switch_camera_layer.scale.is_equal_approx(camera_before),
		"Switch camera refit starts from the current framing instead of snapping"
	)
	if refit != null and refit.is_running():
		await refit.finished
	var camera_after := switch_camera_layer.scale
	_check(
		not camera_after.is_equal_approx(camera_before),
		"Switch camera refit reaches framing for the incoming Anima height"
	)
	view.set_session(session, art_cache)
	await process_frame
	await view.call(
		"_play_switch",
		{"type": "switch", "actor": "player", "from_slot": 0, "to_slot": 1}
	)
	_check(
		switch_camera_layer.scale.is_equal_approx(camera_after),
		"Switch applies the new framing before the next attack event"
	)
	_check(
		player_name.text.begins_with("Team 2") and player_name.text.contains(tr("LEVEL_SHORT")),
		"Switch replaces the active fighter after the Summon handoff"
	)
	# Satu log turn bisa memuat dua switch di sisi yang sama — switch sukarela lalu
	# KO menyusul — jadi Summon wajib menampilkan anggota yang event ini sebut,
	# pada HP-nya sebelum damage turn itu. Memakai session akhir turn membuat pelat
	# menyebut satu nama sementara Anima lain yang muncul, lalu HP bar berhenti di
	# angka pasca-damage sehingga damage berikutnya tidak menggerakkannya.
	var opponent_name := view.find_child("TeamOpponentName", true, false) as Label
	var opponent_hp := view.find_child("TeamOpponentHp", true, false) as ProgressBar
	var mid_switch := session.duplicate(true)
	mid_switch["state"]["opponent"]["roster"][1]["hp"] = 43
	var end_of_turn := mid_switch.duplicate(true)
	end_of_turn["state"]["opponent"]["active_slot"] = 2
	end_of_turn["state"]["opponent"]["roster"][1]["hp"] = 12
	view.set_session(mid_switch, art_cache)
	await process_frame
	var summoned_named_member := false
	view.play_events(
		[{"type": "switch", "actor": "opponent", "from_slot": 0, "to_slot": 1}],
		end_of_turn,
		art_cache
	)
	var switch_deadline := Time.get_ticks_msec() + 15000
	while bool(view.get("_busy")) and Time.get_ticks_msec() < switch_deadline:
		if opponent_name.text.begins_with("Rival 2") and int(opponent_hp.value) == 43:
			summoned_named_member = true
		await process_frame
	_check(
		summoned_named_member,
		"Switch summons the member its plate names, at that member's HP before the turn"
	)
	# Replay authoritative dimulai ketika arena sudah menampilkan session prediksi,
	# jadi baseline Summon wajib datang dari pemanggil lewat `from_session`.
	var replay_read_pre_turn_hp := false
	view.play_events(
		[{"type": "switch", "actor": "opponent", "from_slot": 0, "to_slot": 1}],
		end_of_turn,
		art_cache,
		mid_switch
	)
	var replay_deadline := Time.get_ticks_msec() + 15000
	while bool(view.get("_busy")) and Time.get_ticks_msec() < replay_deadline:
		if opponent_name.text.begins_with("Rival 2") and int(opponent_hp.value) == 43:
			replay_read_pre_turn_hp = true
		await process_frame
	_check(
		replay_read_pre_turn_hp,
		"Authoritative replay summons from the session before the turn, not the prediction"
	)
	session["state"]["player"]["active_slot"] = 0
	view.set_session(session, art_cache)
	var after_ko := session.duplicate(true)
	after_ko["turn_number"] = 9
	after_ko["state"]["turn"] = 9
	after_ko["state"]["player"]["forced_switch"] = true
	after_ko["state"]["player"]["roster"][0]["hp"] = 0
	after_ko["state"]["player"]["roster"][0]["momentum"] = 0
	var player_sprite := view.find_child("TeamPlayerSprite", true, false)
	var saw_initiative := false
	var fainted_on_ko_plate := false
	var initiative_copy := tr("BATTLE_INITIATIVE") % str(view.call("_actor_name", "opponent"))
	var ko_copy := tr("BATTLE_EVENT_KO") % str(view.call("_actor_name", "player"))
	view.play_events([
		{
			"type": "attack",
			"actor": "opponent",
			"target": "player",
			"action": "strike",
			"damage": 50,
			"target_hp": 0,
			"critical": false,
			"element": 1.0,
		},
		{"type": "knockout", "actor": "player"},
	], after_ko)
	var ko_deadline := Time.get_ticks_msec() + 20000
	while bool(view.get("_busy")) and Time.get_ticks_msec() < ko_deadline:
		if effectiveness_label.text == initiative_copy:
			saw_initiative = true
		if player_sprite.current_pose() == "defeated" and effectiveness_label.text == ko_copy:
			fainted_on_ko_plate = true
		await process_frame
	_check(
		saw_initiative,
		"Team and Expedition announce who moves first before the first Attack"
	)
	_check(
		fainted_on_ko_plate,
		"knockout plate lands on the Defeated pose"
	)
	_check(
		switch_panel.visible and actions.visible and not switch_cancel.visible,
		"knockout event log opens the replacement picker after the faint"
	)
	_check(
		not view.handle_back() and switch_panel.visible,
		"forced replacement cannot be cancelled"
	)
	var switch_title := view.find_child("TeamSwitchTitle", true, false) as Label
	_check(
		not feedback.visible
		and switch_title != null
		and switch_title.text == tr("TEAM_SWITCH_FORCED"),
		"forced replacement uses the picker title once, not a second dock line"
	)
	_check(
		player_sprite.current_pose() == "defeated",
		"knocked-out fighter stays in the Defeated pose until a replacement is sent"
	)
	session["state"]["player"]["forced_switch"] = true
	session["state"]["player"]["roster"][0]["hp"] = 0
	view.set_session(session, art_cache)
	_check(
		switch_panel.visible and actions.visible,
		"resumed knockout still requires a free replacement before another action"
	)
	var last_stand := session.duplicate(true)
	last_stand["state"]["player"]["forced_switch"] = true
	last_stand["state"]["player"]["roster"][0]["hp"] = 0
	last_stand["state"]["player"]["roster"][1]["hp"] = 0
	last_stand["state"]["player"]["roster"][2]["hp"] = 0
	var auto_switch := []
	view.action_requested.connect(
		func(action: String, slot: int) -> void: auto_switch.append([action, slot])
	)
	view.set_busy(true)
	view.set_session(last_stand, art_cache)
	_check(
		auto_switch.is_empty(),
		"auto-switch waits while the authoritative turn is still committing"
	)
	view.set_busy(false)
	await process_frame
	_check(
		not switch_panel.visible
		and auto_switch == [["switch", 3]],
		"the last living Anima summons after the controller releases its lock"
	)
	session["status"] = "won"
	session["state"]["status"] = "won"
	session["state"]["player"]["forced_switch"] = false
	session["last_reward"] = {
		"bits": 8,
		"anima_exp": [
			{"anima_id": members[0].anima_id, "exp": 2},
			{"anima_id": members[1].anima_id, "exp": 1},
		],
	}
	view.set_session(session, art_cache)
	var result := view.find_child("TeamResult", true, false) as VBoxContainer
	var result_body := view.find_child("TeamResultBody", true, false) as Label
	_check(result.visible, "terminal Team session restores its result")
	_check(
		result_body.text.contains("Team 1")
		and result_body.text.contains("Team 2")
		and result_body.text.contains("LEVEL UP")
		and result_body.text.contains("Lv. 2"),
		"Team win lists each member EXP and who leveled up"
	)
	session["last_reward"] = {
		"bits": 6,
		"progression": true,
		"anima_exp": [{"anima_id": members[0].anima_id, "exp": 2}],
	}
	view.set_session(session, art_cache)
	_check(
		"6" in result_body.text and result_body.text.contains("Team 1"),
		"resumed Team win restores its per-Anima EXP receipt"
	)
	var team_retry := view.find_child("TeamRetryButton", true, false) as Button
	var team_leave := view.find_child("TeamLeaveButton", true, false) as Button
	var team_builder := view.find_child("TeamBuilder", true, false) as VBoxContainer
	var team_exits := [0]
	var team_retries := [0]
	view.back_requested.connect(func() -> void: team_exits[0] += 1)
	view.retry_requested.connect(func() -> void: team_retries[0] += 1)
	var lost_session: Dictionary = session.duplicate(true)
	lost_session["status"] = "lost"
	(lost_session["state"] as Dictionary)["status"] = "lost"
	view.set_session(lost_session, art_cache)
	_check(team_retry.text == tr("TEAM_RETRY"), "Team loss keeps Try Again on the result CTA")
	var forfeit_session: Dictionary = session.duplicate(true)
	forfeit_session["status"] = "forfeited"
	(forfeit_session["state"] as Dictionary)["status"] = "forfeited"
	view.set_session(forfeit_session, art_cache)
	_check(team_retry.text == tr("TEAM_RETRY"), "Team forfeit keeps Try Again on the result CTA")
	view.set_session(session, art_cache)
	_check(
		team_leave != null and team_leave.visible
		and tr(team_leave.text) == tr("BATTLE_RETURN_LOBBY")
		and team_retry.text == tr("TEAM_NEXT_BATTLE"),
		"terminal Team win offers Next Battle and a way out"
	)
	team_leave.pressed.emit()
	_check(team_exits[0] == 1, "Team leave button closes the mode")
	team_retry.pressed.emit()
	_check(team_retries[0] == 1, "a rested team keeps the plain rematch CTA")
	var drained: Array[Dictionary] = roster.duplicate(true)
	drained[1]["care"]["energy"] = 5.0
	view.set_roster(drained)
	var team_blocked_line := tr("BATTLE_RESULT_BLOCKED") % tr("BATTLE_PICK_LOW_ENERGY")
	_check(
		team_retry.text == tr("TEAM_EDIT")
		and result_body.text.ends_with(team_blocked_line),
		"a drained member swaps the Team rematch CTA for Edit Team plus the reason"
	)
	team_retry.pressed.emit()
	_check(
		team_retries[0] == 1 and team_builder.visible and not result.visible,
		"the blocked Team CTA opens the builder instead of a rematch"
	)
	view.set_session(session, art_cache)
	view.set_roster(roster)
	_check(
		team_retry.text == tr("TEAM_NEXT_BATTLE")
		and not result_body.text.ends_with(team_blocked_line),
		"swapping the drained member back restores the Team Next Battle CTA"
	)
	view.set_expedition_mode(true)
	_check(
		not team_leave.visible and team_retry.text == tr("EXPEDITION_RETURN_MAP"),
		"Expedition already leaves through Return to Map, so it grows no second exit"
	)
	view.set_roster(drained)
	_check(
		team_retry.text == tr("EXPEDITION_RETURN_MAP"),
		"Expedition never rewrites Return to Map into a Team builder CTA"
	)
	view.set_roster(roster)
	session["last_reward"] = {
		"supplies": 4,
		"anima_exp": [{"anima_id": members[0].anima_id, "exp": 2}],
	}
	view.set_session(session, art_cache)
	_check(
		"4" in result_body.text
		and result_body.text.contains("Team 1")
		and result_body.text.contains("LEVEL UP"),
		"Expedition win lists Tokens, member EXP, and Level Up"
	)
	var flow_script := load("res://scripts/scan_flow.gd") as GDScript
	var item_payload: Dictionary = flow_script.team_battle_turn_payload({
		"session_id": "team-session",
		"expected_turn": 2,
		"expected_version": 3,
		"action": "item",
		"item_id": "battle_patch",
		"switch_to_slot": 2,
		"idempotency_key": "team-item-key",
	})
	_check(
		item_payload.get("item_id") == "battle_patch"
		and not item_payload.has("switch_to_slot"),
		"Team item payload cannot leak a stale switch slot"
	)
	var switch_payload: Dictionary = flow_script.team_battle_turn_payload({
		"session_id": "team-session",
		"expected_turn": 2,
		"expected_version": 3,
		"action": "switch",
		"item_id": "battle_patch",
		"switch_to_slot": 2,
		"idempotency_key": "team-switch-key",
	})
	_check(
		switch_payload.get("switch_to_slot") == 2
		and not switch_payload.has("item_id"),
		"Team switch payload cannot leak a stale item"
	)
	var seeker_art := art_cache.duplicate()
	seeker_art["boss_seeker"] = _boss_seeker_loaded()
	var boss_session := session.duplicate(true)
	boss_session["id"] = "boss-session-1"
	boss_session["kind"] = "boss"
	boss_session["status"] = "active"
	boss_session["turn_number"] = 1
	boss_session["zone_attempt"] = 1
	boss_session["boss_seeker"] = _boss_seeker_payload()
	boss_session["state"]["status"] = "active"
	boss_session["last_reward"] = {}
	view.set_session(boss_session, seeker_art)
	await process_frame
	var seeker := view.find_child("BossSeeker", true, false) as AnimatedSprite2D
	var boss_opponent := view.find_child("TeamOpponentSprite", true, false) as AnimaPresenter
	var opponent_anchor := view.find_child("TeamOpponentAnchor", true, false) as Node2D
	var dialog := view.find_child("BossSeekerDialog", true, false) as BossSeekerDialog
	_check(
		seeker != null
		and seeker.visible
		and seeker.sprite_frames != null
		and seeker.z_index > 0
		and boss_opponent != null
		and opponent_anchor != null
		and seeker.z_index < opponent_anchor.z_index
		and not boss_opponent.visible
		and seeker.get_parent() != null
		and seeker.get_parent().find_child("GroundShadow", false, false) != null,
		"boss intro shows the Seeker before her Anima"
	)
	var stage := view.find_child("TeamBattleStage", true, false) as Control
	var metrics_value: Variant = seeker_art["boss_seeker"].get("render_metrics")
	var seeker_metrics: Dictionary = (
		metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	)
	_check(stage != null and stage.size.x > 0.0, "Boss arena has a camera viewport")
	var giant_session := boss_session.duplicate(true)
	giant_session["id"] = "boss-giant-1"
	giant_session["turn_number"] = 2
	giant_session["state"]["turn"] = 2
	giant_session["state"]["player"]["roster"][0]["body_height_cm"] = 2000
	giant_session["state"]["opponent"]["roster"][0]["body_height_cm"] = 2000
	giant_session["boss_seeker"]["body_height_cm"] = 165
	view.set_session(giant_session, seeker_art)
	await process_frame
	await process_frame
	var giant_player := view.find_child("TeamPlayerSprite", true, false) as AnimaPresenter
	var giant_opponent := view.find_child("TeamOpponentSprite", true, false) as AnimaPresenter
	var giant_anchor := view.find_child("TeamPlayerAnchor", true, false) as Node2D
	var opponent_giant_anchor := view.find_child("TeamOpponentAnchor", true, false) as Node2D
	var camera_layer := giant_anchor.get_parent() as Node2D
	var seeker_h := float(seeker_metrics.get("reference_height_px", 300.0)) * absf(seeker.scale.y)
	var player_h := giant_player.opaque_local_rect().size.y * absf(giant_anchor.scale.y)
	var player_half := giant_player.opaque_local_rect().size.x * absf(giant_anchor.scale.x) * 0.5
	var opponent_half := (
		giant_opponent.opaque_local_rect().size.x * absf(opponent_giant_anchor.scale.x) * 0.5
	)
	_check(
		seeker_h > 1.0
		and player_h > 1.0
		and absf(player_h / seeker_h - 300.0 / 165.0) < 0.08,
		"capped 20 m Anima is almost 2× the Seeker on screen"
	)
	var player_left := camera_layer.position.x + (
		giant_anchor.position.x - player_half
	) * camera_layer.scale.x
	var opponent_right := camera_layer.position.x + (
		opponent_giant_anchor.position.x + opponent_half
	) * camera_layer.scale.x
	_check(
		camera_layer.scale.x < 1.0
		and player_left >= -1.0
		and opponent_right <= stage.size.x + 1.0,
		"dynamic camera zooms out until both capped Animas stay fully visible"
	)
	var dim := dialog.find_child("SeekerDim", true, false) as ColorRect if dialog != null else null
	var intro_line := dialog.find_child("SeekerLine", true, false) as Label if dialog != null else null
	_check(
		dialog != null and dialog.is_open()
		and intro_line != null
		and intro_line.text.contains("Show me")
		and (dim == null or not dim.visible),
		"boss intro opens without a dark overlay"
	)
	_check(view.handle_back(), "back dismisses boss intro instead of leaving the arena")
	await process_frame
	_check(not dialog.is_open(), "dismissed boss intro stays closed")
	for _step in 120:
		if boss_opponent.visible:
			break
		await process_frame
	_check(boss_opponent.visible, "tap continues into the Seeker summoning her Anima")
	_check(
		opponent_anchor.z_index < seeker.z_index,
		"first Boss summon recomputes the tall Anima behind the Seeker before turn one"
	)
	var seeker_rest := seeker.position
	seeker.call("play_cut_in")
	await process_frame
	_check(
		seeker.position.is_equal_approx(seeker_rest),
		"Boss Seeker command poses stay on their planted anchor"
	)
	_dismiss_when_open(dialog)
	await view.play_events([{
		"type": "attack",
		"actor": "opponent",
		"target": "player",
		"action": "strike",
		"target_hp": 40,
		"element_multiplier": 1.0,
	}], giant_session, seeker_art)
	_check(not dialog.is_open(), "first opponent Attack speaks once then closes")
	await view.play_events([{
		"type": "attack",
		"actor": "opponent",
		"target": "player",
		"action": "strike",
		"target_hp": 30,
		"element_multiplier": 1.0,
	}], giant_session, seeker_art)
	_check(not dialog.is_open(), "replayed opponent Attack does not repeat first_attack")
	var ace_session := giant_session.duplicate(true)
	ace_session["state"]["opponent"]["active_slot"] = 3
	var ace_member: Dictionary = ace_session["state"]["opponent"]["roster"][3]
	_dismiss_when_open(dialog)
	await view.play_events([{
		"type": "final_ace",
		"actor": "opponent",
		"to_slot": 3,
		"anima_id": ace_member.get("anima_id", ""),
		"name": ace_member.get("name", ""),
	}, {
		"type": "switch",
		"actor": "opponent",
		"to_slot": 3,
		"forced": true,
		"name": ace_member.get("name", ""),
	}, {
		"type": "ace_passive",
		"actor": "opponent",
		"passive_name": "Final Confection",
		"copy": "Nimbelisk enters with +1 PP.",
	}], ace_session, seeker_art)
	_check(not dialog.is_open(), "final ace line closes before Summon and passive finish")
	_check(seeker.animation == "intro_idle", "final ace sequence restores the Seeker idle pose")

	# Figur pemain: cermin Boss Seeker di sisi seberang. Fixture in-memory yang
	# sama dipakai untuk keduanya, jadi geometri yang diperiksa di bawah datang
	# dari sheet yang sudah terbukti alih-alih dari art roster yang ter-bundel.
	var avatar_camera_before := camera_layer.scale
	var avatar_loaded := _boss_seeker_loaded()
	view.set_player_avatar(avatar_loaded)
	await process_frame
	var avatar := view.find_child("PlayerSeeker", true, false) as AnimatedSprite2D
	var avatar_shadow := view.find_child("PlayerSeekerShadow", true, false) as Sprite2D
	_check(
		avatar != null and avatar.visible and avatar.sprite_frames != null
		and avatar.flip_h
		and avatar.get_parent() == camera_layer
		and avatar_shadow != null and avatar_shadow.visible,
		"the player's Seeker Avatar stands in the arena facing the opponent"
	)
	_check(
		avatar.position.y == giant_anchor.position.y
		and avatar.position.y == seeker.position.y,
		"both Seeker figures stand on the one ground line the fighters use"
	)
	# Anima 2000 cm ini jauh di atas ambang `anima_behind_seeker()`, jadi
	# figurnya wajib melangkah ke depan. Lantainya harus melewati anchor
	# petarung **berikut** sprite di atasnya, karena sprite Anima relatif
	# terhadap anchor-nya; bayangan kontaknya ikut lantai yang sama supaya ia
	# tidak tertinggal di balik Anima yang figurnya baru saja lewati.
	_check(
		avatar.z_index > giant_anchor.z_index + giant_player.z_index
		and avatar.z_index > opponent_giant_anchor.z_index + giant_player.z_index
		and avatar_shadow.z_index == avatar.z_index,
		"the player figure steps in front of an Anima that would swallow it"
	)
	# Kedua figur memakai satu jalur bayangan di presenter, jadi diperiksa dari
	# node hidup: tanpa fudge vertikal, piksel opak terbawah figur mendarat tepat
	# di pusat visual bayangannya.
	var boss_shadow := seeker.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	_check(
		boss_shadow != null
		and boss_shadow.position == seeker.position
		and avatar_shadow.position == avatar.position,
		"either Seeker's lowest opaque pixel meets the vertical center of its shadow"
	)
	# Struktural, jadi ia berlaku di portrait maupun landscape: figur hidup di
	# dalam stage, dan stage digambar sebelum dock aksi di kolom arena yang sama.
	var arena_column := stage.get_parent()
	_check(
		camera_layer.get_parent() == stage
		and stage.get_index() < arena_column.get_node("TeamDock").get_index(),
		"the player figure can never cover the action dock, at any aspect"
	)
	# Kamera memang membingkai ulang: kolom figur pemain ikut menentukan bingkai,
	# dan tanpa itu ia mendarat di atas Anima-nya sendiri. Arahnya yang dipagari —
	# ruang hanya boleh dibeli dengan zoom, tidak pernah dengan memperbesar.
	_check(
		camera_layer.scale.x <= avatar_camera_before.x,
		"reserving the player figure's column only ever costs zoom, never adds it"
	)
	# Dihitung ulang di sini alih-alih dibaca dari view: kalau rumus jepitnya
	# bergeser, angka yang diharapkan tidak ikut bergeser diam-diam.
	var avatar_frame := float((avatar_loaded.get("frame_size", Vector2i(341, 341)) as Vector2i).x)
	var avatar_width := float(seeker_metrics.get("reference_width_px", 0.0))
	var avatar_body := (
		float(seeker_metrics.get("reference_min_x_px", 0.0))
		+ avatar_width * 0.5
		- avatar_frame * 0.5
	)
	# `flip_h` mencerminkan sel terhadap origin, jadi pusat badan pindah tanda.
	var avatar_center_x := camera_layer.position.x + (
		avatar.position.x - avatar_body * absf(avatar.scale.x)
	) * camera_layer.scale.x
	var avatar_screen_w := avatar_width * absf(avatar.scale.x) * camera_layer.scale.x
	_check(
		camera_layer.scale.x < 1.0
		and avatar_width > 1.0
		and absf(avatar_center_x - (stage.size.x * 0.025 + avatar_screen_w * 0.5)) < 1.0
		and avatar_center_x < stage.size.x * 0.5,
		"a zoomed-out arena pins the player figure to its own screen edge"
	)

	# Pose sisi pemain hidup di tengah `play_events()` lalu kembali idle, jadi
	# nilai akhirnya saja tidak membuktikan apa pun. Kolektor jalan berdampingan.
	_dismiss_when_open(dialog)
	var avatar_poses := {}
	_collect_poses(avatar, avatar_poses)
	await view.play_events([{
		"type": "switch",
		"actor": "player",
		"to_slot": 1,
		"name": str(ace_session["state"]["player"]["roster"][1].get("name", "")),
	}, {
		"type": "attack",
		"actor": "player",
		"target": "opponent",
		"action": "surge",
		"target_hp": 20,
		"element_multiplier": 1.0,
	}, {
		"type": "attack",
		"actor": "player",
		"target": "opponent",
		"action": "strike",
		"target_hp": 10,
		"element_multiplier": 1.0,
	}, {
		"type": "attack",
		"actor": "opponent",
		"target": "player",
		"action": "strike",
		"target_hp": 20,
		"element_multiplier": 1.0,
	}], ace_session, seeker_art)
	avatar_poses["stop"] = true
	_check(
		avatar_poses.has("switch_command")
		and avatar_poses.has("special_command")
		and avatar_poses.has("attack_command")
		and avatar_poses.has("concern_hit"),
		"the player figure commands its own Switch, Attack, and Special, and worries when hit"
	)
	_check(
		avatar.animation == "intro_idle",
		"the player figure settles back to idle between turns"
	)
	_check(
		not dialog.is_open()
		and view.find_children("*", "BossSeekerDialog", true, false).size() == 1,
		"the player figure is present without a dialog panel of its own"
	)

	var won := ace_session.duplicate(true)
	won["status"] = "won"
	won["state"]["status"] = "won"
	won["last_reward"] = {
		"supplies": 3,
		"first_clear": true,
		"clear_bits": 25,
		"trophy": {"display_name": "Sugarfold Core"},
	}
	var trophy_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var trophy_art := seeker_art.duplicate()
	trophy_art["trophy"] = ImageTexture.create_from_image(trophy_image)
	var result_panel := view.find_child("TeamResult", true, false) as Control
	view.set_session(won, trophy_art)
	await process_frame
	_check(dialog.is_open(), "player win opens the Seeker victory line")
	_check(seeker.animation == "defeat", "player win uses the Seeker defeat pose")
	_check(avatar.animation == "victory", "player win puts the player's own figure in victory")
	dialog.dismiss()
	await process_frame
	var trophy_line := dialog.find_child("SeekerLine", true, false) as Label
	var trophy_speaker := dialog.find_child("SeekerName", true, false) as Label
	_check(
		dialog.is_open()
		and trophy_speaker.text == "Sugarfold Core"
		and trophy_line.text.contains("Sugarfold Core")
		and (dialog.get("_portrait") as TextureRect).texture != null
		and not result_panel.visible,
		"first clear reveals the Trophy right after the Seeker's last line, before the summary"
	)
	dialog.dismiss()
	await process_frame
	_check(
		result_panel.visible and not dialog.is_open(),
		"the reward summary follows the Trophy reveal"
	)
	view.set_session(won, trophy_art)
	await process_frame
	_check(
		not dialog.is_open(),
		"a replayed terminal session never announces the same Trophy twice"
	)
	var lost := ace_session.duplicate(true)
	lost["id"] = "boss-lost-1"
	lost["status"] = "lost"
	lost["state"]["status"] = "lost"
	lost["last_reward"] = {}
	view.set_session(lost, seeker_art)
	await process_frame
	_check(avatar.animation == "defeat", "a lost Battle leaves the player's figure defeated")

	# Shell adalah satu-satunya yang tahu akun mana yang aktif, jadi ia yang
	# menyuapkan figurnya — lewat funnel profil yang sudah ada, bukan jalur kedua,
	# dan dari roster yang ter-bundel (ADR-0002), bukan dari unduhan.
	var arena_flow := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var sync_body := _func_body(arena_flow, "func _sync_seeker_avatar(")
	_check(
		sync_body.find("SeekerRoster.sheet(GameState.profile.get(\"seeker_avatar\"))") >= 0
		and sync_body.find("_battle_view.set_player_avatar(") >= 0
		and sync_body.find("_team_battle_view.set_player_avatar(") >= 0
		and sync_body.find("_expedition_view.set_player_avatar(") >= 0
		and _func_body(arena_flow, "func _refresh_header(").find("_sync_seeker_avatar()") >= 0
		and _func_body(arena_flow, "func _change_seeker_avatar(").find("_sync_seeker_avatar()") >= 0,
		"the shell feeds the chosen figure to all three arenas whenever the profile moves"
	)
	view.queue_free()
	await process_frame


## Pose berubah di tengah `play_events()` dan kembali idle di akhirnya, jadi
## pembacaan sesudah `await` selalu melihat idle. Kolektor ini jalan berdampingan
## dengan event-nya — pola yang sama dengan `_dismiss_when_open()` — dan berhenti
## saat pemanggilnya menaruh `stop`.
func _collect_poses(sprite: AnimatedSprite2D, seen: Dictionary) -> void:
	while not seen.get("stop", false):
		if not is_instance_valid(sprite):
			return
		seen[str(sprite.animation)] = true
		await process_frame


func _test_expedition_view() -> void:
	var controller_script := load("res://scripts/expedition_controller.gd") as GDScript
	var choice_payload: Dictionary = controller_script.operation_payload({
		"operation": "choose",
		"run_id": "run",
		"run_version": 3,
		"option_id": "heal",
		"target_slot": -1,
		"idempotency_key": "choice-key",
	})
	_check(
		choice_payload.get("expected_version") == 3
		and choice_payload.get("option_id") == "heal"
		and not choice_payload.has("target_slot"),
		"Expedition choice payload omits an unused target slot"
	)
	var checkpoint_payload: Dictionary = controller_script.operation_payload({
		"operation": "checkpoint_choice",
		"run_id": "run",
		"run_version": 4,
		"option_id": "power_up",
		"idempotency_key": "checkpoint-key",
	})
	_check(
		checkpoint_payload.get("expected_version") == 4
		and checkpoint_payload.get("option_id") == "power_up",
		"Expedition checkpoint choice persists its authoritative option and version"
	)
	_check(
		controller_script.pending_matches(
			{
				"operation": "turn",
				"expected_turn": 2,
				"expected_version": 4,
			},
			{"version": 7},
			{"status": "active", "turn_number": 2, "version": 4}
		)
		and not controller_script.pending_matches(
			{
				"operation": "turn",
				"expected_turn": 2,
				"expected_version": 3,
			},
			{"version": 7},
			{"status": "active", "turn_number": 2, "version": 4}
		),
		"Expedition replays only an intent matching authoritative encounter state"
	)
	_check(
		controller_script.should_resume_error("STALE_EXPEDITION_ENCOUNTER")
		and controller_script.should_resume_error("NO_ITEM")
		and not controller_script.should_resume_error("NO_SUPPLIES"),
		"stale/terminal encounter errors and an empty item stock enter the bounded resume path, not the fatal one"
	)
	var flow_script := load("res://scripts/scan_flow.gd") as GDScript
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var boot_start := flow_source.find("func _boot")
	var boot_end := flow_source.find("\n\nfunc _reload_roster", boot_start)
	var boot_body := flow_source.substr(
		boot_start, boot_end - boot_start
	) if boot_start >= 0 and boot_end > boot_start else ""
	_check(
		boot_body.find("_resume_battle()") < 0
		and boot_body.find("_resume_team_battle()") < 0
		and boot_body.find("_expedition_controller.resume_pending()") < 0
		and boot_body.find("_switch_destination(BottomNav.BATTLE)") < 0,
		"shell boot leaves persisted Battle modes waiting while Home stays selected"
	)
	var level_ups: Array = flow_script.expedition_level_rewards({
		"anima_exp": [
			{"anima_id": "level-a", "exp": 2},
			{"anima_id": "level-b", "exp": 1},
			{"anima_id": "steady", "exp": 1},
		]
	}, [
		{"anima_id": "level-a", "name": "Level A", "care_score": 4},
		{"anima_id": "level-b", "name": "Level B", "care_score": 9},
		{"anima_id": "steady", "name": "Steady", "care_score": 0},
	])
	_check_eq(level_ups.size(), 2, "Expedition queues every member that crossed a Level")
	if level_ups.size() == 2:
		_check_eq(level_ups[0].anima_id, "level-a", "Level Up queue keeps roster order")
		_check_eq(level_ups[0].level, 2, "first Expedition Level Up has its new Level")
		_check_eq(level_ups[1].level, 3, "second Expedition Level Up has its new Level")
	var controller_source := FileAccess.get_file_as_string(
		"res://scripts/expedition_controller.gd"
	)
	var submit_pending := controller_source.substr(
		controller_source.find("func _submit_pending"), 6500
	)
	_check(
		submit_pending.find("await _view.play_combat_events") >= 0
		and submit_pending.find("await _view.play_combat_events")
		< submit_pending.find("reward_presented.emit(turn_reward, next_encounter)"),
		"Expedition shows the reward summary before starting Level Up presentation"
	)
	_check(
		flow_source.find("_expedition_level_queue.pop_front()") >= 0
		and flow_source.count("&\"expedition_level_up\":") == 2
		and flow_source.find("set_level_up_sequence_busy(true)") >= 0
		and flow_source.find("set_level_up_sequence_busy(false)") >= 0,
		"Expedition advances one Level Up dialog per button or back action before Return Map"
	)
	_check(
		flow_source.find("LEVEL_UP_TITLE") >= 0
		and flow_source.find("CARE_RULES.grown_stat(stats.get(key, 0), previous_score)") >= 0
		and flow_source.find("CARE_RULES.grown_stat(stats.get(key, 0), new_score)") >= 0,
		"each queued Expedition Anima receives Duel-style stat comparison"
	)
	_check(
		flow_source.find("abandon_requested.connect(_confirm_expedition_abandon)") >= 0
		and flow_source.find("EXPEDITION_ABANDON_CONFIRM") >= 0
		and flow_source.find("_expedition_controller.abandon()") >= 0,
		"Expedition Abandon requires a destructive consequence dialog before commit"
	)
	var packed := load("res://scenes/ui/expedition_view.tscn") as PackedScene
	var view := packed.instantiate()
	root.add_child(view)
	await process_frame
	var back := view.find_child("ExpeditionBack", true, false) as Button
	var back_icon := view.find_child("ExpeditionBackIcon", true, false) as TextureRect
	_check(
		back.flat and back.text.is_empty() and back_icon.texture != null
		and back_icon.position.y < 16.0,
		"Expedition header uses a compact chevron Back control"
	)
	var chapter_list := view.find_child("ExpeditionChapterList", true, false) as ItemList
	var open_chapter := view.find_child("ExpeditionOpenChapter", true, false) as Button
	view.set_catalog([
		{
			"version_id": "chapter-v1",
			"unlocked": true,
			"first_cleared_at": null,
			"summary": {"title": "Sugartrail", "description": "Candy paths"},
		},
		{
			"version_id": "chapter-v2",
			"unlocked": false,
			"first_cleared_at": null,
			"summary": {"title": "Locked chapter"},
		},
	])
	_check(
		chapter_list.item_count == 2
		and chapter_list.is_item_disabled(1)
		and not open_chapter.disabled,
		"Expedition catalog opens unlocked chapters and blocks locked chapters"
	)
	var roster: Array[Dictionary] = []
	var members: Array[Dictionary] = []
	var thumbnail_image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	thumbnail_image.fill(Color.WHITE)
	var thumbnail := ImageTexture.create_from_image(thumbnail_image)
	view.set_thumbnail_provider(func(_row: Dictionary) -> Texture2D: return thumbnail)
	for index in 4:
		var anima_id := "50000000-0000-4000-8000-00000000000%d" % index
		roster.append({
			"id": anima_id,
			"nickname": "Trail %d" % (index + 1),
			"status": "ready",
			"element": "food",
			"care": {"energy": 80.0},
		})
		members.append({"slot": index, "anima_id": anima_id})
	var tired := roster[0].duplicate(true)
	tired["id"] = "50000000-0000-4000-8000-000000000009"
	tired["care"] = {"energy": 20.0}
	roster.append(tired)
	view.set_builder(roster, {"id": "expedition-team", "members": members})
	var roster_list := view.find_child("ExpeditionRosterList", true, false) as ItemList
	var expedition_roster := roster_list as TeamRosterList
	var save_team := view.find_child("ExpeditionSaveTeam", true, false) as Button
	var expedition_builder_meta := view.find_child("ExpeditionBuilderMeta", true, false) as Label
	_check(
		roster_list.is_item_disabled(4) and not save_team.disabled
		and roster_list.get_script().resource_path == "res://scripts/team_roster_list.gd"
		and roster_list.get_theme_color("font_selected_color").a == 1.0
		and expedition_roster.get_chosen_indices_ordered() == [0, 1, 2, 3],
		"Expedition Team restores four numbered selections and blocks low Energy"
	)
	_check_toggle_select_mode(roster_list, "the Expedition builder")
	_check(
		expedition_builder_meta.text.contains(tr("TEAM_ROSTER_LEAD_HINT")),
		"Expedition builder shares the slot-1 lead hint"
	)
	_tap_roster_item(roster_list, 2)
	_check(
		save_team.disabled and expedition_roster.get_chosen_indices_ordered() == [0, 1, 3],
		"Expedition Save follows ordered picks instead of Godot's index-sorted state"
	)
	_tap_roster_item(roster_list, 2)
	_check(
		roster_list.get_item_icon(0) == thumbnail
		and roster_list.get_item_text(0).contains(tr("TEAM_ROSTER_READY"))
		and roster_list.get_item_text(4).contains(tr("BATTLE_PICK_LOW_ENERGY")),
		"Expedition Team shows Anima art and concise readiness"
	)
	var builder_back := view.find_child("ExpeditionBuilderBack", true, false) as Button
	_check(
		builder_back.flat
		and builder_back.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and save_team.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and builder_back.get_parent() == save_team.get_parent(),
		"Expedition builder gives Back and Save equal full-width shares"
	)
	var run := {
		"id": "expedition-run",
		"status": "active",
		"zone": 1,
		"supplies": 7,
		"team_id": "expedition-team",
		"chapter_version_id": "chapter-v1",
		"available_node_ids": ["battle-1"],
		"party_state": [
			{"name": "Trail 1", "hp": 0, "max_hp": 50},
			{"name": "Trail 2", "hp": 50, "max_hp": 50},
		],
		"zone_map": {"nodes": [
			{"id": "battle-1", "kind": "battle", "depth": 1},
			{"id": "elite-2", "kind": "elite", "depth": 2},
		]},
	}
	view.set_busy(true)
	view.set_run(run)
	_check(
		str(view.call("_location_text", {})) == tr("EXPEDITION_ARENA_LOCATION") % ["Sugartrail", "1"],
		"regular Expedition arena shows the chapter title and zone"
	)
	var route_map := view.find_child("ExpeditionRouteMap", true, false) as Control
	var map_primary := view.find_child("ExpeditionMapPrimary", true, false) as Button
	var map_cover: Rect2 = route_map.call(
		"cover_rect", Vector2(720.0, 1602.0), Vector2(1000.0, 800.0)
	)
	_check(
		map_cover.size.x + 0.01 >= 1000.0
		and map_cover.size.y + 0.01 >= 800.0
		and is_equal_approx(map_cover.size.x / map_cover.size.y, 720.0 / 1602.0),
		"Expedition map cover-crops wide layouts without stretching the Sugarworks"
	)
	var enabled_route_nodes := 0
	for child in route_map.get_children():
		if child is Button and not (child as Button).disabled:
			enabled_route_nodes += 1
	_check(
		int(route_map.call("node_count")) == 2
		and enabled_route_nodes == 1
		and map_primary.disabled,
		"Expedition map enables only server-authorized previews before Enter Node"
	)
	var checkpoint := run.duplicate(true)
	checkpoint["status"] = "checkpoint"
	checkpoint["zone"] = 2
	checkpoint["checkpoint_choice_pending"] = true
	checkpoint["last_zone_reward"] = {"zone": 1, "bits": 10}
	view.set_team({})
	view.set_run(checkpoint)
	var checkpoint_choice := view.find_child("ExpeditionChoice", true, false) as Control
	var checkpoint_buttons := view.find_child("ExpeditionChoiceButtons", true, false) as VBoxContainer
	var expedition_subtitle := view.find_child("Subtitle", true, false) as Label
	_check(
		checkpoint_choice.visible
		and not expedition_subtitle.visible
		and checkpoint_buttons.get_child_count() == 2
		and (checkpoint_buttons.get_child(0) as Button).text.contains("50%")
		and (checkpoint_buttons.get_child(1) as Button).text.contains("10%"),
		"checkpoint hides lobby copy and requires Recover or one-zone Power Up"
	)
	var selected_checkpoint := {"id": ""}
	view.checkpoint_choice_requested.connect(func(option_id: String) -> void:
		selected_checkpoint["id"] = option_id
	)
	(checkpoint_buttons.get_child(0) as Button).pressed.emit()
	_check(
		selected_checkpoint.id == "recover",
		"checkpoint benefit button emits only its server-authoritative option id"
	)
	checkpoint["checkpoint_choice_pending"] = false
	checkpoint["checkpoint_choice"] = "recover"
	view.set_run(checkpoint)
	_check(
		not route_map.visible
		and map_primary.visible
		and not map_primary.disabled
		and view.call("_team_id") == "expedition-team",
		"checkpoint Start Zone unlocks only after the server commits a benefit"
	)
	view.set_team({"id": "expedition-team"})
	run["pending_node"] = {
		"id": "recovery-1",
		"kind": "recovery",
		"options": [{
			"id": "revive",
			"title_key": "EXPEDITION_NODE_RECOVERY",
			"effect": {"type": "revive_target"},
		}],
	}
	view.set_run(run)
	view.call("_choose_option", run.pending_node.options[0])
	var targets := view.find_child("ExpeditionTargetList", true, false) as ItemList
	var confirm := view.find_child("ExpeditionTargetConfirm", true, false) as Button
	var choice_abandon := view.find_child("ExpeditionChoiceAbandon", true, false) as Button
	_check(
		targets.item_count == 2
		and not targets.is_item_disabled(0)
		and targets.is_item_disabled(1)
		and confirm.disabled,
		"Expedition revive choice accepts only a knocked-out target"
	)
	_check(
		choice_abandon.visible
		and not choice_abandon.disabled
		and not (view.find_child("ExpeditionBack", true, false) as Button).visible,
		"server-committed node choice hides the inert header Back chevron"
	)
	run["pending_node"] = {
		"id": "mystery-1",
		"kind": "mystery",
		"options": [{
			"id": "supply-cache",
			"effect": {"type": "supplies", "value": 3},
		}],
	}
	run["supplies"] = 6
	view.set_run(run)
	var choice_buttons := view.find_child("ExpeditionChoiceButtons", true, false) as VBoxContainer
	var option_button := choice_buttons.get_child(0) as Button if choice_buttons.get_child_count() > 0 else null
	var choice_meta := view.find_child("ExpeditionChoiceMeta", true, false) as Label
	_check(
		choice_meta.visible
		and choice_meta.text == tr("EXPEDITION_EFFECT_SUPPLIES") % "3"
		and not choice_meta.text.contains("supply-cache"),
		"a free Mystery grant shows the Tokens found, not an internal option id"
	)
	_check(
		option_button != null
		and option_button.text == tr("EXPEDITION_CHOICE_CONTINUE")
		and not option_button.text.contains("supply-cache"),
		"a free Mystery grant uses Continue instead of a claim button"
	)
	run["pending_node"] = {
		"id": "cache-1",
		"kind": "cache",
		"options": [{
			"id": "power-up",
			"effect": {"type": "stat_boost", "stat": "atk", "value": 0.12},
		}],
	}
	view.set_run(run)
	option_button = choice_buttons.get_child(0) as Button if choice_buttons.get_child_count() > 0 else null
	_check(
		choice_meta.text.begins_with("Raise")
		and option_button != null
		and option_button.text == tr("EXPEDITION_CHOICE_CONTINUE"),
		"a free Cache grant shows the boost and Continue back to the map"
	)
	run["pending_node"] = {
		"id": "shop-1",
		"kind": "shop",
		"options": [{
			"id": "shop-heal",
			"cost_supplies": 2,
			"effect": {"type": "heal_party", "ratio": 0.25},
		}],
	}
	view.set_run(run)
	option_button = choice_buttons.get_child(0) as Button if choice_buttons.get_child_count() > 0 else null
	_check(
		choice_meta.text == tr("EXPEDITION_CHOICE_SUPPLIES") % "6"
		and option_button != null
		and option_button.text.contains("2"),
		"Trail Shop still shows the Token balance and a priced offer"
	)
	var intro_run := {
		"id": "sugarworks-fresh",
		"status": "active",
		"zone": 1,
		"nodes_completed": 0,
		"supplies": 0,
		"team_id": "expedition-team",
		"available_node_ids": ["battle-1"],
		"zone_map": {"nodes": [{"id": "battle-1", "kind": "battle", "depth": 1}]},
		"boss_seeker": _boss_seeker_payload(),
	}
	view.visible = true
	view.set_run(intro_run, {}, {"boss_seeker": _boss_seeker_loaded()})
	await process_frame
	var chapter_dialog := view.find_child("ChapterSeekerDialog", true, false) as BossSeekerDialog
	var chapter_line := chapter_dialog.find_child("SeekerLine", true, false) as Label if chapter_dialog != null else null
	_check(
		chapter_dialog != null
		and chapter_dialog.is_open()
		and chapter_line != null
		and chapter_line.text.contains("Every path"),
		"fresh Zone 1 map opens the chapter intro"
	)
	_check(view.handle_back(), "back dismisses chapter intro before leaving the map")
	await process_frame
	_check(not chapter_dialog.is_open(), "chapter intro does not reopen on the same run")
	view.set_run(intro_run)
	await process_frame
	_check(not chapter_dialog.is_open(), "resumed same-run map skips chapter intro")
	_check(
		str(view.call("_location_text", {
			"kind": "boss",
			"boss_seeker": {"display_name": "The Confectioner"},
		})) == tr("EXPEDITION_ARENA_BOSS") % "The Confectioner",
		"boss arena names the Seeker and Final Battle"
	)
	view.set_catalog([{
		"id": "chapter-by-id",
		"unlocked": true,
		"first_cleared_at": null,
		"summary": {"title": "ById Trail"},
	}])
	view.set_run({
		"id": "expedition-run-id",
		"status": "checkpoint",
		"zone": 2,
		"chapter_version_id": "chapter-by-id",
		"team_id": "expedition-team",
		"available_node_ids": [],
		"party_state": [],
		"zone_map": {"nodes": []},
	})
	_check(
		str(view.call("_location_text", {}))
		== tr("EXPEDITION_ARENA_LOCATION") % ["ById Trail", "2"],
		"Expedition chapter title matches catalog id"
	)
	# Expedition bertarung di TeamBattleView yang sama, jadi ia hanya perlu
	# meneruskan figurnya — tanpa itu Expedition diam-diam jadi satu-satunya arena
	# tanpa pemain di dalamnya.
	view.set_player_avatar(_boss_seeker_loaded())
	await process_frame
	var expedition_avatar := view.find_child("PlayerSeeker", true, false) as AnimatedSprite2D
	_check(
		expedition_avatar != null
		and expedition_avatar.sprite_frames != null
		and expedition_avatar.flip_h,
		"Expedition forwards the chosen figure into the arena it shares with Team Battle"
	)
	view.queue_free()
	await process_frame


func _test_battle_pick_sheet() -> void:
	var duel_packed := load("res://scenes/ui/battle_view.tscn") as PackedScene
	var duel := duel_packed.instantiate()
	root.add_child(duel)
	var packed := load("res://scenes/ui/battle_pick_sheet.tscn") as PackedScene
	var sheet := packed.instantiate()
	root.add_child(sheet)
	await process_frame
	var duel_result := duel.find_child("BattleResultPanel", true, false) as Control
	duel.visible = true
	duel_result.visible = true
	var tired := {
		"id": "active",
		"nickname": "Velumi",
		"status": "ready",
		"element": "spark",
		"rarity": 2,
		"care_score": 5,
		"care": {"hunger": 80.0, "energy": 10.0, "hygiene": 80.0, "bond": 0.0},
	}
	var ready := {
		"id": "ready-one",
		"nickname": "Noodl",
		"status": "ready",
		"element": "flow",
		"rarity": 1,
		"care_score": 0,
		"care": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "bond": 0.0},
	}
	sheet.open_picker([tired, ready], "active", Callable(), false)
	var list := sheet.find_child("BattlePickList", true, false) as ItemList
	var detail := sheet.find_child("BattlePickDetail", true, false) as Control
	var battle_btn := sheet.find_child("BattlePickBattleButton", true, false) as Button
	var profile_btn := sheet.find_child("BattlePickProfileButton", true, false) as Button
	var reason := sheet.find_child("BattlePickReason", true, false) as Label
	var panel := sheet.panel() as Control
	var content_scroll := sheet.find_child("ContentScroll", true, false) as ScrollContainer
	_check(sheet.visible and list != null and list.item_count == 2, "picker lists the roster")
	_check(
		duel_result != null and duel_result.visible and sheet.z_index > duel_result.z_index,
		"terminal Duel Choose Anima picker paints above the real result overlay",
	)
	_check(
		sheet.scroll_content and content_scroll != null and content_scroll.follow_focus,
		"Battle picker caps tall rosters in the shared mobile scroll viewport"
	)
	_check(
		panel.theme_type_variation == &"BottomSheetPanel"
		and list.get_theme_constant("h_separation") == 16
		and list.get_theme_constant("v_separation") == 16,
		"Battle picker follows the shared sheet surface and roster spacing"
	)
	_check(
		list.get_item_text(0).find(tr("BATTLE_PICK_LOW_ENERGY")) >= 0,
		"ineligible row shows a short Low Energy reason"
	)
	sheet._on_item_selected(0)
	_check(
		detail.visible and battle_btn.disabled and reason.visible
		and reason.text == tr("BATTLE_PICK_LOW_ENERGY"),
		"low-energy detail keeps View Profile and dims Battle"
	)
	_check(not profile_btn.disabled, "ineligible Anima can still open View Profile")
	sheet._on_item_selected(1)
	_check(
		not battle_btn.disabled and battle_btn.text == tr("BATTLE_START"),
		"eligible detail enables Battle"
	)
	_check(sheet.handle_back() and not detail.visible and sheet.visible, "back from detail returns to the list")
	sheet.open_picker([ready], "ready-one", Callable(), true)
	sheet._on_item_selected(0)
	_check(battle_btn.text == tr("BATTLE_TRAIN"), "training lobby labels the sheet action Train")
	_check(sheet.handle_back() and sheet.visible and not detail.visible, "back from detail returns to the list")
	_check(sheet.handle_back(), "back from the list starts closing the picker")
	await create_timer(0.30).timeout
	_check(not sheet.visible, "back from the list closes the picker")

	# The real report: a nine-Anima roster showed four with no way to reach the
	# rest, and trying to drag picked a card instead of scrolling. Opened for
	# real, with a real thumbnail provider -- without icons the rows are short
	# text, nine of them genuinely fit the window, and the bug cannot reproduce.
	var many: Array = []
	for index in 9:
		many.append({
			"id": "many-%d" % index,
			"nickname": "Anima %d" % index,
			"status": "ready",
			"element": "flow",
			"rarity": 1,
			"care_score": 0,
			"care": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "bond": 0.0},
		})
	var swatch := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	swatch.fill(Color.RED)
	var thumb := ImageTexture.create_from_image(swatch)
	var provider := func(_row: Dictionary) -> Texture2D: return thumb
	sheet.open_picker(many, "many-0", provider, false)
	await create_timer(0.40).timeout
	_check(
		sheet.visible and list.item_count == 9,
		"the picker lists a nine-Anima roster in full"
	)
	# The complaint was a picker that opened at roughly a quarter of the screen
	# with the roster stuck behind a stub-sized window, so what matters is that
	# the sheet claims real height and that every row is reachable -- whether it
	# fits outright or needs a scroll depends on the device.
	var picker_panel: Control = sheet.panel()
	var host_height: float = sheet.get_viewport_rect().size.y
	_check(
		picker_panel != null and picker_panel.size.y > host_height * 0.5,
		"the picker fills the screen instead of opening as a quarter-height stub"
	)
	var last_row_end := list.get_item_rect(list.item_count - 1).end.y
	_check(
		last_row_end <= list.size.y + 1.0
		or list.get_v_scroll_bar().max_value > list.get_v_scroll_bar().page,
		"every roster row is reachable, on screen or by scrolling"
	)
	# The height the sheet hands the list has to be measured with the minimums
	# zeroed first. Subtracting the list's own contribution from an already
	# list-inclusive panel minimum feeds each result into the next: measured, it
	# grew the list to 1698 px on a 1602 px screen, which made the sheet's OWN
	# scroll overflow and sent the grid sliding off the top the moment a finger
	# touched it. So: bounded by the host, no rogue scroll outside the list, and
	# stable no matter how many times the sheet re-fits.
	_check(
		list.custom_minimum_size.y <= host_height,
		"the list window never exceeds the screen it has to fit inside"
	)
	var sheet_scroll := sheet.find_child("ContentScroll", true, false) as ScrollContainer
	_check(
		sheet_scroll != null
		and sheet_scroll.get_v_scroll_bar().max_value <= sheet_scroll.get_v_scroll_bar().page + 1.0,
		"only the list scrolls -- the sheet's own scroll has nothing left to run away with"
	)
	var settled_height := list.custom_minimum_size.y
	for _refit in 3:
		sheet.fit_to_content()
		await process_frame
	_check(
		is_equal_approx(list.custom_minimum_size.y, settled_height),
		"re-fitting the sheet does not grow the list a little further each time"
	)
	# Dragging across the roster must scroll it, not open a detail page.
	var was_emulating := Input.is_emulating_touch_from_mouse()
	Input.set_emulate_touch_from_mouse(true)
	var from := list.get_global_rect().position + list.get_item_rect(0).get_center()
	var down := InputEventMouseButton.new()
	down.position = from
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	list.get_viewport().push_input(down, true)
	await process_frame
	for step in range(1, 6):
		var motion := InputEventMouseMotion.new()
		motion.position = from - Vector2(0.0, 24.0 * step)
		motion.relative = Vector2(0.0, -24.0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		list.get_viewport().push_input(motion, true)
		await process_frame
	var up := InputEventMouseButton.new()
	up.position = from - Vector2(0.0, 120.0)
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	list.get_viewport().push_input(up, true)
	await process_frame
	_check(
		not detail.visible,
		"scrolling the roster does not open a detail page for the card under the thumb"
	)
	Input.set_emulate_touch_from_mouse(was_emulating)
	sheet.queue_free()
	duel.queue_free()
	await process_frame


func _test_collection_routes_are_explicit() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		source.find("_collection_view.atlas_requested.connect(_open_atlas)") >= 0
		and source.find("_atlas_view.collection_requested.connect(_open_collection)") >= 0,
		"Collection and Atlas tabs share the existing shell destinations"
	)
	var profile_start := source.find("func _show_collection_profile")
	var summon_start := source.find("func _summon_collection_anima")
	var summon_end := source.find("\n\nfunc _open_scan", summon_start)
	var profile_body := source.substr(
		profile_start, summon_start - profile_start
	) if profile_start >= 0 and summon_start > profile_start else ""
	var summon_body := source.substr(
		summon_start, summon_end - summon_start
	) if summon_start >= 0 and summon_end > summon_start else ""
	_check(
		profile_body.find("_switch_destination(ANIMA_PROFILE_DEST, row)") >= 0,
		"View Profile opens the selected Anima without summoning it"
	)
	_check(
		summon_body.find("_switch_destination(BottomNav.HOME)") >= 0,
		"Summon routes the selected companion to Home"
	)
	_check(
		summon_body.find("begin_care(anima_id, \"summon\")") >= 0
		and summon_body.find("begin_care") < summon_body.find("GameState.remember_anima"),
		"Summon claims the companion on the server before replacing Home"
	)
	_check(
		summon_body.find("await _prepare_anima_art") < summon_body.find("GameState.remember_anima"),
		"Summon prepares art before replacing the active companion"
	)
	var switch_start := source.find("func _switch_destination(")
	var switch_end := source.find("\nfunc _active_view(", switch_start)
	var switch_body := (
		source.substr(switch_start, switch_end - switch_start)
		if switch_start >= 0 and switch_end > switch_start
		else ""
	)
	_check(
		switch_body.find("_bottom_nav.mark_overlay_active(overlay_base)") >= 0,
		"opening an overlay destination still updates BottomNav instead of leaving its prior tab stale"
	)


## `gallery/publish` menolak guest sebelum menyentuh Anima-nya, jadi tap yang
## dijawab toast menawarkan sesuatu yang tidak pernah bisa terjadi. Guest wajib
## mendapat penjelasan plus jalan keluarnya, dan jalan keluarnya wajib pilihan
## sign-in bersama — bukan transfer langsung yang melewati default amannya.
func _test_atlas_publish_offers_sign_in() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var toggle := _func_body(source, "func _toggle_gallery_publish(")
	var guest := toggle.find("GameState.is_anonymous()")
	var consent := toggle.find("&\"atlas_publish\"")
	_check(
		guest >= 0
		and toggle.find("ATLAS_PUBLISH_SIGN_IN_BODY") > guest
		and consent > guest,
		"a Guest tapping Publish is told what it does instead of the consent it cannot give"
	)
	var confirmed := _func_body(source, "func _modal_confirmed(")
	var context := confirmed.find("&\"atlas_publish_signin\"")
	_check(
		context >= 0 and confirmed.find("_show_sign_in_confirmation()") > context,
		"that dialog hands off to the shared sign-in choice instead of dead-ending"
	)
	_check(
		toggle.find("\"uid\": GameState.uid()") > guest
		and _func_body(source, "func _on_auth_succeeded(").find(
			"_resume_pending_publish()"
		) >= 0,
		"the Publish tap survives the OAuth round trip carrying the UID that made it"
	)
	# Transfer justru didefinisikan sebagai UID yang tidak berubah, jadi mencocokkan
	# UID menyatakan "pemilik yang sama" secara langsung; menyimpulkannya dari roster
	# benar hari ini tapi diam kalau urutan muat berubah. Konsumsi wajib mendahului
	# pagar, kalau tidak Keep Guest Separate meninggalkan intent terkokang untuk
	# sign-in berikutnya.
	var resume := _func_body(source, "func _resume_pending_publish(")
	var consumed := resume.find("_publish_after_sign_in = {}")
	_check(
		consumed >= 0
		and resume.find("GameState.is_anonymous()") > consumed
		and resume.find("!= GameState.uid()") > consumed
		and resume.find("_roster_row(anima_id)") > consumed,
		"and is consumed before its guards, so a separate account cannot inherit it"
	)
	var commit := _func_body(source, "func _commit_atlas_publish(")
	_check(
		commit.find("res.error == \"GALLERY_MODERATION_REJECTED\"") >= 0
		and commit.find("\"rejected\": true") >= 0,
		"a moderation rejection becomes a persistent disabled Profile state"
	)
	var status_parse := _func_body(source, "func _gallery_status_from_response(")
	_check(
		status_parse.find("moderation_rejected") >= 0
		and status_parse.find("\"rejected\": moderation_rejected") >= 0,
		"reopening that Profile restores the same rejected state from the server"
	)


## Keep Guest Separate meninggalkan Anima guest di akun yang tidak lagi terlihat,
## jadi urutan tombolnya ikut isi roster. Yang berbahaya bukan urutannya melainkan
## hanyutnya: kalau slot dibalik tanpa handler-nya, Keep Separate mentransfer akun.
func _test_sign_in_choice_follows_guest_roster() -> void:
	var script: GDScript = load("res://scripts/scan_flow.gd")
	_check(
		script.sign_in_choice_moves_guest("primary", true)
		and not script.sign_in_choice_moves_guest("secondary", true)
		and script.sign_in_choice_moves_guest("secondary", false)
		and not script.sign_in_choice_moves_guest("primary", false),
		"the sign-in slot that runs Move is the one holding the Move label"
	)
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var confirm := _func_body(source, "func _show_sign_in_confirmation(")
	var flag := confirm.find(
		"_sign_in_move_first = not _roster.is_empty() or _guest_scan_locked()"
	)
	_check(
		flag >= 0,
		"the button order follows the roster, and a failed load still warns via the scan lock"
	)
	_check(
		confirm.find("if _busy:\n\t\t_say_warning(tr(\"SEEKER_SWITCH_BLOCKED\"), true)") >= 0,
		"a sign-in tap that lands while the shell is busy answers instead of doing nothing"
	)
	_check(
		confirm.find("var move_label := tr(\"SEEKER_MOVE_GUEST_PROGRESS\")") >= 0
		and confirm.find("var separate_label := tr(\"SEEKER_KEEP_GUEST_SEPARATE\")") >= 0
		and confirm.find("move_label if _sign_in_move_first else separate_label") >= 0,
		"a Guest holding an Anima sees Move Guest Progress first"
	)
	_check(
		confirm.find("SEEKER_SIGN_IN_CHOICE_BODY_ANIMA") > flag,
		"and is told the Anima stays behind on the guest account"
	)
	_check(
		_func_body(source, "func _modal_choice_selected(").find(
			"sign_in_choice_moves_guest(choice, _sign_in_move_first)"
		) >= 0,
		"the handler reads that same order instead of assuming a fixed one"
	)


func _test_collection_bottom_sheet() -> void:
	var packed := load("res://scenes/ui/collection_view.tscn") as PackedScene
	var collection := packed.instantiate()
	root.add_child(collection)
	await process_frame
	var collection_tab := collection.find_child(
		"CollectionCollectionTab", true, false
	) as Button
	var synthesis_tab := collection.find_child(
		"CollectionSynthesisTab", true, false
	) as Button
	var atlas_tab := collection.find_child("CollectionAtlasTab", true, false) as Button
	_check(
		collection_tab != null
		and synthesis_tab != null
		and atlas_tab != null
		and collection_tab.button_pressed
		and not synthesis_tab.button_pressed
		and not atlas_tab.button_pressed
		and collection_tab.custom_minimum_size.y >= 72.0
		and synthesis_tab.custom_minimum_size.y >= 72.0
		and atlas_tab.custom_minimum_size.y >= 72.0,
		"Collection exposes touch-safe Collection, Synthesis, and Atlas tabs with Collection active"
	)
	var atlas_requests := [0]
	var synthesis_requests := [0]
	collection.atlas_requested.connect(func() -> void: atlas_requests[0] += 1)
	collection.synthesis_requested.connect(func(_p: Dictionary) -> void: synthesis_requests[0] += 1)
	atlas_tab.pressed.emit()
	_check_eq(atlas_requests[0], 1, "Collection Atlas tab emits its shell navigation intent")
	synthesis_tab.pressed.emit()
	_check_eq(synthesis_requests[0], 1, "Collection Synthesis tab emits its shell navigation intent")
	var row := {
		"id": "sheet-test",
		"nickname": "Velumi",
		"element": "spark",
		"stage": 1,
		"rarity": 4,
		"base_stats": {"hp": 74, "atk": 62, "def": 58, "spd": 81, "special": 77},
		"care": {"hunger": 68, "energy": 84, "hygiene": 57, "bond": 72},
	}
	var rows: Array[Dictionary] = [row]
	collection.set_rows(rows, "", func(_row: Dictionary) -> Texture2D: return null)
	_preview_requests = 0
	collection.preview_requested.connect(_capture_preview_request)
	collection.show_preview(row)
	await process_frame
	var overlay := collection.find_child("CollectionSheetOverlay", true, false) as Control
	var summon := collection.find_child("CollectionSummonButton", true, false) as Button
	var profile := collection.find_child("CollectionProfileButton", true, false) as Button
	var hp := collection.find_child("SheetStatHp", true, false) as Label
	var hunger := collection.find_child("SheetCareHunger", true, false) as ProgressBar
	var skeleton := collection.find_child("ConditionSkeleton", true, false) as Control
	var care_rows := collection.find_child("CareRows", true, false) as Control
	_check(overlay != null and overlay.visible, "selecting an Anima opens the bottom sheet immediately")
	var sheet_panel := collection.find_child("CollectionSheetPanel", true, false) as Control
	var content_scroll := collection.find_child("ContentScroll", true, false) as ScrollContainer
	_check(
		sheet_panel != null
		and is_equal_approx(sheet_panel.size.y, sheet_panel.get_combined_minimum_size().y),
		"Collection sheet height follows its content"
	)
	_check(
		content_scroll != null
		and sheet_panel.theme_type_variation == &"BottomSheetPanel"
		and sheet_panel.size.y <= overlay.size.y * 0.92 + 1.0,
		"Collection details keep a bounded, scroll-safe bottom-sheet layout"
	)
	var handle := collection.find_child("HandleCenter", true, false) as Control
	_check(
		handle != null and handle.custom_minimum_size.y >= TOUCH_MIN,
		"sheet handle exposes a swipe target"
	)
	var sheet_source := FileAccess.get_file_as_string("res://scripts/ui_bottom_sheet.gd")
	_check(
		sheet_source.find("DISMISS_PX") >= 0
		and sheet_source.find("_on_drag_input") >= 0
		and sheet_source.find("close()") >= 0,
		"sheet swipe follows the finger and dismisses past the threshold"
	)
	_check(
		skeleton != null and skeleton.visible and care_rows != null and not care_rows.visible,
		"uncached care sync replaces stale meters with a visible skeleton"
	)
	_check_eq(hunger.value, 0.0, "loading state clears the previous Anima meter value")
	_check(summon.disabled, "Summon waits for authoritative care while the skeleton is visible")

	var synced_row: Dictionary = row.duplicate(true)
	synced_row["care"]["hunger"] = 42.0
	_check(
		collection.apply_care_sync(synced_row, collection.selected_revision()),
		"matching care response updates the open sheet"
	)

	_check(skeleton != null and not skeleton.visible and care_rows.visible, "care sync reveals real meters")
	await create_timer(0.45).timeout
	_check_eq(hp.text, "74", "bottom sheet exposes base stats at a glance")
	_check_eq(hunger.value, 42.0, "bottom sheet exposes authoritative care at a glance")
	_check(summon != null and not summon.disabled, "non-active Anima can be summoned")
	_check_eq(_preview_requests, 1, "first preview requests one authoritative care sync")

	_requested_profile_id = ""
	_requested_summon_id = ""
	collection.profile_requested.connect(_capture_profile_request)
	collection.summon_requested.connect(_capture_summon_request)
	profile.pressed.emit()
	_check_eq(_requested_profile_id, "sheet-test", "View Profile emits the selected row")
	collection.show_preview(row)
	await process_frame
	_check_eq(_preview_requests, 1, "care sync is cached for the current Collection visit")
	summon.pressed.emit()
	_check_eq(_requested_summon_id, "sheet-test", "Summon emits the selected row")
	_check(_requested_summon_synced, "fixture care is marked authoritative")
	_check_eq(_requested_summon_hunger, 42.0, "Summon uses the cached authoritative row")

	collection.set_rows(rows, "sheet-test", func(_row: Dictionary) -> Texture2D: return null)
	collection.show_preview(row, false)
	await process_frame
	_check(summon.disabled, "active companion cannot be summoned twice")
	var old_revision: int = collection.selected_revision()
	collection.close_sheet()
	_check(
		not collection.apply_care_sync(row, old_revision),
		"care response is ignored after its sheet revision closes"
	)

	# Badge level digambar di luar layout, jadi satu-satunya cara ia salah tanpa
	# suara adalah scroll: `get_item_rect()` terukur mengembalikan koordinat
	# konten, bukan koordinat yang terlihat, sehingga badge bisa tertinggal di
	# tempatnya sementara kartunya jalan.
	var locale := root.get_node("LocaleManager")
	var badge_rows: Array[Dictionary] = []
	for index in 24:
		badge_rows.append({
			"id": "badge-%d" % index,
			"nickname": "Badge %d" % index,
			"element": "spark",
			"care_score": 250 if index == 1 else 0,
		})
	collection.set_rows(badge_rows, "", func(_row: Dictionary) -> Texture2D: return null)
	await process_frame
	_check_eq(
		str(collection.call("_badge_text", 0)),
		str(locale.call("level_label", 1)),
		"every Collection card carries its own Lv. badge"
	)
	_check_eq(
		str(collection.call("_badge_text", 1)),
		str(locale.call("level_label", CareRules.level_from_exp(250))),
		"the Lv. badge reads stored EXP, not the row order"
	)
	var badge_bar := (
		collection.find_child("AnimaList", true, false) as ItemList
	).get_v_scroll_bar()
	var badge_top: float = (collection.call("_badge_origin", 0) as Vector2).y
	badge_bar.value = badge_bar.max_value
	_check(
		badge_bar.max_value > 0.0
		and is_equal_approx(
			badge_top - (collection.call("_badge_origin", 0) as Vector2).y,
			badge_bar.max_value
		),
		"the Lv. badge travels with its card when the grid scrolls"
	)
	collection.queue_free()
	await process_frame


## Pagar RC4/RC5 dari docs/designs/2026-08-26-collection-ghost-art-cards.md:
## set_rows() harus tahan terhadap id kembar/kosong/"<null>". Perlindungan
## re-entrancy RC4 sendiri hidup satu lapis di atas (scan_flow.gd men-defer
## _run_thumbnail_backfill()/_populate_collection() supaya thumbnail_provider
## tidak pernah lagi bisa memanggil set_rows() ini secara sinkron) -- lihat
## pagar grep di bawah, bukan diuji di sini dengan re-entrancy paksa lewat
## CollectionView, sebab set_rows() sendiri sengaja tidak lagi punya flag
## re-entrancy: flag begitu bisa nyangkut permanen (set_rows berhenti
## menggambar apa pun) kalau satu baris di tengah rendering error, dan itu
## risiko lebih buruk daripada re-entrancy yang sudah ditutup di sumbernya.
func _test_collection_row_hygiene() -> void:
	var packed := load("res://scenes/ui/collection_view.tscn") as PackedScene
	var collection := packed.instantiate()
	root.add_child(collection)
	await process_frame

	var dup_rows: Array[Dictionary] = [
		{"id": "hygiene-a", "nickname": "A", "element": "spark"},
		{"id": "", "nickname": "Empty", "element": "spark"},
		{"id": "<null>", "nickname": "Nullish", "element": "spark"},
		{"id": "hygiene-a", "nickname": "A dup", "element": "spark"},
		{"id": "hygiene-b", "nickname": "B", "element": "spark"},
	]
	collection.set_rows(dup_rows, "", func(_row: Dictionary) -> Texture2D: return null)
	await process_frame
	var list: ItemList = collection.find_child("AnimaList", true, false) as ItemList
	_check_eq(
		list.item_count, 2,
		"set_rows dedupes by id and rejects empty/\"<null>\" ids (RC5 null guard)"
	)

	# Reproduksi bug "Anima menghilang dari Collection satu per satu setelah
	# Summon" (dilaporkan pemain 2026-08-27): set_rows() tidak menduplikasi
	# array `rows` yang diterima, jadi _row_with_id() mengembalikan Dictionary
	# ASLI milik pemanggil (== _roster di scan_flow.gd) secara referensi.
	# show_preview() lalu set_rows() lagi meng-alias _selected_row ke row itu,
	# dan begin_visit() sebelumnya memanggil _selected_row.clear() -- mutasi
	# in-place yang ikut mengosongkan row ASLI si pemanggil.
	var caller_owned_rows: Array[Dictionary] = [
		{"id": "alias-guard", "nickname": "AliasGuard", "element": "spark"},
	]
	collection.set_rows(caller_owned_rows, "", func(_row: Dictionary) -> Texture2D: return null)
	await process_frame
	collection.show_preview(caller_owned_rows[0], false)
	await process_frame
	# Reconciliation block in set_rows() aliases _selected_row to the row
	# passed in -- fire it again while the sheet is open, same as a repaint
	# during a Summon would.
	collection.set_rows(caller_owned_rows, "", func(_row: Dictionary) -> Texture2D: return null)
	await process_frame
	collection.begin_visit()
	await process_frame
	_check_eq(
		str(caller_owned_rows[0].get("id", "")), "alias-guard",
		"begin_visit() must not clear the caller's own roster Dictionary through an aliased _selected_row"
	)

	collection.queue_free()
	await process_frame

	var view_source := FileAccess.get_file_as_string("res://scripts/collection_view.gd")
	_check(
		view_source.find("var _populating") < 0,
		"CollectionView no longer carries a re-entrancy latch that can wedge stuck"
	)
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		flow_source.find("_thumbnail_backfill_inflight.erase(art_key)") >= 0,
		"backfill in-flight entries are erased on completion, not left as a permanent latch"
	)
	var queue_start := flow_source.find("func _queue_thumbnail_backfill(")
	var queue_end := flow_source.find("func _run_thumbnail_backfill(")
	var queue_body := (
		flow_source.substr(queue_start, queue_end - queue_start)
		if queue_start >= 0 and queue_end > queue_start
		else ""
	)
	_check(
		queue_start >= 0 and queue_end > queue_start
		and queue_body.find("_run_thumbnail_backfill.call_deferred()") >= 0,
		"the thumbnail backfill drain is deferred so it can never be entered from inside set_rows()"
	)
	var queue_code_start := queue_body.find("if not _thumbnail_backfill_running:")
	var queue_code := queue_body.substr(queue_code_start) if queue_code_start >= 0 else ""
	_check(
		queue_code_start >= 0
		and queue_code.find("_thumbnail_backfill_running = true") >= 0
		and queue_code.find("_thumbnail_backfill_running = true") < queue_code.find(".call_deferred()"),
		"the running flag is set synchronously before scheduling the deferred drain -- " +
		"otherwise several rows needing backfill in one set_rows() pass each schedule their own coroutine"
	)
	var dispatch_start := flow_source.find("func _dispatch_summon(")
	var dispatch_body := flow_source.substr(dispatch_start, 260)
	_check(
		dispatch_start >= 0
		and dispatch_body.find("_summon_in_flight = false") < dispatch_body.find("_summon_settled.emit()"),
		"_dispatch_summon resets _summon_in_flight before emitting _summon_settled"
	)
	var activate_start := flow_source.find("func _activate_anima(")
	var activate_end := flow_source.find("func _activate_anima_inner(")
	var activate_body := flow_source.substr(activate_start, activate_end - activate_start)
	_check(
		activate_start >= 0 and activate_end > activate_start
		and activate_body.count("_set_busy(false)") == 1,
		"_activate_anima has exactly one teardown point for _busy"
	)


func _test_atlas_view() -> void:
	var packed := load("res://scenes/ui/atlas_view.tscn") as PackedScene
	var view := packed.instantiate() as Control
	view.custom_minimum_size = Vector2(720.0, 1280.0)
	root.add_child(view)
	view.visible = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var sheet := view.find_child("AtlasDetailSheet", true, false) as UiBottomSheet
	_check(
		sheet != null
		and is_equal_approx(sheet.anchor_right, 1.0)
		and is_equal_approx(sheet.anchor_bottom, 1.0)
		and sheet.scroll_content,
		"Atlas detail sheet is full-rect and scrolls tall mobile profiles"
	)
	var atlas_title := view.find_child("AtlasTitle", true, false) as Label
	var atlas_subtitle := view.find_child("AtlasSubtitle", true, false) as Label
	_check(
		atlas_title != null and atlas_subtitle != null,
		"Atlas header includes title and subtitle for unified UI consistency"
	)
	var atlas_collection_tab := view.find_child("AtlasCollectionTab", true, false) as Button
	var atlas_synthesis_tab := view.find_child("AtlasSynthesisTab", true, false) as Button
	var atlas_tab := view.find_child("AtlasAtlasTab", true, false) as Button
	_check(
		atlas_collection_tab != null
		and atlas_synthesis_tab != null
		and atlas_tab != null
		and not atlas_collection_tab.button_pressed
		and not atlas_synthesis_tab.button_pressed
		and atlas_tab.button_pressed
		and atlas_collection_tab.custom_minimum_size.y >= 72.0
		and atlas_synthesis_tab.custom_minimum_size.y >= 72.0
		and atlas_tab.custom_minimum_size.y >= 72.0,
		"Atlas exposes the same touch-safe tab trio with Atlas active"
	)
	var collection_requests := [0]
	view.collection_requested.connect(func() -> void: collection_requests[0] += 1)
	atlas_collection_tab.pressed.emit()
	_check_eq(collection_requests[0], 1, "Atlas Collection tab emits its shell navigation intent")
	_check(view.has_method("_make_card"), "Anima Atlas scene exposes the AtlasView contract")
	_check(view.has_method("show_demo"), "Anima Atlas exposes a no-network visual QA path")
	for node_name: String in ["AtlasAll", "AtlasScanned", "AtlasExpedition", "AtlasDuel"]:
		_check(view.find_child(node_name, true, false) is Button, "%s filter exists" % node_name)
	var atlas_grid := view.find_child("AtlasGrid", true, false) as GridContainer
	var load_more := view.find_child("AtlasLoadMore", true, false) as Button
	_check(
		atlas_grid != null and atlas_grid.columns >= 3,
		"Atlas keeps at least the compact three-column grid"
	)
	var final_page_entries: Array[Dictionary] = [{
		"form_id": "final-page-form",
		"discovered": true,
		"display_name": "Final Sprig",
		"element": "plant",
		"stage": 1,
	}]
	view.set("_entries", final_page_entries)
	view.set("_cursor", "")
	view.call("_present_entries")
	await process_frame
	_check(
		atlas_grid.get_child_count() == 1 and not load_more.visible,
		"Atlas keeps its final entries while hiding Load More after the cursor ends"
	)
	var atlas_source := FileAccess.get_file_as_string("res://scripts/atlas_view.gd")
	var fetch_page := _func_body(atlas_source, "func _fetch_page(")
	_check(
		fetch_page.find("typeof(next_cursor) == TYPE_STRING") >= 0
		and fetch_page.find("if batch.is_empty():\n\t\t_cursor = \"\"") >= 0,
		"Atlas normalizes a null or empty final cursor instead of requesting a blank page"
	)
	var discovered := view.call("_make_card", {
		"form_id": "form-discovered",
		"discovered": true,
		"display_name": "Sprig",
		"element": "plant",
		"secondary_element": "earth",
		"stage": 2,
	}) as Button
	var silhouette := view.call("_make_card", {
		"form_id": "form-hidden",
		"discovered": false,
		"display_name": "Hidden Name",
		"source_kind": "expedition",
	}) as Button
	_check(not discovered.disabled, "discovered Atlas forms open their profile")
	_check(silhouette.disabled, "undiscovered Expedition forms stay silhouette-only")
	var discovered_column := discovered.get_child(0) as VBoxContainer
	var discovered_portrait := discovered_column.get_child(0) as TextureRect
	_check(
		discovered.custom_minimum_size.x <= 208.0
		and discovered.custom_minimum_size.y <= 280.0
		and discovered_portrait.custom_minimum_size.x <= 196.0,
		"three-column Atlas cards keep their portrait inside the mobile grid"
	)
	view.call("_set_card_loading", discovered_portrait, true)
	var loading_material := discovered_portrait.material as ShaderMaterial
	_check(
		loading_material != null
		and loading_material.shader == load("res://shaders/guard_shimmer.gdshader"),
		"opening an Atlas form shimmers the selected Anima image"
	)
	view.call("_set_card_loading", discovered_portrait, false)
	_check(discovered_portrait.material == null, "Atlas shimmer restores the card material after loading")
	_check(
		(discovered_column.get_child(1) as Label).text == "Sprig",
		"Atlas card shows the generated form name"
	)
	var discovered_meta_label := discovered_column.get_child(2) as Label
	var discovered_meta := discovered_meta_label.text
	_check(
		discovered_meta_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART
		and discovered_meta.find("Plant · Stone") >= 0
		and discovered_meta.find("Adult") < 0,
		"Atlas grid keeps element identity but leaves form stage to detail"
	)
	var hidden_column := silhouette.get_child(0) as VBoxContainer
	var hidden_portrait := hidden_column.get_child(0) as TextureRect
	_check(hidden_portrait.material is ShaderMaterial, "undiscovered Expedition art uses a true silhouette shader")
	_check(
		(hidden_column.get_child(1) as Label).text == "???",
		"Expedition silhouette does not reveal its name"
	)
	var detail_entry := {
		"display_name": "Sprig",
		"stage": 2,
		"subject_kind": "object",
		"element": "plant",
		"secondary_element": "earth",
		"rarity": 3,
		"body_height_cm": 88,
		"base_stats": {"hp": 51, "atk": 52, "def": 53, "spd": 54, "special": 55},
		"strike_name": "Leaf Jab",
		"surge_name": "Root Rise",
		"owner_name": "AtlasOwner",
		"owner_avatar": "masculine",
		"encounter_count": 2,
		"nickname": "PrivateNickname",
		"care": {"hunger": 1},
		"can_report": true,
	}
	view.call("_present_detail", detail_entry)
	await process_frame
	# Produksi selalu present lalu open, dan Godot tidak me-layout subtree yang
	# tak terlihat: selama sheet tertutup SETIAP label autowrap di dalamnya
	# melapor lebar 1 px dan tinggi minimum sampah (terukur: AtlasDetailIdentity
	# 717 px juga). Ukuran hanya boleh diperiksa sesudah sheet benar-benar buka.
	await sheet.open()
	await _await_juice_settled(sheet)
	var portrait := view.find_child("AtlasDetailPortrait", true, false) as TextureRect
	var about := view.find_child("AtlasAboutPanel", true, false) as PanelContainer
	var combat := view.find_child("AtlasCombatPanel", true, false) as PanelContainer
	var discovery := view.find_child("AtlasDiscoveryPanel", true, false) as PanelContainer
	_check(
		portrait != null and portrait.custom_minimum_size.x <= 240.0,
		"Atlas detail keeps its identity hero compact"
	)
	_check(
		about != null and about.theme_type_variation == &"HudSurface"
		and combat != null and combat.theme_type_variation == &"HudSurface"
		and discovery != null and discovery.theme_type_variation == &"HudSurface",
		"Atlas detail groups Traits, Attributes, and Discovery in shared card chrome"
	)
	var traits_grid := view.find_child("AtlasTraitsGrid", true, false) as GridContainer
	var stats_grid := view.find_child("AtlasStatsGrid", true, false) as GridContainer
	var moves_grid := view.find_child("AtlasMovesGrid", true, false) as GridContainer
	_check(traits_grid != null and traits_grid.columns == 2, "Atlas traits use a readable two-column grid")
	_check(stats_grid != null and stats_grid.columns == 5, "Atlas attributes remain glanceable in one row")
	_check(moves_grid != null and moves_grid.columns == 2, "Atlas Attack and Special are separate values")
	_check_eq(
		(view.find_child("AtlasOwnerValue", true, false) as Label).text,
		"AtlasOwner",
		"Duel Atlas detail includes the current Seeker name"
	)
	var owner_cell := view.find_child("AtlasOwnerCell", true, false) as PanelContainer
	var discovery_grid := view.find_child("AtlasDiscoveryGrid", true, false) as GridContainer
	var owner_value := view.find_child("AtlasOwnerValue", true, false) as Label
	var owner_avatar := view.find_child("AtlasOwnerAvatar", true, false) as TextureRect
	await process_frame
	_check(
		owner_avatar != null
		and owner_avatar.visible
		and owner_cell.is_ancestor_of(owner_avatar)
		and owner_avatar.get_parent() == owner_value.get_parent(),
		"the owner figure stands beside the Seeker name it belongs to, in the same cell"
	)
	_check(
		owner_avatar != null
		and owner_avatar.texture == SeekerRoster.portrait("masculine")
		and owner_avatar.expand_mode == TextureRect.EXPAND_IGNORE_SIZE
		and owner_avatar.get_combined_minimum_size().x <= 64.0,
		"another Seeker's figure is drawn small from bundled roster art, with no fetch of its own"
	)
	# Sel Seeker berbagi baris dengan sel Encounters di sheet yang diukur dari
	# kontennya, jadi kedua sumbu figurnya dipagari. Tinggi adalah yang penting:
	# terukur, nama pemilik yang masuk HBox tanpa lebar wrap sendiri menyusut ke
	# 1 px, membungkus per karakter, dan menumbuhkan sheet dari 1.126 px ke
	# 1.801 px — sementara lebar selnya tetap terlihat sehat.
	var owner_min := owner_cell.get_combined_minimum_size()
	view.call("_present_detail", detail_entry)
	view.call("_present_detail", detail_entry)
	await process_frame
	_check(
		owner_min.x <= 320.0 and owner_min.y <= 200.0
		and owner_value.get_line_count() <= 2
		and owner_cell.get_combined_minimum_size() == owner_min,
		"the Seeker cell with its figure stays a cell, at one stable size, %s" % owner_min
	)
	detail_entry["owner_avatar"] = "figure-from-a-newer-server"
	view.call("_present_detail", detail_entry)
	_check(
		owner_avatar.visible
		and owner_avatar.texture == SeekerRoster.portrait(SeekerRoster.DEFAULT_SLUG),
		"a slug this build does not know falls back to the default figure, not an empty slot"
	)
	detail_entry["owner_name"] = null
	view.call("_present_detail", detail_entry)
	_check(
		owner_cell != null
		and not owner_cell.visible
		and discovery_grid != null
		and discovery_grid.columns == 1,
		"Atlas detail omits the Seeker field when the API returns null"
	)
	detail_entry["owner_name"] = "The Confectioner"
	detail_entry["owner_avatar"] = null
	view.call("_present_detail", detail_entry)
	_check(
		owner_cell.visible
		and (view.find_child("AtlasOwnerValue", true, false) as Label).text
			== "The Confectioner",
		"special Expedition Anima show their authored Boss Seeker"
	)
	_check(
		not owner_avatar.visible and owner_avatar.texture == null,
		"a Boss Seeker keeps its own chapter art instead of borrowing a roster figure"
	)
	_check_eq(
		(view.find_child("AtlasStrikeValue", true, false) as Label).text,
		"Leaf Jab",
		"Atlas Attack shows its generated move name"
	)
	var report := view.find_child("AtlasReportButton", true, false) as Button
	_check(
		report != null and report.flat and report.custom_minimum_size.y >= TOUCH_MIN,
		"Atlas Report is a touch-safe secondary action"
	)
	view.set("_selected", {"entry_id": "atlas-entry-report-test", "can_report": true})
	report.pressed.emit()
	await process_frame
	var report_sheet := view.find_child("AtlasReportSheet", true, false) as UiBottomSheet
	_check(
		report_sheet != null and report_sheet.visible,
		"tapping Report opens a dedicated category sheet instead of reporting instantly"
	)
	await _await_juice_settled(sheet)
	_check(
		not sheet.visible,
		"opening the report category sheet closes the entry detail sheet behind it"
	)
	var category_keys := {
		"AtlasReportCategoryCharacter": "ATLAS_REPORT_CATEGORY_CHARACTER",
		"AtlasReportCategorySexual": "ATLAS_REPORT_CATEGORY_SEXUAL",
		"AtlasReportCategoryGore": "ATLAS_REPORT_CATEGORY_GORE",
		"AtlasReportCategoryHate": "ATLAS_REPORT_CATEGORY_HATE",
		"AtlasReportCategoryOther": "ATLAS_REPORT_CATEGORY_OTHER",
	}
	var categories_ok := true
	for node_name in category_keys:
		var category_button := report_sheet.find_child(node_name, true, false) as Button
		if (
			category_button == null
			or category_button.text != tr(category_keys[node_name])
			or category_button.custom_minimum_size.y < TOUCH_MIN
		):
			categories_ok = false
	_check(
		categories_ok,
		"the report sheet offers all five touch-safe categories, replacing the one-tap report"
	)
	report_sheet.close()
	_check(
		view.get("_report_entry_id") == "",
		"dismissing the category sheet without choosing clears the pending report target"
	)
	var detail_text := ""
	for label_node in view.find_children("*", "Label", true, false):
		detail_text += " " + (label_node as Label).text
	_check(
		detail_text.find("PrivateNickname") < 0 and detail_text.find("hunger") < 0,
		"Atlas detail never exposes nickname or care state"
	)
	discovered.queue_free()
	silhouette.queue_free()
	var detail_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	detail_image.fill(Color.WHITE)
	portrait.texture = ImageTexture.create_from_image(detail_image)
	await sheet.open()
	view.call("_start_detail_idle")
	await create_timer(0.45).timeout
	await _await_juice_settled(sheet)
	var panel := sheet.panel()
	var bottom_gap := absf(panel.get_global_rect().end.y - sheet.get_global_rect().end.y)
	_check(
		sheet.visible
		and panel != null
		and absf(panel.offset_bottom) < 0.05
		and panel.offset_top < 0.0
		and bottom_gap < 2.0,
		"Atlas detail sheet fills its host and sits on the bottom edge"
	)
	_check(
		not portrait.scale.is_equal_approx(Vector2.ONE),
		"Atlas detail portrait breathes with the shared Idle motion"
	)
	view.close_detail()
	await process_frame
	_check(
		portrait.scale.is_equal_approx(Vector2.ONE),
		"closing Atlas detail stops and resets its Idle motion"
	)
	var juice_source := FileAccess.get_file_as_string("res://scripts/ui_juice.gd")
	_check(
		juice_source.find("func sheet_host_size") >= 0
		and juice_source.find("never leave a visible 0-size overlay") >= 0
		and juice_source.find("if host_h < 1.0:") < 0,
		"bottom-sheet rest position never parks a zero-size overlay at the top-left"
	)
	view.queue_free()
	await process_frame


func _test_profile_info_rows() -> void:
	var packed := load("res://scenes/ui/anima_details_view.tscn") as PackedScene
	var details := packed.instantiate()
	root.add_child(details)
	details.visible = true
	await process_frame
	details.set_anima({
		"id": "details-test",
		"nickname": "Velumi",
		"element": "spark",
		"stage": 2,
		"rarity": 4,
		"care_score": 28,
		"strike_name": "D-Pad Jab",
		"surge_name": "Pocket Beam",
		"base_stats": {"hp": 74, "atk": 62, "def": 58, "spd": 81, "special": 77},
	}, null)
	await process_frame

	_check(details.find_child("DetailsScroll", true, false) is ScrollContainer, "long Profile rows scroll")
	var portrait := details.find_child("DetailsPortrait", true, false) as TextureRect
	_check(
		portrait != null and portrait.custom_minimum_size.x <= 132.0,
		"Profile hero stays compact"
	)
	var about := details.find_child("AboutPanel", true, false) as PanelContainer
	var combat := details.find_child("CombatPanel", true, false) as PanelContainer
	_check(
		about != null and about.theme_type_variation == &"HudSurface"
		and combat != null and combat.theme_type_variation == &"HudSurface",
		"Profile sections share one card chrome"
	)
	_check_eq(
		(details.find_child("TraitStrike", true, false) as Label).text,
		"D-Pad Jab",
		"Profile Attack shows the generated move name"
	)
	_check_eq(
		(details.find_child("TraitSurge", true, false) as Label).text,
		"Pocket Beam",
		"Profile Special shows the generated move name"
	)
	var traits := details.find_child("TraitsGrid", true, false) as GridContainer
	var stats := details.find_child("StatsGrid", true, false) as GridContainer
	_check(traits != null and traits.columns == 2, "Traits use a compact two-column grid")
	_check(stats != null and stats.columns == 5, "Combat stats match the Collection grid")
	var about_help := details.find_child("AboutHelp", true, false) as Button
	var combat_help := details.find_child("CombatHelp", true, false) as Button
	_check(
		about_help != null and about_help.custom_minimum_size.y >= TOUCH_MIN
		and combat_help != null and combat_help.custom_minimum_size.y >= TOUCH_MIN,
		"each Profile section keeps one 96px help action"
	)

	_help_title = ""
	_help_body = ""
	details.help_requested.connect(_capture_help_request)
	about_help.pressed.emit()
	_check(not _help_title.is_empty() and not _help_body.is_empty(), "Profile help emits concise modal copy")

	details.queue_free()
	await process_frame


func _test_hatch_offers_rename() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _present(")
	var end := source.find("\n\nstatic func normalize_anima_data", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	_check(
		body.find("call_deferred(\"_show_rename\", anima_id)") >= 0,
		"every completed scan offers optional rename after reveal"
	)
	var rename_start := source.find("func _show_rename")
	var rename_end := source.find("\n\nfunc _popup_rename", rename_start)
	var rename_body := source.substr(
		rename_start, rename_end - rename_start
	) if rename_start >= 0 and rename_end > rename_start else ""
	_check(
		rename_body.find("_profile_anima") >= 0
		and rename_body.find("draft: String = \"\"") >= 0,
		"rename accepts the Anima currently shown in Profile and a generated draft"
	)
	var confirm_start := source.find("func _rename_confirmed")
	var confirm_end := source.find("\n\nfunc _modal_confirmed", confirm_start)
	var confirm_body := source.substr(
		confirm_start, confirm_end - confirm_start
	) if confirm_start >= 0 and confirm_end > confirm_start else ""
	_check(
		confirm_body.find("_profile_anima[\"nickname\"] = nickname") >= 0,
		"successful rename refreshes a non-active Profile row"
	)
	# Preflight client mencerminkan `_validated_anima_name()` di Postgres. Kalau
	# keduanya berbeda, pemain melihat Save yang dijawab galat server, atau nama
	# yang sah tertahan sebelum sempat dikirim. Script-nya di-load, bukan ditulis
	# sebagai nama global: mode `--script` mengompilasi test lebih dulu daripada
	# autoload, dan `LocaleManager` di dalamnya belum ada di titik itu.
	var details_script: GDScript = load("res://scripts/anima_details_view.gd")
	for valid in ["Sir Fluffy", "O'Malley", "Rex-2", "A"]:
		_check(
			details_script.is_valid_anima_name(valid),
			"nama peliharaan wajar '%s' harus lolos preflight" % valid
		)
	for invalid in ["12345", "Pika\u00e9", "Two  Spaces", " -Lead", "x".repeat(33)]:
		_check(
			not details_script.is_valid_anima_name(invalid),
			"preflight harus menolak '%s'" % invalid
		)
	# Daftar impersonasi/profanity sengaja tinggal di database saja: ia berubah
	# tanpa build baru, dan server tetap pagar terakhirnya.
	_check(
		details_script.is_valid_anima_name("Admin Bot"),
		"daftar terlarang tidak boleh ikut turun ke client"
	)
	_check(
		int(details_script.NAME_MAX_LENGTH) == 32
		and source.find("AnimaDetailsView.NAME_MAX_LENGTH") >= 0,
		"LineEdit Rename memakai batas yang sama dengan validator"
	)
	_check(
		confirm_body.find("AnimaDetailsView.is_valid_anima_name") >= 0,
		"rename memakai preflight bersama, bukan aturan kedua yang bisa melenceng"
	)
	# Trigger Postgres menjawab dengan kode, bukan kalimat. Tanpa pemetaan ini
	# pemain membaca `ANIMA_NAME_RESERVED` mentah di toast.
	for code in ["INVALID_ANIMA_NAME", "ANIMA_NAME_RESERVED"]:
		_check(
			source.find("\"%s\":" % code) >= 0,
			"galat rename '%s' harus dipetakan ke copy localized" % code
		)


func _test_header_uses_seeker_identity(scene: Node) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var identity_body := _func_body(source, "func _seeker_header_text(")
	var header_body := _func_body(source, "func _refresh_header(")
	var configure_body := _func_body(source, "func _configure_resource_chips(")
	var rename_body := _func_body(source, "func _rename_seeker(")
	var game_state := root.get_node_or_null("GameState")
	var previous_session: Dictionary = game_state.get("session").duplicate(true)
	game_state.set("session", {"is_anonymous": true})
	_check_eq(
		scene.call("_seeker_header_text", {"seeker_name": "Nova"}),
		tr("SEEKER_GUEST_LABEL"),
		"guest HUD ignores stale profile names and shows Guest Seeker",
	)
	game_state.set("session", {"is_anonymous": false})
	_check_eq(
		scene.call("_seeker_header_text", {"seeker_name": "Nova"}),
		"Nova",
		"linked HUD shows the authoritative Seeker name",
	)
	_check_eq(
		scene.call("_seeker_header_text", {}),
		tr("SEEKER_UNNAMED"),
		"linked profile without a name keeps the localized fallback",
	)
	game_state.set("session", previous_session)
	_check(
		identity_body.find("GameState.is_anonymous()") >= 0
		and identity_body.find("SEEKER_GUEST_LABEL") >= 0
		and identity_body.find("seeker_name") >= 0,
		"HUD uses Seeker name with a dedicated Guest Seeker fallback",
	)
	_check(
		header_body.find("_brand.text = _seeker_header_text(p)") >= 0,
		"every header refresh also refreshes the visible Seeker identity",
	)
	_check(
		source.find("_animas_chip") < 0
		and source.find("func _refresh_anima_count") < 0
		and configure_body.find("RESOURCE_ANIMAS") < 0,
		"Animas leave the top HUD while Cores and Bits keep the shared chip path",
	)
	_check(
		rename_body.find("_refresh_header()") > rename_body.find("GameState.profile.merge"),
		"renaming a Seeker updates the HUD immediately",
	)


func _test_compact_shared_toast(scene: Node) -> void:
	var toast := scene.find_child("StatusPanel", true, false) as PanelContainer
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var say_body := _func_body(source, "func _say(")
	var relayout_body := _func_body(source, "func _relayout_toast_after_minimum_update(")
	var place_body := _func_body(source, "func _place_toast(")
	_check(
		toast != null and toast.size.y < 76.0,
		"the shared toast scene starts at one-line height instead of the old 76px slab",
	)
	_check(
		say_body.find("_relayout_toast_after_minimum_update(revision)") >= 0
		and relayout_body.find("await get_tree().process_frame") >= 0
		and relayout_body.find("_layout_for_viewport()")
			> relayout_body.find("await get_tree().process_frame")
		and place_body.find("get_combined_minimum_size().y") >= 0
		and source.find("TOAST_MIN_HEIGHT") < 0,
		"every _say call waits for the panel's current content height before placement",
	)
	var probe := PanelContainer.new()
	probe.size = Vector2(320.0, 1.0)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	probe.add_child(label)
	root.add_child(probe)
	label.text = "Daily Play EXP is complete and every active Anima received this longer status update."
	await process_frame
	probe.size.y = probe.get_combined_minimum_size().y
	var long_height := probe.size.y
	label.text = "Hydron is ready."
	await process_frame
	probe.size.y = probe.get_combined_minimum_size().y
	var short_height := probe.size.y
	_check(
		long_height > short_height
		and is_equal_approx(short_height, probe.get_combined_minimum_size().y),
		"minimum-size notification grows and shrinks the shared toast with its text",
	)
	probe.queue_free()
	toast.visible = false


func _test_present_toast_respects_sleep() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var present_start := source.find("func _present(")
	var present_end := source.find("\n\nfunc _prepare_anima_art", present_start)
	var present_body := source.substr(
		present_start, present_end - present_start
	) if present_start >= 0 and present_end > present_start else ""
	var sync_at := present_body.find("await _sync_active_care(false)")
	var summon_at := present_body.find("await _summon_current_anima()")
	var sleep_at := present_body.find("if _is_sleeping(_current_anima)")
	var sleeping_status_at := present_body.find("STATUS_ANIMA_SLEEPING")
	var ready_status_at := present_body.find("STATUS_ANIMA_READY")
	_check(
		sync_at >= 0 and summon_at >= 0 and sleep_at > sync_at and sleep_at > summon_at,
		"authoritative care sync or summon finishes before choosing the startup toast"
	)
	_check(
		sleeping_status_at > sleep_at and ready_status_at > sleep_at,
		"startup distinguishes sleeping and ready Anima copy"
	)
	_check(
		present_body.find("if complete_scan:\n\t\tawait _sync_active_care(false)") < 0,
		"restored Anima sync care just like a completed scan"
	)

	var row_start := source.find("func _present_row")
	var row_end := source.find("\n\nfunc _perform_care", row_start)
	var row_body := source.substr(
		row_start, row_end - row_start
	) if row_start >= 0 and row_end > row_start else ""
	_check(
		row_body.find("_sync_active_care") < 0,
		"present_row does not repeat the care sync"
	)


func _test_battle_reward_is_authoritative() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _apply_battle_reward")
	var end := source.find("\n\n## Scan yang mati", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	_check(
		body.find("await Backend.fetch_profile()") >= 0
		and body.find("await _reload_roster()") >= 0,
		"Battle reward refreshes authoritative profile and roster"
	)
	_check(
		body.find("GameState.profile[\"bits\"] =") < 0,
		"Battle replay cannot add the same reward delta to local balance twice"
	)


func _test_battle_art_has_no_global_toast() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _prepare_battle_art")
	var end := source.find("\n\nfunc _apply_battle_reward", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	_check(
		body.find("_prepare_signed_battle_art") >= 0
		and body.find("false,") >= 0,
		"Battle art loading must not reuse the shell's persistent download toast"
	)


## Jalur local-first Duel: turn dianimasikan dari simulasi lokal, lalu hasil
## server dibandingkan lewat ringkasan yang sama. Yang diuji di sini gerbang
## prediksinya dan deteksi divergensinya, bukan lagi rumus combat-nya —
## itu sudah dijaga test_battle_sim_parity.
func _test_battle_turn_prediction(scene: Node) -> void:
	var fighter := {
		"element": "spark",
		"level": 6,
		"base_stats": {"hp": 60, "atk": 40, "def": 30, "spd": 35, "special": 38},
	}
	var session := {
		"id": "predict-session",
		"turn_number": 3,
		"status": "active",
		"state": {
			"seed": "predict-seed",
			"turn": 3,
			"status": "active",
			"rules_version": BattleSim.RULES_VERSION,
			"player": BattleSim.create_fighter(fighter),
			"bot": BattleSim.create_fighter(fighter),
		},
	}
	var pending := {"expected_turn": 3, "action": "strike", "idempotency_key": "key-a"}
	var predicted: Dictionary = scene.call("_predict_battle_turn", session, pending)
	_check(
		not predicted.is_empty()
		and int(predicted["session"]["turn_number"]) == 4
		and not (predicted["events"] as Array).is_empty(),
		"Duel predicts the next turn locally so the arena animates before the server replies"
	)
	_check(
		(scene.call("_predict_battle_turn", session, {
			"expected_turn": 9, "action": "strike", "idempotency_key": "key-a",
		}) as Dictionary).is_empty(),
		"a stale local turn falls back to the server instead of animating a guess"
	)

	var server_session: Dictionary = predicted["session"].duplicate(true)
	_check(
		bool(scene.call("_turn_outcome_matches", predicted, server_session, predicted["events"])),
		"an identical server turn reuses the animation already played"
	)
	server_session["state"]["bot"]["hp"] = int(server_session["state"]["bot"]["hp"]) - 1
	_check(
		not bool(
			scene.call("_turn_outcome_matches", predicted, server_session, predicted["events"])
		),
		"a divergent server turn replays the authoritative event log"
	)

	var glass_jaw := fighter.duplicate(true)
	glass_jaw["base_stats"] = {"hp": 1, "atk": 10, "def": 1, "spd": 1, "special": 10}
	var team := TeamSim.create_team_state(
		[fighter, fighter], [glass_jaw, glass_jaw], "predict-team-seed"
	)
	var team_session := {"id": "predict-team", "turn_number": 1, "status": "active"}
	team_session["state"] = team["state"]
	var team_pending := {"expected_turn": 1, "action": "surge", "idempotency_key": "key-b"}
	var team_predicted: Dictionary = scene.call(
		"_predict_team_turn", team_session, team_pending
	)
	var team_events: Array = TeamSim.resolve_team_turn(
		team["state"], "surge", "key-b"
	)["events"]
	var has_switch := false
	for value in team_events:
		if str((value as Dictionary).get("type", "")) == "switch":
			has_switch = true
	_check(
		has_switch and team_predicted.is_empty(),
		"a Switch waits for the server while the incoming sheet is missing from the arena"
	)
	_check(
		not (scene.call("_predict_team_turn", team_session, {
			"expected_turn": 1, "action": "guard", "idempotency_key": "key-c",
		}) as Dictionary).is_empty(),
		"a plain Team action animates from the local simulation"
	)
	# Sheet seluruh roster sudah dimuat saat session dibuka, jadi Switch yang
	# lazim justru punya art-nya dan boleh dianimasikan seketika.
	var named := TeamSim.create_team_state(
		[{"anima_id": "mine-a"}.merged(fighter), {"anima_id": "mine-b"}.merged(fighter)],
		[glass_jaw, glass_jaw],
		"predict-team-seed"
	)
	var cached_session := {"id": "predict-team", "turn_number": 1, "status": "active"}
	cached_session["state"] = named["state"]
	scene.set("_team_art_cache", {"mine-a": {"ok": true}, "mine-b": {"ok": true}})
	var switched: Dictionary = scene.call("_predict_team_turn", cached_session, {
		"expected_turn": 1, "action": "switch", "switch_to_slot": 1,
		"idempotency_key": "key-d",
	})
	_check(
		not switched.is_empty()
		and int(switched["session"]["state"]["player"]["active_slot"]) == 1,
		"a Switch into a cached sheet animates on the frame of the tap"
	)
	scene.set("_team_art_cache", {})
	_test_failed_turn_rolls_back()
	_test_boot_cache_is_display_only(scene)


## Turn yang animasinya sudah jalan tetapi requestnya tidak sampai harus
## mengembalikan arena ke state server terakhir. Tanpa itu tap berikutnya
## mengirim nomor turn yang belum pernah ada dan langsung STALE.
func _test_failed_turn_rolls_back() -> void:
	var shell := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var duel_start := shell.find("func _submit_pending_battle")
	var duel_body := shell.substr(duel_start, shell.find("\n\nfunc ", duel_start) - duel_start)
	_check(
		duel_body.find("_battle_view.set_session(session_before)") >= 0,
		"a Duel turn that never reached the server rewinds the arena"
	)
	var team_start := shell.find("func _submit_pending_team_battle")
	var team_body := shell.substr(team_start, shell.find("\n\nstatic func ", team_start) - team_start)
	_check(
		team_body.find("_team_battle_view.set_session(session_before") >= 0,
		"a Team turn that never reached the server rewinds the arena"
	)
	var trail := FileAccess.get_file_as_string("res://scripts/expedition_controller.gd")
	var trail_start := trail.find("func _submit_pending")
	var trail_body := trail.substr(trail_start, trail.find("\n\nfunc ", trail_start) - trail_start)
	_check(
		trail_body.find("_view.set_combat_encounter(_encounter") >= 0,
		"an Expedition turn that never reached the server rewinds the arena"
	)


## Cache boot hanya boleh mempercepat gambar pertama. Dua hal yang bisa rusak
## diam-diam: layar Loading kembali menimpa cache, dan katalog berhenti disegarkan
## karena cache dianggap sudah tersinkron.
func _test_boot_cache_is_display_only(scene: Node) -> void:
	var shell := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var boot_start := shell.find("func _boot()")
	var boot_body := shell.substr(boot_start, shell.find("\n\nfunc ", boot_start) - boot_start)
	_check(
		boot_body.find("_home_view.shell_state() == &\"ready\"") >= 0
		and boot_body.find("if not from_cache:") >= 0,
		"boot keeps the cached Home instead of covering it with Loading"
	)
	var catalog_start := shell.find("func _refresh_catalog()")
	var catalog_body := shell.substr(
		catalog_start, shell.find("\n\nfunc ", catalog_start) - catalog_start
	)
	_check(
		catalog_body.find("if not _catalog_synced:") >= 0
		and catalog_body.find("_catalog_synced = true") >= 0,
		"the catalog is still fetched once per session, cache or not"
	)
	var state := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var reset_start := state.find("func _clear_account_runtime_state")
	var reset_body := state.substr(
		reset_start, state.find("\n\nfunc ", reset_start) - reset_start
	)
	_check(reset_body.find("clear_boot_cache()") >= 0,
		"shared account reset drops the cached Home")
	for entry in ["func clear_account_state", "func discard_guest_local_state"]:
		var start := state.find(entry)
		var body := state.substr(start, state.find("\n\nfunc ", start) - start)
		_check(
			body.find("_clear_account_runtime_state(") >= 0,
			"%s uses the shared cached-Home reset" % entry
		)
	var delete_start := shell.find("func _delete_account()")
	var delete_body := shell.substr(
		delete_start, shell.find("\n\nfunc ", delete_start) - delete_start
	)
	var preflight_guest := delete_body.find("AuthFlow.prepare_device_guest()")
	var delete_request := delete_body.find("Backend.seeker(\"delete_account\"")
	_check(
		preflight_guest >= 0 and delete_request > preflight_guest,
		"Delete Account proves the guest vault before deleting the linked Seeker"
	)
	var activate_guest := delete_body.find("GameState.activate_stored_session(guest)")
	var discard_deleted := delete_body.find("GameState.discard_guest_local_state()")
	_check(
		activate_guest >= 0 and discard_deleted > activate_guest,
		"Delete Account preserves the guest vault until that guest is active"
	)
	_check(
		delete_body.find("GameState.clear_account_state(false)") >= 0,
		"failed Delete Account guest activation cannot create and overwrite a new guest"
	)
	_check(
		delete_body.find("GameState.account_switch_blocked()") >= 0,
		"Delete Account refuses to race a pending account mutation"
	)
	var cached_start := shell.find("func _show_cached_anima()")
	var cached_body := shell.substr(
		cached_start, shell.find("\n\nfunc ", cached_start) - cached_start
	)
	_check(
		cached_body.find("GameState.last_anima") < 0,
		"cold Home only paints a UID-bound boot cache, never a loose last_anima row"
	)
	scene.set("_booting", true)
	scene.set("_boot_auth_success_mode", "")
	scene.call("_on_auth_succeeded", "separate", {})
	_check_eq(
		scene.get("_boot_auth_success_mode"),
		"separate",
		"cold OAuth delegates its one authoritative reload to boot"
	)
	_check_eq(
		scene.call("_account_success_key", "transfer"),
		"SEEKER_MOVED",
		"boot can still announce the suppressed cold OAuth success"
	)


func _test_anima_delete_action() -> void:
	var packed := load("res://scenes/ui/anima_details_view.tscn") as PackedScene
	var details := packed.instantiate()
	root.add_child(details)
	details.visible = true
	await process_frame
	var menu := details.find_child("ProfileMenuButton", true, false) as Button
	var popover := details.find_child("ProfileActionPopover", true, false) as Control
	var backdrop := details.find_child("ProfileActionBackdrop", true, false) as Button
	var rename := details.find_child("ProfileActionRename", true, false) as Button
	var button := details.find_child("ProfileActionDelete", true, false) as Button
	var gallery_button := details.find_child("GalleryPublishButton", true, false) as Button
	_requested_delete_id = ""
	_requested_rename_id = ""
	_requested_gallery_appeal_id = ""
	details.rename_requested.connect(_capture_rename_request)
	details.delete_requested.connect(_capture_delete_request)
	details.gallery_rejection_info_requested.connect(_capture_gallery_appeal_request)
	details.set_anima(
		{
			"id": "anima-delete-test",
			"nickname": "Velumi",
			"element": "flow",
			"rarity": 1,
			"stage": 1,
			"care_score": 0,
			"base_stats": {"hp": 1, "atk": 1, "def": 1, "spd": 1, "special": 1},
		},
		null
	)
	_check(menu != null and not menu.disabled and not popover.visible, "loaded profile enables a closed action menu")
	menu.pressed.emit()
	await process_frame
	_check(popover.visible and rename.has_focus(), "kebab opens an anchored action menu and focuses Rename")
	rename.pressed.emit()
	_check_eq(_requested_rename_id, "anima-delete-test", "Rename emits the shown Anima id")
	_check(not popover.visible, "choosing Rename closes the profile action menu")
	menu.pressed.emit()
	_check(button != null and not button.disabled, "profile action menu enables Delete")
	_check(
		button != null and button.theme_type_variation != &"DangerButton"
		and button.get_theme_color("font_color").r > button.get_theme_color("font_color").g,
		"profile Delete stays a quiet red menu row"
	)
	button.pressed.emit()
	_check_eq(_requested_delete_id, "anima-delete-test", "Delete emits only the active Anima id")
	menu.pressed.emit()
	backdrop.pressed.emit()
	_check(not popover.visible, "tapping outside dismisses the profile action menu")
	details.set_gallery_status({"available": true, "published": true})
	_check(
		gallery_button.visible and gallery_button.text == tr("GALLERY_UNPUBLISH"),
		"the current Anima can show its approved published state"
	)
	var next_row: Dictionary = details.get("_row").duplicate(true)
	next_row["id"] = "anima-gallery-next"
	details.set_anima(next_row, null)
	_check(
		gallery_button.visible and gallery_button.disabled
		and gallery_button.text == tr("GALLERY_STATUS_LOADING"),
		"opening another profile shows a disabled loading state until Atlas status arrives"
	)
	details.set_gallery_status({"available": true, "published": false})
	details.set_gallery_pending(true, true)
	_check(
		gallery_button.visible and gallery_button.disabled
		and gallery_button.text == tr("GALLERY_PUBLISHING"),
		"Atlas publish keeps a visible disabled progress cue"
	)
	details.set_gallery_status({"available": false, "under_review": true})
	_check(
		gallery_button.visible and gallery_button.disabled
		and gallery_button.text == tr("GALLERY_UNDER_REVIEW"),
		"moderation under review shows a disabled state"
	)
	details.set_gallery_status({
		"available": false, "rejected": true,
		"reject_category": "ip_character", "reject_note": "looks like a mascot",
		"appeal_available": true,
	})
	_check(
		gallery_button.visible and not gallery_button.disabled
		and gallery_button.text == tr("GALLERY_PUBLISH_REJECTED"),
		"a rejected entry stays tappable instead of a dead disabled state"
	)
	_check_eq(
		details.call("get_gallery_rejection_info"),
		{"category": "ip_character", "note": "looks like a mascot", "appeal_available": true},
		"the rejected button's tap target reads back exactly what set_gallery_status delivered"
	)
	gallery_button.pressed.emit()
	_check_eq(
		_requested_gallery_appeal_id, "anima-gallery-next",
		"tapping the rejected button asks scan_flow to show the reason, keyed to the shown Anima id"
	)
	details.set_gallery_appeal_pending(true)
	_check(
		gallery_button.disabled and gallery_button.text == tr("GALLERY_APPEAL_PENDING"),
		"requesting a review shows a disabled progress cue on the same button, not a second one"
	)
	details.set_gallery_appeal_pending(false)
	details.set_busy(true)
	_check(menu.disabled and rename.disabled, "network work disables rename")
	_check(button.disabled and not popover.visible, "network work disables and closes destructive actions")
	details.queue_free()
	await process_frame
	for viewport_size in [Vector2i(720, 900), Vector2i(900, 480)]:
		await _test_profile_actions_at_size(packed, viewport_size)


func _test_profile_actions_at_size(packed: PackedScene, viewport_size: Vector2i) -> void:
	var short_viewport := SubViewport.new()
	short_viewport.size = viewport_size
	root.add_child(short_viewport)
	var details := packed.instantiate()
	details.visible = false
	short_viewport.add_child(details)
	details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	details.set_anima(
		{
			"id": "short-profile-test",
			"nickname": "Velumi",
			"element": "flow",
			"rarity": 1,
			"stage": 1,
			"care_score": 0,
			"base_stats": {"hp": 1, "atk": 1, "def": 1, "spd": 1, "special": 1},
			"synthesis_history": {
				"mode": "balanced",
				"resonance": 72,
				"source_a": {"id": "source-a", "name": "Solin", "selected_stage": 1},
				"source_b": {"id": "source-b", "name": "Playtron", "selected_stage": 2},
				"inheritance_summary": {
					"source_a": "Silhouette",
					"source_b": "Palette",
					"coherence": "Shared shape language",
				},
			},
		},
		null
	)
	details.set_synthesis_enabled(true)
	details.set_gallery_status({"available": true, "published": false})
	details.visible = true
	await process_frame
	await process_frame
	var profile_scroll := details.find_child("DetailsScroll", true, false) as ScrollContainer
	var profile_content := details.find_child("DetailsContent", true, false) as Control
	_check(
		profile_scroll != null and profile_scroll.size.y > 0.0
		and profile_content != null and profile_content.size.y > profile_scroll.size.y,
		"hidden Profile restores a real scroll viewport at %s" % viewport_size
	)
	if profile_scroll != null and profile_content != null:
		_check(
			_touch_blockers(profile_scroll).is_empty(),
			"no Profile card swallows the drag at %s, blocked by %s"
				% [viewport_size, _touch_blockers(profile_scroll)]
		)
		_check(
			profile_scroll.scroll_deadzone > 0.0,
			"Profile keeps a deadzone so pass-through buttons stay tappable at %s" % viewport_size
		)
		var card := _card_under_finger(profile_scroll)
		_check(card != null, "a Profile card sits under the finger at %s" % viewport_size)
		var dragged: bool = await _drag_scrolls(short_viewport, profile_scroll, card)
		_check(
			dragged,
			"dragging from Profile card %s scrolls at %s"
				% ["none" if card == null else String(card.name), viewport_size]
		)
		profile_scroll.scroll_vertical = 0
		await process_frame
	var menu := details.find_child("ProfileMenuButton", true, false) as Button
	var popover := details.find_child("ProfileActionPopover", true, false) as Control
	var panel := details.find_child("ProfileActionPanel", true, false) as Control
	var rename := details.find_child("ProfileActionRename", true, false) as Button
	var delete_button := details.find_child("ProfileActionDelete", true, false) as Button
	var synthesis := details.find_child("SynthesisAnimaButton", true, false) as Button
	var gallery := details.find_child("GalleryPublishButton", true, false) as Button
	var backdrop := details.find_child("ProfileActionBackdrop", true, false) as Control
	_check(
		backdrop != null and backdrop.mouse_filter == Control.MOUSE_FILTER_STOP,
		"the menu backdrop still blocks taps at %s, since it sits outside the scroll" % viewport_size
	)
	menu.pressed.emit()
	await process_frame
	var panel_rect := Rect2(panel.position, panel.size)
	_check(
		popover.visible
		and Rect2(Vector2.ZERO, details.size).encloses(panel_rect)
		and rename.has_focus(),
		"Profile menu stays reachable at %s" % viewport_size
	)
	delete_button.grab_focus()
	_check(delete_button.has_focus(), "Profile Delete is focus-reachable at %s" % viewport_size)
	details.close_action_menu()
	profile_scroll.scroll_vertical = 0
	await process_frame
	await _tap(short_viewport, menu)
	_check(
		popover.visible,
		"a clean tap still opens the Profile menu through the scroll relay at %s" % viewport_size
	)
	details.close_action_menu()
	await process_frame
	synthesis.grab_focus()
	await process_frame
	_check(synthesis.has_focus(), "Synthesize is focus-reachable at %s" % viewport_size)
	gallery.grab_focus()
	_check(gallery.has_focus(), "Publish to Atlas is focus-reachable at %s" % viewport_size)
	short_viewport.queue_free()
	await process_frame


func _test_synthesis_history_cache(scene: Node) -> void:
	var anima_id := "history-cache-test-%d" % Time.get_ticks_usec()
	var cache_id := str(scene.call("_synthesis_history_cache_id", anima_id, "source_a"))
	var backend_script := load("res://scripts/backend.gd") as GDScript
	var cache_path := str(backend_script.call("atlas_thumb_cache_path", cache_id))
	var cache_dir := DirAccess.open("user://")
	if cache_dir != null and not cache_dir.dir_exists("atlas_thumbs"):
		cache_dir.make_dir("atlas_thumbs")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color8(32, 184, 72, 255))
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	_check(file != null, "History cache test can create its isolated entry")
	if file == null:
		return
	file.store_buffer(image.save_png_to_buffer())
	file.close()
	var textures: Dictionary = scene.call("_cached_synthesis_history_textures", anima_id)
	_check(textures.get("source_a") is Texture2D, "History paints a cached source without network")
	_check(not textures.has("source_b"), "History only marks cache slots that exist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	var memory_textures: Dictionary = scene.call("_cached_synthesis_history_textures", anima_id)
	_check(memory_textures.get("source_a") is Texture2D, "History keeps the decoded texture in memory")


func _test_evolve_profile_cta() -> void:
	var packed := load("res://scenes/ui/anima_details_view.tscn") as PackedScene
	var details := packed.instantiate()
	root.add_child(details)
	await process_frame
	var evolve := details.find_child("EvolveAnimaButton", true, false) as Button
	var status := details.find_child("EvolutionStatusLabel", true, false) as Label
	_requested_evolve_row = {}
	details.evolve_requested.connect(_capture_evolve_request)
	var ready_row := {
		"id": "anima-evolve-test",
		"nickname": "Velumi",
		"status": "ready",
		"evolution_version": 1,
		"stage": 1,
		"care_score": 150,
		"element": "spark",
		"rarity": 3,
		"base_stats": {"hp": 1, "atk": 1, "def": 1, "spd": 1, "special": 1},
		"strike_name": "Spark Tap",
		"surge_name": "Voltage Rush",
		"strike_effect_id": "burn",
		"surge_effect_id": "barrier",
	}
	details.set_anima(ready_row, null)
	_check(evolve != null and not evolve.visible, "feature flag off hides Evolve CTA")
	details.set_evolution_enabled(true)
	_check(evolve != null and evolve.visible, "ready Lv16 rollout shows Evolve CTA")
	_check(
		evolve != null and evolve.custom_minimum_size.y >= TOUCH_MIN,
		"Evolve CTA meets touch target"
	)
	if evolve != null:
		evolve.pressed.emit()
	_check_eq(str(_requested_evolve_row.get("id", "")), "anima-evolve-test", "Evolve emits row")
	var evolving_row := ready_row.duplicate(true)
	evolving_row["status"] = "evolving"
	details.set_anima(evolving_row, null)
	_check(evolve != null and not evolve.visible, "evolving hides Evolve CTA")
	_check(status != null and status.visible, "evolving shows chamber copy")
	var incubator := IncubatorEffect.new()
	root.add_child(incubator)
	incubator.start_evolution()
	await process_frame
	_check(incubator.is_active(), "evolution chamber mode activates")
	_check(incubator.is_processing(), "evolution chamber keeps animating while active")
	incubator.stop()
	_check(not incubator.is_active(), "evolution chamber stop clears the ritual")
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		flow_source.find("\"suggested_name\": suggested") >= 0
		and flow_source.find("func _evolution_suggested_name") >= 0
		and flow_source.find("str(body.get(\"suggested_name\", \"\"))") >= 0,
		"ritual Evolve menyimpan nama usulan model untuk tombol Rename"
	)
	_check(
		flow_source.find("queued[\"session_epoch\"] = GameState.session_epoch") >= 0
		and flow_source.find(
			"int(dialog.get(\"session_epoch\", -1)) != GameState.session_epoch"
		) >= 0
		and flow_source.find("_outcome_dialog_queue.clear()") >= 0,
		"outcome FIFO menolak response akun lama dan dibersihkan saat handoff"
	)
	_check(
		flow_source.find("if await _complete_evolution(row, restore_navigation):") >= 0,
		"art evolution yang gagal dimuat tetap dipoll dalam sesi yang sama"
	)
	_check(
		flow_source.find("pending_evolution_here") >= 0
		and flow_source.find("CareRules.is_evolving(active) or pending_evolution_here") >= 0
		and flow_source.find(
			"_anima.visible = not hatching and not _evolution_chamber_active"
		) >= 0,
		"pending evolution lokal mencegah flash form lama saat cold boot"
	)
	var form_line_at := flow_source.find("func _level_up_form_line")
	_check(
		form_line_at >= 0
		and flow_source.substr(form_line_at, 400).find(
			"if _evolution_enabled() and CareRules.evolution_version(form_row) >= 1:"
		) >= 0,
		"Level 16/36 rollout tidak mengumumkan form sebelum ritual committed"
	)
	_check(
		flow_source.find("_evolution_art_error_reported") >= 0,
		"retry download art evolution tidak menumpuk toast setiap poll"
	)
	var ritual_start := flow_source.find("func _start_evolution_ritual")
	var ritual_end := flow_source.find("\n\nfunc _resume_pending_evolution", ritual_start)
	var ritual_body := flow_source.substr(
		ritual_start, ritual_end - ritual_start
	) if ritual_start >= 0 and ritual_end > ritual_start else ""
	_check(
		ritual_body.find("_switch_destination(BottomNav.HOME)") >= 0
		and flow_source.find("_home_view.set_evolution(row)") >= 0
		and flow_source.find("var evolving_row := _evolving_roster_row()") >= 0,
		"Begin Evolution and cold resume land on Home with Evolution-specific chamber state"
	)
	_check(
		flow_source.find("if code == \"FEATURE_DISABLED\":") >= 0
		and flow_source.find("_resume_server_evolution") >= 0
		and flow_source.find("bool(pending.get(\"resume_only\", false))") >= 0
		and flow_source.find("var latest := await _fetch_evolution_row(anima_id)") >= 0
		and flow_source.find(
			"status == \"ready\" and stage <= prior_stage"
		) >= 0,
		"cold-start evolution resumes existing work and detects authoritative rollback"
	)
	# Ritual-nya berjalan menit-menit di latar, jadi toast hampir selalu lewat
	# tanpa dilihat dan pemain ditinggalkan tanpa jalan kembali.
	_check(
		flow_source.find("_queue_evolution_failure_dialog(") >= 0
		and flow_source.find("tr(\"EVOLUTION_FAILED\")") < 0,
		"kegagalan Evolve mendarat sebagai dialog, bukan toast yang lewat"
	)
	_check(
		flow_source.find("&\"evolve\", &\"evolution_failure\":") >= 0
		and flow_source.find(
			"context == &\"evolve\" or context == &\"evolution_failure\""
		) >= 0,
		"Retry dialog memakai jalur konfirmasi Evolve yang sama, dan Cancel melepas row-nya"
	)
	_check(
		flow_source.find("\"kind\": \"evolution_failure\"") >= 0
		and flow_source.find("_present_evolution_failure_outcome(dialog)") >= 0
		and flow_source.find("_outcome_dialog_queue.append(queued)") >= 0,
		"dialog kegagalan Evolve masuk FIFO global alih-alih menimpa modal aktif"
	)
	_check(
		flow_source.find("\"kind\": \"evolution_success\"") >= 0
		and flow_source.find("_shell_modal.open_result_choice(") >= 0
		and flow_source.find("await _summon_evolution_outcome(row)") >= 0
		and flow_source.find("_show_rename(") >= 0,
		"hasil Evolve menawarkan Summon atau Rename setelah art siap"
	)
	_check(
		flow_source.find("\"EVOLUTION_TIMEOUT_BODY\"") >= 0
		and flow_source.find("not CareRules.evolution_ready(row)") >= 0,
		"dialog membedakan timeout dari gagal, dan menahan Retry yang pasti ditolak server"
	)
	incubator.queue_free()
	details.queue_free()
	await process_frame


func _test_synthesis_lab_state() -> void:
	var packed := load("res://scenes/scan_flow.tscn") as PackedScene
	var host := packed.instantiate()
	# Untyped on purpose: statically naming the class here would compile it
	# before the autoloads exist, and the view reads GameState at runtime.
	var view = host.find_child("SynthesisLabView", true, false)
	_check(view != null, "Synthesis Lab can be instantiated for state checks")
	if view == null:
		host.free()
		return
	# The lab lives inside the shell scene, so its `%UniqueName` children are
	# registered on the shell root. Moving ownership down to the lab before it
	# enters the tree keeps those lookups resolvable once the shell is freed.
	# `_synthesis_error_key` hands back catalog keys instead of translated text,
	# so the i18n scanner cannot see them. Resolve each one against the catalog.
	var catalog := FileAccess.get_file_as_string("res://locales/ui.csv")
	for code in [
		"FEATURE_DISABLED", "SYNTHESIS_LEVEL_TOO_LOW", "SYNTHESIS_COOLDOWN",
		"SYNTHESIS_MODE_USED", "SYNTHESIS_ALREADY_ACTIVE", "SYNTHESIS_IN_PROGRESS",
		"SYNTHESIS_FORM_LOCKED", "SYNTHESIS_FORM_INVALID", "SYNTHESIS_STAGE_MISMATCH",
		"ANIMA_DORMANT",
		"ANIMA_IN_ACTIVE_COMBAT", "NO_CORE", "NO_BITS", "SPEND_CAP",
		"SYNTHESIS_FAILED", "UNMAPPED_SERVER_CODE",
	]:
		var key := str(host.call("_synthesis_error_key", code))
		_check(
			catalog.find("\n%s," % key) >= 0,
			"Synthesis error %s resolves to a translated key" % code
		)
	view.get_parent().remove_child(view)
	view.owner = null
	_reown_subtree(view, view)
	root.add_child(view)
	view.visible = true
	host.free()
	await process_frame
	var game_state := root.get_node_or_null("GameState")
	var previous_pending: Dictionary = game_state.get("pending_synthesis").duplicate(true)
	game_state.set("pending_synthesis", {})
	var rows: Array[Dictionary] = [
		{
			"id": "synthesis-locale-a", "nickname": "Solin", "status": "ready",
			"stage": 2, "care_score": 150, "element": "plant",
			"base_stats": {"hp": 70, "atk": 60, "def": 55, "spd": 35, "special": 40},
		},
		{
			"id": "synthesis-locale-b", "nickname": "Mossel", "status": "ready",
			"stage": 1, "care_score": 150, "element": "spark",
			"base_stats": {"hp": 45, "atk": 75, "def": 35, "spd": 80, "special": 65},
		},
	]
	var thumbnail_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	thumbnail_image.fill(Color("67e8f9"))
	var source_thumbnail := ImageTexture.create_from_image(thumbnail_image)
	view.set_thumbnail_provider(
		func(_row: Dictionary) -> Texture2D: return source_thumbnail
	)
	view.set_rows(rows, "synthesis-locale-a")
	await process_frame
	var lab_surface := view.find_child("Column", true, false) as VBoxContainer
	var scroll := view.find_child("Scroll", true, false) as ScrollContainer
	var content := scroll.get_child(0) as Control if scroll != null else null
	var sources := view.find_child("Sources", true, false) as GridContainer
	var source_a_card := view.find_child("SynthesisSourceACard", true, false) as Button
	var source_b_card := view.find_child("SynthesisSourceBCard", true, false) as Button
	var source_a_column := view.find_child("SourceACardColumn", true, false) as VBoxContainer
	var source_b_column := view.find_child("SourceBCardColumn", true, false) as VBoxContainer
	var source_a_portrait := view.find_child("SynthesisSourceAPortrait", true, false) as TextureRect
	var source_b_portrait := view.find_child("SynthesisSourceBPortrait", true, false) as TextureRect
	var picker_overlay := view.find_child("SynthesisPickerOverlay", true, false) as Control
	var picker_list := view.find_child("SynthesisPickerList", true, false) as ItemList
	var picker_back := view.find_child("SynthesisPickerBack", true, false) as Button
	var picker_back_icon := picker_back.get_node_or_null("Icon") as TextureRect
	_check(
		lab_surface != null and lab_surface.size.distance_to(view.size) < 0.5,
		"Synthesis Lab surface fills the destination instead of leaking the Home HUD"
	)
	_check(view.clip_contents, "Synthesis Lab clips content inside the shell viewport")
	var synthesis_title := view.find_child("SynthesisTitle", true, false) as Label
	var synthesis_subtitle := view.find_child("SynthesisSubtitle", true, false) as Label
	_check(
		synthesis_title != null and synthesis_subtitle != null,
		"Synthesis Lab uses the unified title and subtitle header"
	)
	_check(scroll != null and scroll.size.y > 0.0, "Synthesis Lab leaves usable vertical scroll space")
	_check(
		content != null and content.size.x <= scroll.size.x + 0.5,
		"Synthesis Lab content stays inside the right edge"
	)
	_check(
		source_a_card != null and source_b_card != null
		and source_a_portrait != null and source_a_portrait.texture == source_thumbnail
		and source_b_portrait != null and source_b_portrait.texture == source_thumbnail,
		"both Source cards show the selected Anima art"
	)
	_check(
		sources != null and sources.columns == 2
		and source_a_card.get_parent() == sources and source_b_card.get_parent() == sources
		and absf(source_a_card.position.y - source_b_card.position.y) < 0.5
		and source_b_card.position.x >= source_a_card.position.x + source_a_card.size.x + 8.0
		and view.find_child("SourceAPanel", true, false) == null
		and view.find_child("SourceBPanel", true, false) == null,
		"Source A and B are direct, un-nested cards in one side-by-side row"
	)
	_check(
		sources.size.y <= 320.0 and content.size.y <= 720.0
		and content.get_theme_constant("separation") == 12
		and sources.get_theme_constant("h_separation") == 12
		and source_a_column.get_theme_constant("separation") == 8
		and source_b_column.get_theme_constant("separation") == 8
		and source_a_column.position.x >= 12.0 and source_a_column.position.y >= 8.0
		and source_a_column.position.x + source_a_column.size.x <= source_a_card.size.x - 12.0
		and source_a_column.position.y + source_a_column.size.y <= source_a_card.size.y - 8.0,
		"compact Source cards keep a breathable 8-point spacing rhythm without overflow"
	)
	_check(
		view.find_child("SynthesisSourceAForm", true, false) == null
		and view.find_child("SynthesisSourceBForm", true, false) == null,
		"Synthesis exposes no historical-form selector"
	)
	var current_payload := view.current_payload() as Dictionary
	_check(
		int(current_payload.get("source_a_stage", 0)) == 2
		and int(current_payload.get("source_b_stage", 0)) == 1,
		"Synthesis payload always uses each Source's committed form"
	)
	source_a_card.pressed.emit()
	await process_frame
	_check(
		picker_overlay != null and picker_overlay.visible
		and picker_list != null and picker_list.item_count == 2
		and picker_list.get_item_icon(0) == source_thumbnail
		and picker_list.get_item_text(0).find("Lv.") >= 0
		and picker_list.get_item_text(0).find("Plant") >= 0,
		"Source card opens an art-first picker with visible Level and elements"
	)
	_check(
		picker_back != null and picker_back.flat
		and picker_back.custom_minimum_size == Vector2(96, 96)
		and picker_back_icon != null and picker_back_icon.texture != null,
		"Source picker repeats the shared flat 96px chevron pattern"
	)
	picker_back.pressed.emit()
	await process_frame
	_check(not picker_overlay.visible, "Source picker back closes the picker before the Lab")
	view.apply_preview({
		"breakdown": {
			"chance": 72, "base": 40, "level": 10, "care": 12,
			"affinity": 10, "mode": 0, "calibration": 0,
		},
		"cost": {"cores": 1, "bits": 250},
		"source_a": {"base_stats": rows[0].base_stats},
		"source_b": {"base_stats": rows[1].base_stats},
	})
	var payload_before := JSON.stringify(view.current_payload())
	view.refresh_localized_ui()
	_check_eq(
		JSON.stringify(view.current_payload()),
		payload_before,
		"locale refresh preserves Synthesis selections"
	)
	var preview_panel := view.find_child("SynthesisPreviewPanel", true, false) as Control
	var confirm := view.find_child("SynthesisConfirmButton", true, false) as Button
	var review_box := preview_panel.get_node_or_null("Box") as VBoxContainer if preview_panel != null else null
	var chance := view.find_child("SynthesisChance", true, false) as Label
	var chance_caption := view.find_child("SynthesisChanceCaption", true, false) as Label
	var breakdown_grid := view.find_child("SynthesisBreakdownGrid", true, false) as GridContainer
	var stat_grid := view.find_child("SynthesisStatGrid", true, false) as GridContainer
	var factor_base := breakdown_grid.get_node_or_null("FactorBase/Value") as Label if breakdown_grid != null else null
	var stat_hp := stat_grid.get_node_or_null("StatHp/Value") as Label if stat_grid != null else null
	_check(
		preview_panel != null and preview_panel.visible and confirm != null and not confirm.disabled,
		"locale refresh preserves the reviewed Resonance preview"
	)
	_check(
		review_box != null and review_box.get_theme_constant("separation") == 16
		and chance != null and chance.text == "72%"
		and chance_caption != null and chance_caption.text == tr("SYNTHESIS_CHANCE_CAPTION")
		and breakdown_grid != null and breakdown_grid.columns == 3 and breakdown_grid.get_child_count() == 6
		and factor_base != null and factor_base.text == "+40"
		and stat_grid != null and stat_grid.columns == 5 and stat_grid.get_child_count() == 5
		and stat_hp != null and not stat_hp.text.is_empty()
		and view.find_child("Stakes", true, false) == null
		and view.find_child("SynthesisSuccessLabel", true, false) == null
		and view.find_child("SynthesisCost", true, false) == null
		and view.find_child("SynthesisBreakdown", true, false) == null
		and view.find_child("SynthesisStatShape", true, false) == null,
		"Resonance Review keeps only the glanceable chance, factors, and likely shape"
	)
	var shell_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var attempt_start := shell_source.find("func _attempt_synthesis")
	var attempt_end := shell_source.find("\n\nfunc _synthesis_attempt_confirmed", attempt_start)
	var attempt_body := shell_source.substr(
		attempt_start, attempt_end - attempt_start
	) if attempt_start >= 0 and attempt_end > attempt_start else ""
	var confirmed_start := shell_source.find("func _synthesis_attempt_confirmed")
	var confirmed_end := shell_source.find("\n\nfunc _resume_pending_synthesis", confirmed_start)
	var confirmed_body := shell_source.substr(
		confirmed_start, confirmed_end - confirmed_start
	) if confirmed_start >= 0 and confirmed_end > confirmed_start else ""
	_check(
		attempt_body.find("open_confirm") >= 0
		and attempt_body.find("SYNTHESIS_CONFIRM_BODY") >= 0
		and attempt_body.find("begin_synthesis") < 0
		and confirmed_body.find("begin_synthesis") >= 0
		and shell_source.find("&\"synthesis_attempt\"") >= 0,
		"Attempt Synthesis asks for cost and miss confirmation before debiting"
	)
	var open_confirm_idx := attempt_body.find("open_confirm")
	var core_gate_idx := attempt_body.find("genesis_cores")
	var bits_gate_idx := attempt_body.find("\"bits\"")
	_check(
		open_confirm_idx > 0 and core_gate_idx >= 0 and bits_gate_idx >= 0
		and core_gate_idx < open_confirm_idx and bits_gate_idx < open_confirm_idx,
		"Attempt Synthesis blocks on insufficient Core/Bits before offering the cost confirmation"
	)
	view.show_error_key("SYNTHESIS_TECHNICAL_FAILURE")
	view.refresh_localized_ui()
	var outcome_body := view.find_child("SynthesisOutcomeBody", true, false) as Label
	_check_eq(
		outcome_body.text,
		tr("SYNTHESIS_TECHNICAL_FAILURE"),
		"locale refresh repaints the visible Synthesis error"
	)
	game_state.set("pending_synthesis", {
		"source_a_id": "synthesis-locale-a",
		"source_b_id": "synthesis-locale-b",
		"mode": "balanced",
		"idempotency_key": "synthesis-incubating-ui",
	})
	view.set_rows(rows)
	await process_frame
	var incubating_view := view.find_child("SynthesisIncubatingView", true, false) as Control
	var incubator_visual := view.find_child("SynthesisIncubatorVisual", true, false) as Control
	var capsule_icon := view.find_child("SynthesisCapsuleIcon", true, false) as TextureRect
	var incubating_a := view.find_child(
		"SynthesisIncubatingSourceAPortrait", true, false
	) as TextureRect
	var incubating_b := view.find_child(
		"SynthesisIncubatingSourceBPortrait", true, false
	) as TextureRect
	var incubating_a_name := view.find_child(
		"SynthesisIncubatingSourceAName", true, false
	) as Label
	var incubating_b_name := view.find_child(
		"SynthesisIncubatingSourceBName", true, false
	) as Label
	var incubating_a_meta := view.find_child(
		"SynthesisIncubatingSourceAMeta", true, false
	) as Label
	_check(
		incubating_view != null and incubating_view.visible
		and scroll != null and not scroll.visible
		and lab_surface != null and incubating_view.size.x >= lab_surface.size.x - 48.0,
		"pending Synthesis replaces the editor with a full-width incubating state"
	)
	_check(
		incubator_visual != null and incubator_visual.is_processing()
		and incubator_visual.size.y <= 360.0
		and capsule_icon != null and capsule_icon.texture != null,
		"the compact capsule is a live indeterminate indicator with a vector icon"
	)
	_check(
		incubating_a != null and incubating_a.texture == source_thumbnail
		and incubating_b != null and incubating_b.texture == source_thumbnail
		and incubating_a_name != null and incubating_a_name.text == "Solin"
		and incubating_b_name != null and incubating_b_name.text == "Mossel"
		and incubating_a_meta != null and incubating_a_meta.text.find("Lv.") >= 0
		and incubating_a_meta.text.find("Plant") >= 0,
		"incubating state keeps both Source art snippets and glanceable identity data"
	)
	view.refresh_localized_ui()
	var incubating_title := view.find_child("SynthesisIncubatingTitle", true, false) as Label
	_check(
		incubating_title != null and incubating_title.text == tr("SYNTHESIS_INCUBATING_TITLE"),
		"locale refresh repaints the dedicated incubating state"
	)
	view.visible = false
	await process_frame
	_check(not incubator_visual.is_processing(), "changing tabs pauses capsule redraws")
	view.visible = true
	await process_frame
	_check(incubator_visual.is_processing(), "returning to the Lab resumes capsule redraws")
	game_state.set("pending_synthesis", {})
	view.set_rows(rows, "synthesis-locale-a")
	await process_frame
	_check(
		not incubating_view.visible and scroll.visible and not incubator_visual.is_processing(),
		"leaving incubating restores the editor and stops hidden capsule animation"
	)
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		flow_source.find("_queue_synthesis_failure_dialog(") >= 0
		and flow_source.find("_queue_synthesis_success_dialog(row, portrait)") >= 0
		and flow_source.find("\"kind\": \"synthesis_success\"") >= 0
		and flow_source.find("_outcome_dialog_queue.append(queued)") >= 0
		and flow_source.find("tr(\"CORE_INFO_CLOSE\"),") >= 0
		and flow_source.find("\"SYNTHESIS_FAILED\":") >= 0
		and flow_source.find("_clear_synthesis_reference_background") < 0
		and flow_source.find("set_synthesis_history_loading(true)") >= 0,
		"terminal dialogs stay locked and History never re-keys green pixels in the client"
	)
	_check(
		flow_source.find(
			"_synthesis_resume_in_flight = false\n\tif not Backend.response_applies(res, account_epoch)"
		) >= 0
		and flow_source.find(
			"GameState.session_epoch != account_epoch:\n\t\t\t_synthesis_poll_in_flight = false"
		) >= 0,
		"stale Synthesis responses release resume and polling guards"
	)
	_check(
		flow_source.find(
			"not GameState.as_dict(target.get(\"synthesis_history\")).is_empty()"
		) >= 0,
		"Atlas only sends Synthesis consent after showing the matching disclosure"
	)
	game_state.set("pending_synthesis", previous_pending)
	view.queue_free()
	await process_frame


func _test_evolution_history_section() -> void:
	var packed := load("res://scenes/ui/anima_details_view.tscn") as PackedScene
	var details := packed.instantiate()
	root.add_child(details)
	await process_frame
	var panel := details.find_child("EvolutionHistoryPanel", true, false) as PanelContainer
	var row := details.find_child("EvolutionHistoryRow", true, false) as HBoxContainer
	var synthesis_panel := details.find_child("SynthesisHistoryPanel", true, false) as Control
	var combat_panel := details.find_child("CombatPanel", true, false) as PanelContainer
	_check(panel != null and row != null, "Profile builds an Evolution History section")
	if panel == null or row == null:
		details.queue_free()
		await process_frame
		return
	# Urutan yang diminta: Attributes, silsilah, lalu Synthesis History.
	_check(
		combat_panel.get_index() < panel.get_index()
		and panel.get_index() < synthesis_panel.get_index(),
		"Evolution History sits between Attributes and Synthesis History"
	)
	_check(
		row.alignment == BoxContainer.ALIGNMENT_CENTER,
		"The lineage is centered in its panel"
	)
	var drowake := {
		"id": "evolution-history-test",
		"nickname": "Drowake",
		"element": "aqua",
		"stage": 2,
		"rarity": 3,
		"base_stats": {"hp": 50, "atk": 40, "def": 40, "spd": 40, "special": 40},
	}
	details.set_anima(drowake, null)
	# Selama menunggu server, stage Anima sudah cukup untuk memesan jumlah kartu
	# yang benar, jadi pemain tahu section ini ada dan berapa bentuk yang datang.
	details.set_evolution_history_loading(true)
	_check(panel.visible, "The section stands while its lineage is still loading")
	_check(
		row.get_child_count() == 3
		and row.get_child(0) is UiSkeleton
		and row.get_child(2) is UiSkeleton,
		"A stage 2 Anima reserves two skeleton cards — got %d children" % row.get_child_count()
	)
	details.set_evolution_history([])
	_check(not panel.visible, "A single form is not a lineage, so the section stays hidden")
	details.set_evolution_history([
		{"stage": 1, "name": "Hydron"},
		{"stage": 2, "name": "Drowake"},
	])
	_check(panel.visible, "Two forms reveal the section")
	_check(
		row.get_child_count() == 3,
		"Two forms draw form, arrow, form — got %d children" % row.get_child_count()
	)
	_check(
		row.get_child(0) is VBoxContainer
		and row.get_child(1) is TextureRect
		and row.get_child(2) is VBoxContainer,
		"The arrow sits between the two forms"
	)
	_check(
		(row.get_child(1) as TextureRect).flip_h,
		"The reused chevron is flipped so it points at the next form"
	)
	_check(
		not (row.get_child(0) is UiSkeleton),
		"Real forms replace the skeleton instead of stacking on it"
	)
	_check(
		(row.get_child(0).get_child(1) as Label).text == "Hydron"
		and (row.get_child(2).get_child(1) as Label).text == "Drowake",
		"The lineage reads oldest form first"
	)
	details.set_evolution_history([
		{"stage": 1, "name": "Hydron"},
		{"stage": 2, "name": "Drowake"},
		{"stage": 3, "name": "Drowarch"},
	])
	_check(
		row.get_child_count() == 5,
		"A third form extends the same row — got %d children" % row.get_child_count()
	)
	_check(
		(row.get_child(4).get_child(1) as Label).text == "Drowarch",
		"The newest form is drawn last"
	)
	# Membuka Anima lain tidak boleh meninggalkan silsilah milik Anima sebelumnya.
	var other := drowake.duplicate(true)
	other["id"] = "evolution-history-other"
	other["nickname"] = "Vitrelisk"
	other["stage"] = 1
	details.set_anima(other, null)
	_check(
		not panel.visible and row.get_child_count() == 0,
		"Switching Anima clears the previous lineage immediately"
	)
	details.set_evolution_history_loading(true)
	_check(
		not panel.visible,
		"Stage 1 never shows the section, not even as a skeleton"
	)
	# Stage 1 belum punya bentuk sebelumnya, jadi Profile tidak membangunkan
	# Edge Function untuknya sama sekali.
	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		flow_source.find("CareRules.committed_stage(row) < 2") >= 0,
		"Stage 1 skips the lineage request entirely"
	)
	# Read-only: silsilah tidak boleh ikut jalur yang membelanjakan Core.
	var backend_source := FileAccess.get_file_as_string("res://scripts/backend.gd")
	_check(
		backend_source.find("\"operation\": \"history\"") >= 0
		and not backend_source.contains("func evolution_history(\n\tanima_id: String,\n\tidempotency_key"),
		"The lineage request carries no idempotency key"
	)
	details.queue_free()
	await process_frame


func _test_synthesis_profile_ui() -> void:
	var packed := load("res://scenes/ui/anima_details_view.tscn") as PackedScene
	var details := packed.instantiate()
	root.add_child(details)
	await process_frame
	var button := details.find_child("SynthesisAnimaButton", true, false) as Button
	var history_panel := details.find_child("SynthesisHistoryPanel", true, false) as Control
	var history_mode := details.find_child("SynthesisHistoryMode", true, false) as Label
	var history_help := details.find_child("SynthesisHistoryHelp", true, false) as Button
	var history_summary := details.find_child("SynthesisHistorySummary", true, false) as Label
	var profile_actions := details.find_child("ProfileActions", true, false) as VBoxContainer
	var primary_actions := details.find_child("PrimaryActions", true, false) as HBoxContainer
	var about_panel := details.find_child("AboutPanel", true, false) as PanelContainer
	var gallery_button := details.find_child("GalleryPublishButton", true, false) as Button
	var menu_button := details.find_child("ProfileMenuButton", true, false) as Button
	var history_source_a := details.find_child("SynthesisHistorySourceA", true, false) as TextureRect
	var history_source_b := details.find_child("SynthesisHistorySourceB", true, false) as TextureRect
	var skeleton_a := details.find_child(
		"SynthesisHistorySourceASkeleton", true, false
	) as UiSkeleton
	var skeleton_b := details.find_child(
		"SynthesisHistorySourceBSkeleton", true, false
	) as UiSkeleton
	var placeholder_a := details.find_child(
		"SynthesisHistorySourceAPlaceholder", true, false
	) as PanelContainer
	var placeholder_b := details.find_child(
		"SynthesisHistorySourceBPlaceholder", true, false
	) as PanelContainer
	_requested_synthesis_id = ""
	details.synthesis_requested.connect(_capture_synthesis_request)
	var row := {
		"id": "anima-synthesis-source",
		"nickname": "Velumi",
		"status": "ready",
		"stage": 2,
		"care_score": 150,
		"element": "spark",
		"rarity": 3,
		"base_stats": {"hp": 50, "atk": 55, "def": 45, "spd": 60, "special": 65},
		"strike_name": "Spark Tap",
		"surge_name": "Voltage Rush",
		"synthesis_history": {
			"mode": "balanced",
			"resonance": 72,
			"source_a": {"id": "source-a", "name": "Solin", "selected_stage": 1},
			"source_b": {"id": "source-b", "name": "Anima", "selected_stage": 2},
			"inheritance_summary": {
				"source_a": "bright crest",
				"source_b": "stone paws",
				"coherence": "one compact guardian",
			},
		},
	}
	details.set_synthesis_enabled(true)
	details.set_history_source_names({"source-b": "Playtron"})
	details.set_anima(row, null)
	details.set_synthesis_history_loading(true)
	await process_frame
	_check(button != null and button.visible and not button.disabled, "eligible profile opens Synthesis")
	_check(
		profile_actions != null and profile_actions.get_index() == 1
		and about_panel != null and about_panel.get_index() == 2
		and primary_actions != null and primary_actions.get_parent() == profile_actions
		and button.get_parent() == primary_actions
		and gallery_button.get_parent() == primary_actions
		and button.get_index() < gallery_button.get_index()
		and button.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and gallery_button.size_flags_horizontal == Control.SIZE_EXPAND_FILL
		and menu_button != null,
		"Profile keeps equal Synthesize and Publish actions beside each other below identity"
	)
	_check(history_panel != null and history_panel.visible, "Result profile shows Synthesis History")
	_check(history_mode != null and history_mode.text.find("72") >= 0, "History shows successful Resonance")
	var history_source_b_label := details.find_child(
		"SynthesisHistorySourceBLabel", true, false
	) as Label
	_check(
		history_source_b_label != null and history_source_b_label.text.find("Playtron") >= 0,
		"History replaces generic Anima with the Source nickname"
	)
	_check(
		history_help != null and history_help.visible
		and history_help.custom_minimum_size.y >= TOUCH_MIN
		and history_summary != null and not history_summary.visible,
		"History keeps inheritance notes behind one 96px help action"
	)
	_help_title = ""
	_help_body = ""
	details.help_requested.connect(_capture_help_request)
	history_help.pressed.emit()
	_check(
		_help_title == tr("SYNTHESIS_HISTORY_TITLE")
		and _help_body.find("bright crest") >= 0
		and _help_body.find("\n\nSource B:") >= 0
		and _help_body.find("\n\nCoherence:") >= 0,
		"History help separates the three inheritance notes into paragraphs"
	)
	_check(
		skeleton_a != null and skeleton_a.visible
		and skeleton_b != null and skeleton_b.visible
		and skeleton_a.size.is_equal_approx(history_source_a.size)
		and skeleton_b.size.is_equal_approx(history_source_b.size)
		and placeholder_a != null
		and placeholder_b != null
		and placeholder_a.custom_minimum_size == Vector2(112, 112)
		and placeholder_b.custom_minimum_size == Vector2(112, 112)
		and placeholder_a.custom_minimum_size.x < history_source_a.custom_minimum_size.x,
		"History reserves both art slots but pulses only compact centered placeholders"
	)
	var veridian_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	veridian_image.fill(Color8(32, 184, 72, 255))
	var veridian_thumbnail := ImageTexture.create_from_image(veridian_image)
	var history: Dictionary = row["synthesis_history"]
	details.set_synthesis_history(history, {
		"source_a": veridian_thumbnail,
		"source_b": veridian_thumbnail,
	})
	details.set_synthesis_history_loading(false)
	_check(
		not skeleton_a.visible and not skeleton_b.visible
		and history_source_a.texture == veridian_thumbnail
		and history_source_b.texture == veridian_thumbnail
		and history_source_a.texture.get_image().get_pixel(0, 0).g > 0.7
		and history_source_a.texture.get_image().get_pixel(0, 0).a > 0.99,
		"transparent History thumbnails replace skeletons without erasing Veridian green"
	)
	button.pressed.emit()
	_check_eq(_requested_synthesis_id, "anima-synthesis-source", "profile preselects Source A")
	row["care_score"] = 0
	details.set_anima(row, null)
	_check(button.disabled, "Anima below Level 10 cannot become a Source")
	details.queue_free()
	await process_frame


func _reown_subtree(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_reown_subtree(child, owner_node)


func _capture_synthesis_request(row: Dictionary) -> void:
	_requested_synthesis_id = str(row.get("id", ""))


func _capture_evolve_request(row: Dictionary) -> void:
	_requested_evolve_row = row.duplicate(true)


func _capture_delete_request(anima_id: String) -> void:
	_requested_delete_id = anima_id


func _capture_rename_request(anima_id: String) -> void:
	_requested_rename_id = anima_id


func _capture_gallery_appeal_request(anima_id: String) -> void:
	_requested_gallery_appeal_id = anima_id


func _capture_profile_request(row: Dictionary) -> void:
	_requested_profile_id = str(row.get("id", ""))


func _capture_summon_request(row: Dictionary, care_synced: bool) -> void:
	_requested_summon_id = str(row.get("id", ""))
	_requested_summon_synced = care_synced
	var care: Dictionary = row.get("care") if typeof(row.get("care")) == TYPE_DICTIONARY else {}
	_requested_summon_hunger = float(care.get("hunger", 0.0))


func _capture_preview_request(_row: Dictionary, _revision: int) -> void:
	_preview_requests += 1


func _capture_help_request(title: String, body: String) -> void:
	_help_title = title
	_help_body = body


func _check_home_background(scene: Node) -> void:
	var background := scene.find_child("HomeBackground", true, false) as TextureRect
	var stage := scene.find_child("Stage", true, false) as Node2D
	var procedural := scene.find_child("Background", false, false) as Node2D
	var live_background := background.duplicate() as TextureRect
	root.add_child(live_background)
	var daylight_timer := live_background.find_child("DaylightTimer", false, false) as Timer
	var daylight := load("res://scripts/local_daylight.gd") as GDScript
	var background_material := live_background.material as ShaderMaterial
	_check(
		is_zero_approx(daylight.daylight_blend(5, 30))
		and is_equal_approx(daylight.daylight_blend(6, 0), 0.5)
		and is_equal_approx(daylight.daylight_blend(6, 30), 1.0)
		and is_equal_approx(daylight.daylight_blend(17, 30), 1.0)
		and is_equal_approx(daylight.daylight_blend(18, 0), 0.5)
		and is_zero_approx(daylight.daylight_blend(18, 30)),
		"local daylight eases continuously through one-hour dawn and dusk windows"
	)
	var live_viewport := live_background.get_viewport_rect().size
	var live_base := HomeBackground.floor_aligned_cover_rect(
		HomeBackground.HOME_BACKGROUND_NIGHT.get_size(), live_viewport
	)
	var live_blend: float = daylight.daylight_blend()
	var live_platform_center := lerpf(
		HomeBackground.PLATFORM_CENTER_NIGHT_PORTRAIT_RATIO,
		HomeBackground.PLATFORM_CENTER_DAY_PORTRAIT_RATIO,
		live_blend
	)
	var live_platform_y := (
		live_background.position.y + live_background.size.y * live_platform_center
	)
	var live_target_y := (
		live_base.position.y
		+ live_base.size.y * HomeBackground.PLATFORM_TARGET_PORTRAIT_RATIO
	)
	_check(
		background != null
		and background.get_parent() == scene
		and procedural.z_index < background.z_index
		and background.z_index < stage.z_index
		and background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED
		and live_background.position.x <= 0.001
		and live_background.position.y <= 0.001
		and live_background.position.x + live_background.size.x >= live_viewport.x
		and live_background.position.y + live_background.size.y >= live_viewport.y
		and is_equal_approx(live_platform_y, live_target_y),
		"Home cover keeps the blended platform center under the fixed Stage anchor"
	)
	_check(
		live_background.texture == load("res://assets/backgrounds/home_background.png")
		and background_material.get_shader_parameter("day_texture") == load(
			"res://assets/backgrounds/home_day_background.png"
		)
		and is_equal_approx(
			float(background_material.get_shader_parameter("daylight_blend")),
			daylight.daylight_blend()
		),
		"Home shader continuously blends the preloaded day and night artwork"
	)
	var home_background_script := load("res://scripts/home_background.gd") as GDScript
	var wide_cover: Rect2 = home_background_script.floor_aligned_cover_rect(
		Vector2(1600, 900),
		Vector2(1024, 804)
	)
	_check(
		home_background_script.uses_landscape(Vector2(1024, 804))
		and not home_background_script.uses_landscape(Vector2(720, 1602))
		and is_equal_approx(wide_cover.end.y, 804.0)
		and wide_cover.size.x >= 1024.0
		and wide_cover.size.y >= 804.0,
		"Home landscape art covers wide viewports while its floor stays bottom-aligned"
	)
	for blend in [0.0, 1.0]:
		var portrait_size := Vector2(720, 1602)
		var portrait_base: Rect2 = home_background_script.floor_aligned_cover_rect(
			Vector2(720, 1602), portrait_size
		)
		var portrait_cover: Rect2 = home_background_script.portrait_platform_cover_rect(
			Vector2(720, 1602), portrait_size, blend
		)
		var platform_ratio := lerpf(
			HomeBackground.PLATFORM_CENTER_NIGHT_PORTRAIT_RATIO,
			HomeBackground.PLATFORM_CENTER_DAY_PORTRAIT_RATIO,
			blend
		)
		_check(
			portrait_cover.position.x <= 0.0
			and portrait_cover.position.y <= 0.0
			and portrait_cover.end.x >= portrait_size.x
			and portrait_cover.end.y >= portrait_size.y
			and is_equal_approx(
				portrait_cover.position.y + portrait_cover.size.y * platform_ratio,
				portrait_base.position.y
				+ portrait_base.size.y * HomeBackground.PLATFORM_TARGET_PORTRAIT_RATIO
			),
			"Home portrait focal crop centers the %s platform without moving Stage"
			% ("day" if blend > 0.5 else "night")
		)
	_check(
		daylight_timer != null and daylight_timer.wait_time <= 1.0,
		"Home daylight blend resynchronizes at least once per second"
	)
	live_background.free()


func _test_home_care_actions() -> void:
	var packed := load("res://scenes/ui/home_view.tscn") as PackedScene
	var home := packed.instantiate()
	root.add_child(home)
	await process_frame
	var feed := home.find_child("FeedButton", true, false) as Button
	var clean := home.find_child("CleanButton", true, false) as Button
	var sleep := home.find_child("SleepButton", true, false) as Button
	var play := home.find_child("PlayButton", true, false) as Button
	var actions := home.find_child("CareActions", true, false) as GridContainer
	var primary := home.find_child("HomePrimaryAction", true, false) as Button
	var identity := home.find_child("Identity", true, false) as VBoxContainer
	var identity_row := home.find_child("IdentityRow", true, false) as HBoxContainer
	var anima_name := home.find_child("AnimaName", true, false) as Label
	var anima_meta := home.find_child("AnimaMeta", true, false) as Label
	var care_summary := home.find_child("CareSummary", true, false) as Label
	var stage_space := home.find_child("StageSpace", true, false) as Control
	var stage_footer_space := home.find_child("StageFooterSpace", true, false) as Control
	var care_theme := load("res://themes/mobile_theme.tres") as Theme
	# Hover was the only care state padded 20/14, so the resting icon sat 10 px
	# further left and snapped inward the instant a pointer arrived. A phone has
	# no hover at all, which left the odd state out as the only one players saw.
	var hover_box := care_theme.get_stylebox(&"hover", &"Button")
	for variation in ["CareFeedButton", "CareCleanButton", "CareSleepButton", "CarePlayButton"]:
		var resting := care_theme.get_stylebox(&"normal", StringName(variation))
		_check(
			resting != null
			and is_equal_approx(resting.content_margin_left, hover_box.content_margin_left)
			and is_equal_approx(resting.content_margin_right, hover_box.content_margin_right),
			"%s holds its icon still between resting and hover" % variation
		)
	# Every action wears the colour of the meter it moves, so which button feeds
	# which bar is legible before the label is. Tolerance because each border is
	# hand-lifted a little off its fill for punch, not generated from it.
	for pairing in [
		["CareFeedButton", "NeedHunger"],
		["CareCleanButton", "NeedHygiene"],
		["CareSleepButton", "NeedEnergy"],
		["CarePlayButton", "NeedExp"],
	]:
		var resting := care_theme.get_stylebox(&"normal", StringName(pairing[0])) as StyleBoxFlat
		var meter := home.find_child(pairing[1], true, false) as ProgressBar
		var fill: StyleBoxFlat = null
		if meter != null:
			fill = meter.get_theme_stylebox(&"fill") as StyleBoxFlat
		_check(
			resting != null
			and fill != null
			and absf(resting.border_color.r - fill.bg_color.r) < 0.12
			and absf(resting.border_color.g - fill.bg_color.g) < 0.12
			and absf(resting.border_color.b - fill.bg_color.b) < 0.12,
			"%s carries the colour of %s, the meter it moves" % [pairing[0], pairing[1]]
		)
	# The care icons are painted art, not glyphs. Base Button tints icons toward
	# white-blue at rest and gold when pressed, which is right for the Lucide
	# line icons still on the Menu rows but would repaint the kibble and the
	# rabbit. Each variation therefore has to opt out on every state, and it has
	# to opt out by keeping the channels equal — dropping the alpha for disabled
	# is fine, shifting the hue is not. Nothing on screen says when this breaks.
	for variation in ["CareFeedButton", "CareCleanButton", "CareSleepButton", "CarePlayButton"]:
		var tinted: Array[String] = []
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_disabled_color"]:
			var paint := care_theme.get_color(StringName(state), StringName(variation))
			if not (is_equal_approx(paint.r, paint.g) and is_equal_approx(paint.g, paint.b)):
				tinted.append(state)
		_check(
			tinted.is_empty(),
			"%s shows its art instead of repainting it (%s)" % [variation, ", ".join(tinted)]
		)
		_check(
			care_theme.get_constant(&"icon_max_width", StringName(variation))
			> care_theme.get_constant(&"icon_max_width", &"Button"),
			"%s gives the illustration more room than a line glyph needs" % variation
		)
	var dock_box := care_theme.get_stylebox(&"panel", &"CareDock") as StyleBoxTexture
	_check(
		dock_box != null and dock_box.texture != null,
		"the care panel lost its Needs dock artwork and fell back to a flat surface"
	)
	_check(
		identity_row != null and identity.get_parent() == identity_row,
		"Home identity fills its row now that Bag and Shop live inside the HUD"
	)
	_check(
		anima_name != null
		and anima_name.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
		"the name still reads from the left"
	)
	# Autowrap and ellipsis trimming together make Label height-aware, and the
	# identity row only reserves one line, so the headline renders empty.
	_check(
		anima_name.autowrap_mode != TextServer.AUTOWRAP_OFF
		and anima_name.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,
		"loading and error headlines wrap beside the chips instead of vanishing"
	)
	_home_action = ""
	_home_care_action = ""
	_home_care_blocked = ""
	home.first_scan_requested.connect(func() -> void: _home_action = "scan")
	home.retry_requested.connect(func() -> void: _home_action = "retry")
	home.care_blocked.connect(func(message: String) -> void: _home_care_blocked = message)
	home.care_requested.connect(func(action: String) -> void: _home_care_action = action)
	_check_eq(home.shell_state(), &"loading", "Home begins in Loading, not a false empty state")
	_check(
		identity.size_flags_vertical == Control.SIZE_EXPAND_FILL
		and identity.alignment == BoxContainer.ALIGNMENT_CENTER
		and not stage_space.visible
		and not stage_footer_space.visible,
		"Home centers loading copy away from Bag and Shop"
	)
	home.set_shell_state(&"empty")
	_check(
		identity.size_flags_vertical == Control.SIZE_SHRINK_BEGIN
		and stage_space.visible
		and stage_footer_space.visible,
		"non-loading Home restores its normal stage layout"
	)
	var scan_cta_btn := home.find_child("ScanCtaButton", true, false) as Button
	_check(
		scan_cta_btn != null and scan_cta_btn.is_visible_in_tree() and not scan_cta_btn.disabled,
		"empty Home exposes its first-scan CTA"
	)
	if scan_cta_btn != null:
		scan_cta_btn.pressed.emit()
	_check_eq(_home_action, "scan", "empty Home routes its CTA to Scan")
	home.set_shell_state(&"error")
	primary.pressed.emit()
	_check_eq(_home_action, "retry", "roster error exposes Retry instead of onboarding")
	var row := {
		"id": "home-care-test",
		"nickname": "Velumi",
		"element": "spark",
		"stage": 1,
		"care": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "bond": 99.0},
		"care_score": 8,
	}
	home.set_evolution(row)
	_check_eq(home.shell_state(), &"evolving", "Evolution has its own Home state")
	_check(
		anima_name.text == tr("HOME_EVOLUTION_NAME") % "Velumi"
		and anima_meta.text == tr("HOME_EVOLUTION_META")
		and not primary.visible
		and stage_space.visible
		and stage_footer_space.visible,
		"Evolution Home names the Anima and shows chamber copy instead of boot loading copy"
	)
	home.set_anima(row, false)
	_check_eq(home.shell_state(), &"ready", "loaded companion replaces the empty state")
	_check(not primary.visible, "ready Home hides its onboarding CTA")
	_check(
		anima_name.autowrap_mode == TextServer.AUTOWRAP_OFF
		and anima_name.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"a loaded nickname stays on one line and ellipsizes before the chips"
	)
	_check(care_summary.text.contains("EXP 3/5"), "Lv.2 still uses the first 5-EXP band")
	_check(
		not care_summary.text.contains(tr("CARE_STATE_ACTIVE")),
		"an awake companion states Level and EXP without labelling itself Active"
	)
	row["care_score"] = 150
	home.update_care(row, false)
	_check(care_summary.text.contains("EXP 0/20"), "Lv.16 shows its 20-EXP denominator")
	row["care_score"] = 860
	home.update_care(row, false)
	_check(care_summary.text.contains("EXP MAX"), "Lv.40 replaces the denominator with MAX")
	row["care_score"] = 8
	home.update_care(row, false)
	_check(not play.disabled, "Play remains available without a Bond cap")
	row["care"]["bond"] = 100.0
	home.update_care(row, false)
	_check(not play.disabled, "Play stays available even if leftover Bond is 100")
	_check_eq(play.text, tr("CARE_PLAY"), "Play matches the other care action labels")
	_check_eq(actions.columns, 4, "awake care keeps four actions in one row")
	play.pressed.emit()
	_check_eq(_home_care_action, "play", "Play under the daily cap still requests care")
	_home_care_action = ""
	row["care_synced_at"] = "2026-08-14T12:00:00Z"
	row["play_score_on"] = CareRules.local_today_string()
	row["play_score_today"] = 5
	home.update_care(row, false)
	_check(not play.disabled, "Play stays clickable after the daily EXP cap")
	_check(play.self_modulate.a < 1.0, "Play looks disabled at the daily EXP cap")
	_check_eq(play.text, tr("CARE_PLAY"), "Play never shows a daily x/y counter")
	play.pressed.emit()
	_check_eq(_home_care_blocked, tr("ERROR_PLAY_CAPPED"), "capped Play explains the limit with a toast")
	_check_eq(_home_care_action, "", "capped Play does not send a care request")

	_home_care_blocked = ""
	_home_care_action = ""
	row["play_score_today"] = 0
	row["care"]["energy"] = 4.0
	home.update_care(row, false)
	_check(not play.disabled, "Play stays clickable at low Energy")
	_check(play.self_modulate.a < 1.0, "Play looks disabled below the Energy cost")
	play.pressed.emit()
	_check_eq(_home_care_blocked, tr("ERROR_NO_ENERGY"), "low-Energy Play explains the limit with a toast")
	_check_eq(_home_care_action, "", "low-Energy Play does not send a care request, so the happy animation never plays")

	_home_care_blocked = ""
	_home_care_action = ""
	row["care"]["hunger"] = 80.0
	row["care"]["hygiene"] = 100.0
	home.update_care(row, false)
	_check(not feed.disabled, "Feed stays clickable when Hunger is not full")
	_check(is_equal_approx(feed.self_modulate.a, 1.0), "Feed stays bright when Hunger is not full")
	_check(not clean.disabled, "Clean stays clickable when Hygiene looks full")
	_check(clean.self_modulate.a < 1.0, "Clean looks disabled when Hygiene looks full")
	feed.pressed.emit()
	_check_eq(_home_care_action, "feed", "Feed still requests care when only Hygiene is full")
	_home_care_action = ""
	clean.pressed.emit()
	_check_eq(_home_care_blocked, tr("ERROR_NEED_FULL"), "full Clean explains the limit with a toast")
	_check_eq(_home_care_action, "", "full Clean does not send a care request")

	_home_care_blocked = ""
	row["care"]["hunger"] = 100.0
	home.update_care(row, false)
	_check(feed.self_modulate.a < 1.0, "Feed looks disabled when Hunger looks full")
	feed.pressed.emit()
	_check_eq(_home_care_blocked, tr("ERROR_NEED_FULL"), "full Feed explains the limit with a toast")
	_check_eq(_home_care_action, "", "full Feed does not send a care request")

	row["care"]["hunger"] = 80.0
	row["care"]["hygiene"] = 80.0
	home.update_care(row, false)
	_check(is_equal_approx(feed.self_modulate.a, 1.0), "Feed brightens once Hunger drops")
	_check(is_equal_approx(clean.self_modulate.a, 1.0), "Clean brightens once Hygiene drops")

	var hunger_chip := home.find_child("HungerChip", true, false) as PanelContainer
	var energy_chip := home.find_child("EnergyChip", true, false) as PanelContainer
	var hygiene_chip := home.find_child("HygieneChip", true, false) as PanelContainer
	row["care"]["hunger"] = 0.0
	row["care"]["energy"] = 19.0
	row["care"]["hygiene"] = 49.0
	home.update_care(row, false)
	_check_eq(hunger_chip.theme_type_variation, &"NeedChipLow", "empty Hunger highlights its chip")
	_check_eq(energy_chip.theme_type_variation, &"NeedChipLow", "Energy below Battle cost highlights its chip")
	_check_eq(hygiene_chip.theme_type_variation, &"NeedChipLow", "dirty Hygiene highlights its chip")
	row["care"]["hunger"] = 40.0
	row["care"]["energy"] = 20.0
	row["care"]["hygiene"] = 50.0
	home.update_care(row, false)
	_check_eq(hunger_chip.theme_type_variation, &"NeedChip", "Hunger at 40 drops the alert")
	_check_eq(energy_chip.theme_type_variation, &"NeedChip", "Energy at 20 drops the alert")
	_check_eq(hygiene_chip.theme_type_variation, &"NeedChip", "Hygiene at 50 drops the alert")

	var locale_home := root.get_node("LocaleManager")
	var hunger_value := home.find_child("HungerValue", true, false) as Label
	var energy_value := home.find_child("EnergyValue", true, false) as Label
	var hygiene_value := home.find_child("HygieneValue", true, false) as Label
	_check(
		hunger_value.text == locale_home.format_percent(40.0)
		and energy_value.text == locale_home.format_percent(20.0)
		and hygiene_value.text == locale_home.format_percent(50.0),
		"every need chip keeps its own percentage ready behind its bar"
	)
	# Hidden by alpha, never by `visible`: collapsing a Label shrinks its chip, so
	# the whole row would shuffle every time the numbers came and went.
	_check(
		not home.need_values_shown()
		and hunger_value.modulate.a == 0.0
		and hunger_value.visible,
		"needs rest as bars alone while keeping the room the numbers will need"
	)
	_check(
		hunger_chip.mouse_filter == Control.MOUSE_FILTER_STOP,
		"the whole chip is the tap target, not just the bar inside it"
	)
	# The bug this guards is invisible to `gui_input.emit` below, which hands the
	# event straight to the chip: a ProgressBar defaults to STOP, so a real tap
	# landing on the bar died there while the caption row above it worked. Labels
	# default to IGNORE, which is exactly why only half the chip ever answered.
	for chip in [hunger_chip, hygiene_chip, energy_chip]:
		var blockers: Array[String] = []
		for inner in (chip as Control).find_children("*", "Control", true, false):
			if (inner as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				blockers.append(inner.name)
		_check(
			blockers.is_empty(),
			"%s passes every pixel to the chip, not just the caption row (%s)"
				% [chip.name, ", ".join(blockers)]
		)
	# Once more through the viewport's own picking, aimed at the middle of the bar
	# — the pixel players actually reported as dead. `in_local_coords = true` is
	# load-bearing: without it the viewport applies a screen transform that the
	# headless DisplayServer reports garbage for, and every pick silently misses.
	var hunger_bar := home.find_child("NeedHunger", true, false) as Control
	# Scenes other suites left in this shared root are drawn over Home and would
	# win the pick — including the LoadingScreen singleton that expedition tests
	# leave attached to root. Evict it before the viewport pick so only Home answers.
	_dismiss_loading_screen_singleton()
	root.move_child(home, -1)
	await process_frame
	var pick := InputEventMouseButton.new()
	pick.button_index = MOUSE_BUTTON_LEFT
	pick.pressed = true
	pick.position = hunger_bar.get_global_rect().get_center()
	pick.global_position = pick.position
	root.get_viewport().push_input(pick, true)
	await process_frame
	_check(
		home.need_values_shown(),
		"a real tap on the bar reveals, not just one on the caption (hit %s)"
			% root.get_viewport().gui_get_hovered_control()
	)
	home.set_need_values_shown(false)
	await _await_juice_settled(energy_value)
	# One finger arrives twice on Android: as a screen touch, then as the mouse
	# press emulation synthesizes. A toggle that runs twice reads as a dead tap.
	hunger_chip.gui_input.emit(_touch_press())
	hunger_chip.gui_input.emit(_mouse_press())
	_check(home.need_values_shown(), "one finger reveals the numbers exactly once")
	await _await_juice_settled(energy_value)
	_check(
		hunger_value.modulate.a > 0.99
		and hygiene_value.modulate.a > 0.99
		and energy_value.modulate.a > 0.99,
		"tapping one chip answers all three, so one gesture reads the whole row"
	)
	hygiene_chip.gui_input.emit(_mouse_press())
	_check(not home.need_values_shown(), "tapping again puts the numbers away")
	await _await_juice_settled(energy_value)
	_check(
		hunger_value.modulate.a == 0.0 and energy_value.modulate.a == 0.0,
		"and they fade out instead of blinking off"
	)
	home.set_need_values_shown(true)
	await _await_juice_settled(energy_value)
	row["care"]["hunger"] = 55.0
	home.update_care(row, false)
	_check(
		hunger_value.modulate.a > 0.99
		and hunger_value.text == locale_home.format_percent(55.0),
		"a care refresh keeps revealed numbers up and moves them to the new value"
	)
	# The refresh above also restarts the hold, so this waits out a full window
	# from there rather than from the reveal.
	# Read off the instance, never as `HomeView.VALUE_HOLD`: naming the class here
	# makes this suite compile home_view.gd before the autoloads exist, and its
	# LocaleManager reference dies there, silently leaving the scene scriptless.
	var hold_seconds: float = home.VALUE_HOLD
	var hold_deadline := Time.get_ticks_msec() + int(1000.0 * (hold_seconds + 3.0))
	while home.need_values_shown() and Time.get_ticks_msec() < hold_deadline:
		await process_frame
	_check(
		not home.need_values_shown(),
		"the numbers see themselves out after a few seconds instead of waiting for a second tap"
	)
	await _await_juice_settled(energy_value)
	_check(
		hunger_value.modulate.a == 0.0 and energy_value.modulate.a == 0.0,
		"and they leave through the same fade a tap would have given them"
	)

	var need_exp := home.find_child("NeedExp", true, false) as ProgressBar
	# The bar sits directly under `Lv. · EXP` and takes its width from that text,
	# so the caption it used to need is the line above it. As its own row at the
	# foot of the panel it was a fifth band competing with the four actions.
	_check(
		need_exp != null
		and need_exp.get_parent() == care_summary.get_parent()
		and need_exp.get_index() > care_summary.get_index(),
		"the EXP bar underlines the level text instead of closing the panel"
	)
	_check(
		home.find_child("ExpRow", true, false) == null
		and home.find_child("ExpLabel", true, false) == null,
		"and it needs no caption of its own down there any more"
	)
	_check(
		need_exp != null and need_exp.custom_minimum_size.y <= 8.0,
		"the track reads as a hairline, not a meter"
	)
	_check(
		need_exp != null
		and need_exp.get_theme_stylebox(&"fill") != null
		and (need_exp.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color
			== Color(0.83, 0.48, 1),
		"thinner did not mean repainted: the EXP violet is unchanged"
	)
	_check(
		home.find_child("BondChip", true, false) == null
		and not care_theme.has_stylebox(&"panel", &"BondChip"),
		"the EXP row drops the panel chrome it no longer needs"
	)

	row["sleep_started_at"] = "2026-08-13T00:00:00Z"
	home.update_care(row, false)
	await process_frame
	_check(not feed.visible and not clean.visible and not play.visible, "sleep hides other care actions")
	_check(
		care_summary.text.contains(tr("CARE_STATE_SLEEPING")),
		"sleep still names itself, since it is why the action row collapsed"
	)
	_check(sleep.visible and not sleep.disabled, "sleep leaves Wake available")
	_check_eq(actions.columns, 1, "Wake occupies one full-width action column")

	row.erase("sleep_started_at")
	home.update_care(row, false)
	await process_frame
	_check(feed.visible and clean.visible and play.visible, "waking restores all care actions")
	_check_eq(actions.columns, 4, "awake care restores four actions in one row")
	home.queue_free()
	await process_frame


func _test_bottom_nav_busy() -> void:
	var packed := load("res://scenes/ui/bottom_nav.tscn") as PackedScene
	var nav := packed.instantiate()
	root.add_child(nav)
	await process_frame
	var buttons := nav.find_child("Buttons", true, false) as HBoxContainer
	var home_button := nav.find_child("HomeNavButton", true, false) as Button
	var scan_button := nav.find_child("ScanNavButton", true, false) as Button
	var battle_button := nav.find_child("BattleNavButton", true, false) as Button
	var menu_button := nav.find_child("MenuNavButton", true, false) as Button
	_check(buttons != null and buttons.get_child_count() == 5, "bottom navigation contains five tabs")
	_check(nav.find_child("AnimaNavButton", true, false) == null, "bottom nav no longer exposes Anima Profile")
	_check(
		battle_button != null and battle_button.find_child("Content", true, false) is VBoxContainer,
		"Battle tab keeps the vertical icon-over-label layout"
	)
	var collection_button := nav.find_child("CollectionNavButton", true, false) as Button
	_check(
		battle_button != null and battle_button.get_index() == 2
		and collection_button != null and collection_button.get_index() == 3,
		"Battle is the center tab and Animas follows it"
	)
	var tapped_destinations: Array[StringName] = []
	nav.destination_selected.connect(
		func(destination: StringName) -> void: tapped_destinations.append(destination)
	)
	scan_button.pressed.emit()
	battle_button.pressed.emit()
	collection_button.pressed.emit()
	_check(
		tapped_destinations == [BottomNav.SCAN, BottomNav.BATTLE, BottomNav.COLLECTION],
		"reordered tab taps still emit their original destination identities"
	)
	for tab: Button in [home_button, scan_button, battle_button, collection_button, menu_button]:
		_check(
			is_equal_approx(tab.custom_minimum_size.y, 100.0),
			"%s is 100px tall so the active pill and the idle tabs share one baseline" % tab.name
		)
	# The bar's texture is authored art pulled from the design, not something
	# drawn here — a gradient StyleBox would drift from it on every retouch.
	# The corner art reads fine plainly scaled at the widths this bar actually
	# renders at, so it's a NinePatchRect with zero patch margin (a full-region
	# uniform stretch) rather than a 9-sliced corner-preserving stretch — 9-slicing
	# the corner made it render far rounder than the source art, since the corner's
	# native pixel size doesn't track this control's own logical scale.
	var backdrop := nav.find_child("Backdrop", true, false) as NinePatchRect
	_check(
		backdrop != null and backdrop.texture != null,
		"the nav bar wears the design's own background image"
	)
	if backdrop != null and backdrop.texture != null:
		_check(
			backdrop.texture.resource_path == "res://assets/ui/bottom_nav_bg.png",
			"that image is the committed asset rather than a runtime redraw"
		)
		_check(
			is_equal_approx(backdrop.patch_margin_left, 0.0)
			and is_equal_approx(backdrop.patch_margin_top, 0.0)
			and is_equal_approx(backdrop.patch_margin_right, 0.0)
			and is_equal_approx(backdrop.patch_margin_bottom, 0.0),
			"the backdrop stretches plainly instead of over-preserving an oversized corner"
		)
		_check(
			is_equal_approx(buttons.custom_minimum_size.x, 674.0)
			and buttons.size_flags_horizontal == Control.SIZE_FILL + Control.SIZE_EXPAND,
			"the five-tab row floors at its 720px design width but spreads evenly on wider viewports"
		)
		_check(
			backdrop.get_index() < buttons.get_parent().get_index(),
			"the backdrop paints behind the tabs"
		)
	nav.set_active(BottomNav.HOME)
	var home_ink := home_button.find_child("Icon", true, false) as TextureRect
	var battle_ink := battle_button.find_child("Icon", true, false) as TextureRect
	var scan_ink := scan_button.find_child("Icon", true, false) as TextureRect
	var home_text := home_button.find_child("Label", true, false) as Label
	_check(
		home_ink.modulate == BottomNav.ICON_ACTIVE and battle_ink.modulate == BottomNav.ICON_IDLE,
		"only the active tab takes the bright ink"
	)
	# The tab art is full-colour, so its state can only be brightness — a hue
	# would repaint the drawing. The label still carries the cyan, which is what
	# keeps the state readable in more than one channel.
	_check(
		home_ink.modulate.r == home_ink.modulate.b
		and home_text.get_theme_color(&"font_color") == BottomNav.INK_ACTIVE,
		"the active icon dims rather than tints, and the label keeps the cyan"
	)
	nav.set_active(BottomNav.BATTLE)
	_check(
		battle_ink.modulate == BottomNav.ICON_ACTIVE and home_ink.modulate == BottomNav.ICON_IDLE,
		"the bright ink follows the destination instead of sticking to Home"
	)
	nav.set_scan_emphasized(false)
	_check(
		scan_ink.modulate == BottomNav.ICON_UNAVAILABLE and scan_ink.modulate.a > 0.0,
		"an unavailable Scan dims instead of disappearing"
	)
	nav.set_scan_emphasized(true)
	_check(scan_ink.modulate == BottomNav.ICON_IDLE, "Scan returns to its neighbours' ink")
	nav.set_active(BottomNav.BATTLE)
	_check(battle_button.button_pressed, "Battle destination has an explicit active state")
	menu_button.button_pressed = true
	nav.call("_select", BottomNav.MENU)
	_check(
		battle_button.button_pressed and not menu_button.button_pressed,
		"Menu launches its popover without replacing the active destination"
	)
	nav.set_busy(true, true)
	_check(not home_button.disabled, "busy requests keep Home navigation available")
	_check(not scan_button.disabled, "busy requests keep Scan navigation available")
	_check(not battle_button.disabled, "busy requests keep Battle navigation available")
	_check(menu_button.disabled, "Menu launcher blocks concurrent profile and Atlas requests while busy")
	nav.set_busy(false, false)
	_check(not menu_button.disabled, "Menu launcher becomes available after busy clears")
	nav.set_active(BottomNav.HOME)
	var overlay_emit_start := tapped_destinations.size()
	home_button.pressed.emit()
	_check(
		tapped_destinations.size() == overlay_emit_start,
		"tapping the already-active tab is still a no-op with no overlay open"
	)
	nav.mark_overlay_active(BottomNav.HOME)
	_check(
		home_button.button_pressed,
		"the tab underneath an open overlay still reads as active"
	)
	home_button.pressed.emit()
	_check(
		tapped_destinations.size() == overlay_emit_start + 1
		and tapped_destinations[-1] == BottomNav.HOME,
		"tapping the tab underneath an open overlay closes it instead of no-op'ing"
	)
	nav.queue_free()
	await process_frame


func _test_incubator_effect() -> void:
	var effect := Node2D.new()
	effect.set_script(load("res://scripts/incubator_effect.gd"))
	root.add_child(effect)
	await process_frame

	effect.start()
	_check(effect.visible, "start() shows the Incubator")
	_check(effect.is_active(), "start() activates the Incubator")
	await process_frame
	effect.stop()
	_check(not effect.visible, "stop() hides the Incubator")
	_check(not effect.is_active(), "stop() ends its loop")

	effect.start()
	await effect.burst()
	_check(effect.visible, "burst() returns while the flash is visible")
	await create_timer(0.45).timeout
	_check(not effect.visible and not effect.is_active(), "burst cleanup completes")

	await effect.start_portal()
	_check(effect.visible and effect.is_active(), "Summon opens the portal without incubation")
	await effect.burst()
	await create_timer(0.45).timeout
	_check(not effect.visible and not effect.is_active(), "Summon portal cleans itself up")
	effect.free()


func _sheet_button_labels(node_root: Node) -> PackedStringArray:
	var labels := PackedStringArray()
	if node_root == null:
		return labels
	for node in node_root.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or button.is_queued_for_deletion() or not button.visible:
			continue
		if button.name == "ShopEmptyCta" or button.name == "DismissButton":
			continue
		labels.append(button.text)
	return labels


func _control_labels(node_root: Node) -> PackedStringArray:
	var labels := PackedStringArray()
	if node_root == null:
		return labels
	for node in node_root.find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or label.is_queued_for_deletion():
			continue
		labels.append(label.text)
	return labels


func _live_row_count(list: Node) -> int:
	if list == null:
		return 0
	var count := 0
	for child in list.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _boss_seeker_payload() -> Dictionary:
	return {
		"id": "confectioner",
		"display_name": "The Confectioner",
		"portrait_pose": "profile",
		"dialogue": {
			"chapter_intro": "Every path began as a page.",
			"boss_intro": "Show me what your team adds.",
			"rematch": "A second reading?",
			"first_attack": "First measure.",
			"first_special": "Open the sealed formula.",
			"first_switch": "Turn the page.",
			"last_anima": "One page remains.",
			"victory": "You changed the formula.",
			"defeat": "Return when stronger.",
		},
	}


func _boss_seeker_loaded() -> Dictionary:
	var image := Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 1, 0, 1))
	var names := [
		"intro_idle", "attack_command", "special_command",
		"switch_command", "concern_hit", "last_anima",
		"victory", "defeat", "profile",
	]
	var poses := {}
	for index in names.size():
		var col := index % 3
		var row := index / 3
		var x := col * 341
		var y := row * 341
		image.fill_rect(Rect2i(x, y, 300, 300), Color(0.25, 0.2, 0.7, 1))
		poses[names[index]] = {"region": [x, y, 300, 300]}
	return SeekerSheet.build(
		ImageTexture.create_from_image(image),
		{"version": 1, "frame_size": [300, 300], "poses": poses}
	)


func _dismiss_when_open(dialog: BossSeekerDialog) -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if dialog != null and dialog.is_open():
			dialog.dismiss()
			return
		await process_frame


## Team dan Expedition memakai list yang sama, jadi modenya diperiksa pada
## instance scene masing-masing, bukan pada kelasnya: `_ready()` milik list jalan
## **sebelum** `_ready()` view-nya, jadi override di scene atau di view akan
## menang diam-diam — dan SELECT_MULTI adalah tap deselect yang dilaporkan pemain
## (`_test_roster_list_real_taps()` yang memutar ulang tap-nya).
func _check_toggle_select_mode(list: ItemList, label: String) -> void:
	_check(
		list.select_mode == ItemList.SELECT_TOGGLE,
		"%s toggles a pick on press instead of collapsing it on release" % label
	)


## Mirrors what SELECT_TOGGLE does to the selection before the tap is reported:
## it flips the pressed item and leaves the rest alone. Godot swallows a
## disabled item earlier than this, so tapping one here is the stricter path —
## it makes the handler's own guard answer for it.
##
## The pick itself is delivered through `_toggle_index`, not `item_clicked`:
## picks moved to release-with-no-travel so that dragging to scroll stops
## editing the roster, and `item_clicked` is no longer listened to at all.
func _tap_roster_item(list: ItemList, index: int) -> void:
	if not list.is_item_disabled(index):
		if list.is_selected(index):
			list.deselect(index)
			list.multi_selected.emit(index, false)
		else:
			list.select(index, false)
			list.multi_selected.emit(index, true)
	list.call("_toggle_index", index)


## Alasannya sama dengan `_drag_scrolls`: yang rusak di perangkat adalah jalur
## input, dan `item_clicked.emit()` di atas tetap lulus walau Godot memutuskan
## hal lain. SELECT_MULTI menunda collapse-to-single sampai jari diangkat dan
## **tidak pernah** memancarkan `item_clicked` pada press-nya, jadi tap deselect
## meninggalkan satu kartu tersorot sementara `_order` masih memegang tiga.
## Listnya dibangun sendiri karena `team_battle_view` di suite ini hidup
## tersembunyi dan tanpa lebar — jari tidak bisa mendarat di sana.
func _test_roster_list_real_taps() -> void:
	var list := TeamRosterList.new()
	list.max_columns = 1
	list.size = Vector2(480.0, 480.0)
	for index in 3:
		list.add_item("Team %d" % (index + 1))
	root.add_child(list)
	# Scene sisa suite lain digambar di atas dan akan memenangkan pick —
	# termasuk singleton LoadingScreen yang ditinggal test expedition.
	_dismiss_loading_screen_singleton()
	root.move_child(list, -1)
	await process_frame
	var picked: Array[int] = [0, 1, 2]
	list.set_chosen_order(picked)
	var changes := [0]
	list.selection_changed.connect(func() -> void: changes[0] += 1)
	_check(
		list.get_chosen_indices_ordered() == [0, 1, 2] and list.is_selected(1),
		"the roster probe starts with three picked Anima"
	)
	await _tap_roster_item_through_viewport(list, 1)
	_check(
		list.get_chosen_indices_ordered() == [0, 2]
		and not list.is_selected(1)
		and list.is_selected(0)
		and list.is_selected(2)
		and changes[0] == 1,
		"a real deselect tap drops that Anima instead of making it the only pick"
	)
	await _tap_roster_item_through_viewport(list, 1)
	_check(
		list.get_chosen_indices_ordered() == [0, 2, 1]
		and list.is_selected(0)
		and list.is_selected(1)
		and list.is_selected(2)
		and changes[0] == 2,
		"a real tap re-adds an Anima last without clearing the ones already picked"
	)
	list.queue_free()
	await process_frame


## `ItemList` scrolls nothing by itself: a scripted drag over a populated list
## leaves its own scrollbar at 0, so a roster taller than its window was
## unreachable -- the Battle picker showed four of nine Anima. And because
## `ItemList` selects on PRESS, every attempt to scroll also picked whichever
## card the thumb started on, which in the Team builder silently edited the
## roster. Both halves are driven through real mouse-emulated-as-touch input
## (same technique as `_drag_scrolls`), because what broke on the device was the
## input path, not the arithmetic.
func _test_item_list_drag_scroll() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 700)
	root.add_child(viewport)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700.0, 300.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Icon-sized rows, like the real roster cards: short text alone fits nine
	# rows inside the window and would not reproduce the overflow at all.
	var list := ItemList.new()
	list.max_columns = 2
	list.fixed_icon_size = Vector2i(128, 128)
	list.custom_minimum_size = Vector2(600.0, 360.0)
	var swatch := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	swatch.fill(Color.RED)
	var icon := ImageTexture.create_from_image(swatch)
	for index in 9:
		list.add_item("Item %d" % index, icon, true)
	scroll.add_child(body)
	body.add_child(list)
	viewport.add_child(scroll)
	var taps: Array[int] = []
	var drag_ends := [0]
	UiJuice.install_item_list_touch_scroll(
		list,
		func(index: int) -> void: taps.append(index),
		func() -> void: drag_ends[0] += 1
	)
	await process_frame
	await process_frame
	_check(
		list.get_v_scroll_bar().max_value > list.get_v_scroll_bar().page,
		"the probe list really does hide content behind its own window"
	)
	var was_emulating := Input.is_emulating_touch_from_mouse()
	Input.set_emulate_touch_from_mouse(true)

	# A drag must scroll the list and pick nothing.
	var start := Vector2(300.0, 250.0)
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	viewport.push_input(press, true)
	await process_frame
	for step in range(1, 6):
		var motion := InputEventMouseMotion.new()
		motion.position = start - Vector2(0.0, 24.0 * step)
		motion.relative = Vector2(0.0, -24.0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(motion, true)
		await process_frame
	_check(
		list.get_v_scroll_bar().value > 0.0,
		"dragging over the list scrolls it past what fit on one screen"
	)
	_check(
		list.get_selected_items().is_empty(),
		"no card lights up mid-scroll, not even before the finger comes up"
	)
	var release := InputEventMouseButton.new()
	release.position = start - Vector2(0.0, 120.0)
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	viewport.push_input(release, true)
	await process_frame
	_check(
		taps.is_empty() and drag_ends[0] == 1,
		"a scroll drag reports no pick at all, only a drag end"
	)
	# `ItemList` highlights on press, so a scroll used to light up whatever card
	# the thumb started from and only get corrected once the finger came up.
	# The press is swallowed now, so nothing may be selected at any point of a
	# drag -- checked mid-gesture below as well, since correcting it on release
	# is exactly the bug that shipped.
	_check(
		list.get_selected_items().is_empty(),
		"a scroll drag never leaves a selection ring behind"
	)
	# The chrome around the list must not have moved with it.
	_check(
		scroll.scroll_vertical == 0,
		"the list scrolls inside its own window instead of dragging the chrome"
	)

	# A deliberate tap still picks, and picks the row under the finger.
	list.get_v_scroll_bar().value = 0.0
	await process_frame
	var target := 1
	var at := list.get_global_rect().position + list.get_item_rect(target).get_center()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)
		await process_frame
	_check(
		taps == [target] and drag_ends[0] == 1,
		"a clean tap picks exactly the row under the finger"
	)

	Input.set_emulate_touch_from_mouse(was_emulating)
	viewport.queue_free()
	await process_frame


## Evicts the LoadingScreen singleton from the shared root so viewport input
## picks land on the intended target instead of the loading overlay.
## The singleton is re-created on demand the next time show_screen is called,
## so this does not break _test_loading_screen which runs after all pick tests.
func _dismiss_loading_screen_singleton() -> void:
	for child in root.get_children():
		if child is LoadingScreen:
			child.queue_free()
			await process_frame
			break


func _tap_roster_item_through_viewport(list: ItemList, index: int) -> void:
	# `get_item_rect()` sits in content space, so the scroll offset comes back
	# out before the press is aimed — the same correction the badges make.
	var at := (
		list.get_global_rect().position
		+ list.get_item_rect(index).get_center()
		- Vector2(0.0, list.get_v_scroll_bar().value)
	)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		list.get_viewport().push_input(click, true)
		await process_frame


## One loading screen serves every screen swap, so the checks that matter are
## that it instantiates on its own, fills the screen with the brand surface
## instead of reading as a dialog, and never paints for work that finishes
## inside its delay.
func _test_loading_screen() -> void:
	var packed := load(LoadingScreen.SCENE_PATH) as PackedScene
	_check(packed != null, "the loading screen scene loads")
	var probe: Node = packed.instantiate() if packed != null else null
	_check(probe is LoadingScreen, "the loading screen scene instantiates on its own script")
	if probe != null:
		var probe_root := probe.find_child("LoadingScreenRoot", true, false) as Control
		_check_full_rect(probe_root, "loading screen root")
		_check(
			probe_root != null and not probe_root.visible,
			"the loading screen rests hidden until something asks for it"
		)
		_check(
			probe_root != null
			and probe_root.theme != null
			and probe_root.theme.resource_path == "res://themes/mobile_theme.tres",
			"the loading screen carries the shared mobile theme"
		)
		# A dialog panel over a dimmed shell is the shape this screen must not
		# have: it covers the whole screen with the brand surface the shell
		# already draws, so nothing of the half-built Home shows through.
		_check(
			probe.find_child("Brand", true, false) is ScanimaBackground,
			"the loading screen fills itself with the shared brand surface"
		)
		_check(
			ScanimaBackground.BG_TOP.a == 1.0
			and ScanimaBackground.BG_MID.a == 1.0
			and ScanimaBackground.BG_BOTTOM.a == 1.0,
			"the brand fill is opaque instead of letting the shell read through"
		)
		# The seam is the vignette, not the layout: a flat band ends in a hard
		# full-width edge, and with nothing but one line of copy on screen that
		# edge reads as the background stopping short of the bottom. Reaching
		# exactly zero at the band's inner edge is what removes it.
		_check_eq(
			ScanimaBackground.vignette_alpha(0.22, 1.0),
			0.0,
			"the vignette fades to nothing instead of ending on a hard seam"
		)
		var seam := ""
		var last := ScanimaBackground.vignette_alpha(0.22, 0.0)
		for step in range(1, ScanimaBackground.VIGNETTE_BANDS + 1):
			var alpha := ScanimaBackground.vignette_alpha(
				0.22, float(step) / float(ScanimaBackground.VIGNETTE_BANDS)
			)
			if alpha > last:
				seam = "band %d" % step
			last = alpha
		_check(seam.is_empty(), "the vignette only ever lightens inward: %s" % seam)
		# Headless runs cannot read pixels, so a soft `vignette_alpha` alone would
		# still pass with the two flat rects it replaced. The draw path is scanned
		# instead: both edges go through the banded helper, and no bare `draw_rect`
		# survives in `_draw_vignette` to reintroduce a hard-edged slab.
		var brand_source := FileAccess.get_file_as_string(
			"res://scripts/scanima_background.gd"
		)
		var vignette_body := _func_body(brand_source, "func _draw_vignette(")
		_check(
			vignette_body.count("_draw_vignette_band(") == 2
			and vignette_body.find("draw_rect(") < 0,
			"both vignette edges are drawn as bands, not as flat rects"
		)
		var dressing := ""
		for node in probe.find_children("*", "", true, false):
			if node is PanelContainer:
				dressing = str(node.name)
			if node is ColorRect and (node as ColorRect).color.a < 1.0:
				dressing = str(node.name)
		_check(
			dressing.is_empty(),
			"no card or dim scrim makes the loading screen read as a dialog: %s" % dressing
		)
		var message := probe.find_child("LoadingMessage", true, false) as Label
		_check(
			message != null
			and message.theme_type_variation == &"PageTitleLabel"
			and message.text == "STATUS_LOADING"
			and message.autowrap_mode != TextServer.AUTOWRAP_OFF,
			"the centred copy is the display-font Loading title and wraps long locales"
		)
		# The motion must not be a bar that fills: nothing upstream reports a
		# percentage, so a track the dash could fill would be inventing one.
		var track := probe.find_child("LoadingSweep", true, false) as Control
		var spark := probe.find_child("LoadingSpark", true, false) as ColorRect
		_check(
			track != null and spark != null and spark.get_parent() == track,
			"the motion under the copy is a dash inside a clipped track"
		)
		_check(
			track != null and track.clip_contents and track.custom_minimum_size.y <= 12.0,
			"the track stays a thin strip that clips the dash at both ends"
		)
		# A dash far shorter than its track cannot be read as an amount, which is
		# the whole reason it replaced the bar.
		_check(
			track != null and spark != null
			and spark.size.x <= track.custom_minimum_size.x * 0.4,
			"the dash is far shorter than the track so no position reads as a percentage"
		)
		_check(
			spark != null and spark.color == ScanimaBackground.CYAN,
			"the dash reuses the brand cyan instead of a new colour"
		)
		_check(
			probe.find_child("LoadingBar", true, false) == null,
			"the oscillating progress bar is gone rather than left hidden"
		)
		probe.free()

	# Work that settles inside the delay must never paint. That is the promise
	# that a local-first tap does not pay a frame of flicker for this screen.
	LoadingScreen.show_screen("BATTLE_CONNECTING")
	LoadingScreen.hide_screen()
	await create_timer(LoadingScreen.SHOW_DELAY_SEC + 0.12).timeout
	_check(not LoadingScreen.is_showing(), "instant work never paints the loading screen")

	LoadingScreen.show_screen("BATTLE_CONNECTING")
	_check(
		not LoadingScreen.is_showing(),
		"the loading screen waits out its delay before covering the shell"
	)
	await create_timer(LoadingScreen.SHOW_DELAY_SEC + 0.12).timeout
	_check(LoadingScreen.is_showing(), "work slower than the delay paints the loading screen")

	# Reusable means one node answers every caller, with the new copy applied.
	LoadingScreen.show_screen("EXPEDITION_STARTING_RUN")
	var live: Array[Node] = []
	for child in root.get_children():
		if child is LoadingScreen:
			live.append(child)
	_check_eq(live.size(), 1, "every caller shares one loading screen instance")
	var screen: LoadingScreen = live[0] if not live.is_empty() else null
	_check(
		screen != null and screen.message_key() == "EXPEDITION_STARTING_RUN",
		"a second caller swaps the copy instead of stacking a second screen"
	)
	if screen != null:
		await _check_loading_sweep_never_reverses(screen)

	LoadingScreen.hide_screen()
	await create_timer(LoadingScreen.MIN_PAINT_SEC + LoadingScreen.FADE_SEC + 0.12).timeout
	_check(not LoadingScreen.is_showing(), "hiding releases the shell again")
	if screen != null:
		_check_eq(
			(screen.find_child("LoadingScreenRoot", true, false) as Control).visible,
			false,
			"the hidden loading screen stops drawing instead of sitting transparent"
		)

	# Boot asks for the screen at frame zero, so it must paint without waiting the
	# delay, and a warm boot that settles instantly must still be seen.
	LoadingScreen.show_screen("STATUS_LOADING", true)
	_check(
		LoadingScreen.is_showing(),
		"a boot request paints in the same frame instead of waiting the delay"
	)
	LoadingScreen.hide_screen()
	_check(
		LoadingScreen.is_showing(),
		"a screen dismissed straight away holds its floor instead of blinking"
	)
	# A transition landing inside that floor takes over the painted screen: the
	# queued close is cancelled, not honoured behind the new copy.
	LoadingScreen.show_screen("BATTLE_CONNECTING")
	await create_timer(LoadingScreen.MIN_PAINT_SEC + 0.12).timeout
	_check(
		LoadingScreen.is_showing() and screen != null
		and screen.message_key() == "BATTLE_CONNECTING",
		"a request during the floor cancels the queued close"
	)
	LoadingScreen.hide_screen()
	await create_timer(LoadingScreen.FADE_SEC + 0.12).timeout
	_check(not LoadingScreen.is_showing(), "the held screen still closes once it is stale")

	# Boot's own hand-off: the screen has been up long past the floor, so
	# `_set_busy(false)` really starts the fade, and the art wait re-requests it in
	# that same frame. Repainting mid-fade is what keeps Home from flashing through.
	LoadingScreen.show_screen("STATUS_LOADING", true)
	await create_timer(LoadingScreen.MIN_PAINT_SEC + 0.12).timeout
	LoadingScreen.hide_screen()
	LoadingScreen.show_screen("STATUS_LOADING")
	await create_timer(LoadingScreen.FADE_SEC + 0.12).timeout
	_check(
		LoadingScreen.is_showing(),
		"a request in the frame the fade starts keeps the screen up instead of blinking"
	)
	LoadingScreen.hide_screen()
	await create_timer(LoadingScreen.MIN_PAINT_SEC + LoadingScreen.FADE_SEC + 0.12).timeout
	if screen != null:
		screen.queue_free()
		await process_frame

	var shell_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var expedition_source := FileAccess.get_file_as_string(
		"res://scripts/expedition_controller.gd"
	)
	_check(
		shell_source.find("LoadingScreen.show_screen(\"HOME_LOADING_META\")") >= 0
		and shell_source.find("LoadingScreen.show_screen(\"BATTLE_CONNECTING\")") >= 0
		and shell_source.find("LoadingScreen.show_screen(\"BATTLE_RESUMING\")") >= 0
		and shell_source.find("LoadingScreen.show_screen(\"TEAM_STARTING\")") >= 0
		and shell_source.find("LoadingScreen.show_screen(\"TEAM_RESUMING\")") >= 0
		and expedition_source.find("LoadingScreen.show_screen(\"EXPEDITION_LOADING\")") >= 0
		and expedition_source.find("LoadingScreen.show_screen(\"EXPEDITION_RESUMING\")") >= 0
		and expedition_source.find(
			"LoadingScreen.show_screen(str(CONTEXT_LOADING[operation]))"
		) >= 0,
		"boot, Battle, Team Battle, and Expedition transitions all raise the one screen"
	)
	# Boot is the one caller that opens the screen before its busy window: it has
	# to cover the first frame, and `_ready()` runs before `root` will accept the
	# node, so the call is deferred. `_boot()` closing it from `_set_busy(false)`
	# is what keeps that safe.
	_check(
		shell_source.find(
			"LoadingScreen.show_screen.call_deferred(\"STATUS_LOADING\", true)"
		) >= 0,
		"boot opens the loading screen at frame zero"
	)
	var boot_start := shell_source.find("func _boot()")
	var boot_end := shell_source.find("\n\nfunc _reload_roster", boot_start)
	var boot_cover := (
		shell_source.substr(boot_start, boot_end - boot_start)
		if boot_start >= 0 and boot_end > boot_start
		else ""
	)
	# A warm boot from the cache used to skip the screen entirely, which is the
	# one boot a player sees most often.
	_check(
		boot_cover.find("if not from_cache:\n\t\t\tLoadingScreen") < 0
		and boot_cover.find("LoadingScreen.show_screen(\"STATUS_LOADING\")") >= 0,
		"the art wait stays covered on a warm boot too"
	)
	# The busy flag owns the hide, so no error path can leave the screen stuck.
	_check(
		_set_busy_body(shell_source).find("LoadingScreen.hide_screen()") >= 0,
		"the shell releases the loading screen from _set_busy"
	)
	_check(
		_set_busy_body(expedition_source).find("LoadingScreen.hide_screen()") >= 0,
		"Expedition releases the loading screen from _set_busy"
	)
	# Per-node Expedition steps keep the map the player is already reading, so the
	# screen only rides the two operations that swap the whole context. The class
	# is read as source, not imported: naming it here would compile the script
	# before the autoloads it references exist under --script.
	var context_start := expedition_source.find("const CONTEXT_LOADING")
	var context_end := expedition_source.find("}", context_start)
	var context_body := (
		expedition_source.substr(context_start, context_end - context_start)
		if context_start >= 0 and context_end > context_start
		else ""
	)
	_check(
		context_body.count("\":") == 2
		and context_body.find("\"start_run\":") >= 0
		and context_body.find("\"abandon\":") >= 0,
		"only Expedition context swaps raise the loading screen inside a run"
	)


## The dash may only ever move forward while the player can see it. Sampling past
## one full lap is the point: a bar that eases back the way the first version did
## would show a run of gradual decreases here, while the real sweep only ever
## drops in one step, back to its off-screen entry point.
func _check_loading_sweep_never_reverses(screen: LoadingScreen) -> void:
	const SAMPLES := 18
	var interval := LoadingScreen.SWEEP_SEC * 1.6 / float(SAMPLES)
	var bounds: Vector2 = screen.sweep_bounds()
	_check(
		bounds.x < 0.0 and bounds.y > 0.0,
		"the dash enters and leaves outside the clipped track so the wrap is unseen"
	)
	# A wrap hands back the whole lap in one step, while a bar easing backwards
	# could only ever hand back a sample of travel, so the size of the drop tells
	# them apart without depending on frame pacing. A fixed landing ceiling does
	# depend on it: one slow frame carries the dash a few pixels further past its
	# entry point, and the wrap then reads as a retreat.
	var lap := bounds.y - bounds.x
	var previous: float = screen.sweep_x()
	var wraps := 0
	var retreat := ""
	for _i in SAMPLES:
		await create_timer(interval).timeout
		var current: float = screen.sweep_x()
		if current < previous:
			if previous - current > lap * 0.5:
				wraps += 1
			else:
				retreat = "%.1f -> %.1f" % [previous, current]
		previous = current
	_check(retreat.is_empty(), "the dash never walks backwards in view: %s" % retreat)
	_check(wraps > 0, "the dash keeps looping instead of parking at the far end")


## A body ends at the next thing written at column zero, whatever it is: the
## following `func`, a `static func`, or the `##` block that introduces one.
## Stopping only at `func` swallows the whole next function whenever a doc
## comment sits between the two, which quietly makes any scan of the body a scan
## of its neighbour as well.
static func _func_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var body := PackedStringArray()
	var lines := source.substr(start).split("\n")
	for i in lines.size():
		var line := lines[i]
		if i > 0 and not line.is_empty() and not line.begins_with("\t"):
			break
		body.append(line)
	return "\n".join(body)


static func _set_busy_body(source: String) -> String:
	return _func_body(source, "func _set_busy(")


func _check_music(scene: Node) -> void:
	_check(AudioServer.get_bus_index("Music") > 0, "music rides a bus of its own")
	var missing := ""
	for cue: StringName in MusicDirector.TRACKS:
		var path := str(MusicDirector.TRACKS[cue])
		if not ResourceLoader.exists(path):
			missing = path
	_check(missing.is_empty(), "every music cue resolves to an imported track: %s" % missing)

	# The shell picks the cue; the director only obeys. Off-tree the battle views
	# are null, which is exactly the state a boot before the first frame is in.
	_check_eq(scene.call("_music_cue"), &"lobby", "a shell outside Battle asks for lobby music")

	var battle_view: Variant = (load("res://scenes/ui/battle_view.tscn") as PackedScene).instantiate()
	root.add_child(battle_view)
	await process_frame
	var battle_view_before: Variant = scene.get("_battle_view")
	var destination_before := int(scene.get("_destination"))
	scene.set("_battle_view", battle_view)
	scene.set("_destination", BottomNav.BATTLE)
	battle_view.visible = true
	battle_view.show_duel_mode()
	battle_view.set_session({
		"id": "music-duel",
		"status": "active",
		"turn_number": 1,
		"player_snapshot": {"name": "Velumi", "element": "spark", "stage": 1},
		"bot_snapshot": {"name": "Veridian", "element": "flow", "stage": 1},
		"state": {
			"player": {"hp": 100, "max_hp": 100, "momentum": 0, "spd": 10},
			"bot": {"hp": 100, "max_hp": 100, "momentum": 0, "spd": 10},
		},
	})
	_check_eq(scene.call("_music_cue"), &"battle", "a visible Duel arena asks for battle music")
	battle_view.show_team_mode()
	_check(
		battle_view.has_session() and not battle_view.is_duel_arena_open(),
		"switching modes can leave a stale Duel session hidden behind the Battle lobby"
	)
	_check_eq(
		scene.call("_music_cue"),
		&"lobby",
		"a hidden stale Duel session cannot keep battle music in the mode lobby"
	)
	battle_view.show_duel_mode()
	battle_view.set_lobby({})

	var team_view: Variant = (
		load("res://scenes/ui/team_battle_view.tscn") as PackedScene
	).instantiate()
	root.add_child(team_view)
	await process_frame
	var team_view_before: Variant = scene.get("_team_battle_view")
	scene.set("_team_battle_view", team_view)
	team_view.set("_session", {"id": "music-team", "status": "lost"})
	var team_arena := team_view.find_child("TeamArena", true, false) as Control
	team_view.visible = true
	team_arena.visible = true
	_check_eq(
		scene.call("_music_cue"),
		&"battle",
		"a visible Team Battle arena asks for battle music"
	)
	team_view.close_mode()
	_check(
		team_view.is_arena_open() and not team_view.visible,
		"leaving a terminal Team Battle can hide the mode while its arena state remains"
	)
	_check_eq(
		scene.call("_music_cue"),
		&"lobby",
		"a hidden Team Battle arena cannot keep music after returning to the lobby"
	)
	scene.set("_team_battle_view", team_view_before)
	team_view.queue_free()
	scene.set("_battle_view", battle_view_before)
	scene.set("_destination", destination_before)
	battle_view.queue_free()

	var music := MusicDirector.new()
	root.add_child(music)
	await process_frame
	music.play(&"lobby")
	_check(
		music.current_cue() == &"lobby" and music.is_sounding(),
		"the lobby cue starts sounding"
	)
	# set() stays silent when a property is missing, so a stream type that renames
	# its loop flag would only surface as music dying after one pass.
	var players: Array = music.get("_players")
	var playing: AudioStreamPlayer = players[music.get("_active")]
	_check(
		playing.stream != null and bool(playing.stream.get(&"loop")),
		"the cue stream loops instead of falling silent after one pass"
	)
	await create_timer(0.6).timeout
	var lobby_left_at := music.playback_position()
	_check(lobby_left_at > 0.0, "the lobby track advances while it plays")
	music.play(&"battle")
	_check(music.current_cue() == &"battle", "entering a fight swaps the cue")
	music.play(&"lobby")
	_check(
		music.playback_position() >= lobby_left_at,
		"returning to the lobby resumes instead of restarting the seven-minute track"
	)

	music.set_enabled(false)
	await create_timer(MusicDirector.FADE_SEC + 0.3).timeout
	_check(not music.is_sounding(), "muting fades the track out and stops it")
	music.set_enabled(true)
	_check(music.is_sounding(), "unmuting brings the same cue back")
	music.queue_free()


## A Tween's own clock is not wall clock: under `--headless` it lags by a frame
## or two, so sleeping a hair longer than an animation's duration is not a proof
## that the animation landed. Measured on the bottom sheet, 417 ms of wall time
## left its 0.38 s entry tween at 0.368 s and still running, parking the panel
## 0.002 px above the bottom edge — one step short of the resting offsets, which
## is a flake and not a layout bug. The meter tween read 72.99 of 73.0 the same
## way. Frame pacing here averages 24 ms and has been seen at 62 ms, so no fixed
## sleep buys a safe margin; wait for the animation itself. The deadline only
## keeps a stuck tween from hanging the suite instead of failing it.
static func _mouse_press() -> InputEventMouseButton:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	return press


static func _touch_press() -> InputEventScreenTouch:
	var press := InputEventScreenTouch.new()
	press.pressed = true
	return press


func _await_juice_settled(target: Object, meta_key: StringName = UiJuice.META_TWEEN) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		var tween: Variant = target.get_meta(meta_key) if target.has_meta(meta_key) else null
		if not (tween is Tween and (tween as Tween).is_valid() and (tween as Tween).is_running()):
			return
		await process_frame
	# Say so here rather than letting the caller report a panel two pixels out of
	# place: that reading is what sent this flake to the layout code first.
	_check(false, "a UiJuice tween never settled: %s" % meta_key)


func _check_full_rect(node: Control, label: String) -> void:
	_check(node != null, "%s must exist" % label)
	if node == null:
		return
	_check_eq(node.anchor_left, 0.0, "%s left anchor" % label)
	_check_eq(node.anchor_top, 0.0, "%s top anchor" % label)
	_check_eq(node.anchor_right, 1.0, "%s right anchor" % label)
	_check_eq(node.anchor_bottom, 1.0, "%s bottom anchor" % label)
	_check_eq(node.offset_left, 0.0, "%s left offset" % label)
	_check_eq(node.offset_top, 0.0, "%s top offset" % label)
	_check_eq(node.offset_right, 0.0, "%s right offset" % label)
	_check_eq(node.offset_bottom, 0.0, "%s bottom offset" % label)


func _touch_blockers(scroll: ScrollContainer) -> PackedStringArray:
	var blockers := PackedStringArray()
	_collect_touch_blockers(scroll, blockers)
	return blockers


func _collect_touch_blockers(node: Node, blockers: PackedStringArray) -> void:
	for child: Node in node.get_children():
		var control := child as Control
		if control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			blockers.append(control.name)
		_collect_touch_blockers(child, blockers)


## Pada viewport pendek sebagian besar panel berada di luar rect scroll, dan menekan
## di luar sana tidak mengenai apa pun, jadi kartu ujinya dipilih dari yang benar-benar
## terlihat alih-alih dipatok namanya.
func _card_under_finger(scroll: ScrollContainer) -> Control:
	return _find_card(scroll, scroll.get_global_rect())


func _find_card(node: Node, view: Rect2) -> Control:
	for child: Node in node.get_children():
		var card := child as PanelContainer
		if card != null and card.is_visible_in_tree():
			if card.get_global_rect().intersection(view).size.y >= TOUCH_MIN:
				return card
		var nested := _find_card(child, view)
		if nested != null:
			return nested
	return null


## Menggulir lewat gesture, bukan dengan menulis `scroll_vertical`: yang rusak di
## APK adalah jalur input, dan menulis properti langsung tetap lulus walaupun setiap
## kartu menelan gesture-nya. Android mengubah sentuh menjadi event mouse, dan di
## situlah ScrollContainer men-drag — bukan dari `InputEventScreenDrag`.
func _drag_scrolls(viewport: SubViewport, scroll: ScrollContainer, from: Control) -> bool:
	if from == null:
		return false
	var was_emulating := Input.is_emulating_touch_from_mouse()
	# ScrollContainer menolak men-drag ketika DisplayServer bilang tidak ada layar
	# sentuh, dan headless memang bilang begitu; Android sebaliknya.
	Input.set_emulate_touch_from_mouse(true)
	scroll.scroll_vertical = 0
	await process_frame
	var start := from.get_global_rect().intersection(scroll.get_global_rect()).get_center()
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	viewport.push_input(press, true)
	await process_frame
	for step in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.position = start - Vector2(0.0, 24.0 * step)
		motion.relative = Vector2(0.0, -24.0)
		viewport.push_input(motion, true)
		await process_frame
	var scrolled := scroll.scroll_vertical > 0
	var release := InputEventMouseButton.new()
	release.position = start - Vector2(0.0, 192.0)
	release.button_index = MOUSE_BUTTON_LEFT
	viewport.push_input(release, true)
	await process_frame
	Input.set_emulate_touch_from_mouse(was_emulating)
	return scrolled


## Pasangan dari `_drag_scrolls`: menurunkan kartu ke PASS hanya aman selama tap
## bersih tetap sampai ke tombol di dalamnya.
func _tap(viewport: SubViewport, target: Control) -> void:
	var was_emulating := Input.is_emulating_touch_from_mouse()
	Input.set_emulate_touch_from_mouse(true)
	var at := target.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = at
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)
		await process_frame
	Input.set_emulate_touch_from_mouse(was_emulating)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: got %s, wanted %s" % [message, str(actual), str(expected)])


func _finish() -> void:
	if _failures.is_empty():
		print("test_scan_ui: OK (%d checks)" % _checks)
		quit(0)
		return
	printerr("test_scan_ui: FAILED %d of %d checks" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - %s" % failure)
	quit(1)
