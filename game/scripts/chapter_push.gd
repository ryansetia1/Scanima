class_name ChapterPush
extends Node

signal enabled_changed(enabled: bool)
signal chapter_message_received
signal failed

const TOPIC := "scanima-expedition-chapters"
const CORE_SINGLETON := "GodotxFirebaseCore"
const MESSAGING_SINGLETON := "GodotxFirebaseMessaging"

# ponytail: one FCM topic avoids a token registry and per-device fan-out. The
# ceiling is broadcast-only chapter news; add server device tokens if targeting
# or per-user notification preferences become necessary.
var _core: Object
var _messaging: Object
var _wants_enabled := false


static func available() -> bool:
	return (
		Engine.has_singleton(CORE_SINGLETON)
		and Engine.has_singleton(MESSAGING_SINGLETON)
	)


func configure(enabled: bool) -> void:
	if not available():
		return
	_wants_enabled = enabled
	_core = Engine.get_singleton(CORE_SINGLETON)
	_messaging = Engine.get_singleton(MESSAGING_SINGLETON)
	_core.core_initialized.connect(_on_core_initialized)
	_messaging.messaging_permission_granted.connect(_on_permission_granted)
	_messaging.messaging_permission_denied.connect(_on_permission_denied)
	_messaging.messaging_token_received.connect(_on_token_received)
	_messaging.messaging_message_received.connect(
		func(_title: String, _body: String) -> void: chapter_message_received.emit()
	)
	_messaging.messaging_error.connect(func(_message: String) -> void: failed.emit())
	_core.initialize()


func set_enabled(enabled: bool) -> void:
	if not available() or _messaging == null:
		enabled_changed.emit(false)
		return
	_wants_enabled = enabled
	if enabled:
		_messaging.request_permission()
	else:
		_messaging.unsubscribe_from_topic(TOPIC)
		enabled_changed.emit(false)


func _on_core_initialized(success: bool) -> void:
	if not success:
		failed.emit()
		return
	_messaging.initialize()
	if _wants_enabled:
		_messaging.request_permission()


func _on_permission_granted() -> void:
	_messaging.get_token()


func _on_permission_denied() -> void:
	_wants_enabled = false
	enabled_changed.emit(false)


func _on_token_received(_token: String) -> void:
	if not _wants_enabled:
		return
	_messaging.subscribe_to_topic(TOPIC)
	enabled_changed.emit(true)
