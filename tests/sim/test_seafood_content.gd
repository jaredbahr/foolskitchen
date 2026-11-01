extends TestCase
## FK-076 data-only seafood branch: authored ingredients, progression and floor.

const ECONOMY: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const INGREDIENTS: Array[StringName] = [&"fish_fillet", &"shrimp", &"mussels", &"rice", &"lemon"]
const DISHES: Array[StringName] = [&"fish_and_chips", &"mussels_broth", &"salmon_maki", &"shrimp_skewer", &"seafood_stew"]
var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func test_seafood_ingredients_have_their_authored_storage_and_conditional_targets() -> void:
	var kinds: Array[int] = [IngredientDef.Storage.FREEZER, IngredientDef.Storage.FREEZER,
		IngredientDef.Storage.FRIDGE, IngredientDef.Storage.SHELF, IngredientDef.Storage.FRIDGE]
	var settings: ReorderSettings = ReorderSettings.new(ECONOMY)
	for index: int in INGREDIENTS.size():
		var ingredient: IngredientDef = _content.ingredient(INGREDIENTS[index])
		assert_not_null(ingredient)
		assert_eq(int(ingredient.storage), kinds[index], String(ingredient.id))
		assert_true(ingredient.unit_cost > 0)
		assert_true(ingredient.shelf_life_days > 0)
		assert_false(ECONOMY.morning_stock.has(ingredient.id), "seafood never joins the fixed starter order")
		assert_eq(ECONOMY.station_stock[ingredient.id], _target(ingredient.id))
		assert_eq(settings.default_target(ingredient.id), _target(ingredient.id))
		assert_false(settings.ids().has(ingredient.id), "an unused seafood ingredient is not ordered")
	settings.set_in_use(INGREDIENTS)
	var costs: Dictionary = {}
	for ingredient: IngredientDef in _content.ingredients():
		costs[ingredient.id] = ingredient.unit_cost
	var plan: Dictionary = settings.plan(Stock.new(), costs, 10000, 0.0, true)
	assert_eq((plan["lines"] as Array).size(), INGREDIENTS.size())
	for line: Dictionary in plan["lines"]:
		assert_true(INGREDIENTS.has(line["id"]))
		assert_eq(line["qty"], _target(line["id"]))
	settings.set_in_use([])
	assert_true((settings.plan(Stock.new(), costs, 10000, 0.0, true)["lines"] as Array).is_empty())


func test_seafood_unlock_links_levels_sections_and_stations_form_a_valid_branch() -> void:
	var parents: Array[StringName] = [&"fries", &"tomato_soup", &"fish_and_chips", &"mussels_broth", &"shrimp_skewer"]
	var levels: Array[int] = [2, 3, 4, 4, 5]
	var sections: Array[int] = [RecipeDef.Section.MAINS, RecipeDef.Section.STARTERS,
		RecipeDef.Section.STARTERS, RecipeDef.Section.MAINS, RecipeDef.Section.MAINS]
	var stations: Array[Array] = [[&"prep_counter", &"fryer"], [&"stove"], [&"prep_counter"],
		[&"stove"], [&"prep_counter", &"stove"]]
	assert_eq(RecipeDef.validate_unlocks(_content.recipes()), PackedStringArray())
	var choices: Array[RecipeDef] = [_content.recipe(&"burger"), _content.recipe(&"grilled_cheese"), _content.recipe(&"tomato_soup")]
	for id: StringName in DISHES:
		choices.append(_content.recipe(id))
	var menu: MenuSettings = MenuSettings.new(choices)
	for index: int in DISHES.size():
		var recipe: RecipeDef = _content.recipe(DISHES[index])
		assert_not_null(recipe)
		assert_eq(recipe.unlock_from, parents[index])
		assert_eq(recipe.unlock_level, levels[index])
		assert_eq(recipe.unlock_tier, 1)
		assert_eq(recipe.menu_section(), sections[index])
		assert_eq(recipe.theme_tags, [&"seafood"] as Array[StringName])
		assert_false(recipe.is_drink())
		var actual_stations: Array[StringName] = []
		for step: RecipeStep in recipe.steps:
			actual_stations.append(step.station_type)
			assert_true(step.duration_ticks > 0)
		assert_eq(actual_stations, stations[index])
		assert_true(recipe.standard_price > recipe.ingredient_cost())
		assert_true(menu.set_owner_level(levels[index] - 1))
		assert_false(menu.set_enabled(recipe.id, true), "level gate remains authoritative")
		assert_true(menu.set_owner_level(levels[index]))
		assert_true(menu.set_enabled(recipe.id, true))
		assert_true(menu.set_enabled(recipe.id, false))
	assert_eq(_content.recipe(&"fish_and_chips").ingredients[1].id, &"potato")
	assert_eq(_content.recipe(&"fish_and_chips").ingredients[2].id, &"oil")


func test_deck_planks_reuses_the_existing_pattern_and_palette_without_changing_the_starter_floor() -> void:
	var floor: FloorStyleDef = _content.floor_style(&"deck_planks")
	assert_not_null(floor)
	assert_eq(floor.display_name, "Deck planks")
	assert_eq(floor.pattern, FloorStyleDef.Pattern.PLANKS)
	assert_eq([floor.default_swatch, floor.default_accent], [&"slate_blue", &"cream"])
	assert_eq(floor.theme_tags, [&"seafood"] as Array[StringName])
	assert_false(floor.unlocked(3))
	assert_true(floor.unlocked(4))
	assert_eq(floor.price, 3)
	assert_not_null(_content.swatch(floor.default_swatch))
	assert_not_null(_content.swatch(floor.default_accent))
	assert_eq(_content.floor_style(FloorStyleDef.DEFAULT_ID).price, 0)
	assert_eq(_content.floor_styles().size(), 11)
	assert_eq(FloorStyleDef.Pattern.values(), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "no shader pattern is added")


## Pricey seafood restocks in smaller batches (6) to limit waste; rice and lemon keep 12.
func _target(id: StringName) -> int:
	return 6 if id in [&"fish_fillet", &"shrimp", &"mussels"] else 12
