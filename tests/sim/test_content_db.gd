extends TestCase
## Starter data and invalid in-memory definitions use the same validator.


func test_starter_data_loads_without_validation_errors() -> void:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all().size(), 0)
	assert_eq(db.ingredients().size(), 32)
	assert_eq(db.recipes().size(), _recipe_resource_count("res://data/recipes"))
	assert_eq(db.items().size(), 98)
	assert_eq(db.collections().size(), 6)
	assert_eq(db.collection(&"diner_classics").item_ids, [&"neon_open_sign", &"menu_board", &"diner_booth"])


func test_seaside_recipes_use_their_equipment_and_are_marked_for_takeaway() -> void:
	var db: ContentDB = _starter_db()
	var seaside: Array[RecipeDef] = db.recipes_for_lot([&"seaside"])
	var inland: Array[RecipeDef] = db.recipes_for_lot([&"rooftop"])
	var equipment: Dictionary[StringName, StringName] = {
		&"soft_serve": &"soft_serve_machine",
		&"shaved_ice": &"shaved_ice_cart",
		&"cone_fries": &"fryer",
	}
	for recipe_id: StringName in equipment:
		var recipe: RecipeDef = db.recipe(recipe_id)
		var item: ItemDef = db.item(equipment[recipe_id])
		assert_true(recipe.takeaway_ok, recipe.display_name)
		assert_true(seaside.has(recipe))
		assert_false(inland.has(recipe))
		assert_eq(recipe.steps.back().station_type, item.station_type)
		if item.id != &"fryer":
			assert_true(LotAccess.allowed(item, [&"seaside"]))
			assert_false(LotAccess.allowed(item, []))
	var sundae: RecipeDef = db.recipe(&"ice_cream_sundae")
	assert_true(sundae.takeaway_ok)
	assert_true(inland.has(sundae), "the existing diner sundae stays available")
	assert_eq(sundae.steps[0].station_type, &"prep_counter")


func test_lot_access_defaults_to_everywhere_and_accepts_any_shared_tag() -> void:
	var item: ItemDef = ItemDef.new()
	var ingredient: IngredientDef = IngredientDef.new()
	assert_true(LotAccess.allowed(item, []))
	assert_true(LotAccess.allowed(ingredient, [&"rooftop"]))
	item.lot_tags = [&"rooftop", &"seaside"]
	ingredient.lot_tags = [&"seaside"]
	assert_false(LotAccess.allowed(item, []))
	assert_true(LotAccess.allowed(item, [&"other", &"seaside"]))
	assert_true(LotAccess.allowed(item, [&"rooftop"]))
	assert_false(LotAccess.allowed(ingredient, [&"rooftop"]))
	assert_true(LotAccess.allowed(ingredient, [&"seaside"]))
	assert_false(LotAccess.allowed(null, [&"seaside"]))


func test_definition_validation_rejects_empty_and_malformed_lot_tags() -> void:
	var item: ItemDef = ItemDef.new()
	item.id = &"cart"
	item.lot_tags = [&""]
	var ingredient: IngredientDef = IngredientDef.new()
	ingredient.id = &"catch"
	ingredient.lot_tags = [&"by the sea"]
	var errors: PackedStringArray = ContentDB.validate_definitions([ingredient], [], [item])
	assert_true(errors.has("item 'cart': lot tags must be non-empty ids"))
	assert_true(errors.has("ingredient 'catch': lot tags must be non-empty ids"))
	item.lot_tags = []
	ingredient.lot_tags = []
	assert_eq(ContentDB.validate_definitions([ingredient], [], [item]), PackedStringArray())


