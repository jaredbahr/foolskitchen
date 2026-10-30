class_name LegacyTier1Layout
extends RefCounted
## Frozen terrain for isolated wall algorithms and historical save fixtures.
## Tests of the shipped thin layout live in test_thin_dividers.gd.

const TEMPLATE: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
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
