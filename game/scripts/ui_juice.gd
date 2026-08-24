class_name UiJuice
extends RefCounted

## Shared micro-interactions for every screen. Controls keep their own tween in
## metadata, so rapid taps replace the previous motion instead of stacking scale
## writers and leaving a button permanently squashed.

const META_INSTALLED := &"_scanima_juice_installed"
const META_TWEEN := &"_scanima_juice_tween"
const META_METER_TWEEN := &"_scanima_meter_tween"
const META_SHEET_POSITION := &"_scanima_sheet_position"
const META_LIST_SCROLL := &"_scanima_list_scroll"
## `BottomSheetPanel` carries 2 px borders on its left and right, so a
## full-bleed sheet draws them in the outermost column of pixels -- where a
## phone with curved display edges simply eats them, and the sheet reads as
## cut off rather than bordered. The stylebox has no bottom border and square
## bottom corners, so it stays flush at the bottom on purpose; only the sides
## are inset.
const SHEET_SIDE_INSET := 12.0
## Below this much vertical travel a gesture is still a tap, above it the
## finger was scrolling and must not pick anything.
const ITEM_LIST_TAP_SLOP := 12.0
const PLAYER_NAME := &"UiClickPlayer"
const CUE_TAP := &"tap"
const CUE_CARE := &"care"
const CUE_CONFIRM := &"confirm"
const CUE_BACK := &"back"
const VOLUME_DB := -18.0

const _STREAM_PATHS := {
	"tap": "res://assets/audio/ui/ui_tap.ogg",
	"care": "res://assets/audio/ui/ui_care.ogg",
	"confirm": "res://assets/audio/ui/ui_confirm.ogg",
	"back": "res://assets/audio/ui/ui_back.ogg",
}

## `ui_confirm` measures -11,3 dB RMS against -21,2 dB on `ui_back`, so without
## a trim confirming anything is nearly ten times the energy of dismissing it.
const CUE_TRIM_DB := {
	"tap": -1.1,
	"care": 0.0,
	"confirm": -8.7,
	"back": 0.0,
}

static var _streams: Dictionary = {}


static func install_buttons(root: Node) -> void:
	_install_recursive(root)


## Dipasang di pohon, bukan disapu sekali: baris Collection, item Shop, dan entri
## Atlas lahir jauh setelah `_ready()`, dan sapuan sekali jalan hanya menyembuhkan
## layar yang kebetulan sudah ada saat boot.
static func install_touch_scroll(tree: SceneTree) -> void:
	var relay := Callable(UiJuice, "relay_touch_scroll")
	if not tree.node_added.is_connected(relay):
		tree.node_added.connect(relay)


## Godot berhenti di Control ber-`MOUSE_FILTER_STOP` pertama, dan `PanelContainer`
## maupun `Button` default-nya STOP. Tanpa relay ini jari yang mendarat di kartu
## mana pun menelan drag-nya, sehingga hanya celah antar-kartu yang bisa digulir.
## Yang menjaga tap tetap sampai ke tombol adalah `gui/common/default_scroll_deadzone`,
## bukan STOP: di bawah deadzone gesture masih milik tombol, di atasnya jadi gulir.
static func relay_touch_scroll(node: Node) -> void:
	var control := node as Control
	if control == null or control.mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	# Lists that scroll their own bounded viewport opt out: at PASS the outer
	# ScrollContainer would answer the same drag and both would move, which is
	# how the Team builder scrolled its title and its Back/Save row along with
	# the roster. Only those lists -- not every `ItemList` -- are skipped, since
	# e.g. the Expedition chapter list has no inner scroll of its own and still
	# needs the relay to be reachable at all.
	if control.has_meta(META_LIST_SCROLL):
		return
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
			return
		ancestor = ancestor.get_parent()


