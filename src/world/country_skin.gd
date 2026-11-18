class_name CountrySkin
extends Resource
## A country lane instead of a street (#613): a street preset that names one
## (`StreetPreset.country`) has no road, town traffic, pavements or neighbouring
## shops. The shop is an old watermill on a narrow lane: a mill stream runs past its
## side under a turning waterwheel, over a little weir and under the lane's stone
## bridge. Hedgerows and dry-stone walls line the lane and the fields; a farm gate
## with a produce stand opens on a wildflower meadow beside the shop, a cornfield
## stands out back, and cottages, sheep and birds dot the fields beyond. A slow
## tractor and a cyclist come along the lane now and then. NeighbourhoodCountry builds
## it; every colour and count is data here. The meadow and cornfield beside and
## behind the lot are named land plots (#597) that can be shown grown, mown or cleared.

## The fields' grass: pasture, its lighter and darker patches, and the verges.
@export var grass: Color = Color.WHITE
@export var grass_light: Color = Color.WHITE
@export var grass_dark: Color = Color.WHITE
## The meadow's long grass, its seed heads and its wild flowers.
@export var meadow: Color = Color.WHITE
@export var meadow_seed: Color = Color.WHITE
@export var flower_colors: Array[Color] = []
## The cornfield: ripe wheat, its ears, the stubble once cut, and its soil.
@export var wheat: Color = Color.WHITE
@export var wheat_ear: Color = Color.WHITE
@export var stubble: Color = Color.WHITE
@export var soil: Color = Color.WHITE
@export var soil_dark: Color = Color.WHITE
## Hay: mown rows and bales.
@export var hay: Color = Color.WHITE
## The far fields' crops, one per field by hash (pasture shows the grass).
@export var field_colors: Array[Color] = []
## The lane: worn tarmac, its edges, and the grass down its middle.
@export var lane: Color = Color.WHITE
@export var lane_edge: Color = Color.WHITE
## The gravel forecourt in front of the mill.
@export var gravel: Color = Color.WHITE
## Hedgerows: their leaf tones (darkest first) and the hawthorn's blossom.
@export var hedge_colors: Array[Color] = []
@export var blossom: Color = Color.WHITE
## Trees: oaks in the hedgerows, a willow by the stream.
@export var leaf_colors: Array[Color] = []
@export var willow: Color = Color.WHITE
@export var trunk: Color = Color.WHITE
## Stone: the dry-stone walls, the bridge, the weir and the wheel pit.
@export var stone: Color = Color.WHITE
@export var stone_light: Color = Color.WHITE
@export var stone_dark: Color = Color.WHITE
## The stream: its deep middle, shallow edges, ripples and banks.
@export var water_deep: Color = Color.WHITE
@export var water_shallow: Color = Color.WHITE
@export var ripple: Color = Color.WHITE
@export var bank: Color = Color.WHITE
## Timber: the waterwheel, the farm gate, the produce stand; tarred and weathered.
@export var timber: Color = Color.WHITE
@export var timber_dark: Color = Color.WHITE
@export var iron: Color = Color.WHITE
## The produce: cabbages, carrots, potatoes, apples, marrows.
@export var produce_colors: Array[Color] = []
@export var crate: Color = Color.WHITE
@export var chalkboard: Color = Color.WHITE
@export var sign_paint: Color = Color.WHITE
## Far cottages: walls, roofs (thatch or slate), doors. The second roof (slate) also
## roofs the mill's wheel house and caps its axle housing (#619).
@export var cottage_walls: Array[Color] = []
@export var cottage_roofs: Array[Color] = []
@export var door_colors: Array[Color] = []
## The warm lanterns and lit windows at night.
@export var lamp_glow: Color = Color.WHITE
@export var window_glow: Color = Color.WHITE
## Sheep: fleece and face; the birds' tone.
@export var fleece: Color = Color.WHITE
@export var sheep_face: Color = Color.WHITE
@export var bird: Color = Color.WHITE
## The tractor: its paint, its wheels' hubs and its trailer.
@export var tractor: Color = Color.WHITE
@export var tractor_trim: Color = Color.WHITE
@export var tyre: Color = Color.WHITE
## Who comes along the lane, in order: &"cycle" or &"stroll".
@export var walkers: Array[StringName] = []
@export var bike_colors: Array[Color] = []
## How deep (metres) the meadow and cornfield plots round the lot are.
@export_range(3.0, 12.0) var plot_depth: float = 6.5
@export_range(0, 6) var sheep: int = 3
@export_range(0, 12) var birds: int = 5
@export_range(0, 8) var cottages: int = 5

const WALKER_KINDS: Array[StringName] = [&"cycle", &"stroll"]


## What makes the country unusable, in plain words (empty when it is valid). The
## builder indexes every list by hash, so each needs at least one entry.
func errors() -> PackedStringArray:
	var problems: PackedStringArray = []
	var lists: Dictionary[String, Array] = {"flower_colors": flower_colors, "field_colors": field_colors,
		"hedge_colors": hedge_colors, "leaf_colors": leaf_colors, "produce_colors": produce_colors,
		"cottage_walls": cottage_walls, "cottage_roofs": cottage_roofs, "door_colors": door_colors,
		"bike_colors": bike_colors}
	for key: String in lists:
		if lists[key].is_empty():
			problems.append("the country has no %s" % key)
	if walkers.is_empty():
		problems.append("nobody comes along the country lane")
	for kind: StringName in walkers:
		if not WALKER_KINDS.has(kind):
			problems.append("unknown country walker %s" % kind)
	return problems


## A string that changes whenever any colour or count does; used in cache keys.
func signature() -> String:
	return var_to_str([grass, grass_light, grass_dark, meadow, meadow_seed, flower_colors, wheat, wheat_ear, stubble,
		soil, soil_dark, hay, field_colors, lane, lane_edge, gravel, hedge_colors, blossom, leaf_colors, willow, trunk,
		stone, stone_light, stone_dark, water_deep, water_shallow, ripple, bank, timber, timber_dark, iron,
		produce_colors, crate, chalkboard, sign_paint, cottage_walls, cottage_roofs, door_colors, lamp_glow,
		window_glow, fleece, sheep_face, bird, tractor, tractor_trim, tyre, walkers, bike_colors, plot_depth, sheep,
		birds, cottages])
