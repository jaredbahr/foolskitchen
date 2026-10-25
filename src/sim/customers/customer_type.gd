class_name CustomerType
extends Resource
## Data-owned guest preferences. Regular's neutral values preserve the current
## price, patience and review rules when it is the only available type.

@export var id: StringName = &""
@export var display_name: String = ""
@export var budget_multiplier: float = 1.0
@export var patience_multiplier: float = 1.0
@export var quality_weight: float = 0.0
@export var party_size_min: int = 1
@export var party_size_max: int = 1
@export var review_chance_multiplier: float = 1.0
@export var unlock_level: int = 1
@export var weight_at_one_star: float = 0.0
@export var weight_at_five_stars: float = 0.0


func is_valid() -> bool:
	if id.is_empty() or display_name.strip_edges().is_empty() or unlock_level < 1:
		return false
	# Group visits are a later feature. A malformed resource must not spawn one.
	if party_size_min != 1 or party_size_max != 1:
		return false
	for value: float in [budget_multiplier, patience_multiplier,
			review_chance_multiplier]:
		if not is_finite(value) or value <= 0.0:
			return false
	for value: float in [quality_weight, weight_at_one_star,
			weight_at_five_stars]:
		if not is_finite(value) or value < 0.0:
			return false
	return true


## Reputation below one star uses the one-star weight; above five uses five.
func weight_for_stars(stars: float) -> float:
	if not is_valid() or not is_finite(stars):
		return 0.0
	var t: float = (clampf(stars, 1.0, 5.0) - 1.0) / 4.0
	return lerpf(weight_at_one_star, weight_at_five_stars, t)
