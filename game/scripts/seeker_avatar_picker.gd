class_name SeekerAvatarPicker
extends GridContainer

## Kartu figur Seeker Roster, satu per slug, dipakai dua layar: sheet ganti
## avatar di Seeker Profile dan baris picker di onboarding. Yang berbeda antara
## keduanya hanya jumlah kolom dan tinggi kartu, dan keduanya disetel di scene.
##
## Dibangun dari `SeekerRoster.SLUGS`, bukan dari baris scene, jadi figur kelima
## nanti tetap satu sheet dan satu slug (ADR-0002) tanpa menyentuh layar mana
## pun.

signal chosen(slug: String)

## Ruang antara tepi kartu dan art di dalamnya.
const ART_INSET := 12.0

@export var card_height: float = 240.0

var _slug := SeekerRoster.DEFAULT_SLUG
var _buttons: Array[Button] = []


## Kartu dibangun saat picker pertama kali diminta tampil, bukan di `_ready()`:
## membangunnya lebih awal men-decode empat sheet 1024px saat shell boot demi
## layar yang mungkin tidak pernah dibuka.
func build() -> void:
	if not _buttons.is_empty():
		return
	for slug in SeekerRoster.SLUGS:
		var button := Button.new()
		button.name = "SeekerAvatar%s" % slug.capitalize()
		button.custom_minimum_size = Vector2(0, card_height)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.tooltip_text = tr("SEEKER_AVATAR_PICK")
		button.set_meta("avatar", slug)
		var art := TextureRect.new()
		art.name = "Art"
		art.texture = SeekerRoster.portrait(slug)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(art)
		art.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, ART_INSET
		)
		button.pressed.connect(_choose.bind(slug))
		UiJuice.install_button(button)
		add_child(button)
		_buttons.append(button)
	_refresh()


## Menerima `Variant` karena `profiles.seeker_avatar` nullable: `null` berarti
## belum memilih dan menandai figur default, sehingga picker selalu punya satu
## kartu tertandai dan tidak pernah bisa memblokir layar yang memuatnya.
func set_slug(value: Variant) -> void:
	_slug = SeekerRoster.normalize(value)
	_refresh()


func slug() -> String:
	return _slug


## Dipakai onboarding, yang mengunci seluruh formulirnya selama satu submit
## terbang. Tanpa ini kartu figur adalah satu-satunya control yang tetap hidup,
## dan tap di situ akan tertandai di layar tanpa pernah ikut terkirim.
func set_disabled(disabled: bool) -> void:
	for button in _buttons:
		button.disabled = disabled


## Pola yang sama dengan chip Vibe: satu kartu tertandai, sisanya kembali ke
## style default. `set_pressed_no_signal` dipakai karena toggle yang ditulis
## ulang di sini bukan tap pemain.
func _refresh() -> void:
	for button in _buttons:
		var selected := str(button.get_meta("avatar", "")) == _slug
		button.set_pressed_no_signal(selected)
		button.theme_type_variation = &"VibeSelected" if selected else &""


## Tanda dipindahkan lebih dulu supaya toggle yang baru saja dibalik Godot tidak
## meninggalkan dua kartu tertandai selama pemanggil mengerjakan sisanya;
## `set_slug()` tetap yang menentukan tanda akhirnya, termasuk saat rollback.
func _choose(slug: String) -> void:
	set_slug(slug)
	chosen.emit(slug)
