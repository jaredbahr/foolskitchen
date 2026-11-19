class_name CustomerTypePicker
extends RefCounted
## Pure selector. The caller passes GameState.rng(&"customers") through the
## spawner; this class never creates or seeds another random stream.


## `theme` and `strength` are the room's active vibe theme and its arrival
## strength (FK-083). Types that like it weigh more; others are unchanged.
## `mix` is the active lot's guest mix (#471): empty at the home shop, where
## reputation weights decide; elsewhere each type's share replaces them.
## `minute` is the shop clock (negative: ignore arrival windows).
static func choose(catalogue: CustomerTypeCatalogue, owner_level: int,
		stars: float, rng: RandomNumberGenerator, theme: StringName = &"",
		strength: float = 0.0, evening: DayPartsTuning = null,
		mix: Dictionary[StringName, float] = {}, minute: int = -1) -> CustomerType:
	if catalogue == null or rng == null or owner_level < 1 \
			or not catalogue.is_valid() or not is_finite(stars):
		return null
	var available: Array[CustomerType] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for kind: CustomerType in catalogue.types:
		var weight: float = arrival_weight(kind, owner_level, stars, theme, strength, mix, minute)
		if evening != null:
			weight *= evening.evening_guest_multipliers.get(kind.id, 1.0)
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
		stars: float, theme: StringName = &"", strength: float = 0.0,
		mix: Dictionary[StringName, float] = {}) -> float:
	if catalogue == null or owner_level < 1 or not catalogue.is_valid() or not is_finite(stars):
		return 1.0
	var total_weight: float = 0.0
	var total_budget: float = 0.0
	for kind: CustomerType in catalogue.types:
		var weight: float = arrival_weight(kind, owner_level, stars, theme, strength, mix)
		total_weight += weight
		total_budget += weight * kind.budget_multiplier
	if total_weight <= 0.0 or not is_finite(total_weight) or not is_finite(total_budget):
		return 1.0
	var budget: float = total_budget / total_weight
	return budget if is_finite(budget) and budget > 0.0 else 1.0


## One type's relative arrival weight. With no mix (the home shop) this is
## exactly the reputation weight, so home arrivals keep their old stream; the
## location types have zero reputation weight and never arrive there.
static func arrival_weight(kind: CustomerType, owner_level: int, stars: float,
		theme: StringName = &"", strength: float = 0.0,
		mix: Dictionary[StringName, float] = {}, minute: int = -1) -> float:
	if kind == null or kind.unlock_level > owner_level:
		return 0.0
	var weight: float = kind.weight_for_stars(stars)
	if not mix.is_empty():
		var share: float = mix.get(kind.id, 0.0)
		weight = share if is_finite(share) and share > 0.0 and kind.is_valid() else 0.0
	var liking: float = kind.theme_multiplier(theme, strength)
	if liking != 1.0:
		weight *= liking
	var window: float = kind.window_multiplier(minute)
	return weight * window if window != 1.0 else weight
