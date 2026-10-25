extends TestCase
## Vibe scoring is pure derived data over detached shop and menu inputs.

const TUNING: VibeTuning = preload("res://data/balance/vibe.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray(), "content loads")


func after_each() -> void:
	_content = null


func test_repeated_decor_keeps_diminishing_marginal_charm() -> void:
	var one: VibeModel.Result = _evaluate([
		_item(&"repeatable", 2.0, [], [Vector2i(1, 1)]),
	])
	var two: VibeModel.Result = _evaluate([
		_item(&"repeatable", 2.0, [], [Vector2i(1, 1)]),
		_item(&"repeatable", 2.0, [], [Vector2i(2, 1)]),
	])
	var three: VibeModel.Result = _evaluate([
		_item(&"repeatable", 2.0, [], [Vector2i(1, 1)]),
		_item(&"repeatable", 2.0, [], [Vector2i(2, 1)]),
		_item(&"repeatable", 2.0, [], [Vector2i(3, 1)]),
	])
	assert_true(one.valid)
	assert_true(two.valid)
	assert_true(three.valid)
	var second_gain: float = two.decor_points - one.decor_points
	var third_gain: float = three.decor_points - two.decor_points
	assert_true(second_gain > 0.0, "a repeated copy still adds some charm")
	assert_true(third_gain > 0.0, "repeat decay does not erase all later copies")
	assert_true(third_gain < second_gain, "each repeated copy contributes less than the previous one")


func test_distinct_decor_earns_variety_more_than_repeating_one_kind() -> void:
	var repeated: VibeModel.Result = _evaluate([
		_item(&"first_kind", 2.0, [], [Vector2i(1, 1)]),
		_item(&"first_kind", 2.0, [], [Vector2i(2, 1)]),
	])
	var varied: VibeModel.Result = _evaluate([
		_item(&"first_kind", 2.0, [], [Vector2i(1, 1)]),
		_item(&"second_kind", 2.0, [], [Vector2i(2, 1)]),
	])
	assert_true(repeated.valid)
	assert_true(varied.valid)
	assert_true(varied.variety_points > repeated.variety_points)
	assert_true(varied.score > repeated.score)


func test_seafood_theme_detection_is_order_independent_and_ties_are_stable() -> void:
	var majority: Array[VibeModel.Item] = [
		_item(&"seafood_one", 3.0, [&"seafood"], [Vector2i(1, 1)]),
		_item(&"seafood_two", 3.0, [&"seafood"], [Vector2i(2, 1)]),
		_item(&"cosy_one", 3.0, [&"cosy"], [Vector2i(3, 1)]),
	]
	var forward: VibeModel.Result = _evaluate(majority)
	var reversed_items: Array[VibeModel.Item] = majority.duplicate()
	reversed_items.reverse()
	var reversed: VibeModel.Result = _evaluate(reversed_items)
	assert_true(forward.valid)
	assert_eq(forward.active_theme, &"seafood")
	assert_eq(forward.theme_label, "Seafood")
	assert_eq(_result_signature(forward), _result_signature(reversed),
		"changing input order does not change theme choice or score")

	var tie_items: Array[VibeModel.Item] = [
		_item(&"tie_seafood", 3.0, [&"seafood"], [Vector2i(1, 1)]),
		_item(&"tie_cosy", 3.0, [&"cosy"], [Vector2i(2, 1)]),
	]
	var tie_forward: VibeModel.Result = _evaluate(tie_items)
	tie_items.reverse()
	var tie_reverse: VibeModel.Result = _evaluate(tie_items)
	assert_eq(_result_signature(tie_forward), _result_signature(tie_reverse),
		"a tied theme is resolved consistently regardless of source order")
	assert_eq(tie_forward.active_theme, &"")


func test_active_multitag_ties_follow_the_authored_theme_order() -> void:
	var tied_items: Array[VibeModel.Item] = [
		_item(&"multi_tag_one", 3.0, [&"seafood", &"cosy"], [Vector2i(1, 1)]),
		_item(&"multi_tag_two", 3.0, [&"cosy", &"seafood"], [Vector2i(2, 1)]),
	]
	var default_order: VibeModel.Result = _evaluate(tied_items)
	assert_true(default_order.valid)
	assert_almost_eq(default_order.theme_share, 1.0)
	assert_eq(default_order.active_theme, &"cosy", "the authored first theme wins an active tie")

	var reversed_items: Array[VibeModel.Item] = tied_items.duplicate()
	reversed_items.reverse()
	var reordered: VibeModel.Result = _evaluate(reversed_items)
	assert_eq(_result_signature(reordered), _result_signature(default_order),
		"item and tag order cannot change the authored tie winner")

	var seafood_first: VibeTuning = TUNING.duplicate(true) as VibeTuning
	seafood_first.theme_order = [&"seafood", &"cosy", &"modern", &"rustic", &"diner"]
	assert_true(seafood_first.is_valid())
	var data_ordered: VibeModel.Result = VibeModel.evaluate(_inputs(tied_items), seafood_first)
	assert_true(data_ordered.valid)
	assert_eq(data_ordered.active_theme, &"seafood", "tuning order controls a genuine tie")


func test_menu_only_theme_agreement_cannot_activate_a_room_theme() -> void:
	var menu: Array[VibeModel.Dish] = []
	for index: int in range(4):
		menu.append(_dish(StringName("seafood_menu_%d" % index), [&"seafood"]))
	var result: VibeModel.Result = _evaluate([], menu)
	assert_true(result.valid)
	assert_eq(result.theme_share, 0.0)
	_assert_neutral(result)


func test_menu_tags_have_lower_weight_than_decor_and_paint_tags_contribute() -> void:
	var competing: Array[VibeModel.Item] = [
		_item(&"cozy_decor", 3.0, [&"cosy"], [Vector2i(1, 1)]),
		_item(&"modern_decor", 3.0, [&"modern"], [Vector2i(2, 1)]),
	]
	var one_menu: Array[VibeModel.Dish] = [_dish(&"menu_cozy", [&"cosy"])]
	var one_menu_result: VibeModel.Result = _evaluate(competing, one_menu)
	assert_true(one_menu_result.valid)
	assert_eq(one_menu_result.active_theme, &"",
		"one lower-weight menu tag cannot outweigh the tied decor sources")

	var two_decor: Array[VibeModel.Item] = competing.duplicate()
	two_decor.append(_item(&"second_cozy_decor", 3.0, [&"cosy"], [Vector2i(3, 1)]))
	var two_decor_result: VibeModel.Result = _evaluate(two_decor)
	assert_true(two_decor_result.valid)
	assert_eq(two_decor_result.active_theme, &"cosy",
		"one equally weighted decor source moves the same room past the theme threshold")

	var four_menu: Array[VibeModel.Dish] = []
	for index: int in range(4):
		four_menu.append(_dish(StringName("menu_cozy_%d" % index), [&"cosy"]))
	var four_menu_result: VibeModel.Result = _evaluate(competing, four_menu)
	assert_true(four_menu_result.valid)
	assert_eq(four_menu_result.active_theme, &"cosy",
		"four unique quarter-weight menu sources contribute the same vote as one decor source")

	var painted: VibeModel.Inputs = _inputs(competing)
	painted.items[0].paint_theme_tags = [&"cosy"]
	painted.wall_paint_theme_tags = [&"cosy"]
	painted.floor_paint_theme_tags = [&"cosy"]
	var painted_result: VibeModel.Result = VibeModel.evaluate(painted, TUNING)
	assert_true(painted_result.valid)
	assert_eq(painted_result.active_theme, &"cosy",
		"item, wall and floor paint tags contribute to a player-designed theme")


func test_duplicate_theme_tags_do_not_gain_extra_votes() -> void:
	var single: VibeModel.Result = _evaluate([
		_item(&"duplicate_tag", 4.0, [&"cosy"], [Vector2i(1, 1)]),
		_item(&"other_theme", 3.0, [&"modern"], [Vector2i(2, 1)]),
	])
	var duplicated: VibeModel.Result = _evaluate([
		_item(&"duplicate_tag", 4.0, [&"cosy", &"cosy", &"cosy"], [Vector2i(1, 1)]),
		_item(&"other_theme", 3.0, [&"modern"], [Vector2i(2, 1)]),
	])
	assert_eq(_result_signature(duplicated), _result_signature(single),
		"a source's repeated tag is counted once")


func test_crowding_uses_normal_cell_union_and_ignores_floor_rug_overlay() -> void:
	var floor_cells: Array[Vector2i] = []
	for x: int in range(10):
		floor_cells.append(Vector2i(x, 0))
	var first: VibeModel.Item = _item(&"normal_one", 0.0, [], [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 0),
	], ItemDef.Category.TABLE)
	var second: VibeModel.Item = _item(&"normal_two", 0.0, [], [
		Vector2i(2, 0), Vector2i(3, 0),
	], ItemDef.Category.CHAIR)
	var without_rug: VibeModel.Inputs = _inputs([first, second])
	without_rug.floor_cells = floor_cells.duplicate()
	var crowded: VibeModel.Result = VibeModel.evaluate(without_rug, TUNING)
	assert_true(crowded.valid)
	assert_eq(crowded.interior_cells, 10)
	assert_eq(crowded.occupied_normal_cells, 4,
		"overlapping and duplicate normal cells count once")
	assert_almost_eq(crowded.crowding_density, 0.4)
	assert_true(crowded.crowding_penalty > 0.0)

	var rug: VibeModel.Item = _item(&"floor_rug", 0.0, [], [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	], ItemDef.Category.DECOR, true)
	var with_rug: VibeModel.Inputs = _inputs([first, second, rug])
	with_rug.floor_cells = floor_cells.duplicate()
	var overlaid: VibeModel.Result = VibeModel.evaluate(with_rug, TUNING)
	assert_true(overlaid.valid)
	assert_eq(overlaid.interior_cells, crowded.interior_cells)
	assert_eq(overlaid.occupied_normal_cells, crowded.occupied_normal_cells)
	assert_almost_eq(overlaid.crowding_density, crowded.crowding_density)
	assert_almost_eq(overlaid.crowding_penalty, crowded.crowding_penalty)