func test_content_lot_tags_must_be_declared_by_a_lot() -> void:
	var lot: LotDef = LotDef.new()
	lot.tags = [&"seaside"]
	var item: ItemDef = ItemDef.new()
	item.id = &"cart"
	item.lot_tags = [&"rooftop"]
	var ingredient: IngredientDef = IngredientDef.new()
	ingredient.id = &"catch"
	ingredient.lot_tags = [&"seaside", &"seasdie"]
	var errors: PackedStringArray = ContentDB.validate_definitions([ingredient], [], [item], [lot])
	assert_true(errors.has("item 'cart': lot tag 'rooftop' is not declared by any lot"))
	assert_true(errors.has("ingredient 'catch': lot tag 'seasdie' is not declared by any lot"))
	lot.tags.append(&"rooftop")
	ingredient.lot_tags = [&"seaside"]
	assert_eq(ContentDB.validate_definitions([ingredient], [], [item], [lot]), PackedStringArray())


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
	assert_eq(ingredient_ids, [&"bacon", &"beef_patty", &"beer", &"bread", &"bun", &"cereal", &"cheese", &"coffee_beans",
		&"dough", &"egg", &"fish_fillet", &"flour", &"fresh_catch", &"frozen_fries", &"fruit_syrup", &"ice_cream", &"lemon", &"lettuce",
		&"milk",
		&"mussels", &"oil", &"pastry", &"potato", &"rice", &"sausage", &"shrimp", &"soda", &"soup_stock", &"tea",
		&"tomato", &"tortilla", &"wine"])
	var recipe_ids: Array[StringName] = []
	for definition: RecipeDef in db.recipes():
		recipe_ids.append(definition.id)
	assert_eq(recipe_ids, [&"bacon_and_eggs", &"bar_fries", &"beer", &"burger", &"cereal", &"club_sandwich", &"coffee",
		&"cone_fries", &"croissant", &"fish_and_chips", &"fried_eggs", &"fries", &"grilled_cheese", &"hot_dog", &"ice_cream_sundae",
		&"muffin", &"mussels_broth", &"pancakes", &"pizza_slice", &"salmon_maki", &"savoury_pie", &"seafood_stew",
		&"shaved_ice", &"shrimp_skewer", &"soft_drink", &"soft_serve", &"taco", &"tea", &"tomato_melt", &"tomato_soup", &"waffles", &"wine"])
	var item_ids: Array[StringName] = []
	for definition: ItemDef in db.items():
		item_ids.append(definition.id)
	assert_eq(item_ids, [
		&"a_frame_sign", &"aquarium", &"aquarium_large", &"awning", &"bar_corner", &"bar_counter", &"bar_end_left", &"bar_end_right",
		&"bar_section", &"bar_stool", &"barrel", &"bathroom_sink", &"beach_sign", &"bench", &"bookcase_open_low", &"bunting", &"chair",
		&"cloth_table", &"coat_rack_standing", &"cocktail_station", &"coffee_machine", &"corner_cabinet", &"crockery_dresser",
		&"cross_table", &"cushioned_bench", &"diner_booth", &"diner_stool", &"door", &"drinks_fridge", &"drinks_shelf", &"fishing_net",
		&"flour_sacks", &"flower_window_box", &"freezer", &"fridge", &"fryer", &"glass_table", &"jukebox", &"lamp_floor_round",
		&"lamp_floor_square", &"lamp_pendant", &"lamp_table_round", &"lamp_table_square", &"lamp_wall", &"lifebuoy",
		&"lounge_chair", &"menu_board", &"modern_chair", &"modern_frame_chair", &"neon_open_sign", &"order_counter", &"oven", &"pass_counter",
		&"patio_chair", &"patio_table_2", &"patio_waiting_bench", &"pergola", &"plant_small_1",
		&"plant_small_2", &"plant_small_3", &"potted_plant", &"prep_cabinet", &"prep_counter", &"restroom_mirror", &"round_table",
		&"rounded_chair", &"rug_rectangle", &"rug_round", &"rug_square", &"shaved_ice_cart", &"shell_jars",
		&"shop_name_sign", &"side_table", &"sink", &"skyline_print", &"soft_serve_machine",
		&"speaker", &"square_bar_stool", &"storage_shelf", &"stove", &"street_awning_2", &"street_awning_3", &"street_awning_4",
		&"string_lights_2", &"string_lights_3", &"string_lights_4", &"surfboard", &"table_2", &"table_4", &"television_vintage", &"tip_jar", &"toilet",
		&"waiting_bench", &"wall_art_peaks", &"wall_art_sunrise", &"wall_hand_dryer", &"wheat_sheaf", &"wooden_chair",
	])
	var copy: Array[ItemDef] = db.items()
	copy.clear()
	assert_eq(db.items().size(), 98)


func test_reloading_does_not_duplicate_definitions() -> void:
	var db: ContentDB = _starter_db()
	assert_eq(db.load_all().size(), 0)
	assert_eq(db.ingredients().size(), 32)
	assert_eq(db.recipes().size(), _recipe_resource_count("res://data/recipes"))
	assert_eq(db.items().size(), 98)


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
	assert_eq(content_paths, 162)
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
	# Nine folders, plus the missing starting floor and wall finish.
	assert_eq(errors.size(), 11)
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


func test_seated_lean_defaults_to_imported_pose_and_accepts_bounded_articulation() -> void:
	var definition: ItemDef = _station()
	assert_almost_eq(definition.seated_lean_degrees, 0.0)
	for angle: float in [0.0, 7.5, ItemDef.MAX_SEATED_LEAN_DEGREES]:
		definition.seated_lean_degrees = angle
		assert_eq(ContentDB.validate_definitions([], [], [definition]), PackedStringArray())