## `ItemList` scrolls nothing by itself. Unlike `ScrollContainer` it never binds
## drag-to-scroll to its own scrollbar (measured: a scripted drag over a
## populated list leaves `v_scroll_bar.value` at 0), so a list taller than its
## own window was simply unreachable -- the Battle picker showed four of nine
## Anima with no way to reach the rest.
##
## Forwarding the drag here, rather than growing the list so an outer
## `ScrollContainer` can own it, is what keeps the surrounding chrome still:
## the list is the only thing that moves, so a builder's title and its
## Back/Save row stay where the thumb expects them.
##
## The other half is that a drag must not count as a pick. `ItemList` selects
## on PRESS, so every attempted scroll also chose whatever card the thumb
## started on -- in the Team builder that silently edited the roster. The press
## is therefore swallowed outright and a pick is reported on RELEASE, only when
## the gesture never travelled past `ITEM_LIST_TAP_SLOP`. That leaves the
## selection ring entirely to the caller, which is what stops a card lighting
## up mid-scroll; `on_drag_end` is where a caller repaints after an abandoned
## gesture.
##
## ponytail: swallowing the press also stops the list taking focus on click, and
## picks no longer come from `item_selected`, so keyboard/gamepad selection on
## these lists is gone. Plafonnya: tidak ada yang pernah memberi fokus ke
## ketiganya dan `TeamRosterList` justru mengosongkan stylebox cursor/fokusnya,
## jadi jalur itu memang belum pernah dirancang. Kalau navigasi keyboard
## benar-benar ditambahkan, arahkan `item_activated` ke `on_tap` -- bukan
## `item_selected`, yang akan mengembalikan seleksi-saat-press.
static func install_item_list_touch_scroll(
	list: ItemList, on_tap: Callable, on_drag_end := Callable()
) -> void:
	if list.has_meta(META_LIST_SCROLL):
		return
	list.set_meta(META_LIST_SCROLL, true)
	# Set explicitly, not left to the scene: `relay_touch_scroll` may already
	# have flipped this list to PASS on node_added, before this ran.
	list.mouse_filter = Control.MOUSE_FILTER_STOP
	var gesture := {"pressed": false, "index": -1, "origin": 0.0, "travel": 0.0}
	list.gui_input.connect(
		_on_item_list_gesture.bind(list, on_tap, on_drag_end, gesture)
	)


static func _on_item_list_gesture(
	event: InputEvent,
	list: ItemList,
	on_tap: Callable,
	on_drag_end: Callable,
	gesture: Dictionary
) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			gesture["pressed"] = true
			gesture["origin"] = event.position.y
			gesture["travel"] = 0.0
			gesture["index"] = list.get_item_at_position(event.position, true)
			# Swallow the press so `ItemList` never runs its own selection.
			# `Control` emits this signal BEFORE calling `_gui_input`, and
			# `accept_event()` marks the input handled, so the built-in handler
			# is skipped entirely. Without this the card under the thumb lights
			# up the moment the finger lands and only gets corrected on release
			# -- every attempt to scroll flashed a selection ring on whatever it
			# started from. Selection is now entirely the caller's to paint.
			list.accept_event()
			return
		if not bool(gesture["pressed"]):
			return
		gesture["pressed"] = false
		var index := int(gesture["index"])
		if float(gesture["travel"]) < ITEM_LIST_TAP_SLOP and index >= 0:
			if on_tap.is_valid():
				on_tap.call(index)
		elif on_drag_end.is_valid():
			on_drag_end.call()
		return
	if event is InputEventMouseMotion and bool(gesture["pressed"]):
		list.get_v_scroll_bar().value -= event.relative.y
		# Displacement from where the finger landed, NOT the sum of per-event
		# deltas: touch jitter during a long stationary press would accumulate
		# past the slop and throw a real tap away.
		#
		# Measured in the list's own coordinates, which do not move when it
		# scrolls. Adding the scroll offset to make this "content space" looks
		# tempting and is exactly wrong: a drag that scrolls the list under the
		# finger keeps the finger over the same content, so the displacement
		# cancels to zero and every scroll reads as a tap.
		gesture["travel"] = absf(event.position.y - float(gesture["origin"]))


static func install_button(button: Button) -> void:
	if button.has_meta(META_INSTALLED):
		return
	button.set_meta(META_INSTALLED, true)
	button.resized.connect(_center_pivot.bind(button))
	button.button_down.connect(_button_down.bind(button))
	button.button_up.connect(_button_up.bind(button))
	button.mouse_entered.connect(_button_hover.bind(button, true))
	button.mouse_exited.connect(_button_hover.bind(button, false))
	button.focus_entered.connect(_button_hover.bind(button, true))
	button.focus_exited.connect(_button_hover.bind(button, false))
	_center_pivot(button)


static func play_button(button: Button) -> void:
	_play_click(button)


