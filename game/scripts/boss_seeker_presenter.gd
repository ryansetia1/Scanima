class_name BossSeekerPresenter
extends AnimatedSprite2D

const REST_OFFSET := Vector2(58.0, -78.0)
const CUT_IN_OFFSET := Vector2(18.0, -52.0)
const BODY_SCALE := 0.92

var _cut_in: Tween


func apply(loaded: Dictionary) -> void:
	if not bool(loaded.get("ok", false)):
		clear()
		return
	sprite_frames = loaded.get("frames")
	offset = loaded.get("ground_offset", Vector2(0.0, -150.0))
	scale = Vector2(BODY_SCALE, BODY_SCALE)
	position = REST_OFFSET
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


func play_cut_in() -> void:
	position = REST_OFFSET
	if UiMotion.reduced_motion:
		return
	if is_instance_valid(_cut_in):
		_cut_in.kill()
	_cut_in = create_tween()
	_cut_in.tween_property(self, "position", CUT_IN_OFFSET, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cut_in.tween_property(self, "position", REST_OFFSET, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
