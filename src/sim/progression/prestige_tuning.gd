class_name PrestigeTuning
extends Resource
## Golden Ladle thresholds and the weight of repeated copies of one item.

const MAX_LADLES: int = 3
const UNITS_PER_POINT: int = 4

@export var thresholds: Vector3i
## Inclusive end of the first and second copy tiers.
@export var repeat_breakpoints: Vector2i
## Each copy's weight in quarter-points, by tier.
@export var repeat_weights: Vector3i


func is_valid() -> bool:
	return thresholds.x > 0 and thresholds.x < thresholds.y and thresholds.y < thresholds.z \
		and repeat_breakpoints.x > 0 and repeat_breakpoints.y > repeat_breakpoints.x \
		and repeat_weights.x == UNITS_PER_POINT \
		and repeat_weights.x >= repeat_weights.y and repeat_weights.y >= repeat_weights.z \
		and repeat_weights.z >= 0


func copy_weight_units(copies: int) -> int:
	var first: int = mini(copies, repeat_breakpoints.x)
	var second: int = mini(copies, repeat_breakpoints.y) - first
	var remaining: int = copies - first - second
	return first * repeat_weights.x + second * repeat_weights.y + remaining * repeat_weights.z
