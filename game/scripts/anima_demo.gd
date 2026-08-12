extends Node2D

## Demo Phase 1: membuktikan sheet dari pipeline bisa dipotong, dipasang, dan
## terlihat hidup di Godot.
##
## Tanpa argumen, demo memakai sheet placeholder yang dibuat di memori, jadi bisa
## dijalankan sebelum ada satu pun hasil generation. Untuk melihat hasil eval
## yang sungguhan, tunjuk manifest-nya:
##
##   godot --path game -- --manifest=/abs/path/eval/results/v1/smoke/mouse.json

const PLACEHOLDER_DIR := "user://animas/placeholder"

var _ui_juice: GDScript = load("res://scripts/ui_juice.gd") as GDScript

@onready var _anima: AnimaPresenter = %Anima
@onready var _info: Label = %Info
@onready var _pose_row: HBoxContainer = %PoseRow
@onready var _hop_button: Button = %HopButton


func _ready() -> void:
	var manifest_path := _manifest_path_from_cmdline()
	var loaded: Dictionary

	if manifest_path.is_empty():
		# Jalur in-memory: tidak menyentuh disk sama sekali.
		var built := PlaceholderSheet.build()
		var texture := ImageTexture.create_from_image(built["image"])
		loaded = AnimaLoader.build(texture, built["manifest"])
	else:
		loaded = AnimaLoader.load_from_manifest(manifest_path)

	if not loaded.get("ok", false):
		_info.text = "Gagal memuat:\n%s" % loaded.get("error", "?")
		push_error("gagal memuat Anima: %s" % loaded.get("error", "?"))
		return

	_anima.apply(loaded)
	_build_pose_buttons(loaded["poses"])
	_hop_button.pressed.connect(_anima.hop)
	_show_info(loaded, manifest_path)
	await get_tree().process_frame
	_ui_juice.install_buttons(self)
	_ui_juice.reveal($UI/Margin/Column/HeaderCard, 0.02)
	_ui_juice.reveal($UI/Margin/Column/InfoCard, 0.10)
	_ui_juice.reveal(_pose_row, 0.18)
	_ui_juice.reveal(_hop_button, 0.24)

	var pose := _arg_value("--pose=")
	if not pose.is_empty():
		_anima.set_pose(pose)

	var shot := _arg_value("--screenshot=")
	if not shot.is_empty():
		_capture_and_quit(shot)


func _manifest_path_from_cmdline() -> String:
	return _arg_value("--manifest=")


func _arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


## Memeriksa hasil art tanpa membuka editor:
##
##   godot --path game -- --screenshot=/tmp/anima.png
##
## Test unit bisa membuktikan region-nya benar, tapi tidak bisa membuktikan
## sprite-nya tidak terbalik, alpha-nya tidak tertukar, atau kakinya tidak
## menembus lantai. Untuk itu perlu benar-benar melihatnya.
func _capture_and_quit(path: String) -> void:
	# Beberapa frame supaya tween sudah mulai dan layout container sudah tetap.
	for _i in 24:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("viewport tidak bisa dibaca, jalankan tanpa --headless")
		get_tree().quit(1)
		return

	if image.save_png(path) != OK:
		push_error("gagal menulis screenshot ke %s" % path)
		get_tree().quit(1)
		return

	print("screenshot: %s" % path)
	get_tree().quit(0)


func _build_pose_buttons(poses: PackedStringArray) -> void:
	for child in _pose_row.get_children():
		child.queue_free()

	for pose in poses:
		var button := Button.new()
		button.text = pose.capitalize()
		button.custom_minimum_size = Vector2(0, 96)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"PoseButton"
		# Bind, bukan closure yang menangkap variabel loop: di GDScript variabel
		# loop bisa berubah sebelum callback dipanggil.
		button.pressed.connect(_anima.set_pose.bind(pose))
		_pose_row.add_child(button)
		_ui_juice.install_button(button)


func _show_info(loaded: Dictionary, manifest_path: String) -> void:
	var lines: PackedStringArray = []
	lines.append("%s  ·  tahap %d" % [loaded["species_key"], loaded["stage"]])
	lines.append("frame %s  ·  pose %s" % [str(loaded["frame_size"]), ", ".join(loaded["poses"])])
	lines.append("sumber: %s" % ("placeholder in-memory" if manifest_path.is_empty() else manifest_path))

	var qa: Dictionary = loaded.get("qa", {})
	var warnings: Array = qa.get("warnings", [])
	if not warnings.is_empty():
		lines.append("peringatan: %s" % ", ".join(PackedStringArray(warnings)))

	_info.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	# Menyentuh Anima memantulkannya. Ini interaksi paling dasar dari game
	# virtual pet, dan gratis karena hanya Tween.
	if event is InputEventMouseButton and event.pressed:
		_anima.hop()
