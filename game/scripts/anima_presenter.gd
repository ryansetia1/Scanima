class_name AnimaPresenter
extends AnimatedSprite2D

## Menghidupkan Anima dari gambar statis di sheet.
##
## Model hanya memberi pose diam, bukan animasi. Gerakannya datang dari Tween di
## sisi Godot: napas, pantulan kecil, tersentak saat menyerang. Ini bukan
## penghematan sementara, melainkan alasan biaya art bisa satu panggilan per
## Anima: menganimasikan 8 frame per pose lewat model berarti 8x biaya dan
## konsistensi yang tidak mungkin dijaga.

signal pose_changed(pose: String)

const CARE_RULES: GDScript = preload("res://scripts/care_rules.gd")
const GUARD_SHIMMER_SHADER: Shader = preload("res://shaders/guard_shimmer.gdshader")
const BREATH_IDLE_SEC := 1.6
const BREATH_SLEEP_SEC := 2.8
const BREATH_DAMAGED_SEC := 1.1
const HOP_HEIGHT_PX := 10.0
const PLAY_BOUNCE_HEIGHT_PX := 14.0
const PLAY_BOUNCE_COUNT := 6
const VICTORY_BOUNCE_HEIGHT_PX := 18.0
const VICTORY_FLOURISH_HEIGHT_PX := 8.0
const VICTORY_FLOURISH_COUNT := 2
const TAP_HIT_PADDING_PX := 28.0
const FX_TRAVEL_SEC := 0.36
const OPAQUE_ALPHA_MIN := 0.12
## Sekali sapuan penuh, dipasang lebih pendek daripada tahan pelat Guard
## (BattleView.ACTION_CUE_SEC) supaya kilaunya selesai sementara copy-nya masih
## terbaca, bukan tertinggal sampai animasi turn berikutnya.
const GUARD_SHIMMER_SEC := 1.05
## Dua bob rendah untuk item energi -- beda ritme dari satu hop tinggi Feed,
## supaya keduanya terasa berbeda tanpa membaca warna kilaunya.
const ITEM_BOB_HEIGHT_PX := 6.0
const ITEM_BOB_RISE_SEC := 0.10
const ITEM_BOB_FALL_SEC := 0.12
const ITEM_BOB_HOLD_SEC := 0.02
## Burst partikel dampak Feed/Item/Clean -- lihat `_burst()`.
const BURST_LIFETIME_SEC := 0.55
const BURST_AMOUNT_FEED := 24
const BURST_AMOUNT_ITEM := 30
const BURST_AMOUNT_CLEAN := 22

var _motion: Tween
var _feedback: Tween
var _care_tint: Tween
var _fx_tween: Tween
var _shimmer: Tween
var _shimmer_material: ShaderMaterial
var _fx: Sprite2D
var _burst_particles: CPUParticles2D
var _fx_motion: Dictionary = {}
var _queued_care: Dictionary = {}
var _base_position: Vector2 = Vector2.ZERO
var _reference_height_px := 0.0
var _current_pose: String = ""
var _facing_direction := -1.0
var _victory_loop := false
var _opaque_local_by_pose: Dictionary = {}


func _ready() -> void:
	_base_position = position
	centered = true


## Menerima hasil AnimaLoader.build() / load_from_manifest().
func apply(loaded: Dictionary) -> bool:
	if not loaded.get("ok", false):
		push_warning("AnimaPresenter.apply menolak data: %s" % loaded.get("error", "?"))
		return false

	sprite_frames = loaded["frames"]
	offset = loaded["ground_offset"]
	_fx_motion = (loaded.get("fx_motion", {}) as Dictionary).duplicate()
	_opaque_local_by_pose.clear()
	_base_position = position
	var metrics_value: Variant = loaded.get("render_metrics", {})
	var metrics: Dictionary = metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	_reference_height_px = maxf(0.0, float(metrics.get("reference_height_px", 0.0)))
	set_pose(AnimaLoader.DEFAULT_POSE)
	return true


## Tinggi badan opak yang dicatat manifest, dipakai pemanggil untuk menormalkan
## skala. Pose-independent, tidak seperti `opaque_local_rect()`: pose tidur lebih
## pendek daripada idle, jadi mengukurnya per pose akan mengubah ukuran Anima
## setiap kali ia tertidur. Nol berarti manifest lama tanpa metrik.
func reference_height_px() -> float:
	return _reference_height_px


