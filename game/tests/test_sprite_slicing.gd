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
	await _test_presenter()
	_test_boss_seeker_sheet()
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
	_check_eq(frames.get_animation_names().size(), 9, "harus ada 9 animasi")
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
	_check_eq(loaded["fx_motion"]["fx_strike"], "projectile", "motion Attack harus terbawa")
	_check_eq(loaded["fx_motion"]["fx_surge"], "bloom", "motion Special harus terbawa")


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
		_check_eq(frames.get_animation_names().size(), 9, "9 pose harus terbaca dari disk")
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
	out_of_bounds["poses"]["sleep"]["region"] = [800, 800, 256, 256]
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
	for pose in ["defeated", "sleep", "happy", "hungry", "dirty", "fx_strike", "fx_surge"]:
		partial["poses"].erase(pose)

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
	presenter.call("plant_on_anchor")
	var planted: Rect2 = presenter.call("opaque_local_rect")
	_check(
		planted.size.y > 0.0
		and absf(planted.end.y + presenter.position.y) < 1.0,
		"kaki opak duduk di origin, bukan dasar sel kotak"
	)
	var shadow_host := Node2D.new()
	root.add_child(shadow_host)
	var shadow := Sprite2D.new()
	shadow.centered = true
	shadow_host.add_child(shadow)
	presenter.sync_ground_shadow(shadow)
	var feet_global := presenter.to_global(Vector2(planted.get_center().x, planted.end.y))
	_check(
		shadow.position.distance_to(shadow_host.to_local(feet_global)) < 0.01,
		"titik opak terbawah Anima harus tepat di pusat vertikal shadow"
	)
	shadow_host.free()
	var body_center: Vector2 = presenter.body_center_global()
	var frame_center: Vector2 = presenter.to_global(presenter.offset)
	_check(
		body_center.y >= frame_center.y,
		"pusat tubuh harus di massa opak, bukan di tengah sel yang banyak padding"
	)
	_check_eq(presenter.current_pose(), AnimaLoader.DEFAULT_POSE, "pose awal harus idle")
	_check(presenter.centered, "sprite harus centered supaya offset bermakna")
	_check_eq(presenter.fx_motion("fx_surge"), "bloom", "presenter harus menyimpan motion manifest")
	_check_eq(presenter.fx_motion("tidak_ada"), "projectile", "sheet lama fallback ke projectile")

	for pose in ["attack", "sleep", "defeated", "happy", "hungry", "dirty", "idle"]:
		_check(presenter.set_pose(pose), "set_pose('%s') harus berhasil" % pose)
		_check_eq(presenter.animation, pose, "animation harus ikut berganti")
		_check_eq(presenter.current_pose(), pose, "current_pose harus ikut berganti")

	_check(not presenter.set_pose("tidak_ada"), "pose tak dikenal harus ditolak")
	_check_eq(presenter.current_pose(), "idle", "pose gagal tidak boleh mengubah state")

	presenter.set_pose("defeated")
	var damaged_motion := presenter.get("_motion") as Tween
	_check(
		damaged_motion != null and damaged_motion.get_loops_left() == -1,
		"pose Damaged harus heavy breathing sampai state berubah"
	)
	presenter.set_pose("idle")
	_check(
		not damaged_motion.is_valid() or not damaged_motion.is_running(),
		"keluar dari Damaged harus menghentikan heavy breathing lama"
	)

	presenter.care_feedback("play")
	_check_eq(presenter.current_pose(), "happy", "Play memakai pose Happy")
	var play_feedback := presenter.get("_feedback") as Tween
	_check(
		play_feedback != null and play_feedback.get_loops_left() == 6,
		"Play harus memulai beberapa bounce, bukan satu hop"
	)
	# apply() dengan data gagal tidak boleh merusak Anima yang sedang tampil.
	_check(not presenter.apply({"ok": false, "error": "uji"}), "apply data gagal harus mengembalikan false")
	_check(presenter.sprite_frames != null, "frames lama harus tetap terpasang")

	presenter.apply_care_state(true, false)
	_check_eq(presenter.current_pose(), "sleep", "state tidur harus memakai pose Sleep")
	presenter.apply_care_state(false, true)
	_check_eq(presenter.current_pose(), "defeated", "Dormant harus memakai pose Defeated")
	_check(presenter.modulate != Color.WHITE, "Dormant harus terlihat pucat")
	presenter.apply_care_state(false, false)
	_check_eq(presenter.current_pose(), "idle", "kebutuhan penuh harus Idle; Happy hanya event")
	_check_eq(presenter.modulate, Color.WHITE, "pulih dari Dormant harus menghapus tint")
	presenter.apply_care_state(false, false, {"hunger": 20.0, "energy": 80.0, "hygiene": 80.0})
	_check_eq(presenter.current_pose(), "hungry", "Hunger rendah harus memakai pose Hungry")
	presenter.apply_care_state(false, false, {"hunger": 80.0, "energy": 80.0, "hygiene": 20.0})
	_check_eq(presenter.current_pose(), "dirty", "Hygiene rendah harus memakai pose Dirty")
	presenter.celebrate_level_up()
	_check_eq(presenter.current_pose(), "happy", "naik level memakai pose Happy")

	presenter.victory_celebration()
	_check_eq(presenter.current_pose(), "happy", "menang Battle memakai pose Happy")
	var victory := presenter.get("_feedback") as Tween
	_check(
		victory != null and victory.get_loops_left() == -1,
		"kemenangan harus melompat terus, bukan sekali seperti naik level"
	)
	presenter.set_pose("idle")
	_check(
		not victory.is_valid() or not victory.is_running(),
		"pose berikutnya harus melepas loop kemenangan, bukan ikut terpantul"
	)
	_check_eq(
		presenter.position,
		presenter.get("_base_position"),
		"loop kemenangan yang dilepas harus mengembalikan kaki ke anchor"
	)

	# Hop tanpa akhir hanya cocok untuk badan Hatchling. Adult dan Evolved
	# mendapat flourish membumi yang selesai sendiri.
	presenter.victory_celebration(CareRules.ADULT_LEVEL)
	_check_eq(presenter.current_pose(), "happy", "Adult tetap memakai pose Happy saat menang")
	var flourish := presenter.get("_feedback") as Tween
	_check(
		flourish != null and flourish.get_loops_left() == AnimaPresenter.VICTORY_FLOURISH_COUNT,
		"Adult harus mendapat flourish yang selesai sendiri, bukan lompatan tanpa akhir"
	)
	_check(
		not bool(presenter.get("_victory_loop")),
		"flourish yang selesai sendiri tidak butuh kill guard loop kemenangan"
	)
	presenter.victory_celebration(CareRules.EVOLVED_LEVEL)
	_check(
		(presenter.get("_feedback") as Tween).get_loops_left()
			== AnimaPresenter.VICTORY_FLOURISH_COUNT,
		"Evolved memakai flourish yang sama dengan Adult"
	)
	presenter.victory_celebration(CareRules.ADULT_LEVEL - 1)
	_check(
		(presenter.get("_feedback") as Tween).get_loops_left() == -1,
		"Level tepat di bawah Adult masih melompat terus"
	)
	presenter.set_pose("idle")

	presenter.guard_shimmer()
	var shimmer := presenter.material as ShaderMaterial
	_check(
		shimmer != null and shimmer.shader == AnimaPresenter.GUARD_SHIMMER_SHADER,
		"Guard harus memasang shader kilau di badan Anima"
	)
	_check_eq(
		float(shimmer.get_shader_parameter("progress")),
		0.0,
		"sapuan Guard harus mulai dari nol supaya tween yang memiliki waktunya"
	)
	presenter.call("_clear_shimmer")
	_check(presenter.material == null, "kilau Guard harus melepas materialnya sendiri")

	presenter.set_facing(1.0)
	presenter.hit_react()
	_check(presenter.get("_feedback") != null, "hit_react starts a shake tween")
	presenter.set_pose("dirty")
	presenter.play_fx("fx_strike")
	var fx := presenter.get("_fx") as Sprite2D
	_check(fx != null and fx.visible, "fx_strike harus menampilkan overlay efek")
	_check(fx.offset == Vector2.ZERO, "VFX harus terpusat di titik impact, bukan ground offset Anima")
	_check(
		fx.get_parent() == root and fx.get_parent() != presenter,
		"overlay FX harus sibling supaya lunge Attack tidak menelan VFX"
	)
	_check(
		fx.texture != presenter.sprite_frames.get_frame_texture("attack", 0),
		"VFX harus memakai sel fx_strike, bukan pose Attack"
	)
	var strike_tex := fx.texture
	presenter.play_fx("fx_surge")
	_check(
		fx.visible and fx.texture != strike_tex,
		"fx_surge harus overlay sel efek yang berbeda dari strike"
	)
	var impact := presenter.global_position + Vector2(90.0, -20.0)
	var start_pos := fx.position
	presenter.play_fx("fx_strike", impact)
	_check(
		fx.position.distance_to(start_pos) < 48.0,
		"FX travel mulai di dekat penyerang, bukan langsung di tubuh lawan"
	)
	await create_timer(AnimaPresenter.FX_TRAVEL_SEC + 0.04).timeout
	var local_impact := impact
	if fx.get_parent() is CanvasItem:
		local_impact = (fx.get_parent() as CanvasItem).to_local(impact)
	_check(
		fx.position.distance_to(local_impact) < 16.0,
		"FX strike/surge harus masuk ke tubuh lawan"
	)
	presenter.set("_fx_motion", {"fx_strike": "sweep"})
	presenter.play_fx("fx_strike", impact)
	_check(
		fx.position.distance_to(local_impact) < 80.0 and absf(fx.rotation) > 0.01,
		"motion sweep harus muncul di sekitar target dengan rotasi sapuan"
	)
	presenter.set("_fx_motion", {"fx_strike": "impact"})
	presenter.play_fx("fx_strike", impact)
	_check(
		fx.position.distance_to(local_impact) < 1.0 and fx.scale.x < 0.6,
		"motion impact harus pop langsung di tubuh target"
	)
	presenter.set("_fx_motion", {"fx_strike": "bloom"})
	presenter.play_fx("fx_strike", impact)
	_check(
		fx.position.distance_to(local_impact) < 1.0 and fx.scale.x < 0.5,
		"motion bloom harus tumbuh radial dari tubuh target"
	)

	presenter.visible = false
	await presenter.hatch_reveal()
	_check(presenter.visible, "hatch reveal harus menampilkan Anima")
	_check(presenter.scale.is_equal_approx(Vector2.ONE), "hatch reveal harus kembali ke skala pose")
	_check_eq(presenter.current_pose(), "dirty", "hatch reveal tidak boleh mengganti pose")
	await presenter.summon_dissolve()
	_check(not presenter.visible, "summon dissolve harus menyembunyikan companion lama")
	await presenter.summon_reveal()
	_check(presenter.visible, "summon reveal harus menampilkan companion pilihan")
	_check(
		presenter.scale.is_equal_approx(Vector2.ONE),
		"summon transition harus mengembalikan transform pose"
	)

	var haze := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	haze.fill(Color(0, 1, 0, 0.04))
	haze.fill_rect(Rect2i(20, 12, 16, 28), Color(0.2, 0.8, 0.3, 1))
	var haze_frames := SpriteFrames.new()
	haze_frames.add_animation("idle")
	haze_frames.add_frame("idle", ImageTexture.create_from_image(haze))
	presenter.sprite_frames = haze_frames
	presenter.set("_opaque_local_by_pose", {})
	presenter.set("_current_pose", "idle")
	presenter.animation = "idle"
	var tight: Rect2 = presenter.call("opaque_local_rect")
	_check(
		tight.size.x >= 15.0
		and tight.size.x <= 18.0
		and tight.size.y >= 27.0
		and tight.size.y <= 30.0,
		"haze sel kotak tidak dihitung sebagai tubuh opak"
	)
	presenter.free()


