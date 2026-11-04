extends TestCase
## Historical private-seat barrier: guests retain their own departure lifecycle;
## idle staff (including a Floor owner) still physically vacate a cleaned seat.

const LAYOUT = preload("res://tests/fixtures/legacy_tier1_layout.gd")
const SEAT: Vector2i = Vector2i(1, 7)
const NORTH: Vector2i = Vector2i(1, 6)
const SOUTH: Vector2i = Vector2i(1, 8)
const ARRIVAL_WATCHDOG: int = 128
const EXIT_WATCHDOG: int = 64
const BUS_WATCHDOG: int = 64

var _sim: RestaurantSim
var _guest: CustomerAgent
var _table: PlacedItem
var _busser: StaffAgent
var _bus_task: SimTask
var _departures: Array[int] = []
var _bus_completions: Array[int] = []
var _bus_work: Array[Vector2i] = []
var _callback_valid: bool = true


func before_each() -> void:
	_departures.clear()
	_bus_completions.clear()
	_bus_work.clear()
	_callback_valid = true
	_guest = null
	_busser = null
	_bus_task = null
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.new()
	_sim.world = ShopBuilder.build(LAYOUT.make(), content, errors)
	assert_eq(errors, [] as Array[String])
	# Declared customer-only/no-menu scenario. No order, payment, patience or
	# movement state is fabricated; the real arrival reaches its normal no-menu exit.
	assert_true(_sim.menu.is_empty())
	for item: PlacedItem in _sim.world.grid.items():
		if item.seat_cells.has(SEAT):
			_table = item
			break
	assert_not_null(_table)
	_sim.customer_left.connect(_on_left)
	_sim.world.board.task_completed.connect(_on_bus_completed)
	assert_true(_sim.world.clock.start_service())


func after_each() -> void:
	_sim.customer_left.disconnect(_on_left)
	_sim.world.board.task_completed.disconnect(_on_bus_completed)
	# WORK binds this TestCase; release retained task/actor/world references.
	_bus_task = null
	_busser = null
	_guest = null
	_table = null
	_sim = null


func test_customer_keeps_real_downward_exit_after_no_menu_releases_booked_seat() -> void:
	if not _arrive_and_leave_without_menu():
		return
	assert_eq(_guest.state, CustomerAgent.State.LEAVING)
	assert_eq(_guest.leave_reason, &"no_menu")
	assert_eq(_guest.cell, SEAT)
	assert_true(_guest.has_arrived())
	assert_true(_guest.path.is_empty(), "the normal leave transition cleared its completed seat route")
	assert_eq(_table.reserved_by(SEAT), _guest.id, "booking remains until physical departure")
	if not _advance():
		return
	assert_eq(_guest.cell, SEAT)
	assert_eq(_guest.next_cell(), SOUTH, "Customer chooses its actual exit, not Staff's north-first evacuation")
	assert_true(_guest.move_progress > 0.0)
	assert_eq(_table.reserved_by(SEAT), _guest.id, "a partial edge cannot release its occupied source seat")
	assert_false(_sim.world.movement.is_stopping(_guest.id), "ordinary departure must not be replaced by busser STOP")
	_finish_customer_exit()


func test_customer_partial_departure_replan_preserves_real_edge_and_booking() -> void:
	if not _arrive_and_leave_without_menu():
		return
	var route: Array[Vector2i] = _sim.world.grid.find_guest_path_to_any(SEAT, _sim.world.grid.entries())
	assert_false(route.is_empty())
	if route.is_empty():
		return
	assert_eq(route[1], SOUTH)
	assert_true(_guest.set_destination(_sim.world.grid, route.back()))
	# Start one genuine physical edge through the existing public movement API,
	# as the existing mid-edge departure regression does. No path/progress/map writes.
	_guest.begin_movement_trace(_sim.world.now)
	assert_eq(_guest.step_move(_sim.world), SimAgent.MoveResult.MOVING)
	_guest.end_movement_trace()
	assert_eq(_guest.cell, SEAT)
	assert_eq(_guest.next_cell(), SOUTH)
	assert_true(_guest.move_progress > 0.0)
	var before_position: Vector3 = _guest.movement_position()
	_guest.needs_repath = true
	if not _advance():
		return
	assert_eq(_guest.cell, SEAT)
	assert_eq(_guest.next_cell(), SOUTH)
	assert_true(_guest.movement_position().distance_to(GridMath.cell_to_world(SOUTH)) \
		< before_position.distance_to(GridMath.cell_to_world(SOUTH)), "replan advances the retained real edge")
	assert_eq(_table.reserved_by(SEAT), _guest.id)
	_finish_customer_exit()


func test_idle_staff_busser_still_evacuates_and_releases_real_seat_lease() -> void:
	_busser = StaffAgent.new(&"server", 3)
	_run_real_busser()


func test_floor_owner_busser_keeps_staff_evacuating_behavior() -> void:
	var owner: OwnerAgent = OwnerAgent.new(SOUTH)
	assert_true(owner.assign_mode(&"floor"))
	_busser = owner
	_run_real_busser()
	assert_eq(owner.current_mode(), &"floor")


