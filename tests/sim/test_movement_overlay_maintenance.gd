extends TestCase
## Real staff task maintenance must survive consumed yield/stop movement ticks.
## Direct-grid solids are deliberate chaos faults, not permitted player edits.

const STATION: ItemDef = preload("res://data/items/prep_counter.tres")
const STATION_CELL: Vector2i = Vector2i(2, 1)
const POCKET: Vector2i = Vector2i(2, 0)
const WATCHDOG: int = 400
const MAINTENANCE_BOUND: int = 62

var _world: SimWorld
var _station: PlacedItem
var _working: StaffAgent
var _crossing: StaffAgent
var _station_task: SimTask
var _crossing_task: SimTask
var _callback_cells: Array[Vector2i] = []
var _drop_reasons: Array[StringName] = []


func before_each() -> void:
	_callback_cells.clear()
	_drop_reasons.clear()


func after_each() -> void:
	if _world != null:
		for agent: SimAgent in _world.agents.duplicate():
			_world.remove_agent(agent)
	_world = null
	_station = null
	_working = null
	_crossing = null
	_station_task = null
	_crossing_task = null


func test_buried_real_return_drops_work_and_releases_station_within_existing_stuck_bound() -> void:
	if not _reach_real_return(false):
		return
	assert_true(_world.grid.is_walkable(STATION_CELL))
	assert_eq(_working.next_cell(), STATION_CELL)
	assert_eq(_working.move_progress, 0.0)
	var position: Vector3 = _working.movement_position()
	var remaining_work: float = _working.work_left
	var blocked_tick: int = _world.now
	var blocker: PlacedItem = _world.grid.place(Vector2i.ONE, POCKET, 0, true)
	assert_not_null(blocker)
	if blocker == null:
		return
	assert_false(_world.grid.is_walkable(POCKET))
	assert_true(_world.grid.is_walkable(STATION_CELL), "the return destination stays open; its origin is buried")
	assert_true(_working.needs_repath)
	# The injected solid itself covers the current actor. The full geometry
	# oracle would correctly reject that fault; check its containment instead.
	for _tick: int in MAINTENANCE_BOUND:
		_world.advance()
		_assert_frozen(position, 0.0, remaining_work)
		assert_eq(_actor_edge(), {}, "a buried origin cannot acquire an escape edge")
		if _working.task == null:
			break
	assert_true(_world.now - blocked_tick <= MAINTENANCE_BOUND)
	assert_null(_working.task, "RETURNING must still run ordinary no-progress task maintenance within 62 ticks")
	assert_eq(_station_task.state, SimTask.State.OPEN)
	assert_eq(_station_task.claimed_by, -1)
	assert_eq(_station_task.drops, 1, "the ordinary stuck drop gives the task back exactly once")
	assert_eq(_drop_reasons, [&"stuck"] as Array[StringName])
	assert_eq(_station.reserved_by(STATION_CELL), -1, "an abandoned job cannot retain its station lease")
	assert_false(_world.movement.is_yielding(_working.id))
	assert_eq(_callback_cells, [] as Array[Vector2i])
	_world.grid.remove(blocker.id)
	_finish_after_restoring_geometry()


