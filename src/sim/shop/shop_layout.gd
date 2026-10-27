class_name ShopLayout
extends Resource
## A shop as data: terrain rows (SimGrid.from_ascii legend: '.' floor, '#'
## wall, 'E' street entry, ' ' outside), the items in it, and where staff
## start. Layouts live in data/layouts/.

@export var id: StringName = &""
@export var display_name: String = ""
@export var rows: PackedStringArray = []
@export var placements: Array[ShopPlacement] = []
## Whole-room paint; empty IDs preserve the authored placeholder palette.
@export var wall_swatch_id: StringName = &""
@export var floor_swatch_id: StringName = &""
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
## Built-in dry storage (FK-087): the back-room pantry the shop comes with,
## in units of dry (shelf) ingredients. Placed storage shelves add to it.
@export var pantry_units: int = 0
