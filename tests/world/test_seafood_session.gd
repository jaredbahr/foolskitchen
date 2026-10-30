extends TestCase
## Seafood goes through the same equipment hints, menu choices and real kitchen.

const DISHES: Array[StringName] = [&"fish_and_chips", &"mussels_broth", &"salmon_maki", &"shrimp_skewer", &"seafood_stew"]
const SEAFOOD: Array[StringName] = [&"fish_fillet", &"shrimp", &"mussels", &"rice", &"lemon"]
var _mains: Array[Node] = []


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_starter_menu_and_orders_are_unchanged_and_new_food_waits_for_the_player() -> void:
	var main: Node = _start()
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_eq(_ids(settings.enabled_recipes()), [&"burger", &"grilled_cheese", &"tomato_soup"] as Array[StringName])
	for id: StringName in DISHES:
		assert_false(settings.is_enabled(id))
	for id: StringName in SEAFOOD:
		assert_eq(Economy.stock.count(id), 0)
		assert_false((main.get("reorder_settings") as ReorderSettings).ids().has(id))
	assert_true(settings.set_owner_level(5))
	main.call("_refresh_menu_catalogue")
	for id: StringName in DISHES:
		assert_false(settings.is_enabled(id), "a level-up never picks a new dish")
	assert_true(Clock.sim.start_service())
	for id: StringName in SEAFOOD:
		assert_eq(Economy.stock.count(id), 0, "no seafood is purchased for the starter menu")


func test_equipment_reasons_cover_missing_fryer_and_freezer_without_mutating_the_menu() -> void:
	var main: Node = _start()
	var before_menu: Dictionary = (main.get("menu_settings") as MenuSettings).to_dict()
	var before_books: Dictionary = Economy.ledger.to_dict()
	var before_random: Dictionary = GameState.call("_capture_save")
	var details: Dictionary = main.call("menu_recipe_details")
	assert_true(details[&"fish_and_chips"]["equipment"].has({"text": "Buy a fryer", "met": false}))
	for id: StringName in [&"fish_and_chips", &"salmon_maki", &"shrimp_skewer", &"seafood_stew"]:
		assert_true(details[id]["equipment"].has({"text": "Buy a freezer", "met": false}), String(id))
	assert_false(details[&"mussels_broth"]["equipment"].has({"text": "Buy a freezer", "met": false}))
	assert_true(details[&"mussels_broth"]["equipment"].has({"text": "Stove ready", "met": true}))
	assert_true(details[&"salmon_maki"]["equipment"].has({"text": "Prep counter ready", "met": true}))
	assert_eq((main.get("menu_settings") as MenuSettings).to_dict(), before_menu)
	assert_eq(Economy.ledger.to_dict(), before_books)
	assert_eq(GameState.call("_capture_save"), before_random)
	_prepare(main)
	details = main.call("menu_recipe_details")
	assert_true(details[&"fish_and_chips"]["equipment"].has({"text": "Fryer ready", "met": true}))
	for id: StringName in [&"fish_and_chips", &"salmon_maki", &"shrimp_skewer", &"seafood_stew"]:
		assert_true(details[id]["equipment"].has({"text": "Freezer ready", "met": true}), String(id))


func test_every_seafood_dish_cooks_delivers_and_gets_paid_during_its_own_service_day() -> void:
	for id: StringName in DISHES:
		var main: Node = _start()
		_prepare(main)
		assert_true(main.call("menu_set_enabled", id, true), String(id))
		var settings: MenuSettings = main.get("menu_settings") as MenuSettings
		for recipe: RecipeDef in settings.enabled_recipes():
			if recipe.id != id:
				assert_true(main.call("menu_set_enabled", recipe.id, false))
		assert_true(Clock.sim.start_service())
		var recipe: RecipeDef = (main.get("content") as ContentDB).recipe(id)
		var stock_before: Dictionary[StringName, int] = {}
		for ingredient: IngredientDef in recipe.ingredients:
			stock_before[ingredient.id] = Economy.stock.count(ingredient.id)
			assert_true(Economy.stock.count(ingredient.id) > 0, "%s ordered %s" % [id, ingredient.id])
		var sim: RestaurantSim = main.get("sim") as RestaurantSim
		for guard: int in range(30):
			if Clock.sim.phase == SimClock.Phase.CLOSED:
				break
			main.call("run_ticks", 1000)
		assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, String(id))
		var sold: int = int((main.get("dishes_sold_today") as Dictionary).get(id, 0))
		assert_true(sold > 0, "%s must cook, deliver and receive payment" % id)
		assert_eq(sim.served_today, sold, "only this seafood dish is enabled")
		assert_true((Economy.ledger.day_totals(1).get(Ledger.SALE, 0) as int) > 0)
		for order: Order in sim.orders.orders_in_state(Order.State.DELIVERED):
			assert_eq(order.recipe_id, id)
			assert_true(order.quality > 0.0)
			assert_not_null(order.quality_breakdown)
		for ingredient_id: StringName in stock_before:
			assert_true(Economy.stock.count(ingredient_id) < stock_before[ingredient_id],
				"a seafood order consumes every authored ingredient")
		print("SEAFOOD_SERVICE dish=%s served=%d lost=%d" % [id, sim.served_today, sim.lost_today])
		_close(main)


func test_deck_planks_lays_through_the_normal_edit_and_survives_the_shop_snapshot() -> void:
	var main: Node = _start()
	_prepare(main)
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var style: FloorStyleDef = (main.get("content") as ContentDB).floor_style(&"deck_planks")
	var cells: Array[Vector2i] = [Vector2i(3, 8), Vector2i(4, 8)]
	var changes: Dictionary[Vector2i, FloorFinishes.Finish] = editor.lay_changes(cells,
		style.id, style.default_swatch, style.default_accent)
	var cash: int = Economy.cash
	assert_true(main.call("shop_flooring", changes))
	assert_eq(Economy.cash, cash - style.price * cells.size())
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(editor.to_dict(),
		load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout,
		main.get("content") as ContentDB, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	for cell: Vector2i in cells:
		assert_eq(layout.floor_finishes[cell], PackedStringArray([style.id, style.default_swatch, style.default_accent]))


func _start() -> Node:
	var main: Node = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 126)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _prepare(main: Node) -> void:
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	progress.award_bonus(progress.threshold_for(5))
	assert_true((main.get("menu_settings") as MenuSettings).set_owner_level(5))
	(main.get("shop_editor") as ShopEditor).set_owner_level(5)
	Economy.add_cash(10000, Ledger.OTHER)
	assert_true(main.call("shop_buy", &"fryer", Vector2i(9, 3), 0))
	assert_true(main.call("shop_buy", &"freezer", Vector2i(12, 3), 0))
	assert_true(main.call("shop_buy", &"fridge", Vector2i(11, 1), 2))
	assert_true(main.call("shop_buy", &"storage_shelf", Vector2i(3, 1), 2))


func _ids(recipes: Array[RecipeDef]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for recipe: RecipeDef in recipes:
		ids.append(recipe.id)
	return ids


func _close(main: Node) -> void:
	_mains.erase(main)
	if is_instance_valid(main):
		if main.is_inside_tree():
			main.get_parent().remove_child(main)
		main.free()
