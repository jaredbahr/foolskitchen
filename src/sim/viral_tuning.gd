class_name ViralTuning
extends Resource
## A happy guest's viral review (#335). All odds, durations and boosts are data.

@export_range(0.0, 1.0, 0.01) var min_happy_share: float = 0.85
@export var min_served: int = 25
@export_range(0.0, 1.0, 0.01) var viral_chance: float = 0.15
@export var viral_multiplier: float = 1.35
@export var boosted_open_days: int = 3
## Days between trigger closes, matching the critic's day-interval convention.
@export var cooldown_days: int = 10


func is_valid() -> bool:
	return is_finite(min_happy_share) and min_happy_share >= 0.0 and min_happy_share <= 1.0 \
		and min_served >= 1 and is_finite(viral_chance) and viral_chance >= 0.0 \
		and viral_chance <= 1.0 and is_finite(viral_multiplier) and viral_multiplier >= 1.0 \
		and boosted_open_days >= 1 and boosted_open_days <= 30 and cooldown_days >= 1
