extends SceneTree

## Free contract test for the production mobile shell. The scene is instantiated
## off-tree, so no authentication or network requests run.

const TOUCH_MIN := 96.0
const BATTLE_SCALE := preload("res://scripts/battle_scale.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _requested_delete_id := ""
var _requested_evolve_row: Dictionary = {}
var _requested_rename_id := ""
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
		"HomeView", "ScanView", "BattleView", "CollectionView",
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
	var details := scene.find_child("AnimaDetailsView", true, false) as Control
	var seeker_profile := scene.find_child("SeekerProfileView", true, false) as Control
	var atlas := scene.find_child("AtlasView", true, false) as Control
	_check(home != null and home.visible, "Home is the default destination")
	_check(scan != null and not scan.visible, "Scan starts hidden")
	_check(battle != null and not battle.visible, "Battle starts hidden")
	_check(collection != null and not collection.visible, "Collection starts hidden")
	_check(details != null and not details.visible, "Details starts hidden")
	_check(seeker_profile != null and not seeker_profile.visible, "Seeker profile starts hidden")
	_check(atlas != null and not atlas.visible, "Atlas starts hidden")

	for name in [
		"ScanButton", "HomeNavButton", "ScanNavButton", "BattleNavButton",
		"CollectionNavButton", "MenuNavButton",
		"FeedButton", "CleanButton", "SleepButton", "PlayButton", "EditAnimaNameButton",
		"DeleteAnimaButton", "GalleryPublishButton", "EvolveAnimaButton", "AtlasBack", "AtlasLoadMore",
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
		"OnboardingSubmit", "SeekerProfileBack", "RenameSeeker",
		"ChapterPush", "MenuProfile", "MenuAtlas", "MenuSettings",
		"SeekerAccount", "SeekerHelp", "DeleteAccount",
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
		_check_eq(list.max_columns, 2, "collection uses two columns")
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
			"PrimaryButton", "DangerButton", "CareDock", "BottomNavPanel", "NavTabButton", "ToastPanel",
			"NeedChip", "NeedChipLow",
		]:
			_check(
				margin.theme.get_type_variation_base(StringName(variation)) != StringName(),
				"theme must provide %s" % variation
			)

	var background := scene.find_child("Background", true, false) as Node2D
	_check(background != null and background.get_script() != null, "procedural background remains attached")
	_check(scene.find_child("TopHud", true, false) is PanelContainer, "compact resource HUD must exist")
	var animas_chip := scene.find_child("AnimasChip", true, false) as PanelContainer
	var cores_chip := scene.find_child("CoresChip", true, false) as PanelContainer
	var bits_chip := scene.find_child("BitsChip", true, false) as PanelContainer
	_check(animas_chip != null and animas_chip.get_script() != null, "HUD uses the shared Animas chip")
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
		and String(shop.get_parent().name) == "ToastLayer",
		"Shop overlays below Bits instead of splitting the HUD resource row"
	)
	_check(
		bag.get_parent() == shop.get_parent(),
		"Bag sits on the same overlay row as Shop"
	)
	_check(
		shop.custom_minimum_size == bits_chip.custom_minimum_size,
		"Shop matches the Bits chip press target"
	)
	_check(
		bag.custom_minimum_size == shop.custom_minimum_size,
		"Bag matches the Shop chip press target"
	)
	_check(
		animas_chip.custom_minimum_size.y >= TOUCH_MIN
		and cores_chip.custom_minimum_size.y >= TOUCH_MIN
		and bits_chip.custom_minimum_size.y >= TOUCH_MIN,
		"interactive resource chips expose 96px press targets"
	)
	for chip in [animas_chip, cores_chip, bits_chip, shop, bag]:
		var column := chip.get_node_or_null("Column") as BoxContainer
		_check(
			column != null and column.alignment == BoxContainer.ALIGNMENT_CENTER,
			"%s centers its content inside the press target" % chip.name
		)
	_check(
		shop.find_child("Icon", true, false) is TextureRect,
		"Shop chip has an icon slot"
	)
	_check(
		bag.find_child("Icon", true, false) is TextureRect,
		"Bag chip has an icon slot"
	)
	_check(
		scene.find_child("BagGutter", true, false) == null
		and scene.find_child("ShopGutter", true, false) == null,
		"non-Home headers do not reserve space for hidden Bag and Shop buttons"
	)
	_check(
		scene.find_child("BattlePickSheet", true, false) != null,
		"Battle lobby picker lives on the shell overlay"
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
	_check(scene.find_child("PoseRow", true, false) == null, "debug pose controls must not ship in production")
	var shell_modal := scene.find_child("ShellModal", true, false) as Control
	var modal_panel := scene.find_child("ModalPanel", true, false) as PanelContainer
	var modal_input := scene.find_child("ModalInput", true, false) as LineEdit
	var modal_cancel := scene.find_child("CancelButton", true, false) as Button
	var modal_primary := scene.find_child("PrimaryButton", true, false) as Button
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
		and modal_cancel.custom_minimum_size.y >= TOUCH_MIN,
		"shared modal actions meet the touch target"
	)
	_check(
		modal_input != null
		and modal_input.max_length == 32
		and modal_input.custom_minimum_size.y >= TOUCH_MIN,
		"shared input mode enforces the server name length and touch target"
	)
	var shell_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		shell_source.find("var show_chrome := _destination == BottomNav.HOME and not immersive") >= 0
		and shell_source.find("_shop_button.visible = show_chrome") >= 0
		and shell_source.find("_bag_button.visible = show_chrome") >= 0
		and shell_source.find("_top_hud.visible = not immersive") >= 0
		and shell_source.find("_bottom_nav.visible = not immersive") >= 0
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
		shell_source.find("_animas_chip.pressed.connect(_open_collection)") >= 0,
		"Animas chip navigates to Collection"
	)
	_check(
		shell_source.find("NOTIFICATION_WM_GO_BACK_REQUEST") >= 0
		and shell_source.find("_handle_back(true)") >= 0
		and shell_source.find("STATUS_NEED_CORE") >= 0,
		"Android back closes overlays and empty Cores block the camera"
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

	var scan_button := scene.find_child("ScanButton", true, false) as Button
	if scan_button != null:
		_check_eq(scan_button.theme_type_variation, &"PrimaryButton", "Scan remains the signature CTA")
	var scan_nav := scene.find_child("ScanNavButton", true, false) as Button
	if scan_nav != null:
		_check_eq(scan_nav.theme_type_variation, &"ScanTabButton", "Scan is emphasized when Cores remain")
		var nav := scene.find_child("BottomNav", true, false)
		if nav != null and nav.has_method("set_scan_emphasized"):
			nav.set_scan_emphasized(false)
			_check_eq(
				scan_nav.theme_type_variation,
				&"NavTabButton",
				"Scan nav matches other tabs when Cores are empty"
			)
			nav.set_scan_emphasized(true)

	var juice_probe := Button.new()
	juice_probe.custom_minimum_size = Vector2(120.0, 96.0)
	root.add_child(juice_probe)
	await process_frame
	UiJuice.install_button(juice_probe)
	_check(juice_probe.has_meta(&"_scanima_juice_installed"), "button motion installs idempotently")
	juice_probe.scale = Vector2(0.5, 0.5)
	UiJuice.reveal(juice_probe)
	await create_timer(0.40).timeout
	_check(absf(juice_probe.scale.x - 1.0) < 0.05, "reveal animates scale to normal")
	var meter_probe := ProgressBar.new()
	meter_probe.custom_minimum_size = Vector2(240.0, 32.0)
	root.add_child(meter_probe)
	await process_frame
	meter_probe.value = 0.0
	UiJuice.tween_meter(meter_probe, 73.0)
	await create_timer(0.45).timeout
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
	_check(
		flow_source.find("func _celebrate_level_up") >= 0
		and flow_source.find("Sfx.play(Sfx.CUE_LEVEL_UP)") > flow_source.find("func _celebrate_level_up"),
		"Level Up SFX stays on the shell banner, not a restyled button"
	)
	Sfx.play(Sfx.CUE_STRIKE)
	var sfx_host := root.get_node_or_null("SfxHost")
	_check(sfx_host != null, "first gameplay cue mounts the shared SFX host")

	var care_dock := scene.find_child("CareDock", true, false) as PanelContainer
	_check(care_dock != null, "CareDock must exist")
	if care_dock != null:
		_check(not care_dock.visible, "care stays hidden before an Anima loads")
	_check(scene.find_child("CareSummary", true, false) is Label, "EXP summary has a label")
	var level_up := scene.find_child("LevelUpBanner", true, false) as Control
	_check(level_up != null, "level-up banner exists")
	if level_up != null:
		_check(not level_up.visible, "level-up banner starts hidden")
		_check_eq(
			level_up.mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"level-up banner does not steal taps"
		)
		var level_up_column := scene.find_child("LevelUpColumn", true, false) as Control
		_check(
			level_up_column != null and level_up_column.anchor_top <= 0.22,
			"level-up copy sits in the identity band above the Anima"
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
		"keep",
		"stretch keep mengunci crop background saat window di-resize"
	)
	for size in [Vector2(720, 1280), Vector2(720, 1602), Vector2(360, 640), Vector2(412, 915), Vector2(1080, 1920)]:
		var pos: Vector2 = script.stage_position_for(size, Vector4.ZERO)
		_check(is_equal_approx(pos.x, size.x * 0.5), "Stage stays horizontally centered at %s" % size)
		_check(pos.y > 0.0 and pos.y < size.y, "Stage stays inside %s" % size)

	var inset_pos: Vector2 = script.stage_position_for(Vector2(720, 1280), Vector4(0, 80, 0, 120))
	_check(inset_pos.y > 80.0 and inset_pos.y < 1160.0, "Stage stays inside safe areas")

	var incubator := scene.find_child("Incubator", true, false) as Node2D
	_check(incubator != null, "Stage keeps its Incubator")
	if incubator != null:
		_check(not incubator.visible, "Incubator starts hidden")
		_check_eq(incubator.position, Vector2.ZERO, "Incubator shares the Stage ground anchor")
	var anima := scene.find_child("Anima", true, false) as AnimatedSprite2D
	_check(anima != null and not anima.visible, "cached art stays hidden until server care is known")
	var first_effect := scene.find_child("FirstAnimaEffect", true, false) as Node2D
	_check(first_effect != null and not first_effect.visible, "first-Anima scanner starts hidden")
	_test_care_feedback_is_immediate()
	_test_collection_routes_are_explicit()
	_test_hatch_offers_rename()
	_test_header_uses_ready_roster()
	_test_present_toast_respects_sleep()
	_test_battle_reward_is_authoritative()
	_test_battle_art_has_no_global_toast()
	_test_battle_turn_prediction(scene)
	_test_home_tap_interaction(scene)

	await _check_music(scene)

	scene.free()
	await _test_anima_tap_reactions()
	await _test_shared_components()
	await _test_scan_phase_visuals()
	await _test_seeker_ui()
	await _test_battle_view()
	await _test_team_battle_view()
	await _test_expedition_view()
	await _test_battle_pick_sheet()
	await _test_collection_bottom_sheet()
	await _test_atlas_view()
	await _test_profile_info_rows()
	await _test_anima_delete_action()
	await _test_evolve_profile_cta()
	await _test_home_care_actions()
	await _test_bottom_nav_busy()
	await _test_incubator_effect()
	_finish()


func _test_shared_components() -> void:
	var modal = (load("res://scenes/ui/ui_modal.tscn") as PackedScene).instantiate()
	root.add_child(modal)
	await process_frame
	var modal_input := modal.find_child("ModalInput", true, false) as LineEdit
	var modal_cancel := modal.find_child("CancelButton", true, false) as Button
	var modal_primary := modal.find_child("PrimaryButton", true, false) as Button
	modal.open_info("Info", "Short body", "Got It")
	_check(modal.visible and not modal_input.visible and not modal_cancel.visible, "UiModal info mode is compact")
	modal.open_confirm("Delete", "Danger body", "Delete", "Cancel", true)
	_check(
		modal_cancel.visible and modal_primary.theme_type_variation == &"DangerButton",
		"UiModal danger-confirm mode exposes safe cancel and danger action"
	)
	modal.open_input("Rename", "Prompt", "Velumi", "Save", "Cancel", "Name")
	_check(
		modal_input.visible and modal_input.text == "Velumi" and modal_cancel.visible,
		"UiModal input mode exposes the current value and Cancel"
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
	chip.set_icon(load("res://assets/icons/shopping-bag.svg") as Texture2D)
	var chip_column := chip.get_node_or_null("Column") as BoxContainer
	_check(chip_icon != null and chip_icon.visible and chip_icon.texture != null, "ResourceChip can show a Shop icon")
	_check(
		chip_column != null and chip_column.get_theme_constant("separation") >= 8,
		"Shop icon keeps a gap above the label"
	)

	var sheet = (load("res://scenes/ui/ui_bottom_sheet.tscn") as PackedScene).instantiate()
	root.add_child(sheet)
	await process_frame
	sheet.open()
	_check(sheet.visible, "UiBottomSheet opens through shared chrome")
	sheet.close()
	await create_timer(0.30).timeout
	_check(not sheet.visible, "UiBottomSheet closes after its dismiss animation")

	var fresh = (load("res://scenes/ui/ui_bottom_sheet.tscn") as PackedScene).instantiate()
	root.add_child(fresh)
	await fresh.open()
	await create_timer(0.40).timeout
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
		tap_body.find("_say(tr(\"FEEDBACK_PURCHASE\"), true)") >= 0,
		"purchase feedback is transient instead of persisting above the Shop"
	)
	_check(
		tap_body.find("GameState.profile[\"bits\"] = bits_before") >= 0,
		"a rejected purchase puts the Bits it predicted back"
	)
	_test_optimistic_care()
	_test_summon_overlaps_portal()


## Mengganti companion memutar dissolve dan portal lebih dulu, jadi round trip
## `summon` habis di balik animasi yang memang harus jalan. Sprite tetap tidak
## ditukar sebelum server mengizinkan.
func _test_summon_overlaps_portal() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _activate_anima")
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
	var care_dock := scene.get_node_or_null(
		"UI/SafeMargin/Shell/ViewStack/HomeView/Column/CareDock"
	) as Control
	_check(
		care_dock != null and care_dock.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"care controls still capture their own taps"
	)


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


func _test_scan_phase_visuals() -> void:
	var packed := load("res://scenes/ui/scan_view.tscn") as PackedScene
	var view := packed.instantiate()
	root.add_child(view)
	await process_frame
	var idle_graphic := view.find_child("IdleGraphic", true, false) as TextureRect
	var preview := view.find_child("PreviewPanel", true, false) as PanelContainer
	var overlay := view.find_child("ScanOverlay", true, false) as Control
	_check(idle_graphic != null and idle_graphic.visible, "idle Scan shows the camera graphic")
	_check(overlay != null and not overlay.visible, "scan overlay starts hidden")

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
	for slug in ["natural", "cute", "brave", "wild", "sinister"]:
		var vibe_button := view.find_child("Vibe%s" % slug.capitalize(), true, false) as Button
		_check(
			vibe_button != null
			and vibe_button.custom_minimum_size.y >= TOUCH_MIN
			and vibe_button.focus_mode == Control.FOCUS_ALL
			and not vibe_button.text.is_empty(),
			"%s Vibe stays a 96px labelled focus target" % slug
		)
	view.set_vibe("cute")
	var cute_button := view.find_child("VibeCute", true, false) as Button
	_check(
		view.vibe() == "cute"
		and cute_button != null
		and cute_button.theme_type_variation == &"PrimaryButton",
		"choosing Cute marks that chip without requiring another Scan tap"
	)
	view.set_phase(&"analyzing")
	_check(not vibe_block.visible, "analysis hides Vibe so the choice cannot change mid-scan")
	view.set_phase(&"idle")
	_check(vibe_block.visible and view.vibe() == "cute", "returning idle keeps the chosen Vibe")
	view.reset_vibe()
	_check_eq(view.vibe(), "natural", "a finished Scan returns the selector to Natural")
	var sign_in_requests: Array[String] = []
	view.sign_in_requested.connect(func() -> void: sign_in_requests.append("sign_in"))
	view.set_sign_in_required(true)
	_check(
		scan_button.text == tr("SCAN_SIGN_IN_ACTION")
		and hint.text == tr("SCAN_SIGN_IN_HINT")
		and not scan_button.disabled,
		"used guest Scan becomes an active Google sign-in CTA"
	)
	scan_button.pressed.emit()
	_check_eq(sign_in_requests.size(), 1, "guest Scan CTA requests sign-in instead of camera")

	view.queue_free()
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
		func(name: String, birth_year: Variant, gender: Variant) -> void:
			submitted.append({"name": name, "birth_year": birth_year, "gender": gender})
	)
	onboarding.show_for_profile()
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

	var menu = (load("res://scenes/ui/seeker_menu_sheet.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	menu.show_menu(true, true, true, true)
	_check(
		(menu.find_child("SeekerMenuTitle", true, false) as Label).text == tr("SETTINGS_TITLE"),
		"Settings menu uses the shared title"
	)
	_check(
		(menu.find_child("SeekerAccount", true, false) as Button).text
			== tr("SEEKER_SIGN_IN_GOOGLE"),
		"guest account action offers Google sign-in"
	)
	_check(
		(menu.find_child("ChapterPush", true, false) as CheckButton).visible
		and (menu.find_child("ChapterPush", true, false) as CheckButton).button_pressed,
		"OS chapter push is an explicit opt-in shown only when its native adapter exists"
	)
	_check(
		(menu.find_child("DeleteAccount", true, false) as Button).visible,
		"guest can delete the anonymous account and its data"
	)
	var delete_account := menu.find_child("DeleteAccount", true, false) as Button
	_check(
		menu.find_child("ContentScroll", true, false) is ScrollContainer
		and menu.find_child("DangerDivider", true, false) is HSeparator
		and delete_account.theme_type_variation == &"DangerButton",
		"Seeker menu scrolls safely and separates the destructive account action"
	)
	_check(
		(menu.find_child("MusicEnabled", true, false) as CheckButton).button_pressed,
		"music plays by default and can be turned off from Settings"
	)
	menu.show_menu(true, false, false, false)
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
	}, null)
	var rows := profile.find_child("SeekerRows", true, false) as VBoxContainer
	_check_eq(rows.get_child_count(), 6, "Seeker profile shows six server-authoritative stats")
	_check(
		(profile.find_child("SeekerProfileName", true, false) as Label).text == "Nova_13",
		"Seeker profile shows the unique name"
	)
	var trophy_rows: Array[Dictionary] = []
	for index in 4:
		trophy_rows.append({"expedition_trophies": {
			"id": "60000000-0000-4000-8000-00000000000%d" % index,
			"display_name": "Trail Trophy %d" % (index + 1),
		}})
	profile.set_trophies(trophy_rows)
	var trophy_grid := profile.find_child("TrophyGrid", true, false) as GridContainer
	var trophy_empty := profile.find_child("TrophyEmpty", true, false) as Label
	_check(
		trophy_grid.visible
		and not trophy_empty.visible
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
	_check(
		trophy_empty.visible and not trophy_grid.visible,
		"an account without a Core sees the earn-one hint instead of an empty grid"
	)
	profile.set_profile({"seeker_name": null}, null)
	_check(
		(profile.find_child("SeekerProfileName", true, false) as Label).text
			== tr("SEEKER_UNNAMED"),
		"incomplete profile never renders a null wire value"
	)

	onboarding.queue_free()
	menu.queue_free()
	profile.queue_free()
	await process_frame


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
	_check(item.self_modulate.a > 0.9, "JSON null item_used_id does not dim Item")
	_check(_item_picker_opens, "unused Item opens the battle picker")
	session["item_used_id"] = "power_chip"
	view.set_session(session, loaded, loaded)
	_item_picker_opens = false
	view.call("_request_item")
	_check(
		item.self_modulate.a < 0.5 and not _item_picker_opens,
		"a real item_used_id dims Item and blocks a second use"
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
	_check(
		not header.visible
		and arena.is_ancestor_of(forfeit)
		and forfeit.flat
		and forfeit.custom_minimum_size.y >= TOUCH_MIN,
		"active Battle uses a quiet Forfeit action with a full touch target inside its HUD"
	)
	_check(
		not feedback.visible
		and is_equal_approx(footer.custom_minimum_size.y, 104.0),
		"Battle command footer keeps the four primary actions without idle copy"
	)
	_check(player_sprite.flip_h and not bot_sprite.flip_h, "Battle fighters face each other")
	_check(
		is_equal_approx(active_ground_y, active_arena_height * BATTLE_SCALE.GROUND_Y_RATIO),
		"Battle fighters stand near the arena floor"
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
	view.set_error("BATTLE_EXPIRED")
	_check(
		result.visible and content.visible and not lobby.visible,
		"resume failure keeps one recoverable result overlay"
	)

	view.queue_free()
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
	_check(
		resume_body.find('res.error in ["TEAM_BATTLE_NOT_FOUND", "INVALID_SESSION_ID"]') >= 0
		and resume_body.find("GameState.finish_team_battle()") >= 0
		and flow_source.find("if _busy or _team_battle_demo_active:") >= 0
		and flow_source.find("_team_battle_demo_active = true") >= 0,
		"invalid or demo Team Battle sessions cannot trap the persisted hub state"
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
	view.set_builder(roster, team)
	var roster_list := view.find_child("TeamRosterList", true, false) as ItemList
	var save := view.find_child("TeamSaveButton", true, false) as Button
	_check(roster_list.item_count == 5, "Team builder lists the current roster")
	_check(roster_list.is_item_disabled(4), "unavailable Anima cannot be selected for a Team")
	_check(
		roster_list.get_item_icon(0) == thumbnail
		and roster_list.get_item_text(0).contains(tr("TEAM_ROSTER_READY"))
		and roster_list.get_item_text(4).contains(tr("BATTLE_PICK_LOW_ENERGY")),
		"Team builder shows Anima art and concise readiness"
	)
	roster_list.deselect_all()
	roster_list.call("sync_chosen")
	for index in 4:
		_tap_roster_item(roster_list, index)
	var selected_style := roster_list.get_theme_stylebox("selected_focus") as StyleBoxFlat
	var cursor_style := roster_list.get_theme_stylebox("cursor")
	_check(
		not save.disabled
		and roster_list.get_selected_items().size() == 4
		and roster_list.get_script().resource_path == "res://scripts/team_roster_list.gd"
		and selected_style.border_color.a > 0.0
		and roster_list.get_theme_color("font_selected_color").a == 1.0
		and cursor_style is StyleBoxEmpty
		and roster_list.get_theme_stylebox("hovered") is StyleBoxEmpty,
		"four taps keep four checked cards and enable Save without a stale count"
	)
	_tap_roster_item(roster_list, 4)
	_tap_roster_item(roster_list, 1)
	_check(
		save.disabled
		and roster_list.get_selected_items().size() == 3
		and not roster_list.is_selected(1),
		"tapping again releases a member and a blocked Anima never joins"
	)
	_tap_roster_item(roster_list, 1)
	_check(not save.disabled, "re-tapping restores the fourth member")
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
	_check(
		arena_background != null and not arena_background.visible,
		"Team Battle arena keeps zone art hidden without an Expedition background"
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
		and forfeit.get_index() == 2
		and not forfeit.flat,
		"active arena hides page chrome; Retreat is a regular support-row button"
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
	view.set_expedition_mode(true)
	view.set_arena_location("The Sugarworks — Zone 1")
	_check(
		turn.visible
		and turn.text.contains("Sugarworks")
		and arena_hud.offset_top >= 40.0,
		"Expedition arena shows the chapter-zone label above a lowered HUD"
	)
	view.set_expedition_mode(false)
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
	var primary_row := view.find_child("PrimaryRow", true, false) as HBoxContainer
	var support_row := view.find_child("SupportRow", true, false) as HBoxContainer
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
		and primary_row.get_child_count() == 3
		and support_row.get_child_count() == 3
		and special.theme_type_variation == &""
		and attack.custom_minimum_size.y >= TOUCH_MIN
		and special.custom_minimum_size.y >= TOUCH_MIN
		and not special.disabled,
		"Team arena uses a balanced 3+3 action grid"
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
	_check(
		team_source.find("_seeker_shadow.position = _seeker.position") >= 0
		and team_source.find("_seeker.position + Vector2(0.0, 4.0)") < 0,
		"Boss Seeker lowest opaque pixel meets the vertical center of its shadow"
	)
	var attack_fn := team_source.substr(team_source.find("func _play_attack"), 3600)
	_check(
		team_source.find("BATTLE_EVENT_ITEM") >= 0
		and team_source.find("BATTLE_EVENT_ATTACK") >= 0
		and team_source.find("BATTLE_EVENT_TIMEOUT") >= 0,
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
		{"type": "switch", "actor": "player", "from_slot": 0, "to_slot": 1},
		switched
	)
	_check(
		switch_camera_layer.scale.is_equal_approx(camera_after),
		"Switch applies the new framing before the next attack event"
	)
	_check(
		player_name.text.begins_with("Team 2") and player_name.text.contains(tr("LEVEL_SHORT")),
		"Switch replaces the active fighter after the Summon handoff"
	)
	session["state"]["player"]["active_slot"] = 0
	view.set_session(session, art_cache)
	var after_ko := session.duplicate(true)
	after_ko["turn_number"] = 9
	after_ko["state"]["turn"] = 9
	after_ko["state"]["player"]["forced_switch"] = true
	after_ko["state"]["player"]["roster"][0]["hp"] = 0
	after_ko["state"]["player"]["roster"][0]["momentum"] = 0
	await view.play_events([
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
	var player_sprite := view.find_child("TeamPlayerSprite", true, false)
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
	_check(
		team_leave != null and team_leave.visible
		and tr(team_leave.text) == tr("BATTLE_RETURN_LOBBY")
		and team_retry.text == tr("TEAM_RETRY"),
		"terminal Team result offers both a rematch and a way out"
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
		team_retry.text == tr("TEAM_RETRY")
		and not result_body.text.ends_with(team_blocked_line),
		"swapping the drained member back restores the Team rematch CTA"
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
		"copy": "Cotton enters with +1 PP.",
	}], ace_session, seeker_art)
	_check(not dialog.is_open(), "final ace line closes before Summon and passive finish")
	_check(seeker.animation == "intro_idle", "final ace sequence restores the Seeker idle pose")
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
	view.queue_free()
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
		and not controller_script.should_resume_error("NO_SUPPLIES"),
		"only stale or terminal encounter errors enter the bounded resume path"
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
		flow_source.find("EXPEDITION_LEVEL_UP_STATS_TITLE") >= 0
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
	var save_team := view.find_child("ExpeditionSaveTeam", true, false) as Button
	_check(
		roster_list.is_item_disabled(4) and not save_team.disabled
		and roster_list.get_script().resource_path == "res://scripts/team_roster_list.gd"
		and roster_list.get_theme_color("font_selected_color").a == 1.0,
		"Expedition Team keeps four visible checked selections and blocks low Energy"
	)
	_tap_roster_item(roster_list, 2)
	_check(
		save_team.disabled and roster_list.get_selected_items().size() == 3,
		"Expedition Save follows the tapped selection instead of Godot's raw state"
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
		builder_back.flat and builder_back.size_flags_horizontal != Control.SIZE_EXPAND_FILL,
		"Expedition Back stays compact while preserving its touch height"
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
	view.queue_free()
	await process_frame


func _test_battle_pick_sheet() -> void:
	var packed := load("res://scenes/ui/battle_pick_sheet.tscn") as PackedScene
	var sheet := packed.instantiate()
	root.add_child(sheet)
	await process_frame
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
	_check(sheet.visible and list != null and list.item_count == 2, "picker lists the roster")
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
	sheet.queue_free()
	await process_frame


func _test_collection_routes_are_explicit() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
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


func _test_collection_bottom_sheet() -> void:
	var packed := load("res://scenes/ui/collection_view.tscn") as PackedScene
	var collection := packed.instantiate()
	root.add_child(collection)
	await process_frame
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
	collection.queue_free()
	await process_frame


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
		and is_equal_approx(sheet.anchor_bottom, 1.0),
		"Atlas detail sheet is a full-rect child of AtlasView"
	)
	_check(view.has_method("_make_card"), "Anima Atlas scene exposes the AtlasView contract")
	_check(view.has_method("show_demo"), "Anima Atlas exposes a no-network visual QA path")
	for node_name: String in ["AtlasAll", "AtlasScanned", "AtlasExpedition", "AtlasDuel"]:
		_check(view.find_child(node_name, true, false) is Button, "%s filter exists" % node_name)
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
	_check(
		(discovered_column.get_child(1) as Label).text == "Sprig",
		"Atlas card shows the generated form name"
	)
	var discovered_meta := (discovered_column.get_child(2) as Label).text
	_check(
		discovered_meta.find("Plant · Stone") >= 0 and discovered_meta.find("Adult") >= 0,
		"Atlas card shows both elements and the registered form stage"
	)
	var hidden_column := silhouette.get_child(0) as VBoxContainer
	var hidden_portrait := hidden_column.get_child(0) as TextureRect
	_check(hidden_portrait.material is ShaderMaterial, "undiscovered Expedition art uses a true silhouette shader")
	_check(
		(hidden_column.get_child(1) as Label).text == "???",
		"Expedition silhouette does not reveal its name"
	)
	var detail_copy := str(view.call("_detail_copy", {
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
		"encounter_count": 2,
		"nickname": "PrivateNickname",
		"care": {"hunger": 1},
	}))
	_check(detail_copy.find("AtlasOwner") >= 0, "Duel Atlas detail includes the current Seeker name")
	_check(
		detail_copy.find("PrivateNickname") < 0 and detail_copy.find("hunger") < 0,
		"Atlas detail never exposes nickname or care state"
	)
	discovered.queue_free()
	silhouette.queue_free()
	await sheet.open()
	await create_timer(0.45).timeout
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


func _test_header_uses_ready_roster() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var count_start := source.find("func _refresh_anima_count")
	var count_end := source.find("\n\nfunc _set_busy", count_start)
	var count_body := source.substr(
		count_start, count_end - count_start
	) if count_start >= 0 and count_end > count_start else ""
	var populate_start := source.find("func _populate_collection")
	var populate_end := source.find("\n\nfunc _thumbnail_for", populate_start)
	var populate_body := source.substr(
		populate_start, populate_end - populate_start
	) if populate_start >= 0 and populate_end > populate_start else ""
	var header_start := source.find("func _refresh_header")
	var header_end := source.find("\n\nfunc _refresh_anima_count", header_start)
	var header_body := source.substr(
		header_start, header_end - header_start
	) if header_start >= 0 and header_end > header_start else ""
	_check(
		count_body.find("LocaleManager.format_integer(_roster.size())") >= 0,
		"HUD count is derived from the authenticated ready roster"
	)
	_check(
		populate_body.find("_refresh_anima_count()") >= 0,
		"every roster UI refresh also updates the HUD count"
	)
	_check(
		header_body.find("scan_charges") < 0,
		"scan charges remain an economy rule, not the displayed collection count"
	)


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
	_test_boot_cache_is_display_only()


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
func _test_boot_cache_is_display_only() -> void:
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
	for entry in ["func clear_account_state", "func discard_guest_local_state"]:
		var start := state.find(entry)
		var body := state.substr(start, state.find("\n\nfunc ", start) - start)
		_check(
			body.find("clear_boot_cache()") >= 0,
			"%s also drops the cached Home" % entry
		)


func _test_anima_delete_action() -> void:
	var packed := load("res://scenes/ui/anima_details_view.tscn") as PackedScene
	var details := packed.instantiate()
	root.add_child(details)
	await process_frame
	var rename := details.find_child("EditAnimaNameButton", true, false) as Button
	var button := details.find_child("DeleteAnimaButton", true, false) as Button
	_requested_delete_id = ""
	_requested_rename_id = ""
	details.rename_requested.connect(_capture_rename_request)
	details.delete_requested.connect(_capture_delete_request)
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
	_check(rename != null and not rename.disabled, "loaded profile enables rename")
	if rename != null:
		rename.pressed.emit()
	_check_eq(_requested_rename_id, "anima-delete-test", "Edit name emits the shown Anima id")
	_check(button != null and not button.disabled, "loaded profile enables Delete")
	_check(
		button != null
		and button.flat
		and button.theme_type_variation != &"DangerButton",
		"profile Delete is a quiet text action like Forfeit"
	)
	if button != null:
		button.pressed.emit()
	_check_eq(_requested_delete_id, "anima-delete-test", "Delete emits only the active Anima id")
	details.set_busy(true)
	_check(rename != null and rename.disabled, "network work disables rename")
	_check(button != null and button.disabled, "network work disables destructive action")
	details.queue_free()
	await process_frame


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
		flow_source.find("call_deferred(\"_show_rename\", anima_id, suggested)") >= 0
		and flow_source.find("func _evolution_suggested_name") >= 0
		and flow_source.find("str(body.get(\"suggested_name\", \"\"))") >= 0,
		"ritual Evolve menawarkan Rename terisi nama usulan model"
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
	_check(
		flow_source.find("not uses_evolution_ritual") >= 0,
		"Level 16/36 rollout tidak mengumumkan form sebelum ritual committed"
	)
	_check(
		flow_source.find("_evolution_art_error_reported") >= 0,
		"retry download art evolution tidak menumpuk toast setiap poll"
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
	incubator.queue_free()
	details.queue_free()
	await process_frame


func _capture_evolve_request(row: Dictionary) -> void:
	_requested_evolve_row = row.duplicate(true)


func _capture_delete_request(anima_id: String) -> void:
	_requested_delete_id = anima_id


func _capture_rename_request(anima_id: String) -> void:
	_requested_rename_id = anima_id


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
	var care_summary := home.find_child("CareSummary", true, false) as Label
	var stage_space := home.find_child("StageSpace", true, false) as Control
	var stage_footer_space := home.find_child("StageFooterSpace", true, false) as Control
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
	_check(primary.visible and not primary.disabled, "empty Home exposes its first-scan CTA")
	primary.pressed.emit()
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
	home.set_anima(row, false)
	_check_eq(home.shell_state(), &"ready", "loaded companion replaces the empty state")
	_check(not primary.visible, "ready Home hides its onboarding CTA")
	_check(care_summary.text.contains("EXP 3/5"), "Lv.2 still uses the first 5-EXP band")
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

	row["sleep_started_at"] = "2026-08-13T00:00:00Z"
	home.update_care(row, false)
	await process_frame
	_check(not feed.visible and not clean.visible and not play.visible, "sleep hides other care actions")
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


## Mirrors a real tap: Godot replaces the whole multi-selection, emits
## multi_selected from that pre-correction state, then emits item_clicked.
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
	return BossSeekerSheet.build(
		ImageTexture.create_from_image(image),
		{"version": 1, "frame_size": [300, 300], "poses": poses}
	)


func _dismiss_when_open(dialog: BossSeekerDialog) -> void:
	for _step in 180:
		if dialog != null and dialog.is_open():
			dialog.dismiss()
			return
		await process_frame


func _tap_roster_item(list: ItemList, index: int) -> void:
	if not list.is_item_disabled(index):
		list.select(index, true)
		list.multi_selected.emit(index, true)
	list.item_clicked.emit(index, Vector2.ZERO, MOUSE_BUTTON_LEFT)


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


func _check_full_rect(node: Control, label: String) -> void:
	_check(node != null, "%s must exist" % label)
	if node == null:
		return
	_check_eq(node.anchor_left, 0.0, "%s left anchor" % label)
	_check_eq(node.anchor_top, 0.0, "%s top anchor" % label)
	_check_eq(node.anchor_right, 1.0, "%s right anchor" % label)
	_check_eq(node.anchor_bottom, 1.0, "%s bottom anchor" % label)


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
