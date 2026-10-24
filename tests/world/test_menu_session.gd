extends TestCase
## Menu requests, autosave/startup staging and the real kitchen's sale prices.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "menu_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _paid_amounts: Array[int] = []
var _paid_recipes: Array[StringName] = []
var _old_default_speed: int


func before_each() -> void:
	_old_default_speed = Preferences.default_open_speed
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "menu_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	Preferences.default_open_speed = _old_default_speed
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)
	_paid_amounts.clear()
	_paid_recipes.clear()


func test_menu_edits_wait_for_next_morning_then_reload_without_recipe_mutation() -> void:
	var first: Node = _start()
	var settings: MenuSettings = first.get("menu_settings")
	assert_eq(settings.recipes().size(), 4)
	assert_eq(settings.enabled_count(), 3, "the fourth recipe is visible but locked")
	var standard: int = (first.get("content") as ContentDB).recipe(&"burger").standard_price
	var morning_file: String = FileAccess.get_file_as_string(_path())
	var before_books: Dictionary = Economy.ledger.to_dict()
	var before_stock: Dictionary = Economy.stock.to_dict()
	var before_clock: Dictionary = Clock.sim.to_dict()
	var before_rng: int = GameState.rng(&"customers").state
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file)
	assert_true(first.call("menu_set_price", &"burger", 15))
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file)
	assert_eq(Economy.ledger.to_dict(), before_books)
	assert_eq(Economy.stock.to_dict(), before_stock)
	assert_eq(Clock.sim.to_dict(), before_clock)
	assert_eq(GameState.rng(&"customers").state, before_rng)
	var saved: Dictionary = settings.to_dict()
	_next_morning()
	assert_eq(_document()["data"]["menu"], saved)
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.day, 2)
	assert_eq((second.get("menu_settings") as MenuSettings).to_dict(), saved)
	var sim: RestaurantSim = second.get("sim")
	assert_eq(sim.menu.size(), 2)
	assert_eq(sim.price_of((second.get("content") as ContentDB).recipe(&"burger")), 15)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq((second.get("content") as ContentDB).recipe(&"burger").standard_price, standard)


func test_old_save_without_menu_gets_all_cookable_dishes_at_standard_prices() -> void:
	var first: Node = _start()
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(first.call("menu_set_price", &"burger", 18))
	_next_morning()
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


func test_menu_settings_entry_opens_and_returns_without_changing_dishes() -> void:
	var main: Node = _start(false)
	var menu_button: Button = main.get_node("HUD/Top/Row/Menu") as Button
	var menu: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	var settings: SettingsPanel = main.get_node("Overlay/SettingsPanel") as SettingsPanel
	var before: Dictionary = (main.get("menu_settings") as MenuSettings).to_dict()
	menu_button.pressed.emit()
	assert_true(menu.visible)
	(menu.get_node("Panel/Content/SettingsButton") as Button).pressed.emit()
	assert_false(menu.visible)
	assert_true(settings.visible)
	assert_eq(settings.theme, preload("res://src/ui/theme/main_theme.tres"))
	(settings.get_node("Panel/Scroll/Content/CloseButton") as Button).pressed.emit()
	assert_false(settings.visible)
	assert_true(menu.visible)
	assert_eq((main.get("menu_settings") as MenuSettings).to_dict(), before)
	assert_true(main.call("set_menu_visible", false))
	Preferences.default_open_speed = 2
	(main.get_node("HUD/Top/Row/Context") as Button).pressed.emit()
	assert_eq(Clock.speed, 2, "the real Main binds its saved opening-speed preference")


func test_settings_modal_blocks_outside_clicks_from_the_hud_menu() -> void:
	var main: Node = _start(false)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu_button: Button = main.get_node("HUD/Top/Row/Menu") as Button
	var menu: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	var settings: SettingsPanel = main.get_node("Overlay/SettingsPanel") as SettingsPanel
	menu_button.pressed.emit()
	(menu.get_node("Panel/Content/SettingsButton") as Button).pressed.emit()
	await tree.process_frame
	await tree.process_frame
	assert_eq(settings.mouse_filter, Control.MOUSE_FILTER_STOP)
	var point: Vector2 = menu_button.get_global_rect().get_center()
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.position = point
	mouse.global_position = point
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse.pressed = true
	tree.root.push_input(mouse, true)
	mouse.pressed = false
	mouse.button_mask = 0
	tree.root.push_input(mouse, true)
	assert_true(settings.visible, "outside-card clicks stay in the modal")
	assert_false(menu.visible, "the underlying Menu button never receives that click")


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


