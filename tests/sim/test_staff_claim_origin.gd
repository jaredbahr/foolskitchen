extends TestCase
## New work waits for a legal physical origin; truly unreachable targets keep
## ordinary claim/drop recovery. Direct-grid solids are deliberate soak faults.

const PREP_COUNTER: ItemDef = preload("res://data/items/prep_counter.tres")
const ORIGIN: Vector2i = Vector2i(1, 1)
const STATION_CELL: Vector2i = Vector2i(4, 3)
const WATCHDOG: int = 512
const BURIAL_TICKS: int = 12

var _world: SimWorld
var _counter: PlacedItem
var _cook: StaffAgent
var _task: SimTask
var _completed: Array[int] = []
var _failed: Array[StringName] = []
var _drop_reasons: Array[StringName] = []
var _drop_actor_ids: Array[int] = []
var _worked_cells: Array[Vector2i] = []
var _callbacks_valid: bool = true


func before_each() -> void:
	_completed.clear()
	_failed.clear()
	_drop_reasons.clear()
	_drop_actor_ids.clear()
	_worked_cells.clear()
	_callbacks_valid = true
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"########",
		"#......#",
		"#......#",
		"#......#",
		"#......#",
		"########",
	]))
	_counter = grid.place_def(PREP_COUNTER, Vector2i(4, 4))
	assert_not_null(_counter)
	_world = SimWorld.new(grid)
	_cook = StaffAgent.new(&"cook", 3)
	_cook.cell = ORIGIN
	_world.add_agent(_cook)
	_task = SimTask.new(&"cook", &"cook", "Prepare at the counter")
	_task.steps.append(TaskStep.go_to_item(_counter.id, "going to the counter"))
	_task.steps.append(TaskStep.work(4, "preparing", _on_prepared))
	_world.board.task_completed.connect(_on_completed)
	_world.board.task_failed.connect(_on_failed)
	_world.board.task_dropped.connect(_on_dropped)
	assert_eq(_counter.work_cells, [STATION_CELL] as Array[Vector2i])
	assert_eq(_task.timeout_ticks, 600)
	assert_true(WATCHDOG < _task.timeout_ticks)
	assert_true(_world.clock.start_service())


func after_each() -> void:
	_world.board.task_completed.disconnect(_on_completed)
	_world.board.task_failed.disconnect(_on_failed)
	_world.board.task_dropped.disconnect(_on_dropped)


