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
var _preview_requests := 0


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
		"FeedButton", "CleanButton", "SleepButton", "PlayButton", "EditAnimaNameButton",
		"DeleteAnimaButton",
		"HomePrimaryAction", "CollectionEmptyAction", "CollectionProfileButton",
		"CollectionSummonButton",
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
	_check(scene.find_child("AnimaCount", true, false) is Label, "HUD exposes the owned Anima count")
	_check(scene.find_child("ScanCount", true, false) == null, "HUD no longer labels scan charges as a count")
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

	scene.free()
	await _test_scan_phase_visuals()
	await _test_collection_bottom_sheet()
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
	var synced_row: Dictionary = row.duplicate(true)
	synced_row["care"]["hunger"] = 42.0
	_check(
		collection.apply_care_sync(synced_row, collection.selected_revision()),
		"matching care response updates the open sheet"
	)

	var overlay := collection.find_child("CollectionSheetOverlay", true, false) as Control
	var summon := collection.find_child("CollectionSummonButton", true, false) as Button
	var profile := collection.find_child("CollectionProfileButton", true, false) as Button
	var hp := collection.find_child("SheetStatHp", true, false) as Label
	var hunger := collection.find_child("SheetCareHunger", true, false) as ProgressBar
	_check(overlay != null and overlay.visible, "selecting an Anima opens the bottom sheet")
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
	var confirm_end := source.find("\n\nfunc _rename_submitted", confirm_start)
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
	var sleep_at := present_body.find("if _is_sleeping(_current_anima)")
	var sleeping_status_at := present_body.find("STATUS_ANIMA_SLEEPING")
	var ready_status_at := present_body.find("STATUS_ANIMA_READY")
	_check(
		sync_at >= 0 and sleep_at > sync_at,
		"authoritative care sync finishes before choosing the startup toast"
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
	home.first_scan_requested.connect(func() -> void: _home_action = "scan")
	home.retry_requested.connect(func() -> void: _home_action = "retry")
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