func test_seated_lean_rejects_nonfinite_backward_and_excessive_articulation() -> void:
	for angle: float in [-0.01, ItemDef.MAX_SEATED_LEAN_DEGREES + 0.000001, INF, -INF, NAN]:
		var definition: ItemDef = _station()
		definition.seated_lean_degrees = angle
		var errors: PackedStringArray = ContentDB.validate_definitions([], [], [definition])
		assert_true(_has_error(errors, "seated_lean_degrees must be finite and between 0 and 35 degrees"))


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
	assert_eq(db.recipe(&"burger").total_ticks(), 84)
	var grilled: RecipeDef = db.recipe(&"grilled_cheese")
	assert_eq(grilled.ingredients.size(), 3)
	assert_true(grilled.ingredients[0] == grilled.ingredients[1])
	assert_eq(grilled.ingredient_cost(), 3)
	assert_eq(grilled.total_ticks(), 49)
	assert_eq(db.recipe(&"tomato_soup").ingredient_cost(), 3)
	assert_eq(db.recipe(&"tomato_soup").total_ticks(), 105)


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
			if definition.outdoor_only:
				var patio: Dictionary[Vector2i, int] = {}
				for cell: Vector2i in grid.cells():
					if grid.terrain(cell) == SimGrid.Terrain.FLOOR:
						patio[cell] = SimGrid.Room.PATIO
				assert_true(grid.set_rooms(patio), "outdoor seats have legal patio floor")
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


func test_rain_cover_must_be_outdoor_only_floor_decor() -> void:
	var cover: ItemDef = ItemDef.new()
	cover.id = &"test_cover"
	cover.category = ItemDef.Category.DECOR
	cover.placement_layer = ItemDef.PlacementLayer.FLOOR_DECOR
	cover.solid = false
	cover.rain_cover = true
	cover.outdoor_only = true
	assert_eq(ContentDB.validate_definitions([], [], [cover]), PackedStringArray())
	var indoor: ItemDef = cover.duplicate(true) as ItemDef
	indoor.outdoor_only = false
	assert_true(_has_error(ContentDB.validate_definitions([], [], [indoor]), "rain cover must be outdoor-only"))
	var normal: ItemDef = cover.duplicate(true) as ItemDef
	normal.placement_layer = ItemDef.PlacementLayer.NORMAL
	assert_true(_has_error(ContentDB.validate_definitions([], [], [normal]), "rain cover must be outdoor-only"))


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
	assert_eq(definition.section, RecipeDef.Section.BREAKFAST)
	assert_eq(_starter_db().recipe(&"tomato_soup").section, RecipeDef.Section.STARTERS)


func test_breakfast_uses_existing_stations_and_stocks_chilled_and_dry_ingredients() -> void:
	var db: ContentDB = _starter_db()
	var cooked: Array[StringName] = [&"bacon_and_eggs", &"fried_eggs", &"pancakes", &"waffles"]
	var breakfast: Array[StringName] = []
	for recipe: RecipeDef in db.recipes():
		if recipe.menu_section() != RecipeDef.Section.BREAKFAST:
			continue
		breakfast.append(recipe.id)
		assert_eq(recipe.unlock_level, 2)
		assert_eq(recipe.unlock_tier, 1)
		assert_false(recipe.default_enabled)
		assert_eq(recipe.theme_tags, [&"cafe", &"cosy"] as Array[StringName])
		assert_false(recipe.ingredients.is_empty())
		for ingredient: IngredientDef in recipe.ingredients:
			assert_eq(ingredient, db.ingredient(ingredient.id), "uses a stocked ingredient")
		assert_eq(recipe.steps.size(), 2 if cooked.has(recipe.id) else 1)
		assert_eq(recipe.steps[0].station_type, db.item(&"prep_counter").station_type)
		if cooked.has(recipe.id):
			assert_eq(recipe.steps[1].station_type, db.item(&"stove").station_type)
	assert_eq(breakfast, [&"bacon_and_eggs", &"cereal", &"fried_eggs", &"muffin", &"pancakes", &"waffles"] as Array[StringName])
	for ingredient_id: StringName in [&"egg", &"bacon", &"milk"]:
		assert_eq(db.ingredient(ingredient_id).storage, IngredientDef.Storage.FRIDGE)
	for ingredient_id: StringName in [&"cereal", &"flour", &"pastry"]:
		assert_eq(db.ingredient(ingredient_id).storage, IngredientDef.Storage.SHELF)


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


