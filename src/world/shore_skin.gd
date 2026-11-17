class_name ShoreSkin
extends Resource
## The beach and the sea behind a street (#588): a street preset that names one
## (`StreetPreset.shore`) trades the meadow and tree line behind its back lane for
## dunes, a plank path down to a sandy beach, beach life, the surf and open sea.
## NeighbourhoodShore builds it; every colour and count is data here, so each
## seaside street can have its own beach. A preset with no shore keeps its meadow.

## Dry sand, its lighter and darker drifts, and sand the surf has just left.
@export var sand: Color = Color.WHITE
@export var sand_light: Color = Color.WHITE
@export var sand_dark: Color = Color.WHITE
@export var sand_wet: Color = Color.WHITE
## Marram grass on the dunes, one colour per tuft by hash.
@export var grass_colors: Array[Color] = []
## The sea from the shallows out to deep water, and the surf's foam.
@export var sea_shallow: Color = Color.WHITE
@export var sea_mid: Color = Color.WHITE
@export var sea_deep: Color = Color.WHITE
@export var foam: Color = Color.WHITE
## Weathered timber (the path, posts, the lifeguard hut's stilts) and rock.
@export var timber: Color = Color.WHITE
@export var rock: Color = Color.WHITE
## Umbrella canopies (two stripes each), towels, the beach ball and the hut.
@export var umbrella_colors: Array[Color] = []
@export var towel_colors: Array[Color] = []
@export var ball_colors: Array[Color] = []
@export var hut_body: Color = Color.WHITE
@export var hut_trim: Color = Color.WHITE
## The lighthouse's stripes (two alternating) and its lamp's night glow.
@export var lighthouse_colors: Array[Color] = []
@export var lamp_glow: Color = Color(1.0, 0.82, 0.48)
## Sailboat sails and hulls.
@export var sail_colors: Array[Color] = []
@export var hull_colors: Array[Color] = []
## Gull body, wing and wing-tip colours.
@export var gull_body: Color = Color.WHITE
@export var gull_wing: Color = Color.WHITE
@export var gull_tip: Color = Color.WHITE
## How much life: beach umbrellas, people on the sand, people paddling, gulls, boats.
@export_range(0, 8) var umbrellas: int = 4
@export_range(0, 8) var sunbathers: int = 5
@export_range(0, 4) var waders: int = 3
@export_range(0, 8) var gulls: int = 5
@export_range(0, 4) var boats: int = 3


## What makes the shore unusable, in plain words (empty when it is valid).
func errors() -> PackedStringArray:
	var problems: PackedStringArray = []
	var lists: Dictionary[String, Array] = {"grass_colors": grass_colors, "umbrella_colors": umbrella_colors,
		"towel_colors": towel_colors, "ball_colors": ball_colors, "lighthouse_colors": lighthouse_colors,
		"sail_colors": sail_colors, "hull_colors": hull_colors}
	for key: String in lists:
		if lists[key].is_empty():
			problems.append("the shore has no %s" % key)
	return problems


## A string that changes whenever any colour or count does; used in cache keys.
func signature() -> String:
	return var_to_str([sand, sand_light, sand_dark, sand_wet, grass_colors, sea_shallow, sea_mid, sea_deep, foam,
		timber, rock, umbrella_colors, towel_colors, ball_colors, hut_body, hut_trim, lighthouse_colors, lamp_glow,
		sail_colors, hull_colors, gull_body, gull_wing, gull_tip, umbrellas, sunbathers, waders, gulls, boats])
