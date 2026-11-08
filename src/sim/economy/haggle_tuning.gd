class_name HaggleTuning
extends Resource
## Optional morning haggle; widths and speeds are normalized to the bar.

@export_range(0.0, 1.0, 0.01) var max_discount: float = 0.10
@export var rounds: int = 3
@export var zone_widths: Array[float] = [0.36, 0.26, 0.18]
@export var speeds: Array[float] = [0.65, 0.90, 1.20]


func is_valid() -> bool:
	if not is_finite(max_discount) or max_discount < 0.0 or max_discount > 1.0 \
			or rounds < 1 or rounds > 12 or zone_widths.size() != rounds or speeds.size() != rounds:
		return false
	for index: int in rounds:
		if not is_finite(zone_widths[index]) or zone_widths[index] <= 0.0 or zone_widths[index] > 1.0 \
				or not is_finite(speeds[index]) or speeds[index] <= 0.0:
			return false
	return true
