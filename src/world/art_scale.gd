class_name ArtScale
extends RefCounted
## Shared view-only proportions from docs/ART_STYLE.md section 2.
## The simulation grid, footprints and saved layouts keep their authored sizes.

const FURNITURE_SCALE: float = 1.1
const CHARACTER_SCALE: float = 1.1
const FOOD_SCALE: float = 0.22
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
