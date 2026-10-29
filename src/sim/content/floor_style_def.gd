class_name FloorStyleDef
extends Resource
## One floor type (D25): a pattern laid per cell, in a main colour and an
## accent colour (grout, the second checker colour, seams). IDs are save data;
## names are player text. Looks only: a floor type changes nothing in the sim.
## Adding a type is a .tres in data/floors/ plus, for a new look, a Pattern
## value and its branch in src/world/floor_finish.gdshader.

## The shader's pattern numbers (the data texture's red channel). Never
## renumber: 0 is the legacy wide planks every older shop is drawn with.
enum Pattern { PLANKS, NARROW_PLANKS, HERRINGBONE, CHECKER, SMALL_TILE, HEX_TILE, TERRACOTTA, TERRAZZO, CONCRETE, CARPET }

## The free starting floor every shop has (the legacy wide planks).
const DEFAULT_ID: StringName = &"planks"

@export var id: StringName = &""
@export var display_name: String = ""
## Catalogue order, lowest first.
@export var order: int = 0
## Price per floor tile (one 0.5 m cell). Replacing a priced floor refunds half
## its price; recolouring is free.
@export var price: int = 0
@export var pattern: Pattern = Pattern.PLANKS
## Colours a newly laid tile gets unless the player picks others (SwatchDef
## ids). An empty main colour is the shop's original floor brown; an empty
## accent is a darker shade of the main colour.
@export var default_swatch: StringName = &""
@export var default_accent: StringName = &""
## Optional style tags for later theme work (empty for now).
@export var theme_tags: Array[StringName] = []
## Owner level that unlocks laying this floor; 1 is the starting set.
@export var unlock_level: int = 1
## Property tier that unlocks it.
@export var unlock_tier: int = 1


## Whether an owner at `level` may lay this floor.
func unlocked(level: int, tier: int = 1) -> bool:
	return unlock_tier <= tier and unlock_level <= level


## Player words for why this floor is locked, or "" when it is not.
func locked_reason(level: int, tier: int = 1) -> String:
	if unlock_tier > tier:
		return "Unlocks with a bigger restaurant"
	if unlock_level > level:
		return "Unlocks at level %d" % unlock_level
	return ""
