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
	if party_size_min < 1 or party_size_max < party_size_min or party_size_max > 4:
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
	for chance: float in [drink_add_chance, pastry_add_chance]:
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


## The owner level at which this type first arrives as a group (0 if never).
func group_level() -> int:
	return maxi(unlock_level, party_unlock_level) if party_size_max > 1 else 0


## Reputation below one star uses the one-star weight; above five uses five.
func weight_for_stars(stars: float) -> float:
	if not is_valid() or not is_finite(stars):
		return 0.0
	var t: float = (clampf(stars, 1.0, 5.0) - 1.0) / 4.0
	return lerpf(weight_at_one_star, weight_at_five_stars, t)
