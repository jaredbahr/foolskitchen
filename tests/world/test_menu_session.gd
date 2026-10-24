extends TestCase
## Menu requests, autosave/startup staging and the real kitchen's sale prices.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SAVE_DIR: String = "user://test_menu_sessions/"
const SLOT: String = "menu_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _paid_amounts: Array[int] = []
var _paid_recipes: Array[StringName] = []


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	SaveSystem.save_dir = SAVE_DIR
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SAVE_DIR)
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)
	_paid_amounts.clear()
	_paid_recipes.clear()


func test_menu_edits_autosave_once_and_restore_full_stock_without_recipe_mutation() -> void:
	var first: Node = _start()
	var settings: MenuSettings = first.get("menu_settings")
	assert_eq(settings.recipes().size(), 3)
	var standard: int = (first.get("content") as ContentDB).recipe(&"burger").standard_price
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	var backup: Dictionary = _document(true)
	assert_eq((backup["data"]["menu"]["enabled"] as Array).size(), 3, "one autosave after the change")
	assert_true(first.call("menu_set_price", &"burger", 15))
	backup = _document(true)
	assert_eq(backup["data"]["menu"]["prices"]["burger"], str(standard))
	var saved: Dictionary = settings.to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	_close(first)
	var second: Node = _start()
	assert_eq((second.get("menu_settings") as MenuSettings).to_dict(), saved)
	var sim: RestaurantSim = second.get("sim")
	assert_eq(sim.menu.size(), 2)
	assert_eq(sim.price_of((second.get("content") as ContentDB).recipe(&"burger")), 15)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq((second.get("content") as ContentDB).recipe(&"burger").standard_price, standard)
	assert_eq(second.get("last_menu_save_error"), OK)


func test_old_save_without_menu_gets_all_cookable_dishes_at_standard_prices() -> void:
	var first: Node = _start()
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(first.call("menu_set_price", &"burger", 18))
	var document: Dictionary = _document()
	document["data"].erase("menu")
	_write_document(document)
	_remove_backup()
	_close(first)
	var second: Node = _start()
	var settings: MenuSettings = second.get("menu_settings")
	assert_eq(settings.enabled_count(), 3)
	for recipe: RecipeDef in settings.recipes():
		assert_eq(settings.price_of(recipe), recipe.standard_price)
		assert_eq((second.get("sim") as RestaurantSim).price_of(recipe), recipe.standard_price)


func test_hud_and_real_panel_requests_enforce_morning_last_dish_and_clamps() -> void:
	var main: Node = _start(false)
	var menu_button: Button = main.get_node("HUD/Top/Row/Menu") as Button
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_false(menu_button.disabled)
	assert_false(panel.visible)
	menu_button.pressed.emit()
	assert_true(panel.visible)
	var row: Control = panel.row_for(&"burger")
	(row.get_node("Price/Plus") as Button).pressed.emit()
	assert_eq((main.get("menu_settings") as MenuSettings).price_of((main.get("content") as ContentDB).recipe(&"burger")), 13)
	assert_true(main.call("menu_set_enabled", &"grilled_cheese", false))
	assert_true(main.call("menu_set_enabled", &"tomato_soup", false))
	assert_false(main.call("menu_set_enabled", &"burger", false))
	assert_true((row.get_node("Top/Enabled") as Button).disabled)
	assert_true(main.call("menu_set_price", &"burger", -100))
	assert_eq((row.get_node("Price/Amount") as Label).text, "$6")
	assert_true(main.call("menu_set_price", &"burger", 1000))
	assert_eq((row.get_node("Price/Amount") as Label).text, "$24")
	var before: Dictionary = (main.get("menu_settings") as MenuSettings).to_dict()
	assert_true(Clock.sim.start_service())
	assert_true(menu_button.disabled)
	assert_false(menu_button.tooltip_text.is_empty())
	assert_false(panel.visible)
	panel.price_requested.emit(&"burger", 12)
	panel.enable_requested.emit(&"tomato_soup", true)
	assert_false(main.call("menu_set_price", &"burger", 12))
	assert_eq((main.get("menu_settings") as MenuSettings).to_dict(), before)
	menu_button.pressed.emit()
	assert_false(panel.visible)


