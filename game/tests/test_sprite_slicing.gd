extends SceneTree

## Test slicing sprite, dijalankan tanpa jendela:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##       --script res://tests/test_sprite_slicing.gd
##
## Tidak ada PNG fixture di repo. Sheet dibuat di memori oleh PlaceholderSheet,
## bentuknya identik dengan keluaran backend, jadi test ini melewati jalur kode
## yang sama dengan sheet sungguhan tanpa menyimpan biner.

var _failures: PackedStringArray = []
var _checks := 0


func _initialize() -> void:
	_test_build_from_memory()
	_test_atlas_regions()
	_test_ground_offset()
	_test_load_from_disk()
	_test_rejects_bad_manifest()
	_test_partial_poses()
	_test_presenter()
	_test_real_sheet_if_given()

	print("")
	if _failures.is_empty():
		print("test_sprite_slicing: OK (%d check)" % _checks)
		quit(0)
	else:
		printerr("test_sprite_slicing: GAGAL %d dari %d check" % [_failures.size(), _checks])
		for f in _failures:
			printerr("  - %s" % f)
		quit(1)


# ---------------------------------------------------------------- helper

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s (dapat %s, harus %s)" % [message, str(actual), str(expected)])


func _built() -> Dictionary:
	var built := PlaceholderSheet.build()
	var texture := ImageTexture.create_from_image(built["image"])
	return {"texture": texture, "manifest": built["manifest"]}


# ---------------------------------------------------------------- test

func _test_build_from_memory() -> void:
	print("1. build dari sheet in-memory")
	var src := _built()
	var loaded: Dictionary = AnimaLoader.build(src["texture"], src["manifest"])

	_check(loaded.get("ok", false), "build harus berhasil: %s" % loaded.get("error", ""))
	if not loaded.get("ok", false):
		return

	var frames: SpriteFrames = loaded["frames"]
	_check_eq(frames.get_animation_names().size(), 4, "harus ada 4 animasi")
	for pose in AnimaLoader.KNOWN_POSES:
		_check(frames.has_animation(pose), "animasi '%s' harus ada" % pose)
		_check_eq(frames.get_frame_count(pose), 1, "pose '%s' harus 1 frame" % pose)

	# Animasi "default" bawaan SpriteFrames tidak boleh tertinggal, kalau tidak
	# AnimatedSprite2D bisa memutar frame kosong saat pertama kali muncul.
	_check(not frames.has_animation("default"), "animasi 'default' harus dibuang")

	# Pose statis: looping tidak ada gunanya dan hanya membuang siklus.
	for pose in AnimaLoader.KNOWN_POSES:
		if frames.has_animation(pose):
			_check(not frames.get_animation_loop(pose), "pose '%s' tidak boleh loop" % pose)

	_check_eq(loaded["frame_size"], PlaceholderSheet.FRAME, "frame_size harus dari manifest")
	_check_eq(loaded["species_key"], "placeholder_demo_box", "species_key harus terbawa")


func _test_atlas_regions() -> void:
	print("2. AtlasTexture menunjuk region yang benar dan seragam")
	var src := _built()
	var manifest: Dictionary = src["manifest"]
	var loaded: Dictionary = AnimaLoader.build(src["texture"], manifest)
	if not loaded.get("ok", false):
		_check(false, "build gagal, region tidak bisa diperiksa")
		return

	var frames: SpriteFrames = loaded["frames"]
	var sizes: Array = []

	for pose in AnimaLoader.KNOWN_POSES:
		var texture: Texture2D = frames.get_frame_texture(pose, 0)
		_check(texture is AtlasTexture, "pose '%s' harus AtlasTexture, bukan tekstur penuh" % pose)
		if not texture is AtlasTexture:
			continue

		var atlas: AtlasTexture = texture
		var expected: Array = manifest["poses"][pose]["region"]
		_check_eq(
			atlas.region,
			Rect2(expected[0], expected[1], expected[2], expected[3]),
			"region pose '%s'" % pose
		)
		# Semua AtlasTexture berbagi satu tekstur sumber. Kalau tidak, tiap pose
		# jadi tekstur terpisah di VRAM dan 4 Anima di layar berarti 16 tekstur.
		_check(atlas.atlas == src["texture"], "pose '%s' harus berbagi atlas yang sama" % pose)
		sizes.append(atlas.get_size())

	for s in sizes:
		_check_eq(s, sizes[0], "ukuran frame antar pose harus identik")


