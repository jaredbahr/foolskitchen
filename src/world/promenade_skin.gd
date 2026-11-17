class_name PromenadeSkin
extends Resource
## A car-free promenade in front of the shops (#596, D39): a street preset that names
## one (`StreetPreset.promenade`) trades its road, kerbs and passing car for one wide
## sweep of paving, with a decorated centre band of lamp posts, benches and planters,
## and people on foot, bikes and with prams and dogs. NeighbourhoodDressing builds it;
## every colour, spacing and walker is data here. A preset with none keeps its road.

## The kinds of people out on the promenade, one per walking lane.
const WALKER_KINDS: Array[StringName] = [&"stroll", &"jog", &"cycle", &"dog", &"pram"]

## The joints between paving slabs, the centre band's stone, its edging and the wave
## inlaid along it.
@export var joint: Color = Color.WHITE
@export var band: Color = Color.WHITE
@export var band_edge: Color = Color.WHITE
@export var wave: Color = Color.WHITE
## Cast-iron paint on the lamp posts and bollards, and the lamps' gilded trim.
@export var iron: Color = Color.WHITE
@export var iron_trim: Color = Color.WHITE
## Metres between lamp posts along the centre band.
@export_range(3.0, 12.0) var lamp_spacing: float = 6.0
## Who walks the promenade, nearest the shops first (see WALKER_KINDS).
@export var walkers: Array[StringName] = []
## Bike frames, prams and dogs, one colour each by hash.
@export var bike_colors: Array[Color] = []
@export var pram_colors: Array[Color] = []
@export var dog_colors: Array[Color] = []
## The ice-cream cart's canopy stripes and its box.
@export var cart_colors: Array[Color] = []


## What makes the promenade unusable, in plain words (empty when it is valid).
func errors() -> PackedStringArray:
	var problems: PackedStringArray = []
	var lists: Dictionary[String, Array] = {"walkers": walkers, "bike_colors": bike_colors, "pram_colors": pram_colors,
		"dog_colors": dog_colors, "cart_colors": cart_colors}
	for key: String in lists:
		if lists[key].is_empty():
			problems.append("the promenade has no %s" % key)
	if walkers.size() > NeighbourhoodDressing.PROMENADE_LANES.size():
		problems.append("the promenade has more walkers than lanes")
	for kind: StringName in walkers:
		if not WALKER_KINDS.has(kind):
			problems.append("unknown promenade walker %s" % kind)
	return problems


## A string that changes whenever any colour, spacing or walker does; used in cache keys.
func signature() -> String:
	return var_to_str([joint, band, band_edge, wave, iron, iron_trim, lamp_spacing, walkers, bike_colors, pram_colors,
		dog_colors, cart_colors])