static func button_cue(button: Button) -> StringName:
	var variation := button.theme_type_variation
	if variation == &"PrimaryButton":
		return CUE_CONFIRM
	if variation.begins_with("Care"):
		return CUE_CARE
	var node_name := String(button.name)
	if (
		variation == &"DangerButton"
		or node_name.contains("Cancel")
		or node_name.contains("Back")
		or node_name.contains("Dismiss")
		or node_name.contains("Leave")
	):
		return CUE_BACK
	return CUE_TAP


static func reveal(control: Control, delay: float = 0.0) -> void:
	_kill_tween(control)
	control.visible = true
	control.pivot_offset = control.size * 0.5
	control.modulate = Color(1.0, 1.0, 1.0, 0.0)
	control.scale = Vector2(0.94, 0.94)
	var tween := control.create_tween().set_parallel(true)
	tween.set_meta("owner_control", control)
	tween.tween_property(control, "modulate", Color.WHITE, 0.24) \
		.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2.ONE, 0.38) \
		.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	control.set_meta(META_TWEEN, tween)


## The counterpart of `reveal` for a control that has to keep its slot in a
## container. It fades the ink and never touches `visible`, because hiding a
## Label collapses its width and drags every sibling still on screen with it.
static func dismiss(control: Control, delay: float = 0.0) -> void:
	_kill_tween(control)
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "modulate:a", 0.0, 0.14) \
		.set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2(0.94, 0.94), 0.14) \
		.set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	control.set_meta(META_TWEEN, tween)