func _arrive_and_leave_without_menu() -> bool:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 263
	_guest = _sim.add_customer(_sim.world.grid.entries()[0], random)
	assert_not_null(_guest)
	if _guest == null:
		return false
	var booked: bool = false
	for tick: int in ARRIVAL_WATCHDOG:
		if not _advance():
			return false
		booked = booked or (_guest.table_item_id == _table.id and _guest.seat_cell == SEAT \
			and _table.reserved_by(SEAT) == _guest.id)
		if _guest.state == CustomerAgent.State.LEAVING:
			break
	assert_true(booked, "real arrival actually booked the historical first seat")
	assert_eq(_guest.state, CustomerAgent.State.LEAVING)
	assert_eq(_guest.cell, SEAT)
	assert_eq(_guest.leave_reason, &"no_menu")
	assert_eq(_sim.world.agent(_guest.id), _guest)
	assert_true(_departures.is_empty())
	return booked and _guest.state == CustomerAgent.State.LEAVING and _guest.cell == SEAT


func _finish_customer_exit() -> void:
	var released: bool = false
	for tick: int in EXIT_WATCHDOG:
		if not _advance():
			return
		if _table.reserved_by(SEAT) == -1:
			released = true
			assert_ne(_guest.cell, SEAT, "release only follows actual vacancy")
		if _guest.state == CustomerAgent.State.LEFT:
			break
	assert_true(released)
	assert_eq(_guest.state, CustomerAgent.State.LEFT)
	assert_true(_sim.world.grid.entries().has(_guest.cell), "actual exit vertex, never the100-tick unreachable fallback")
	assert_almost_eq(_guest.move_progress, 0.0)
	assert_eq(_table.reserved_by(SEAT), -1)
	assert_eq(_sim.lost_today, 0, "world-only ticks have not fabricated RestaurantSim cleanup")
	_sim.world.remove_agent(_guest)
	assert_null(_sim.world.agent(_guest.id))
	assert_eq(_departures, [_guest.id] as Array[int])
	assert_eq(_sim.lost_today, 1)
	_sim.record_departure(_guest)
	assert_eq(_departures, [_guest.id] as Array[int])
	assert_eq(_sim.lost_today, 1, "ordinary departure accounting remains exactly once")


func _run_real_busser() -> void:
	_busser.cell = SOUTH
	_sim.world.add_agent(_busser)
	assert_true(_busser.movement_admitted)
	_bus_task = SimTask.new(&"bus_table", &"server", "Clear real seat")
	_bus_task.steps.append(TaskStep.go_to_item(_table.id, "walk to seat", true))
	_bus_task.steps.append(TaskStep.work(1, "clear seat", _on_bus_work))
	_sim.world.board.post(_bus_task, _sim.world.now)
	for tick: int in BUS_WATCHDOG:
		if not _advance():
			return
		if _bus_task.state == SimTask.State.DONE:
			break
	assert_eq(_bus_task.state, SimTask.State.DONE)
	assert_eq(_bus_task.drops, 0)
	assert_eq(_bus_completions, [_bus_task.id] as Array[int])
	assert_eq(_bus_work, [SEAT] as Array[Vector2i])
	assert_true(_callback_valid, "real completed WORK held the actual seat lease and Board claim")
	assert_null(_busser.task)
	assert_eq(_busser.cell, SEAT)
	assert_eq(_table.reserved_by(SEAT), _busser.id, "completed busser still physically occupies its released seat")
	for tick: int in BUS_WATCHDOG:
		if not _advance():
			return
		if _table.reserved_by(SEAT) == -1:
			break
	assert_eq(_table.reserved_by(SEAT), -1)
	assert_eq(_busser.cell, NORTH, "idle staff retain actual north-first standing-cell evacuation")
	assert_almost_eq(_busser.move_progress, 0.0)
	assert_null(_busser.task)
	assert_eq(_sim.world.agent(_busser.id), _busser)
	assert_true(_sim.world.pending_agents().is_empty())


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_sim.world)
	_sim.world.advance()
	var problem: String = MovementInvariants.problem(_sim.world, before)
	assert_eq(problem, "", "every actual tick retains all independent physical/seat/trace invariants")
	assert_true(_sim.world.pending_agents().is_empty())
	return problem.is_empty()


func _on_bus_work(agent: SimAgent) -> bool:
	_bus_work.append(agent.cell)
	var valid: bool = agent == _busser and agent.cell == SEAT and agent.move_progress == 0.0 \
		and _table.reserved_by(SEAT) == agent.id and _busser.task == _bus_task \
		and _bus_task.state == SimTask.State.CLAIMED and _bus_task.claimed_by == agent.id \
		and _sim.world.board.get_task(_bus_task.id) == _bus_task
	_callback_valid = _callback_valid and valid
	return valid


func _on_bus_completed(task: SimTask) -> void:
	if task == _bus_task:
		_bus_completions.append(task.id)


func _on_left(guest: CustomerAgent, _reason: StringName) -> void:
	_departures.append(guest.id)
