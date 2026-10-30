class_name VibeModel
extends RefCounted
## Pure, derived restaurant ambience. Call after layout, paint or menu changes,
## and again on load; no ticks, random draws, nodes or saved state belong here.

## Detached placed-item input. Cells are absolute occupied footprint cells.
## DECOR and hung RESTROOM accents earn charm/variety; other items may vote for themes.
class Item extends RefCounted:
	var definition_id: StringName = &""
	var charm: float = 0.0
	var category: int = ItemDef.Category.DECOR
	var theme_tags: Array[StringName] = []
	## Explicit tags supplied by a future paint adapter, not guessed swatch IDs.
	var paint_theme_tags: Array[StringName] = []
	var cells: Array[Vector2i] = []
	## Rugs can add charm/style but never consume another layer's floor space.
	var floor_decor: bool = false

## The caller supplies today's enabled recipes only, once per recipe ID.
class Dish extends RefCounted:
	var id: StringName = &""
	var theme_tags: Array[StringName] = []

class Inputs extends RefCounted:
	var items: Array[Item] = []
	var menu: Array[Dish] = []
	## Interior FLOOR cells only; repeated cells are harmless.
	var floor_cells: Array[Vector2i] = []
	var wall_paint_theme_tags: Array[StringName] = []
	var floor_paint_theme_tags: Array[StringName] = []

## Transient readable breakdown and bounded effects. No result is serialized.
## Invalid input returns a neutral result, without partially computed effects.
class Result extends RefCounted:
	var valid: bool = false
	var reason: String = ""
	var score: float = 0.0
	var decor_points: float = 0.0
	var variety_points: float = 0.0
	var theme_points: float = 0.0
	var lamp_points: float = 0.0
	var crowding_penalty: float = 0.0
	var active_theme: StringName = &""
	var theme_label: String = ""
	var theme_share: float = 0.0
	var patience_multiplier: float = 1.0
	## Unrounded additive review term; integer-star integration is separate.
	var raw_review_bonus: float = 0.0
	## Strength only: customer-type selection and randomness remain with #111.
	var arrival_theme_strength: float = 0.0
	var interior_cells: int = 0
	var occupied_normal_cells: int = 0
	var crowding_density: float = 0.0

class _Group extends RefCounted:
	var charm: float = 0.0
	var category: int = ItemDef.Category.DECOR
	var tags: Array[StringName] = []
	var floor_decor: bool = false
	var count: int = 0
	var paint_sources: int = 0
	var paint_votes: Dictionary[StringName, int] = {}

class _Collected extends RefCounted:
	var reason: String = ""
	var groups: Dictionary[StringName, _Group] = {}
	var dishes: Dictionary[StringName, Dish] = {}
	var floor_cells: Dictionary[Vector2i, bool] = {}
	var occupied_cells: Dictionary[Vector2i, bool] = {}

class _Themes extends RefCounted:
	var votes: Dictionary[StringName, float] = {}
	var source_weight: float = 0.0
	var layout_weight: float = 0.0


