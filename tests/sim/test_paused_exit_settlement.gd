extends TestCase
## Real entry birth, ordinary300-tick no-table departure and a real Staff job
## create recovery movement. No active reset, lifecycle/map/edge fabrication.

const ORIGINAL_EXIT: Vector2i = Vector2i(2, 1)
const WAITING: Vector2i = Vector2i(2, 2)
const POCKET: Vector2i = Vector2i(3, 2)
const CROSSING_GOAL: Vector2i = Vector2i(2, 3)
const ARRIVAL_WATCHDOG: int = 384
const RECOVERY_WATCHDOG: int = 128
var _sim: RestaurantSim
var _guest: CustomerAgent
var _staff: StaffAgent
var _crossing: SimTask
var _callbacks: int = 0
var _departures: Array[int] = []
var _witnesses: Array[Dictionary] = []
var _removed: bool = false
var _private_rng: int = 0
var _arrival_rng: int = 0


func after_each() -> void:
	print("PAUSED_EXIT_WITNESSES " + JSON.stringify(_witnesses))
	if _sim != null:
		_sim.customer_left.disconnect(_on_left)
		for actor: SimAgent in _sim.world.all_agents():
			_sim.world.remove_agent(actor)
	_crossing = null
	_guest = null
	_staff = null
	_sim = null


func test_real_leaving_guest_finishes_at_alternate_entry_reached_during_yield() -> void:
	if not _fixture(true):
		return
	_post_crossing()
	if not _reach_outbound_pocket():
		return
	assert_eq(_guest.cell, POCKET)
	assert_eq(_guest.move_progress, 0.0)
	assert_true(_sim.world.grid.entries().has(_guest.cell))
	assert_eq(_guest.destination(), ORIGINAL_EXIT, "the alternate exit was reached through genuine temporary recovery")
	assert_true(_sim.world.movement.is_yielding(_guest.id))
	assert_false(_sim.world.movement.is_stopping(_guest.id))
	assert_eq(_staff.cell, ORIGINAL_EXIT, "the old chosen exit remains physically occupied at this arrival")
	assert_eq(_staff.move_progress, 0.0)
	assert_eq(_callbacks, 0)
	assert_eq(_guest.state, CustomerAgent.State.LEFT,
		"consumed recovery movement must settle actual arrival at either real exit on this tick")
	if _guest.state != CustomerAgent.State.LEFT:
		return
	_finish_one_departure()


func test_partial_entry_edge_keeps_leaving_guest_and_exact_reserved_stop() -> void:
	if not _fixture(true, true):
		return
	# Only public MORNING speed configuration differs. The unchanged300 queue
	# deadline naturally expires during real ENTRY-to-FLOOR ingress, and _leave
	# itself creates STOP. This tests ENTRY+progress>0, not merely a floor source.
	assert_true(_sim.world.grid.entries().has(_guest.cell))
	assert_eq(_guest.cell, POCKET)
	assert_true(_guest.move_progress > 0.0 and _guest.move_progress < 1.0)
	assert_eq(_guest.next_cell(), WAITING)
	assert_true(_sim.world.movement.is_stopping(_guest.id))
	var edge: Dictionary = _edge()
	assert_false(edge.is_empty())
	var before_progress: float = _guest.move_progress
	_witness("natural_partial_ENTRY_stop")
	if not _advance():
		return
	assert_eq(_guest.state, CustomerAgent.State.LEAVING, "an ENTRY source is not an exit arrival while its edge is partial")
	assert_true(_sim.world.movement.is_stopping(_guest.id))
	assert_eq(_edge(), edge)
	assert_eq(_guest.cell, POCKET)
	assert_eq(_guest.next_cell(), WAITING)
	assert_almost_eq(_guest.move_progress, before_progress + _guest.move_speed, 0.00001,
		"pause maintenance cannot perform a second move or abandon the real edge")
	assert_true(_departures.is_empty())
	assert_eq(_sim.lost_today, 0)
	_assert_rng()