func set_pose(pose: String) -> bool:
	if sprite_frames == null or not sprite_frames.has_animation(pose):
		return false

	# Loop kemenangan tidak punya akhir sendiri, jadi ia harus dilepas di sini:
	# _start_motion() hanya membunuh _motion, dan _feedback yang selamat akan
	# menahan plant_on_anchor() sekaligus memantulkan pose berikutnya.
	if _victory_loop:
		_victory_loop = false
		if _feedback != null and _feedback.is_valid():
			_feedback.kill()
		_feedback = null

	animation = pose
	# Tiap pose satu frame, jadi play() hanya menampilkannya; yang bergerak Tween.
	play()
	_current_pose = pose
	plant_on_anchor()
	_start_motion(pose)
	pose_changed.emit(pose)
	return true


func current_pose() -> String:
	return _current_pose


func fx_motion(pose: String) -> String:
	return str(_fx_motion.get(pose, "projectile"))


## Sprite sheet selalu dibuat menghadap kiri. Arena membalik petarung di sisi
## kiri agar pose dan gerak serang keduanya menuju lawan.
func set_facing(direction: float) -> void:
	_facing_direction = -1.0 if direction < 0.0 else 1.0
	flip_h = _facing_direction > 0.0
	plant_on_anchor()


func hit_test(global_point: Vector2) -> bool:
	if not visible or sprite_frames == null:
		return false
	var texture := sprite_frames.get_frame_texture(animation, frame)
	if texture == null:
		return false
	var texture_size := texture.get_size()
	var top_left := offset - texture_size * 0.5 if centered else offset
	# Titik datang dari viewport, jadi transform kanvas harus ikut dihitung; to_local()
	# saja akan salah begitu Stage bergeser atau ada Camera2D.
	var local := make_canvas_position_local(global_point)
	if flip_h:
		local.x = -local.x
	return Rect2(top_left, texture_size).grow(TAP_HIT_PADDING_PX).has_point(local)


## Geser sprite supaya kaki opak duduk di origin node, bukan dasar sel kotak.
func plant_on_anchor() -> void:
	var bounds := opaque_local_rect()
	if bounds.size == Vector2.ZERO:
		return
	_base_position = -_feet_local(bounds)
	if _feedback == null or not _feedback.is_valid():
		position = _base_position


## Pusat massa opak pose saat ini, bukan pusat sel sheet (banyak padding).
func body_center_global() -> Vector2:
	return to_global(_body_center_local())


## Kotak badan opak pose sekarang dalam ruang viewport, siap jadi target
## `UiJuice.fly_to()`. Ukurannya ikut skala `AnimaBody` (parent anchor), jadi
## dihitung lewat transform kanvas milik engine -- bukan `opaque_local_rect()`
## mentah, yang masih dalam ruang lokal sprite sebelum skala Home diterapkan.
func body_viewport_rect() -> Rect2:
	var bounds := opaque_local_rect()
	if bounds.size == Vector2.ZERO:
		return Rect2()
	var xf := get_global_transform_with_canvas()
	var size: Vector2 = (xf * Rect2(Vector2.ZERO, bounds.size)).size
	var center: Vector2 = xf * _body_center_local()
	return Rect2(center - size * 0.5, size)


func opaque_local_rect() -> Rect2:
	if sprite_frames == null:
		return Rect2()
	var pose: String = _current_pose
	if pose.is_empty():
		pose = String(animation)
	if _opaque_local_by_pose.has(pose):
		return _opaque_local_by_pose[pose]
	var texture := sprite_frames.get_frame_texture(animation, frame)
	if texture == null:
		return Rect2()
	var image := texture.get_image()
	if image == null:
		return Rect2()
	var used := _tight_used_rect(image)
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2()
	var texture_size := Vector2(image.get_width(), image.get_height())
	var top_left := offset - texture_size * 0.5 if centered else offset
	var rect := Rect2(top_left + Vector2(used.position), Vector2(used.size))
	_opaque_local_by_pose[pose] = rect
	return rect


func sync_ground_shadow(shadow: Sprite2D) -> void:
	if not is_instance_valid(shadow):
		return
	if sprite_frames == null or not visible:
		shadow.visible = false
		return
	var bounds := opaque_local_rect()
	var feet := _feet_local(bounds)
	var width := bounds.size.x if bounds.size.x > 0.0 else 96.0
	var parent := shadow.get_parent() as Node2D
	shadow.visible = true
	shadow.z_index = 0
	# Feet are sprite-local; the blob lives on the arena anchor so hop/flip
	# do not leave it beside the body.
	if parent != null:
		shadow.position = parent.to_local(to_global(feet))
	else:
		shadow.position = feet
	shadow.scale = Vector2(clampf(width / 180.0, 0.5, 2.0), 0.7)


