extends TestCase
## Starter data and invalid in-memory definitions use the same validator.


func test_starter_data_loads_without_validation_errors() -> void:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all().size(), 0)
	assert_eq(db.ingredients().size(), 7)
	assert_eq(db.recipes().size(), 3)
	assert_eq(db.items().size(), 8)


func test_lookups_find_each_kind_and_unknown_ids_return_null() -> void:
	var db: ContentDB = _starter_db()
	assert_eq(db.ingredient(&"beef_patty").display_name, "Beef patty")
	assert_eq(db.recipe(&"burger").standard_price, 9)
	assert_eq(db.item(&"prep_counter").station_type, &"prep_counter")
	assert_null(db.ingredient(&"missing"))
	assert_null(db.recipe(&"missing"))
	assert_null(db.item(&"missing"))


func test_lists_are_sorted_and_do_not_expose_index_arrays() -> void:
	var db: ContentDB = _starter_db()
	var ingredient_ids: Array[StringName] = []
	for definition: IngredientDef in db.ingredients():
		ingredient_ids.append(definition.id)
	assert_eq(ingredient_ids, [&"beef_patty", &"bread", &"bun", &"cheese", &"lettuce", &"soup_stock", &"tomato"])
	var recipe_ids: Array[StringName] = []
	for definition: RecipeDef in db.recipes():
		recipe_ids.append(definition.id)
	assert_eq(recipe_ids, [&"burger", &"grilled_cheese", &"tomato_soup"])
	var item_ids: Array[StringName] = []
	for definition: ItemDef in db.items():
		item_ids.append(definition.id)
	assert_eq(item_ids, [&"chair", &"door", &"fridge", &"pass_counter", &"potted_plant", &"prep_counter", &"stove", &"table_2"])
	var copy: Array[ItemDef] = db.items()
	copy.clear()
	assert_eq(db.items().size(), 8)


func test_reloading_does_not_duplicate_definitions() -> void:
	var db: ContentDB = _starter_db()
	assert_eq(db.load_all().size(), 0)
	assert_eq(db.ingredients().size(), 7)
	assert_eq(db.recipes().size(), 3)
	assert_eq(db.items().size(), 8)


func test_recursive_resource_discovery_returns_sorted_original_tres_names() -> void:
	var errors: PackedStringArray = []
	var paths: PackedStringArray = ContentDB._resource_paths("res://data", errors)
	assert_eq(errors.size(), 0)
	assert_eq(paths.size(), 18)
	assert_true(paths.has("res://data/ingredients/bun.tres"))
	assert_true(paths.has("res://data/recipes/burger.tres"))
	assert_true(paths.has("res://data/items/table_2.tres"))
	var sorted_paths: PackedStringArray = paths.duplicate()
	sorted_paths.sort()
	assert_eq(paths, sorted_paths)
	for path: String in paths:
		assert_true(path.ends_with(".tres"), "discovery returns source names, not export remap filenames")


func test_missing_resource_directories_report_errors_and_clear_old_indices() -> void:
	var db: ContentDB = _starter_db()
	var errors: PackedStringArray = db.load_all("res://data/missing_content_db_test_root")
	assert_eq(errors.size(), 3)
	assert_true(_has_error(errors, "Cannot open content directory:"))
	assert_eq(db.ingredients().size(), 0)
	assert_eq(db.recipes().size(), 0)
	assert_eq(db.items().size(), 0)
	assert_null(db.recipe(&"burger"))


func test_recipe_without_steps_is_reported() -> void:
	var recipe_def: RecipeDef = _recipe()
	recipe_def.steps.clear()
	var errors: PackedStringArray = ContentDB.validate_definitions([], [recipe_def], [_station()])
	assert_true(_has_error(errors, "at least one step"))


func test_recipe_with_unknown_station_is_reported() -> void:
	var recipe_def: RecipeDef = _recipe()
	recipe_def.steps[0].station_type = &"missing_station"
	var errors: PackedStringArray = ContentDB.validate_definitions([], [recipe_def], [_station()])
	assert_true(_has_error(errors, "unknown station 'missing_station'"))


