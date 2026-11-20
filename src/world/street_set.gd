class_name StreetSet
extends Resource
## The buildings of one street (#422): palettes, roof shapes, heights, fences and
## the little businesses that stand in the row beside the player's lot. Like
## GroundSkin it is one half of a StreetPreset (#425): a seaside street supplies
## its own set in its preset and NeighbourhoodBuildings builds it the same way.
## The starter street's set (warm swatches, cottages and a baker's row) is data
## in data/streets/starter.tres; `standard()` returns a copy of it.

## The neighbour id of the named rival house (`rival_house`).
const RIVAL_ID: StringName = &"rival_house"

enum Roof { GABLE_FRONT, GABLE_SIDE, HIP, PYRAMID, SHED, FLAT, FALSE_FRONT }
enum Fence { PICKET, HEDGE, WALL, RAIL }

## Changes every hashed choice (colours, heights, widths) without touching rules.
@export var seed_salt: int = 7
## Shopfronts on each side of the player's lot, sharing the street line.
@export_range(1, 3) var shops_per_side: int = 2
## Houses across the road, each on its own lot.
@export_range(1, 8) var house_count: int = 5
## The house across the road a rival can take over (#701): its index in the house row, or -1
## for none. It becomes a named neighbour with the id `RIVAL_ID`, so the neighbour API
## (`NeighbourhoodDressing.set_neighbour_state`) reaches it; with no rival it looks like any house.
@export var rival_house: int = -1
## Where the rival parks his food truck on a street with no shopfronts (#701): its centre's offset along the
## street from the door and its distance out from the lot's front edge, in metres. (0, 0) means the street
## has no room for one. The serving hatch always faces the street.
@export var rival_truck_slot: Vector2 = Vector2.ZERO
@export var wall_colors: Array[Color] = []
@export var roof_colors: Array[Color] = []
@export var door_colors: Array[Color] = []
@export var hedge_colors: Array[Color] = []
@export var bloom_colors: Array[Color] = []
@export var trim: Color = Color.WHITE
@export var glass: Color = Color.WHITE
@export var stone: Color = Color.WHITE
@export var path: Color = Color.WHITE
@export var wood: Color = Color.WHITE
## Back gardens (#440): soil, the pastel cloths on a washing line, play-set and toy colours.
@export var soil: Color = Color.WHITE
@export var laundry_colors: Array[Color] = []
@export var play_colors: Array[Color] = []
## Night windows (#440): the warm tints a lit window takes, one per window by hash.
@export var window_glows: Array[Color] = []
@export var house_roofs: Array[int] = []
@export var shop_roofs: Array[int] = []
@export var house_heights: Array[float] = []
@export var shop_heights: Array[float] = []
@export var fences: Array[int] = []
@export var shops: Array[ShopStyle] = []
## A named terrace (#596): when set, the row on each side is these neighbours, in
## order outward from the lot (left is -u), instead of `shops_per_side` hashed picks
## from `shops`. Each is its own node the view can show closed and for sale.
@export var terrace_left: Array[ShopStyle] = []
@export var terrace_right: Array[ShopStyle] = []
## Street furniture on the near pavement (#423): what stands there and how many.
@export var furniture: Array[StreetPropSpec] = []
@export var metal: Color = Color.WHITE
## Postbox and hydrant paint.
@export var signal_red: Color = Color.WHITE
@export var bin_colors: Array[Color] = []
## Small life (#423): birds on the lawn, leaves off the planter trees, hanging signs.
@export_range(0, 6) var birds: int = 3
@export var bird_colors: Array[Color] = []
@export_range(0, 24) var leaves: int = 8
@export var leaf_colors: Array[Color] = []
## How far (degrees) the shops' hanging signs swing.
@export_range(0.0, 30.0) var sign_sway_degrees: float = 9.0


## A fresh copy of the starter street's set (data/streets/starter.tres), safe to change.
static func standard() -> StreetSet:
	return StreetPreset.starter().buildings.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as StreetSet


## True when the street names a spot for the rival's food truck (#701).
func has_truck_slot() -> bool:
	return rival_truck_slot != Vector2.ZERO


## True when the row beside the lot is a named terrace (#596).
func has_terrace() -> bool:
	return not terrace_left.is_empty() or not terrace_right.is_empty()


## A string that changes whenever anything in the set does; used in cache keys.
func signature() -> String:
	var parts: Array = [seed_salt, shops_per_side, house_count, rival_house, rival_truck_slot, wall_colors, roof_colors, door_colors, hedge_colors,
		bloom_colors, trim, glass, stone, path, wood, house_roofs, shop_roofs, house_heights, shop_heights, fences,
		metal, signal_red, bin_colors, birds, bird_colors, leaves, leaf_colors, sign_sway_degrees,
		soil, laundry_colors, play_colors, window_glows]
	for spec: StreetPropSpec in furniture:
		parts.append([int(spec.kind), spec.count, int(spec.zone)])
	for style: ShopStyle in shops:
		parts.append([style.id, style.wall, style.awning_a, style.awning_b, style.sign_board, style.door, int(style.accent)])
	for side: Array[ShopStyle] in ([terrace_left, terrace_right] if has_terrace() else []):
		for style: ShopStyle in side:
			parts.append([style.id, style.wall, style.awning_a, style.awning_b, style.sign_board, style.door, int(style.accent),
				int(style.form), style.sign_text, style.width])
		parts.append("|")
	return var_to_str(parts)
