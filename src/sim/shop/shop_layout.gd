class_name ShopLayout
extends Resource
## A shop as data: terrain rows (SimGrid.from_ascii legend: '.' floor, '#'
## wall, 'E' street entry, ' ' outside), the items in it, and where staff
## start. Layouts live in data/layouts/.

@export var id: StringName = &""
@export var display_name: String = ""
@export var rows: PackedStringArray = []
## Authored terrain before thin dividers (snapshot versions 1–7 omit terrain).
@export var legacy_rows: PackedStringArray = []
## Version-8 interior-only terrain exceptions, normalized into rows on load.
@export var thin_cells: Array[Vector2i] = []
@export var thick_cells: Array[Vector2i] = []
@export var placements: Array[ShopPlacement] = []
## Whole-room paint; empty IDs preserve the authored placeholder palette.
@export var wall_swatch_id: StringName = &""
@export var floor_swatch_id: StringName = &""
## Floor types (D25): the shop's default floor type (empty is the free wide
## planks) and the cells laid differently (cell -> [style, swatch, accent],
## FloorStyleDef and SwatchDef ids). Empty is every cell the default.
@export var floor_style_id: StringName = &""
@export var floor_finishes: Dictionary[Vector2i, PackedStringArray] = {}
## Wall finishes (D26): the default finish (empty is plain paint) and the
## faces finished differently (WallFaces key Vector3i(x, y, dir) -> [style,
## swatch, accent]). Wall decor: anchor face -> ItemDef id (WALL layer).
@export var wall_style_id: StringName = &""
@export var wall_finishes: Dictionary[Vector3i, PackedStringArray] = {}
@export var wall_items: Dictionary[Vector3i, StringName] = {}
## Starting cell per staff role (&"cook", &"server", &"cleaner", &"owner").
@export var staff_spawns: Dictionary[StringName, Vector2i] = {}
## Wall segments (FK-070): edge key (SimGrid edge) -> WallKindDef id.
@export var wall_segments: Dictionary[Vector3i, StringName] = {}
## Lot (FK-080): how many cells the outer walls may move out past the starting
## shell on each side. The street (south) side never moves.
@export var lot_west: int = 0
@export var lot_east: int = 0
@export var lot_north: int = 0
## Price of one new floor cell. Removing bought floor refunds half, like furniture.
@export var floor_cell_price: int = 0
## Floor cells the player has bought (FK-080), in grid coordinates. The outer
## walls are derived from these by ShopFootprint; empty is the starting shell.
@export var floor_cells: Array[Vector2i] = []
## Rooms (FK-101), authored like `rows`, one character per cell: 'K' kitchen,
## 'R' restroom, 'S' storage; anything else (or a missing row) is Dining.
## Only floor cells take a room.
@export var room_rows: PackedStringArray = []
## Saved rooms (cell -> SimGrid.Room, Dining cells left out). Used instead of
## room_rows when rooms_explicit is set (a loaded save).
@export var room_cells: Dictionary[Vector2i, int] = {}
@export var rooms_explicit: bool = false
## Set on an older save whose kitchen could not be inferred (a seat was in
## or behind it): the morning asks the player to mark their kitchen.
var rooms_unmarked: bool = false
## Plain notes from forgiving normalization of older saves, logged on load.
var load_notes: Array[String] = []
## Pure load migration stages refunds; Main applies them after complete success.
var load_refund: int = 0
## Built-in dry storage (FK-087): the back-room pantry the shop comes with,
## in units of dry (shelf) ingredients. Placed storage shelves add to it.
@export var pantry_units: int = 0


## The authored rooms from room_rows (cell -> SimGrid.Room, Dining left out).
func authored_rooms() -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for y: int in room_rows.size():
		var row: String = room_rows[y]
		for x: int in row.length():
			match row[x]:
				"K":
					out[Vector2i(x, y)] = SimGrid.Room.KITCHEN
				"R":
					out[Vector2i(x, y)] = SimGrid.Room.RESTROOM
				"S":
					out[Vector2i(x, y)] = SimGrid.Room.STORAGE
	return out


## The rooms this layout builds with: the saved ones, else the authored ones.
func room_map() -> Dictionary[Vector2i, int]:
	return room_cells.duplicate() if rooms_explicit else authored_rooms()
