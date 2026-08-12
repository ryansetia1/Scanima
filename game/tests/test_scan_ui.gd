extends SceneTree

## Kontrak layout scan_flow tanpa jaringan:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##       --script res://tests/test_scan_ui.gd
##
## Scene hanya di-instantiate dan TIDAK dimasukkan ke tree, jadi _ready() tidak
## menjalankan auth atau request apa pun. Uji ini menjaga hal yang paling mudah
## mengecil lagi tanpa terlihat di test logika: target sentuh, anchor modal, dan
## posisi Stage pada beberapa ukuran portrait.

const TOUCH_MIN := 96.0

var _checks := 0
var _failures: PackedStringArray = []
var _ui_juice: GDScript = load("res://scripts/ui_juice.gd") as GDScript


func _initialize() -> void:
	var packed := load("res://scenes/scan_flow.tscn") as PackedScene
	_check(packed != null, "scan_flow.tscn harus bisa dimuat")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	_check(scene != null, "scan_flow.tscn harus bisa di-instantiate")
	if scene == null:
		_finish()
		return

	_check_full_rect(scene.find_child("Margin", true, false) as Control, "Margin utama")
	_check_full_rect(scene.find_child("CollectionOverlay", true, false) as Control, "modal Koleksi")
	_check_full_rect(scene.find_child("StatsOverlay", true, false) as Control, "modal Stats")

	for name in [
		"ScanButton", "CollectionButton", "StatsButton",
		"CloseCollectionButton", "CloseStatsButton",
		"FeedButton", "CleanButton", "SleepButton", "PlayButton",
	]:
		var button := scene.find_child(name, true, false) as Button
		_check(button != null, "%s wajib ada" % name)
		if button != null:
			_check(
				button.custom_minimum_size.y >= TOUCH_MIN,
				"%s minimal %.0f px, dapat %.0f" % [name, TOUCH_MIN, button.custom_minimum_size.y]
			)

	var list := scene.find_child("AnimaList", true, false) as ItemList
	_check(list != null, "AnimaList wajib ada")
	if list != null:
		_check_eq(list.max_columns, 2, "koleksi memakai grid dua kolom")
		_check_eq(list.fixed_icon_size, Vector2i(128, 128), "thumbnail koleksi 128 px")

	var margin := scene.find_child("Margin", true, false) as MarginContainer
	_check(margin != null and margin.theme != null, "theme mobile harus terpasang")
	if margin != null and margin.theme != null:
		_check(margin.theme.default_font_size >= 32, "font default minimal 32 px")
		_check_eq(
			margin.theme.get_type_variation_base(&"PrimaryButton"),
			&"Button",
			"theme harus menyediakan variasi CTA bersama"
		)
		_check_eq(
			margin.theme.get_type_variation_base(&"ModalPanel"),
			&"PanelContainer",
			"theme harus menyediakan panel modal bersama"
		)

	var background := scene.find_child("Background", true, false) as Node2D
	_check(background != null and background.get_script() != null, "latar procedural wajib terpasang")
	_check(scene.find_child("HeaderCard", true, false) is PanelContainer, "HUD wajib punya kartu header")
	_check(scene.find_child("StageBadge", true, false) is PanelContainer, "Stage wajib punya badge chamber")
	_check(scene.find_child("StatusPanel", true, false) is PanelContainer, "status wajib punya panel terbaca")
	var scan_button := scene.find_child("ScanButton", true, false) as Button
	if scan_button != null:
		_check_eq(scan_button.theme_type_variation, &"PrimaryButton", "scan harus menjadi CTA utama")
	var collection_panel := scene.get_node("UI/CollectionOverlay/CollectionMargin/Panel") as PanelContainer
	var stats_panel := scene.get_node("UI/StatsOverlay/StatsMargin/Panel") as PanelContainer
	_check_eq(collection_panel.theme_type_variation, &"ModalPanel", "Koleksi memakai chrome modal")
	_check_eq(stats_panel.theme_type_variation, &"ModalPanel", "Stats memakai chrome modal")

	var juice_probe := Button.new()
	_ui_juice.install_button(juice_probe)
	_check(juice_probe.has_meta(&"_scanima_juice_installed"), "button juice harus idempoten dan terpasang")
	juice_probe.free()

	var care_panel := scene.find_child("CarePanel", true, false) as PanelContainer
	_check(care_panel != null, "CarePanel wajib ada")
	if care_panel != null:
		_check(not care_panel.visible, "CarePanel tersembunyi sebelum Anima termuat")
	_check(scene.find_child("CareSummary", true, false) is Label, "Care Score wajib punya label")
	for name in ["NeedHunger", "NeedEnergy", "NeedHygiene", "NeedBond"]:
		var meter := scene.find_child(name, true, false) as ProgressBar
		_check(meter != null, "%s wajib ada" % name)
		if meter != null:
			_check_eq(meter.max_value, 100.0, "%s memakai rentang 0–100" % name)

	var script := scene.get_script() as GDScript
	var normalized: Dictionary = script.normalize_anima_data({
		"stats": {"hp": 61, "atk": 42, "def": 55, "spd": 48, "special": 70},
	})
	_check_eq(
		(normalized["base_stats"] as Dictionary).get("special"),
		70,
		"cache-hit Vision stats harus menjadi base_stats untuk modal"
	)
	for size in [Vector2(720, 1280), Vector2(360, 640), Vector2(412, 915), Vector2(1080, 1920)]:
		var pos: Vector2 = script.stage_position_for(size, Vector4.ZERO)
		_check(is_equal_approx(pos.x, size.x * 0.5), "Stage harus horizontal-center pada %s" % size)
		_check(pos.y > 0.0 and pos.y < size.y, "Stage harus di dalam viewport %s" % size)

	var inset_pos: Vector2 = script.stage_position_for(Vector2(720, 1280), Vector4(0, 80, 0, 120))
	_check(inset_pos.y > 80.0 and inset_pos.y < 1160.0, "Stage harus berada di safe area")

	var incubator := scene.find_child("Incubator", true, false) as Node2D
	_check(incubator != null, "Stage wajib punya Incubator")
	if incubator != null:
		_check(not incubator.visible, "Incubator harus tersembunyi sebelum generation")

	scene.free()
	await _test_incubator_effect()
	_finish()


