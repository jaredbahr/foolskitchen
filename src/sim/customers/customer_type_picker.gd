class_name CustomerTypePicker
extends RefCounted
## Pure selector. The caller passes GameState.rng(&"customers") through the
## spawner; this class never creates or seeds another random stream.


## `theme` and `strength` are the room's active vibe theme and its arrival
## strength (FK-083). Types that like it weigh more; others are unchanged.
static func choose(catalogue: CustomerTypeCatalogue, owner_level: int,
		stars: float, rng: RandomNumberGenerator, theme: StringName = &"",
		strength: float = 0.0) -> CustomerType:
	if catalogue == null or rng == null or owner_level < 1 \
			or not catalogue.is_valid() or not is_finite(stars):
		return null
	var available: Array[CustomerType] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for kind: CustomerType in catalogue.types:
		var weight: float = _arrival_weight(kind, owner_level, stars, theme, strength)
		if weight <= 0.0:
			continue
		available.append(kind)
		weights.append(weight)
		total += weight
	if available.is_empty() or not is_finite(total):
		return null
	# This matters for the Regular-only golden comparison: selecting the sole
	# type must not shift the existing customers RNG stream by one draw.
	if available.size() == 1:
		return available[0]
	var ticket: float = rng.randf() * total
	for index: int in available.size():
		ticket -= weights[index]
		if ticket < 0.0:
			return available[index]
	return available.back()  # Floating-point boundary at the total.


## A representative budget for today's arrival weights, without sampling.
static func average_budget(catalogue: CustomerTypeCatalogue, owner_level: int,
		stars: float, theme: StringName = &"", strength: float = 0.0) -> float:
	if catalogue == null or owner_level < 1 or not catalogue.is_valid() or not is_finite(stars):
		return 1.0
	var total_weight: float = 0.0
	var total_budget: float = 0.0
	for kind: CustomerType in catalogue.types:
		var weight: float = _arrival_weight(kind, owner_level, stars, theme, strength)
		total_weight += weight
		total_budget += weight * kind.budget_multiplier
	if total_weight <= 0.0 or not is_finite(total_weight) or not is_finite(total_budget):
		return 1.0
	var budget: float = total_budget / total_weight
	return budget if is_finite(budget) and budget > 0.0 else 1.0


static func _arrival_weight(kind: CustomerType, owner_level: int, stars: float,
		theme: StringName, strength: float) -> float:
	if kind.unlock_level > owner_level:
		return 0.0
	var weight: float = kind.weight_for_stars(stars)
	var liking: float = kind.theme_multiplier(theme, strength)
	return weight * liking if liking != 1.0 else weight