func test_invalid_menu_slot_is_untouched_by_edits_until_next_morning() -> void:
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
	var clock: Dictionary = Clock.sim.to_dict()
	var rng_state: int = GameState.rng(&"customers").state
	assert_true(second.call("menu_set_price", &"burger", 15))
	assert_eq(FileAccess.get_file_as_string(_path()), broken, "the first price change cannot bypass the failed-load skip")
	assert_true(second.call("menu_set_enabled", &"tomato_soup", false))
	assert_eq(FileAccess.get_file_as_string(_path()), broken, "enabled changes also leave the bad slot untouched today")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.rng(&"customers").state, rng_state)
	_next_morning()
	assert_eq(int(_document()["data"]["clock"]["day"]), 2)
	assert_eq(_document()["data"]["menu"], settings.to_dict(), "normal later morning autosaves resume")


func test_invalid_menu_provider_does_not_fall_back_to_a_semantic_backup() -> void:
	var first: Node = _start()
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(first.call("menu_set_price", &"burger", 15))
	_next_morning()
	assert_true(first.call("menu_set_price", &"burger", 16))
	_next_morning()
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
	var menu: Dictionary = (first.get("menu_settings") as MenuSettings).to_dict()
	var shop: Dictionary = (first.get("shop_editor") as ShopEditor).to_dict()
	_next_morning()
	assert_eq(_document()["data"]["menu"], menu)
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


func test_panel_edits_do_not_save_restock_or_draw_rng_before_next_morning() -> void:
	var main: Node = _start()
	var morning_file: String = FileAccess.get_file_as_string(_path())
	var full_count: int = Economy.stock.count(&"bun")
	var consumed: Dictionary[StringName, int] = {&"bun": 1}
	assert_true(Economy.stock.take_many(consumed))
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var rng_state: int = GameState.rng(&"customers").state
	(main.get_node("HUD/Top/Row/Menu") as Button).pressed.emit()
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_true(panel.visible)
	(panel.row_for(&"burger").get_node("Price/Plus") as Button).pressed.emit()
	var soup_toggle: Button = panel.row_for(&"tomato_soup").get_node("Top/Enabled") as Button
	soup_toggle.button_pressed = false
	var saved: Dictionary = (main.get("menu_settings") as MenuSettings).to_dict()
	assert_eq((main.get("sim") as RestaurantSim).price_of((main.get("content") as ContentDB).recipe(&"burger")), 13)
	assert_false((main.get("menu_settings") as MenuSettings).is_enabled(&"tomato_soup"))
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.rng(&"customers").state, rng_state)
	_next_morning()
	assert_eq(_document()["data"]["menu"], saved)
	assert_eq(Economy.stock.count(&"bun"), full_count, "ordinary morning setup still performs the stock top-up")


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
	assert_eq(recipes.size(), 4)
	var content: ContentDB = main.get("content")
	for index: int in range(layout.placements.size() - 1, -1, -1):
		if content.item(layout.placements[index].item_id).station_type == &"stove":
			layout.placements.remove_at(index)
	recipes = main.call("_cookable_recipes", layout)
	assert_true(recipes.is_empty(), "all current dishes need their stove step")
	assert_eq((main.get("menu_settings") as MenuSettings).recipes().size(), 4, "catalog checks do not mutate the live menu")


## Persistence fixtures skip service; the real kitchen/order test above covers it.
func _next_morning() -> void:
	var previous_day: int = Clock.sim.day
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.day, previous_day + 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


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
	return _save_dir.path_join(SLOT + ".json")


func _document(backup: bool = false) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path() + (".bak" if backup else "")))


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")