func _test_ground_offset() -> void:
	print("3. ground_offset menaruh titik tumpu di origin node")
	var src := _built()
	var loaded: Dictionary = AnimaLoader.build(src["texture"], src["manifest"])
	if not loaded.get("ok", false):
		return

	# Isi frame rata bawah, sprite di-render centered. Menggeser ke atas setengah
	# frame membuat kaki jatuh di origin, sehingga tween napas membesar dari
	# bawah dan bukan dari perut.
	_check_eq(
		loaded["ground_offset"],
		Vector2(0.0, -PlaceholderSheet.FRAME.y / 2.0),
		"ground_offset harus setengah tinggi frame ke atas"
	)


func _test_load_from_disk() -> void:
	print("4. load_from_manifest membaca PNG + JSON dari disk")
	var dir := "user://test_animas/slicing"
	var manifest_path := PlaceholderSheet.write_to_dir(dir)
	_check(not manifest_path.is_empty(), "penulisan sheet uji harus berhasil")
	if manifest_path.is_empty():
		return

	var loaded: Dictionary = AnimaLoader.load_from_manifest(manifest_path)
	_check(loaded.get("ok", false), "muat dari disk harus berhasil: %s" % loaded.get("error", ""))
	if loaded.get("ok", false):
		var frames: SpriteFrames = loaded["frames"]
		_check_eq(frames.get_animation_names().size(), 4, "4 pose harus terbaca dari disk")
		_check_eq(loaded["frame_size"], PlaceholderSheet.FRAME, "frame_size dari disk")

	# Manifest hilang harus ditolak dengan pesan, bukan crash.
	var missing: Dictionary = AnimaLoader.load_from_manifest("user://test_animas/tidak_ada.json")
	_check(not missing.get("ok", true), "manifest yang tidak ada harus ditolak")
	_check(str(missing.get("error", "")).contains("tidak ada"), "pesan error harus menyebut penyebabnya")


func _test_rejects_bad_manifest() -> void:
	print("5. manifest cacat ditolak, bukan menghasilkan sprite rusak")
	var src := _built()
	var texture: Texture2D = src["texture"]

	var wrong_version: Dictionary = (src["manifest"] as Dictionary).duplicate(true)
	wrong_version["version"] = 99
	_check(
		not AnimaLoader.build(texture, wrong_version).get("ok", true),
		"versi manifest tak dikenal harus ditolak"
	)

	# Invarian paling penting: region yang ukurannya beda dari frame_size membuat
	# sprite tersentak berpindah tiap ganti pose, dan itu tidak bisa diperbaiki
	# di sisi client. Harus gagal keras di sini.
	var uneven: Dictionary = (src["manifest"] as Dictionary).duplicate(true)
	uneven["poses"]["attack"]["region"] = [256, 0, 200, 256]
	var uneven_result: Dictionary = AnimaLoader.build(texture, uneven)
	_check(not uneven_result.get("ok", true), "region berukuran beda harus ditolak")
	_check(
		str(uneven_result.get("error", "")).contains("frame_size"),
		"pesan error harus menjelaskan soal frame_size"
	)

	var out_of_bounds: Dictionary = (src["manifest"] as Dictionary).duplicate(true)
	out_of_bounds["poses"]["sleep"]["region"] = [400, 400, 256, 256]
	_check(
		not AnimaLoader.build(texture, out_of_bounds).get("ok", true),
		"region di luar sheet harus ditolak"
	)

	var no_idle: Dictionary = (src["manifest"] as Dictionary).duplicate(true)
	no_idle["poses"].erase("idle")
	_check(not AnimaLoader.build(texture, no_idle).get("ok", true), "tanpa pose idle harus ditolak")

	var no_poses: Dictionary = (src["manifest"] as Dictionary).duplicate(true)
	no_poses.erase("poses")
	_check(not AnimaLoader.build(texture, no_poses).get("ok", true), "tanpa objek poses harus ditolak")

	var bad_frame: Dictionary = (src["manifest"] as Dictionary).duplicate(true)
	bad_frame["frame_size"] = [0, 0]
	_check(not AnimaLoader.build(texture, bad_frame).get("ok", true), "frame_size 0 harus ditolak")

	_check(not AnimaLoader.build(null, src["manifest"]).get("ok", true), "sheet null harus ditolak")