func _tight_used_rect(image: Image) -> Rect2i:
	# ponytail: get_used_rect counts a>0, so sheet-cell haze becomes the square.
	# Ceiling: shrinks edges once per pose; bake manifest bbox if hatch hitches.
	var src := image
	if image.get_format() != Image.FORMAT_RGBA8:
		src = image.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var data := src.get_data()
	var full := src.get_used_rect()
	if full.size.x <= 0 or full.size.y <= 0:
		return full
	var width := src.get_width()
	var threshold := int(OPAQUE_ALPHA_MIN * 255.0)
	var x0 := full.position.x
	var y0 := full.position.y
	var x1 := full.end.x - 1
	var y1 := full.end.y - 1
	while y0 < y1 and not _row_opaque(data, width, y0, x0, x1, threshold):
		y0 += 1
	while y1 > y0 and not _row_opaque(data, width, y1, x0, x1, threshold):
		y1 -= 1
	while x0 < x1 and not _col_opaque(data, width, x0, y0, y1, threshold):
		x0 += 1
	while x1 > x0 and not _col_opaque(data, width, x1, y0, y1, threshold):
		x1 -= 1
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _row_opaque(
	data: PackedByteArray, width: int, y: int, x0: int, x1: int, threshold: int
) -> bool:
	var index := (y * width + x0) * 4 + 3
	var last := (y * width + x1) * 4 + 3
	while index <= last:
		if data[index] >= threshold:
			return true
		index += 4
	return false


func _col_opaque(
	data: PackedByteArray, width: int, x: int, y0: int, y1: int, threshold: int
) -> bool:
	var index := (y0 * width + x) * 4 + 3
	var last := (y1 * width + x) * 4 + 3
	var stride := width * 4
	while index <= last:
		if data[index] >= threshold:
			return true
		index += stride
	return false


func _body_center_local() -> Vector2:
	var bounds := opaque_local_rect()
	if bounds.size == Vector2.ZERO:
		return offset
	return _flip_local(bounds.get_center())


func _feet_local(bounds: Rect2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return Vector2(offset.x, 0.0)
	return _flip_local(Vector2(bounds.get_center().x, bounds.end.y))


func _flip_local(point: Vector2) -> Vector2:
	if flip_h:
		point.x = (2.0 * offset.x) - point.x
	return point


func react_to_tap() -> void:
	if sprite_frames == null:
		return
	_stop_tap_motion()
	match _current_pose:
		"sleep":
			_feedback = _sleepy_tap()
		"defeated":
			_feedback = _dormant_tap()
		_:
			_feedback = _awake_tap()
	_feedback.finished.connect(_resume_pose_motion)


func hit_react(element_multiplier: float = 1.0) -> void:
	if sprite_frames == null:
		return
	Sfx.play_effectiveness(element_multiplier)
	_stop_tap_motion()
	var knockback := -_facing_direction * 16.0
	# Jitter vertikal di atas knockback horizontal supaya kesan impact-nya
	# terasa sebagai shake, bukan cuma tersentak satu arah.
	var shake_y := 6.0 * clampf(element_multiplier, 0.5, 2.0)
	_feedback = create_tween()
	_feedback.tween_property(
		self, "position", _base_position + Vector2(knockback, -shake_y), 0.04
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_feedback.tween_property(
		self, "position", _base_position + Vector2(knockback * -0.55, shake_y), 0.05
	)
	_feedback.tween_property(
		self, "position", _base_position + Vector2(knockback * 0.28, -shake_y * 0.5), 0.04
	)
	_feedback.tween_property(self, "position", _base_position, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_feedback.finished.connect(_resume_pose_motion)


func _start_motion(pose: String) -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()

	# Reset dulu, kalau tidak sisa transform pose sebelumnya menumpuk.
	scale = Vector2.ONE
	rotation = 0.0
	position = _base_position
	match pose:
		"idle", "happy", "hungry", "dirty":
			_motion = _breathe(BREATH_IDLE_SEC, 0.045)
		"sleep":
			# Napas tidur lebih lambat dan lebih dalam, plus badan turun sedikit
			# supaya terlihat benar-benar melunak, bukan hanya diam.
			position = _base_position + Vector2(0.0, 3.0)
			_motion = _breathe(BREATH_SLEEP_SEC, 0.07)
		"attack":
			_motion = _lunge()
		"defeated":
			# Pose ini adalah Damaged/Dormant, bukan jasad yang kalah. Napas
			# pendek yang tidak simetris membuatnya terasa kelelahan sampai pulih.
			_motion = _heavy_breathe()
		_:
			_motion = _breathe(BREATH_IDLE_SEC, 0.045)


## Napas: melebar sedikit saat memendek, seperti massa yang tertekan.
## Karena offset menaruh kaki di origin, pemendekan ini terjadi dari bawah.
func _breathe(duration: float, amount: float) -> Tween:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "scale", Vector2(1.0 - amount * 0.5, 1.0 + amount), duration * 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2.ONE, duration * 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return tween


func _heavy_breathe() -> Tween:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "scale", Vector2(0.96, 1.075), BREATH_DAMAGED_SEC * 0.24) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.025, 0.965), BREATH_DAMAGED_SEC * 0.44) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2.ONE, BREATH_DAMAGED_SEC * 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(BREATH_DAMAGED_SEC * 0.10)
	return tween


