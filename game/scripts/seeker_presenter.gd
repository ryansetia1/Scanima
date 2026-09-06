class_name SeekerPresenter
extends AnimatedSprite2D

const IDLE_POSE := "intro_idle"
const IDLE_ORGANIC := "organic"
const IDLE_MECHANICAL := "mechanical"
const ORGANIC_BREATH_SCALE := 1.008
const ORGANIC_BREATH_IN_SEC := 1.6
const ORGANIC_BREATH_OUT_SEC := 1.9
const ORGANIC_SHIFT_RADIANS := 0.0038
const ORGANIC_SHIFT_WAIT_SEC := 3.4
const ORGANIC_SHIFT_SEC := 0.9
const MECHANICAL_SETTLE_SCALE := 0.994
const MECHANICAL_SETTLE_RADIANS := 0.0028
const MECHANICAL_SETTLE_IN_SEC := 0.16
const MECHANICAL_SETTLE_OUT_SEC := 0.22
const MECHANICAL_SETTLE_WAIT_SEC := 4.2

var _rest_position := Vector2.ZERO
var _body_scale := 1.0
var _ground_offset := Vector2(0.0, -150.0)
var _pose_ground_offsets: Dictionary = {}
var _reference_width := BattleScale.SEEKER_REFERENCE_WIDTH_PX
var _idle_motion_kind := IDLE_ORGANIC
var _primary_idle_tween: Tween = null
var _secondary_idle_tween: Tween = null


func apply(loaded: Dictionary) -> void:
	if not bool(loaded.get("ok", false)):
		clear()
		return
	sprite_frames = loaded.get("frames")
	_ground_offset = loaded.get("ground_offset", Vector2(0.0, -150.0))
	var pose_offsets_value: Variant = loaded.get("pose_ground_offsets", {})
	_pose_ground_offsets = (
		pose_offsets_value if typeof(pose_offsets_value) == TYPE_DICTIONARY else {}
	)
	_reference_width = maxf(1.0, BattleScale.seeker_reference_width(loaded))
	_idle_motion_kind = str(loaded.get("idle_motion_kind", IDLE_ORGANIC))
	offset = _ground_offset
	scale = Vector2(_body_scale, _body_scale)
	position = _rest_position
	visible = sprite_frames != null
	set_pose("intro_idle")


func clear() -> void:
	_stop_idle_motion()
	sprite_frames = null
	_pose_ground_offsets.clear()
	_reference_width = BattleScale.SEEKER_REFERENCE_WIDTH_PX
	visible = false


## Bayangan kontak figur Seeker. Ia sengaja menuntut `shadow` bersaudara dengan
## presenter-nya di layer yang sama — Seeker berdiri diam, jadi posisi badan
## sudah cukup dan tidak perlu perhitungan kaki seperti `AnimaPresenter`.
func sync_ground_shadow(shadow: Sprite2D) -> void:
	if not is_instance_valid(shadow):
		return
	if not has_sheet():
		shadow.visible = false
		return
	shadow.visible = true
	shadow.z_index = z_index
	shadow.position = position
	shadow.scale = Vector2(
		clampf(_reference_width * absf(scale.x) / 130.0, 0.9, 3.0), 1.15
	)


func has_sheet() -> bool:
	return sprite_frames != null


func set_pose(pose: String) -> void:
	if sprite_frames == null or not sprite_frames.has_animation(pose):
		return
	_stop_idle_motion()
	var pose_offset: Variant = _pose_ground_offsets.get(pose, _ground_offset)
	offset = pose_offset if typeof(pose_offset) == TYPE_VECTOR2 else _ground_offset
	animation = pose
	play(pose)
	if pose == IDLE_POSE:
		_start_idle_motion()