func test_blocked_reserved_stop_drops_work_but_holds_exact_edge_until_normal_completion() -> void:
	if not _reach_real_return(true):
		return
	var position: Vector3 = _working.movement_position()
	var progress: float = _working.move_progress
	var remaining_work: float = _working.work_left
	# Public cancellation of travel preserves the real reserved partial edge.
	# It does not withdraw the staff task or release the work-cell lease.
	_working.clear_path()
	assert_true(_world.movement.is_stopping(_working.id))
	assert_eq(_working.task, _station_task)
	assert_eq(_station.reserved_by(STATION_CELL), _working.id)
	_assert_reserved_return_edge()
	var blocker: PlacedItem = _world.grid.place(Vector2i.ONE, STATION_CELL, 0, true)
	assert_not_null(blocker)
	if blocker == null:
		return
	assert_false(_world.grid.is_walkable(STATION_CELL))
	var dropped_tick: int = -1
	for _tick: int in MAINTENANCE_BOUND:
		_world.advance()
		_assert_frozen(position, progress, remaining_work)
		_assert_reserved_return_edge()
		assert_true(_world.movement.is_stopping(_working.id))
		if _working.task == null and dropped_tick < 0:
			dropped_tick = _world.now
		if dropped_tick >= 0:
			assert_null(_working.task, "STOP cannot reclaim the reopened task before its real edge finishes")
			assert_eq(_station_task.state, SimTask.State.OPEN)
			assert_eq(_station_task.claimed_by, -1)
			assert_eq(_station_task.drops, 1)
			assert_eq(_station.reserved_by(STATION_CELL), -1)
	assert_true(dropped_tick >= 0, "STOP must still run ordinary no-progress maintenance within 62 ticks")
	assert_null(_working.task)
	assert_eq(_station_task.state, SimTask.State.OPEN)
	assert_eq(_station_task.drops, 1)
	assert_eq(_drop_reasons, [&"stuck"] as Array[StringName])
	assert_eq(_station.reserved_by(STATION_CELL), -1)
	assert_eq(_callback_cells, [] as Array[Vector2i])
	_world.grid.remove(blocker.id)
	# The first legal step resumes exactly the held edge, without a snap or
	# productive work. Only after reaching its vertex may the task be reclaimed.
	var first_progress: float = progress + _working.move_speed
	_advance_valid()
	assert_eq(_working.work_left, remaining_work)
	assert_null(_working.task)
	if first_progress < 1.0:
		assert_eq(_working.cell, POCKET)
		assert_almost_eq(_working.move_progress, first_progress)
		_assert_reserved_return_edge()
	else:
		assert_eq(_working.cell, STATION_CELL)
		assert_eq(_working.move_progress, 0.0)
		assert_false(_world.movement.is_stopping(_working.id))
	assert_eq(_callback_cells, [] as Array[Vector2i])
	_finish_after_restoring_geometry()


func _reach_real_return(partial: bool) -> bool:
	_world = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["##.##", ".....", "##..#"])))
	_world.board.task_dropped.connect(_task_dropped)
	_station = _world.grid.place_def(STATION, Vector2i(2, 2))
	assert_not_null(_station)
	if _station == null:
		return false
	assert_eq(_station.work_cells, [STATION_CELL] as Array[Vector2i])
	_crossing = StaffAgent.new(&"server")
	_crossing.cell = Vector2i(1, 1)
	_world.add_agent(_crossing)
	_working = StaffAgent.new(&"cook")
	_working.cell = STATION_CELL
	_world.add_agent(_working)
	assert_true(_crossing.id < _working.id)
	assert_eq(_world.movement.priority(_world, _crossing), _world.movement.priority(_world, _working))
	_station_task = SimTask.new(&"cook", &"cook", "Finish real station work after recovery")
	_station_task.steps = [TaskStep.go_to_item(_station.id),
		TaskStep.work(120, "work at station", _station_done)]
	_world.board.post(_station_task, _world.now)
	assert_eq(_station_task.timeout_ticks, 600, "the existing timeout is not shortened to mask missing stuck recovery")
	assert_true(_world.clock.start_service())
	for _tick: int in 3:
		_advance_valid()
	assert_eq(_working.task, _station_task)
	assert_eq(_working.step_index, 1)
	assert_true(_working.work_left > 0.0 and _working.work_left < 120.0)
	assert_eq(_station.reserved_by(STATION_CELL), _working.id)
	_crossing_task = SimTask.new(&"take_order", &"server", "Cross the occupied aisle")
	_crossing_task.steps = [TaskStep.go_to_cell(Vector2i(4, 1)), TaskStep.work(1)]
	_world.board.post(_crossing_task, _world.now)
	var saw_pocket: bool = false
	for _tick: int in WATCHDOG:
		_advance_valid()
		saw_pocket = saw_pocket or _working.cell == POCKET
		var returning: bool = _world.movement.snapshot().returning.has(_working.id)
		var phase_matches: bool = _working.move_progress > 0.0 if partial else _working.move_progress == 0.0
		if returning and _working.cell == POCKET and _working.next_cell() == STATION_CELL and phase_matches:
			assert_true(saw_pocket)
			assert_true(_world.movement.is_yielding(_working.id))
			assert_eq(_working.task, _station_task)
			assert_eq(_station_task.state, SimTask.State.CLAIMED)
			assert_eq(_station_task.claimed_by, _working.id)
			assert_eq(_station.reserved_by(STATION_CELL), _working.id)
			assert_eq(_callback_cells, [] as Array[Vector2i])
			return true
	fail("ordinary lower-ID aisle traffic must establish the requested actual return phase")
	return false


