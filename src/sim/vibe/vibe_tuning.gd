class_name VibeTuning
extends Resource
## Authored restaurant ambience weights. The model never changes this resource.
## Values in data/balance/vibe.tres are provisional until the balance probe runs.

const KNOWN_THEMES: Array[StringName] = [&"cosy", &"modern", &"rustic", &"diner", &"seafood", &"cafe", &"bar"]

@export var score_cap: float = 100.0
## Copy N contributes charm * repeat_decay^(N - 1).
@export var repeat_decay: float = 0.5
## The starter plant and its one decor kind should not change today's balance.
@export var free_charm: float = 2.0
@export var free_variety: int = 1
@export var decor_points_per_charm: float = 6.0
@export var decor_cap: float = 60.0
@export var variety_points_per_kind: float = 6.0
@export var variety_cap: float = 20.0
## Lamps are DECOR items partitioned out of the ordinary decor component.
## Empty until lamp content is approved; never guess a lamp from its name.
@export var lamp_item_ids: Array[StringName] = []
@export var lamp_points_per_charm: float = 6.0
@export var lamp_cap: float = 10.0
@export var theme_cap: float = 15.0
## Excess effective charm beyond the free allowance needed for full theme points.
@export var theme_full_charm: float = 4.0
## Utility equipment's existing diner tags must not outweigh the room's style.
@export var theme_category_weights: Dictionary[int, float] = {
	ItemDef.Category.DOOR: 0.0,
	ItemDef.Category.TABLE: 1.0,
	ItemDef.Category.CHAIR: 1.0,
	ItemDef.Category.STATION: 0.0,
	ItemDef.Category.STORAGE: 0.0,
	ItemDef.Category.PASS: 0.0,
	ItemDef.Category.DECOR: 1.0,
}
## Per-item overrides of the category weight (FK-083): a coffee machine or a
## drinks shelf is equipment, yet it says "café" or "bar" more than a stove
## says "diner". Items not listed keep their category's weight.
@export var theme_item_weights: Dictionary[StringName, float] = {}
@export var theme_paint_weight: float = 0.25
@export var theme_menu_weight: float = 0.25
@export var theme_min_share: float = 0.6
## A menu alone cannot establish a restaurant theme.
@export var theme_min_layout_weight: float = 1.0
## Explicit tie order, independent of placement, dictionary or menu order.
@export var theme_order: Array[StringName] = [&"cosy", &"modern", &"rustic", &"diner", &"seafood", &"cafe", &"bar"]
@export var theme_labels: Dictionary[StringName, String] = {
	&"cosy": "Cosy", &"modern": "Modern", &"rustic": "Rustic",
	&"diner": "Diner", &"seafood": "Seafood", &"cafe": "Café", &"bar": "Bar",
}
@export var no_theme_label: String = "No theme"
@export var crowding_start_density: float = 0.35
@export var crowding_cap: float = 10.0
@export var max_patience_bonus: float = 0.15
@export var max_review_bonus: float = 0.4


## Rejects invalid authoring instead of clamping NaN or silently changing rules.
func is_valid() -> bool:
	for value: float in [score_cap, repeat_decay, free_charm, decor_points_per_charm,
			decor_cap, variety_points_per_kind, variety_cap, lamp_points_per_charm,
			lamp_cap, theme_cap, theme_full_charm, theme_paint_weight, theme_menu_weight, theme_min_share,
			theme_min_layout_weight, crowding_start_density, crowding_cap,
			max_patience_bonus, max_review_bonus]:
		if not is_finite(value) or value < 0.0:
			return false
	if score_cap <= 0.0 or score_cap > 100.0 or repeat_decay >= 1.0 or free_variety < 0 or theme_full_charm <= 0.0:
		return false
	for cap: float in [decor_cap, variety_cap, lamp_cap, theme_cap, crowding_cap]:
		if cap > score_cap:
			return false
	if theme_min_share <= 0.5 or theme_min_share > 1.0 or theme_min_layout_weight <= 0.0 \
			or crowding_start_density >= 1.0 or no_theme_label.strip_edges().is_empty():
		return false
	if theme_order.size() != KNOWN_THEMES.size() or theme_labels.size() != KNOWN_THEMES.size():
		return false
	var seen_themes: Dictionary[StringName, bool] = {}
	for theme: StringName in theme_order:
		if not KNOWN_THEMES.has(theme) or seen_themes.has(theme) or not theme_labels.has(theme) \
				or theme_labels[theme].strip_edges().is_empty():
			return false
		seen_themes[theme] = true
	if theme_category_weights.size() != ItemDef.Category.size():
		return false
	var smallest_weight: float = INF
	for category: int in theme_category_weights:
		var weight: float = theme_category_weights[category]
		if not ItemDef.Category.values().has(category) or not is_finite(weight) or weight < 0.0:
			return false
		if weight > 0.0:
			smallest_weight = minf(smallest_weight, weight)
	if not is_finite(smallest_weight) or theme_menu_weight >= smallest_weight:
		return false
	for item_id: StringName in theme_item_weights:
		var item_weight: float = theme_item_weights[item_id]
		if String(item_id).strip_edges().is_empty() or not is_finite(item_weight) or item_weight < 0.0:
			return false
	var seen_lamps: Dictionary[StringName, bool] = {}
	for item_id: StringName in lamp_item_ids:
		if String(item_id).strip_edges().is_empty() or seen_lamps.has(item_id):
			return false
		seen_lamps[item_id] = true
	return true
