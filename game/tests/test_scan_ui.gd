extends SceneTree

## Free contract test for the production mobile shell. The scene is instantiated
## off-tree, so no authentication or network requests run.

const TOUCH_MIN := 96.0

var _checks := 0
var _failures: PackedStringArray = []
var _requested_delete_id := ""
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
	for name in ["HomeView", "ScanView", "BattleView", "CollectionView", "AnimaDetailsView"]:
		var view := scene.find_child(name, true, false) as Control
		_check(view != null, "%s must exist" % name)
		if view != null:
			_check_full_rect(view, name)

	var home := scene.find_child("HomeView", true, false) as Control
	var scan := scene.find_child("ScanView", true, false) as Control
	var battle := scene.find_child("BattleView", true, false) as Control
	var collection := scene.find_child("CollectionView", true, false) as Control
	var details := scene.find_child("AnimaDetailsView", true, false) as Control
	_check(home != null and home.visible, "Home is the default destination")
	_check(scan != null and not scan.visible, "Scan starts hidden")
	_check(battle != null and not battle.visible, "Battle starts hidden")
	_check(collection != null and not collection.visible, "Collection starts hidden")
	_check(details != null and not details.visible, "Details starts hidden")

	for name in [
		"ScanButton", "HomeNavButton", "ScanNavButton", "BattleNavButton",
		"CollectionNavButton", "AnimaNavButton",
		"FeedButton", "CleanButton", "SleepButton", "PlayButton", "EditAnimaNameButton",
		"DeleteAnimaButton",
		"HomePrimaryAction", "CollectionEmptyAction", "CollectionProfileButton",
		"CollectionSummonButton", "BattleStartButton", "BattleStrikeButton",
		"BattleSurgeButton", "BattleGuardButton", "BattleForfeitButton", "BattleRetryButton",
	]:
		var button := scene.find_child(name, true, false) as Button
		_check(button != null, "%s must exist" % name)
		if button != null:
			_check(
				button.custom_minimum_size.y >= TOUCH_MIN,
				"%s must be at least %.0f px tall" % [name, TOUCH_MIN]
			)

	var list := scene.find_child("AnimaList", true, false) as ItemList
	_check(list != null, "AnimaList must exist")
	if list != null:
		_check_eq(list.max_columns, 2, "collection uses two columns")
		_check_eq(list.fixed_icon_size, Vector2i(128, 128), "collection thumbnails are 128 px")
	var scan_flow := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		scan_flow.find("CareRules.collection_pose") >= 0
		and scan_flow.find("begin_visit()") >= 0
		and scan_flow.find("_populate_collection()") >= 0,
		"Collection thumbnails project Sleep or Idle when the tab opens"
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
	_check(
		animas_chip.custom_minimum_size.y >= TOUCH_MIN
		and cores_chip.custom_minimum_size.y >= TOUCH_MIN
		and bits_chip.custom_minimum_size.y >= TOUCH_MIN,
		"interactive resource chips expose 96px press targets"
	)
	for chip in [animas_chip, cores_chip, bits_chip]:
		var column := chip.get_node_or_null("Column") as BoxContainer
		_check(
			column != null and column.alignment == BoxContainer.ALIGNMENT_CENTER,
			"%s centers its content inside the press target" % chip.name
		)
	_check(scene.find_child("ScanCount", true, false) == null, "HUD no longer labels scan charges as a count")
	_check(scene.find_child("BottomNav", true, false) is PanelContainer, "bottom navigation must exist")
	var toast := scene.find_child("StatusPanel", true, false) as PanelContainer
	_check(toast != null, "floating feedback must exist")
	if toast != null:
		_check_eq(toast.anchor_top, 0.0, "toast pins below the HUD instead of mid-screen")
		_check_eq(toast.anchor_bottom, 0.0, "toast does not stretch through the Anima")
	_check(scene.find_child("PoseRow", true, false) == null, "debug pose controls must not ship in production")
	var shell_modal := scene.find_child("ShellModal", true, false) as Control
	var modal_panel := scene.find_child("ModalPanel", true, false) as PanelContainer
	var modal_input := scene.find_child("ModalInput", true, false) as LineEdit
	var modal_cancel := scene.find_child("CancelButton", true, false) as Button
	var modal_primary := scene.find_child("PrimaryButton", true, false) as Button
	_check(shell_modal != null and not shell_modal.visible, "shared shell modal starts hidden")
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
	UiJuice.install_button(juice_probe)
	_check(juice_probe.has_meta(&"_scanima_juice_installed"), "button motion installs idempotently")
	UiMotion.set_reduced_motion(true)
	juice_probe.scale = Vector2(0.5, 0.5)
	UiJuice.reveal(juice_probe)
	_check_eq(juice_probe.scale, Vector2.ONE, "reduced motion reveals without scaling")
	var meter_probe := ProgressBar.new()
	UiJuice.tween_meter(meter_probe, 73.0)
	_check_eq(meter_probe.value, 73.0, "reduced motion updates meters immediately")
	meter_probe.free()
	UiMotion.set_reduced_motion(false)
	juice_probe.free()

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
	for size in [Vector2(720, 1280), Vector2(360, 640), Vector2(412, 915), Vector2(1080, 1920)]:
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
	_test_home_tap_interaction(scene)

	scene.free()
	await _test_anima_tap_reactions()
	await _test_shared_components()
	await _test_scan_phase_visuals()
	await _test_battle_view()
	await _test_collection_bottom_sheet()
	await _test_profile_info_rows()
	await _test_anima_delete_action()
	await _test_home_care_actions()
	await _test_bottom_nav_busy()
	await _test_incubator_effect()
	_finish()


