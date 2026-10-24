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
