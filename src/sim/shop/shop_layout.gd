class_name ShopLayout
extends Resource
## A shop as data: terrain rows (SimGrid.from_ascii legend: '.' floor, '#'
## wall, 'E' street entry, ' ' outside), the items in it, and where staff
## start. Layouts live in data/layouts/.

@export var id: StringName = &""
@export var display_name: String = ""
@export var rows: PackedStringArray = []
@export var placements: Array[ShopPlacement] = []
## Starting cell per staff role (&"cook", &"server", &"owner").
@export var staff_spawns: Dictionary[StringName, Vector2i] = {}
