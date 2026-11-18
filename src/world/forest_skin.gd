class_name ForestSkin
extends Resource
## A woodland clearing instead of a street (#607): a street preset that names one
## (`StreetPreset.forest`) has no road, cars, pavements or neighbouring buildings.
## The shop stands in a clearing ringed by tall pines, a dirt track winds past its
## front with hikers and cyclists on it, and a stream runs beyond the track.
## NeighbourhoodForest builds it; every colour and count is data here, so another
## wooded site can have its own forest. The trees on the lot's sides and back are
## named stands (#597) that can be shown felled to stumps or cleared.

## The forest floor under the trees, its needle-litter and mossy patches, and the
## sun that breaks through the canopy in flecks.
@export var forest_floor: Color = Color.WHITE
@export var floor_dark: Color = Color.WHITE
@export var moss: Color = Color.WHITE
@export var sun_fleck: Color = Color.WHITE
## The clearing's grass and its lighter and darker patches.
@export var grass: Color = Color.WHITE
@export var grass_light: Color = Color.WHITE
@export var grass_dark: Color = Color.WHITE
## The dirt track: packed earth, its darker edges and pale dusty stones.
@export var track: Color = Color.WHITE
@export var track_edge: Color = Color.WHITE
@export var pebble: Color = Color.WHITE
## Pine foliage, one tone per tree by hash (darkest first), and their trunks.
@export var pine_colors: Array[Color] = []
@export var trunk: Color = Color.WHITE
## A few broadleaf trees (birch, alder) by the clearing and the stream.
@export var leaf_colors: Array[Color] = []
@export var birch_bark: Color = Color.WHITE
## The undergrowth: ferns, bushes, mushroom caps (with their stems) and wild flowers.
@export var fern_colors: Array[Color] = []
@export var bush_colors: Array[Color] = []
@export var mushroom_caps: Array[Color] = []
@export var mushroom_stem: Color = Color.WHITE
@export var flower_colors: Array[Color] = []
## Stones: mossy rocks, the fire pit's ring and the stream's pebbles.
@export var stone: Color = Color.WHITE
@export var stone_dark: Color = Color.WHITE
## The stream: its deep middle, shallow edges, ripples and muddy banks.
@export var water_deep: Color = Color.WHITE
@export var water_shallow: Color = Color.WHITE
@export var ripple: Color = Color.WHITE
@export var bank: Color = Color.WHITE
## Timber: the porch deck, rails, footbridge and chairs; split log ends; felled stumps.
@export var timber: Color = Color.WHITE
@export var timber_dark: Color = Color.WHITE
@export var log_end: Color = Color.WHITE
## The fire: its flames (glowing, from dusk) and the ash bed.
@export var flame: Color = Color.WHITE
@export var flame_tip: Color = Color.WHITE
@export var ash: Color = Color.WHITE
## The warm bulbs of the string lights and the porch lanterns, and the fireflies.
@export var lamp_glow: Color = Color.WHITE
@export var firefly: Color = Color.WHITE
## A blanket on a rocking chair and the trail sign's paint.
@export var blanket: Color = Color.WHITE
@export var sign_paint: Color = Color.WHITE
## Wildlife at the clearing's edge.
@export var deer_coat: Color = Color.WHITE
@export var deer_pale: Color = Color.WHITE
@export var rabbit_coat: Color = Color.WHITE
## Who comes along the track, in order: &"hike" (with a backpack), &"cycle" or &"stroll".
@export var walkers: Array[StringName] = []
@export var pack_colors: Array[Color] = []
@export var bike_colors: Array[Color] = []
## How deep (metres) each named stand of trees is, outward from the lot.
@export_range(3.0, 12.0) var stand_depth: float = 7.0
@export_range(0, 6) var deer: int = 3
@export_range(0, 8) var rabbits: int = 4
@export_range(0, 120) var fireflies: int = 48

const WALKER_KINDS: Array[StringName] = [&"hike", &"cycle", &"stroll"]


## What makes the forest unusable, in plain words (empty when it is valid). The
## builder indexes every list by hash, so each needs at least one entry.
func errors() -> PackedStringArray:
	var problems: PackedStringArray = []
	var lists: Dictionary[String, Array] = {"pine_colors": pine_colors, "leaf_colors": leaf_colors,
		"fern_colors": fern_colors, "bush_colors": bush_colors, "mushroom_caps": mushroom_caps,
		"flower_colors": flower_colors, "pack_colors": pack_colors, "bike_colors": bike_colors}
	for key: String in lists:
		if lists[key].is_empty():
			problems.append("the forest has no %s" % key)
	if walkers.is_empty():
		problems.append("nobody walks the forest track")
	for kind: StringName in walkers:
		if not WALKER_KINDS.has(kind):
			problems.append("unknown forest walker %s" % kind)
	return problems


## A string that changes whenever any colour or count does; used in cache keys.
func signature() -> String:
	return var_to_str([forest_floor, floor_dark, moss, sun_fleck, grass, grass_light, grass_dark, track, track_edge, pebble,
		pine_colors, trunk, leaf_colors, birch_bark, fern_colors, bush_colors, mushroom_caps, mushroom_stem,
		flower_colors, stone, stone_dark, water_deep, water_shallow, ripple, bank, timber, timber_dark, log_end,
		flame, flame_tip, ash, lamp_glow, firefly, blanket, sign_paint, deer_coat, deer_pale, rabbit_coat,
		walkers, pack_colors, bike_colors, stand_depth, deer, rabbits, fireflies])