func _lunge() -> Tween:
	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(
		self,
		"position",
		_base_position + Vector2(-14.0 * _facing_direction, 4.0),
		0.10
	) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(
		self,
		"position",
		_base_position + Vector2(26.0 * _facing_direction, -6.0),
		0.12
	) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", _base_position, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	return tween


func _stop_tap_motion() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_motion = null
	_feedback = null
	position = _base_position
	scale = Vector2.ONE
	rotation = 0.0


func _awake_tap() -> Tween:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", _base_position - Vector2(0.0, HOP_HEIGHT_PX), 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.08, 0.92), 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# chain() lalu set_parallel(true) akan menyatukan langkahnya lagi, sehingga
	# hop dan kembalinya jalan bersamaan dan Anima tampak tidak bergerak.
	tween.chain().tween_property(self, "position", _base_position, 0.20) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return tween


func _sleepy_tap() -> Tween:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", _base_position + Vector2(0.0, 6.0), 0.18) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation", -0.025, 0.18)
	tween.tween_property(self, "modulate", Color(0.86, 0.9, 1.08, 1.0), 0.18)
	tween.chain().tween_property(self, "position", _base_position, 0.26) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(self, "rotation", 0.0, 0.26)
	tween.parallel().tween_property(self, "modulate", Color.WHITE, 0.26)
	return tween


func _dormant_tap() -> Tween:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(0.975, 1.035), 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(self, "modulate", Color(0.76, 0.8, 0.94, 1.0), 0.16)
	tween.tween_property(self, "scale", Vector2.ONE, 0.28) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(self, "modulate", Color(0.68, 0.72, 0.82, 1.0), 0.28)
	return tween


func _resume_pose_motion() -> void:
	_feedback = null
	if not _queued_care.is_empty():
		var sleeping := bool(_queued_care.get("sleeping", false))
		var dormant := bool(_queued_care.get("dormant", false))
		var care: Variant = _queued_care.get("care", {})
		_queued_care.clear()
		apply_care_state(sleeping, dormant, care)
		return
	_start_motion(_current_pose)


## Pantulan sekali untuk Feed. Tidak mengganggu napas pose karena bounce menulis
## position sementara napas menulis scale.
func hop() -> void:
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = _bounce(1, HOP_HEIGHT_PX)