func test_non_exit_recovery_pocket_does_not_finish_departure() -> void:
	if not _fixture(false):
		return
	_post_crossing()
	if not _reach_outbound_pocket():
		return
	assert_eq(_guest.cell, POCKET)
	assert_eq(_sim.world.grid.terrain(POCKET), SimGrid.Terrain.FLOOR)
	assert_false(_sim.world.grid.entries().has(POCKET))
	assert_eq(_guest.move_progress, 0.0)
	assert_eq(_guest.state, CustomerAgent.State.LEAVING)
	assert_true(_departures.is_empty())
	assert_eq(_sim.lost_today, 0)
	# Preserve the actual original goal; ordinary return travel reaches an exit.
	assert_eq(_guest.destination(), ORIGINAL_EXIT)
	for tick: int in RECOVERY_WATCHDOG:
		if not _advance():
			return
		if _guest.state == CustomerAgent.State.LEFT:
			break
	assert_eq(_guest.state, CustomerAgent.State.LEFT)
	if _guest.state != CustomerAgent.State.LEFT:
		return
	_finish_one_departure()


func _fixture(entry_pocket: bool, slow_ingress: bool = false) -> bool:
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.from_ascii(PackedStringArray([
		"#####", "##E##", "#..E#" if entry_pocket else "#E..#", "##.##"])))
	_sim.rng.seed = 263
	_staff = StaffAgent.new(&"cleaner", 3)
	_staff.cell = ORIGINAL_EXIT
	_sim.world.add_agent(_staff)
	assert_true(_staff.movement_admitted)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 263
	var birth: Vector2i = POCKET if entry_pocket else Vector2i(1, 2)
	assert_true(_sim.world.grid.entries().has(birth))
	_guest = _sim.add_customer(birth, random)
	assert_not_null(_guest)
	if _guest == null:
		return false
	assert_true(_guest.movement_admitted)
	assert_eq(_guest.cell, birth, "real entry birth, never a reset or teleport")
	assert_true(_staff.id < _guest.id)
	assert_true(_sim.world.movement.priority(_sim.world, _staff) > _sim.world.movement.priority(_sim.world, _guest))
	assert_eq(_guest.queue_patience, 300, "retain the ordinary patience budget")
	if slow_ingress:
		_guest.move_speed = 0.001
	_private_rng = _guest.rng.state
	_arrival_rng = _sim.rng.state
	_sim.customer_left.connect(_on_left)
	assert_true(_sim.world.clock.start_service())
	for tick: int in ARRIVAL_WATCHDOG:
		if not _advance():
			return false
		if _guest.state == CustomerAgent.State.LEAVING:
			break
	assert_eq(_guest.state, CustomerAgent.State.LEAVING)
	assert_eq(_guest.leave_reason, &"no_table")
	assert_eq(_guest._queue_wait, 300)
	assert_false(_guest.paid)
	assert_true(_departures.is_empty())
	assert_eq(_sim.world.clock.phase, SimClock.Phase.OPEN)
	if slow_ingress:
		assert_eq(_guest.cell, birth)
		assert_true(_guest.move_progress > 0.0)
		assert_true(_sim.world.movement.is_stopping(_guest.id))
	else:
		assert_eq(_guest.cell, WAITING)
		assert_eq(_guest.move_progress, 0.0)
		var chosen: Array[Vector2i] = _sim.world.grid.find_guest_path_to_any(_guest.cell, _sim.world.grid.entries())
		assert_false(chosen.is_empty())
		if chosen.is_empty():
			return false
		assert_eq(chosen.back(), ORIGINAL_EXIT, "prove the actual original exit tie before creating a yield")
	_witness("natural_LEAVING")
	return _guest.state == CustomerAgent.State.LEAVING


func _post_crossing() -> void:
	_crossing = SimTask.new(&"cross_departing_guest", &"cleaner", "Cross departing guest's floor")
	assert_eq(_crossing.timeout_ticks, 600)
	_crossing.steps = [TaskStep.go_to_cell(CROSSING_GOAL), TaskStep.work(1, "complete actual crossing", _crossed)]
	_sim.world.board.post(_crossing, _sim.world.now)


