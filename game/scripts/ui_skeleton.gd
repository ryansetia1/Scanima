class_name UiSkeleton
extends VBoxContainer

var _pulse: Tween


func set_loading(loading: bool) -> void:
	visible = loading
	if not loading:
		_stop_pulse()
		modulate = Color.WHITE
		return
	_start_pulse()


func _start_pulse() -> void:
	_stop_pulse()
	if UiMotion.reduced_motion:
		modulate = Color(1.0, 1.0, 1.0, 0.58)
		return
	modulate = Color(0.82, 0.9, 1.0, 0.42)
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "modulate", Color(0.72, 0.94, 1.12, 0.9), 0.62) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "modulate", Color(0.82, 0.9, 1.0, 0.42), 0.62) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_stop_pulse()
