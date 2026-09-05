class_name SeekerRoster
extends RefCounted

## Seeker Roster: himpunan Seeker Avatar yang boleh dipilih pemain. Satu tempat
## untuk empat slug-nya, satu tempat untuk manifest yang dipakai keempatnya.
##
## Slug adalah teks yang menjelaskan dirinya, bukan indeks angka, mengikuti gaya
## katalog Shop yang menamai sheet-nya. Figur androgini adalah anggota roster
## yang **dipilih** dan sekaligus yang tergambar untuk pemain yang belum memilih
## — ia bukan fallback untuk jawaban Seeker Demographics, yang tidak pernah
## menentukan wujud (ADR-0001).
##
## ponytail: art keempat figur ikut ter-bundel ke build alih-alih disajikan dari
## Storage (ADR-0002), jadi tidak ada bucket, unggahan, jalur unduh, atau avatar
## yang hilang karena satu fetch gagal. Art final sudah masuk, dan harganya
## terukur, bukan lagi taksiran: dua `--export-pack Android` dengan dan tanpa
## `assets/seekers/` berselisih 2.022.776 byte, yaitu **1,93 MiB untuk empat
## figur** — di bawah taksiran ~3,2 MB ADR-0002, sekitar 0,48 MiB per figur.
## Plafonnya tetap sekitar enam figur (~2,9 MiB): di atas itu biaya APK melewati
## kerumitan yang dibelinya, jadi pindahkan pengiriman art ke pola
## `chapter_assets` yang sudah dipakai Boss Seeker.

const SHEET_DIR := "res://assets/seekers"
const DEFAULT_SLUG := "androgynous"
const SLUGS: PackedStringArray = [
	"androgynous",
	"masculine",
	"feminine",
	"automaton",
]
const BODY_HEIGHTS_CM := {
	"androgynous": 172.0,
	"masculine": 176.0,
	"feminine": 170.0,
	"automaton": 180.0,
}

## Keempat sheet digambar pada grid yang sama dengan Boss Seeker chapter: sel
## 341px pada sheet 1024px dengan jendela capture 300px. Angkanya sengaja sama
## supaya loader, presenter, dan helper potret yang sudah ada dipakai apa adanya.
const CELL := 341
const FRAME := 300


static func sheet_path(slug: String) -> String:
	return "%s/%s.png" % [SHEET_DIR, slug]


## Tinggi tubuh adalah identitas kosmetik figur, bukan ukuran piksel sheet atau
## data Seeker Demographics. Slug asing memakai figur default beserta tingginya.
static func body_height_cm(value: Variant) -> float:
	return float(BODY_HEIGHTS_CM[normalize(value)])


static func idle_motion_kind(value: Variant) -> String:
	return "mechanical" if normalize(value) == "automaton" else "organic"


## Sembilan pose-nya diturunkan dari SeekerSheet.KNOWN_POSES, bukan disalin, jadi
## kontrak nama pose tidak bisa bergeser hanya di satu sisi.
static func manifest() -> Dictionary:
	var poses: Dictionary = {}
	for index in SeekerSheet.KNOWN_POSES.size():
		poses[SeekerSheet.KNOWN_POSES[index]] = {
			"region": [(index % 3) * CELL, (index / 3) * CELL, FRAME, FRAME],
		}
	return {
		"version": SeekerSheet.MANIFEST_VERSION,
		"frame_size": [FRAME, FRAME],
		"poses": poses,
	}


static func load_sheet(slug: String) -> Dictionary:
	var path := sheet_path(slug)
	var texture: Texture2D = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
	var loaded := SeekerSheet.build(texture, manifest())
	if bool(loaded.get("ok", false)):
		loaded["body_height_cm"] = body_height_cm(slug)
		loaded["idle_motion_kind"] = idle_motion_kind(slug)
	return loaded


## `profiles.seeker_avatar` nullable, jadi nilainya datang sebagai Variant: `null`
## berarti belum memilih dan digambar sebagai figur default. Slug di luar roster
## diperlakukan sama, supaya build lama yang belum mengenal figur kelima tetap
## menggambar seseorang alih-alih slot kosong.
static func normalize(value: Variant) -> String:
	var slug := str(value) if typeof(value) == TYPE_STRING else ""
	return slug if SLUGS.has(slug) else DEFAULT_SLUG


## slug -> sheet terbangun, slug -> pose profil. Art roster sama untuk setiap
## akun, jadi kedua cache ini sengaja tidak ikut dibuang saat akun berganti.
static var _sheets: Dictionary = {}
static var _portraits: Dictionary = {}


## Sheet yang sudah ter-bundel — nol panggilan jaringan dan nol panggilan model.
## Di-cache karena `build()` men-decode sheet 1024px lalu memindai sembilan
## region, sementara pemanggilnya berulang: picker membuka seluruh roster
## sekaligus, potret Profile digambar setiap kunjungan, dan arena menyegarkan
## figurnya setiap kali profil berubah.
static func sheet(value: Variant) -> Dictionary:
	var slug := normalize(value)
	if not _sheets.has(slug):
		_sheets[slug] = load_sheet(slug)
	return _sheets[slug]


static func portrait(value: Variant) -> Texture2D:
	var slug := normalize(value)
	if not _portraits.has(slug):
		_portraits[slug] = SeekerSheet.portrait(sheet(slug))
	return _portraits[slug]
