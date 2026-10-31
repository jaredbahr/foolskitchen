extends TestCase
## FK-083 in the production session: stations put drinks on the menu, the
## Drinks section and its hints, opening hours in the morning save, wages by
## the hour, and only in-use station ingredients on the morning order.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const HOURS: OpeningHoursTuning = preload("res://data/balance/hours.tres")
const SLOT: String = "concept_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "concept_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains:
		if is_instance_valid(main):
			if main.is_inside_tree():
				main.get_parent().remove_child(main)
			main.free()
	_mains.clear()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start(with_saves: bool) -> Node:
	var main: Node = MainScene.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _menu_ids(main: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for recipe: RecipeDef in (main.get("menu_settings") as MenuSettings).recipes():
		ids.append(recipe.id)
	return ids


## Ingredients the Stock panel lists as in use (others are greyed out, FK-087).
func _stock_ids(main: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row: Dictionary in main.call("stock_rows"):
		if row["in_use"]:
			ids.append(row["id"])
	return ids


func test_a_coffee_machine_puts_coffee_tea_and_pastries_on_the_menu_until_it_is_sold() -> void:
	var main: Node = _start(false)
	assert_false(_menu_ids(main).has(&"coffee"), "no machine, no coffee")
	assert_false(_stock_ids(main).has(&"coffee_beans"), "nor beans on the order")
	for id: StringName in TUNING.station_stock:
		assert_eq(Economy.stock.count(id), 0, "%s is not bought for a shop that cannot use it" % id)
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_true(main.call("set_menu_visible", true))
	assert_not_null(panel.tree_item_for(&"coffee"), "the tree reveals unavailable recipes")
	assert_true((panel.row_for(&"coffee").get_node("Top/Enabled") as Button).disabled, "no machine, no coffee choice")
	var hints: Array[String] = main.call("drink_station_hints")
	assert_eq(hints, ["Coffee, tea and croissant: buy a coffee machine.", "Beer: buy a drinks shelf.",
		"Soft drink: buy a drinks fridge."] as Array[String], "named items, never ids")
	assert_true(main.call("set_menu_visible", false))
	assert_true(main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	for id: StringName in [&"coffee", &"tea"]:
		assert_true(settings.is_enabled(id), "%s joins the menu, switched on" % id)
	assert_true(settings.recipe(&"croissant") != null and not settings.is_enabled(&"croissant"),
		"a new dish is listed but waits for the player")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	assert_true(sim.menu.has((main.get("content") as ContentDB).recipe(&"coffee")), "today's service offers it")
	assert_eq(sim.visit_kinds(), [RecipeDef.FOOD, RecipeDef.COFFEE] as Array[StringName])
	assert_true(_stock_ids(main).has(&"coffee_beans"), "coffee is on, so its beans are ordered")
	assert_eq(Economy.stock.count(&"coffee_beans"), 0, "editing buys no stock; opening does")
	assert_false(_stock_ids(main).has(&"pastry"), "the croissant is off, so no pastries yet")
	assert_true(main.call("menu_set_enabled", &"croissant", true))
	assert_true(_stock_ids(main).has(&"pastry"))
	assert_false(_stock_ids(main).has(&"beer"))
	assert_true(main.call("set_menu_visible", true))
	assert_true(panel.select_recipe(&"coffee"))
	assert_true(panel.drinks_section().is_ancestor_of(panel.row_for(&"coffee")))
	assert_false((panel.row_for(&"coffee").get_node("Top/Enabled") as Button).disabled, "the machine enables the selected drink")
	assert_not_null(panel.row_for(&"croissant"), "the pastry is listed under Food")
	assert_false(panel.drinks_section().is_ancestor_of(panel.row_for(&"croissant")))
	assert_true(main.call("set_menu_visible", false))
	var machine: PlacedItem = sim.world.grid.item_at(Vector2i(12, 5))
	assert_true(int(main.call("shop_sell", machine.id)) >= 0)
	assert_false(_menu_ids(main).has(&"coffee"), "selling the machine takes coffee off")
	assert_false(_stock_ids(main).has(&"coffee_beans"))
	assert_true(settings.is_valid() and settings.enabled_count() >= 1)


func test_undo_and_redo_of_a_coffee_machine_return_money_exactly_and_keep_menu_choices() -> void:
	var main: Node = _start(false)
	Economy.add_cash(1000, Ledger.SALE)
	assert_true(main.call("set_build_active", true))
	var cash: int = Economy.cash
	assert_true(main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	assert_eq(Economy.cash, cash - 120, "only the machine is paid for; supplies wait for opening")
	assert_true(main.call("menu_set_price", &"coffee", 6))
	assert_true(main.call("menu_set_enabled", &"tea", false))
	assert_true(main.call("menu_set_enabled", &"croissant", true))
	assert_true(main.call("undo_edit"))
	assert_eq(Economy.cash, cash, "undo refunds exactly")
	assert_false(_menu_ids(main).has(&"coffee"))
	assert_true(main.call("redo_edit"))
	assert_eq(Economy.cash, cash - 120)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_eq(settings.price_of(settings.recipe(&"coffee")), 6, "the price came back")
	assert_false(settings.is_enabled(&"tea"), "tea stays off")
	assert_true(settings.is_enabled(&"croissant"), "the croissant stays on")
	# The pantry is nearly full of the morning's food: a shelf holds the new supplies (FK-087).
	assert_true(main.call("shop_buy", &"storage_shelf", Vector2i(12, 1), 2))
	assert_true(main.call("set_build_active", false))
	assert_eq(Economy.stock.count(&"coffee_beans"), 0)
	# The player fixes these station targets before opening; other rows stay automatic.
	assert_true(main.call("stock_set_target", &"coffee_beans", TUNING.station_stock[&"coffee_beans"]))
	assert_true(main.call("stock_set_target", &"pastry", TUNING.station_stock[&"pastry"]))
	assert_true(Clock.sim.start_service())
	assert_eq(Economy.stock.count(&"coffee_beans"), TUNING.station_stock[&"coffee_beans"], "opening tops up the new supplies")
	assert_eq(Economy.stock.count(&"pastry"), TUNING.station_stock[&"pastry"])
	assert_eq(Economy.stock.count(&"tea"), 0, "tea is off, so none is bought")


func test_drinks_behind_a_closed_bar_stay_off_the_menu_with_a_reason() -> void:
	var main: Node = _start(false)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var editor: ShopEditor = ProbeSetups._free_editor(main)
	assert_true(ProbeSetups._clear_east_table(main, editor))
	assert_true(editor.buy(&"drinks_shelf", Vector2i(10, 5), 2) and editor.buy(&"drinks_fridge", Vector2i(11, 5), 2))
	for x: int in range(9, 13):
		assert_true(editor.buy(&"bar_section", Vector2i(x, 7), 2) and editor.buy(&"bar_stool", Vector2i(x, 8), 0))
	main.call("_refresh_menu_catalogue")
	assert_true(_menu_ids(main).has(&"beer"), "an open-ended bar serves beer")
	for y: int in [5, 6]:
		assert_true(editor.buy(&"bar_section", Vector2i(9, y), 1))
	assert_false(editor.last_check.unreachable.is_empty(), "build warns about the shut-in shelf")
	main.call("_refresh_menu_catalogue")
	assert_false(_menu_ids(main).has(&"beer"), "staff can't reach the shelf")
	assert_false(_menu_ids(main).has(&"soft_drink"))
	assert_false(sim.visit_kinds().has(RecipeDef.DRINKS))
	var hints: Array[String] = main.call("drink_station_hints")
	assert_true(hints.has("Beer: staff can't reach the drinks shelf."), str(hints))
	assert_true(hints.has("Soft drink: staff can't reach the drinks fridge."), str(hints))


func _wall_in_drinks(main: Node) -> void:
	for placed: PlacedItem in (main.get("sim") as RestaurantSim).world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if (definition.id == &"table_2" and placed.origin == Vector2i(10, 6)) \
				or (definition.id == &"potted_plant" and placed.origin == Vector2i(12, 9)):
			assert_true(int(main.call("shop_sell", placed.id)) >= 0)
	assert_true(main.call("shop_buy", &"drinks_shelf", Vector2i(10, 5), 2))
	assert_true(main.call("shop_buy", &"drinks_fridge", Vector2i(11, 5), 2))
	for x: int in range(9, 13):
		assert_true(main.call("shop_buy", &"bar_section", Vector2i(x, 7), 2))
	for y: int in [5, 6]:
		assert_true(main.call("shop_buy", &"bar_section", Vector2i(9, y), 1))


func test_a_walled_in_bar_saves_and_reloads_without_losing_the_game() -> void:
	var main: Node = _start(true)
	Economy.add_cash(2000, Ledger.SALE)
	_wall_in_drinks(main)
	assert_false(_menu_ids(main).has(&"beer"), "staff can't reach the shelf")
	assert_true(Clock.sim.start_service())
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 20:
		main.call("run_ticks", 1000)
		guard += 1
	assert_true(Clock.sim.next_day())
	var reloaded: Node = _start(true)
	assert_eq(Clock.sim.day, 2, "the morning save loads")
	assert_false(_menu_ids(reloaded).has(&"beer"), "still off: the shelf is still walled in")
	var shelves: int = 0
	for placed: PlacedItem in (reloaded.get("sim") as RestaurantSim).world.grid.items():
		shelves += 1 if (placed.def as ItemDef).id == &"drinks_shelf" else 0
	assert_eq(shelves, 1, "the bar came back with the shop")


func test_a_reachable_second_drinks_shelf_serves_while_the_first_is_walled_in() -> void:
	var main: Node = _start(false)
	Economy.add_cash(2000, Ledger.SALE)
	_wall_in_drinks(main)
	assert_true(main.call("shop_buy", &"drinks_shelf", Vector2i(1, 9), 0))
	assert_true(_menu_ids(main).has(&"beer"))
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.menu = [(main.get("content") as ContentDB).recipe(&"beer")] as Array[RecipeDef]
	var cancelled: Array[StringName] = []
	sim.orders.order_cancelled.connect(func(o: Order) -> void: cancelled.append(o.cancellation_reason))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 3
	var guest: CustomerAgent = sim.add_visitor(sim.world.grid.entries()[0], random, null, RecipeDef.DRINKS)
	guest.food_patience = 5000
	assert_true(Clock.sim.start_service())
	for tick: int in range(3000):
		main.call("run_ticks", 1)
		if guest.paid:
			break
	assert_true(guest.paid, "the beer came from the shelf staff can reach")
	assert_eq(cancelled, [] as Array[StringName])


func test_undo_redo_of_a_drinks_only_menu_is_exact() -> void:
	var main: Node = _start(false)
	Economy.add_cash(1000, Ledger.SALE)
	assert_true(main.call("set_build_active", true))
	assert_true(main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	for id: StringName in [&"burger", &"grilled_cheese", &"tomato_soup", &"tea"]:
		assert_true(main.call("menu_set_enabled", id, false))
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var before: Dictionary = settings.to_dict()
	assert_true(main.call("undo_edit"))
	assert_eq(settings.enabled_count(), 1, "one dish stands in while the machine is gone")
	assert_true(main.call("redo_edit"))
	assert_eq(settings.to_dict(), before, "the stand-in goes off again")


func test_opening_hours_are_a_morning_choice_saved_at_the_next_morning_and_paid_by_the_hour() -> void:
	var main: Node = _start(true)
	var morning_file: String = FileAccess.get_file_as_string(_save_path())
	assert_false(main.call("set_opening_hours", 5 * 60, 15 * 60), "outside the limits")
	assert_true(main.call("set_opening_hours", 7 * 60, 15 * 60))
	assert_eq(Clock.sim.display_minutes(), 7 * 60, "the HUD clock shows the new opening time")
	assert_eq(Clock.sim.open_ticks, 8 * 60 * HOURS.ticks_per_minute)
	assert_eq(FileAccess.get_file_as_string(_save_path()), morning_file, "no save on the change itself")
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_true(main.call("set_menu_visible", true))
	assert_eq((panel.hours_control("open") as Label).text, "Opens 07:00")
	(panel.hours_control("close_plus") as Button).pressed.emit()
	assert_eq(Clock.sim.display_close_minute, 15 * 60 + 30, "the panel asks the session")
	assert_true(main.call("set_opening_hours", 7 * 60, 15 * 60))
	assert_true(main.call("set_menu_visible", false))
	assert_true(main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	assert_true(main.call("menu_set_enabled", &"tea", false))
	assert_true(Clock.sim.start_service())
	assert_false(main.call("set_opening_hours", 8 * 60, 15 * 60), "mornings only")
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 20:
		main.call("run_ticks", 1000)
		guard += 1
	var expected_wages: int = 0
	for member: StaffMember in (main.get("staff_roster") as StaffRoster).members():
		expected_wages += roundi(float(member.wage) * 0.8)
	assert_eq(-int(Economy.ledger.day_totals(1).get(Ledger.WAGES, 0)), expected_wages, "eight of ten hours")
	assert_true(Clock.sim.next_day())
	var reloaded: Node = _start(true)
	assert_eq(Clock.sim.day, 2)
	assert_eq([Clock.sim.display_open_minute, Clock.sim.display_close_minute], [7 * 60, 15 * 60],
		"the clock section kept the hours")
	var settings: MenuSettings = reloaded.get("menu_settings") as MenuSettings
	assert_true(settings.is_enabled(&"coffee") and not settings.is_enabled(&"tea"),
		"the machine's drinks and their choices reload with the shop")
	assert_true(reloaded.call("set_opening_hours", 11 * 60, 21 * 60), "back to the default")


func test_a_save_with_hours_outside_the_limits_keeps_the_game_with_default_hours() -> void:
	var first: Node = _start(true)
	assert_true(Clock.sim.start_service())
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 20:
		first.call("run_ticks", 1000)
		guard += 1
	assert_true(Clock.sim.next_day())
	Clock.sim.display_open_minute = 2 * 60
	assert_eq(SaveSystem.save_game(SLOT), OK)
	_start(true)
	assert_eq(Clock.sim.day, 2, "the save still loads")
	assert_eq([Clock.sim.display_open_minute, Clock.sim.display_close_minute, Clock.sim.open_ticks],
		[11 * 60, 21 * 60, 3600], "the hours snap back to the default day")


func _save_path() -> String:
	return SaveSystem.save_dir.path_join(SLOT + ".json")


func test_a_drink_left_off_a_full_menu_says_how_to_add_it() -> void:
	var main: Node = _start(false)
	var editor: ShopEditor = ProbeSetups._free_editor(main)
	assert_true(ProbeSetups._clear_east_table(main, editor))
	assert_true(editor.buy(&"coffee_machine", Vector2i(12, 5), 2))
	assert_true(editor.buy(&"drinks_shelf", Vector2i(10, 5), 2) and editor.buy(&"drinks_fridge", Vector2i(11, 5), 2))
	main.call("_refresh_menu_catalogue")
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_eq(settings.enabled_count(), settings.menu_limit(), "drinks fill the level-1 menu")
	var waiting: Array[RecipeDef] = settings.crowded_out_drinks()
	assert_eq(waiting.size(), 1, str(waiting))
	var hints: Array[String] = main.call("drink_station_hints")
	var notice: String = "%s is ready to serve; make room on the menu to add it." % waiting[0].display_name
	assert_true(hints.has(notice), str(hints))
	# Making room and switching it on from the panel clears the notice at once.
	var panel: Node = main.get("_menu_panel")
	panel.call("set_drink_hints", hints)
	var other: StringName = settings.enabled_recipes()[0].id
	main.call("_on_menu_enable_requested", other, false)
	main.call("_on_menu_enable_requested", waiting[0].id, true)
	assert_true(settings.is_enabled(waiting[0].id))
	var shown: Array = panel.get("_drink_hints")
	assert_false(shown.has(notice), str(shown))


func test_fryer_and_oven_enable_only_their_food_and_show_named_reasons() -> void:
	var main: Node = _start(false)
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	assert_false(progress.award_bonus(progress.threshold_for(3)).is_empty())
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_true(settings.set_owner_level(3))
	(main.get("shop_editor") as ShopEditor).set_owner_level(3)
	Economy.add_cash(1000, Ledger.SALE)
	assert_false(_menu_ids(main).has(&"fries"))
	assert_false(_menu_ids(main).has(&"savoury_pie"))
	assert_true(_equipment(main, &"fries").has({"text": "Buy a fryer", "met": false}))
	assert_true(_equipment(main, &"savoury_pie").has({"text": "Buy an oven", "met": false}))
	assert_true(main.call("shop_buy", &"fryer", Vector2i(9, 3), 0))
	assert_true(_menu_ids(main).has(&"fries"))
	assert_false(_menu_ids(main).has(&"savoury_pie"), "a fryer does not bake")
	assert_false(settings.is_enabled(&"fries"), "new food waits for the player")
	assert_false(_stock_ids(main).has(&"potato"))
	assert_true(main.call("menu_set_enabled", &"fries", true))
	assert_true(_stock_ids(main).has(&"potato") and _stock_ids(main).has(&"oil"))
	assert_eq(Economy.stock.count(&"potato"), 0, "editing never buys supplies")
	assert_true(main.call("shop_buy", &"oven", Vector2i(11, 3), 0))
	assert_true(_menu_ids(main).has(&"savoury_pie"))
	assert_false(settings.is_enabled(&"savoury_pie"))
	assert_true(_equipment(main, &"fries").has({"text": "Fryer ready", "met": true}))
	assert_true(_equipment(main, &"savoury_pie").has({"text": "Oven ready", "met": true}))
	assert_true(main.call("menu_set_enabled", &"savoury_pie", true))
	assert_eq(settings.enabled_count(), 5)
	# FK-087: the starter pantry is small; the supplies need a storage shelf.
	assert_true(main.call("shop_buy", &"storage_shelf", Vector2i(12, 1), 2))
	# The player fixes these station targets before opening; other rows stay automatic.
	assert_true(main.call("stock_set_target", &"potato", TUNING.station_stock[&"potato"]))
	assert_true(main.call("stock_set_target", &"oil", TUNING.station_stock[&"oil"]))
	assert_true(main.call("stock_set_target", &"dough", TUNING.station_stock[&"dough"]))
	assert_true(Clock.sim.start_service())
	assert_eq(Economy.stock.count(&"potato"), TUNING.station_stock[&"potato"])
	assert_eq(Economy.stock.count(&"oil"), TUNING.station_stock[&"oil"])
	assert_eq(Economy.stock.count(&"dough"), TUNING.station_stock[&"dough"])


func test_new_food_keeps_level_gates_sections_and_choices_when_appliance_returns() -> void:
	var main: Node = _start(false)
	var editor: ShopEditor = ProbeSetups._free_editor(main)
	assert_true(editor.buy(&"fryer", Vector2i(9, 3), 0))
	main.call("_refresh_menu_catalogue")
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_eq(settings.recipe(&"fries").menu_section(), RecipeDef.Section.SIDES)
	assert_false(main.call("menu_set_enabled", &"fries", true), "level one remains locked")
	assert_eq(settings.menu_limit(), 6)
	assert_true(settings.set_owner_level(2))
	assert_true(main.call("menu_set_enabled", &"fries", true))
	assert_true(main.call("menu_set_price", &"fries", 9))
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var fryer: PlacedItem = sim.world.grid.item_at(Vector2i(9, 3))
	assert_true(sim.world.grid.remove(fryer.id))
	main.call("_refresh_menu_catalogue")
	assert_false(_menu_ids(main).has(&"fries"))
	assert_false(_stock_ids(main).has(&"potato"))
	assert_not_null(sim.world.grid.place_def((main.get("content") as ContentDB).item(&"fryer"), Vector2i(9, 3)))
	main.call("_refresh_menu_catalogue")
	assert_true(settings.is_enabled(&"fries"))
	assert_eq(settings.price_of(settings.recipe(&"fries")), 9)


func test_food_equipment_reasons_show_in_the_tree_and_detail_not_the_drinks_hints() -> void:
	var main: Node = _start(false)
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	progress.award_bonus(progress.threshold_for(3))
	assert_true((main.get("menu_settings") as MenuSettings).set_owner_level(3))
	assert_true(main.call("set_menu_visible", true))
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_eq(panel.tree_item_for(&"fries").get_text(1), "Buy a fryer")
	assert_eq(panel.tree_item_for(&"savoury_pie").get_text(1), "Buy an oven")
	assert_true(panel.select_recipe(&"fries"))
	var slots: VBoxContainer = panel.get("_requirements_box") as VBoxContainer
	var shown: Array[String] = []
	for child: Node in slots.get_children():
		shown.append((child as Label).text)
	assert_true(shown.has("Buy a fryer"), str(shown))
	for hint: String in panel.get("_drink_hints") as Array[String]:
		assert_false(hint.contains("Fries") or hint.contains("Savoury pie"), hint)
	assert_false(panel.drinks_section().is_ancestor_of(slots))


func test_walled_in_drinks_show_the_reach_reason_in_the_equipment_slot() -> void:
	var main: Node = _start(false)
	Economy.add_cash(2000, Ledger.SALE)
	_wall_in_drinks(main)
	assert_true(_equipment(main, &"beer").has({"text": "Staff can't reach the drinks shelf", "met": false}))
	assert_true(main.call("drink_station_hints").has("Beer: staff can't reach the drinks shelf."))


func test_a_missing_fridge_or_pass_is_listed_as_equipment_for_every_dish() -> void:
	var main: Node = _start(false)
	for id: StringName in [&"burger", &"coffee"]:
		for row: Dictionary in _equipment(main, id):
			assert_false(String(row["text"]).begins_with("Fridge") or String(row["text"]).begins_with("Pass"),
				"a working fridge and pass are not listed")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	for placed: PlacedItem in sim.world.grid.items():
		var category: int = (placed.def as ItemDef).category
		if category == ItemDef.Category.PASS or category == ItemDef.Category.STORAGE:
			assert_true(sim.world.grid.remove(placed.id))
	for id: StringName in [&"burger", &"coffee"]:
		var equipment: Array = _equipment(main, id)
		assert_true(equipment.has({"text": "Buy a fridge", "met": false}), str(equipment))
		assert_true(equipment.has({"text": "Buy a pass counter", "met": false}), str(equipment))


func _equipment(main: Node, id: StringName) -> Array:
	var details: Dictionary[StringName, Dictionary] = main.call("menu_recipe_details")
	return details[id]["equipment"]


func test_fryer_coffee_probe_builds_a_reachable_explicit_level_two_menu() -> void:
	var main: Node = _start(false)
	var before: Dictionary = GameState.call("_capture_save")
	assert_true(ProbeSetups.apply("fryer_coffee", main))
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_eq(settings.owner_level(), 2)
	for id: StringName in [&"burger", &"grilled_cheese", &"fries", &"coffee"]:
		assert_true(settings.is_enabled(id), str(id))
	assert_false(settings.is_enabled(&"tea"))
	assert_false(settings.is_enabled(&"tomato_soup"))
	assert_eq(settings.enabled_count(), 4)
	assert_false(_menu_ids(main).has(&"savoury_pie"), "no oven in this scenario")
	assert_true(_stock_ids(main).has(&"potato"))
	assert_true(_stock_ids(main).has(&"coffee_beans"))
	assert_eq(Economy.stock.count(&"potato"), 0, "opening, not setup, orders supplies")
	assert_eq((main.get("sim") as RestaurantSim).world.now, 0)
	assert_eq(GameState.call("_capture_save"), before, "the layout and explicit XP draw no randomness")


func test_level_one_starter_menu_hints_name_each_missing_station_once() -> void:
	var main: Node = _start(false)
	assert_eq((main.get("owner_progress") as OwnerProgress).level, 1)
	var drinks: Array[String] = main.call("drink_station_hints")
	assert_eq(drinks, ["Coffee, tea and croissant: buy a coffee machine.", "Beer: buy a drinks shelf.",
		"Soft drink: buy a drinks fridge."] as Array[String], "the croissant joins the coffee machine line")
	assert_true(main.call("set_menu_visible", true))
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_eq(panel.get("_drink_hints"), drinks)


func test_a_missing_prep_counter_is_named_after_the_prep_counter_not_a_later_cabinet() -> void:
	var main: Node = _start(false)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	for placed: PlacedItem in sim.world.grid.items():
		if (placed.def as ItemDef).id == &"prep_counter":
			assert_true(sim.world.grid.remove(placed.id))
	assert_eq(main.call("_station_item_name", &"prep_counter"), "Prep counter")
	assert_eq(main.call("_station_item_name", &"coffee"), "Coffee machine", "no item id matches, so the earliest unlock")
	for id: StringName in [&"burger", &"grilled_cheese", &"tomato_soup"]:
		assert_true(_equipment(main, id).has({"text": "Buy a prep counter", "met": false}), str(id))
	assert_false(main.call("drink_station_hints").has("Burger, grilled cheese and tomato soup: buy a prep counter."),
		"food-only equipment is not a Drinks hint")


func test_food_equipment_reasons_survive_a_menu_refresh() -> void:
	var main: Node = _start(false)
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	progress.award_bonus(progress.threshold_for(3))
	assert_true((main.get("menu_settings") as MenuSettings).set_owner_level(3))
	assert_true(main.call("set_menu_visible", true))
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	panel.refresh()
	assert_eq(panel.tree_item_for(&"fries").get_text(1), "Buy a fryer")
	assert_eq(panel.tree_item_for(&"savoury_pie").get_text(1), "Buy an oven")


func test_a_walled_in_fryer_or_fridge_shows_red_in_the_tree_and_fries_leave_the_menu() -> void:
	var main: Node = _start(false)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_true(settings.set_owner_level(2))
	(main.get("shop_editor") as ShopEditor).set_owner_level(2)
	Economy.add_cash(1000, Ledger.SALE)
	assert_true(main.call("shop_buy", &"fryer", Vector2i(9, 3), 0))
	assert_true(_menu_ids(main).has(&"fries"))
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var fryer: PlacedItem = sim.world.grid.item_at(Vector2i(9, 3))
	for cell: Vector2i in fryer.work_cells:
		assert_not_null(sim.world.grid.place(Vector2i.ONE, cell, 0, true), "a crate blocks the fryer")
	main.call("_refresh_menu_catalogue")
	assert_false(_menu_ids(main).has(&"fries"), "service never takes orders staff can't cook")
	assert_true(main.call("set_menu_visible", true))
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_eq(panel.tree_item_for(&"fries").get_text(1), "Can't reach the fryer")
	assert_eq(panel.tree_item_for(&"fries").get_custom_color(1), MenuPanel.HIGHER_COLOR)
	assert_eq(panel.tree_item_for(&"fries").get_tooltip_text(1), "Staff can't reach the fryer.")
	assert_true(main.call("set_menu_visible", false))
	for placed: PlacedItem in sim.world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition != null and definition.station_type == &"fridge":
			for cell: Vector2i in placed.work_cells:
				if sim.world.grid.is_walkable(cell):
					assert_not_null(sim.world.grid.place(Vector2i.ONE, cell, 0, true))
	assert_true(main.call("set_menu_visible", true))
	assert_eq(panel.tree_item_for(&"burger").get_text(1), "Can't reach the fridge")
	assert_eq(panel.tree_item_for(&"burger").get_custom_color(1), MenuPanel.HIGHER_COLOR)
