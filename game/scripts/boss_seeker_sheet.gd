class_name BossSeekerSheet
extends RefCounted

## SpriteFrames for a chapter Boss Seeker 3×3 sheet. Pose names are not Anima
## poses, so this stays separate from AnimaLoader.

const MANIFEST_VERSION := 1
const DEFAULT_POSE := "intro_idle"
const KNOWN_POSES: PackedStringArray = [
	"intro_idle",
	"attack_command",
	"special_command",
	"switch_command",
	"concern_hit",
	"last_anima",
	"victory",
	"defeat",
	"profile",
]


static func build(sheet: Texture2D, manifest: Dictionary) -> Dictionary:
	if sheet == null:
		return _fail("sheet null")
	if int(manifest.get("version", 0)) != MANIFEST_VERSION:
		return _fail("versi manifest seeker tidak didukung")
	var frame_size := _to_vector2i(manifest.get("frame_size"))
	if frame_size.x <= 0 or frame_size.y <= 0:
		return _fail("frame_size seeker tidak sah")
	var poses_raw: Variant = manifest.get("poses")
	if typeof(poses_raw) != TYPE_DICTIONARY:
		return _fail("manifest seeker tidak punya objek poses")
	var poses: Dictionary = poses_raw
	var sheet_size := sheet.get_size()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var loaded: PackedStringArray = []
	var display_size := frame_size
	var idle_region := Rect2i()
	for pose in KNOWN_POSES:
		if not poses.has(pose):
			continue
		var entry: Variant = poses[pose]
		if typeof(entry) != TYPE_DICTIONARY:
			return _fail("pose seeker %s bukan object" % pose)
		var region := _to_rect2i(entry.get("region"))
		if region.size != frame_size:
			return _fail("region seeker %s harus sama dengan frame_size" % pose)
		region = _full_grid_cell(region, sheet_size, frame_size)
		display_size = region.size
		if (
			region.position.x < 0
			or region.position.y < 0
			or region.end.x > int(sheet_size.x)
			or region.end.y > int(sheet_size.y)
		):
			return _fail("region seeker %s keluar dari sheet" % pose)
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(region)
		atlas.filter_clip = true
		frames.add_animation(pose)
		frames.set_animation_loop(pose, false)
		frames.add_frame(pose, atlas)
		loaded.append(pose)
		if pose == DEFAULT_POSE:
			idle_region = region
	if not frames.has_animation(DEFAULT_POSE):
		return _fail("pose wajib intro_idle tidak ada")
	var metrics_value: Variant = manifest.get("render_metrics", {})
	var metrics: Dictionary = metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	var used := _opaque_bounds(sheet, idle_region)
	if used.size.x > 0 and used.size.y > 0:
		metrics = {
			"reference_width_px": used.size.x,
			"reference_height_px": used.size.y,
			"reference_min_x_px": used.position.x,
		}
	var display_h := float(display_size.y)
	var opaque_bottom := (
		float(used.position.y + used.size.y) if used.size.y > 0 else display_h
	)
	return {
		"ok": true,
		"error": "",
		"frames": frames,
		"frame_size": display_size,
		"ground_offset": Vector2(0.0, display_h * 0.5 - opaque_bottom),
		"poses": loaded,
		"render_metrics": metrics,
	}


static func portrait(loaded: Dictionary, pose: String = "profile") -> Texture2D:
	var frames: Variant = loaded.get("frames")
	if not frames is SpriteFrames:
		return null
	var sheet := frames as SpriteFrames
	if sheet.has_animation(pose):
		return sheet.get_frame_texture(pose, 0)
	if sheet.has_animation("profile"):
		return sheet.get_frame_texture("profile", 0)
	if sheet.has_animation(DEFAULT_POSE):
		return sheet.get_frame_texture(DEFAULT_POSE, 0)
	return null


## 300px captures on a 1024 sheet drop the bottom 41px of each cell. Standing
## Seekers are taller than 300px, so that window cuts their feet. The PNG still
## has the full cell; open it at runtime.
static func _full_grid_cell(region: Rect2i, sheet_size: Vector2, frame_size: Vector2i) -> Rect2i:
	if int(sheet_size.x) != 1024 or int(sheet_size.y) != 1024 or frame_size != Vector2i(300, 300):
		return region
	var cell := 341
	var col := region.position.x / cell
	var row := region.position.y / cell
	var width := mini(cell, int(sheet_size.x) - col * cell)
	var height := mini(cell, int(sheet_size.y) - row * cell)
	return Rect2i(col * cell, row * cell, width, height)


static func _opaque_bounds(sheet: Texture2D, region: Rect2i) -> Rect2i:
	if region.size.x <= 0 or region.size.y <= 0:
		return Rect2i()
	var image := sheet.get_image()
	if image == null or image.is_empty():
		return Rect2i()
	return image.get_region(region).get_used_rect()


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
