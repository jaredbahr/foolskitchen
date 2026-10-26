class_name ItemDef
extends Resource
## Placeable content definition in 0.5 m grid cells, facing -Z by default.

enum Category { DOOR, TABLE, CHAIR, STATION, STORAGE, PASS, DECOR }
enum PlacementLayer { NORMAL, FLOOR_DECOR }

## Director's upper bound in metres; presentation logic must also keep hips supported.
const MAX_SEATED_FORWARD_OFFSET: float = 0.05

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.DECOR
## Floor decor shares cells with normal furniture without owning its access.
@export var placement_layer: PlacementLayer = PlacementLayer.NORMAL
## Hidden entries remain valid content so existing saved placements still load.
@export var catalogue_visible: bool = true
## Width and depth of the unrotated occupied rectangle, in cells.
@export var footprint: Vector2i = Vector2i.ONE
@export var solid: bool = true
## Additional blocked cells inside a partly walkable footprint. Empty preserves
## whole-footprint `solid` behaviour; these cells cannot also be seats or work cells.
@export var blocking_cells: Array[Vector2i] = []
## Unrotated relative standing cells; may lie outside the occupied rectangle.
@export var work_cells: Array[Vector2i] = []
## Unrotated relative customer cells, including seats built into a table.
@export var seat_cells: Array[Vector2i] = []
## Optional presentation-only guest offset in world metres toward the authored seat front.
@export var seated_forward_offset: float = 0.0
## Kitchen/storage role; category distinguishes a cooking station from storage.
@export var station_type: StringName = &""
## Concurrent jobs or storage slots, depending on category.
@export var capacity: int = 1
@export var quality_bonus: float = 0.0
@export var price: int = 0
## Owner level required for new purchases. Existing placed items remain valid.
@export var unlock_level: int = 1
@export var charm: int = 0
@export var theme_tags: Array[StringName] = []
## Warm placeholder palette until the shared model palette is locked in Phase 4.
@export var placeholder_color: Color = Color(0.65, 0.44, 0.27, 1.0)
## Optional presentation resource. The sim never instantiates or reads this scene.
## The world view keeps its box fallback when this is absent.
@export var view_scene: PackedScene
## One body-colour slot; unpainted items keep their authored placeholder colour.
@export var paintable: bool = true
@export var paint_slot: StringName = &"body"


## Only passive, non-blocking decor may occupy the floor layer. Interaction
## cells and all gameplay furniture stay in the ordinary placement layer.
func placement_layer_valid() -> bool:
	if placement_layer == PlacementLayer.NORMAL:
		return true
	return placement_layer == PlacementLayer.FLOOR_DECOR and category == Category.DECOR \
		and not solid and blocking_cells.is_empty() and work_cells.is_empty() and seat_cells.is_empty()


## Partial blocking is authored in the same unrotated coordinates as seats.
## Reject invalid cells before any placement or edit can change the live grid.
func blocking_cells_valid() -> bool:
	return blocking_cells_fit(footprint, work_cells, seat_cells)


## The low-level grid API can receive placement arguments separately from this
## definition. Its actual footprint and interaction cells must also fit.
func blocking_cells_fit(occupied_footprint: Vector2i, standing_cells: Array[Vector2i],
		customer_cells: Array[Vector2i]) -> bool:
	var seen: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in blocking_cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= occupied_footprint.x or cell.y >= occupied_footprint.y \
				or seen.has(cell) or customer_cells.has(cell) or standing_cells.has(cell):
			return false
		seen[cell] = true
	return true


## Rotates clockwise in the x/depth plane, then translates the rotated
## footprint's minimum corner to the origin. Outside cells rotate unchanged
## relative to that rectangle; they are deliberately never clamped into it.
static func rotate_cell(cell: Vector2i, unrotated_footprint: Vector2i, quarter_turns: int) -> Vector2i:
	return GridMath.rotate_cell(cell, unrotated_footprint, quarter_turns)