static func pop(control: Control, strength: float = 1.045) -> void:
	if not is_instance_valid(control) or not control.visible:
		return
	_kill_tween(control)
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.96, 0.96)
	control.modulate = Color(1.1, 1.1, 1.1, 1.0)
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "scale", Vector2(strength, strength), 0.10) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "modulate", Color.WHITE, 0.22)
	tween.chain().tween_property(control, "scale", Vector2.ONE, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	control.set_meta(META_TWEEN, tween)


## Berapa lama satu ikon terbang dari Shop ke Bag butuh untuk sampai.
const FLY_TO_SEC := 0.4
## Mid-flight bulge sebelum menyusut masuk ke Bag -- naik dulu ke 2,5x supaya
## busurnya terasa dilempar, bukan cuma diseret lurus dari titik A ke titik B.
const FLY_TO_MID_SCALE := 2.5
const FLY_TO_LAND_SCALE := 0.55


## Satu TextureRect sekali pakai yang terbang dari `from_global` ke pusat
## `to_global`, lalu memanggil `on_arrive` tepat sekali dan membuang dirinya.
## `host` adalah induk sementara si flyer -- biasanya node `UI` di root shell,
## supaya ia menggambar di atas seluruh chrome termasuk scrim bottom sheet.
## Kedua rect diharapkan dari `get_global_rect()`.
##
## Posisi awal dipasang lewat `global_position`, dan tween-nya men-tween
## `global_position` langsung -- BUKAN `position` hasil konversi manual lewat
## `to_local * from_global.position` yang dicoba pertama kali. Versi manual itu
## terukur benar di headless (transform di sana selalu identity, jadi
## bug-nya tidak pernah kena) tapi salah di perangkat: project ini memakai
## `window/stretch/mode="canvas_items"`, dan begitu skala device != 1,
## `get_global_rect()` mengembalikan `size` yang TIDAK ikut diskalakan oleh
## transform yang sama dengan `position`-nya -- meng-konversi `.position` lewat
## `affine_inverse()` lalu menyalin `.size` mentah-mentah mencampur dua unit
## berbeda dalam satu Rect2. `size` di sini aman dipakai apa adanya karena ia
## jadi ukuran LOKAL milik `flyer` (node baru di bawah `host`, canvas yang
## sama), bukan sesuatu yang perlu dikonversi lintas ruang koordinat; hanya
## posisi origin-nya yang perlu itu, dan `global_position` sudah menghitungnya
## dengan benar lewat mesin Godot sendiri, bukan re-implementasi manual.
static func fly_to(
	host: Control,
	texture: Texture2D,
	from_global: Rect2,
	to_global: Rect2,
	on_arrive: Callable = Callable()
) -> void:
	if texture == null or not is_instance_valid(host):
		if on_arrive.is_valid():
			on_arrive.call()
		return
	var flyer := TextureRect.new()
	flyer.texture = texture
	flyer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Without this, TextureRect's minimum size defaults to the TEXTURE's own
	# native size (341x341 for a catalog atlas cell), and Control.size's setter
	# silently clamps any smaller size UP to that minimum -- confirmed by
	# measuring it directly: requesting (72, 96) rendered at (341, 341)
	# regardless. The flyer would always render at native atlas-cell size no
	# matter what from_global/to_global said, both oversized and with its
	# pivot-based visual center thrown off from the box it was actually meant
	# to occupy. `_make_row()`'s row icon sets this for the same reason.
	flyer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyer.z_index = 60
	flyer.size = from_global.size
	flyer.pivot_offset = from_global.size * 0.5
	host.add_child(flyer)
	flyer.global_position = from_global.position

	var target_global := to_global.position + to_global.size * 0.5 - from_global.size * 0.5
	var tween := flyer.create_tween().set_parallel(true)
	tween.tween_property(flyer, "global_position", target_global, FLY_TO_SEC) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(flyer, "modulate:a", 0.85, FLY_TO_SEC) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(func() -> void:
		flyer.queue_free()
		if on_arrive.is_valid():
			on_arrive.call()
	)

	# Scale runs on its OWN Tween, not folded into the one above: a `.chain()`
	# step only starts once every member of the PRECEDING parallel group has
	# finished -- including `global_position`'s full `FLY_TO_SEC` -- so a
	# grow-then-shrink pair chained after it would sit at full bulge for the
	# whole flight and only shrink once the flyer had already arrived. Two
	# independent Tweens on the same node don't have that coupling; both still
	# add up to `FLY_TO_SEC` total and start on the same frame.
	var scale_tween := flyer.create_tween()
	scale_tween.tween_property(flyer, "scale", Vector2.ONE * FLY_TO_MID_SCALE, FLY_TO_SEC * 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	scale_tween.tween_property(flyer, "scale", Vector2.ONE * FLY_TO_LAND_SCALE, FLY_TO_SEC * 0.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


static func show_overlay(overlay: Control, panel: Control) -> void:
	if overlay.visible and overlay.modulate.a >= 0.99:
		return
	_kill_tween(overlay)
	overlay.visible = true
	overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.pivot_offset = panel.size * Vector2(0.5, 0.72)
	panel.scale = Vector2(0.88, 0.88)
	panel.modulate = Color(0.82, 0.92, 1.08, 0.0)
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate", Color.WHITE, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.38) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.24) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	overlay.set_meta(META_TWEEN, tween)
	await tween.finished


static func hide_overlay(overlay: Control, panel: Control) -> void:
	if not overlay.visible:
		return
	_kill_tween(overlay)
	# ponytail: drop under show_overlay's settled threshold in the same frame the
	# fade starts. A dialog reopened mid-fade (the Expedition Level Up queue does
	# exactly that) would otherwise be treated as already shown and swallowed by
	# this tween. Plafon: the two thresholds live next to each other on purpose.
	overlay.modulate.a = 0.98
	panel.pivot_offset = panel.size * Vector2(0.5, 0.72)
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.18) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "scale", Vector2(0.92, 0.92), 0.18) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate:a", 0.0, 0.14)
	overlay.set_meta(META_TWEEN, tween)
	await tween.finished
	if is_instance_valid(overlay):
		overlay.visible = false
		overlay.modulate = Color.WHITE
	if is_instance_valid(panel):
		panel.scale = Vector2.ONE
		panel.modulate = Color.WHITE


# ponytail: hidden full-rect hosts can still report size 0 before their first
# layout. Rest Y uses parent then viewport; never leave a visible 0-size overlay
# at (0,0) — that pins the sheet to the top-left on Android. Plafon: a nested
# sheet that is not full-rect still needs its host laid out.
static func sheet_host_size(overlay: Control, panel: Control) -> Vector2:
	var host := panel.get_parent() as Control
	var size := host.size if host != null else overlay.size
	if size.x < 1.0 or size.y < 1.0:
		size = overlay.size
	if (size.x < 1.0 or size.y < 1.0) and overlay.get_parent() is Control:
		size = (overlay.get_parent() as Control).size
	if (size.x < 1.0 or size.y < 1.0) and overlay.is_inside_tree():
		size = overlay.get_viewport_rect().size
	return size


## X is the side inset, not 0: assigning `position` rewrites a Control's offsets,
## so a rest position of x=0 would quietly undo the inset every time the sheet
## animated into place.
static func sheet_rest_position(overlay: Control, panel: Control) -> Vector2:
	var height := maxf(panel.get_combined_minimum_size().y, 1.0)
	return Vector2(SHEET_SIDE_INSET, sheet_host_size(overlay, panel).y - height)


static func show_bottom_sheet(overlay: Control, panel: Control) -> void:
	_kill_tween(overlay)
	overlay.visible = true
	var height := maxf(panel.get_combined_minimum_size().y, 1.0)
	panel.offset_left = SHEET_SIDE_INSET
	panel.offset_right = -SHEET_SIDE_INSET
	panel.offset_top = -height
	panel.offset_bottom = 0.0
	var target := sheet_rest_position(overlay, panel)
	panel.set_meta(META_SHEET_POSITION, target)
	overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.position = target + Vector2(0.0, height + 24.0)
	panel.modulate = Color(0.84, 0.94, 1.08, 1.0)
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate", Color.WHITE, 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "position", target, 0.38) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.26)
	overlay.set_meta(META_TWEEN, tween)


static func hide_bottom_sheet(overlay: Control, panel: Control) -> void:
	if not overlay.visible:
		return
	_kill_tween(overlay)
	var height := maxf(panel.get_combined_minimum_size().y, 1.0)
	var target: Vector2 = panel.get_meta(META_SHEET_POSITION, sheet_rest_position(overlay, panel))
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.18) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "position", target + Vector2(0.0, height + 24.0), 0.24) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	overlay.set_meta(META_TWEEN, tween)
	await tween.finished
	if is_instance_valid(overlay):
		overlay.visible = false
		overlay.modulate = Color.WHITE
	if is_instance_valid(panel):
		panel.position = target
		panel.modulate = Color.WHITE


