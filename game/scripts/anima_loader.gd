class_name AnimaLoader
extends RefCounted

## Membangun SpriteFrames dari sheet PNG RGBA + manifest.json yang dihasilkan
## post-processing di backend (lihat backend/supabase/functions/_shared/postprocess.mjs).
##
## Tidak ada slicing 2x2 secara buta di sini. Godot mempercayai region dari
## manifest, karena yang tahu di mana kreaturnya sebenarnya berada adalah tahap
## yang punya akses piksel, bukan client. Client hanya memverifikasi bahwa
## region-nya masuk akal, lalu menolak kalau tidak.

const MANIFEST_VERSION := 1
const KNOWN_POSES: PackedStringArray = ["idle", "attack", "sleep", "defeated"]
const DEFAULT_POSE := "idle"


## Memuat dari path manifest.json. Sheet dicari dari field "sheet" di manifest,
## relatif terhadap folder manifest itu sendiri.
static func load_from_manifest(manifest_path: String) -> Dictionary:
	if not FileAccess.file_exists(manifest_path):
		return _fail("manifest tidak ada: %s" % manifest_path)

	var text := FileAccess.get_file_as_string(manifest_path)
	if text.is_empty():
		return _fail("manifest kosong atau tidak bisa dibaca: %s" % manifest_path)

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("manifest bukan JSON object: %s" % manifest_path)
	var manifest: Dictionary = parsed

	var dir := manifest_path.get_base_dir()
	var sheet_name := str(manifest.get("sheet", "")).strip_edges()
	if sheet_name.is_empty():
		sheet_name = "sheet.png"
	var sheet_path := dir.path_join(sheet_name)

	var texture := load_sheet_texture(sheet_path)
	if texture == null:
		return _fail("sheet gagal dimuat: %s" % sheet_path)

	return build(texture, manifest)


## Memuat PNG jadi tekstur. Dipisah karena sheet hidup di user:// setelah
## diunduh, dan file di user:// tidak lewat pipeline impor Godot, jadi load()
## biasa tidak bisa dipakai.
static func load_sheet_texture(sheet_path: String) -> Texture2D:
	var image := Image.new()
	if image.load(sheet_path) != OK:
		return null
	if image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Bagian murni: tekstur + manifest jadi SpriteFrames. Tanpa I/O, supaya bisa
## diuji dengan sheet yang dibuat di memori.
static func build(sheet: Texture2D, manifest: Dictionary) -> Dictionary:
	if sheet == null:
		return _fail("sheet null")

	var version := int(manifest.get("version", 0))
	if version != MANIFEST_VERSION:
		return _fail("versi manifest %d tidak didukung, butuh %d" % [version, MANIFEST_VERSION])

	var frame_size := _to_vector2i(manifest.get("frame_size"))
	if frame_size.x <= 0 or frame_size.y <= 0:
		return _fail("frame_size tidak sah: %s" % str(manifest.get("frame_size")))

	var poses_raw: Variant = manifest.get("poses")
	if typeof(poses_raw) != TYPE_DICTIONARY:
		return _fail("manifest tidak punya objek poses")
	var poses: Dictionary = poses_raw

	var sheet_size := sheet.get_size()
	var frames := SpriteFrames.new()
	# SpriteFrames selalu lahir dengan animasi "default" yang tidak kita pakai.
	frames.remove_animation("default")

	var loaded: PackedStringArray = []
	for pose in KNOWN_POSES:
		if not poses.has(pose):
			continue

		var entry: Variant = poses[pose]
		if typeof(entry) != TYPE_DICTIONARY:
			return _fail("pose %s bukan object" % pose)

		var region := _to_rect2i(entry.get("region"))
		if region.size.x <= 0 or region.size.y <= 0:
			return _fail("region pose %s tidak sah: %s" % [pose, str(entry.get("region"))])

		# Ukuran region WAJIB sama dengan frame_size untuk semua pose.
		# AnimatedSprite2D hanya punya satu offset untuk seluruh animasi, jadi
		# region yang ukurannya beda membuat sprite tersentak berpindah setiap
		# kali pose berganti, dan tidak ada cara memperbaikinya di sini.
		if region.size != frame_size:
			return _fail(
				"region pose %s berukuran %s, harus sama dengan frame_size %s"
				% [pose, str(region.size), str(frame_size)]
			)

		if region.position.x < 0 or region.position.y < 0 \
				or region.end.x > sheet_size.x or region.end.y > sheet_size.y:
			return _fail(
				"region pose %s keluar dari sheet %s: %s" % [pose, str(sheet_size), str(region)]
			)

		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(region)
		atlas.filter_clip = true

		frames.add_animation(pose)
		frames.set_animation_loop(pose, false)
		frames.add_frame(pose, atlas)
		loaded.append(pose)

	if loaded.is_empty():
		return _fail("tidak ada pose yang bisa dipakai")
	if not frames.has_animation(DEFAULT_POSE):
		return _fail("pose wajib '%s' tidak ada di manifest" % DEFAULT_POSE)

	return {
		"ok": true,
		"error": "",
		"frames": frames,
		"frame_size": frame_size,
		# Sprite di-render centered, sementara isi frame rata bawah. Menggeser
		# ke atas setengah frame membuat titik tumpu kreatur jatuh di origin
		# node, sehingga tween "bernapas" membesar dari kaki, bukan dari perut.
		"ground_offset": Vector2(0.0, -frame_size.y / 2.0),
		"poses": loaded,
		"species_key": str(manifest.get("species_key", "")),
		"stage": int(manifest.get("stage", 1)),
		"qa": manifest.get("qa", {}),
	}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "frames": null, "poses": PackedStringArray()}


static func _to_vector2i(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		var arr: Array = value
		return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO


static func _to_rect2i(value: Variant) -> Rect2i:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 4:
		var arr: Array = value
		return Rect2i(int(arr[0]), int(arr[1]), int(arr[2]), int(arr[3]))
	return Rect2i()
