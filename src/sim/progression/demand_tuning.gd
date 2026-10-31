class_name DemandTuning
extends Resource
## Authored demand curves; no random stream or scene state participates.

@export var reputation_stars: PackedFloat32Array = PackedFloat32Array([1.0, 3.0, 5.0])
@export var reputation_factors: PackedFloat32Array = PackedFloat32Array([0.6, 1.0, 1.6])
@export var renown_per_happy_guest: float = 1.0
@export var renown_daily_decay: float = 0.05
@export var renown_max_factor: float = 1.8
@export var renown_half_saturation: float = 90.0
@export var starting_dishes: int = 3
@export var menu_per_extra_dish: float = 0.04
@export var menu_max_bonus: float = 0.30
@export var vibe_min_factor: float = 0.9
@export var vibe_max_factor: float = 1.15
@export var vibe_score_max: float = 100.0
@export var intro_days: int = 1
@export var intro_vibe_floor: float = 1.0
@export var total_cap: float = 3.0
@export var party_max_size: int = 6
@export var party_growth_full_factor: float = 3.0
@export var party_size_weights: PackedFloat32Array = PackedFloat32Array([1.0, 0.8, 0.6, 0.5, 0.3, 0.15])


func is_valid() -> bool:
	if reputation_stars.size() != 3 or reputation_factors.size() != 3:
		return false
	for index: int in 3:
		if not is_finite(reputation_stars[index]) or not _positive(reputation_factors[index]):
			return false
		if index > 0 and (reputation_stars[index] <= reputation_stars[index - 1] \
				or reputation_factors[index] < reputation_factors[index - 1]):
			return false
	if not _nonnegative(renown_per_happy_guest) or not _nonnegative(renown_daily_decay) \
			or renown_daily_decay > 1.0 or not _positive(renown_max_factor) \
			or renown_max_factor < 1.0 or not _positive(renown_half_saturation) \
			or starting_dishes < 0 or not _nonnegative(menu_per_extra_dish) \
			or not _nonnegative(menu_max_bonus) or not _positive(vibe_min_factor) \
			or not _positive(vibe_max_factor) or vibe_min_factor > vibe_max_factor \
			or not _positive(vibe_score_max) or intro_days < 0 \
			or not _positive(intro_vibe_floor) or not _positive(total_cap) or total_cap < 1.0 \
			or party_max_size < 1 or party_max_size > Party.MAX_SIZE \
			or not _positive(party_growth_full_factor) or party_growth_full_factor <= 1.0 \
			or party_size_weights.size() != party_max_size:
		return false
	var positive_weight: bool = false
	for weight: float in party_size_weights:
		if not _nonnegative(weight):
			return false
		positive_weight = positive_weight or weight > 0.0
	return positive_weight


static func _positive(value: float) -> bool:
	return is_finite(value) and value > 0.0


static func _nonnegative(value: float) -> bool:
	return is_finite(value) and value >= 0.0
