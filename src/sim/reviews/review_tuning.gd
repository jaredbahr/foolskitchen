class_name ReviewTuning
extends Resource
## Authored review probability, scoring penalties, and day-start arrival curve.

@export_range(0.0, 1.0, 0.01) var review_chance: float = 0.5
@export_range(0.0, 4.0, 0.05) var queue_wait_weight: float = 1.0
@export_range(0.0, 4.0, 0.05) var food_wait_weight: float = 1.3
@export_range(0.0, 4.0, 0.05) var overprice_weight: float = 0.8
@export_range(0.0, 4.0, 0.05) var dirt_weight: float = 0.6
@export_range(0.1, 2.0, 0.05) var arrivals_at_one_star: float = 0.8
@export_range(0.1, 2.0, 0.05) var arrivals_at_five_stars: float = 1.2


func is_valid() -> bool:
	for value: float in [review_chance, queue_wait_weight, food_wait_weight,
			overprice_weight, dirt_weight, arrivals_at_one_star, arrivals_at_five_stars]:
		if not is_finite(value) or value < 0.0:
			return false
	return review_chance <= 1.0 and arrivals_at_one_star > 0.0 \
		and arrivals_at_five_stars > 0.0
