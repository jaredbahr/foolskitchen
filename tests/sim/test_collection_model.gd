extends TestCase
## Collections derive from placed base IDs and interior floor styles.

const TUNING: VibeTuning = preload("res://data/balance/vibe.tres")

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray(), "starter collections validate with all content")


func after_each() -> void:
	_content = null


func test_authored_sets_are_sorted_named_and_incomplete_in_the_starting_shop() -> void:
	assert_eq(_content.collections().size(), 6)
	assert_eq(_content.collection(&"diner_classics").display_name, "Diner Classics")
	for definition: CollectionDef in _content.collections():
		assert_false(definition.short_line.strip_edges().is_empty(), "%s has its required short line" % definition.id)
	var starting_items: Array[StringName] = [&"fridge", &"prep_counter", &"stove", &"pass_counter",
		&"table_2", &"potted_plant", &"sink"]
	var result: CollectionModel.Result = _evaluate(starting_items, [&"planks"])
	assert_true(result.valid)
	assert_eq(result.completed_ids, [] as Array[StringName], "the ordinary starting shop has no completed bonus")
	assert_eq(result.effective_bonus, 0.0)
	assert_eq(result.entries.size(), 6)


func test_collection_requires_each_distinct_base_item_and_any_interior_matching_floor() -> void:
	var definition: CollectionDef = _content.collection(&"diner_classics")
	var items: Array[StringName] = []
	items.assign(definition.item_ids)
	var result: CollectionModel.Result = _evaluate_set(definition, items, [&"planks"])
	assert_true(result.valid)
	assert_false(result.entries[0].completed, "matching objects without the required floor are incomplete")
	result = _evaluate_set(definition, [&"neon_open_sign", &"menu_board", &"menu_board"], [&"checker"])
	assert_false(result.entries[0].completed, "copies of one base ID cannot replace the missing item")
	result = _evaluate_set(definition, definition.item_ids, [&"planks", &"checker"])
	assert_true(result.entries[0].completed, "one matching interior floor cell is sufficient")
	assert_eq(result.entries[0].requirements.size(), 3)
	assert_eq(result.entries[0].requirements.filter(func(entry: CollectionModel.Entry.Requirement) -> bool:
		return entry.present).size(), 3)
	result = _evaluate_set(definition, [&"neon_open_sign", &"menu_board"], [&"checker"])
	assert_false(result.entries[0].completed, "removing a required item reverses derived completion")
	result = _evaluate_set(definition, definition.item_ids, [&"checker"])
	assert_true(result.entries[0].completed, "restoring the required item derives completion again")


func test_six_completed_collections_share_the_authored_cap() -> void:
	var item_ids: Array[StringName] = []
	var floor_ids: Array[StringName] = []
	for definition: CollectionDef in _content.collections():
		item_ids.append_array(definition.item_ids)
		floor_ids.append(definition.floor_id)
	var result: CollectionModel.Result = _evaluate(item_ids, floor_ids)
	assert_true(result.valid)
	assert_eq(result.completed_ids.size(), 6)
	assert_eq(result.nominal_bonus, 12.0)
	assert_eq(result.effective_bonus, TUNING.max_collection_bonus)
	assert_true(result.capped)
	result = CollectionModel.evaluate(_content.collections().slice(0, 3), item_ids, floor_ids, 6.0, _content)
	assert_true(result.valid)
	assert_eq(result.nominal_bonus, 6.0)
	assert_eq(result.effective_bonus, 6.0)
	assert_false(result.capped, "the exact cap boundary is not reported as over cap")
	result = CollectionModel.evaluate(_content.collections().slice(0, 1), item_ids, floor_ids, 0.0, _content)
	assert_eq(result.effective_bonus, 0.0)
	assert_true(result.capped, "a positive nominal bonus exceeds a zero cap")


