class_name AnimaPresenter
extends AnimatedSprite2D

## Menghidupkan Anima dari empat gambar statis.
##
## Model hanya memberi 4 pose, bukan 4 animasi. Gerakannya datang dari Tween di
## sisi Godot: napas, pantulan kecil, tersentak saat menyerang. Ini bukan
## penghematan sementara, melainkan alasan biaya art bisa satu panggilan per
## Anima: menganimasikan 8 frame per pose lewat model berarti 8x biaya dan
## konsistensi yang tidak mungkin dijaga.

signal pose_changed(pose: String)

const BREATH_IDLE_SEC := 1.6
const BREATH_SLEEP_SEC := 2.8
const BREATH_DAMAGED_SEC := 1.1
const HOP_HEIGHT_PX := 10.0
const PLAY_BOUNCE_HEIGHT_PX := 14.0
const PLAY_BOUNCE_COUNT := 6

var _motion: Tween
var _feedback: Tween
var _base_position: Vector2 = Vector2.ZERO
var _current_pose: String = ""
var _facing_direction := -1.0


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
	_base_position = position
	set_pose(AnimaLoader.DEFAULT_POSE)
	return true


func set_pose(pose: String) -> bool:
	if sprite_frames == null or not sprite_frames.has_animation(pose):
		return false

	animation = pose
	# Tiap pose satu frame, jadi play() hanya menampilkannya; yang bergerak Tween.
	play()
	_current_pose = pose
	_start_motion(pose)
	pose_changed.emit(pose)
	return true


func current_pose() -> String:
	return _current_pose


## Sprite sheet selalu dibuat menghadap kiri. Arena membalik petarung di sisi
## kiri agar pose dan gerak serang keduanya menuju lawan.
func set_facing(direction: float) -> void:
	_facing_direction = -1.0 if direction < 0.0 else 1.0
	flip_h = _facing_direction > 0.0


func _start_motion(pose: String) -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()

	# Reset dulu, kalau tidak sisa transform pose sebelumnya menumpuk.
	scale = Vector2.ONE
	rotation = 0.0
	position = _base_position
	if UiMotion.reduced_motion:
		return

	match pose:
		"idle":
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


## Pantulan sekali untuk Feed. Tidak mengganggu napas pose karena bounce menulis
## position sementara napas menulis scale.
func hop() -> void:
	if UiMotion.reduced_motion:
		return
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = _bounce(1, HOP_HEIGHT_PX)


func play_bounce() -> void:
	if UiMotion.reduced_motion:
		return
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = _bounce(PLAY_BOUNCE_COUNT, PLAY_BOUNCE_HEIGHT_PX)


func _bounce(loops: int, height: float) -> Tween:
	var tween := create_tween().set_loops(loops)
	tween.tween_property(self, "position", _base_position - Vector2(0.0, height), 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", _base_position, 0.18) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	tween.tween_interval(0.08)
	return tween


func care_feedback(action: String) -> void:
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = null
	position = _base_position
	if UiMotion.reduced_motion:
		return

	var tint := Color.WHITE
	match action:
		"feed":
			hop()
			return
		"play":
			play_bounce()
			return
		"clean":
			tint = Color(0.55, 1.2, 1.35, 1.0)
		"sleep":
			tint = Color(0.72, 0.78, 1.08, 1.0)
		"wake":
			tint = Color(1.14, 1.08, 0.72, 1.0)
		_:
			return

	_feedback = create_tween()
	_feedback.tween_property(self, "modulate", tint, 0.12)
	_feedback.tween_property(self, "modulate", Color.WHITE, 0.34) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func apply_care_state(sleeping: bool, dormant: bool) -> void:
	if dormant:
		modulate = Color(0.68, 0.72, 0.82, 1.0)
		if not set_pose("defeated"):
			set_pose("sleep")
		return

	modulate = Color.WHITE
	if sleeping:
		set_pose("sleep")
	elif _current_pose == "sleep" or _current_pose == "defeated":
		set_pose("idle")


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
	if UiMotion.reduced_motion:
		visible = true
		position = _base_position
		scale = Vector2.ONE
		rotation = 0.0
		modulate = Color.WHITE
		return

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
	if UiMotion.reduced_motion:
		visible = false
		return

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
