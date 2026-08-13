class_name ScanView
extends Control

signal scan_requested

@onready var _preview_panel: PanelContainer = %PreviewPanel
@onready var _preview: TextureRect = %PhotoPreview
@onready var _idle_graphic: TextureRect = $Column/DiscoverySpace/IdleGraphic
@onready var _scan_overlay: Control = %ScanOverlay
@onready var _phase_badge: Label = %ScanPhase
@onready var _status: Label = %ScanStatus
@onready var _hint: Label = %ScanPhaseHint
@onready var _scan_button: Button = %ScanButton

var _phase := &"idle"


func _ready() -> void:
	_scan_button.pressed.connect(scan_requested.emit)
	set_phase(&"idle")


func set_busy(busy: bool) -> void:
	_scan_button.disabled = busy


func set_status(message: String) -> void:
	_status.text = message


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
			_hint.text = tr("SCAN_CAMERA_HINT")


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