func celebrate_level_up() -> void:
	if sprite_frames == null or not visible:
		return
	if _motion != null and _motion.is_valid():
		_motion.kill()
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	set_pose("happy")
	position = _base_position
	rotation = 0.0
	modulate = Color(1.38, 1.18, 0.58, 1.0)
	scale = Vector2(0.88, 1.14)
	_feedback = create_tween()
	_feedback.tween_property(self, "position", _base_position - Vector2(0.0, 28.0), 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_feedback.parallel().tween_property(self, "scale", Vector2(1.14, 0.90), 0.16)
	_feedback.chain().tween_property(self, "position", _base_position, 0.30) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	_feedback.parallel().tween_property(self, "scale", Vector2.ONE, 0.30)
	_feedback.parallel().tween_property(self, "modulate", Color.WHITE, 0.34)
	_feedback.finished.connect(_resume_pose_motion, CONNECT_ONE_SHOT)


func play_bounce() -> void:
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = _bounce(PLAY_BOUNCE_COUNT, PLAY_BOUNCE_HEIGHT_PX)
	_feedback.finished.connect(_resume_pose_motion, CONNECT_ONE_SHOT)


## Kemenangan Battle: pose Happy plus lompatan tanpa akhir sampai pemain
## meninggalkan hasilnya. Berbeda dari play_bounce() yang dihitung enam kali,
## loop ini sengaja tidak menyambung _resume_pose_motion karena tidak selesai
## sendiri; set_pose() yang melepasnya saat session berikutnya dipasang.
##
## Lompatan itu hanya untuk Hatchling. Adult (Lv.16) dan Evolved (Lv.36) punya
## badan yang lebih besar dan berat, jadi mereka mendapat flourish membumi: dua
## angkatan pelan 8px yang selesai sendiri, tanpa pendaratan memantul.
func victory_celebration(level: int = 1) -> void:
	if sprite_frames == null:
		return
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = null
	_victory_loop = false
	set_pose("happy")
	if CareRules.form_key(level) == "hatchling":
		_victory_loop = true
		_feedback = _bounce(0, VICTORY_BOUNCE_HEIGHT_PX)
		return
	_feedback = _bounce(
		VICTORY_FLOURISH_COUNT,
		VICTORY_FLOURISH_HEIGHT_PX,
		0.34,
		0.42,
		0.16,
		Tween.TRANS_SINE
	)
	_feedback.finished.connect(_resume_pose_motion, CONNECT_ONE_SHOT)


## Guard: kilau menyapu badan sekali, seperti Harden. Dipanggil pada frame pelat
## Guard muncul, bukan setelah await-nya, supaya kilau dan copy-nya sejalan.
func guard_shimmer() -> void:
	if sprite_frames == null or not visible:
		return
	Sfx.play(Sfx.CUE_GUARD)
	if _shimmer != null and _shimmer.is_valid():
		_shimmer.kill()
	if _shimmer_material == null:
		_shimmer_material = ShaderMaterial.new()
		_shimmer_material.shader = GUARD_SHIMMER_SHADER
	material = _shimmer_material
	_shimmer = create_tween()
	_shimmer_material.set_shader_parameter("progress", 0.0)
	_shimmer.tween_property(
		_shimmer_material, "shader_parameter/progress", 1.0, GUARD_SHIMMER_SEC
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
	_shimmer.tween_callback(_clear_shimmer)


func _clear_shimmer() -> void:
	material = null
	if _shimmer_material != null:
		_shimmer_material.set_shader_parameter("progress", 0.0)


func _bounce(
	loops: int,
	height: float,
	rise_sec := 0.16,
	fall_sec := 0.18,
	hold_sec := 0.08,
	fall_trans := Tween.TRANS_BOUNCE
) -> Tween:
	var tween := create_tween().set_loops(loops)
	tween.tween_property(self, "position", _base_position - Vector2(0.0, height), rise_sec) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", _base_position, fall_sec) \
		.set_ease(Tween.EASE_IN).set_trans(fall_trans)
	tween.tween_interval(hold_sec)
	return tween


## `_feedback` memegang gerak (position/scale), `_care_tint` memegang warna
## (modulate) -- dua slot terpisah supaya Feed dan Item bisa punya bob DAN
## kilau sekaligus tanpa satu tween menimpa handle milik yang lain.
func care_feedback(action: String) -> void:
	if action == "feed":
		Sfx.play(Sfx.CUE_FEED)
	elif action == "item":
		Sfx.play(Sfx.CUE_ITEM)
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = null
	if _care_tint != null and _care_tint.is_valid():
		_care_tint.kill()
	_care_tint = null
	position = _base_position
	if action == "play":
		set_pose("happy")
		play_bounce()
		return
	if action == "feed":
		hop()
		_care_tint = _flash(Color(0.72, 1.30, 0.86, 1.0), false)
		_burst("feed")
		return
	if action == "item":
		_feedback = _bounce(
			2, ITEM_BOB_HEIGHT_PX, ITEM_BOB_RISE_SEC, ITEM_BOB_FALL_SEC,
			ITEM_BOB_HOLD_SEC, Tween.TRANS_QUAD
		)
		_care_tint = _flash(Color(0.45, 1.15, 1.70, 1.0), true)
		_burst("item")
		return
	var tint := Color.WHITE
	match action:
		"clean":
			tint = Color(0.55, 1.2, 1.35, 1.0)
			_burst("clean")
		"sleep":
			tint = Color(0.72, 0.78, 1.08, 1.0)
		"wake":
			tint = Color(1.14, 1.08, 0.72, 1.0)
		_:
			return
	_care_tint = _flash(tint, false)


## Kilau modulate sekali (single blip) atau dua kali (double blip untuk Item).
func _flash(tint: Color, double_blip: bool) -> Tween:
	var tween := create_tween()
	tween.tween_property(self, "modulate", tint, 0.08)
	if double_blip:
		tween.tween_property(self, "modulate", Color.WHITE, 0.12)
		tween.tween_property(self, "modulate", tint, 0.08)
	tween.tween_property(self, "modulate", Color.WHITE, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	return tween


## Percikan dampak Feed/Item. `CPUParticles2D`, bukan GPU: burst sekali-jalan
## berjumlah kecil sudah terdokumentasi lebih stabil di CPU pada mobile --
## GPUParticles2D bergantung compute path yang bisa flicker/berhenti render di
## sebagian GPU Android. Bukan procedural `_draw()` seperti tiga efek lain di
## proyek ini (incubator/first-anima/synthesis) karena itu efek TERSTRUKTUR
## (cincin, scanline) yang memang butuh kontrol penuh; sebaran acak sekali
## pakai lebih pendek sebagai node bawaan engine.
##
## `emission_shape = EMISSION_SHAPE_RECTANGLE` seukuran bounding box opak
## Anima -- percikan lahir menyebar di seluruh siluet badan, bukan cuma dari
## satu koordinat tengah, yang terasa jauh lebih kecil dari yang seharusnya.
func _burst(kind: String) -> void:
	if sprite_frames == null or not visible:
		return
	var host := get_parent() if get_parent() != null else self
	if _burst_particles == null or not is_instance_valid(_burst_particles):
		_burst_particles = CPUParticles2D.new()
		_burst_particles.z_index = 8
		_burst_particles.one_shot = true
		_burst_particles.explosiveness = 1.0
		_burst_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		# Alpha meluruh ke 0 sepanjang umur partikel -- tanpa ini partikel
		# one-shot berhenti mendadak (pop) tepat saat lifetime habis, bukan
		# memudar.
		_burst_particles.color_ramp = _burst_fade_ramp()
		host.add_child(_burst_particles)
	elif _burst_particles.get_parent() != host:
		_burst_particles.reparent(host)
	_burst_particles.position = (
		host.to_local(body_center_global()) if host is Node2D else body_center_global()
	)
	var bounds := opaque_local_rect()
	# Fallback kotak sedang kalau posenya belum termuat, supaya burst tidak
	# pernah menciut jadi satu titik.
	_burst_particles.emission_rect_extents = (
		bounds.size * 0.5 if bounds.size != Vector2.ZERO else Vector2(32.0, 40.0)
	)
	if kind == "item":
		_burst_particles.texture = _spark_texture()
		_burst_particles.gravity = Vector2.ZERO
		_burst_particles.orbit_velocity_min = 0.0
		_burst_particles.orbit_velocity_max = 0.0
		_burst_particles.amount = BURST_AMOUNT_ITEM
		_burst_particles.lifetime = BURST_LIFETIME_SEC
		_burst_particles.direction = Vector2.UP
		_burst_particles.spread = 150.0
		_burst_particles.initial_velocity_min = 90.0
		_burst_particles.initial_velocity_max = 190.0
		_burst_particles.angular_velocity_min = -240.0
		_burst_particles.angular_velocity_max = 240.0
		_burst_particles.scale_amount_min = 1.0
		_burst_particles.scale_amount_max = 2.0
		_burst_particles.color = Color(0.45, 1.15, 1.70, 1.0)
	elif kind == "clean":
		# Gelembung sabun: naik lambat lewat gravity NEGATIF (daya apung),
		# nol angular_velocity (ring radial-simetris tidak menampakkan rotasi),
		# dan orbit_velocity kecil untuk goyangan ke samping ala gelembung
		# nyata -- feed/item sengaja tidak memakainya karena percikan mereka
		# lurus dan tajam, bukan mengambang.
		_burst_particles.texture = _bubble_texture()
		_burst_particles.gravity = Vector2(0.0, -18.0)
		_burst_particles.orbit_velocity_min = -0.12
		_burst_particles.orbit_velocity_max = 0.12
		_burst_particles.amount = BURST_AMOUNT_CLEAN
		_burst_particles.lifetime = BURST_LIFETIME_SEC * 1.6
		_burst_particles.direction = Vector2.UP
		_burst_particles.spread = 65.0
		_burst_particles.initial_velocity_min = 30.0
		_burst_particles.initial_velocity_max = 70.0
		_burst_particles.angular_velocity_min = 0.0
		_burst_particles.angular_velocity_max = 0.0
		_burst_particles.scale_amount_min = 0.6
		_burst_particles.scale_amount_max = 1.5
		_burst_particles.color = Color(0.70, 1.30, 1.45, 1.0)
	else:
		_burst_particles.texture = _spark_texture()
		_burst_particles.gravity = Vector2.ZERO
		_burst_particles.orbit_velocity_min = 0.0
		_burst_particles.orbit_velocity_max = 0.0
		_burst_particles.amount = BURST_AMOUNT_FEED
		_burst_particles.lifetime = BURST_LIFETIME_SEC * 1.15
		_burst_particles.direction = Vector2.UP
		_burst_particles.spread = 90.0
		_burst_particles.initial_velocity_min = 55.0
		_burst_particles.initial_velocity_max = 130.0
		_burst_particles.angular_velocity_min = -160.0
		_burst_particles.angular_velocity_max = 160.0
		_burst_particles.scale_amount_min = 0.85
		_burst_particles.scale_amount_max = 1.7
		_burst_particles.color = Color(1.75, 1.55, 0.25, 1.0)
	# `restart()` sendiri tidak menyalakan `emitting` -- untuk one_shot yang
	# sudah selesai, toggle emitting saja (tanpa restart) juga tidak memutar
	# ulang siklusnya. Keduanya wajib bersama untuk burst kedua dan seterusnya.
	_burst_particles.restart()
	_burst_particles.emitting = true


static var _spark_texture_cache: GradientTexture2D = null


## Bercak bundar putih->transparan dibangun di kode, bukan aset baru: ukuran
## kecil (dipakai sebagai satu titik percikan) tidak butuh import step apa pun,
## dan glyph outline `sparkles.svg` yang ada terbaca buruk di skala partikel.
static func _spark_texture() -> GradientTexture2D:
	if _spark_texture_cache != null:
		return _spark_texture_cache
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 28
	texture.height = 28
	_spark_texture_cache = texture
	return texture


static var _bubble_texture_cache: GradientTexture2D = null


## Cincin putih dengan pusat transparan, bukan bercak penuh seperti
## `_spark_texture()` -- itu yang membuatnya terbaca sebagai gelembung sabun
## (rim terang, isi tembus pandang) alih-alih percikan padat.
static func _bubble_texture() -> GradientTexture2D:
	if _bubble_texture_cache != null:
		return _bubble_texture_cache
	var gradient := Gradient.new()
	# Both endpoints set BEFORE add_point() below -- Gradient.new() starts with
	# exactly 2 points at index 0/1, and add_point() inserts keeping offset
	# order, which shifts later indices. Calling set_color(1, ...) after
	# add_point() would silently hit the wrong (inserted) point and leave
	# Gradient's own default endpoint -- opaque white -- on the real offset
	# 1.0 point, which is what rendered as a solid white square past the
	# ring's radius.
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.58, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.74, Color(1.0, 1.0, 1.0, 0.55))
	gradient.add_point(0.88, Color(1.0, 1.0, 1.0, 0.9))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 48
	texture.height = 48
	_bubble_texture_cache = texture
	return texture


static var _burst_fade_ramp_cache: Gradient = null


## Putih->transparan sepanjang lifetime partikel, terpisah dari alpha radial
## `_spark_texture()` sendiri: yang ini mengontrol PELURUHAN dari waktu ke
## waktu (fade-out), bukan bentuk satu percikan.
static func _burst_fade_ramp() -> Gradient:
	if _burst_fade_ramp_cache != null:
		return _burst_fade_ramp_cache
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_burst_fade_ramp_cache = gradient
	return gradient


func apply_care_state(sleeping: bool, dormant: bool, care: Variant = {}) -> void:
	if dormant:
		modulate = Color(0.68, 0.72, 0.82, 1.0)
	else:
		modulate = Color.WHITE
	if (
		not dormant
		and not sleeping
		and _current_pose == "happy"
		and _feedback != null
		and _feedback.is_valid()
	):
		_queued_care = {"sleeping": sleeping, "dormant": dormant, "care": care}
		return
	_queued_care.clear()
	var pose: String = String(CARE_RULES.visual_pose(sleeping, dormant, care))
	if set_pose(pose):
		return
	if pose == "defeated":
		set_pose("sleep")
	else:
		set_pose(AnimaLoader.DEFAULT_POSE)


## Overlay sel fx_strike / fx_surge sebagai VFX tambahan, bukan ganti pose.
## Sibling di bawah parent yang sama supaya lunge Attack tidak menelan efeknya.
## Metadata manifest memilih projectile/sweep/impact/bloom. Sheet lama tanpa
## metadata tetap memakai projectile supaya cache lama tidak berubah perilaku.
## Sheet 2×2 tanpa sel itu melewati pemanggilan ini diam-diam.
func play_fx(pose: String, impact_global: Vector2 = Vector2.INF) -> void:
	if sprite_frames == null or not sprite_frames.has_animation(pose):
		return
	Sfx.play(Sfx.CUE_SURGE if pose == "fx_surge" else Sfx.CUE_STRIKE)
	var host := get_parent() if get_parent() != null else self
	if _fx == null or not is_instance_valid(_fx):
		_fx = Sprite2D.new()
		_fx.centered = true
		_fx.z_index = 8
		host.add_child(_fx)
	elif _fx.get_parent() != host:
		_fx.reparent(host)
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx.texture = sprite_frames.get_frame_texture(pose, 0)
	_fx.offset = Vector2.ZERO
	_fx.flip_h = flip_h
	_fx.visible = true
	_fx.modulate = Color.WHITE
	_fx.rotation = 0.0
	var toward := Vector2(36.0 * _facing_direction, -10.0)
	var start := position + toward if host != self else toward
	var impact := start
	if impact_global.is_finite():
		if host is CanvasItem:
			impact = (host as CanvasItem).to_local(impact_global)
		else:
			impact = impact_global
	var motion := fx_motion(pose)
	_fx.position = impact if motion in ["impact", "bloom"] and impact_global.is_finite() else start
	if motion == "sweep":
		var sweep_center := impact if impact_global.is_finite() else start
		_fx.position = sweep_center - Vector2(30.0 * _facing_direction, 0.0)
		_fx.scale = Vector2(0.72, 0.92)
		_fx.rotation = -0.28 * _facing_direction
		_fx_tween = create_tween()
		_fx_tween.set_parallel(true)
		_fx_tween.tween_property(
			_fx, "position", sweep_center + Vector2(22.0 * _facing_direction, 0.0), 0.22
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_property(_fx, "scale", Vector2(1.12, 1.0), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_property(_fx, "rotation", 0.08 * _facing_direction, 0.22)
		_fx_tween.chain().tween_property(_fx, "modulate:a", 0.0, 0.14)
		_fx_tween.tween_callback(_hide_fx)
		return
	if motion == "impact":
		_fx.position = impact if impact_global.is_finite() else start
		_fx.scale = Vector2(0.46, 0.46)
		_fx_tween = create_tween()
		_fx_tween.tween_property(_fx, "scale", Vector2(1.14, 1.14), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_interval(0.08)
		_fx_tween.tween_property(_fx, "modulate:a", 0.0, 0.16)
		_fx_tween.tween_callback(_hide_fx)
		return
	if motion == "bloom":
		_fx.position = impact if impact_global.is_finite() else start
		_fx.scale = Vector2(0.34, 0.34)
		_fx.rotation = -0.12 * _facing_direction
		_fx_tween = create_tween()
		_fx_tween.set_parallel(true)
		_fx_tween.tween_property(_fx, "scale", Vector2(1.24, 1.24), 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_property(_fx, "rotation", 0.10 * _facing_direction, 0.20)
		_fx_tween.chain().tween_interval(0.02)
		_fx_tween.tween_property(_fx, "modulate:a", 0.0, 0.14)
		_fx_tween.tween_callback(_hide_fx)
		return
	if impact_global.is_finite():
		_fx.scale = Vector2.ONE
		_fx_tween = create_tween()
		_fx_tween.tween_property(_fx, "position", impact, FX_TRAVEL_SEC) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_fx_tween.tween_interval(0.10)
		_fx_tween.tween_property(_fx, "modulate:a", 0.0, 0.18)
		_fx_tween.tween_callback(_hide_fx)
		return
	_fx.scale = Vector2(0.88, 0.88)
	_fx_tween = create_tween()
	_fx_tween.tween_property(_fx, "scale", Vector2(1.18, 1.18), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_interval(0.18)
	_fx_tween.tween_property(_fx, "modulate:a", 0.0, 0.22)
	_fx_tween.tween_callback(_hide_fx)


func _hide_fx() -> void:
	if is_instance_valid(_fx):
		_fx.visible = false
		_fx.scale = Vector2.ONE
		_fx.rotation = 0.0
		_fx.modulate = Color.WHITE


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_hide_fx()
		if _shimmer != null and _shimmer.is_valid():
			_shimmer.kill()
		_clear_shimmer()


func _exit_tree() -> void:
	if is_instance_valid(_fx) and _fx.get_parent() != self:
		_fx.queue_free()
	_fx = null


## Reveal satu kali setelah Incubator mencapai flash puncak. Pose tween dihentikan
## dulu supaya dua tween tidak berebut scale/position, lalu dinyalakan lagi saat
## squash-and-stretch selesai.
func hatch_reveal() -> void:
	if sprite_frames == null:
		return
	if _motion != null and _motion.is_valid():
		_motion.kill()
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	visible = true
	position = _base_position - Vector2(0.0, 46.0)
	scale = Vector2(0.18, 1.24)
	rotation = -0.10
	modulate = Color(0.68, 1.18, 1.42, 0.0)

	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(self, "modulate", Color.WHITE, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	reveal.tween_property(self, "position", _base_position, 0.48) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	reveal.tween_property(self, "scale", Vector2(1.16, 0.90), 0.40) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	reveal.tween_property(self, "rotation", 0.035, 0.36) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await reveal.finished

	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(self, "scale", Vector2(0.96, 1.08), 0.12) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	settle.tween_property(self, "rotation", -0.018, 0.12)
	await settle.finished

	var finish := create_tween().set_parallel(true)
	finish.tween_property(self, "scale", Vector2.ONE, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	finish.tween_property(self, "rotation", 0.0, 0.18)
	await finish.finished

	modulate = Color.WHITE
	_start_motion(_current_pose)


func summon_dissolve() -> void:
	if sprite_frames == null or not visible:
		return
	if _motion != null and _motion.is_valid():
		_motion.kill()
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	var dissolve := create_tween().set_parallel(true)
	dissolve.tween_property(self, "modulate", Color(0.45, 0.92, 1.25, 0.0), 0.28) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	dissolve.tween_property(self, "scale", Vector2(0.66, 1.12), 0.28) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	dissolve.tween_property(self, "position", _base_position - Vector2(0.0, 28.0), 0.28)
	dissolve.tween_property(self, "rotation", 0.08, 0.28)
	await dissolve.finished
	visible = false
	position = _base_position
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE


func summon_reveal() -> void:
	await hatch_reveal()
