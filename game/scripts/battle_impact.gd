class_name BattleImpact
extends Control

const REFERENCE_WIDTH := 720.0
const MAX_AMPLITUDE := 14.0
const BACKGROUND_RATIO := 0.40
const REFIT_BACKGROUND_PX := 4.0
const OVERSCAN_SAFETY_PX := 2.0
const COMMAND_HAPTIC_MS := 18
const SHAKE_WEIGHTS: Array[float] = [0.16, 0.26, 0.23, 0.18, 0.17]

const RESISTED_PROFILE := {"amplitude": 4.0, "duration": 0.14, "haptic_ms": 35}
const NEUTRAL_PROFILE := {"amplitude": 6.0, "duration": 0.18, "haptic_ms": 35}
const STRONG_PROFILE := {"amplitude": 8.0, "duration": 0.22, "haptic_ms": 55}
const KILLING_PROFILE := {"amplitude": 10.0, "duration": 0.28, "haptic_ms": 70}
const STATUS_KO_PROFILE := {"amplitude": 8.0, "duration": 0.20, "haptic_ms": 55}

var _scenery_offset: Control
var _shake_tween: Tween


func mount(arena: Control, background: Control) -> void:
	name = "BattleWorldOffset"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_index: int = background.get_index()
	arena.add_child(self)
	arena.move_child(self, background_index)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scenery_offset = Control.new()
	_scenery_offset.name = "BattleSceneryOffset"
	_scenery_offset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scenery_offset)
	_scenery_offset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.reparent(_scenery_offset)


func add_foreground(layer: Node2D) -> void:
	add_child(layer)


func play_event(event: Dictionary, physical_feedback: bool = true) -> void:
	cancel()
	var profile := profile_for_event(event)
	if profile.is_empty() or not physical_feedback or not is_visible_in_tree():
		return
	vibrate(int(profile.haptic_ms))
	if not GameState.battle_shake_enabled():
		return
	var amplitude := scaled_amplitude(float(profile.amplitude), size.x)
	if amplitude <= 0.0:
		return
	var points := shake_points(amplitude, impact_direction(event))
	var duration := float(profile.duration)
	_shake_tween = create_tween()
	for index in range(points.size() - 1):
		_shake_tween.tween_method(
			_apply_world_offset,
			points[index],
			points[index + 1],
			duration * SHAKE_WEIGHTS[index]
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shake_tween.finished.connect(_finish_shake)


func cancel() -> void:
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	_shake_tween = null
	_apply_world_offset(Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel()


func _exit_tree() -> void:
	cancel()


func _finish_shake() -> void:
	_shake_tween = null
	_apply_world_offset(Vector2.ZERO)


func _apply_world_offset(offset: Vector2) -> void:
	position = offset
	if is_instance_valid(_scenery_offset):
		_scenery_offset.position = -offset * (1.0 - BACKGROUND_RATIO)


static func profile_for_event(event: Dictionary) -> Dictionary:
	var event_type := str(event.get("type", ""))
	var target_hp := int(event.get("target_hp", 1))
	if event_type == "status_tick":
		var amount := int(event.get("amount", 0))
		return STATUS_KO_PROFILE.duplicate() if amount > 0 and target_hp <= 0 else {}
	var damage := int(event.get("damage", 0))
	if event_type != "attack" or damage <= 0:
		return {}
	if target_hp <= 0:
		return KILLING_PROFILE.duplicate()
	var multiplier := float(event.get("element_multiplier", 1.0))
	if bool(event.get("crit", false)) or multiplier > 1.0:
		return STRONG_PROFILE.duplicate()
	if multiplier < 1.0:
		return RESISTED_PROFILE.duplicate()
	return NEUTRAL_PROFILE.duplicate()


static func message_keys(event: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray()
	if bool(event.get("crit", false)):
		keys.append("BATTLE_CRITICAL")
	var multiplier := float(event.get("element_multiplier", 1.0))
	if multiplier > 1.0:
		keys.append("BATTLE_EFFECTIVE")
	elif multiplier < 1.0:
		keys.append("BATTLE_NOT_EFFECTIVE")
	return keys


static func scaled_amplitude(base_amplitude: float, arena_width: float) -> float:
	return minf(base_amplitude * maxf(arena_width, 0.0) / REFERENCE_WIDTH, MAX_AMPLITUDE)


static func background_overscan_px(arena_width: float) -> float:
	return (
		scaled_amplitude(float(KILLING_PROFILE.amplitude), arena_width) * BACKGROUND_RATIO
		+ REFIT_BACKGROUND_PX
		+ OVERSCAN_SAFETY_PX
	)


static func shake_points(amplitude: float, x_direction: float = 1.0) -> Array[Vector2]:
	return [
		Vector2.ZERO,
		Vector2(amplitude * 0.98 * x_direction, -amplitude * 0.18),
		Vector2(-amplitude * 0.54 * x_direction, amplitude * 0.16),
		Vector2(amplitude * 0.28 * x_direction, -amplitude * 0.09),
		Vector2(-amplitude * 0.11 * x_direction, amplitude * 0.04),
		Vector2.ZERO,
	]


static func impact_direction(event: Dictionary) -> float:
	return -1.0 if str(event.get("target", "")) == "player" else 1.0


static func command_haptic() -> void:
	vibrate(COMMAND_HAPTIC_MS)


static func vibrate(duration_ms: int) -> void:
	if duration_ms > 0 and GameState.haptics_enabled():
		Input.vibrate_handheld(duration_ms)