func test_storage_does_not_satisfy_a_recipe_station_requirement() -> void:
	var item_def: ItemDef = _station()
	item_def.category = ItemDef.Category.STORAGE
	var errors: PackedStringArray = ContentDB.validate_definitions([], [_recipe()], [item_def])
	assert_true(_has_error(errors, "unknown station"))


func test_null_recipe_ingredients_and_steps_are_reported_without_engine_errors() -> void:
	var recipe_def: RecipeDef = _recipe()
	recipe_def.ingredients.append(null)
	recipe_def.steps.append(null)
	var errors: PackedStringArray = ContentDB.validate_definitions([], [recipe_def], [_station()])
	assert_true(_has_error(errors, "ingredient[0] is null"))
	assert_true(_has_error(errors, "step[1] is null"))


func test_zero_and_negative_step_durations_are_reported() -> void:
	var recipe_def: RecipeDef = _recipe()
	for duration: int in [0, -1]:
		recipe_def.steps[0].duration_ticks = duration
		var errors: PackedStringArray = ContentDB.validate_definitions([], [recipe_def], [_station()])
		assert_true(_has_error(errors, "duration_ticks must be > 0"))


func test_duplicate_ids_are_reported_per_kind() -> void:
	var ingredient_def: IngredientDef = IngredientDef.new()
	ingredient_def.id = &"duplicate"
	var recipe_def: RecipeDef = _recipe()
	var item_def: ItemDef = _station()
	var errors: PackedStringArray = ContentDB.validate_definitions(
		[ingredient_def, ingredient_def], [recipe_def, recipe_def], [item_def, item_def])
	assert_true(_has_error(errors, "ingredient id 'duplicate' is duplicated"))
	assert_true(_has_error(errors, "recipe id 'test_recipe' is duplicated"))
	assert_true(_has_error(errors, "item id 'prep' is duplicated"))


func test_same_id_in_different_kinds_is_allowed() -> void:
	var ingredient_def: IngredientDef = IngredientDef.new()
	ingredient_def.id = &"shared"
	var recipe_def: RecipeDef = _recipe()
	recipe_def.id = &"shared"
	var item_def: ItemDef = _station()
	item_def.id = &"shared"
	assert_eq(ContentDB.validate_definitions([ingredient_def], [recipe_def], [item_def]).size(), 0)


func test_empty_ids_are_reported_for_all_kinds() -> void:
	var ingredient_def: IngredientDef = IngredientDef.new()
	var recipe_def: RecipeDef = _recipe()
	recipe_def.id = &""
	var item_def: ItemDef = _station()
	item_def.id = &""
	var errors: PackedStringArray = ContentDB.validate_definitions([ingredient_def], [recipe_def], [item_def])
	assert_true(_has_error(errors, "ingredient has an empty id"))
	assert_true(_has_error(errors, "recipe has an empty id"))
	assert_true(_has_error(errors, "item has an empty id"))


func test_invalid_footprint_and_negative_prices_are_reported() -> void:
	var ingredient_def: IngredientDef = IngredientDef.new()
	ingredient_def.id = &"bad_cost"
	ingredient_def.unit_cost = -1
	var recipe_def: RecipeDef = _recipe()
	recipe_def.standard_price = -1
	var item_def: ItemDef = _station()
	item_def.price = -1
	item_def.footprint = Vector2i(0, -1)
	var errors: PackedStringArray = ContentDB.validate_definitions([ingredient_def], [recipe_def], [item_def])
	assert_true(_has_error(errors, "unit_cost must be >= 0"))
	assert_true(_has_error(errors, "standard_price must be >= 0"))
	assert_true(_has_error(errors, "price must be >= 0"))
	assert_true(_has_error(errors, "footprint components must be >= 1"))