func test_actual_kitchen_orders_and_sales_use_only_enabled_override() -> void:
	var main: Node = _start(false)
	assert_true(main.call("menu_set_enabled", &"grilled_cheese", false))
	assert_true(main.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(main.call("menu_set_price", &"burger", 9))
	var sim: RestaurantSim = main.get("sim")
	sim.customer_paid.connect(_on_paid)
	assert_true(Clock.sim.start_service())
	for _guard: int in range(30):
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
		main.call("run_ticks", 1000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(_paid_amounts.size() > 0)
	for index: int in range(_paid_amounts.size()):
		assert_eq(_paid_amounts[index], 9)
		assert_eq(_paid_recipes[index], &"burger")
	assert_eq(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.SALE, 0), _paid_amounts.size() * 9)
	assert_eq(sim.served_today, _paid_amounts.size())
	assert_eq(sim.leave_reasons_today.get(&"too_expensive", 0), 0)
	assert_eq((main.get("content") as ContentDB).recipe(&"burger").standard_price, 12)


func test_invalid_menu_starts_fresh_skips_next_save_then_menu_edits_can_save() -> void:
	var first: Node = _start()
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	var document: Dictionary = _document()
	document["data"]["menu"]["prices"]["burger"] = "not_a_price"
	_write_document(document)
	_remove_backup()
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	var settings: MenuSettings = second.get("menu_settings")
	assert_eq(Clock.sim.day, 1)
	assert_eq(settings.enabled_count(), 3)
	assert_eq(settings.price_of((second.get("content") as ContentDB).recipe(&"burger")), 12)
	assert_eq(FileAccess.get_file_as_string(_path()), broken, "failed startup skips its next morning autosave")
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	assert_true(second.call("menu_set_price", &"burger", 15))
	assert_eq(second.get("last_menu_save_error"), OK)
	assert_eq(_document()["data"]["menu"]["prices"]["burger"], "15", "a later user menu edit is a morning save boundary")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)


func test_invalid_menu_provider_does_not_fall_back_to_a_semantic_backup() -> void:
	var first: Node = _start()
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(first.call("menu_set_price", &"burger", 15))
	assert_true(first.call("menu_set_price", &"burger", 16))
	var good_backup: String = FileAccess.get_file_as_string(_path() + ".bak")
	var saved: Dictionary = _document(true)["data"]["menu"]
	var document: Dictionary = _document()
	document["data"]["clock"]["day"] = 9
	document["data"]["menu"]["prices"]["burger"] = "not_a_price"
	_write_document(document)
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	var settings: MenuSettings = second.get("menu_settings")
	assert_eq(Clock.sim.day, 1, "provider failure follows the existing fresh-game path")
	assert_eq(settings.enabled_count(), 3)
	assert_eq(settings.price_of((second.get("content") as ContentDB).recipe(&"burger")), 12)
	assert_ne(settings.to_dict(), saved, "a readable primary with a rejected provider returns FAILED, without semantic fallback")
	assert_eq(FileAccess.get_file_as_string(_path()), broken)
	assert_eq(FileAccess.get_file_as_string(_path() + ".bak"), good_backup)


