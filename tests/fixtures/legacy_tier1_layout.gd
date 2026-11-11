class_name LegacyTier1Layout
extends RefCounted
## Frozen original authored geometry for wall algorithms and historical saves.
## Tests of the shipped thin layout live in test_thin_dividers.gd.

const TEMPLATE: ShopLayout = preload("res://data/layouts/tier1_original.tres")
const ROWS: PackedStringArray = ["##############", "#............#", "#............#",
	"#............#", "#####...######", "#............#", "#............#", "#............#",
	"#............#", "#............#", "######..######", "      EE      "]
const ROOMS: PackedStringArray = ["", " KKKKKKKKKKKK", " KKKKKKKKKKKK", " KKKKKKKKKKKK", "     KKK"]


static func make() -> ShopLayout:
	var layout: ShopLayout = TEMPLATE.duplicate(true) as ShopLayout
	layout.rows = ROWS.duplicate()
	layout.legacy_rows = ROWS.duplicate()
	layout.room_rows = ROOMS.duplicate()
	layout.wall_segments.clear()
	layout.thin_cells.clear()
	layout.thick_cells.clear()
	return layout


## `layout` with its three tables back in one row, as the original template had
## them before #320 turned them for an aisle. That row's seats shut the
## kitchen off for anyone who won't walk through a seat; fixtures that record
## or study that barrier use it.
static func with_table_row(layout: ShopLayout) -> ShopLayout:
	var copy: ShopLayout = layout.duplicate() as ShopLayout
	copy.placements = []
	var table: int = 0
	for placement: ShopPlacement in layout.placements:
		var placed: ShopPlacement = placement.duplicate() as ShopPlacement
		if placed.item_id == &"table_2" and table < AisleRepair.ORIGINAL_TABLES.size():
			placed.origin = AisleRepair.ORIGINAL_TABLES[table][0]
			placed.quarter_turns = AisleRepair.ORIGINAL_TABLES[table][1]
			table += 1
		copy.placements.append(placed)
	return copy
