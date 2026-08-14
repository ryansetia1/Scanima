extends Node

## Penyimpanan satu blob sesi. Di Android/iOS nilainya dienkripsi native oleh
## OAuth2Plugin (Android Keystore / iOS Keychain), bukan ditulis ke state.json.

const SESSION_KEY := "scanima:session"
const BACKUP_KEY := "scanima:session_backup"

## Hanya untuk editor/headless dan build desktop yang bukan target rilis mobile.
# ponytail: fallback plaintext menjaga alat dev tetap hidup. Plafonnya desktop
# internal; ganti dengan keyring desktop jika Scanima kelak dirilis di desktop.
var fallback_path: String = "user://secure_session.dev.json"

var _native: Object


func _ready() -> void:
	if Engine.has_singleton("OAuth2Plugin"):
		_native = Engine.get_singleton("OAuth2Plugin")


func has_native_store() -> bool:
	return _native != null


func load_session() -> Dictionary:
	return _decode(_read(SESSION_KEY))


func save_session(value: Dictionary) -> bool:
	return _write(SESSION_KEY, JSON.stringify(value))


func clear_session() -> void:
	_delete(SESSION_KEY)


func backup_session(value: Dictionary) -> bool:
	return _write(BACKUP_KEY, JSON.stringify(value))


func load_backup() -> Dictionary:
	return _decode(_read(BACKUP_KEY))


func clear_backup() -> void:
	_delete(BACKUP_KEY)


func _read(key: String) -> String:
	if _native != null:
		return str(_native.get_token(key))
	if OS.has_feature("android") or OS.has_feature("ios"):
		return ""
	var data := _load_fallback()
	return str(data.get(key, ""))


func _write(key: String, value: String) -> bool:
	if _native != null:
		_native.save_token(key, value)
		return true
	if OS.has_feature("android") or OS.has_feature("ios"):
		return false
	var data := _load_fallback()
	data[key] = value
	return _save_fallback(data)


func _delete(key: String) -> void:
	if _native != null:
		_native.delete_token(key)
		return
	if OS.has_feature("android") or OS.has_feature("ios"):
		return
	var data := _load_fallback()
	data.erase(key)
	_save_fallback(data)


func _decode(value: String) -> Dictionary:
	if value.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(value)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_fallback() -> Dictionary:
	if not FileAccess.file_exists(fallback_path):
		return {}
	return _decode(FileAccess.get_file_as_string(fallback_path))


func _save_fallback(data: Dictionary) -> bool:
	var tmp := fallback_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(tmp, fallback_path) == OK
