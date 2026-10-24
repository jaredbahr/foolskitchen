class_name CleanlinessTuning
extends Resource
## Authored dirt chances, capacity, patience effect, and report bands.

@export_range(0.0, 1.0, 0.01) var arrival_chance: float = 0.15
@export_range(0.0, 1.0, 0.01) var seat_departure_chance: float = 0.25
@export_range(1, 64) var max_spots: int = 12
@export_range(0.0, 1.0, 0.01) var dirt_penalty: float = 0.3
@export_range(1, 1000) var clean_work_ticks: int = 30
## Zero spots are spotless; these counts select the two nonempty report bands.
@export_range(1, 64) var messy_at: int = 1
@export_range(1, 64) var grubby_at: int = 5
@export var spotless_label: String = "Spotless"
@export var messy_label: String = "A bit messy"
@export var grubby_label: String = "Grubby"


func is_valid() -> bool:
	return is_finite(arrival_chance) and arrival_chance >= 0.0 and arrival_chance <= 1.0 \
		and is_finite(seat_departure_chance) and seat_departure_chance >= 0.0 \
		and seat_departure_chance <= 1.0 and max_spots >= 1 and max_spots <= 64 \
		and is_finite(dirt_penalty) and dirt_penalty >= 0.0 and dirt_penalty <= 1.0 \
		and clean_work_ticks >= 1 and clean_work_ticks <= 1000 \
		and messy_at >= 1 and messy_at < grubby_at and grubby_at <= max_spots \
		and not spotless_label.strip_edges().is_empty() and not messy_label.strip_edges().is_empty() \
		and not grubby_label.strip_edges().is_empty()