func test_evaluation_is_deterministic_and_does_not_mutate_inputs() -> void:
	var first: VibeModel.Item = _item(&"stable_a", 3.0, [&"cosy", &"seafood"], [Vector2i(1, 1)])
	var second: VibeModel.Item = _item(&"stable_b", 3.0, [&"cosy"], [Vector2i(2, 1)])
	var inputs: VibeModel.Inputs = _inputs([first, second], [_dish(&"soup", [&"seafood"])])
	inputs.wall_paint_theme_tags = [&"cosy", &"modern"]
	inputs.floor_paint_theme_tags = [&"seafood"]
	var before: Dictionary = _inputs_signature(inputs)
	var result: VibeModel.Result = VibeModel.evaluate(inputs, TUNING)
	var replay: VibeModel.Result = VibeModel.evaluate(inputs, TUNING)
	assert_true(result.valid)
	assert_eq(_result_signature(result), _result_signature(replay))
	assert_eq(_inputs_signature(inputs), before, "evaluation leaves every input field untouched")


func test_score_and_effects_are_finite_monotone_and_capped() -> void:
	var quiet: VibeModel.Result = _evaluate([])
	var lavish_items: Array[VibeModel.Item] = []
	for index: int in range(12):
		lavish_items.append(_item(StringName("lavish_%d" % index), 100.0, [&"seafood"],
			[Vector2i(index, 1)]))
	var lavish: VibeModel.Result = _evaluate(lavish_items)
	assert_true(quiet.valid)
	assert_true(lavish.valid)
	for result: VibeModel.Result in [quiet, lavish]:
		for value: float in [result.score, result.decor_points, result.variety_points,
				result.theme_points, result.lamp_points, result.crowding_penalty,
				result.theme_share, result.patience_multiplier, result.raw_review_bonus,
				result.arrival_theme_strength, result.crowding_density]:
			assert_true(is_finite(value), "every exposed score/effect is finite")
		assert_true(result.score >= 0.0 and result.score <= TUNING.score_cap)
		assert_true(result.decor_points <= TUNING.decor_cap)
		assert_true(result.variety_points <= TUNING.variety_cap)
		assert_true(result.theme_points <= TUNING.theme_cap)
		assert_true(result.lamp_points <= TUNING.lamp_cap)
		assert_true(result.crowding_penalty <= TUNING.crowding_cap)
		assert_true(result.theme_share >= 0.0 and result.theme_share <= 1.0)
		assert_true(result.crowding_density >= 0.0 and result.crowding_density <= 1.0)
		assert_true(result.patience_multiplier >= 1.0)
		assert_true(result.patience_multiplier <= 1.0 + TUNING.max_patience_bonus)
		assert_true(result.raw_review_bonus >= 0.0)
		assert_true(result.raw_review_bonus <= TUNING.max_review_bonus)
		assert_true(result.arrival_theme_strength >= 0.0 and result.arrival_theme_strength <= 1.0)
	assert_almost_eq(quiet.patience_multiplier, 1.0)
	assert_almost_eq(quiet.raw_review_bonus, 0.0)
	assert_almost_eq(quiet.arrival_theme_strength, 0.0)
	assert_true(lavish.score > quiet.score)
	assert_true(lavish.patience_multiplier > quiet.patience_multiplier)
	assert_true(lavish.raw_review_bonus > quiet.raw_review_bonus)
	assert_true(lavish.arrival_theme_strength > quiet.arrival_theme_strength)