func test_buried_idle_origin_defers_new_claim_until_geometry_is_restored() -> void:
	if not _advance_valid():
		return
	assert_null(_cook.task)
	assert_eq(_cook.cell, ORIGIN)
	assert_true(_world.grid.is_walkable(ORIGIN), "the actor is genuinely active on legal floor before fault injection")
	assert_false(_world.grid.find_path(ORIGIN, STATION_CELL).is_empty())
	var position: Vector3 = _cook.movement_position()
	var physical_claims: Dictionary = _world.movement.snapshot()
	# This public direct-grid edit deliberately bypasses player placement checks,
	# as the existing soak does. It covers the actual admitted actor's origin.
	var blocker: PlacedItem = _world.grid.place(Vector2i.ONE, _cook.cell, 0, true)
	assert_not_null(blocker)
	if blocker == null:
		return
	assert_false(_world.grid.is_walkable(ORIGIN))
	assert_true(_world.grid.is_walkable(STATION_CELL), "the real station target is still free floor")
	assert_false(_world.grid.find_path(Vector2i(2, 1), STATION_CELL).is_empty(),
		"only the actor origin is buried; another legal floor cell can reach the station")
	_world.board.post(_task, _world.now)
	# The injected solid itself violates the full geometry oracle. During this
	# deliberate fault, independently check physical containment and claims.
	for tick: int in BURIAL_TICKS:
		_world.advance()
		_assert_buried_physics(position, physical_claims)
		assert_null(_cook.task, "a buried idle actor cannot consume a new Board claim")
		assert_eq(_task.state, SimTask.State.OPEN)
		assert_eq(_task.claimed_by, -1)
		assert_eq(_task.claimed_tick, -1)
		assert_eq(_task.drops, 0, "a temporary origin fault cannot spend a viable task's retry budget")
		assert_eq(_world.board.get_task(_task.id), _task)
		assert_eq(_world.board.open_tasks(), [_task] as Array[SimTask])
		assert_true(_world.board.claimed_tasks().is_empty())
		assert_eq(_counter.reserved_by(STATION_CELL), -1, "no new station lease while the worker is buried")
		assert_eq(_cook.work_left, 0.0)
		assert_true(_worked_cells.is_empty())
		assert_true(_completed.is_empty())
		assert_true(_failed.is_empty())
		assert_true(_drop_reasons.is_empty())
	_world.grid.remove(blocker.id)
	assert_true(_world.grid.is_walkable(ORIGIN))
	assert_eq(_cook.movement_position(), position, "restoring geometry does not reposition the actor")
	if not _advance_valid():
		return
	assert_eq(_cook.task, _task, "the first ordinary legal-origin tick can claim the waiting job")
	assert_eq(_task.state, SimTask.State.CLAIMED)
	assert_eq(_task.claimed_by, _cook.id)
	assert_eq(_task.claimed_tick, _world.now)
	var walked: bool = false
	for tick: int in range(_world.now, WATCHDOG):
		if not _advance_valid():
			return
		walked = walked or _cook.move_progress > 0.0
		if _task.state == SimTask.State.DONE:
			break
	assert_true(walked, "the worker traverses real claimed edges after the obstacle is removed")
	assert_eq(_task.state, SimTask.State.DONE)
	assert_eq(_task.drops, 0)
	assert_eq(_completed, [_task.id] as Array[int], "the original job completes exactly once")
	assert_eq(_worked_cells, [STATION_CELL] as Array[Vector2i])
	assert_true(_callbacks_valid, "WORK completes at the actual station under the real lease and Board claim")
	assert_eq(_cook.cell, STATION_CELL)
	assert_almost_eq(_cook.move_progress, 0.0)
	assert_null(_cook.task)
	assert_null(_world.board.get_task(_task.id))
	assert_eq(_counter.reserved_by(STATION_CELL), -1, "normal completion releases the actual station lease")
	assert_true(_drop_reasons.is_empty())
	assert_true(_failed.is_empty())
	assert_true(_world.now <= WATCHDOG)
	_assert_active_identity()


