class_name WallStyleDef
extends Resource
## One wall finish (D26): a pattern put up per wall face (the room side of a
## shell wall, either side of an interior wall), in a main colour and an
## accent colour. IDs are save data; names are player text. Looks only: a
## wall finish changes nothing in the sim. Adding a finish is a .tres in
## data/wall_finishes/ plus, for a new look, a Pattern value and its branch in
## src/world/wall_finish.gdshader (and WallThumbnail).

## The shader's pattern numbers. Never renumber: 0 is the plain paint every
## older shop is drawn with.
enum Pattern { PAINT, WAINSCOT, STRIPES, SUBWAY_TILE, BRICK }

## The free finish every wall face starts with: plain paint in the shop's
## own wall colour.
const DEFAULT_ID: StringName = &"paint"

@export var id: StringName = &""
@export var display_name: String = ""
## Catalogue order, lowest first.
@export var order: int = 0
## Price per wall face (one 0.5 m wide side of a wall). Replacing a priced
## finish refunds half its price; recolouring is free.
@export var price: int = 0
@export var pattern: Pattern = Pattern.PAINT
## Colours a newly finished face gets unless the player picks others
## (SwatchDef ids). An empty main colour is the shop's own wall colour. An
## empty accent is automatic: the shop's wall colour above painted panelling,
## a darker shade of the main colour for the other patterns.
@export var default_swatch: StringName = &""
@export var default_accent: StringName = &""
## Optional style tags for later theme work (empty for now).
@export var theme_tags: Array[StringName] = []
## Owner level that unlocks putting this finish up; 1 is the starting set.
@export var unlock_level: int = 1
## Property tier that unlocks it (only tier 1 exists yet).
@export var unlock_tier: int = 1


## Whether an owner at `level` may put this finish up (tier 1 only for now).
func unlocked(level: int) -> bool:
	return unlock_tier <= 1 and unlock_level <= level


## Player words for why this finish is locked, or "" when it is not.
func locked_reason(level: int) -> String:
	if unlock_tier > 1:
		return "Unlocks with a bigger restaurant"
	if unlock_level > level:
		return "Unlocks at level %d" % unlock_level
	return ""