func test_unlock_links_load_as_owner_level_branches_without_changing_prices() -> void:
	var db: ContentDB = _starter_db()
	assert_eq(db.recipe(&"tomato_melt").unlock_from, &"burger")
	assert_eq(db.recipe(&"tea").unlock_from, &"coffee")
	assert_eq(db.recipe(&"wine").unlock_from, &"beer")
	assert_eq(db.recipe(&"fries").unlock_from, &"burger")
	assert_eq(db.recipe(&"savoury_pie").unlock_from, &"tomato_soup")
	assert_eq(RecipeDef.validate_unlocks(db.recipes()), PackedStringArray())
	assert_eq(db.recipe(&"burger").standard_price, 12)
	assert_eq(db.recipe(&"tomato_melt").unlock_level, 2)


func test_unlock_graph_rejects_unknown_parents_later_parents_and_cycles() -> void:
	var first: RecipeDef = _recipe()
	first.id = &"first"
	var second: RecipeDef = _recipe()
	second.id = &"second"
	first.unlock_from = &"missing"
	assert_true(_has_error(RecipeDef.validate_unlocks([first, second]), "unknown unlock prerequisite"))
	first.unlock_from = &"second"
	second.unlock_level = 2
	assert_true(_has_error(RecipeDef.validate_unlocks([first, second]), "must unlock no later"))
	second.unlock_level = 1
	second.unlock_from = &"first"
	assert_true(_has_error(RecipeDef.validate_unlocks([first, second]), "contain a cycle"))
	first.unlock_from = &"first"
	assert_true(_has_error(RecipeDef.validate_unlocks([first]), "contain a cycle"))
	first.unlock_from = &""
	assert_eq(RecipeDef.validate_unlocks([first, second]), PackedStringArray())
	assert_eq(first.unlock_level, 1, "validation never rewrites level data")


func test_quality_star_projection_is_bounded_without_replacing_quality() -> void:
	for row: Array in [[-1.0, 1], [0.0, 1], [0.2, 1], [0.4, 2], [0.6, 3], [0.8, 4], [1.0, 5], [2.0, 5]]:
		assert_eq(RecipeDef.quality_stars(row[0]), row[1])
	assert_eq(RecipeDef.quality_stars(NAN), 1)
	assert_eq(RecipeDef.quality_stars(INF), 1)


func test_fryer_and_oven_recipes_have_data_owned_prices_levels_sections_and_steps() -> void:
	var db: ContentDB = _starter_db()
	for row: Array in [[&"fries", &"fryer", 7, 2, RecipeDef.Section.SIDES, 49, 2],
			[&"savoury_pie", &"oven", 13, 3, RecipeDef.Section.MAINS, 91, 4]]:
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


func test_diner_classics_use_existing_stations_and_unlock_across_levels_two_to_four() -> void:
	var db: ContentDB = _starter_db()
	var specs: Dictionary[StringName, Array] = {
		&"club_sandwich": [2, RecipeDef.Section.MAINS, &"stove"],
		&"hot_dog": [2, RecipeDef.Section.MAINS, &"stove"],
		&"pizza_slice": [3, RecipeDef.Section.MAINS, &"oven"],
		&"taco": [3, RecipeDef.Section.MAINS, &"stove"],
		&"ice_cream_sundae": [4, RecipeDef.Section.DESSERTS, &""],
	}
	for id: StringName in specs:
		var recipe: RecipeDef = db.recipe(id)
		assert_not_null(recipe)
		var spec: Array = specs[id]
		assert_eq(recipe.unlock_level, spec[0])
		assert_eq(recipe.unlock_tier, 1)
		assert_eq(recipe.menu_section(), spec[1])
		assert_eq(recipe.theme_tags, ([&"diner", &"cafe"] if id == &"ice_cream_sundae" else [&"diner"]) as Array[StringName])
		assert_eq(recipe.steps[0].station_type, db.item(&"prep_counter").station_type)
		assert_eq(recipe.steps.size(), 1 if spec[2] == &"" else 2)
		if spec[2] != &"":
			assert_eq(recipe.steps[1].station_type, db.item(spec[2]).station_type)
		assert_false(recipe.ingredients.is_empty())
		for ingredient: IngredientDef in recipe.ingredients:
			assert_eq(ingredient, db.ingredient(ingredient.id))
	assert_eq(db.ingredient(&"sausage").storage, IngredientDef.Storage.FRIDGE)
	assert_eq(db.ingredient(&"tortilla").storage, IngredientDef.Storage.SHELF)
	assert_eq(db.ingredient(&"ice_cream").storage, IngredientDef.Storage.FREEZER)


func _recipe_resource_count(folder: String) -> int:
	var directory: DirAccess = DirAccess.open(folder)
	assert_not_null(directory)
	if directory == null:
		return 0
	var count: int = 0
	for file: String in directory.get_files():
		if file.ends_with(".tres"):
			count += 1
	for child: String in directory.get_directories():
		count += _recipe_resource_count(folder.path_join(child))
	return count
