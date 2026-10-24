extends TestCase
## FK-024: the main scene runs a real day: books, closing costs, evening
## report, next day and autosave.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const TEST_SAVES: String = "user://test_session_saves/"

var _mains: Array[Node] = []
var _old_save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_SAVES
	SaveSystem.delete_slot("test_session")


func after_each() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	for m in _mains:
		if is_instance_valid(m):
			if m.is_inside_tree():
				root.remove_child(m)
			m.free()
	_mains.clear()
	SaveSystem.delete_slot("test_session")
	DirAccess.remove_absolute(TEST_SAVES)
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start(with_saves: bool) -> Node:
	var main: Node = MainScene.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", "test_session")
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")  # the test runner never delivers _ready()
	return main


func _morning_stock_cost(main: Node) -> int:
	var content: ContentDB = main.get("content")
	var total := 0
	for id: StringName in TUNING.morning_stock:
		total += TUNING.morning_stock[id] * content.ingredient(id).unit_cost
	return total


func _run_day(main: Node) -> void:
	assert_true(Clock.sim.start_service(), "shop opens from the morning")
	var guard := 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 20:
		main.call("run_ticks", 1000)
		guard += 1
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, "the day ends")


func test_new_game_starts_with_cash_minus_morning_stock() -> void:
	var main := _start(false)
	assert_eq(Economy.cash, TUNING.starting_cash - _morning_stock_cost(main))
	assert_eq(Economy.stock.count(&"bun"), TUNING.morning_stock[&"bun"])
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_true(Clock.attached_world == main.get("world"), "Clock drives this restaurant")
	var report: Control = main.get_node("Overlay/EveningReport")
	assert_false(report.visible, "no report in the morning")


func test_full_day_charges_costs_and_shows_report() -> void:
	var main := _start(false)
	var cash_at_open := Economy.cash
	_run_day(main)
	var wages := 0
	for role: StringName in TUNING.wages:
		wages += TUNING.wages[role]
	var sales: int = int(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.SALE, 0))
	assert_true(sales > 0, "the real kitchen serves paying guests")
	assert_eq(Economy.cash, cash_at_open + sales - wages - TUNING.daily_rent, "meal sales, wages and rent reconcile at closing")
	var report: Control = main.get_node("Overlay/EveningReport")
	assert_true(report.visible, "evening report shown at CLOSED")
	var day_report: DayReport = main.call("build_report", 1)
	assert_eq(day_report.income.get(Ledger.SALE, 0), sales)
	assert_eq(day_report.costs.get(Ledger.WAGES, 0), wages)
	assert_eq(day_report.costs.get(Ledger.RENT, 0), TUNING.daily_rent)
	assert_eq(day_report.costs.get(Ledger.INGREDIENTS, 0), _morning_stock_cost(main))
	var sim: RestaurantSim = main.get("sim")
	assert_true(sim.served_today + sim.lost_today > 0, "guests came")
	assert_eq(sim.customers().size(), 0, "nobody inside after closing")


func test_sale_reaches_books_and_report() -> void:
	var main := _start(false)
	var sim: RestaurantSim = main.get("sim")
	var before := Economy.cash
	var order := Order.new()
	order.recipe_id = &"burger"
	order.price = 9
	var guest := CustomerAgent.new(sim, RandomNumberGenerator.new())
	sim.pay(guest, order)
	assert_eq(Economy.cash, before + 9)
	var day_report: DayReport = main.call("build_report", Clock.sim.day)
	assert_eq(day_report.income.get(Ledger.SALE, 0), 9)
	assert_eq(day_report.dishes_sold.get(&"burger", 0), 1)
	assert_eq(day_report.customers_served, 1)


func test_next_day_resets_and_hides_report() -> void:
	var main := _start(false)
	_run_day(main)
	var report: Control = main.get_node("Overlay/EveningReport")
	report.emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_false(report.visible)
	var sim: RestaurantSim = main.get("sim")
	assert_eq(sim.served_today + sim.lost_today, 0, "day counters reset")
	assert_eq(Economy.stock.count(&"bun"), TUNING.morning_stock[&"bun"], "fridge topped up again")


func test_autosave_resumes_next_morning() -> void:
	var first := _start(true)
	_run_day(first)
	(first.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	var cash_day2 := Economy.cash
	assert_true(SaveSystem.list_slots().has("test_session"), "autosaved")
	var root := (Engine.get_main_loop() as SceneTree).root
	_mains.erase(first)
	root.remove_child(first)
	first.free()
	Economy.reset(12345)  # scramble, so the load must restore it
	var second := _start(true)
	assert_eq(Clock.sim.day, 2, "resumed on day 2")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(Economy.cash, cash_day2, "cash restored")
	var sim: RestaurantSim = second.get("sim")
	assert_true(sim.stock == Economy.stock, "kitchen uses the restored stock")


func test_guests_sent_home_at_closing_are_in_the_report() -> void:
	var main := _start(false)
	var sim: RestaurantSim = main.get("sim")
	Clock.sim.open_ticks = 600
	Clock.sim.last_orders_max_ticks = 50
	sim.spawner.min_gap = 20
	sim.spawner.max_gap = 40
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 5000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var closing: int = sim.leave_reasons_today.get(&"closing", 0)
	assert_true(closing > 0, "some guests were still inside at closing (%s)" % [sim.leave_reasons_today])
	# The report actually put on screen must include them.
	var shown: DayReport = main.get("shown_report")
	assert_not_null(shown, "a report was shown at closing")
	assert_eq(shown.leave_reasons.get(&"closing", 0), closing)
	assert_eq(shown.customers_lost, sim.lost_today)


func test_arrivals_use_the_saved_game_state_rng() -> void:
	var first := _start(true)
	var sim: RestaurantSim = first.get("sim")
	assert_true(sim.rng == GameState.rng(&"customers"), "arrivals use GameState's stream")
	assert_true(sim.spawner.rng == sim.rng)
	var saved_state: int = GameState.rng(&"customers").state
	_mains.erase(first)
	(Engine.get_main_loop() as SceneTree).root.remove_child(first)
	first.free()
	GameState.new_run(999)  # scramble
	var second := _start(true)
	var sim2: RestaurantSim = second.get("sim")
	assert_true(sim2.rng == GameState.rng(&"customers"), "re-bound after load")
	# The new morning draws one arrival gap from the restored stream.
	var expected := RandomNumberGenerator.new()
	expected.state = saved_state
	expected.randi_range(maxi(1, sim2.spawner.min_gap), maxi(maxi(1, sim2.spawner.min_gap), sim2.spawner.max_gap))
	assert_eq(GameState.rng(&"customers").state, expected.state, "the stream continues from the save")


func test_half_broken_save_starts_fresh_and_keeps_the_file() -> void:
	var first := _start(true)
	_run_day(first)
	(first.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	_mains.erase(first)
	(Engine.get_main_loop() as SceneTree).root.remove_child(first)
	first.free()
	# Corrupt only the economy section.
	var path := TEST_SAVES.path_join("test_session.json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["data"]["economy"] = {"ledger": 5}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	var broken := FileAccess.get_file_as_string(path)
	_start(true)
	assert_eq(Clock.sim.day, 1, "a clean new game, not day 2 with new-game cash")
	assert_eq(Economy.cash, TUNING.starting_cash - _morning_stock_cost(_mains[-1]))
	assert_eq(FileAccess.get_file_as_string(path), broken, "the unreadable save was not overwritten")
