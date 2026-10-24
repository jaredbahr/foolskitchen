extends TestCase
## The first level-two dish uses existing cookable content without new assets.


func test_tomato_melt_loads_from_real_content_and_waits_for_owner_level_two() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var recipe: RecipeDef = content.recipe(&"tomato_melt")
	assert_not_null(recipe)
	assert_eq(recipe.display_name, "Tomato melt")
	assert_eq(recipe.unlock_tier, 1)
	assert_eq(recipe.unlock_level, 2)
	assert_eq(recipe.standard_price, 10)
	assert_true(recipe.base_quality > 0.0 and recipe.base_quality <= 1.0)
	var ingredient_ids: Array[StringName] = []
	for ingredient: IngredientDef in recipe.ingredients:
		assert_not_null(content.ingredient(ingredient.id))
		ingredient_ids.append(ingredient.id)
	assert_eq(ingredient_ids, [&"bread", &"bread", &"cheese", &"tomato"] as Array[StringName])
	assert_eq(recipe.ingredient_cost(), 4)
	var station_types: Array[StringName] = []
	for step: RecipeStep in recipe.steps:
		station_types.append(step.station_type)
	assert_eq(station_types, [&"prep_counter", &"stove"] as Array[StringName])
	assert_eq(recipe.total_ticks(), 85)
	var menu: MenuSettings = MenuSettings.new(content.recipes())
	assert_true(menu.is_valid())
	assert_eq(menu.recipe(&"tomato_melt"), recipe)
	assert_false(menu.is_enabled(&"tomato_melt"))
	assert_false(menu.set_enabled(&"tomato_melt", true))
	assert_true(menu.set_owner_level(2))
	assert_false(menu.is_enabled(&"tomato_melt"))
	assert_true(menu.set_enabled(&"tomato_melt", true))