func _test_shared_components() -> void:
	UiMotion.set_reduced_motion(true)
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
	_check(not modal.visible, "UiModal closes immediately under Reduced Motion")

	var chip = (load("res://scenes/ui/resource_chip.tscn") as PackedScene).instantiate()
	root.add_child(chip)
	await process_frame
	chip.set_value_text("7")
	chip.set_name_text("Animas")
	chip.set_interactive(true, "Open Collection")
	var chip_action := chip.find_child("ActionButton", true, false) as Button
	_check(
		chip_action.visible and chip.custom_minimum_size.y >= TOUCH_MIN,
		"ResourceChip can expose a touch-safe action overlay"
	)

	var sheet = (load("res://scenes/ui/ui_bottom_sheet.tscn") as PackedScene).instantiate()
	root.add_child(sheet)
	await process_frame
	sheet.open()
	_check(sheet.visible, "UiBottomSheet opens through shared chrome")
	sheet.close()
	_check(not sheet.visible, "UiBottomSheet closes immediately under Reduced Motion")

	var skeleton = (load("res://scenes/ui/ui_skeleton.tscn") as PackedScene).instantiate()
	root.add_child(skeleton)
	skeleton.set_loading(true)
	_check(
		skeleton.visible and is_equal_approx(skeleton.modulate.a, 0.58),
		"UiSkeleton uses a static Reduced Motion state"
	)
	skeleton.set_loading(false)
	_check(not skeleton.visible, "UiSkeleton clears when authoritative data arrives")

	modal.queue_free()
	chip.queue_free()
	sheet.queue_free()
	skeleton.queue_free()
	await process_frame
	UiMotion.set_reduced_motion(false)


