class_name ClientVersion
extends RefCounted

## Versi build client. Naikkan saat client wajib diperbarui sebelum fitur baru live.
const APP_BUILD_VERSION := 1


static func platform_key() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("ios"):
		return "ios"
	return "desktop"


## Pure: true hanya bila min_client_version menyebut platform ini dan build kita di bawahnya.
## Config kosong, tidak terbaca, atau angka nol = permissive (tidak outdated).
static func is_outdated(min_client_version: Variant, build_version: int = APP_BUILD_VERSION) -> bool:
	if typeof(min_client_version) != TYPE_DICTIONARY:
		return false
	var mins: Dictionary = min_client_version
	var required := int(mins.get(platform_key(), 0))
	if required <= 0:
		return false
	return build_version < required
