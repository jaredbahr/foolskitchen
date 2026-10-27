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
## Below this owner level the type always arrives alone. The size is still
## drawn first, so the unlock never adds or removes a draw from the stream.
@export var party_unlock_level: int = 1
## Short player-facing tip for the level-up report when groups start visiting.
@export var party_tip: String = ""
@export var review_chance_multiplier: float = 1.0
@export var unlock_level: int = 1
@export var weight_at_one_star: float = 0.0
@export var weight_at_five_stars: float = 0.0


func is_valid() -> bool:
	if id.is_empty() or display_name.strip_edges().is_empty() or unlock_level < 1:
		return false
	if party_size_min < 1 or party_size_max < party_size_min or party_size_max > 4:
		return false
	if party_unlock_level < 1:
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


## Fixed sizes consume no draw, preserving the single-guest arrival stream.
## The spawner supplies its existing seeded customers stream for a range.
func draw_party_size(random: RandomNumberGenerator) -> int:
	if not is_valid() or random == null:
		return 0
	if party_size_min == party_size_max:
		return party_size_min
	return random.randi_range(party_size_min, party_size_max)


## Applied after draw_party_size: a locked group shrinks to its first member.
func party_size_at(drawn: int, owner_level: int) -> int:
	return drawn if owner_level >= party_unlock_level else mini(drawn, 1)


## The owner level at which this type first arrives as a group (0 if never).
func group_level() -> int:
	return maxi(unlock_level, party_unlock_level) if party_size_max > 1 else 0


## Reputation below one star uses the one-star weight; above five uses five.
func weight_for_stars(stars: float) -> float:
	if not is_valid() or not is_finite(stars):
		return 0.0
	var t: float = (clampf(stars, 1.0, 5.0) - 1.0) / 4.0
	return lerpf(weight_at_one_star, weight_at_five_stars, t)