static func tween_meter(meter: ProgressBar, target: float) -> void:
	var previous: Variant = meter.get_meta(META_METER_TWEEN) if meter.has_meta(META_METER_TWEEN) else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	var tween := meter.create_tween()
	tween.tween_property(meter, "value", target, 0.42) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	meter.set_meta(META_METER_TWEEN, tween)


static func _install_recursive(node: Node) -> void:
	if node is Button:
		install_button(node as Button)
	for child in node.get_children():
		_install_recursive(child)


static func _center_pivot(button: Button) -> void:
	if is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


static func _button_down(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	_play_click(button)
	_kill_tween(button)
	button.pivot_offset = button.size * 0.5
	var tilt := -0.012 if button.get_instance_id() % 2 == 0 else 0.012
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2(0.94, 0.94), 0.08) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(button, "rotation", tilt, 0.08)
	tween.tween_property(button, "modulate", Color(1.12, 1.12, 1.12, 1.0), 0.08)
	button.set_meta(META_TWEEN, tween)


static func _button_up(button: Button) -> void:
	if not is_instance_valid(button):
		return
	_kill_tween(button)
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE, 0.26) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "rotation", 0.0, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(button, "modulate", Color.WHITE, 0.18)
	button.set_meta(META_TWEEN, tween)


static func _button_hover(button: Button, hovered: bool) -> void:
	if not is_instance_valid(button) or button.disabled or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_kill_tween(button)
	button.pivot_offset = button.size * 0.5
	var target := Vector2(1.025, 1.025) if hovered else Vector2.ONE
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", target, 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(
		button,
		"modulate",
		Color(1.06, 1.06, 1.06, 1.0) if hovered else Color.WHITE,
		0.16
	)
	button.set_meta(META_TWEEN, tween)


# ponytail: one shared player on the tree root, no AudioManager. A second tap
# cuts the first; add a 2-voice pool + UI bus when settings exist.
static func _play_click(button: Button) -> void:
	if not button.is_inside_tree():
		return
	var tree := button.get_tree()
	if tree == null:
		return
	var cue := button_cue(button)
	var stream := _stream_for(cue)
	if stream == null:
		return
	var player := tree.root.get_node_or_null(NodePath(PLAYER_NAME)) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = String(PLAYER_NAME)
		tree.root.add_child(player)
	player.stream = stream
	player.volume_db = VOLUME_DB + float(CUE_TRIM_DB.get(String(cue), 0.0))
	player.pitch_scale = randf_range(0.96, 1.04)
	player.play()


static func _stream_for(cue: StringName) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue] as AudioStream
	var path := String(_STREAM_PATHS.get(String(cue), ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream != null:
		_streams[cue] = stream
	return stream


static func _kill_tween(control: Control) -> void:
	var previous: Variant = control.get_meta(META_TWEEN) if control.has_meta(META_TWEEN) else null
	if previous is Tween and previous.is_valid():
		previous.kill()
