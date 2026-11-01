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
## Below this owner level the type always arrives alone and draws exactly what
## a single guest draws, so play below the unlock matches single-guest main.
@export var party_unlock_level: int = 1
## Short player-facing tip for the level-up report when groups start visiting.
@export var party_tip: String = ""
@export var review_chance_multiplier: float = 1.0
@export var unlock_level: int = 1
@export var weight_at_one_star: float = 0.0
@export var weight_at_five_stars: float = 0.0
## Chance that a guest who came to eat also orders a drink, once drinks are
## on today's menu and their station stands (FK-083). Never drawn otherwise.
@export_range(0.0, 1.0, 0.01) var drink_add_chance: float = 0.0
## Chance that a coffee-only guest adds a pastry (a dish served with drinks)
## while one is on the menu. Never drawn otherwise.
@export_range(0.0, 1.0, 0.01) var pastry_add_chance: float = 0.0
## Chance that a guest needs the restroom after ordering (FK-101). Drawn only
## in a shop with a restroom or at the restroom seat threshold.
@export_range(0.0, 1.0, 0.01) var restroom_chance: float = 0.25
## Multiplies the time-of-day weight of each drinks-only visit kind
## (RecipeDef.COFFEE, RecipeDef.DRINKS). Missing kinds count 1.0.
@export var visit_weights: Dictionary[StringName, float] = {}
## Vibe themes this type is drawn to: while one of them is the room's theme,
## the type's arrival weight grows by up to liked_theme_bonus (FK-083).
@export var liked_themes: Array[StringName] = []
@export var liked_theme_bonus: float = 0.0


func is_valid() -> bool:
	if id.is_empty() or display_name.strip_edges().is_empty() or unlock_level < 1:
		return false
	if party_size_min < 1 or party_size_max < party_size_min or party_size_max > Party.MAX_SIZE:
		return false
	if party_unlock_level < 1:
		return false
	for value: float in [budget_multiplier, patience_multiplier,
			review_chance_multiplier]:
		if not is_finite(value) or value <= 0.0:
			return false
	for value: float in [quality_weight, weight_at_one_star,
			weight_at_five_stars, liked_theme_bonus]:
		if not is_finite(value) or value < 0.0:
			return false
	for chance: float in [drink_add_chance, pastry_add_chance, restroom_chance]:
		if not is_finite(chance) or chance < 0.0 or chance > 1.0:
			return false
	for kind: StringName in visit_weights:
		var weight: float = visit_weights[kind]
		if not RecipeDef.ORDER_TYPES.has(kind) or not is_finite(weight) or weight < 0.0:
			return false
	return true


## The multiplier for a visit kind; food and unlisted kinds stay neutral.
func visit_weight(kind: StringName) -> float:
	return visit_weights.get(kind, 1.0)


## Arrival-weight multiplier for the room's theme. Exactly 1.0 unless the
## active theme is liked, so ordinary arrivals keep their exact weights.
func theme_multiplier(theme: StringName, strength: float) -> float:
	if theme.is_empty() or not liked_themes.has(theme) or liked_theme_bonus <= 0.0 \
			or not is_finite(strength) or strength <= 0.0:
		return 1.0
	return 1.0 + liked_theme_bonus * clampf(strength, 0.0, 1.0)


## Fixed sizes consume no draw, preserving the single-guest arrival stream.
## The spawner supplies its existing seeded customers stream for a range.
func draw_party_size(random: RandomNumberGenerator) -> int:
	if not is_valid() or random == null:
		return 0
	if party_size_min == party_size_max:
		return party_size_min
	return random.randi_range(party_size_min, party_size_max)


## A locked type is a single guest and consumes no size draw.
func draw_party_size_at(random: RandomNumberGenerator, owner_level: int) -> int:
	if not is_valid() or random == null:
		return 0
	return draw_party_size(random) if owner_level >= party_unlock_level else 1


## Growth blends the authored uniform range with the demand weights, extending
## unlocked groups (including a fixed solo range) up to the tuning's maximum.
## Neutral and invalid contexts
## delegate before any new draw, retaining the original fixed/locked streams.
func draw_party_size_for_demand(random: RandomNumberGenerator, owner_level: int,
		demand_factor: float, tuning: DemandTuning) -> int:
	if not is_finite(demand_factor) or demand_factor <= 1.0 \
			or owner_level < party_unlock_level or not is_valid() or random == null:
		return draw_party_size_at(random, owner_level)
	if tuning == null or not tuning.is_valid() or tuning.party_max_size < party_size_max:
		return draw_party_size_at(random, owner_level)
	var growth_total: float = 0.0
	for size: int in range(party_size_min, tuning.party_max_size + 1):
		growth_total += tuning.party_size_weights[size - 1]
	if not is_finite(growth_total) or growth_total <= 0.0:
		return draw_party_size_at(random, owner_level)
	# Compare first so even a very large finite factor cannot overflow the ratio.
	var blend: float = 1.0 if demand_factor >= tuning.party_growth_full_factor \
		else (demand_factor - 1.0) / (tuning.party_growth_full_factor - 1.0)
	var baseline_weight: float = 1.0 / float(party_size_max - party_size_min + 1)
	var weights: Array[float] = []
	var total: float = 0.0
	var positive_bins: int = 0
	var last_positive: int = party_size_min
	for size: int in range(party_size_min, tuning.party_max_size + 1):
		var baseline: float = baseline_weight if size <= party_size_max else 0.0
		var growth: float = tuning.party_size_weights[size - 1] / growth_total
		var weight: float = (1.0 - blend) * baseline + blend * growth
		weights.append(weight)
		total += weight
		if weight > 0.0:
			positive_bins += 1
			last_positive = size
	if not is_finite(total) or total <= 0.0:
		return draw_party_size_at(random, owner_level)
	if positive_bins == 1:
		return last_positive
	var ticket: float = random.randf() * total
	for index: int in weights.size():
		if weights[index] <= 0.0:
			continue
		ticket -= weights[index]
		if ticket < 0.0:
			return party_size_min + index
	# randf() may return its upper endpoint; a zero-weight final bin stays absent.
	return last_positive


## The owner level at which this type first arrives as a group (0 if never).
func group_level() -> int:
	return maxi(unlock_level, party_unlock_level) if party_size_max > 1 else 0


## Reputation below one star uses the one-star weight; above five uses five.
func weight_for_stars(stars: float) -> float:
	if not is_valid() or not is_finite(stars):
		return 0.0
	var t: float = (clampf(stars, 1.0, 5.0) - 1.0) / 4.0
	return lerpf(weight_at_one_star, weight_at_five_stars, t)