func test_walkable_origin_still_claims_and_drops_a_genuinely_unreachable_station() -> void:
	if not _advance_valid():
		return
	# The counter itself occupies the two southern neighbors. Real solids cover
	# the other six, boxing its sole work cell without burying the worker.
	var blocked_neighbors: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2),
		Vector2i(3, 3), Vector2i(5, 3), Vector2i(3, 4)]
	for cell: Vector2i in blocked_neighbors:
		assert_not_null(_world.grid.place(Vector2i.ONE, cell, 0, true))
	assert_true(_world.grid.is_walkable(ORIGIN))
	assert_true(_world.grid.is_walkable(STATION_CELL), "the target is a free work cell, not a busy reservation")
	assert_eq(_counter.reserved_by(STATION_CELL), -1)
	assert_true(_world.grid.find_path(ORIGIN, STATION_CELL).is_empty(), "the station is genuinely disconnected")
	for offset: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
			Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		assert_false(_world.grid.is_walkable(STATION_CELL + offset))
	_world.board.post(_task, _world.now)
	if not _advance_valid():
		return
	assert_eq(_cook.task, _task, "a legal origin retains ordinary task claiming even when its target is unreachable")
	assert_eq(_task.state, SimTask.State.CLAIMED)
	assert_eq(_task.claimed_by, _cook.id)
	assert_eq(_task.drops, 0)
	if not _advance_valid():
		return
	assert_null(_cook.task)
	assert_eq(_task.state, SimTask.State.OPEN)
	assert_eq(_task.drops, 1)
	assert_eq(_drop_reasons, [&"unreachable"] as Array[StringName])
	assert_eq(_counter.reserved_by(STATION_CELL), -1)
	for tick: int in range(_world.now, WATCHDOG):
		if not _advance_valid():
			return
		assert_eq(_cook.cell, ORIGIN)
		assert_almost_eq(_cook.move_progress, 0.0)
		assert_true(_worked_cells.is_empty())
		assert_eq(_counter.reserved_by(STATION_CELL), -1)
		if _task.state == SimTask.State.CANCELLED:
			break
	assert_eq(_task.state, SimTask.State.CANCELLED)
	assert_eq(_task.drops, TaskBoard.MAX_DROPS, "the existing Board retry budget still bounds truly broken work")
	assert_eq(_task.claimed_by, -1)
	assert_eq(_drop_reasons.size(), TaskBoard.MAX_DROPS)
	assert_eq(_drop_actor_ids.size(), TaskBoard.MAX_DROPS)
	for index: int in _drop_reasons.size():
		assert_eq(_drop_reasons[index], &"unreachable")
		assert_eq(_drop_actor_ids[index], _cook.id)
	assert_eq(_failed, [&"dropped_too_often"] as Array[StringName])
	assert_true(_completed.is_empty())
	assert_null(_cook.task)
	assert_null(_world.board.get_task(_task.id))
	assert_true(_world.now <= WATCHDOG)
	_assert_active_identity()


func _assert_buried_physics(position: Vector3, physical_claims: Dictionary) -> void:
	_assert_active_identity()
	assert_eq(_cook.cell, ORIGIN)
	assert_eq(_cook.next_cell(), ORIGIN)
	assert_eq(_cook.move_progress, 0.0)
	assert_eq(_cook.movement_position(), position)
	assert_eq(_world.movement.snapshot(), physical_claims, "the deliberate fault preserves all observed physical claims")
	var trace: Dictionary = _cook.movement_trace()
	assert_eq(trace.tick, _world.now)
	assert_false(trace.discontinuous, "fault containment cannot reset the admitted actor")
	assert_eq(trace.discontinuity_cause, "")
	assert_eq(trace.times, [0.0, 1.0] as Array[float])
	assert_eq(trace.points, [position, position] as Array[Vector3], "the entire actual tick trace stays at the buried origin")


func _advance_valid() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "", "all ordinary movement keeps the complete physical invariant oracle")
	_assert_active_identity()
	return problem.is_empty()


func _assert_active_identity() -> void:
	assert_eq(_world.agents, [_cook] as Array[SimAgent])
	assert_eq(_world.agent(_cook.id), _cook)
	assert_true(_cook.movement_admitted)
	assert_true(_world.pending_agents().is_empty(), "the active worker cannot be hidden in admission")


func _on_prepared(agent: StaffAgent) -> bool:
	_worked_cells.append(agent.cell)
	var valid: bool = agent == _cook and agent.cell == STATION_CELL and agent.move_progress == 0.0 \
		and _counter.reserved_by(STATION_CELL) == agent.id and agent.task == _task \
		and _task.state == SimTask.State.CLAIMED and _task.claimed_by == agent.id \
		and _world.board.get_task(_task.id) == _task
	_callbacks_valid = _callbacks_valid and valid
	return valid


func _on_completed(task: SimTask) -> void:
	if task == _task:
		_completed.append(task.id)


func _on_failed(task: SimTask, reason: StringName) -> void:
	if task == _task:
		_failed.append(reason)


func _on_dropped(task: SimTask, actor_id: int, reason: StringName) -> void:
	if task == _task:
		_drop_reasons.append(reason)
		_drop_actor_ids.append(actor_id)