func _test_care_feedback_is_immediate() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _perform_care")
	var end := source.find("\n\nfunc _resume_pending_care", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	var feedback := body.find("_anima.care_feedback(action)")
	var request := body.find("await _send_pending_care")
	_check(feedback >= 0 and request > feedback, "care reacts before its network response")
	_check(
		body.find("_home_view.set_busy(true)") >= 0 and body.find("_set_busy(true)") < 0,
		"care locks only its action dock, not the whole shell"
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
	UiMotion.set_reduced_motion(false)
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

	UiMotion.set_reduced_motion(true)
	presenter.set_pose("idle")
	presenter.react_to_tap()
	await process_frame
	_check_eq(presenter.position, Vector2.ZERO, "Reduced Motion keeps a tapped Anima still")
	UiMotion.set_reduced_motion(false)

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
	UiMotion.set_reduced_motion(false)
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

	UiMotion.set_reduced_motion(true)
	view.set_phase(&"idle")
	view.set_phase(&"analyzing")
	_check(overlay.visible and not overlay.is_processing(), "Reduced Motion keeps a static scan overlay")

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

	view.queue_free()
	await process_frame
	UiMotion.set_reduced_motion(false)


func _test_battle_view() -> void:
	UiMotion.set_reduced_motion(true)
	var packed := load("res://scenes/ui/battle_view.tscn") as PackedScene
	var view := packed.instantiate()
	root.add_child(view)
	await process_frame

	var lobby := view.find_child("BattleLobbyPanel", true, false) as Control
	var header := view.find_child("Header", true, false) as Control
	var content := view.find_child("BattleContent", true, false) as Control
	var result := view.find_child("BattleResultPanel", true, false) as Control
	var start := view.find_child("BattleStartButton", true, false) as Button
	var lobby_name := view.find_child("BattleLobbyName", true, false) as Label
	var lobby_meta := view.find_child("BattleLobbyMeta", true, false) as Label
	var strike := view.find_child("BattleStrikeButton", true, false) as Button
	var surge := view.find_child("BattleSurgeButton", true, false) as Button
	var guard := view.find_child("BattleGuardButton", true, false) as Button
	var strike_commit := view.find_child("BattleStrikeCommit", true, false) as ColorRect
	var surge_commit := view.find_child("BattleSurgeCommit", true, false) as ColorRect
	var guard_commit := view.find_child("BattleGuardCommit", true, false) as ColorRect
	var forfeit := view.find_child("BattleForfeitButton", true, false) as Button
	var player_hp := view.find_child("BattlePlayerHp", true, false) as ProgressBar
	var bot_hp := view.find_child("BattleBotHp", true, false) as ProgressBar
	var player_hp_value := view.find_child("BattlePlayerHpValue", true, false) as Label
	var bot_hp_value := view.find_child("BattleBotHpValue", true, false) as Label
	var daily_reward := view.find_child("BattleDailyReward", true, false) as Label
	var feedback := view.find_child("BattleFeedback", true, false) as Label
	var damage := view.find_child("BattleDamage", true, false) as Label
	var effectiveness := view.find_child("BattleEffectiveness", true, false) as Control
	var effectiveness_badge := view.find_child(
		"BattleEffectivenessBadge", true, false
	) as Control
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
	_check(not start.disabled, "ready awake active Anima can start Battle")
	var normal_daily_reward := {
		"earned": 2,
		"limit": 3,
		"remaining": 1,
		"rewarded": false,
		"server_now": "2026-08-13T23:59:00.000000+00:00",
		"reset_at": "2026-08-14T00:00:00+00:00",
	}
	view.set_daily_reward(normal_daily_reward)
	_check(start.text == tr("BATTLE_START"), "rewarded lobby offers one Battle action")
	var training_daily_reward: Dictionary = normal_daily_reward.duplicate(true)
	training_daily_reward["earned"] = 7
	training_daily_reward["remaining"] = 0
	view.set_daily_reward(training_daily_reward)
	_check(
		start.text == tr("BATTLE_TRAIN")
		and lobby_meta.text == tr("BATTLE_LOBBY_TRAINING") % ["3", "3"],
		"daily cap clamps overflow and changes the single lobby action to Train"
	)
	_check(
		is_equal_approx(float(view.reward_reset_delay(training_daily_reward)), 60.0),
		"Training status schedules reset from server timestamps"
	)
	view.set_daily_reward(normal_daily_reward)
	anima["sleep_started_at"] = "2026-08-13T00:00:00Z"
	view.set_lobby(anima)
	_check(start.disabled, "sleeping Anima cannot start Battle")
	anima.erase("sleep_started_at")
	anima["dormant_since"] = "2026-08-13T00:00:00Z"
	view.set_lobby(anima)
	_check(start.disabled, "Dormant Anima cannot start Battle")
	anima.erase("dormant_since")
	anima["care"]["energy"] = 19.0
	view.set_daily_reward(training_daily_reward)
	view.set_lobby(anima)
	_check(
		start.disabled and start.text == tr("BATTLE_TRAIN")
		and lobby_name.text == tr("BATTLE_LOBBY_TITLE_LOW_ENERGY")
		and lobby_meta.text == tr("BATTLE_ANIMA_LOW_ENERGY"),
		"Energy below 20 replaces Prepare for Battle with a rest title"
	)
	anima["care"]["energy"] = 20.0
	view.set_daily_reward(normal_daily_reward)
	view.set_lobby(anima)
	_check(not start.disabled, "exactly 20 Energy remains eligible for Battle")
	anima["care"]["hunger"] = 39.0
	view.set_lobby(anima)
	_check(
		start.disabled
		and lobby_name.text == tr("BATTLE_LOBBY_TITLE_HUNGRY")
		and lobby_meta.text == tr("BATTLE_ANIMA_HUNGRY"),
		"Hunger below 40 blocks Battle and Training"
	)
	anima["care"]["hunger"] = 40.0
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
		is_equal_approx(footer.custom_minimum_size.y, 148.0),
		"Battle command footer keeps only feedback and the three primary actions"
	)
	_check(player_sprite.flip_h and not bot_sprite.flip_h, "Battle fighters face each other")
	_check(
		is_equal_approx(active_ground_y, active_arena_height * 0.88),
		"Battle fighters stand near the arena floor"
	)
	_check(result.get_parent() == footer, "Battle result overlays the fixed footer")
	_check_eq(player_hp.value, 220.0, "Battle HUD displays authoritative HP")
	_check(
		player_hp_value.text == "220 / 220"
		and bot_hp_value.text == "205 / 205",
		"unified fighter HUD overlays exact current and maximum HP"
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
	_check(
		effectiveness.position.y + effectiveness.size.y < damage.position.y
		and effectiveness_badge is CenterContainer
		and view.find_child("BattleEffectivenessLeftStreak", true, false) == null
		and view.find_child("BattleEffectivenessRightStreak", true, false) == null
		and effectiveness_label.get_theme_font("font") is FontVariation
		and effectiveness_label.get_theme_font_size("font_size") >= 36,
		"effectiveness impact uses bold type above fighters without a box or side lines"
	)
	view.call("_show_effectiveness", 0.67)
	_check(
		effectiveness.visible and effectiveness_label.text == tr("BATTLE_NOT_EFFECTIVE"),
		"resisted attacks show a Not very effective indicator"
	)
	view.call("_show_effectiveness", 1.0)
	_check(not effectiveness.visible, "neutral attacks do not show a misleading indicator")
	_check_eq(strike.text, "D-Pad Jab", "Attack button uses the generated move name")
	_check(
		surge.text == tr("BATTLE_ACTION_SURGE_COST") % ["Pocket Beam", "3", "3"],
		"Special button shows the generated name plus PP"
	)
	_check(
		daily_reward.visible
		and daily_reward.text == tr("BATTLE_DAILY_REWARDS") % ["2", "3"],
		"Battle HUD shows authoritative daily rewarded wins"
	)
	_check(
		view.find_child("BattleMomentum", true, false) == null,
		"no redundant PP label survives outside the Special button"
	)
	_check(not strike.disabled and not surge.disabled and not guard.disabled, "active turn unlocks three actions")
	UiMotion.set_reduced_motion(false)
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
	UiMotion.set_reduced_motion(true)

	view.set_loading("BATTLE_RESUMING")
	_check(
		not lobby.visible and content.visible and feedback.text == tr("BATTLE_RESUMING"),
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
		feedback.text == tr("BATTLE_NO_MOMENTUM"),
		"empty PP names Guard as the way back instead of leaving a dead button"
	)
	var training_active: Dictionary = session.duplicate(true)
	training_active["state"]["player"]["momentum"] = 1
	training_active["daily_reward"] = training_daily_reward.duplicate(true)
	view.set_session(training_active, loaded, loaded)
	_check(
		feedback.text == tr("BATTLE_TRAINING_HINT") and not daily_reward.visible,
		"Training explains disabled rewards without presenting a fake Training limit"
	)
	view.begin_action("strike")
	_check(
		not strike.disabled and not surge.disabled and not guard.disabled
		and strike.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and surge.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and guard.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"pending turn blocks repeat input without making every action look disabled"
	)
	_check(
		strike_commit.visible and not surge_commit.visible and not guard_commit.visible
		and feedback.text == tr("BATTLE_ACTION_PENDING_STRIKE") % ["D-Pad Jab"]
		and surge.self_modulate.a < strike.self_modulate.a,
		"selected Battle action reacts immediately with committed feedback"
	)

	var won: Dictionary = session.duplicate(true)
	won["status"] = "won"
	won["state"]["bot"]["hp"] = 0
	won["daily_reward"] = {
		"earned": 3, "limit": 3, "remaining": 0, "rewarded": true,
	}
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
	_check(result.size.y >= 236.0, "Battle result grows upward and stays clear of bottom navigation")
	_check(
		bot_hp_value.text == "0 / 205",
		"terminal Battle HUD keeps the exact defeated HP visible"
	)
	_check(
		daily_reward.text == tr("BATTLE_DAILY_REWARDS") % ["3", "3"]
		and result_title.text == tr("BATTLE_WIN_TITLE")
		and result_body.text == tr("BATTLE_WIN_BODY"),
		"third rewarded win remains Battle even though it closes the daily cap"
	)
	var ready_again: Dictionary = anima.duplicate(true)
	ready_again.erase("dormant_since")
	view.set_lobby(ready_again)
	_check(
		start.text == tr("BATTLE_TRAIN"),
		"returning after the third reward immediately offers Training"
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
	view.set_session(training_win, loaded, loaded)
	_check(
		not daily_reward.visible
		and result_title.text == tr("BATTLE_TRAINING_TITLE")
		and result_body.text == tr("BATTLE_TRAINING_WIN_BODY")
		and retry.text == tr("BATTLE_TRAIN_AGAIN"),
		"wins after the cap are consistently presented as Training"
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
	UiMotion.set_reduced_motion(false)


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
		profile_body.find("_switch_destination(BottomNav.ANIMA, row)") >= 0,
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
	UiMotion.set_reduced_motion(true)
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
	_check(
		sheet_panel != null
		and is_equal_approx(sheet_panel.size.y, sheet_panel.get_combined_minimum_size().y),
		"Collection sheet height follows its content"
	)
	var handle := collection.find_child("HandleCenter", true, false) as Control
	_check(
		handle != null and handle.custom_minimum_size.y >= TOUCH_MIN,
		"sheet handle exposes a swipe target"
	)
	var sheet_source := FileAccess.get_file_as_string("res://scripts/ui_bottom_sheet.gd")
	_check(
		sheet_source.find("if UiMotion.reduced_motion:") >= 0
		and sheet_source.find("close()") >= 0
		and sheet_source.find("DISMISS_PX") >= 0,
		"sheet swipe follows the finger and closes immediately under reduced motion"
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
	UiMotion.set_reduced_motion(false)


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
		rename_body.find("_profile_anima") >= 0,
		"rename accepts the Anima currently shown in Profile"
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
		body.find("GameState.as_dict(snapshot.get(\"manifest\")),\n\t\tfalse") >= 0,
		"Battle art loading must not reuse the shell's persistent download toast"
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
	_home_action = ""
	_home_care_action = ""
	_home_care_blocked = ""
	home.first_scan_requested.connect(func() -> void: _home_action = "scan")
	home.retry_requested.connect(func() -> void: _home_action = "retry")
	home.care_blocked.connect(func(message: String) -> void: _home_care_blocked = message)
	home.care_requested.connect(func(action: String) -> void: _home_care_action = action)
	_check_eq(home.shell_state(), &"loading", "Home begins in Loading, not a false empty state")
	home.set_shell_state(&"empty")
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
	row["play_score_on"] = "2026-08-14"
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
	var details_button := nav.find_child("AnimaNavButton", true, false) as Button
	_check(buttons != null and buttons.get_child_count() == 5, "bottom navigation contains five tabs")
	_check(
		battle_button != null and battle_button.find_child("Content", true, false) is VBoxContainer,
		"Battle tab keeps the vertical icon-over-label layout"
	)
	nav.set_active(BottomNav.BATTLE)
	_check(battle_button.button_pressed, "Battle destination has an explicit active state")
	nav.set_busy(true, true)
	_check(not home_button.disabled, "busy requests keep Home navigation available")
	_check(not scan_button.disabled, "busy requests keep Scan navigation available")
	_check(not battle_button.disabled, "busy requests keep Battle navigation available")
	_check(not details_button.disabled, "available Anima remains inspectable while busy")
	nav.set_busy(false, false)
	_check(details_button.disabled, "profile stays disabled without an Anima")
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
	UiMotion.set_reduced_motion(true)
	await effect.start_portal()
	_check(
		not effect.visible and not effect.is_active(),
		"Reduced Motion skips the Summon portal entirely"
	)
	UiMotion.set_reduced_motion(false)
	effect.free()


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
