class_name AquariumTuning
extends Resource
## Fish tank upkeep (#125). With `maintenance` off a tank never clouds over.

## Optional maintenance, on by default: a tank clouds over after this many
## days without a clean, and its charm drops until a "Clean tank" task is done.
@export var maintenance: bool = true
@export_range(1, 60) var cloudy_after_days: int = 4
## A cloudy tank's share of its normal charm.
@export_range(0.0, 1.0, 0.01) var cloudy_charm_factor: float = 0.5
@export_range(1, 1000) var clean_work_ticks: int = 60


func is_valid() -> bool:
	return cloudy_after_days >= 1 and cloudy_after_days <= 60 \
		and is_finite(cloudy_charm_factor) and cloudy_charm_factor >= 0.0 and cloudy_charm_factor <= 1.0 \
		and clean_work_ticks >= 1 and clean_work_ticks <= 1000