func test_menu_then_furniture_edit_reload_keeps_both_committed_sections() -> void:
	var first: Node = _start()
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(first.call("menu_set_price", &"burger", 9))
	var before_buy: String = FileAccess.get_file_as_string(_path())
	assert_true(first.call("shop_buy", &"chair", Vector2i(4, 9)))
	assert_eq(FileAccess.get_file_as_string(_path()), before_buy, "a shop edit no longer saves itself")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(SaveSystem.save_game(SLOT), OK)  # An explicit valid MORNING save.
	var menu: Dictionary = (first.get("menu_settings") as MenuSettings).to_dict()
	var shop: Dictionary = (first.get("shop_editor") as ShopEditor).to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	_close(first)
	var second: Node = _start()
	assert_eq((second.get("menu_settings") as MenuSettings).to_dict(), menu)
	assert_eq((second.get("shop_editor") as ShopEditor).to_dict(), shop)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq((second.get("sim") as RestaurantSim).price_of((second.get("content") as ContentDB).recipe(&"burger")), 9)


func test_menu_restore_provider_only_stages_choices_without_touching_the_live_sim() -> void:
	var main: Node = _start(false)
	var settings: MenuSettings = main.get("menu_settings")
	var before: Dictionary = settings.to_dict()
	var staged: Dictionary = before.duplicate(true)
	staged["enabled"] = ["burger"]
	staged["prices"]["burger"] = "15"
	var sim: RestaurantSim = main.get("sim")
	var prices: Dictionary[StringName, int] = sim.prices.duplicate()
	assert_true(main.call("_restore_menu", staged))
	assert_eq(settings.to_dict(), before)
	assert_eq(sim.menu.size(), 3)
	assert_eq(sim.prices, prices)
	assert_true(main.get("sim") == sim, "live menu installation waits for normal load success")


func test_save_failure_keeps_menu_committed_and_retry_does_not_restock() -> void:
	var main: Node = _start()
	main.set("save_slot", "invalid/slot")
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	assert_true(main.call("menu_set_price", &"burger", 15))
	assert_eq(main.get("last_menu_save_error"), ERR_INVALID_PARAMETER)
	var saved: Dictionary = (main.get("menu_settings") as MenuSettings).to_dict()
	assert_eq((main.get("sim") as RestaurantSim).price_of((main.get("content") as ContentDB).recipe(&"burger")), 15)
	main.set("save_slot", SLOT)
	assert_eq(main.call("save_menu_changes"), OK)
	assert_eq(main.get("last_menu_save_error"), OK)
	assert_eq(_document()["data"]["menu"], saved)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)


func test_cookable_catalog_requires_the_actual_station_definitions() -> void:
	var main: Node = _start(false)
	var layout: ShopLayout = ShopLayout.new()
	var missing: ShopPlacement = ShopPlacement.new()
	missing.item_id = &"potted_plant"
	layout.placements = [missing]
	var recipes: Array[RecipeDef] = main.call("_cookable_recipes", layout)
	assert_true(recipes.is_empty(), "decorations cannot supply kitchen stations")
	var authored: ShopLayout = load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout
	layout.placements = authored.placements.duplicate()
	recipes = main.call("_cookable_recipes", layout)
	assert_eq(recipes.size(), 3)
	var content: ContentDB = main.get("content")
	for index: int in range(layout.placements.size() - 1, -1, -1):
		if content.item(layout.placements[index].item_id).station_type == &"stove":
			layout.placements.remove_at(index)
	recipes = main.call("_cookable_recipes", layout)
	assert_true(recipes.is_empty(), "all current dishes need their stove step")
	assert_eq((main.get("menu_settings") as MenuSettings).recipes().size(), 3, "catalog checks do not mutate the live menu")


func _start(with_saves: bool = true) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	var sim: RestaurantSim = main.get("sim")
	if sim != null and sim.customer_paid.is_connected(_on_paid):
		sim.customer_paid.disconnect(_on_paid)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _on_paid(_guest: CustomerAgent, order: Order, amount: int) -> void:
	_paid_amounts.append(amount)
	_paid_recipes.append(order.recipe_id)


func _path() -> String:
	return SAVE_DIR.path_join(SLOT + ".json")


func _document(backup: bool = false) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path() + (".bak" if backup else "")))


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")
