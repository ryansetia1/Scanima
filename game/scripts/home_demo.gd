extends Node2D

## Harness untuk menyetel layout Home di editor.
##
## Ia memasang `home_view.tscn` yang sama dengan production plus HUD, bottom nav,
## dan overlay Shop/Bag, lalu memberi satu row Anima palsu — nol jaringan, nol
## akun, nol biaya. Tekan F6 dengan scene ini terbuka, atau:
##
##   godot --path game res://scenes/home_demo.tscn -- --screenshot=/tmp/home.png
##
## Yang disetel tetap `home_view.tscn`; scene ini cuma jendelanya. Stage Anima
## sengaja kosong karena sprite-nya diunduh saat runtime ke `user://animas/`.

const FLOW: GDScript = preload("res://scripts/scan_flow.gd")

@onready var _home: HomeView = %HomeView
@onready var _top_hud: PanelContainer = %TopHud
@onready var _brand: Label = %Brand
@onready var _cores_chip: ResourceChip = %CoresChip
@onready var _bits_chip: ResourceChip = %BitsChip
@onready var _shop_button: ResourceChip = %ShopButton
@onready var _bag_button: ResourceChip = %BagButton
@onready var _stage: Node2D = %Stage
@onready var _anima: AnimaPresenter = %Anima


func _ready() -> void:
	_configure_chips()
	_home.set_anima(demo_row(), false)
	var built := PlaceholderSheet.build()
	var loaded := AnimaLoader.build(
		ImageTexture.create_from_image(built["image"]), built["manifest"]
	)
	_anima.apply(loaded)
	_anima.set_pose("idle")
	_place_stage()
	get_viewport().size_changed.connect(_place_stage)
	get_viewport().size_changed.connect(_place_chips)

	# Chip rects stay zero-sized until the shell has laid out, so the overlay can
	# only be placed after that.
	await get_tree().process_frame
	await get_tree().process_frame
	_place_chips()

	var shot := _arg_value("--screenshot=")
	if not shot.is_empty():
		await _capture_and_quit(shot)


## Satu companion yang menyentuh setiap state yang layout-nya harus tahan: nama
## pendek, Energy di bawah ambang `NeedChipLow`, dan EXP di tengah band-nya.
static func demo_row() -> Dictionary:
	return {
		"id": "home-demo",
		"nickname": "Mugshots",
		"element": "flow",
		"stage": 1,
		"care": {"hunger": 85.0, "energy": 5.0, "hygiene": 80.0},
		"care_score": 62,
	}


func _configure_chips() -> void:
	_brand.text = tr("SEEKER_GUEST_LABEL")
	for badge: ResourceChip in [_cores_chip, _bits_chip]:
		badge.set_inline(true)
	_cores_chip.set_name_text(tr("RESOURCE_CORES"))
	_cores_chip.set_value_text("2")
	_bits_chip.set_name_text(tr("RESOURCE_BITS"))
	_bits_chip.set_value_text("30")
	_shop_button.set_icon(FLOW.SHOP_ICON)
	_shop_button.set_value_text(tr("SHOP_OPEN"))
	_shop_button.set_name_text("")
	_bag_button.set_icon(FLOW.BAG_ICON)
	_bag_button.set_value_text(tr("BAG_OPEN"))
	_bag_button.set_name_text("")


# This harness still floats its own Shop/Bag overlay for quick layout tweaks;
# the shipped HUD in scan_flow.tscn now lays them out as real row children
# instead (see TopHud/Column/BottomSection/RightButtons).
const _CHIP_INSET := 2.0
const _SHOP_GAP := 6.0


func _place_chips() -> void:
	var hud := _top_hud.get_global_rect()
	var chip := _shop_button.get_combined_minimum_size()
	if hud.size.y <= 0.0 or chip.x <= 0.0:
		return
	var right := hud.end.x - _CHIP_INSET
	var bottom := hud.end.y - _CHIP_INSET - chip.y
	var gutter := chip.x * 2.0 + _SHOP_GAP
	_shop_button.position = Vector2(right - gutter, bottom)
	_shop_button.size = chip
	_bag_button.position = Vector2(right - chip.x, bottom)
	_bag_button.size = chip


func _place_stage() -> void:
	_stage.position = FLOW.stage_position_for(get_viewport_rect().size)


func _arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func _capture_and_quit(path: String) -> void:
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
