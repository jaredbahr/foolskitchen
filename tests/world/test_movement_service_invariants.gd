extends TestCase
## Real five-day service, checking every fixed tick rather than sampled frames.
## The same-seed replay compares the complete observed movement/RNG trace;
## it is not a new economic golden or a claim of old/new balance equality.

const MAIN_SCENE: PackedScene = preload("res://src/world/main.tscn")
const DAYS: int = 5
const SEED: int = 263
const MAX_DAY_TICKS: int = 30000

var _mains: Array[Node] = []
var _arrived: Dictionary[int, bool] = {}
var _departed: Dictionary[int, bool] = {}


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_free(main)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_default_five_days_have_exclusive_occupancy_and_repeat_the_full_seeded_trace() -> void:
	var first: Dictionary = _run_profile("default")
	if first.has("error"):
		return
	var second: Dictionary = _run_profile("default")
	if second.has("error"):
		return
	assert_eq(first, second, "same seed repeats every checked tick, private/named RNG states and final reports")
	assert_true(first.ticks_checked > 0)
	assert_true(first.customer_visits > 0, "the real service admits and accounts for guests")
	assert_true(first.served > 0 and first.carrying_food_ticks > 0, "real meals are carried and served")
	assert_eq(first.days.size(), DAYS)


func test_expanded_tables_five_days_have_exclusive_occupancy_on_every_tick() -> void:
	var result: Dictionary = _run_profile("expanded_tables")
	if result.has("error"):
		return
	assert_eq(result.days.size(), DAYS)
	assert_true(result.ticks_checked > 0)
	assert_true(result.customer_visits > 0)
	assert_true(result.served > 0 and result.carrying_food_ticks > 0)


func _run_profile(setup: String) -> Dictionary:
	var main: Node = MAIN_SCENE.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", SEED)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null:
		return _error("%s: production Main did not start" % setup)
	## Match the ordinary fixed-seed probe's initialization, without replacing
	## stock, arrival gaps, menu, opening hours, movement or service behavior.
	GameState.new_run(SEED)
	sim.use_rng(GameState.rng(&"customers"))
	sim.configure_reviews(sim.review_book, sim.review_tuning, sim.review_quotes, GameState.rng(&"reviews"))
	if not ProbeSetups.apply(setup, main):
		return _error("%s: actual authored setup could not be applied" % setup)
	sim.start_day()
	sim.customer_arrived.connect(_on_arrived)
	sim.customer_left.connect(_on_left)
	var trace: HashingContext = HashingContext.new()
	assert_eq(trace.start(HashingContext.HASH_SHA256), OK)
	var daily: Array[Dictionary] = []
	var ticks_checked: int = 0
	var visits: int = 0
	var served: int = 0
	var carrying_food_ticks: int = 0
	for index: int in DAYS:
		_arrived.clear()
		_departed.clear()
		if index > 0 and not ProbeSetups.morning(setup, main):
			return _error("%s: morning %d failed" % [setup, index + 1])
		if not Clock.sim.start_service():
			return _error("%s: day %d did not open" % [setup, index + 1])
		var elapsed: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and elapsed < MAX_DAY_TICKS:
			var previous_tick: int = sim.world.now
			var before_tick: Dictionary = MovementInvariants.capture(sim.world)
			main.call("run_ticks", 1)
			if sim.world.now != previous_tick + 1:
				return _error("%s day %d: one call did not advance exactly one tick" % [setup, index + 1])
			var problem: String = MovementInvariants.problem(sim.world, before_tick)
			if not problem.is_empty():
				return _error("%s day %d world tick %d: %s" % [setup, index + 1, sim.world.now, problem])
			trace.update(var_to_bytes(_tick_signature(sim)))
			for agent: SimAgent in sim.world.agents:
				if agent is StaffAgent and (agent as StaffAgent).carries_food():
					assert_eq(sim.world.movement.priority(sim.world, agent), 3, "actual kitchen pickup earns food priority")
					carrying_food_ticks += 1
			ticks_checked += 1
			elapsed += 1
		if Clock.sim.phase != SimClock.Phase.CLOSED:
			return _error("%s: day %d exceeded the service watchdog" % [setup, index + 1])
		var report: DayReport = main.get("shown_report") as DayReport
		if report == null:
			return _error("%s: day %d has no actual report" % [setup, index + 1])
		assert_eq(sim.customers().size(), 0, "closed service has no hidden active or pending visit")
		assert_eq(_arrived.size(), sim.served_today + sim.lost_today,
			"every arrival, including ordered pending admission, has one settled outcome")
		assert_eq(_departed.size(), _arrived.size(), "every visit departs exactly once")
		assert_eq(report.customers_served, sim.served_today)
		assert_eq(report.customers_lost, sim.lost_today)
		visits += _arrived.size()
		served += sim.served_today
		daily.append({"report": report.to_dict(), "ledger": Economy.ledger.day_totals(report.day),
			"cash": Economy.cash, "ticks": elapsed})
		if index + 1 < DAYS and not Clock.sim.next_day():
			return _error("%s: next morning did not start" % setup)
	sim.customer_arrived.disconnect(_on_arrived)
	sim.customer_left.disconnect(_on_left)
	var result: Dictionary = {"days": daily, "ticks_checked": ticks_checked, "customer_visits": visits,
		"served": served, "carrying_food_ticks": carrying_food_ticks,
		"trace_sha256": trace.finish().hex_encode()}
	_free(main)
	return result


