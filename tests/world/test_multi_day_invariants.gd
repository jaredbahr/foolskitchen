extends TestCase
## FK-023: five real days through the whole game (real kitchen, real guests,
## books, closing costs, report, autosave and a reload in the middle).
## Checks the rules that must hold every day, whatever the guests do.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "test_invariants"
const DAYS: int = 5
const RELOAD_BEFORE_DAY: int = 3

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _arrivals_today: int = 0
var _paid_today: int = 0
var _sales_today: int = 0


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "multi_day_invariants")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains:
		_free(main)
	_mains.clear()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_five_days_keep_books_guests_and_shop_consistent() -> void:
	var main: Node = _start()
	var total_served: int = 0
	for day: int in range(1, DAYS + 1):
		if day == RELOAD_BEFORE_DAY:
			main = _reload(main)
		assert_eq(Clock.sim.day, day)
		assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
		_assert_clean_morning(main, day)
		_run_day(main, day)
		_assert_closed_books(main, day)
		total_served += (main.get("sim") as RestaurantSim).served_today
		(main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_true(total_served > DAYS * 5, "the shop serves real guests every day (%d in %d days)" % [total_served, DAYS])


func _start() -> Node:
	var main: Node = MainScene.instantiate()
	main.set("use_saves", true)
	main.set("save_slot", SLOT)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")  # the test runner never delivers _ready()
	var sim: RestaurantSim = main.get("sim")
	sim.customer_arrived.connect(_on_arrived)
	sim.customer_paid.connect(_on_paid)
	return main


## Quits to the menu and loads the morning autosave in a fresh scene.
func _reload(old: Node) -> Node:
	var cash: int = Economy.cash
	var day: int = Clock.sim.day
	var stock: Dictionary = Economy.stock.to_dict()
	_mains.erase(old)
	_free(old)
	Economy.reset(98765)  # scramble, so the load must restore everything
	GameState.new_run(4242)
	var main: Node = _start()
	assert_eq(Clock.sim.day, day, "the reload resumes the same morning")
	assert_eq(Economy.cash, cash, "cash survives the reload")
	assert_eq(Economy.stock.to_dict(), stock, "the fridge survives the reload")
	return main


func _assert_clean_morning(main: Node, day: int) -> void:
	var sim: RestaurantSim = main.get("sim")
	var world: SimWorld = main.get("world")
	assert_eq(sim.customers().size(), 0, "day %d: no guests before opening" % day)
	assert_eq(world.board.active_count(), 0, "day %d: no jobs carried over" % day)
	assert_eq(sim.kitchen.dirty_tables.size(), 0, "day %d: tables clean" % day)
	assert_not_null(sim.cleanliness, "day %d: cleanliness is installed" % day)
	assert_eq(sim.cleanliness.spot_count(), 0, "day %d: floor spots are tidied overnight" % day)
	assert_eq(sim.clean_tasks.active_task_count(), 0, "day %d: no mop task survives overnight" % day)
	var diagnostics: DebugOverlay = main.get_node("Overlay/DebugOverlay") as DebugOverlay
	assert_true(diagnostics.get("_cleanliness") == sim.cleanliness,
		"day %d: F3 follows this shop's floor state" % day)
	diagnostics.refresh()
	assert_true((diagnostics.get_node("Panel/Margin/Scroll/Content/Rates") as Label).text.contains(
		"Floor spots 0"), "day %d: F3 shows the clean morning" % day)
	_assert_plate_conservation(sim, day)
	assert_eq(sim.kitchen.clean_plates, sim.kitchen.plates.total, "day %d: every plate clean overnight" % day)
	assert_eq(sim.served_today + sim.lost_today, 0, "day %d: counters reset" % day)
	var reputation: ReputationBook = main.get("reputation") as ReputationBook
	assert_true(reputation.average() >= 0.0 and reputation.average() <= 5.0,
		"day %d: morning reputation stays within the star scale" % day)
	for agent: SimAgent in world.agents:
		if agent is StaffAgent:
			assert_null((agent as StaffAgent).task)
			assert_eq(agent.cell, LAYOUT.staff_spawns[agent.role], "day %d: %s at its post" % [day, agent.role])
	for item: PlacedItem in world.grid.items():
		for cell: Vector2i in item.work_cells + item.seat_cells:
			assert_eq(item.reserved_by(cell), -1, "day %d: nothing reserved overnight" % day)
	for id: StringName in TUNING.morning_stock:
		assert_true(Economy.stock.count(id) >= TUNING.morning_stock[id], "day %d: %s restocked" % [day, id])
	assert_true(sim.stock == Economy.stock, "day %d: the kitchen cooks from the books' stock" % day)


func _run_day(main: Node, day: int) -> void:
	_arrivals_today = 0
	_paid_today = 0
	_sales_today = 0
	var report: Control = main.get_node("Overlay/EveningReport")
	assert_false(report.visible, "day %d: no report before opening" % day)
	assert_true(Clock.sim.start_service(), "day %d: the shop opens" % day)
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 30:
		main.call("run_ticks", 1000)
		_assert_plate_conservation(main.get("sim") as RestaurantSim, day)
		guard += 1
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, "day %d ends" % day)
	assert_true(report.visible, "day %d: the evening report is shown" % day)


