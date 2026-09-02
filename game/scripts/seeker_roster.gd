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
## yang hilang karena satu fetch gagal. Plafonnya sekitar enam figur: sheet
## sembilan pose yang sudah dikeying ditaksir ~0,8 MB, jadi enam ~4,8 MB, dan di
## atas itu biaya APK melewati kerumitan yang dibelinya — pindahkan pengiriman
## art ke pola `chapter_assets` yang sudah dipakai Boss Seeker. Placeholder yang
## ada sekarang jauh lebih ringan (~12 KB per `.ctex`, 112 KB untuk keempatnya),
## jadi plafon itu baru benar-benar terasa setelah art final masuk.

const SHEET_DIR := "res://assets/seekers"
const DEFAULT_SLUG := "androgynous"
const SLUGS: PackedStringArray = [
	"androgynous",
	"masculine",
	"feminine",
	"automaton",
]

## Keempat sheet digambar pada grid yang sama dengan Boss Seeker chapter: sel
## 341px pada sheet 1024px dengan jendela capture 300px. Angkanya sengaja sama
## supaya loader, presenter, dan helper potret yang sudah ada dipakai apa adanya.
const CELL := 341
const FRAME := 300


static func sheet_path(slug: String) -> String:
	return "%s/%s.png" % [SHEET_DIR, slug]


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
	return SeekerSheet.build(texture, manifest())


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