func test_only_authored_lamp_ids_use_the_lamp_charm_component() -> void:
	var tuning: VibeTuning = TUNING.duplicate(true) as VibeTuning
	tuning.lamp_item_ids = [&"fixture_lamp"]
	assert_true(tuning.is_valid())
	var input: VibeModel.Inputs = _inputs([
		_item(&"fixture_lamp", 4.0, [], [Vector2i(1, 1)]),
	])
	var result: VibeModel.Result = VibeModel.evaluate(input, tuning)
	assert_true(result.valid)
	assert_true(result.lamp_points > 0.0)
	assert_almost_eq(result.decor_points, 0.0)

	var ordinary_tuning: VibeTuning = TUNING.duplicate(true) as VibeTuning
	var ordinary: VibeModel.Result = VibeModel.evaluate(input, ordinary_tuning)
	assert_true(ordinary.valid)
	assert_true(ordinary.decor_points > 0.0)
	assert_almost_eq(ordinary.lamp_points, 0.0)


func test_invalid_input_returns_neutral_result_without_mutation() -> void:
	var bad_item: VibeModel.Item = _item(&"negative_charm", -1.0, [], [Vector2i(1, 1)])
	var inputs: VibeModel.Inputs = _inputs([bad_item])
	var before: Dictionary = _inputs_signature(inputs)
	var result: VibeModel.Result = VibeModel.evaluate(inputs, TUNING)
	assert_false(result.valid)
	assert_false(result.reason.strip_edges().is_empty())
	assert_eq(_inputs_signature(inputs), before)
	_assert_neutral(result)

	var invalid_tuning: VibeTuning = TUNING.duplicate(true) as VibeTuning
	invalid_tuning.theme_menu_weight = -1.0
	var valid_input: VibeModel.Inputs = _inputs([_item(&"valid_decor", 3.0, [&"cosy"], [Vector2i(1, 1)])])
	var bad_tuning_result: VibeModel.Result = VibeModel.evaluate(valid_input, invalid_tuning)
	assert_false(bad_tuning_result.valid)
	assert_false(bad_tuning_result.reason.strip_edges().is_empty())
	_assert_neutral(bad_tuning_result)


