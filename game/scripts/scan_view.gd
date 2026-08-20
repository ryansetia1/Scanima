class_name ScanView
extends Control

signal scan_requested
signal sign_in_requested

const VIBES: PackedStringArray = ["natural", "cute", "brave", "wild", "sinister"]
const DEFAULT_VIBE := "natural"
# Lucide camera flash sits above and left of the body; (8, 24) is the optical
# center at 172px. Revisit if the glyph changes.
const CAMERA_OPTICAL_OFFSET := Vector2(8.0, 24.0)

@onready var _preview_panel: PanelContainer = %PreviewPanel
@onready var _preview: TextureRect = %PhotoPreview
@onready var _subtitle: Label = $Column/Subtitle
@onready var _discovery_space: Control = $Column/DiscoverySpace
@onready var _idle_graphic: TextureRect = $Column/DiscoverySpace/IdleGraphic
@onready var _scan_overlay: Control = %ScanOverlay
@onready var _status_panel: PanelContainer = %StatusPanel
@onready var _phase_badge: Label = %ScanPhase
@onready var _status: Label = %ScanStatus
@onready var _hint: Label = %ScanPhaseHint
@onready var _vibe_block: VBoxContainer = %VibeBlock
@onready var _vibe_hint: Label = %VibeHint
@onready var _scan_button: Button = %ScanButton

var _phase := &"idle"
var _cores := -1
var _busy := false
var _sign_in_required := false
var _vibe: String = DEFAULT_VIBE
var _vibe_buttons: Array[Button] = []


static func normalize_vibe(value: Variant) -> String:
	var slug := str(value).strip_edges().to_lower()
	return slug if VIBES.has(slug) else DEFAULT_VIBE


func _ready() -> void:
	_scan_button.pressed.connect(_on_primary_pressed)
	for slug in VIBES:
		var button := _vibe_block.find_child("Vibe%s" % slug.capitalize(), true, false) as Button
		if button == null:
			continue
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.set_meta("vibe", slug)
		button.pressed.connect(_on_vibe_pressed.bind(slug))
		_vibe_buttons.append(button)
	resized.connect(_align_idle_graphic)
	_discovery_space.resized.connect(_align_idle_graphic)
	visibility_changed.connect(_align_idle_graphic)
	set_phase(&"idle")
	_refresh_vibe_ui()
	_align_idle_graphic.call_deferred()


func vibe() -> String:
	return _vibe


func set_vibe(slug: String) -> void:
	_vibe = normalize_vibe(slug)
	_refresh_vibe_ui()


func reset_vibe() -> void:
	set_vibe(DEFAULT_VIBE)


func set_busy(busy: bool) -> void:
	_busy = busy
	_scan_button.disabled = busy
	_refresh_lock()
	_refresh_vibe_ui()


func set_cores(cores: int) -> void:
	_cores = cores
	_refresh_lock()


func set_sign_in_required(required: bool) -> void:
	_sign_in_required = required
	_refresh_lock()


func set_status(message: String) -> void:
	_status.text = message


func refresh_localized_ui() -> void:
	set_phase(_phase)


func set_phase(phase: StringName) -> void:
	_phase = phase
	_idle_graphic.visible = phase == &"idle" and not _preview_panel.visible
	_scan_overlay.call("set_active", phase == &"analyzing" and _preview_panel.visible)
	match phase:
		&"analyzing":
			_phase_badge.text = tr("SCAN_PHASE_ANALYZE")
			_hint.text = tr("SCAN_PHASE_ANALYZE_HINT")
		&"synthesizing":
			_phase_badge.text = tr("SCAN_PHASE_SYNTHESIZE")
			_hint.text = tr("SCAN_PHASE_SYNTHESIZE_HINT")
		_:
			_phase_badge.text = tr("SCAN_NEW_DISCOVERY")
			_refresh_lock()
	_refresh_idle_copy()
	_refresh_vibe_ui()
	_align_idle_graphic.call_deferred()


func _refresh_lock() -> void:
	var locked := _cores == 0 and not _sign_in_required
	_scan_button.self_modulate = (
		Color(1, 1, 1, 0.42) if locked and not _busy else Color.WHITE
	)
	_scan_button.text = tr("SCAN_SIGN_IN_ACTION") if _sign_in_required else tr("SCAN_PRIMARY_ACTION")
	if _phase == &"idle":
		if _sign_in_required:
			_hint.text = tr("SCAN_SIGN_IN_HINT")
		elif locked:
			_hint.text = tr("SCAN_NO_CORE_HINT")
		else:
			_hint.text = tr("SCAN_CAMERA_HINT")
	_refresh_idle_copy()


func _refresh_idle_copy() -> void:
	var idle := _phase == &"idle"
	_subtitle.visible = false
	_phase_badge.visible = not idle
	_status.visible = not idle
	_hint.visible = not idle or not _sign_in_required
	_status_panel.visible = _phase_badge.visible or _status.visible or _hint.visible


func _align_idle_graphic() -> void:
	if not is_instance_valid(_idle_graphic) or not is_instance_valid(_discovery_space):
		return
	var space := _discovery_space
	if space.size.x < 8.0 or space.size.y < 8.0:
		return
	var chamber := ScanimaBackground.chamber_center(get_viewport_rect().size)
	var local := space.get_global_transform_with_canvas().affine_inverse() * chamber
	local += CAMERA_OPTICAL_OFFSET
	var half := _idle_graphic.size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		half = Vector2(86.0, 86.0)
	local.x = clampf(local.x, half.x, maxf(half.x, space.size.x - half.x))
	local.y = clampf(local.y, half.y, maxf(half.y, space.size.y - half.y))
	var delta := local - space.size * 0.5
	_idle_graphic.offset_left = -half.x + delta.x
	_idle_graphic.offset_top = -half.y + delta.y
	_idle_graphic.offset_right = half.x + delta.x
	_idle_graphic.offset_bottom = half.y + delta.y


func _refresh_vibe_ui() -> void:
	var idle := _phase == &"idle"
	_vibe_block.visible = idle
	var title := _vibe_block.get_node_or_null("VibeTitle") as Label
	if title != null:
		title.text = tr("SCAN_VIBE_TITLE")
	for button in _vibe_buttons:
		var slug := str(button.get_meta("vibe", ""))
		var selected := slug == _vibe
		button.set_pressed_no_signal(selected)
		button.disabled = _busy or not idle
		button.theme_type_variation = &"VibeSelected" if selected else &""
		button.text = tr("SCAN_VIBE_%s" % slug.to_upper())
	_vibe_hint.text = tr("SCAN_VIBE_HINT_%s" % _vibe.to_upper())


func _on_vibe_pressed(slug: String) -> void:
	if _busy or _phase != &"idle":
		_refresh_vibe_ui()
		return
	set_vibe(slug)


func _on_primary_pressed() -> void:
	if _sign_in_required:
		sign_in_requested.emit()
	else:
		scan_requested.emit()


func show_preview(texture: Texture2D) -> void:
	_preview.texture = texture
	_preview_panel.visible = texture != null
	_idle_graphic.visible = texture == null and _phase == &"idle"
	_scan_overlay.call("set_active", texture != null and _phase == &"analyzing")
	if texture != null:
		UiJuice.reveal(_preview_panel)


func clear_preview() -> void:
	_preview.texture = null
	_preview_panel.visible = false
	_scan_overlay.call("set_active", false)
	_idle_graphic.visible = _phase == &"idle"


func has_preview() -> bool:
	return _preview_panel.visible