func _reach_outbound_pocket() -> bool:
	var saw_partial: bool = false
	for tick: int in RECOVERY_WATCHDOG:
		if not _advance():
			return false
		if not _sim.world.movement.is_yielding(_guest.id) or _guest.path.is_empty():
			continue
		# This setup assertion prevents a west-entry sidestep from masquerading
		# as the intended FLOOR-pocket negative control.
		assert_eq(_guest.path.back(), POCKET, "prove the actual chosen recovery endpoint")
		if _guest.path.back() != POCKET:
			return false
		assert_eq(_guest.destination(), ORIGINAL_EXIT)
		assert_false(_sim.world.movement.snapshot().returning.has(_guest.id))
		saw_partial = saw_partial or (_guest.cell == WAITING and _guest.next_cell() == POCKET and _guest.move_progress > 0.0)
		if _guest.cell == POCKET and _guest.move_progress == 0.0 and _guest.has_arrived():
			assert_true(saw_partial, "the pocket must be reached through real partial edges")
			assert_eq(_guest._exit_unreachable, 0, "never use the100-tick removal fallback")
			_witness("actual_outbound_pocket_arrival")
			return saw_partial
	fail("the real crossing did not establish the required outbound pocket within128ticks")
	return false


func _finish_one_departure() -> void:
	assert_true(_sim.world.grid.entries().has(_guest.cell))
	assert_eq(_guest.move_progress, 0.0)
	assert_eq(_guest._exit_unreachable, 0)
	assert_eq(_guest.state, CustomerAgent.State.LEFT)
	assert_eq(_departures, [] as Array[int], "world-only ticks defer ordinary removal accounting")
	_sim.world.remove_agent(_guest)
	_removed = true
	assert_null(_sim.world.agent(_guest.id))
	assert_eq(_departures, [_guest.id] as Array[int])
	assert_eq(_sim.lost_today, 1)
	assert_eq(_sim.served_today, 0)
	assert_eq(_sim.leave_reasons_today.get(&"no_table", 0), 1)
	_sim.record_departure(_guest)
	assert_eq(_departures, [_guest.id] as Array[int])
	assert_eq(_sim.lost_today, 1, "recording again cannot duplicate a departure")
	for tick: int in RECOVERY_WATCHDOG:
		if _crossing.state == SimTask.State.DONE:
			break
		if not _advance():
			return
	assert_eq(_crossing.state, SimTask.State.DONE)
	assert_eq(_crossing.drops, 0)
	assert_eq(_callbacks, 1)
	assert_eq(_departures, [_guest.id] as Array[int])
	_assert_rng()
	_witness("one_recorded_departure")


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_sim.world)
	_sim.world.advance()
	var problem: String = MovementInvariants.problem(_sim.world, before)
	assert_eq(problem, "", "every ordinary world tick retains complete physical, seat, swept-edge and continuous-speed invariants")
	assert_eq(_sim.world.agents.size(), 1 if _removed else 2)
	assert_true(_sim.world.pending_agents().is_empty())
	return problem.is_empty()


func _edge() -> Dictionary:
	for edge: Dictionary in _sim.world.movement.snapshot().edges:
		if edge.id == _guest.id:
			return edge
	return {}


func _crossed(actor: SimAgent) -> bool:
	_callbacks += 1
	var valid: bool = actor == _staff and actor.cell == CROSSING_GOAL and actor.move_progress == 0.0 \
		and _staff.task == _crossing and _crossing.state == SimTask.State.CLAIMED \
		and _crossing.claimed_by == actor.id and _sim.world.board.get_task(_crossing.id) == _crossing
	assert_true(valid, "the real claimed crossing performs WORK only at its true goal")
	return valid


func _on_left(guest: CustomerAgent, _reason: StringName) -> void:
	_departures.append(guest.id)


func _assert_rng() -> void:
	assert_eq(_guest.rng.state, _private_rng)
	assert_eq(_sim.rng.state, _arrival_rng)


func _witness(phase: String) -> void:
	_witnesses.append({"phase": phase, "tick": _sim.world.now, "state": int(_guest.state),
		"cell": [_guest.cell.x, _guest.cell.y], "next": [_guest.next_cell().x, _guest.next_cell().y],
		"goal": [_guest.destination().x, _guest.destination().y], "progress": _guest.move_progress,
		"yielding": _sim.world.movement.is_yielding(_guest.id), "stopping": _sim.world.movement.is_stopping(_guest.id),
		"returning": _sim.world.movement.snapshot().returning.has(_guest.id),
		"staff_cell": [_staff.cell.x, _staff.cell.y], "departures": _departures.duplicate()})