func test_null_top_level_definitions_and_quality_bounds_are_reported() -> void:
	var recipe_def: RecipeDef = _recipe()
	recipe_def.base_quality = 1.1
	var errors: PackedStringArray = ContentDB.validate_definitions([null], [recipe_def, null], [null])
	assert_true(_has_error(errors, "ingredient[0] is null"))
	assert_true(_has_error(errors, "recipe[1] is null"))
	assert_true(_has_error(errors, "item[0] is null"))
	assert_true(_has_error(errors, "base_quality must be between 0 and 1"))


func test_clockwise_rotation_covers_every_quarter_turn_of_two_by_one_footprint() -> void:
	var first: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var second: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 0), Vector2i(0, 0)]
	for turns: int in range(4):
		assert_eq(ItemDef.rotate_cell(Vector2i(0, 0), Vector2i(2, 1), turns), first[turns])
		assert_eq(ItemDef.rotate_cell(Vector2i(1, 0), Vector2i(2, 1), turns), second[turns])


func test_outside_work_cells_rotate_without_clamping_and_turns_wrap() -> void:
	var front: Vector2i = Vector2i(0, -1)
	var expected: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(-1, 1)]
	for turns: int in range(4):
		var rotated: Vector2i = ItemDef.rotate_cell(front, Vector2i(2, 1), turns)
		assert_eq(rotated, expected[turns])
		var rotated_size: Vector2i = Vector2i(1, 2) if turns % 2 == 1 else Vector2i(2, 1)
		assert_eq(ItemDef.rotate_cell(rotated, rotated_size, -turns), front)
	assert_eq(ItemDef.rotate_cell(front, Vector2i(2, 1), -1), expected[3])
	assert_eq(ItemDef.rotate_cell(front, Vector2i(2, 1), 5), expected[1])


func test_recipe_helpers_count_repeated_ingredient_units_and_all_steps() -> void:
	var db: ContentDB = _starter_db()
	assert_eq(db.recipe(&"burger").ingredient_cost(), 4)
	assert_eq(db.recipe(&"burger").total_ticks(), 120)
	var grilled: RecipeDef = db.recipe(&"grilled_cheese")
	assert_eq(grilled.ingredients.size(), 3)
	assert_true(grilled.ingredients[0] == grilled.ingredients[1])
	assert_eq(grilled.ingredient_cost(), 3)
	assert_eq(grilled.total_ticks(), 70)
	assert_eq(db.recipe(&"tomato_soup").ingredient_cost(), 3)
	assert_eq(db.recipe(&"tomato_soup").total_ticks(), 150)


func test_starter_footprints_categories_and_interaction_cells() -> void:
	var db: ContentDB = _starter_db()
	assert_false(db.item(&"door").solid)
	assert_eq(db.item(&"door").footprint, Vector2i(1, 2))
	assert_eq(db.item(&"table_2").seat_cells.size(), 2)
	assert_eq(db.item(&"fridge").category, ItemDef.Category.STORAGE)
	assert_eq(db.item(&"prep_counter").work_cells, [Vector2i(0, -1)])
	assert_eq(db.item(&"pass_counter").category, ItemDef.Category.PASS)
	assert_eq(db.item(&"pass_counter").work_cells, [Vector2i(0, -1), Vector2i(0, 1)])
	assert_eq(db.item(&"potted_plant").charm, 2)


func _starter_db() -> ContentDB:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all().size(), 0)
	return db


func _recipe() -> RecipeDef:
	var result: RecipeDef = RecipeDef.new()
	result.id = &"test_recipe"
	var step: RecipeStep = RecipeStep.new()
	step.station_type = &"prep_counter"
	step.duration_ticks = 10
	result.steps.append(step)
	return result


func _station() -> ItemDef:
	var result: ItemDef = ItemDef.new()
	result.id = &"prep"
	result.category = ItemDef.Category.STATION
	result.station_type = &"prep_counter"
	return result


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for error: String in errors:
		if error.contains(fragment):
			return true
	return false
