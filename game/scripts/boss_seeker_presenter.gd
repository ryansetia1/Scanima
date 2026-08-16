class_name BossSeekerPresenter
extends AnimatedSprite2D

var _rest_position := Vector2.ZERO
var _body_scale := 1.0


func apply(loaded: Dictionary) -> void:
	if not bool(loaded.get("ok", false)):
		clear()
		return
	sprite_frames = loaded.get("frames")
	offset = loaded.get("ground_offset", Vector2(0.0, -150.0))
	scale = Vector2(_body_scale, _body_scale)
	position = _rest_position
	visible = sprite_frames != null
	set_pose("intro_idle")


func clear() -> void:
	sprite_frames = null
	visible = false


func has_sheet() -> bool:
	return sprite_frames != null


func set_pose(pose: String) -> void:
	if sprite_frames == null or not sprite_frames.has_animation(pose):
		return
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
