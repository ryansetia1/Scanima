class_name CatalogAtlas
extends RefCounted

const CELL := 341
const FOOD_SHEET := preload("res://assets/catalog/food_sheet.png")
const ITEM_SHEET := preload("res://assets/catalog/item_sheet.png")


static func icon_for(row: Dictionary) -> AtlasTexture:
	var sheet_name := str(row.get("sprite_sheet", ""))
	var index := clampi(int(row.get("sprite_index", 0)), 0, 8)
	var sheet: Texture2D = ITEM_SHEET if sheet_name == "item" else FOOD_SHEET
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	var col := index % 3
	var row_i := int(index / 3)
	atlas.region = Rect2(col * CELL, row_i * CELL, CELL, CELL)
	return atlas