func test_conflicting_item_definitions_and_duplicate_menu_ids_are_rejected() -> void:
	var inconsistent: VibeModel.Inputs = _inputs([
		_item(&"same_definition", 1.0, [&"cosy"], [Vector2i(1, 1)]),
		_item(&"same_definition", 2.0, [&"cosy"], [Vector2i(2, 1)]),
	])
	var duplicate_menu: VibeModel.Inputs = _inputs([],
		[_dish(&"same_recipe", [&"seafood"]), _dish(&"same_recipe", [&"cosy"])])
	for invalid_input: VibeModel.Inputs in [inconsistent, duplicate_menu]:
		var before: Dictionary = _inputs_signature(invalid_input)
		var result: VibeModel.Result = VibeModel.evaluate(invalid_input, TUNING)
		assert_false(result.valid)
		assert_false(result.reason.strip_edges().is_empty())
		assert_eq(_inputs_signature(invalid_input), before)
		_assert_neutral(result)


func test_nonfinite_and_overflow_inputs_return_neutral_results() -> void:
	var nan_tuning: VibeTuning = TUNING.duplicate(true) as VibeTuning
	nan_tuning.decor_points_per_charm = NAN
	_assert_invalid_neutral(_inputs([_item(&"finite_input", 3.0, [], [Vector2i(1, 1)])]), nan_tuning)

	var infinite_charm: VibeModel.Inputs = _inputs([
		_item(&"infinite_charm", INF, [], [Vector2i(1, 1)]),
	])
	_assert_invalid_neutral(infinite_charm, TUNING)

	var overflow_charm: VibeModel.Inputs = _inputs([
		_item(&"large_charm_one", 1.0e308, [], [Vector2i(1, 1)]),
		_item(&"large_charm_two", 1.0e308, [], [Vector2i(2, 1)]),
	])
	_assert_invalid_neutral(overflow_charm, TUNING)


