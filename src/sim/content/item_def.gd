class_name ItemDef
extends Resource
## Placeable content definition in 0.5 m grid cells, facing -Z by default.

enum Category { DOOR, TABLE, CHAIR, STATION, STORAGE, PASS, DECOR }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.DECOR
## Width and depth of the unrotated occupied rectangle, in cells.
@export var footprint: Vector2i = Vector2i.ONE
@export var solid: bool = true
## Unrotated relative standing cells; may lie outside the occupied rectangle.
@export var work_cells: Array[Vector2i] = []
## Unrotated relative customer cells, including seats built into a table.
@export var seat_cells: Array[Vector2i] = []
## Kitchen/storage role; category distinguishes a cooking station from storage.
@export var station_type: StringName = &""
## Concurrent jobs or storage slots, depending on category.
@export var capacity: int = 1
@export var quality_bonus: float = 0.0
@export var price: int = 0
@export var charm: int = 0
@export var theme_tags: Array[StringName] = []
## Warm placeholder palette until the shared model palette is locked in Phase 4.
@export var placeholder_color: Color = Color(0.65, 0.44, 0.27, 1.0)


## Rotates clockwise in the x/depth plane, then translates the rotated
## footprint's minimum corner to the origin. Outside cells rotate unchanged
## relative to that rectangle; they are deliberately never clamped into it.
static func rotate_cell(cell: Vector2i, unrotated_footprint: Vector2i, quarter_turns: int) -> Vector2i:
	return GridMath.rotate_cell(cell, unrotated_footprint, quarter_turns)
