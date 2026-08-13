class_name PlaceholderSheet
extends RefCounted

## Sheet bohongan yang dibuat di memori, bentuknya persis seperti keluaran
## backend: RGBA, region berukuran seragam, isi rata bawah.
##
## Ada dua alasan file ini ada. Pertama, demo bisa dijalankan sebelum satu sen
## pun dibelanjakan ke Replicate. Kedua, test slicing tidak perlu menyimpan PNG
## biner di repo, dan tetap menguji jalur kode yang sama dengan sheet sungguhan.

const FRAME := Vector2i(256, 256)
const PAD := 6
const GRID := 3

# Harus cocok dengan LAYOUT_3X3 di backend/supabase/functions/_shared/postprocess.mjs.
const QUADRANT := {
	"idle": Vector2i(0, 0),
	"attack": Vector2i(1, 0),
	"sleep": Vector2i(2, 0),
	"happy": Vector2i(0, 1),
	"hungry": Vector2i(1, 1),
	"dirty": Vector2i(2, 1),
	"defeated": Vector2i(0, 2),
	"fx_strike": Vector2i(1, 2),
	"fx_surge": Vector2i(2, 2),
}

# Tinggi berbeda-beda dengan sengaja: pose meringkuk memang lebih pendek, dan
# rata-bawah hanya terbukti benar kalau tingginya tidak seragam.
const BODY := {
	"idle": Vector2i(120, 200),
	"attack": Vector2i(150, 196),
	"sleep": Vector2i(170, 96),
	"happy": Vector2i(124, 198),
	"hungry": Vector2i(118, 188),
	"dirty": Vector2i(122, 192),
	"defeated": Vector2i(140, 120),
	"fx_strike": Vector2i(88, 64),
	"fx_surge": Vector2i(110, 90),
}

const BODY_COLOR := Color("6fa8dc")
const SHADE_COLOR := Color("4a7fb5")
const EYE_COLOR := Color("f5f7fa")
const PUPIL_COLOR := Color("1b2430")
const FX_STRIKE_COLOR := Color("ffc14a")
const FX_SURGE_COLOR := Color("5ce1ff")


static func build() -> Dictionary:
	var sheet_size := FRAME * GRID
	var image := Image.create_empty(sheet_size.x, sheet_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var poses := {}
	for pose in QUADRANT.keys():
		var cell: Vector2i = QUADRANT[pose] * FRAME
		var body: Vector2i = BODY[pose]
		var origin := cell + Vector2i((FRAME.x - body.x) / 2, FRAME.y - PAD - body.y)
		var fill := BODY_COLOR
		if pose.begins_with("fx_"):
			# Blob di tengah sel, bukan siluet kaki, supaya overlay terbaca
			# sebagai VFX di depan tubuh bukan tempelan warna yang sama.
			fill = FX_SURGE_COLOR if pose == "fx_surge" else FX_STRIKE_COLOR
			origin.y = cell.y + (FRAME.y - body.y) / 2

		image.fill_rect(Rect2i(origin, body), fill)
		# Sisi bawah lebih gelap supaya arah cahaya terbaca dan mata manusia
		# bisa melihat kalau sprite dipasang terbalik.
		image.fill_rect(Rect2i(origin + Vector2i(0, body.y - 18), Vector2i(body.x, 18)), SHADE_COLOR)

		var eye := Vector2i(maxi(10, body.x / 7), maxi(10, body.x / 7))
		var eye_y := origin.y + maxi(12, body.y / 6)
		if not pose.begins_with("fx_"):
			for side: int in [-1, 1]:
				var eye_x: int = origin.x + body.x / 2 + side * body.x / 4 - eye.x / 2
				image.fill_rect(Rect2i(Vector2i(eye_x, eye_y), eye), EYE_COLOR)
				# Pose tidur dan tumbang: mata tertutup, digambar sebagai garis.
				var pupil_h := 3 if pose in ["sleep", "defeated"] else eye.y / 2
				image.fill_rect(
					Rect2i(Vector2i(eye_x + 2, eye_y + eye.y / 2 - 1), Vector2i(eye.x - 4, pupil_h)),
					PUPIL_COLOR
				)

		poses[pose] = {"region": [cell.x, cell.y, FRAME.x, FRAME.y]}

	var manifest := {
		"version": AnimaLoader.MANIFEST_VERSION,
		"sheet": "placeholder.png",
		"sheet_size": [sheet_size.x, sheet_size.y],
		"frame_size": [FRAME.x, FRAME.y],
		"species_key": "placeholder_demo_box",
		"color_bucket": "cool_blue",
		"stage": 1,
		"prompt_version": "placeholder",
		"poses": poses,
		"qa": {"cells_detected": poses.size(), "warnings": ["sheet placeholder, bukan hasil model"]},
	}

	return {"image": image, "manifest": manifest}


## Menulis sheet placeholder ke folder sebagai PNG + manifest.json, supaya jalur
## baca-dari-disk juga bisa diuji, bukan hanya jalur in-memory.
static func write_to_dir(dir_path: String) -> String:
	var made := DirAccess.make_dir_recursive_absolute(dir_path)
	if made != OK and not DirAccess.dir_exists_absolute(dir_path):
		return ""

	var built := build()
	var image: Image = built["image"]
	var manifest: Dictionary = built["manifest"]

	if image.save_png(dir_path.path_join(str(manifest["sheet"]))) != OK:
		return ""

	var manifest_path := dir_path.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()

	return manifest_path
