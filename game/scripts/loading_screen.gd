class_name LoadingScreen
extends CanvasLayer

## Satu layar loading untuk seluruh perpindahan layar. Dipanggil statis dari mana
## saja, tanpa autoload keenam: node-nya menempel sendiri ke root scene tree
## seperti `UiClickPlayer` milik `UiJuice`, jadi urutan autoload di
## `project.godot` tidak ikut berubah.
##
##     LoadingScreen.show_screen("BATTLE_CONNECTING")
##     var res := await Backend.battle_anima("start", payload)
##     LoadingScreen.hide_screen()
##
## `scan_flow` dan `ExpeditionController` sudah memanggil `hide_screen()` dari
## `_set_busy(false)`, jadi transisi di dalam shell hanya perlu baris show-nya
## dan tidak ada jalur error yang bisa meninggalkan layarnya menempel. Syaratnya
## satu: `show_screen()` di dalam shell wajib duduk di dalam jendela
## `_set_busy(true)` milik operasinya. Memanggilnya dari setter atau helper
## bersama meninggalkan overlay pemblokir input pada pemanggil yang tidak busy.
##
## Boot adalah satu-satunya pemanggil `immediate`: ia dibuka di frame pertama,
## sebelum Home mengecat apa pun, dan ditutup oleh `_set_busy(false)` milik
## `_boot()` yang menyusul.
##
## Pesan memakai key katalog `locales/ui.csv`, bukan kalimat mentah.

const SCENE_PATH := "res://scenes/ui/loading_screen.tscn"
const NODE_NAME := "LoadingScreen"
const DEFAULT_MESSAGE := "STATUS_LOADING"

## Kerja yang selesai lebih cepat dari ini tidak pernah mengecat apa pun. Jalur
## local-first — cache boot, art yang sudah ada di disk — karena itu tidak
## membayar satu frame pun kedipan, dan layar ini hanya muncul untuk round trip
## yang memang membuat pemain menunggu. `immediate` melewatinya untuk transisi
## yang wajib tertutup sejak frame pertama.
const SHOW_DELAY_SEC := 0.12

## Layar yang sudah tercat menahan dirinya sampai sekian sebelum menutup. Boot
## hangat dari `user://boot_cache.json` bisa selesai dalam sekejap, dan tanpa
## lantai ini pemain melihat kedipan alih-alih layar loading. Jalur local-first
## tidak membayarnya: kerja yang selesai di bawah `SHOW_DELAY_SEC` tidak pernah
## tercat, dan `dismiss()` yang menemukannya belum tampil langsung keluar.
const MIN_PAINT_SEC := 0.45
const FADE_SEC := 0.18

## Satu lintasan dash penuh. 1,2 detik menempatkan `--screenshot` yang menunggu
## tiga detik tepat di tengah lintasan, jadi bukti visualnya deterministik.
const SWEEP_SEC := 1.2

static var _singleton: LoadingScreen

@onready var _screen: Control = %LoadingScreenRoot
@onready var _brand_title: Label = %BrandTitle
@onready var _message: Label = %LoadingMessage
@onready var _track: Control = %LoadingSweep
@onready var _spark: ColorRect = %LoadingSpark
@onready var _delay: Timer = %ShowDelay

var _fade: Tween
var _sweep: Tween
var _fading_out := false
var _message_key := DEFAULT_MESSAGE
var _painted_ms := 0
var _dismiss_queued := false


## Meminta layar loading dengan pesan tertentu. Aman dipanggil berulang: request
## kedua hanya mengganti pesannya, tidak merestart animasinya. `immediate`
## mengecatnya di frame yang sama alih-alih menunggu `SHOW_DELAY_SEC`.
static func show_screen(message_key: String = DEFAULT_MESSAGE, immediate := false) -> void:
	var screen := _instance()
	if screen != null:
		screen.request(message_key, immediate)


## Idempoten. Menutup layar yang belum sempat tercat berarti nol frame terlihat.
# ponytail: satu layar, dua flag busy — `scan_flow` dan `ExpeditionController`
# sama-sama menutupnya, jadi yang selesai lebih dulu melepas layar milik yang
# lain. Plafonnya interleaving langka (Retry roster Home persis saat hub
# Expedition masih terbang): layarnya terangkat lebih awal, tidak pernah
# tersangkut, dan view yang masih menunggu tetap diredupkan sendiri. Upgrade
# ke owner token di `request()`/`dismiss()` kalau pemilik ketiga muncul.
static func hide_screen() -> void:
	if is_instance_valid(_singleton):
		_singleton.dismiss()