## Aggregates in definition/recipe order, so permutations do not change floats,
## dominant-theme ties or effects. Caller-owned records/arrays remain untouched.
static func evaluate(inputs: Inputs, tuning: VibeTuning) -> Result:
	if tuning == null or not tuning.is_valid():
		return _invalid("The vibe tuning is invalid")
	if inputs == null:
		return _invalid("The shop layout is unavailable")
	var collected: _Collected = _collect(inputs, tuning)
	if not collected.reason.is_empty():
		return _invalid(collected.reason)
	var result: Result = Result.new()
	result.theme_label = tuning.no_theme_label
	var themes: _Themes = _Themes.new()
	for theme: StringName in tuning.theme_order:
		themes.votes[theme] = 0.0
	var decor_charm: float = 0.0
	var lamp_charm: float = 0.0
	var varieties: int = 0
	## StringName compares interned pointers; sort Strings for cross-run order.
	var ids: Array[String] = []
	for group_id: StringName in collected.groups:
		ids.append(String(group_id))
	ids.sort()
	for id_text: String in ids:
		var item_id: StringName = StringName(id_text)
		var group: _Group = collected.groups[item_id]
		if (group.category == ItemDef.Category.DECOR or
				(group.category == ItemDef.Category.RESTROOM and group.floor_decor)) and group.charm > 0.0:
			var charm: float = group.charm * (1.0 - pow(tuning.repeat_decay, group.count)) \
				/ (1.0 - tuning.repeat_decay)
			if not is_finite(charm):
				return _invalid("The vibe amounts are too large")
			if tuning.lamp_item_ids.has(item_id):
				lamp_charm += charm
			else:
				decor_charm += charm
			varieties += 1
		var weight: float = tuning.theme_item_weights.get(item_id, tuning.theme_category_weights[group.category])
		if not _add_tags(themes, group.tags, weight, group.count, true) \
				or not _add_item_paint(themes, group, tuning):
			return _invalid("The vibe amounts are too large")
	var total_charm: float = decor_charm + lamp_charm
	if not is_finite(total_charm):
		return _invalid("The vibe amounts are too large")
	## Share the starter allowance between ordinary decor and lamps exactly once.
	var excess_charm: float = maxf(0.0, total_charm - tuning.free_charm)
	var charm_share: float = excess_charm / total_charm if total_charm > 0.0 else 0.0
	var decor_amount: float = decor_charm * charm_share * tuning.decor_points_per_charm
	var lamp_amount: float = lamp_charm * charm_share * tuning.lamp_points_per_charm
	var variety_amount: float = float(maxi(0, varieties - tuning.free_variety)) * tuning.variety_points_per_kind
	if not is_finite(decor_amount) or not is_finite(lamp_amount) or not is_finite(variety_amount):
		return _invalid("The vibe amounts are too large")
	result.decor_points = minf(tuning.decor_cap, decor_amount)
	result.lamp_points = minf(tuning.lamp_cap, lamp_amount)
	result.variety_points = minf(tuning.variety_cap, variety_amount)
	if not _add_tags(themes, _known_tags(inputs.wall_paint_theme_tags, tuning), tuning.theme_paint_weight, 1, true) \
			or not _add_tags(themes, _known_tags(inputs.floor_paint_theme_tags, tuning), tuning.theme_paint_weight, 1, true):
		return _invalid("The vibe amounts are too large")
	var dish_ids: Array[String] = []
	for menu_id: StringName in collected.dishes:
		dish_ids.append(String(menu_id))
	dish_ids.sort()
	for dish_text: String in dish_ids:
		var dish_id: StringName = StringName(dish_text)
		if not _add_tags(themes, _known_tags(collected.dishes[dish_id].theme_tags, tuning), tuning.theme_menu_weight, 1, false):
			return _invalid("The vibe amounts are too large")
	_choose_theme(result, themes, tuning, excess_charm)
	result.interior_cells = collected.floor_cells.size()
	result.occupied_normal_cells = collected.occupied_cells.size()
	if result.interior_cells > 0:
		result.crowding_density = float(result.occupied_normal_cells) / float(result.interior_cells)
	var crowding_fraction: float = clampf((result.crowding_density - tuning.crowding_start_density) \
		/ (1.0 - tuning.crowding_start_density), 0.0, 1.0)
	result.crowding_penalty = crowding_fraction * tuning.crowding_cap
	result.score = clampf(result.decor_points + result.variety_points + result.theme_points \
		+ result.lamp_points - result.crowding_penalty, 0.0, tuning.score_cap)
	var strength: float = result.score / tuning.score_cap
	result.patience_multiplier = 1.0 + strength * tuning.max_patience_bonus
	result.raw_review_bonus = strength * tuning.max_review_bonus
	if not result.active_theme.is_empty():
		result.arrival_theme_strength = strength * result.theme_share
	result.valid = true
	return result


