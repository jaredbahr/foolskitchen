extends TestCase
## Starter data and invalid in-memory definitions use the same validator.


func test_starter_data_loads_without_validation_errors() -> void:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all().size(), 0)
	assert_eq(db.ingredients().size(), 16)
	assert_eq(db.recipes().size(), 12)
	assert_eq(db.items().size(), 49)


func test_lookups_find_each_kind_and_unknown_ids_return_null() -> void:
	var db: ContentDB = _starter_db()
	assert_eq(db.ingredient(&"beef_patty").display_name, "Beef patty")
	assert_eq(db.recipe(&"burger").standard_price, 12)
	assert_eq(db.recipe(&"tomato_melt").unlock_level, 2)
	assert_eq(db.item(&"potted_plant").unlock_level, 2)
	assert_eq(db.item(&"prep_counter").station_type, &"prep_counter")
	assert_eq(db.item(&"sink").footprint, Vector2i.ONE)
	assert_eq(db.item(&"sink").work_cells.size(), 1)
	assert_eq(db.item(&"sink").price, 40)
	assert_null(db.ingredient(&"missing"))
	assert_null(db.recipe(&"missing"))
	assert_null(db.item(&"missing"))


func test_lists_are_sorted_and_do_not_expose_index_arrays() -> void:
	var db: ContentDB = _starter_db()
	var ingredient_ids: Array[StringName] = []
	for definition: IngredientDef in db.ingredients():
		ingredient_ids.append(definition.id)
	assert_eq(ingredient_ids, [&"beef_patty", &"beer", &"bread", &"bun", &"cheese", &"coffee_beans", &"dough",
		&"lettuce", &"oil", &"pastry", &"potato", &"soda", &"soup_stock", &"tea", &"tomato", &"wine"])
	var recipe_ids: Array[StringName] = []
	for definition: RecipeDef in db.recipes():
		recipe_ids.append(definition.id)
	assert_eq(recipe_ids, [&"beer", &"burger", &"coffee", &"croissant", &"fries", &"grilled_cheese", &"savoury_pie", &"soft_drink",
		&"tea", &"tomato_melt", &"tomato_soup", &"wine"])
	var item_ids: Array[StringName] = []
	for definition: ItemDef in db.items():
		item_ids.append(definition.id)
	assert_eq(item_ids, [
		&"bar_corner", &"bar_counter", &"bar_end_left", &"bar_end_right", &"bar_section",
		&"bar_stool", &"bench", &"bookcase_open_low", &"chair", &"cloth_table",
		&"coat_rack_standing", &"coffee_machine", &"corner_cabinet", &"cross_table", &"cushioned_bench", &"diner_booth", &"diner_stool",
		&"door", &"drinks_fridge", &"drinks_shelf", &"fridge", &"fryer", &"glass_table",
		&"lounge_chair", &"modern_chair", &"modern_frame_chair", &"oven", &"pass_counter", &"plant_small_1",
		&"plant_small_2", &"plant_small_3", &"potted_plant", &"prep_cabinet", &"prep_counter", &"round_table",
		&"rounded_chair", &"rug_rectangle", &"rug_round", &"rug_square", &"side_table", &"sink",
		&"speaker", &"square_bar_stool", &"storage_shelf", &"stove", &"table_2", &"table_4", &"television_vintage", &"wooden_chair",
	])
	var copy: Array[ItemDef] = db.items()
	copy.clear()
	assert_eq(db.items().size(), 49)


func test_reloading_does_not_duplicate_definitions() -> void:
	var db: ContentDB = _starter_db()
	assert_eq(db.load_all().size(), 0)
	assert_eq(db.ingredients().size(), 16)
	assert_eq(db.recipes().size(), 12)
	assert_eq(db.items().size(), 49)