func test_vibe_uses_the_same_pure_result_and_only_its_capped_points() -> void:
	var item_ids: Array[StringName] = []
	var floor_ids: Array[StringName] = []
	for definition: CollectionDef in _content.collections():
		item_ids.append_array(definition.item_ids)
		floor_ids.append(definition.floor_id)
	var collection_result: CollectionModel.Result = _evaluate(item_ids, floor_ids)
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	inputs.collection_result = collection_result
	var vibe: VibeModel.Result = VibeModel.evaluate(inputs, TUNING)
	assert_true(vibe.valid)
	assert_eq(vibe.collection_result.get_instance_id(), collection_result.get_instance_id(),
		"Goals and vibe retain the exact same derived collection snapshot")
	assert_eq(vibe.collection_points, 6.0)
	assert_eq(vibe.score, 6.0)
	var stale_cap: CollectionModel.Result = _evaluate(item_ids, floor_ids)
	stale_cap.effective_bonus = 100.0
	stale_cap.capped = false
	stale_cap.nominal_bonus = 9.0
	inputs.collection_result = stale_cap
	vibe = VibeModel.evaluate(inputs, TUNING)
	assert_true(vibe.valid)
	assert_eq(vibe.collection_points, TUNING.max_collection_bonus,
		"VibeModel applies the current tuning cap rather than trusting a stale snapshot")
	assert_eq(vibe.collection_nominal_bonus, 9.0)
	stale_cap.nominal_bonus = NAN
	assert_false(VibeModel.evaluate(inputs, TUNING).valid, "non-finite nominal points invalidate the vibe")
	stale_cap.nominal_bonus = -1.0
	assert_false(VibeModel.evaluate(inputs, TUNING).valid, "negative nominal points invalidate the vibe")


func test_optional_floor_and_pure_evaluator_rejects_invalid_requirements() -> void:
	var definition: CollectionDef = _definition(&"no_floor", [&"table_2"])
	definition.floor_id = &""
	var result: CollectionModel.Result = CollectionModel.evaluate([definition], [&"table_2"],
		[] as Array[StringName], TUNING.max_collection_bonus, _content)
	assert_true(result.valid)
	assert_true(result.entries[0].completed, "an empty floor ID means the collection has no floor requirement")
	var duplicate: CollectionDef = _definition(&"duplicate", [&"table_2", &"table_2"])
	assert_false(CollectionModel.evaluate([duplicate], [&"table_2"], [] as Array[StringName], 6.0, _content).valid)
	var unknown_item: CollectionDef = _definition(&"unknown", [&"missing_item"])
	assert_false(CollectionModel.evaluate([unknown_item], [&"missing_item"], [] as Array[StringName], 6.0, _content).valid)
	var unknown_floor: CollectionDef = _definition(&"unknown_floor", [&"table_2"])
	unknown_floor.floor_id = &"missing_floor"
	assert_false(CollectionModel.evaluate([unknown_floor], [&"table_2"], [] as Array[StringName], 6.0, _content).valid)


func test_content_validation_rejects_empty_duplicate_and_unknown_requirements() -> void:
	var empty: CollectionDef = _definition(&"empty", [])
	var duplicate: CollectionDef = _definition(&"duplicate", [&"table_2", &"table_2"])
	var unknown: CollectionDef = _definition(&"unknown", [&"future_item"])
	unknown.floor_id = &"future_floor"
	var empty_id: CollectionDef = _definition(&"empty_id", [&""])
	var errors: PackedStringArray = ContentDB.validate_collections([empty, duplicate, unknown, empty_id],
		_content.items(), _content.floor_styles())
	assert_true(_has_error(errors, "requirements are empty"))
	assert_true(_has_error(errors, "item requirement is empty"))
	assert_true(_has_error(errors, "is duplicated"))
	assert_true(_has_error(errors, "unknown item"))
	assert_true(_has_error(errors, "unknown floor"))
	var no_line: CollectionDef = _definition(&"no_line", [&"table_2"])
	no_line.short_line = "  "
	assert_true(_has_error(ContentDB.validate_collections([no_line], _content.items(), _content.floor_styles()),
		"short_line is empty"))


func _evaluate(items: Array[StringName], floors: Array[StringName]) -> CollectionModel.Result:
	return CollectionModel.evaluate(_content.collections(), items, floors, TUNING.max_collection_bonus, _content)


func _evaluate_set(definition: CollectionDef, items: Array[StringName], floors: Array[StringName]) -> CollectionModel.Result:
	var definitions: Array[CollectionDef] = [definition]
	return CollectionModel.evaluate(definitions, items, floors, TUNING.max_collection_bonus, _content)


func _definition(id: StringName, items: Array[StringName]) -> CollectionDef:
	var definition: CollectionDef = CollectionDef.new()
	definition.id = id
	definition.display_name = String(id)
	definition.short_line = "A little moment of comfort."
	definition.item_ids = items
	definition.bonus = 2.0
	return definition


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for error: String in errors:
		if error.contains(fragment):
			return true
	return false
