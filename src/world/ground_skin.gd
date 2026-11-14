class_name GroundSkin
extends Resource
## The look of one street's ground and tree line (#421, #424): every colour and
## planting knob NeighbourhoodGround uses. A future site (a neighbourhood plus a
## cuisine) supplies its own skin in its StreetPreset (#425); the geometry and the
## camera edge never change. The warm meadow the starter street uses is data in
## data/streets/starter.tres; `standard()` returns a copy of it.

@export var grass: Color = Color.WHITE
@export var patch_light: Color = Color.WHITE
@export var patch_dark: Color = Color.WHITE
@export var lawn: Color = Color.WHITE
## The forest floor past the tree line.
@export var forest: Color = Color.WHITE
## The back lane and its darker edge.
@export var lane: Color = Color.WHITE
@export var lane_edge: Color = Color.WHITE
@export var trunk: Color = Color.WHITE
@export var leaf_dark: Color = Color.WHITE
@export var leaf_light: Color = Color.WHITE
@export var flowers: Array[Color] = []
## The near and far pavement (a seaside boardwalk, say). Fully transparent, the
## default, keeps the shared grey paving, so the starter street is untouched. It is
## a tint, and the warm key light multiplies it: a pale greige lights up as sandy timber.
@export var pavement: Color = Color(0.0, 0.0, 0.0, 0.0)
## Boardwalk seams: thin lines across the near and far pavement, one plank apart.
## Fully transparent, the default, draws none.
@export var plank_seam: Color = Color(0.0, 0.0, 0.0, 0.0)
## Share of trees that are pines in the meadow and in the tree line.
@export_range(0.0, 1.0) var pine_share: float = 0.18
@export_range(0.0, 1.0) var ring_pine_share: float = 0.32
## Multiplies how many trees stand in the open meadow.
@export_range(0.0, 3.0) var tree_density: float = 1.0
## Multiplies how many flower clumps and bushes dot the meadow.
@export_range(0.0, 3.0) var flower_density: float = 1.0


static func standard() -> GroundSkin:
	return StreetPreset.starter().ground.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GroundSkin


## A string that changes whenever any colour or knob does; used in cache keys.
func signature() -> String:
	return var_to_str([grass, patch_light, patch_dark, lawn, forest, lane, lane_edge, trunk, leaf_dark,
		leaf_light, flowers, pine_share, ring_pine_share, tree_density, flower_density, pavement, plank_seam])
