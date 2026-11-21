class_name ArtScale
extends RefCounted
## Shared view-only proportions from docs/ART_STYLE.md section 2.
## The simulation grid, footprints and saved layouts keep their authored sizes.

const FURNITURE_SCALE: float = 1.1
const CHARACTER_SCALE: float = 1.1
const FOOD_SCALE: float = 0.33
## Served food (ART_STYLE §5): the food on a vessel is fitted to fill about
## this share of the vessel's fit radius (DishVessels), never the vessel itself.
const SERVED_FOOD_FILL: float = 0.7
## No served food or drink stands taller than this above its vessel (metres).
const SERVED_FOOD_MAX_HEIGHT: float = 0.18
## Vessels drawn larger than their kit size, on top of FOOD_SCALE, so a small
## cup reads at the default zoom. Every vessel stays inside the plate footprint.
const VESSEL_SCALE: Dictionary[StringName, float] = {
	&"cup_saucer": 1.5, &"paper_cup": 1.6, &"board": 0.9, &"rect_plate": 0.88, &"paper_bag": 1.1, &"coaster": 1.3,
}
## The restaurant cat (#119) is built at its own real size; this keeps it in
## proportion to the Mini Characters, who are scaled by CHARACTER_SCALE.
const CAT_SCALE: float = 1.5
const WALL_HEIGHT: float = 1.4

## Street-front decor sits in separate vertical bands at the shared kit scale.
const EXTERIOR_CANOPY_BOTTOM: float = 1.10
const EXTERIOR_HEADER_BOTTOM: float = 1.27
const EXTERIOR_SILL_BOTTOM: float = 0.28
const EXTERIOR_LIGHTS_BOTTOM: float = 1.30
const EXTERIOR_LIGHTS_OUTSET: float = 0.06
const EXTERIOR_SIGN_TEXT_SIZE: Vector2 = Vector2(0.86, 0.085)
const EXTERIOR_SIGN_TEXT_POSITION: Vector3 = Vector3(0.0, 0.06, -0.029)

## Restroom edge panels: fixed laminate, thinner than the painted walls.
const STALL_PARTITION_HEIGHT: float = 1.4
const STALL_PARTITION_THICKNESS: float = 0.035
