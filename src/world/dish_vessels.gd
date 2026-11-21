class_name DishVessels
extends RefCounted
## What each RecipeDef.vessel is drawn with (ART_STYLE §5). Sizes are the kit's
## source units; the serving multiplies them by ArtScale.FOOD_SCALE and
## ArtScale.VESSEL_SCALE. Read once while a DishVisual warms its pool.
##
## - scene: the vessel model ("" draws none: a takeaway drink in its own cup).
## - rest: height of the surface food stands on.
## - fit: the radius a fitted food fills (ArtScale.SERVED_FOOD_FILL of the
##   vessel's own radius for plates and boards; the inside for cups).
## A food scene whose root has `vessel_space` metadata (a soup in its bowl)
## is authored in its vessel's own space instead: it is not fitted or moved.

const VESSEL_SPACE: StringName = &"vessel_space"
const SPECS: Dictionary[StringName, Dictionary] = {
	&"plate": {"scene": "res://assets/kenney/food/plate.glb", "rest": 0.09, "fit": 0.446},
	&"diner_plate": {"scene": "res://assets/made/food/diner_plate.glb", "rest": 0.09, "fit": 0.446},
	&"deep_plate": {"scene": "res://assets/kenney/food/plate-deep.glb", "rest": 0.1, "fit": 0.446},
	&"bowl": {"scene": "res://assets/kenney/food/bowl.glb", "rest": 0.18, "fit": 0.33},
	&"soup_bowl": {"scene": "res://assets/props/food/soup_bowl.tscn", "rest": 0.23, "fit": 0.33},
	&"pan": {"scene": "res://assets/kenney/food/pan.glb", "rest": 0.13, "fit": 0.37},
	&"board": {"scene": "res://assets/made/food/walnut_board.glb", "rest": 0.055, "fit": 0.44},
	&"rect_plate": {"scene": "res://assets/kenney/food/plate-rectangle.glb", "rest": 0.08, "fit": 0.5},
	&"basket": {"scene": "res://assets/made/food/fry_basket.glb", "rest": 0.025, "fit": 0.42},
	&"cup_saucer": {"scene": "res://assets/kenney/food/cup-saucer.glb", "rest": 0.022, "fit": 0.2},
	&"coaster": {"scene": "res://assets/made/food/coaster.glb", "rest": 0.018, "fit": 0.19},
	&"paper_tray": {"scene": "res://assets/made/food/paper_tray.glb", "rest": 0.012, "fit": 0.4},
	&"paper_cup": {"scene": "res://assets/kenney/food/ice-cream-cup.glb", "rest": 0.1, "fit": 0.24},
	&"paper_bag": {"scene": "res://assets/kenney/food/bag-flat.glb", "rest": 0.06, "fit": 0.42},
	&"none": {"scene": "", "rest": 0.0, "fit": 0.19},
}


static func scene(vessel: StringName) -> PackedScene:
	var path: String = String(spec(vessel).get("scene", ""))
	return null if path.is_empty() else load(path) as PackedScene


static func spec(vessel: StringName) -> Dictionary:
	return SPECS.get(vessel, SPECS[RecipeDef.PLATE])


## Model-to-serving scale of the vessel itself (and of food in its space).
static func scale(vessel: StringName) -> float:
	return ArtScale.FOOD_SCALE * float(ArtScale.VESSEL_SCALE.get(vessel, 1.0))


static func rest_height(vessel: StringName) -> float:
	return float(spec(vessel)["rest"]) * scale(vessel)


## Radius, in metres, that fitted food on this vessel fills.
static func fit_radius(vessel: StringName) -> float:
	return float(spec(vessel)["fit"]) * scale(vessel) * ArtScale.SERVED_FOOD_FILL


static func is_takeaway(vessel: StringName) -> bool:
	return vessel in RecipeDef.TAKEAWAY_VESSELS
