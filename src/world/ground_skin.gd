class_name GroundSkin
extends Resource
## The look of one street's ground and tree line (#421, #424): every colour and
## planting knob NeighbourhoodGround uses. A future site (a neighbourhood plus a
## cuisine) supplies its own skin; the geometry and the camera edge never change.
## `standard()` is the warm meadow the first street uses, from existing swatches.

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
## Share of trees that are pines in the meadow and in the tree line.
@export_range(0.0, 1.0) var pine_share: float = 0.18
@export_range(0.0, 1.0) var ring_pine_share: float = 0.32
## Multiplies how many trees stand in the open meadow.
@export_range(0.0, 3.0) var tree_density: float = 1.0
## Multiplies how many flower clumps and bushes dot the meadow.
@export_range(0.0, 3.0) var flower_density: float = 1.0


static func standard() -> GroundSkin:
	var moss: Color = (load("res://data/swatches/moss.tres") as SwatchDef).color
	var sage: Color = (load("res://data/swatches/sage.tres") as SwatchDef).color
	var butter: Color = (load("res://data/swatches/butter.tres") as SwatchDef).color
	var cream: Color = (load("res://data/swatches/cream.tres") as SwatchDef).color
	var clay: Color = (load("res://data/swatches/clay.tres") as SwatchDef).color
	var rose: Color = (load("res://data/swatches/dusty_rose.tres") as SwatchDef).color
	var terracotta: Color = (load("res://data/swatches/terracotta.tres") as SwatchDef).color
	var honey: Color = (load("res://data/swatches/honey.tres") as SwatchDef).color
	var skin: GroundSkin = GroundSkin.new()
	# Sage and moss warmed with butter, then pushed toward a fresh meadow green:
	# the scene's tone-mapping and soft light dim every swatch a good deal.
	var mix: Color = sage.lerp(butter, 0.30).lerp(moss, 0.15)
	skin.grass = Color.from_hsv(lerpf(mix.h, 0.235, 0.7), clampf(mix.s * 2.0, 0.0, 0.47), clampf(mix.v * 1.22, 0.0, 0.82))
	skin.patch_light = skin.grass.lerp(butter, 0.22)
	skin.patch_dark = skin.grass.lerp(moss, 0.4)
	skin.lawn = skin.grass.lerp(cream, 0.10).lerp(butter, 0.08)
	skin.forest = skin.grass.darkened(0.42)
	skin.lane = clay.lerp(butter, 0.35).lerp(cream, 0.5)
	skin.lane_edge = skin.lane.darkened(0.16)
	skin.trunk = (load("res://data/swatches/walnut.tres") as SwatchDef).color
	skin.leaf_dark = skin.grass.darkened(0.22).lerp(moss.darkened(0.1), 0.1)
	skin.leaf_light = skin.grass.lightened(0.04)
	skin.flowers = [butter, rose, cream, terracotta.lerp(rose, 0.3), honey]
	return skin