func _test_partial_poses() -> void:
	print("6. sheet dengan sebagian pose tetap bisa dipakai")
	var src := _built()
	# Backend bisa menolak satu kuadran yang gagal keying. Kehilangan pose
	# Defeated tidak boleh membuat Anima tidak bisa ditampilkan sama sekali.
	var partial: Dictionary = (src["manifest"] as Dictionary).duplicate(true)
	partial["poses"].erase("defeated")
	partial["poses"].erase("sleep")

	var loaded: Dictionary = AnimaLoader.build(src["texture"], partial)
	_check(loaded.get("ok", false), "sheet sebagian harus tetap dimuat: %s" % loaded.get("error", ""))
	if loaded.get("ok", false):
		_check_eq(loaded["poses"].size(), 2, "hanya pose yang ada yang dimuat")
		var frames: SpriteFrames = loaded["frames"]
		_check(frames.has_animation("idle"), "idle harus ada")
		_check(not frames.has_animation("defeated"), "pose hilang tidak boleh dikarang")


func _test_presenter() -> void:
	print("7. presenter memasang frames dan berganti pose")
	var src := _built()
	var loaded: Dictionary = AnimaLoader.build(src["texture"], src["manifest"])
	if not loaded.get("ok", false):
		_check(false, "build gagal, presenter tidak bisa diuji")
		return

	var presenter := AnimatedSprite2D.new()
	presenter.set_script(load("res://scripts/anima_presenter.gd"))
	root.add_child(presenter)

	_check(presenter.apply(loaded), "apply harus berhasil")
	_check_eq(presenter.offset, loaded["ground_offset"], "offset harus dari ground_offset")
	_check_eq(presenter.current_pose(), AnimaLoader.DEFAULT_POSE, "pose awal harus idle")
	_check(presenter.centered, "sprite harus centered supaya offset bermakna")

	for pose in ["attack", "sleep", "defeated", "idle"]:
		_check(presenter.set_pose(pose), "set_pose('%s') harus berhasil" % pose)
		_check_eq(presenter.animation, pose, "animation harus ikut berganti")
		_check_eq(presenter.current_pose(), pose, "current_pose harus ikut berganti")

	_check(not presenter.set_pose("tidak_ada"), "pose tak dikenal harus ditolak")
	_check_eq(presenter.current_pose(), "idle", "pose gagal tidak boleh mengubah state")

	# apply() dengan data gagal tidak boleh merusak Anima yang sedang tampil.
	_check(not presenter.apply({"ok": false, "error": "uji"}), "apply data gagal harus mengembalikan false")
	_check(presenter.sprite_frames != null, "frames lama harus tetap terpasang")

	presenter.free()


## Memeriksa sheet sungguhan yang dihasilkan pipeline Node, kalau path-nya
## diberikan. Ini satu-satunya test yang membuktikan kontrak antara
## backend/supabase/functions/_shared/postprocess.mjs dan AnimaLoader benar-benar cocok, bukan hanya cocok
## dengan sheet yang dibuat Godot sendiri.
##
##   node eval/selftest.mjs --emit /tmp/scanima_e2e
##   godot --headless --path game --script res://tests/test_sprite_slicing.gd \
##       -- --manifest=/tmp/scanima_e2e/manifest.json
func _test_real_sheet_if_given() -> void:
	var manifest_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):
			manifest_path = arg.trim_prefix("--manifest=")

	if manifest_path.is_empty():
		print("8. sheet nyata: dilewati (tidak ada --manifest=)")
		return

	print("8. sheet nyata dari pipeline Node: %s" % manifest_path)
	var loaded: Dictionary = AnimaLoader.load_from_manifest(manifest_path)
	_check(loaded.get("ok", false), "sheet pipeline harus dimuat: %s" % loaded.get("error", ""))
	if not loaded.get("ok", false):
		return

	var frames: SpriteFrames = loaded["frames"]
	_check(frames.has_animation("idle"), "sheet pipeline harus punya pose idle")
	print("   spesies %s, frame %s, pose %s" % [
		loaded["species_key"], str(loaded["frame_size"]), ", ".join(loaded["poses"])
	])

	var qa: Dictionary = loaded.get("qa", {})
	if qa.has("green_residue_ratio"):
		var residue := float(qa["green_residue_ratio"])
		_check(residue < 0.01, "residu hijau %.4f terlalu tinggi untuk dipakai" % residue)
