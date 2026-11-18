class_name CliffSkin
extends Resource
## A cliff top instead of a street (#380): a street preset that names one
## (`StreetPreset.cliff`) has no road, cars, pavements or neighbouring shops. The shop
## is a white cottage café on a grassy cliff top. Behind the lot and along one side the
## land ends at a sheer, layered rock cliff, with surf, rocks, a little cove with sea
## stacks and the open sea far below; a timber and white-post rail runs along the edge.
## Guests come up a winding gravel cliff path, over a stile and past a finger post, from
## a small car park and bus stop far off. A lighthouse stands on a distant headland and
## a fishing boat works the bay below. NeighbourhoodCliff builds it; every colour and
## count is data here, so another cliff site can have its own rock and sea.

## The cliff top: its grass (with lighter and darker patches), the turf lip at the edge
## and the soil under it, and the gravel of the cliff path (and its darker edges).
@export var grass: Color = Color.WHITE
@export var grass_light: Color = Color.WHITE
@export var grass_dark: Color = Color.WHITE
@export var turf: Color = Color.WHITE
@export var soil: Color = Color.WHITE
@export var gravel: Color = Color.WHITE
@export var gravel_dark: Color = Color.WHITE
## The cliff's rock: one colour per stratum from the top down (repeated if the cliff has
## more strata), the dark of its cracks and overhangs, and the air between the cliff top
## and the sea that the lower rock and the sea fade toward (it reads as a long way down).
@export var strata: Array[Color] = []
@export var rock_dark: Color = Color.WHITE
@export var haze: Color = Color.WHITE
## The sea far below (sea.gdshader's colours), its foam, and the cove's sand and the
## sand the surf has just left.
@export var sea_shallow: Color = Color.WHITE
@export var sea_mid: Color = Color.WHITE
@export var sea_deep: Color = Color.WHITE
@export var foam: Color = Color.WHITE
@export var sand: Color = Color.WHITE
@export var sand_wet: Color = Color.WHITE
## The safety rail: white posts and weathered timber rails; timber and its dark for the
## stile, finger post and bench; dry-stone walls (main, dark and light stones).
@export var rail_post: Color = Color.WHITE
@export var rail: Color = Color.WHITE
@export var timber: Color = Color.WHITE
@export var timber_dark: Color = Color.WHITE
@export var stone: Color = Color.WHITE
@export var stone_dark: Color = Color.WHITE
@export var stone_light: Color = Color.WHITE
## Plants: wind-bent grass tufts (one colour each by hash), sea pinks (thrift) and their
## leaves, gorse and its yellow flowers, and the windswept thorn's leaves.
@export var tuft_colors: Array[Color] = []
@export var thrift: Color = Color.WHITE
@export var thrift_leaf: Color = Color.WHITE
@export var gorse: Color = Color.WHITE
@export var gorse_bloom: Color = Color.WHITE
@export var thorn_leaf: Color = Color.WHITE
@export var trunk: Color = Color.WHITE
## The lighthouse (white tower, its band and lantern) and the keeper's cottage roof.
@export var lighthouse: Color = Color.WHITE
@export var lighthouse_band: Color = Color.WHITE
@export var slate: Color = Color.WHITE
@export var window: Color = Color.WHITE
## The fishing boat: hull, wheelhouse and trim.
@export var hull: Color = Color.WHITE
@export var wheelhouse: Color = Color.WHITE
@export var boat_trim: Color = Color.WHITE
## Gull body, wing and wing-tip colours; sheep in the fields inland (fleece and face).
@export var gull_body: Color = Color.WHITE
@export var gull_wing: Color = Color.WHITE
@export var gull_tip: Color = Color.WHITE
@export var fleece: Color = Color.WHITE
@export var sheep_face: Color = Color.WHITE
## The car park: its tarmac lane, parked cars (one colour each by hash), the bus stop
## sign, and the lifebuoy's two colours.
@export var tarmac: Color = Color.WHITE
@export var car_colors: Array[Color] = []
@export var bus_sign: Color = Color.WHITE
@export var buoy_a: Color = Color.WHITE
@export var buoy_b: Color = Color.WHITE
## Glowing parts: the lighthouse's lamp and beam, the boat's and the car park's lamps and
## lit windows (a dedicated emissive colour, ART_STYLE.md 3).
@export var lamp_glow: Color = Color.WHITE
## How far down the sea is (metres below the cliff top), and how much life.
@export_range(10.0, 30.0) var drop: float = 16.0
@export_range(0, 10) var gulls: int = 6
@export_range(0, 8) var sheep: int = 5
@export_range(0, 6) var cars: int = 3


## What makes the cliff unusable, in plain words (empty when it is valid). The builder
## indexes every list by hash, so each needs at least one entry.
func errors() -> PackedStringArray:
	var problems: PackedStringArray = []
	var lists: Dictionary[String, Array] = {"strata": strata, "tuft_colors": tuft_colors, "car_colors": car_colors}
	for key: String in lists:
		if lists[key].is_empty():
			problems.append("the cliff has no %s" % key)
	return problems


## A string that changes whenever any colour or count does; used in cache keys.
func signature() -> String:
	return var_to_str([grass, grass_light, grass_dark, turf, soil, gravel, gravel_dark, strata, rock_dark, haze,
		sea_shallow, sea_mid, sea_deep, foam, sand, sand_wet, rail_post, rail, timber, timber_dark, stone, stone_dark,
		stone_light, tuft_colors, thrift, thrift_leaf, gorse, gorse_bloom, thorn_leaf, trunk, lighthouse, lighthouse_band,
		slate, window, hull, wheelhouse, boat_trim, gull_body, gull_wing, gull_tip, fleece, sheep_face, tarmac, car_colors,
		bus_sign, buoy_a, buoy_b, lamp_glow, drop, gulls, sheep, cars])
