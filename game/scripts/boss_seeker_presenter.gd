class_name BossSeekerPresenter
extends AnimatedSprite2D

var _rest_position := Vector2.ZERO
var _body_scale := 1.0
var _ground_offset := Vector2(0.0, -150.0)
var _pose_ground_offsets: Dictionary = {}


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
	offset = _ground_offset
	scale = Vector2(_body_scale, _body_scale)
	position = _rest_position
	visible = sprite_frames != null
	set_pose("intro_idle")


func clear() -> void:
	sprite_frames = null
	_pose_ground_offsets.clear()
	visible = false


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
