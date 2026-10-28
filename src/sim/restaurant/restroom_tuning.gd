class_name RestroomTuning
extends Resource
## Restrooms (FK-101), in data. A shop below `seat_threshold` dining seats
## with no restroom draws nothing and changes nothing; a restroom there is
## only a small bonus. From the threshold up, guests expect one.

## Dining seats from which guests start expecting a restroom.
@export var seat_threshold: int = 12
## How long a guest stays inside, in ticks (10 ticks a second).
@export var use_ticks: int = 200
## Share of a guest's food patience lost when they need a restroom and can't
## use one in a shop at or above the threshold.
@export_range(0.0, 1.0, 0.01) var missed_patience_share: float = 0.2
## Raw review bonus for every guest of a shop with a restroom ("a bit happier").
@export_range(0.0, 1.0, 0.01) var restroom_review_bonus: float = 0.2
## Review penalty (raw stars) when a guest needed one and couldn't use one.
@export_range(0.0, 4.0, 0.05) var missed_review_penalty: float = 0.8
## Chance a guest needs the restroom when their customer type sets none.
@export_range(0.0, 1.0, 0.01) var default_need_chance: float = 0.25


func is_valid() -> bool:
	for value: float in [missed_patience_share, restroom_review_bonus, missed_review_penalty, default_need_chance]:
		if not is_finite(value) or value < 0.0:
			return false
	return seat_threshold >= 1 and use_ticks >= 1 and missed_patience_share <= 1.0 and default_need_chance <= 1.0
