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
const HOP_HEIGHT_PX := 10.0

var _motion: Tween
var _base_position: Vector2 = Vector2.ZERO
var _current_pose: String = ""


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


func _start_motion(pose: String) -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()

	# Reset dulu, kalau tidak sisa transform pose sebelumnya menumpuk.
	scale = Vector2.ONE
	rotation = 0.0
	position = _base_position

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
			# Satu kali menghela, lalu benar-benar diam. Kreatur yang tumbang
			# tapi tetap bernapas ritmis terbaca seperti bug, bukan kekalahan.
			_motion = create_tween()
			_motion.tween_property(self, "scale", Vector2(1.03, 0.95), 0.35) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
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


func _lunge() -> Tween:
	var tween := create_tween().set_loops()
	tween.set_parallel(false)
	tween.tween_property(self, "position", _base_position + Vector2(-16.0, 4.0), 0.14) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "position", _base_position + Vector2(22.0, -6.0), 0.10) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", _base_position, 0.28) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(0.5)
	return tween


## Pantulan sekali, untuk dipakai saat pemain menyentuh Anima atau saat diberi
## makan. Tidak mengganggu tween pose karena berjalan di tween terpisah.
func hop() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", _base_position - Vector2(0.0, HOP_HEIGHT_PX), 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", _base_position, 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
