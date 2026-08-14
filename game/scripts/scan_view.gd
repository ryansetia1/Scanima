class_name ScanView
extends Control

signal scan_requested
signal sign_in_requested

@onready var _preview_panel: PanelContainer = %PreviewPanel
@onready var _preview: TextureRect = %PhotoPreview
@onready var _idle_graphic: TextureRect = $Column/DiscoverySpace/IdleGraphic
@onready var _scan_overlay: Control = %ScanOverlay
@onready var _phase_badge: Label = %ScanPhase
@onready var _status: Label = %ScanStatus
@onready var _hint: Label = %ScanPhaseHint
@onready var _scan_button: Button = %ScanButton

var _phase := &"idle"
var _cores := -1
var _busy := false
var _sign_in_required := false


func _ready() -> void:
	_scan_button.pressed.connect(_on_primary_pressed)
	set_phase(&"idle")


func set_busy(busy: bool) -> void:
	_busy = busy
	_scan_button.disabled = busy
	_refresh_lock()


func set_cores(cores: int) -> void:
	_cores = cores
	_refresh_lock()


func set_sign_in_required(required: bool) -> void:
	_sign_in_required = required
	_refresh_lock()


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
			_refresh_lock()


func _refresh_lock() -> void:
	var locked := _cores == 0 and not _sign_in_required
	_scan_button.self_modulate = (
		Color(1, 1, 1, 0.42) if locked and not _busy else Color.WHITE
	)
	_scan_button.text = tr("SCAN_SIGN_IN_ACTION") if _sign_in_required else tr("SCAN_PRIMARY_ACTION")
	if _phase == &"idle":
		if _sign_in_required:
			_hint.text = tr("SCAN_SIGN_IN_HINT")
		else:
			_hint.text = tr("SCAN_NO_CORE_HINT") if locked else tr("SCAN_CAMERA_HINT")


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
