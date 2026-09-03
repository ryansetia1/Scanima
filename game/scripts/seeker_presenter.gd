class_name SeekerPresenter
extends AnimatedSprite2D

var _rest_position := Vector2.ZERO
var _body_scale := 1.0
var _ground_offset := Vector2(0.0, -150.0)
var _pose_ground_offsets: Dictionary = {}
var _reference_width := BattleScale.SEEKER_REFERENCE_WIDTH_PX


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
	offset = _ground_offset
	scale = Vector2(_body_scale, _body_scale)
	position = _rest_position
	visible = sprite_frames != null
	set_pose("intro_idle")


func clear() -> void:
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
	var pose_offset: Variant = _pose_ground_offsets.get(pose, _ground_offset)
	offset = pose_offset if typeof(pose_offset) == TYPE_VECTOR2 else _ground_offset
	animation = pose
	play(pose)


func set_layout(rest_position: Vector2, body_scale: float) -> void:
	_rest_position = rest_position
	_body_scale = maxf(body_scale, 0.01)
	position = _rest_position
	scale = Vector2(_body_scale, _body_scale)


func play_cut_in() -> void:
	# Command poses stay planted; wider art may crop instead of shifting the body.
	return