func test_recursive_resource_discovery_returns_sorted_original_tres_names() -> void:
	var errors: PackedStringArray = []
	var paths: PackedStringArray = ContentDB._resource_paths("res://data", errors)
	assert_eq(errors.size(), 0)
	# Count only the content folders, so other data (layouts, ...) can grow freely.
	var content_paths := 0
	for path: String in paths:
		if path.begins_with("res://data/ingredients/") or path.begins_with("res://data/recipes/") \
				or path.begins_with("res://data/items/"):
			content_paths += 1
	assert_eq(content_paths, 77)
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
	assert_eq(errors.size(), 5)
	assert_true(_has_error(errors, "Cannot open content directory:"))
	assert_eq(db.ingredients().size(), 0)
	assert_eq(db.recipes().size(), 0)
	assert_eq(db.items().size(), 0)
	assert_eq(db.swatches().size(), 0)
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


func test_seated_forward_offset_defaults_to_zero_and_accepts_values_through_the_director_limit() -> void:
	var definition: ItemDef = _station()
	assert_almost_eq(definition.seated_forward_offset, 0.0)
	assert_eq(ContentDB.validate_definitions([], [], [definition]), PackedStringArray())
	for offset: float in [0.025, ItemDef.MAX_SEATED_FORWARD_OFFSET]:
		definition.seated_forward_offset = offset
		assert_eq(ContentDB.validate_definitions([], [], [definition]), PackedStringArray(), str(offset))


func test_out_of_range_or_nonfinite_seated_forward_offsets_are_reported() -> void:
	for offset: float in [-0.01, ItemDef.MAX_SEATED_FORWARD_OFFSET + 0.000001, INF, NAN]:
		var definition: ItemDef = _station()
		definition.seated_forward_offset = offset
		var errors: PackedStringArray = ContentDB.validate_definitions([], [], [definition])
		assert_true(_has_error(errors, "seated_forward_offset must be finite and between 0 and 0.05 m"), str(offset))


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


func test_all_item_seats_are_walkable_and_reachable_in_every_rotation() -> void:
	var db: ContentDB = ContentDB.new()
	var errors: PackedStringArray = db.load_all()
	assert_eq(errors, PackedStringArray(), "starter content loads")
	var seats_checked: int = 0
	for definition: ItemDef in db.items():
		if definition.seat_cells.is_empty():
			continue
		for turns: int in range(4):
			var grid: SimGrid = SimGrid.new(Vector2i(6, 6))
			var item: PlacedItem = grid.place_def(definition, Vector2i(2, 2), turns)
			assert_not_null(item, "%s fits at rotation %d" % [definition.id, turns])
			if item == null:
				continue
			assert_eq(item.seat_cells.size(), definition.seat_cells.size(), "all declared seats are placed")
			for seat: Vector2i in item.seat_cells:
				seats_checked += 1
				var context: String = "%s seat %s at rotation %d" % [definition.id, seat, turns]
				assert_true(grid.is_walkable(seat), "%s is walkable" % context)
				assert_true(grid.is_reachable(Vector2i.ZERO, seat), "%s is reachable from (0,0)" % context)
	assert_true(seats_checked > 0, "content includes seats to check")


func test_rugs_use_passive_floor_layer_and_existing_furniture_keeps_normal_layer() -> void:
	var db: ContentDB = _starter_db()
	for id: StringName in [&"rug_rectangle", &"rug_round", &"rug_square"]:
		var definition: ItemDef = db.item(id)
		assert_eq(definition.placement_layer, ItemDef.PlacementLayer.FLOOR_DECOR)
		assert_true(definition.placement_layer_valid())
		assert_false(definition.solid)
		assert_true(definition.work_cells.is_empty())
		assert_true(definition.seat_cells.is_empty())
		assert_true(definition.catalogue_visible)
	for id: StringName in [&"table_2", &"chair", &"fridge", &"prep_counter", &"door"]:
		assert_eq(db.item(id).placement_layer, ItemDef.PlacementLayer.NORMAL)
	assert_true(ItemDef.new().catalogue_visible, "existing content remains listed unless explicitly hidden")