func _assert_frozen(position: Vector3, progress: float, remaining_work: float) -> void:
	assert_eq(_working.cell, POCKET)
	assert_eq(_working.movement_position(), position, "the chaos fault cannot teleport or further penetrate the person")
	assert_eq(_working.move_progress, progress)
	assert_eq(_working.work_left, remaining_work, "overlay maintenance must never execute WORK")
	assert_eq(_callback_cells, [] as Array[Vector2i])
	assert_eq(_world.movement.snapshot().occupied.get(POCKET, -1), _working.id)
	var trace: Dictionary = _working.movement_trace()
	assert_false(trace.discontinuous, "ordinary fault containment is not a position reset")
	for point: Vector3 in trace.points:
		assert_eq(point, position, "the entire observed trace must stay at the held physical position")
	for agent: SimAgent in _world.agents:
		if agent != _working:
			assert_ne(agent.cell, POCKET, "no peer may occupy the held origin")
			if agent.move_progress > 0.0:
				assert_ne(agent.next_cell(), POCKET, "no peer may travel into the held origin")


func _assert_reserved_return_edge() -> void:
	assert_eq(_working.next_cell(), STATION_CELL)
	assert_eq(_actor_edge(), {"id": _working.id, "from": POCKET, "to": STATION_CELL})
	assert_eq(_world.movement.snapshot().occupied.get(STATION_CELL, -1), -1,
		"the partial edge destination cannot be occupied by another person")
	assert_eq(_world.movement.snapshot().next.get(STATION_CELL, -1), _working.id,
		"task cleanup must preserve the exact physical next-cell ownership")


func _actor_edge() -> Dictionary:
	for edge: Dictionary in _world.movement.snapshot().edges:
		if edge.id == _working.id:
			return edge
	return {}


func _finish_after_restoring_geometry() -> void:
	for _tick: int in WATCHDOG:
		_advance_valid()
		if _station_task.state == SimTask.State.DONE and _crossing_task.state == SimTask.State.DONE:
			break
	assert_eq(_station_task.state, SimTask.State.DONE, "restoring geometry must allow real station work to complete")
	assert_eq(_crossing_task.state, SimTask.State.DONE)
	assert_eq(_crossing.cell, Vector2i(4, 1))
	assert_eq(_callback_cells, [STATION_CELL] as Array[Vector2i])
	assert_eq(_station.reserved_by(STATION_CELL), -1)
	assert_false(_world.movement.is_stopping(_working.id))
	assert_false(_world.movement.is_yielding(_working.id))
	assert_true(_working.has_arrived())


func _advance_valid() -> void:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	assert_eq(MovementInvariants.problem(_world, before), "", "ordinary movement must retain all physical invariants")


func _station_done(agent: SimAgent) -> bool:
	_callback_cells.append(agent.cell)
	return agent.cell == STATION_CELL and agent.move_progress == 0.0


func _task_dropped(task: SimTask, _actor_id: int, reason: StringName) -> void:
	if task == _station_task:
		_drop_reasons.append(reason)