func test_positive_charm_on_non_decor_items_does_not_earn_decor_or_variety_points() -> void:
	var result: VibeModel.Result = _evaluate([
		_item(&"fixture_table", 8.0, [&"cosy"], [Vector2i(1, 1)], ItemDef.Category.TABLE),
		_item(&"fixture_station", 8.0, [&"modern"], [Vector2i(2, 1)], ItemDef.Category.STATION),
	])
	assert_true(result.valid)
	assert_eq(result.active_theme, &"cosy", "eligible table tags still establish a theme")
	assert_almost_eq(result.decor_points, 0.0)
	assert_almost_eq(result.variety_points, 0.0)
	assert_almost_eq(result.lamp_points, 0.0)
	assert_almost_eq(result.theme_points, 0.0, 0.0001,
		"theme tags do not grant theme points without positive decor charm")
	assert_almost_eq(result.score, 0.0)
	assert_almost_eq(result.patience_multiplier, 1.0)
	assert_almost_eq(result.raw_review_bonus, 0.0)
	assert_almost_eq(result.arrival_theme_strength, 0.0)

	var decor: VibeModel.Result = _evaluate([
		_item(&"decor_control", 8.0, [&"cosy"], [Vector2i(1, 1)]),
	])
	assert_true(decor.valid)
	assert_true(decor.decor_points > 0.0, "positive DECOR charm still contributes")
	assert_true(decor.score > 0.0)


func test_real_tier_one_shop_has_neutral_vibe_effects() -> void:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 41, errors)
	assert_eq(errors, [] as Array[String], "the starter layout builds cleanly")
	assert_not_null(sim)
	if sim == null:
		return
	var inputs: VibeModel.Inputs = _inputs_from_shop(sim.world, LAYOUT)
	for recipe: RecipeDef in sim.menu:
		var dish: VibeModel.Dish = VibeModel.Dish.new()
		dish.id = recipe.id
		dish.theme_tags = recipe.theme_tags.duplicate()
		inputs.menu.append(dish)
	var result: VibeModel.Result = VibeModel.evaluate(inputs, TUNING)
	assert_true(result.valid)
	assert_almost_eq(result.patience_multiplier, 1.0, 0.0001,
		"the actual starter layout keeps the issue's default patience effect near zero")
	assert_almost_eq(result.raw_review_bonus, 0.0, 0.0001,
		"the actual starter layout keeps the issue's default review effect near zero")
	assert_almost_eq(result.arrival_theme_strength, 0.0, 0.0001,
		"the starter does not auto-select a theme arrival bonus")


func _inputs(items: Array[VibeModel.Item], menu: Array[VibeModel.Dish] = []) -> VibeModel.Inputs:
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	inputs.items = items.duplicate()
	inputs.menu = menu.duplicate()
	inputs.floor_cells = _test_floor_cells()
	return inputs


func _evaluate(items: Array[VibeModel.Item], menu: Array[VibeModel.Dish] = []) -> VibeModel.Result:
	return VibeModel.evaluate(_inputs(items, menu), TUNING)