func _assert_closed_books(main: Node, day: int) -> void:
	var sim: RestaurantSim = main.get("sim")
	_assert_plate_conservation(sim, day)
	# Guests: everyone who came in is accounted for, exactly once.
	assert_eq(sim.customers().size(), 0, "day %d: everyone left at closing" % day)
	assert_eq(sim.served_today + sim.lost_today, _arrivals_today, "day %d: every guest counted once" % day)
	assert_eq(sim.served_today, _paid_today, "day %d: served means paid" % day)
	var reasons: int = 0
	for reason: StringName in sim.leave_reasons_today:
		reasons += sim.leave_reasons_today[reason]
	assert_eq(reasons, _arrivals_today, "day %d: every guest has a reason" % day)
	var reputation: ReputationBook = main.get("reputation") as ReputationBook
	assert_true(reputation.average() >= 0.0 and reputation.average() <= 5.0,
		"day %d: closing reputation stays within the star scale" % day)
	assert_true(reputation.scores().size() >= ReputationBook.INITIAL_REVIEWS
		and reputation.scores().size() <= ReputationBook.WINDOW,
		"day %d: the rolling window remains bounded" % day)
	assert_true(sim.reviews_today.size() <= _arrivals_today,
		"day %d: each arriving guest reviews at most once" % day)
	for row: Dictionary in sim.reviews_today:
		assert_true(int(row.get("stars", 0)) >= 1 and int(row.get("stars", 0)) <= 5)
		assert_false(String(row.get("quote", "")).is_empty())
	for reason: StringName in sim.leave_reasons_today:
		assert_true(reason == &"happy" or reason == &"no_menu" or reason == &"too_expensive"
			or CustomerAgent.PLAYER_REASONS.has(reason) or reason == &"kitchen_failed",
			"day %d: '%s' is a reason the player can read" % [day, reason])
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY]:
		assert_eq(sim.orders.orders_in_state(state).size(), 0, "day %d: no open tickets" % day)
	# Money: the books add up, and closing costs are charged exactly once.
	var totals: Dictionary = Economy.ledger.day_totals(day)
	assert_eq(int(totals.get(Ledger.SALE, 0)), _sales_today, "day %d: every sale is in the books" % day)
	var wages: int = (main.get("staff_roster") as StaffRoster).total_wages()
	assert_eq(int(totals.get(Ledger.WAGES, 0)), -wages, "day %d: wages once" % day)
	assert_eq(int(totals.get(Ledger.RENT, 0)), -TUNING.daily_rent, "day %d: rent once" % day)
	assert_eq(int(totals.get(Ledger.OTHER, 0)), 0, "day %d: no unexplained money" % day)
	var since_start: int = 0
	for d: int in range(1, day + 1):
		since_start += Economy.ledger.day_profit(d)
	assert_eq(Economy.cash, TUNING.starting_cash + since_start, "day %d: cash = start + every recorded change" % day)
	for id: StringName in Economy.stock.to_dict():
		assert_true(Economy.stock.count(id) >= 0, "day %d: %s never goes negative" % [day, id])
	# The report on screen tells the same story as the books.
	var shown: DayReport = main.get("shown_report")
	assert_not_null(shown)
	if shown == null:
		return
	assert_eq(shown.day, day)
	assert_eq(shown.customers_served, sim.served_today)
	assert_eq(shown.customers_lost, sim.lost_today)
	assert_eq(shown.cleanliness_label, sim.cleanliness.worst_category_label(),
		"day %d: the report retains the worst floor condition, not the current spot count" % day)
	assert_eq(shown.review_cards.size(), sim.reviews_today.size(),
		"day %d: every review reaches the evening report" % day)
	assert_eq(shown.reputation_after, reputation.average())
	assert_eq(int(shown.income.get(Ledger.SALE, 0)), _sales_today)
	var dishes: int = 0
	for recipe: StringName in shown.dishes_sold:
		dishes += shown.dishes_sold[recipe]
	assert_eq(dishes, sim.served_today, "day %d: one dish per served guest" % day)
	print("INVARIANT_DAY day=%d arrivals=%d served=%d lost=%d profit=%d cash=%d reasons=%s" % [
		day, _arrivals_today, sim.served_today, sim.lost_today,
		Economy.ledger.day_profit(day), Economy.cash, sim.leave_reasons_today])


func _assert_plate_conservation(sim: RestaurantSim, day: int) -> void:
	assert_true(sim.kitchen.clean_plates >= 0 and sim.kitchen.dirty_plates >= 0 and sim.kitchen.in_use_plates >= 0)
	assert_eq(sim.kitchen.clean_plates + sim.kitchen.dirty_plates + sim.kitchen.in_use_plates,
		sim.kitchen.plates.total, "day %d: clean + dirty + in use equals owned stock" % day)


func _free(main: Node) -> void:
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _on_arrived(_guest: CustomerAgent) -> void:
	_arrivals_today += 1


func _on_paid(_guest: CustomerAgent, _order: Order, amount: int) -> void:
	_paid_today += 1
	_sales_today += amount
