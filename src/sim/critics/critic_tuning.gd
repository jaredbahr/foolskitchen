class_name CriticTuning
extends Resource
## The disguised food critic (#303), in data (data/balance/critic.tres).
## How often one visits, how heavily their review counts and how their
## disguise looks are authored here; nothing about the critic is hard-coded.

## Shop (owner) level from which a critic can visit.
@export var unlock_level: int = 2
## At least this many days between two critic visits (5 = at most one in 5 days).
@export var cooldown_days: int = 5
## Chance that a critic comes on an open day that is not in the cooldown.
@export_range(0.0, 1.0, 0.01) var daily_chance: float = 0.2
## Their review counts as up to this many ordinary reviews in the reputation
## window (a young shop, with few reviews, counts it fewer times: see
## ReputationBook.record_critic).
@export var review_weight: int = 3
## How many of the four tells a critic shows.
@export var tell_count: int = 2
## The "lingers" tell: the meal lasts this many times longer.
@export_range(1.0, 3.0, 0.01) var linger_multiplier: float = 1.2
## A critic judges the food harder than any guest type (neutral at half quality).
@export_range(0.0, 12.0, 0.1) var quality_weight: float = 6.0
## Stars from which the verdict is positive; at or below `bad_stars` it is negative.
@export_range(1, 5) var good_stars: int = 4
@export_range(1, 5) var bad_stars: int = 2
## When they arrive, as a share of the open hours (permille, 0..1000).
## An ordinary critic comes mid-service; "odd hour" ones very early or late (never
## in the last quarter of the open hours, so they can still be served).
@export var normal_arrival_permille: Vector2i = Vector2i(200, 500)
@export var early_arrival_permille: Vector2i = Vector2i(0, 60)
@export var late_arrival_permille: Vector2i = Vector2i(650, 700)


func is_valid() -> bool:
	if not is_finite(daily_chance) or daily_chance < 0.0 or daily_chance > 1.0:
		return false
	if unlock_level < 1 or cooldown_days < 1 or review_weight < 1 or review_weight > 15:
		return false
	if tell_count < 1 or tell_count > 4 or not is_finite(linger_multiplier) or linger_multiplier < 1.0:
		return false
	if not is_finite(quality_weight) or quality_weight < 0.0 or bad_stars >= good_stars:
		return false
	for window: Vector2i in [normal_arrival_permille, early_arrival_permille, late_arrival_permille]:
		if window.x < 0 or window.y > 1000 or window.x > window.y:
			return false
	return true