func _item(id: StringName, charm: float, tags: Array[StringName], cells: Array[Vector2i],
		category: int = ItemDef.Category.DECOR, floor_decor: bool = false,
		paint_tags: Array[StringName] = []) -> VibeModel.Item:
	var item: VibeModel.Item = VibeModel.Item.new()
	item.definition_id = id
	item.charm = charm
	item.category = category
	item.theme_tags = tags.duplicate()
	item.paint_theme_tags = paint_tags.duplicate()
	item.cells = cells.duplicate()
	item.floor_decor = floor_decor
	return item


func _dish(id: StringName, tags: Array[StringName]) -> VibeModel.Dish:
	var dish: VibeModel.Dish = VibeModel.Dish.new()
	dish.id = id
	dish.theme_tags = tags.duplicate()
	return dish


func _inputs_from_shop(world: SimWorld, layout: ShopLayout) -> VibeModel.Inputs:
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	for placed: PlacedItem in world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		var item: VibeModel.Item = _item(definition.id, definition.charm, definition.theme_tags,
			placed.cells, definition.category)
		inputs.items.append(item)
	for y: int in range(layout.rows.size()):
		var row: String = layout.rows[y]
		for x: int in range(row.length()):
			if row.substr(x, 1) == ".":
				inputs.floor_cells.append(Vector2i(x, y))
	return inputs


func _test_floor_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(20):
		for x: int in range(20):
			cells.append(Vector2i(x, y))
	return cells


func _inputs_signature(inputs: VibeModel.Inputs) -> Dictionary:
	var items: Array[Dictionary] = []
	for item: VibeModel.Item in inputs.items:
		items.append({"id": item.definition_id, "charm": item.charm, "category": item.category,
			"tags": item.theme_tags.duplicate(), "paint_tags": item.paint_theme_tags.duplicate(),
			"cells": item.cells.duplicate(), "floor_decor": item.floor_decor})
	var menu: Array[Dictionary] = []
	for dish: VibeModel.Dish in inputs.menu:
		menu.append({"id": dish.id, "tags": dish.theme_tags.duplicate()})
	return {"items": items, "menu": menu, "floor_cells": inputs.floor_cells.duplicate(),
		"wall_tags": inputs.wall_paint_theme_tags.duplicate(),
		"floor_tags": inputs.floor_paint_theme_tags.duplicate()}


func _result_signature(result: VibeModel.Result) -> Dictionary:
	return {"valid": result.valid, "reason": result.reason, "score": result.score,
		"decor": result.decor_points, "variety": result.variety_points, "theme": result.theme_points,
		"lamps": result.lamp_points, "crowding": result.crowding_penalty,
		"active_theme": result.active_theme, "theme_label": result.theme_label,
		"share": result.theme_share, "patience": result.patience_multiplier,
		"review": result.raw_review_bonus, "arrival": result.arrival_theme_strength,
		"interior_cells": result.interior_cells, "occupied_normal_cells": result.occupied_normal_cells,
		"crowding_density": result.crowding_density}


func _assert_neutral(result: VibeModel.Result) -> void:
	for value: float in [result.score, result.decor_points, result.variety_points,
			result.theme_points, result.lamp_points, result.crowding_penalty,
			result.theme_share, result.patience_multiplier, result.raw_review_bonus,
			result.arrival_theme_strength, result.crowding_density]:
		assert_true(is_finite(value), "invalid results retain only finite outputs")
	assert_almost_eq(result.score, 0.0)
	assert_almost_eq(result.decor_points, 0.0)
	assert_almost_eq(result.variety_points, 0.0)
	assert_almost_eq(result.theme_points, 0.0)
	assert_almost_eq(result.lamp_points, 0.0)
	assert_almost_eq(result.crowding_penalty, 0.0)
	assert_eq(result.active_theme, &"")
	assert_almost_eq(result.patience_multiplier, 1.0)
	assert_almost_eq(result.raw_review_bonus, 0.0)
	assert_almost_eq(result.arrival_theme_strength, 0.0)


func _assert_invalid_neutral(inputs: VibeModel.Inputs, tuning: VibeTuning) -> void:
	var before: Dictionary = _inputs_signature(inputs)
	var result: VibeModel.Result = VibeModel.evaluate(inputs, tuning)
	assert_false(result.valid)
	assert_false(result.reason.strip_edges().is_empty())
	assert_eq(_inputs_signature(inputs), before, "invalid evaluation leaves its inputs untouched")
	_assert_neutral(result)
