class_name BossSeekerPresenter
extends AnimatedSprite2D

const CUT_IN_TRAVEL := Vector2(-40.0, 26.0)

var _cut_in: Tween
var _rest_position := Vector2.ZERO
var _cut_in_position := CUT_IN_TRAVEL
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
	z_index = 1
	set_pose("intro_idle")


func clear() -> void:
	if is_instance_valid(_cut_in):
		_cut_in.kill()
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
	_cut_in_position = rest_position + CUT_IN_TRAVEL
	_body_scale = maxf(body_scale, 0.01)
	position = _rest_position
	scale = Vector2(_body_scale, _body_scale)


func play_cut_in() -> void:
	position = _rest_position
	if UiMotion.reduced_motion:
		return
	if is_instance_valid(_cut_in):
		_cut_in.kill()
	_cut_in = create_tween()
	_cut_in.tween_property(self, "position", _cut_in_position, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cut_in.tween_property(self, "position", _rest_position, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
