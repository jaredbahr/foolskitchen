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


func _stock_ids(main: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row: Dictionary in main.call("stock_rows"):
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
	assert_eq(panel.drinks_section().get_child_count(), 0)
	var hints: Array[String] = main.call("drink_station_hints")
	assert_eq(hints, ["Coffee and Tea: buy a coffee machine.", "Beer and Glass of wine: buy a drinks shelf.",
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
	assert_true(Economy.stock.count(&"coffee_beans") > 0, "a morning purchase is stocked at once")
	assert_false(_stock_ids(main).has(&"pastry"), "the croissant is off, so no pastries yet")
	assert_true(main.call("menu_set_enabled", &"croissant", true))
	assert_true(_stock_ids(main).has(&"pastry") and Economy.stock.count(&"pastry") > 0)
	assert_false(_stock_ids(main).has(&"beer"))
	assert_true(main.call("set_menu_visible", true))
	assert_eq(panel.drinks_section().get_child_count(), 2, "Coffee and Tea under Drinks")
	assert_not_null(panel.row_for(&"croissant"), "the pastry is listed under Food")
	assert_false(panel.drinks_section().is_ancestor_of(panel.row_for(&"croissant")))
	assert_true(main.call("set_menu_visible", false))
	var machine: PlacedItem = sim.world.grid.item_at(Vector2i(12, 5))
	assert_true(int(main.call("shop_sell", machine.id)) >= 0)
	assert_false(_menu_ids(main).has(&"coffee"), "selling the machine takes coffee off")
	assert_false(_stock_ids(main).has(&"coffee_beans"))
	assert_true(settings.is_valid() and settings.enabled_count() >= 1)


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


func test_a_save_with_hours_outside_the_limits_starts_fresh() -> void:
	_start(true)
	Clock.sim.display_open_minute = 2 * 60
	assert_eq(SaveSystem.save_game(SLOT), OK)
	_start(true)
	assert_eq(Clock.sim.day, 1)
	assert_eq([Clock.sim.display_open_minute, Clock.sim.display_close_minute], [11 * 60, 21 * 60])


func _save_path() -> String:
	return SaveSystem.save_dir.path_join(SLOT + ".json")
