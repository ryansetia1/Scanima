extends SceneTree

func _initialize():
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1602)
	root.add_child(vp)
	var view = (load("res://scenes/ui/collection_view.tscn") as PackedScene).instantiate()
	vp.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var sheet = view.find_child("CollectionSheetOverlay", true, false)
	var panel := sheet.panel() as PanelContainer
	var body := sheet.find_child("SheetContent", true, false) as Control
	var row := {
		"id": "p1", "nickname": "Mugshots", "status": "ready",
		"element": "ceramic", "secondary_element": "flow", "rarity": 1, "stage": 1,
		"care_score": 120,
		"base_stats": {"hp": 55, "atk": 25, "def": 65, "spd": 40, "special": 15},
		"care": {"hunger": 100.0, "energy": 100.0, "hygiene": 100.0, "bond": 0.0},
	}
	view.show_preview(row, false)
	view.apply_atlas_status({"available": true, "published": false}, row, view.selected_revision())
	for i in 40:
		await process_frame
	var sb := panel.get_theme_stylebox("panel")
	var pad := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb != null else 0.0
	print("panel_w=", panel.size.x, " panel_pad=", pad,
		" available=", panel.size.x - pad,
		" body_min_w=", body.get_combined_minimum_size().x)
	var badge := view.find_child("CollectionAtlasBadge", true, false) as Label
	var meta := view.find_child("CollectionSheetMeta", true, false) as Label
	print("badge visible=", badge.visible, " text=", badge.text,
		" badge_min_w=", badge.get_combined_minimum_size().x,
		" autowrap=", badge.autowrap_mode)
	print("meta text=", meta.text, " meta_min_w=", meta.get_combined_minimum_size().x)
	print("--- widest rows ---")
	var rows: Array = []
	for c in body.get_children():
		var ctrl := c as Control
		if ctrl == null:
			continue
		rows.append([ctrl.get_combined_minimum_size().x, String(ctrl.name), ctrl.visible])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 6):
		print("  ", r[1], " min_w=", r[0], " visible=", r[2])
	quit()