func _tick_signature(sim: RestaurantSim) -> Dictionary:
	var actors: Array[Dictionary] = []
	for agent: SimAgent in sim.world.agents + sim.world.pending_agents():
		var row: Dictionary = {"id": agent.id, "role": agent.role, "cell": agent.cell,
			"path": agent.path.duplicate(), "index": agent.path_index, "progress": agent.move_progress,
			"admitted": agent.movement_admitted, "repath": agent.needs_repath,
			"last_progress": agent.last_progress_tick, "trace": agent.movement_trace()}
		if agent is StaffAgent:
			var staff: StaffAgent = agent as StaffAgent
			row["work"] = [staff.task.id if staff.task != null else 0, staff.step_index, staff.work_left]
		if agent is CustomerAgent:
			var guest: CustomerAgent = agent as CustomerAgent
			row["guest"] = [guest.state, guest.restroom, guest.table_item_id, guest.seat_cell,
				guest.waiting_item_id, guest.waiting_cell, guest.paid, guest.leave_reason, str(guest.rng.state)]
		if agent is CourierAgent:
			var courier: CourierAgent = agent as CourierAgent
			row["courier"] = [courier.state, courier.dropped, courier.all_dropped, courier.carrying]
		actors.append(row)
	var tasks: Array[Array] = []
	for task: SimTask in sim.world.board.open_tasks() + sim.world.board.claimed_tasks():
		tasks.append([task.id, task.kind, task.state, task.claimed_by, task.claimed_tick, task.drops])
	return {"now": sim.world.now, "clock": sim.world.clock.to_dict(), "actors": actors, "tasks": tasks,
		"movement_claims": sim.world.movement.snapshot(),
		"named_rngs": GameState.call("_capture_save"), "served": sim.served_today, "lost": sim.lost_today,
		"reasons": sim.leave_reasons_today.duplicate(), "cash": Economy.cash}


func _on_arrived(guest: CustomerAgent) -> void:
	assert_false(_arrived.has(guest.id), "one arrival event per visit")
	_arrived[guest.id] = true


func _on_left(guest: CustomerAgent, _reason: StringName) -> void:
	assert_true(_arrived.has(guest.id), "departure retains the arrival's identity")
	assert_false(_departed.has(guest.id), "one departure per visit, including pending-at-close")
	_departed[guest.id] = true


func _error(message: String) -> Dictionary:
	fail(message)
	return {"error": message}


func _free(main: Node) -> void:
	_mains.erase(main)
	if is_instance_valid(main):
		if main.is_inside_tree():
			main.get_parent().remove_child(main)
		main.free()