static func is_showing() -> bool:
	return is_instance_valid(_singleton) and _singleton.is_painted()


static func _instance() -> LoadingScreen:
	if is_instance_valid(_singleton):
		return _singleton
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return null
	_singleton = packed.instantiate() as LoadingScreen
	_singleton.name = NODE_NAME
	loop.root.add_child(_singleton)
	return _singleton


func _ready() -> void:
	_screen.visible = false
	_screen.modulate.a = 0.0
	if _brand_title != null:
		_brand_title.text = tr("APP_NAME")
	_delay.timeout.connect(_paint)


func request(message_key: String, immediate := false) -> void:
	# Penutupan yang masih menunggu lantai minimum dibatalkan: transisi berikutnya
	# memakai layar yang sudah tampil alih-alih mengedipkannya dua kali.
	_dismiss_queued = false
	_message_key = message_key if not message_key.is_empty() else DEFAULT_MESSAGE
	_message.text = tr(_message_key)
	if _screen.visible:
		# Request baru saat fade-out masih jalan (dua transisi beruntun) memakai
		# layar yang sama alih-alih mengedipkannya.
		if _fading_out:
			_paint()
		return
	if immediate:
		_paint()
		return
	if _delay.is_stopped():
		_delay.start(SHOW_DELAY_SEC)


func dismiss() -> void:
	_delay.stop()
	if not _screen.visible or _fading_out:
		return
	var painted_sec := float(Time.get_ticks_msec() - _painted_ms) / 1000.0
	if painted_sec < MIN_PAINT_SEC:
		# Satu penutupan tertunda cukup: `_set_busy(false)` bisa dipanggil beberapa
		# kali di dalam jendela yang sama, dan masing-masing tidak perlu timer.
		if not _dismiss_queued:
			_dismiss_queued = true
			get_tree().create_timer(MIN_PAINT_SEC - painted_sec).timeout.connect(_flush_dismiss)
		return
	_fading_out = true
	_stop_sweep()
	# Input dilepas di frame yang sama dengan mulainya fade: layar di bawahnya
	# sudah authoritative, jadi menahan tap selama 0,18 detik lagi hanya latency.
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_fade()
	_fade = create_tween()
	_fade.tween_property(_screen, "modulate:a", 0.0, FADE_SEC) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fade.tween_callback(_settle_hidden)


func is_painted() -> bool:
	return _screen.visible and not _fading_out


func message_key() -> String:
	return _message_key


func _flush_dismiss() -> void:
	if _dismiss_queued:
		dismiss()


func _paint() -> void:
	_fading_out = false
	_dismiss_queued = false
	_delay.stop()
	_painted_ms = Time.get_ticks_msec()
	_screen.visible = true
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_kill_fade()
	_fade = create_tween()
	_fade.tween_property(_screen, "modulate:a", 1.0, FADE_SEC) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_start_sweep()


func _settle_hidden() -> void:
	_fading_out = false
	_screen.visible = false
	_screen.modulate.a = 0.0


## Titik masuk dan keluar dash. Keduanya berada **di luar** region terpotong,
## jadi wrap tween jatuh saat dash sudah tidak terlihat: yang dilihat pemain
## hanya prosesi maju yang tidak pernah patah.
func sweep_bounds() -> Vector2:
	return Vector2(-_spark.size.x, maxf(_track.size.x, _track.custom_minimum_size.x))


func sweep_x() -> float:
	return _spark.position.x


## Indikator indeterminate satu arah. Replicate maupun Postgres tidak memberi
## persentase yang bermakna, jadi tidak ada yang terisi: satu dash brand meluncur
## dengan laju tetap ke satu arah, keluar layar, lalu masuk lagi dari sisi yang
## sama. Bar yang maju lalu **mundur** — versi sebelumnya — terbaca sebagai
## progres yang hilang, dan pemain membacanya sebagai gagal atau mulai ulang.
## Panjang dash yang jauh lebih pendek dari lintasannya juga berarti tidak ada
## posisi di lintasan itu yang bisa dibaca sebagai persentase.
func _start_sweep() -> void:
	_stop_sweep()
	var bounds := sweep_bounds()
	_spark.position.x = bounds.x
	_sweep = create_tween().set_loops()
	_sweep.tween_property(_spark, "position:x", bounds.y, SWEEP_SEC) \
		.from(bounds.x).set_trans(Tween.TRANS_LINEAR)


func _stop_sweep() -> void:
	if _sweep != null and _sweep.is_valid():
		_sweep.kill()
	_sweep = null


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
