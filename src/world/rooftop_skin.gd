class_name RooftopSkin
extends Resource
## A city rooftop instead of a street (#614): a street preset that names one
## (`StreetPreset.rooftop`) has no road, cars, pavements or neighbouring shops at
## roof level. The shop stands on the roof of the tallest tower in town, behind a
## parapet. Guests come up by the lift and stair lobby in front of the shop; a deck
## terrace with planters, potted trees and string lights sits either side of their
## path; plant (water tower, air handlers, vents, a mast) stands round the back. All
## round and far below lies the city: other rooftops a few storeys down, towers, and
## streets fading into haze. NeighbourhoodRooftop builds it; every colour and count is
## data here, so another high site (a downtown club) can have its own city.

## The roof: its membrane and seams, the gravel round its edge and the paving slabs
## of the path from the lobby to the shop.
@export var membrane: Color = Color.WHITE
@export var membrane_seam: Color = Color.WHITE
@export var gravel: Color = Color.WHITE
@export var gravel_dark: Color = Color.WHITE
@export var paver: Color = Color.WHITE
@export var paver_seam: Color = Color.WHITE
## The parapet round the roof's edge, its coping and the rail on top.
@export var parapet: Color = Color.WHITE
@export var coping: Color = Color.WHITE
@export var railing: Color = Color.WHITE
## The terrace: its deck (two plank tones), planters and their soil, plants and pots.
@export var deck: Color = Color.WHITE
@export var deck_dark: Color = Color.WHITE
@export var planter: Color = Color.WHITE
@export var soil: Color = Color.WHITE
@export var leaf_colors: Array[Color] = []
@export var bloom_colors: Array[Color] = []
@export var trunk: Color = Color.WHITE
@export var pot_colors: Array[Color] = []
## The bench cushions and the parasol's two stripes.
@export var cushion: Color = Color.WHITE
@export var parasol_a: Color = Color.WHITE
@export var parasol_b: Color = Color.WHITE
## The lift and stair lobby: walls, dark trim and frames, the lift doors, its glass
## and the board over the doors.
@export var lobby_wall: Color = Color.WHITE
@export var trim: Color = Color.WHITE
@export var lift_door: Color = Color.WHITE
@export var glass: Color = Color.WHITE
@export var sign_board: Color = Color.WHITE
## The roof's plant: air handlers, vents and ducts, and the water tower's staves,
## hoops and roof.
@export var plant: Color = Color.WHITE
@export var plant_dark: Color = Color.WHITE
@export var duct: Color = Color.WHITE
@export var tank_wood: Color = Color.WHITE
@export var tank_roof: Color = Color.WHITE
## Glowing parts: the terrace bulbs and the lobby's lit board, the red aircraft
## lights, the street lights far below and the cars' head and tail lights.
@export var lamp_glow: Color = Color.WHITE
@export var aircraft_red: Color = Color.WHITE
@export var street_glow: Color = Color.WHITE
@export var headlight: Color = Color.WHITE
@export var taillight: Color = Color.WHITE
## The city: building faces (one per building by hash), the curtain-wall glass of the
## office towers, the other roofs, and the streets and pavements at the bottom.
@export var facade_colors: Array[Color] = []
@export var tower_glass: Array[Color] = []
@export var roof_colors: Array[Color] = []
@export var street: Color = Color.WHITE
@export var pavement: Color = Color.WHITE
## Other roofs' clutter: a helipad and its markings, roof gardens' lawn.
@export var helipad: Color = Color.WHITE
@export var helipad_mark: Color = Color.WHITE
@export var lawn: Color = Color.WHITE
## Windows: glass by day and unlit at night, and the warm and cool light of lit rooms.
@export var window_day: Color = Color.WHITE
@export var window_dark: Color = Color.WHITE
@export var window_warm: Color = Color.WHITE
@export var window_cool: Color = Color.WHITE
## The haze the city fades into with depth and distance: by day, at dusk and at night.
@export var haze_day: Color = Color.WHITE
@export var haze_dusk: Color = Color.WHITE
@export var haze_night: Color = Color.WHITE
## Life: pigeons (body and neck sheen), the birds wheeling over the city, the clouds
## drifting past below the roof (lit top and shaded underside), and a distant plane.
@export var pigeon: Color = Color.WHITE
@export var pigeon_neck: Color = Color.WHITE
@export var bird: Color = Color.WHITE
@export var cloud: Color = Color.WHITE
@export var cloud_shade: Color = Color.WHITE
@export var plane: Color = Color.WHITE
@export var plane_tail: Color = Color.WHITE
## How far down the street is (metres below the roof) and how far the city runs out.
@export_range(20.0, 80.0) var street_depth: float = 46.0
@export_range(60.0, 160.0) var city_reach: float = 110.0
@export_range(0, 8) var pigeons: int = 5
@export_range(0, 12) var birds: int = 7
@export_range(0, 16) var clouds: int = 9


## What makes the rooftop unusable, in plain words (empty when it is valid). The
## builder indexes every list by hash, so each needs at least one entry.
func errors() -> PackedStringArray:
	var problems: PackedStringArray = []
	var lists: Dictionary[String, Array] = {"leaf_colors": leaf_colors, "bloom_colors": bloom_colors,
		"pot_colors": pot_colors, "facade_colors": facade_colors, "tower_glass": tower_glass, "roof_colors": roof_colors}
	for key: String in lists:
		if lists[key].is_empty():
			problems.append("the rooftop has no %s" % key)
	return problems


## A string that changes whenever any colour or count does; used in cache keys.
func signature() -> String:
	return var_to_str([membrane, membrane_seam, gravel, gravel_dark, paver, paver_seam, parapet, coping, railing,
		deck, deck_dark, planter, soil, leaf_colors, bloom_colors, trunk, pot_colors, cushion, parasol_a, parasol_b,
		lobby_wall, trim, lift_door, glass, sign_board, plant, plant_dark, duct, tank_wood, tank_roof,
		lamp_glow, aircraft_red, street_glow, headlight, taillight, facade_colors, tower_glass, roof_colors, street, pavement,
		helipad, helipad_mark, lawn, window_day, window_dark, window_warm, window_cool, haze_day, haze_dusk, haze_night,
		pigeon, pigeon_neck, bird, cloud, cloud_shade, plane, plane_tail, street_depth, city_reach, pigeons, birds, clouds])