func _test_incubator_effect() -> void:
	var effect := Node2D.new()
	effect.set_script(load("res://scripts/incubator_effect.gd"))
	root.add_child(effect)
	await process_frame

	effect.start()
	_check(effect.visible, "start() harus menampilkan Incubator")
	_check(effect.is_active(), "start() harus mengaktifkan loop Incubator")
	await process_frame
	effect.stop()
	_check(not effect.visible, "stop() harus menyembunyikan Incubator saat scan gagal")
	_check(not effect.is_active(), "stop() harus menghentikan loop Incubator")

	effect.start()
	await effect.burst()
	_check(effect.visible, "burst() kembali saat flash masih terlihat")
	await create_timer(0.45).timeout
	_check(not effect.visible and not effect.is_active(), "burst selesai harus membersihkan Incubator")
	effect.free()


func _check_full_rect(node: Control, label: String) -> void:
	_check(node != null, "%s wajib ada" % label)
	if node == null:
		return
	_check_eq(node.anchor_left, 0.0, "%s anchor kiri" % label)
	_check_eq(node.anchor_top, 0.0, "%s anchor atas" % label)
	_check_eq(node.anchor_right, 1.0, "%s anchor kanan" % label)
	_check_eq(node.anchor_bottom, 1.0, "%s anchor bawah" % label)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: dapat %s, mau %s" % [message, str(actual), str(expected)])


func _finish() -> void:
	if _failures.is_empty():
		print("test_scan_ui: OK (%d check)" % _checks)
		quit(0)
		return
	printerr("test_scan_ui: GAGAL %d dari %d check" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - %s" % failure)
	quit(1)
