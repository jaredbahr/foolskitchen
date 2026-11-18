class_name DayPartsTuning
extends Resource
## Relative evening weights applied to eligible ordinary arrivals.

@export var evening_guest_multipliers: Dictionary[StringName, float] = {}


func is_valid() -> bool:
	for kind: StringName in evening_guest_multipliers:
		var factor: float = evening_guest_multipliers[kind]
		if kind.is_empty() or not is_finite(factor) or factor <= 0.0:
			return false
	return true
