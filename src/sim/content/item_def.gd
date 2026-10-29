class_name ItemDef
extends Resource
## Placeable content definition in 0.5 m grid cells, facing -Z by default.

## RESTROOM (FK-101): restroom fixtures; a toilet has station_type &"toilet".
enum Category { DOOR, TABLE, CHAIR, STATION, STORAGE, PASS, DECOR, RESTROOM, WAITING }
## WALL (D26): hangs on a wall face (ShopEditor.decor, WallDecor), never on
## the grid; its footprint is (width along the wall in faces, 1).
enum PlacementLayer { NORMAL, FLOOR_DECOR, WALL }
## Where a WALL-layer item hangs (D26). INSIDE_FACE: on a solid wall face
## inside the shop (prints, boards). WINDOW: in an outside window, one per
## window, its front facing the street (the neon OPEN sign). Never renumber;
## an exterior-face mount (the street front, #168) would be the next value.
enum WallMount { INSIDE_FACE, WINDOW }
## The widest wall item, in wall faces (0.5 m each).
const MAX_WALL_WIDTH: int = 4

## Buy mode groups furniture by room or function (FK-085). An item without
## one (or with an unknown one) is shown under Decor.
const CATALOGUE_ROOMS: Array[StringName] = [&"dining", &"kitchen", &"bar_cafe", &"decor", &"lighting", &"restroom"]
const DEFAULT_ROOM: StringName = &"decor"

## Director's upper bound in metres; presentation logic must also keep hips supported.
const MAX_SEATED_FORWARD_OFFSET: float = 0.05
## A bounded upper-body pose, never a model scale or a whole-person displacement.
const MAX_SEATED_LEAN_DEGREES: float = 35.0

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.DECOR
## Floor decor shares cells with normal furniture without owning its access.
@export var placement_layer: PlacementLayer = PlacementLayer.NORMAL
## Hidden entries remain valid content so existing saved placements still load.
@export var catalogue_visible: bool = true
## Buy mode room (one of CATALOGUE_ROOMS); empty means Decor.
@export var catalogue_room: StringName = &""
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
## Forward torso articulation while seated. Zero preserves the imported sit pose.
@export var seated_lean_degrees: float = 0.0
## A counter served from the far side (FK-083): staff take orders and hand
## food and drinks across it to a guest on a facing stool.
@export var serve_across: bool = false
## Kitchen/storage role; category distinguishes a cooking station from storage.
@export var station_type: StringName = &""
## Concurrent jobs at a station (storage space is storage_units).
@export var capacity: int = 1
## Ingredient storage this item adds (FK-087): units of one storage kind,
## shared by every ingredient of that kind. Capacities of one kind add up.
@export var storage_kind: IngredientDef.Storage = IngredientDef.Storage.SHELF
@export var storage_units: int = 0
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
## Wall decor (D26): the colour of a soft light the view puts in front of a
## hung item, such as the neon sign's red glow on its wall and the floor
## below. Alpha 0 (the default) is no light. Looks only.
@export var glow_color: Color = Color(0.0, 0.0, 0.0, 0.0)
## Wall items only: on an inside wall face, or in an outside window (one
## window wide, so `footprint` is (1, 1)).
@export var wall_mount: WallMount = WallMount.INSIDE_FACE
## One body-colour slot; unpainted items keep their authored placeholder colour.
@export var paintable: bool = true
@export var paint_slot: StringName = &"body"


## The Buy mode room this item is listed under.
func buy_room() -> StringName:
	return catalogue_room if CATALOGUE_ROOMS.has(catalogue_room) else DEFAULT_ROOM


## Only passive, non-blocking decor may occupy the floor layer. Interaction
## cells and all gameplay furniture stay in the ordinary placement layer.
## Wall items (D26) are passive decor or restroom fixtures one face deep.
func placement_layer_valid() -> bool:
	if placement_layer == PlacementLayer.NORMAL:
		return true
	var passive: bool = not solid and blocking_cells.is_empty() and work_cells.is_empty() and seat_cells.is_empty()
	if placement_layer == PlacementLayer.WALL:
		return passive and (category == Category.DECOR or category == Category.RESTROOM) \
			and footprint.y == 1 and footprint.x >= 1 and footprint.x <= MAX_WALL_WIDTH \
			and (wall_mount == WallMount.INSIDE_FACE or wall_mount == WallMount.WINDOW and footprint.x == 1)
	return placement_layer == PlacementLayer.FLOOR_DECOR and category == Category.DECOR and passive


## Hangs on a wall face (D26) instead of standing on the floor.
func hangs_on_wall() -> bool:
	return placement_layer == PlacementLayer.WALL


## A wall item that hangs in an outside window rather than on a wall face.
func hangs_in_window() -> bool:
	return placement_layer == PlacementLayer.WALL and wall_mount == WallMount.WINDOW


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
