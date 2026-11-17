class_name PrestigeTuning
extends Resource
## The scores needed for one, two and three Golden Ladles.

const MAX_LADLES: int = 3

@export var thresholds: Vector3i


func is_valid() -> bool:
	return thresholds.x > 0 and thresholds.x < thresholds.y and thresholds.y < thresholds.z
