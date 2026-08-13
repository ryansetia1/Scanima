extends SceneTree

## Free contract test for the production mobile shell. The scene is instantiated
## off-tree, so no authentication or network requests run.

const TOUCH_MIN := 96.0

var _checks := 0
var _failures: PackedStringArray = []
var _requested_delete_id := ""


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
	for name in ["HomeView", "ScanView", "CollectionView", "AnimaDetailsView"]:
		var view := scene.find_child(name, true, false) as Control
		_check(view != null, "%s must exist" % name)
		if view != null:
			_check_full_rect(view, name)

	var home := scene.find_child("HomeView", true, false) as Control
	var scan := scene.find_child("ScanView", true, false) as Control
	var collection := scene.find_child("CollectionView", true, false) as Control
	var details := scene.find_child("AnimaDetailsView", true, false) as Control
	_check(home != null and home.visible, "Home is the default destination")
	_check(scan != null and not scan.visible, "Scan starts hidden")
	_check(collection != null and not collection.visible, "Collection starts hidden")
	_check(details != null and not details.visible, "Details starts hidden")

	for name in [
		"ScanButton", "HomeNavButton", "ScanNavButton", "CollectionNavButton", "AnimaNavButton",
		"FeedButton", "CleanButton", "SleepButton", "PlayButton", "DeleteAnimaButton",
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
	_check(scene.find_child("BottomNav", true, false) is PanelContainer, "bottom navigation must exist")
	_check(scene.find_child("StatusPanel", true, false) is PanelContainer, "floating feedback must exist")
	_check(scene.find_child("PoseRow", true, false) == null, "debug pose controls must not ship in production")
	var core_info_button := scene.find_child("CoreInfoButton", true, false) as Button
	var core_info_overlay := scene.find_child("CoreInfoOverlay", true, false) as Control
	var core_info_panel := scene.find_child("CoreInfoPanel", true, false) as PanelContainer
	var core_info_close := scene.find_child("CoreInfoCloseButton", true, false) as Button
	_check(core_info_button != null, "Core resource must be tappable")
	_check(core_info_overlay != null and not core_info_overlay.visible, "Core info modal starts hidden")
	_check(
		core_info_panel != null and core_info_panel.theme_type_variation == &"ModalPanel",
		"Core info modal uses shared modal chrome"
	)
	_check(
		core_info_close != null and core_info_close.custom_minimum_size.y >= TOUCH_MIN,
		"Core info close action meets the touch target"
	)
	var delete_dialog := scene.find_child("DeleteAnimaDialog", true, false) as ConfirmationDialog
	var rename_dialog := scene.find_child("RenameAnimaDialog", true, false) as ConfirmationDialog
	var rename_input := scene.find_child("RenameAnimaInput", true, false) as LineEdit
	_check(
		delete_dialog != null
		and delete_dialog.dialog_autowrap
		and delete_dialog.get_theme_constant("buttons_min_height", "AcceptDialog") >= TOUCH_MIN,
		"delete dialog wraps copy and keeps touch-safe actions"
	)
	_check(
		delete_dialog != null
		and delete_dialog.get_theme_constant("title_height", "Window") >= 72,
		"dialog title keeps breathing room above its copy"
	)
	_check(
		rename_dialog != null and rename_dialog.dialog_autowrap,
		"hatch rename dialog must exist and wrap localized copy"
	)
	var shell_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	_check(
		shell_source.find("_delete_anima_dialog.add_theme_icon_override(\"close\"") >= 0
		and shell_source.find("_rename_anima_dialog.add_theme_icon_override(\"close\"") >= 0,
		"small native close icons stay hidden in favor of touch-safe cancel actions"
	)
	_check(
		rename_input != null
		and rename_input.max_length == 32
		and rename_input.custom_minimum_size.y >= TOUCH_MIN,
		"rename input enforces the server length and touch target"
	)

	var scan_button := scene.find_child("ScanButton", true, false) as Button
	if scan_button != null:
		_check_eq(scan_button.theme_type_variation, &"PrimaryButton", "Scan remains the signature CTA")
	var scan_nav := scene.find_child("ScanNavButton", true, false) as Button
	if scan_nav != null:
		_check_eq(scan_nav.theme_type_variation, &"ScanTabButton", "Scan is emphasized in navigation")

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
	_check(scene.find_child("CareSummary", true, false) is Label, "Care Score has a label")
	for name in ["NeedHunger", "NeedEnergy", "NeedHygiene", "NeedBond"]:
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
	var anima := scene.find_child("Anima", true, false) as AnimatedSprite2D
	_check(anima != null and not anima.visible, "cached art stays hidden until server care is known")
	_test_care_feedback_is_immediate()
	_test_collection_selection_goes_home()
	_test_hatch_offers_rename()

	scene.free()
	await _test_anima_delete_action()
	await _test_home_care_actions()
	await _test_bottom_nav_busy()
	await _test_incubator_effect()
	_finish()


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


func _test_collection_selection_goes_home() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _on_anima_selected")
	var end := source.find("\n\nfunc _show_delete_confirmation", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	_check(
		body.find("_switch_destination(BottomNav.HOME)") >= 0,
		"collection selection routes directly to Home"
	)
	_check(
		body.find("_switch_destination(BottomNav.ANIMA)") < 0,
		"collection selection no longer opens the intermediate profile"
	)


func _test_hatch_offers_rename() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var start := source.find("func _present(")
	var end := source.find("\n\nstatic func normalize_anima_data", start)
	var body := source.substr(start, end - start) if start >= 0 and end > start else ""
	_check(
		body.find("call_deferred(\"_show_hatch_rename\", anima_id)") >= 0,
		"every completed scan offers optional rename after reveal"
	)


func _test_anima_delete_action() -> void:
	var packed := load("res://scenes/ui/anima_details_view.tscn") as PackedScene
	var details := packed.instantiate()
	root.add_child(details)
	await process_frame
	var button := details.find_child("DeleteAnimaButton", true, false) as Button
	_requested_delete_id = ""
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
	_check(button != null and not button.disabled, "loaded profile enables Delete")
	if button != null:
		button.pressed.emit()
	_check_eq(_requested_delete_id, "anima-delete-test", "Delete emits only the active Anima id")
	details.set_busy(true)
	_check(button != null and button.disabled, "network work disables destructive action")
	details.queue_free()
	await process_frame


func _capture_delete_request(anima_id: String) -> void:
	_requested_delete_id = anima_id


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
	var row := {
		"care": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "bond": 99.0},
		"care_score": 8,
	}
	home.update_care(row, false)
	_check(not play.disabled, "Play remains available below full Bond")
	row["care"]["bond"] = 100.0
	home.update_care(row, false)
	_check(play.disabled, "Play is disabled at full Bond")

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
	_check(actions.columns == 2 or actions.columns == 4, "awake care restores responsive columns")
	home.queue_free()
	await process_frame


func _test_bottom_nav_busy() -> void:
	var packed := load("res://scenes/ui/bottom_nav.tscn") as PackedScene
	var nav := packed.instantiate()
	root.add_child(nav)
	await process_frame
	var home_button := nav.find_child("HomeNavButton", true, false) as Button
	var scan_button := nav.find_child("ScanNavButton", true, false) as Button
	var details_button := nav.find_child("AnimaNavButton", true, false) as Button
	nav.set_busy(true, true)
	_check(not home_button.disabled, "busy requests keep Home navigation available")
	_check(not scan_button.disabled, "busy requests keep Scan navigation available")
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