## Shake impact singkat saat figur pemain kena serangan lawan, dipasangkan
## dengan pose "concern_hit" di pemanggil. Jangkarnya `position` saat dipanggil
## (bukan `_rest_position`), sebab `_pin_player_seeker_to_camera_left()`
## menimpa `position.x` di luar `set_layout()` tanpa memperbarui `_rest_position`.
func shake_impact() -> void:
	if sprite_frames == null:
		return
	var anchor := position
	var shake := create_tween()
	shake.tween_property(self, "position", anchor + Vector2(-6.0, -4.0), 0.04) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	shake.tween_property(self, "position", anchor + Vector2(5.0, 3.0), 0.05)
	shake.tween_property(self, "position", anchor + Vector2(-3.0, -2.0), 0.04)
	shake.tween_property(self, "position", anchor, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_layout(rest_position: Vector2, body_scale: float) -> void:
	var resume_idle := animation == IDLE_POSE
	_stop_idle_motion()
	_rest_position = rest_position
	_body_scale = maxf(body_scale, 0.01)
	position = _rest_position
	scale = Vector2(_body_scale, _body_scale)
	if resume_idle:
		_start_idle_motion()


## Camera compensation must update the presenter's baseline, not only `scale`:
## every pose transition restores `_body_scale` before starting its own motion.
func set_body_scale(body_scale: float) -> void:
	var resume_idle := animation == IDLE_POSE
	_stop_idle_motion()
	_body_scale = maxf(body_scale, 0.01)
	scale = Vector2(_body_scale, _body_scale)
	if resume_idle:
		_start_idle_motion()


## Ambient motion owns only scale/rotation; arena layout owns position and the
## parent fighter layer. Changing pose always kills both loops and restores this
## layout baseline before any command or reaction.
func _start_idle_motion() -> void:
	if not is_inside_tree() or sprite_frames == null or animation != IDLE_POSE:
		return
	if _idle_motion_kind == IDLE_MECHANICAL:
		_start_mechanical_settle()
		return
	_primary_idle_tween = create_tween().set_loops()
	_primary_idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_primary_idle_tween.tween_property(
		self, "scale:y", _body_scale * ORGANIC_BREATH_SCALE, ORGANIC_BREATH_IN_SEC
	)
	_primary_idle_tween.tween_property(self, "scale:y", _body_scale, ORGANIC_BREATH_OUT_SEC)
	_secondary_idle_tween = create_tween().set_loops()
	_secondary_idle_tween.tween_interval(ORGANIC_SHIFT_WAIT_SEC)
	_secondary_idle_tween.tween_property(
		self, "rotation", ORGANIC_SHIFT_RADIANS, ORGANIC_SHIFT_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_secondary_idle_tween.tween_property(
		self, "rotation", 0.0, ORGANIC_SHIFT_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_secondary_idle_tween.tween_interval(ORGANIC_SHIFT_WAIT_SEC)
	_secondary_idle_tween.tween_property(
		self, "rotation", -ORGANIC_SHIFT_RADIANS, ORGANIC_SHIFT_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_secondary_idle_tween.tween_property(
		self, "rotation", 0.0, ORGANIC_SHIFT_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_mechanical_settle() -> void:
	_primary_idle_tween = create_tween().set_loops()
	_primary_idle_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_primary_idle_tween.tween_property(
		self, "scale:y", _body_scale * MECHANICAL_SETTLE_SCALE, MECHANICAL_SETTLE_IN_SEC
	)
	_primary_idle_tween.parallel().tween_property(
		self, "rotation", MECHANICAL_SETTLE_RADIANS, MECHANICAL_SETTLE_IN_SEC
	)
	_primary_idle_tween.tween_property(
		self, "scale:y", _body_scale, MECHANICAL_SETTLE_OUT_SEC
	)
	_primary_idle_tween.parallel().tween_property(
		self, "rotation", 0.0, MECHANICAL_SETTLE_OUT_SEC
	)
	_primary_idle_tween.tween_interval(MECHANICAL_SETTLE_WAIT_SEC)


func _stop_idle_motion() -> void:
	if _primary_idle_tween != null and _primary_idle_tween.is_valid():
		_primary_idle_tween.kill()
	if _secondary_idle_tween != null and _secondary_idle_tween.is_valid():
		_secondary_idle_tween.kill()
	_primary_idle_tween = null
	_secondary_idle_tween = null
	scale = Vector2(_body_scale, _body_scale)
	rotation = 0.0


func play_cut_in() -> void:
	# Command poses stay planted; wider art may crop instead of shifting the body.
	return
