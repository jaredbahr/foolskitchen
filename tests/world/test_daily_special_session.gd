extends TestCase
## Real session requests, owned morning checkpoints and paid closing results.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "daily_special_session"

var _mains: Array[Node] = []
var _previous_save_dir: String
var _save_dir: String
var _previous_open_speed: int


func before_each() -> void:
	_previous_open_speed = Preferences.default_open_speed
	_previous_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "daily_special_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	Preferences.default_open_speed = _previous_open_speed
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _previous_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_morning_request_changes_one_offer_without_saving_charging_or_drawing_rng() -> void:
	var main: Node = _start()
	var checkpoint: String = FileAccess.get_file_as_string(_path())
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var customers: int = GameState.rng(&"customers").state
	var reviews: int = GameState.rng(&"reviews").state
	var panel: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	panel.special_requested.emit(&"burger")
	assert_eq((main.get("daily_special") as DailySpecial).recipe_id(), &"burger")
	assert_eq((main.get("sim") as RestaurantSim).price_of((main.get("content") as ContentDB).recipe(&"burger")), 11)
	assert_false(main.call("menu_set_special", &"missing"))
	assert_eq((main.get("daily_special") as DailySpecial).recipe_id(), &"burger")
	assert_true(main.call("menu_set_special", &"tomato_soup"))
	assert_eq((main.get("daily_special") as DailySpecial).recipe_id(), &"tomato_soup")
	assert_eq(FileAccess.get_file_as_string(_path()), checkpoint)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(GameState.rng(&"customers").state, customers)
	assert_eq(GameState.rng(&"reviews").state, reviews)
	assert_true(Clock.sim.start_service())
	assert_false(main.call("menu_set_special", &"burger"))
	panel.special_requested.emit(&"")
	assert_eq((main.get("daily_special") as DailySpecial).recipe_id(), &"tomato_soup")


func test_real_save_providers_round_trip_the_choice_and_next_morning_clears_it() -> void:
	var first: Node = _start()
	assert_true(first.call("menu_set_price", &"burger", 25))
	assert_true(first.call("menu_set_special", &"burger"))
	# Explicit persistence fixture, through the production providers. Selection
	# itself never calls this; the game's only save point remains _begin_morning.
	assert_eq(SaveSystem.save_game(SLOT), OK)
	assert_eq(_document()["data"]["daily_special"]["recipe"], "burger")
	var captured: Dictionary = (first.get("daily_special") as DailySpecial).to_dict()
	_close(first)
	var restored: Node = _start()
	assert_eq((restored.get("daily_special") as DailySpecial).to_dict(), captured)
	var burger: RecipeDef = (restored.get("content") as ContentDB).recipe(&"burger")
	# The requested 25 is clamped by the unchanged menu's 2x-standard limit.
	assert_eq((restored.get("sim") as RestaurantSim).price_of(burger), 22)
	reset_weekly_for_synthetic_day_jump(restored)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq((restored.get("daily_special") as DailySpecial).recipe_id(), &"")
	assert_eq(_document()["data"]["daily_special"]["recipe"], "")
	assert_eq((restored.get("sim") as RestaurantSim).price_of(burger), 24)


func test_legacy_checkpoint_without_the_section_loads_with_no_special() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	document["data"].erase("daily_special")
	_write(document)
	_close(first)
	var restored: Node = _start()
	assert_eq((restored.get("daily_special") as DailySpecial).recipe_id(), &"")
	var sim: RestaurantSim = restored.get("sim") as RestaurantSim
	for recipe: RecipeDef in sim.menu:
		assert_eq(sim.price_of(recipe), recipe.standard_price)


func test_invalid_special_never_installs_and_the_failed_checkpoint_is_preserved() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	document["data"]["daily_special"] = {"version": 1, "day": 1, "recipe": "missing"}
	_write(document)
	var bad_bytes: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var restored: Node = _start()
	assert_eq((restored.get("daily_special") as DailySpecial).recipe_id(), &"")
	assert_eq(Clock.sim.day, 1)
	assert_eq(FileAccess.get_file_as_string(_path()), bad_bytes)


func test_paid_service_captures_discounted_tickets_and_a_detached_special_report_line() -> void:
	var main: Node = _start(false)
	assert_true(main.call("menu_set_special", &"burger"))
	assert_true(Clock.sim.start_service())
	for _guard: int in 30:
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
		main.call("run_ticks", 1000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var burger_tickets: int = 0
	for order: Order in sim.orders.orders_in_state(Order.State.DELIVERED):
		if order.recipe_id == &"burger":
			burger_tickets += 1
			assert_eq(order.price, 11)
	assert_true(burger_tickets > 0)
	var report: DayReport = main.get("shown_report") as DayReport
	assert_not_null(report)
	if report == null:
		return
	var sold: int = int(report.dishes_sold.get(&"burger", 0))
	assert_true(sold > 0)
	assert_eq(report.daily_special_line, "Today's special: Burger, %d sold" % sold)
	var detached: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(detached.daily_special_line, report.daily_special_line)
	assert_true(Clock.sim.next_day())
	assert_eq((main.get("daily_special") as DailySpecial).recipe_id(), &"")
	assert_eq(report.daily_special_line, "Today's special: Burger, %d sold" % sold)


func _start(saves: bool = true) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 1)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if is_instance_valid(main):
		if main.is_inside_tree():
			main.get_parent().remove_child(main)
		main.free()


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")
