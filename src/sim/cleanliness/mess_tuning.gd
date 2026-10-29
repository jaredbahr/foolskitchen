class_name MessTuning
extends Resource
## Small, authored day-local mishaps. A zero spill chance is entirely inert.

@export_range(0.0, 1.0, 0.0001) var spill_chance_per_cell: float = 0.004
@export_range(1.0, 10.0, 0.1) var clumsy_multiplier: float = 3.0
@export_range(0, 10) var pass_crowding_radius: int = 2
@export_range(1, 20) var pass_crowding_threshold: int = 3
@export_range(0.0, 1.0, 0.0001) var crowding_spill_bonus: float = 0.002
@export_range(0.0, 1.0, 0.001) var maximum_spill_chance: float = 0.03
@export_range(0.0, 1.0, 0.01) var broken_plate_chance: float = 0.2
@export_range(0, 1000) var replacement_plate_cost: int = 2
@export_range(1, 1000) var grease_threshold: int = 8
@export_range(0.1, 1.0, 0.01) var greasy_work_multiplier: float = 0.9
@export_range(1, 1000) var degrease_work_ticks: int = 40
@export_range(1, 64) var sticky_floor_threshold: int = 1


func is_valid() -> bool:
	return _chance(spill_chance_per_cell) and is_finite(clumsy_multiplier) and clumsy_multiplier >= 1.0 \
		and clumsy_multiplier <= 10.0 and pass_crowding_radius >= 0 and pass_crowding_radius <= 10 \
		and pass_crowding_threshold >= 1 and pass_crowding_threshold <= 20 \
		and _chance(crowding_spill_bonus) and _chance(maximum_spill_chance) \
		and maximum_spill_chance >= spill_chance_per_cell and _chance(broken_plate_chance) \
		and replacement_plate_cost >= 0 and replacement_plate_cost <= 1000 \
		and grease_threshold >= 1 and grease_threshold <= 1000 \
		and is_finite(greasy_work_multiplier) and greasy_work_multiplier > 0.0 and greasy_work_multiplier <= 1.0 \
		and degrease_work_ticks >= 1 and degrease_work_ticks <= 1000 \
		and sticky_floor_threshold >= 1 and sticky_floor_threshold <= 64


static func _chance(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0