static func _collect(inputs: Inputs, tuning: VibeTuning) -> _Collected:
	var collected: _Collected = _Collected.new()
	for cell: Vector2i in inputs.floor_cells:
		collected.floor_cells[cell] = true
	for item: Item in inputs.items:
		if item == null or String(item.definition_id).strip_edges().is_empty() \
				or not is_finite(item.charm) or item.charm < 0.0 \
				or not ItemDef.Category.values().has(item.category):
			collected.reason = "A placed item has invalid vibe data"
			return collected
		var tags: Array[StringName] = _known_tags(item.theme_tags, tuning)
		var group: _Group = collected.groups.get(item.definition_id)
		if group == null:
			group = _Group.new()
			group.charm = item.charm
			group.category = item.category
			group.tags = tags
			group.floor_decor = item.floor_decor
			collected.groups[item.definition_id] = group
		elif group.charm != item.charm or group.category != item.category \
				or group.tags != tags or group.floor_decor != item.floor_decor:
			collected.reason = "Copies of an item have different vibe data"
			return collected
		group.count += 1
		var paint_tags: Array[StringName] = _known_tags(item.paint_theme_tags, tuning)
		if not paint_tags.is_empty():
			group.paint_sources += 1
			for theme: StringName in paint_tags:
				group.paint_votes[theme] = group.paint_votes.get(theme, 0) + 1
		if not item.floor_decor:
			for cell: Vector2i in item.cells:
				if collected.floor_cells.has(cell):
					collected.occupied_cells[cell] = true
	for dish: Dish in inputs.menu:
		if dish == null or String(dish.id).strip_edges().is_empty() or collected.dishes.has(dish.id):
			collected.reason = "Today's menu has invalid vibe data"
			return collected
		collected.dishes[dish.id] = dish
	return collected


## Normalizing against authored order also removes duplicate/unknown tags.
static func _known_tags(tags: Array[StringName], tuning: VibeTuning) -> Array[StringName]:
	var known: Array[StringName] = []
	for theme: StringName in tuning.theme_order:
		if tags.has(theme):
			known.append(theme)
	return known


## A source with several tags casts one vote for each, with one denominator.
## Only sources with known tags contribute, as the brief says "tagged items".
static func _add_tags(themes: _Themes, tags: Array[StringName], weight: float, count: int, layout: bool) -> bool:
	if tags.is_empty() or weight == 0.0:
		return true
	var amount: float = weight * float(count)
	themes.source_weight += amount
	if layout:
		themes.layout_weight += amount
	for theme: StringName in tags:
		themes.votes[theme] += amount
		if not is_finite(themes.votes[theme]):
			return false
	return is_finite(themes.source_weight) and is_finite(themes.layout_weight)


static func _add_item_paint(themes: _Themes, group: _Group, tuning: VibeTuning) -> bool:
	var amount: float = tuning.theme_paint_weight * float(group.paint_sources)
	themes.source_weight += amount
	themes.layout_weight += amount
	for theme: StringName in tuning.theme_order:
		themes.votes[theme] += tuning.theme_paint_weight * float(group.paint_votes.get(theme, 0))
		if not is_finite(themes.votes[theme]):
			return false
	return is_finite(themes.source_weight) and is_finite(themes.layout_weight)


static func _choose_theme(result: Result, themes: _Themes, tuning: VibeTuning, excess_charm: float) -> void:
	if themes.source_weight <= 0.0 or themes.layout_weight < tuning.theme_min_layout_weight:
		return
	var best_vote: float = 0.0
	var best_theme: StringName = &""
	for theme: StringName in tuning.theme_order:
		if themes.votes[theme] > best_vote:
			best_theme = theme
			best_vote = themes.votes[theme]
	var share: float = clampf(best_vote / themes.source_weight, 0.0, 1.0)
	result.theme_share = share
	if share < tuning.theme_min_share:
		return
	result.active_theme = best_theme
	result.theme_label = tuning.theme_labels[best_theme]
	## The starter allowance stays neutral; additional decor ramps the bonus
	## instead of granting a full theme cap as soon as one extra copy is placed.
	if excess_charm > 0.0:
		result.theme_points = share * tuning.theme_cap * minf(1.0, excess_charm / tuning.theme_full_charm)


static func _invalid(reason: String) -> Result:
	var result: Result = Result.new()
	result.reason = reason
	return result