func _test_boss_seeker_sheet() -> void:
	print("8. Boss Seeker sheet memakai pose command, bukan pose Anima")
	var image := Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 1, 0, 0))
	var names := [
		"intro_idle", "attack_command", "special_command",
		"switch_command", "concern_hit", "last_anima",
		"victory", "defeat", "profile",
	]
	var poses := {}
	for index in names.size():
		var col := index % 3
		var row := index / 3
		var x := col * 341
		var y := row * 341
		var opaque_bottom := 260 if names[index] == "victory" else 300
		image.fill_rect(
			Rect2i(x + 70, y + 20, 160, opaque_bottom - 20),
			Color(0.2, 0.3, 0.8, 1)
		)
		poses[names[index]] = {"region": [x, y, 300, 300]}
	var loaded := SeekerSheet.build(
		ImageTexture.create_from_image(image),
		{"version": 1, "frame_size": [300, 300], "poses": poses}
	)
	_check(bool(loaded.get("ok", false)), "sheet seeker harus dibangun: %s" % loaded.get("error", ""))
	var frames: SpriteFrames = loaded.get("frames")
	_check(frames != null and frames.has_animation("intro_idle"), "seeker wajib punya intro_idle")
	_check(frames.has_animation("profile") and not frames.has_animation("idle"), "seeker tidak memakai pose Anima")
	_check(SeekerSheet.portrait(loaded, "profile") != null, "portrait seeker turun dari sheet yang sama")
	var pose_offsets: Dictionary = loaded.get("pose_ground_offsets", {})
	_check_eq(
		pose_offsets.get("intro_idle"),
		Vector2(0.0, 341.0 * 0.5 - 300.0),
		"intro Seeker menaruh kaki opak di anchor"
	)
	_check_eq(
		pose_offsets.get("victory"),
		Vector2(0.0, 341.0 * 0.5 - 260.0),
		"pose victory yang lebih pendek turun sampai kaki menyentuh anchor"
	)
	var seeker := SeekerPresenter.new()
	root.add_child(seeker)
	seeker.apply(loaded)
	seeker.set_pose("victory")
	_check_eq(
		seeker.offset,
		pose_offsets.get("victory"),
		"presenter memakai baseline victory, bukan baseline intro_idle"
	)
	seeker.set_pose("intro_idle")
	_check_eq(
		seeker.offset,
		pose_offsets.get("intro_idle"),
		"presenter mengembalikan baseline pose saat kembali Idle"
	)
	seeker.free()
	_check(
		not bool(SeekerSheet.build(ImageTexture.create_from_image(image), {
			"version": 1,
			"frame_size": [300, 300],
			"poses": {"profile": {"region": [682, 682, 300, 300]}},
		}).get("ok", false)),
		"sheet seeker tanpa intro_idle harus ditolak"
	)


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
		print("9. sheet nyata: dilewati (tidak ada --manifest=)")
		return

	print("9. sheet nyata dari pipeline Node: %s" % manifest_path)
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