func test_invalid_floor_layer_definitions_are_reported_without_changing_resources() -> void:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_floor_decor"
	definition.category = ItemDef.Category.DECOR
	definition.placement_layer = ItemDef.PlacementLayer.FLOOR_DECOR
	definition.solid = false
	assert_eq(ContentDB.validate_definitions([], [], [definition]), PackedStringArray())
	var invalid: Array[ItemDef] = []
	var solid: ItemDef = definition.duplicate(true) as ItemDef
	solid.solid = true
	invalid.append(solid)
	var table: ItemDef = definition.duplicate(true) as ItemDef
	table.category = ItemDef.Category.TABLE
	invalid.append(table)
	var worker: ItemDef = definition.duplicate(true) as ItemDef
	worker.work_cells = [Vector2i.UP]
	invalid.append(worker)
	var seat: ItemDef = definition.duplicate(true) as ItemDef
	seat.seat_cells = [Vector2i.ZERO]
	invalid.append(seat)
	var unknown: ItemDef = definition.duplicate(true) as ItemDef
	unknown.set("placement_layer", 99)
	invalid.append(unknown)
	for bad: ItemDef in invalid:
		assert_false(bad.placement_layer_valid())
		var errors: PackedStringArray = ContentDB.validate_definitions([], [], [bad])
		assert_true(_has_error(errors, "invalid placement layer"))
	assert_true(definition.placement_layer_valid())
	assert_eq(definition.placement_layer, ItemDef.PlacementLayer.FLOOR_DECOR)
	assert_false(definition.solid)


func test_recipe_menu_sections_validate_without_changing_shared_content() -> void:
	var definition: RecipeDef = _recipe()
	assert_eq(ContentDB.validate_definitions([], [definition], [_station()]), PackedStringArray())
	for section: int in RecipeDef.Section.values():
		definition.set("section", section)
		var section_errors: PackedStringArray = ContentDB.validate_definitions([], [definition], [_station()])
		if section == RecipeDef.Section.DRINKS:
			assert_true(_has_error(section_errors, "only drinks, belong in the Drinks section"), "food is never listed under Drinks")
		else:
			assert_eq(section_errors, PackedStringArray())
	var drink: RecipeDef = definition.duplicate(true) as RecipeDef
	drink.order_type = RecipeDef.COFFEE
	assert_true(_has_error(ContentDB.validate_definitions([], [drink], [_station()]), "belong in the Drinks section"))
	drink.section = RecipeDef.Section.DRINKS
	assert_eq(drink.menu_section(), RecipeDef.Section.DRINKS)
	var invalid: RecipeDef = definition.duplicate(true) as RecipeDef
	invalid.set("section", 99)
	var errors: PackedStringArray = ContentDB.validate_definitions([], [invalid], [_station()])
	assert_eq(errors.size(), 1)
	assert_true(_has_error(errors, "unknown menu section"))
	assert_eq(definition.section, RecipeDef.Section.DESSERTS)
	assert_eq(_starter_db().recipe(&"tomato_soup").section, RecipeDef.Section.STARTERS)


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


func test_fryer_and_oven_recipes_have_data_owned_prices_levels_sections_and_steps() -> void:
	var db: ContentDB = _starter_db()
	for row: Array in [[&"fries", &"fryer", 7, 2, RecipeDef.Section.SIDES, 70, 2],
			[&"savoury_pie", &"oven", 13, 3, RecipeDef.Section.MAINS, 130, 4]]:
		var recipe: RecipeDef = db.recipe(row[0])
		assert_eq(recipe.standard_price, row[2])
		assert_eq(recipe.unlock_level, row[3])
		assert_eq(recipe.unlock_tier, 1)
		assert_eq(recipe.menu_section(), row[4])
		assert_eq(recipe.steps.size(), 2)
		assert_eq(recipe.steps[0].station_type, &"prep_counter")
		assert_eq(recipe.steps[1].station_type, row[1])
		assert_eq(recipe.total_ticks(), row[5])
		assert_eq(recipe.ingredient_cost(), row[6])
		assert_eq(recipe.theme_tags, [&"diner"] as Array[StringName])
		assert_false(recipe.is_drink())
