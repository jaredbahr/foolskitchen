extends TestCase
## Unindexed station approach uses actual legal routes; task picking is unchanged.

const FIRST: Vector2i = Vector2i(4, 2)
const SECOND: Vector2i = Vector2i(4, 4)
const WATCHDOG: int = 128

var _world: SimWorld
var _station: PlacedItem
var _worker: StaffAgent
var _task: SimTask
var _completed: Array[int] = []
var _failed: Array[StringName] = []
var _drops: Array[StringName] = []
var _worked: Array[Vector2i] = []
var _callbacks_valid: bool = true


func before_each() -> void:
	_completed.clear()
	_failed.clear()
	_drops.clear()
	_worked.clear()
	_callbacks_valid = true
	_worker = null
	_task = null
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"##########", "#........#", "#........#", "#........#",
		"#........#", "#........#", "#........#", "##########",
	]))
	_station = grid.place(Vector2i(2, 1), Vector2i(4, 3), 0, true,
		[Vector2i(0, -1), Vector2i(0, 1)] as Array[Vector2i])
	assert_not_null(_station)
	_world = SimWorld.new(grid)
	_world.board.task_completed.connect(_on_completed)
	_world.board.task_failed.connect(_on_failed)
	_world.board.task_dropped.connect(_on_dropped)
	assert_eq(_station.work_cells, [FIRST, SECOND] as Array[Vector2i])
	assert_true(_world.clock.start_service())


func after_each() -> void:
	_world.board.task_completed.disconnect(_on_completed)
	_world.board.task_failed.disconnect(_on_failed)
	_world.board.task_dropped.disconnect(_on_dropped)
	# The WORK callback binds this TestCase; release the retained task cycle.
	_task = null
	_worker = null
	_station = null
	_world = null


func test_worker_already_at_second_free_cell_works_without_departing() -> void:
	_start(SECOND)
	var position: Vector3 = _worker.movement_position()
	for tick: int in WATCHDOG:
		if not _advance_valid():
			return
		assert_eq(_worker.cell, SECOND, "available current work cell needs no walk to authored-first")
		assert_eq(_worker.movement_position(), position)
		assert_almost_eq(_worker.move_progress, 0.0)
		if _task.state == SimTask.State.DONE:
			break
	_assert_done(SECOND)


func test_shorter_real_route_beats_straight_line_nearer_authored_first() -> void:
	# The wall forces the worker around its south end. FIRST has the smaller
	# octile lower bound, but SECOND has the genuinely shorter physical route.
	for point: Vector2i in [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]:
		assert_not_null(_world.grid.place(Vector2i.ONE, point, 0, true))
	var origin: Vector2i = Vector2i(1, 2)
	var first_path: Array[Vector2i] = _world.grid.find_path(origin, FIRST)
	var second_path: Array[Vector2i] = _world.grid.find_path(origin, SECOND)
	assert_false(first_path.is_empty())
	assert_false(second_path.is_empty())
	assert_true(GridMath.octile(origin, FIRST) < GridMath.octile(origin, SECOND))
	assert_true(GridMath.path_cost(second_path) < GridMath.path_cost(first_path),
		"precondition distinguishes real route cost from straight-line distance")
	_start(origin)
	_run_to_terminal()
	_assert_done(SECOND)


func test_available_unreachable_first_cell_does_not_hide_reachable_second() -> void:
	_box_first()
	var origin: Vector2i = Vector2i(1, 5)
	assert_true(_world.grid.is_walkable(FIRST))
	assert_true(_world.grid.find_path(origin, FIRST).is_empty())
	assert_false(_world.grid.find_path(origin, SECOND).is_empty())
	_start(origin)
	_run_to_terminal()
	_assert_done(SECOND)


func test_nearer_reserved_cell_keeps_other_workers_real_lease() -> void:
	var other: StaffAgent = _holder(1)
	assert_eq(_station.reserved_by(SECOND), other.id)
	_start(Vector2i(3, 5))
	_run_to_terminal()
	_assert_done(FIRST)
	assert_eq(_station.reserved_by(SECOND), other.id, "another worker's actual lease is never borrowed")
	assert_not_null(other.task)
	assert_eq(other.task.state, SimTask.State.CLAIMED)


func test_equal_real_cost_keeps_authored_cell_order() -> void:
	var origin: Vector2i = Vector2i(1, 3)
	var first_path: Array[Vector2i] = _world.grid.find_path(origin, FIRST)
	var second_path: Array[Vector2i] = _world.grid.find_path(origin, SECOND)
	assert_false(first_path.is_empty())
	assert_false(second_path.is_empty())
	assert_almost_eq(GridMath.path_cost(first_path), GridMath.path_cost(second_path))
	_start(origin)
	_run_to_terminal()
	_assert_done(FIRST)


func test_all_available_cells_unreachable_use_existing_bounded_drop_recovery() -> void:
	_box_first()
	for point: Vector2i in [Vector2i(3, 4), Vector2i(3, 5), Vector2i(4, 5),
			Vector2i(5, 5), Vector2i(5, 4)]:
		assert_not_null(_world.grid.place(Vector2i.ONE, point, 0, true))
	var origin: Vector2i = Vector2i(1, 5)
	for point: Vector2i in _station.work_cells:
		assert_true(_world.grid.is_walkable(point))
		assert_eq(_station.reserved_by(point), -1)
		assert_true(_world.grid.find_path(origin, point).is_empty())
	_start(origin)
	if not _advance_valid():
		return
	assert_eq(_task.state, SimTask.State.CLAIMED, "the real Board first grants an ordinary claim")
	assert_eq(_task.claimed_by, _worker.id)
	if not _advance_valid():
		return
	assert_eq(_task.state, SimTask.State.OPEN)
	assert_eq(_task.drops, 1)
	assert_eq(_drops, [&"unreachable"] as Array[StringName])
	_run_to_terminal()
	assert_eq(_task.state, SimTask.State.CANCELLED)
	assert_eq(_task.drops, TaskBoard.MAX_DROPS)
	assert_eq(_drops, [&"unreachable", &"unreachable", &"unreachable"] as Array[StringName])
	assert_eq(_failed, [&"dropped_too_often"] as Array[StringName])
	assert_true(_completed.is_empty())
	assert_true(_worked.is_empty())
	assert_eq(_worker.cell, origin)
	assert_almost_eq(_worker.move_progress, 0.0)
	assert_null(_worker.task)
	assert_null(_world.board.get_task(_task.id))
	for point: Vector2i in _station.work_cells:
		assert_eq(_station.reserved_by(point), -1)


func test_no_free_lease_waits_then_completes_after_real_holders_release() -> void:
	var first_holder: StaffAgent = _holder(0)
	var second_holder: StaffAgent = _holder(1)
	var first_task: SimTask = first_holder.task
	var second_task: SimTask = second_holder.task
	_start(Vector2i(1, 5))
	for tick: int in 6:
		if not _advance_valid():
			return
		assert_eq(_task.state, SimTask.State.CLAIMED)
		assert_eq(_task.claimed_by, _worker.id)
		assert_eq(_task.drops, 0, "busy cells retain the existing wait instead of spending retries")
		assert_eq(_worker.cell, Vector2i(1, 5))
		assert_eq(_station.reserved_by(FIRST), first_holder.id)
		assert_eq(_station.reserved_by(SECOND), second_holder.id)
		assert_true(_worked.is_empty())
		assert_true(_drops.is_empty())
		assert_true(_failed.is_empty())
	_world.board.cancel(first_task, &"fixture_release")
	_world.board.cancel(second_task, &"fixture_release")
	_run_to_terminal()
	_assert_done(SECOND)
	assert_eq(_station.reserved_by(FIRST), -1)
	assert_eq(_station.reserved_by(SECOND), -1)


func _start(origin: Vector2i) -> void:
	_worker = StaffAgent.new(&"cook", 3)
	_worker.cell = origin
	_world.add_agent(_worker)
	assert_true(_worker.movement_admitted)
	assert_eq(_world.agent(_worker.id), _worker)
	assert_true(_world.pending_agents().is_empty())
	_task = SimTask.new(&"cook", &"cook", "Use station")
	_task.steps.append(TaskStep.go_to_item(_station.id, "walking to station"))
	_task.steps.append(TaskStep.work(4, "working", _on_worked))
	assert_eq(_task.timeout_ticks, 600)
	assert_true(WATCHDOG < _task.timeout_ticks)
	_world.board.post(_task, _world.now)


func _holder(index: int) -> StaffAgent:
	var holder: StaffAgent = StaffAgent.new(&"server", 3)
	holder.cell = _station.work_cells[index]
	_world.add_agent(holder)
	assert_true(holder.movement_admitted)
	var held_task: SimTask = SimTask.new(&"job", &"server", "Hold exact station side")
	held_task.steps.append(TaskStep.go_to_work_cell(_station.id, index))
	held_task.steps.append(TaskStep.work(100))
	_world.board.post(held_task, _world.now)
	for tick: int in 2:
		if not _advance_valid():
			return holder
	assert_eq(holder.task, held_task)
	assert_eq(held_task.state, SimTask.State.CLAIMED)
	assert_eq(held_task.claimed_by, holder.id)
	assert_eq(_world.board.get_task(held_task.id), held_task)
	assert_eq(_station.reserved_by(holder.cell), holder.id)
	return holder


func _box_first() -> void:
	# The station body already closes (4,3)/(5,3); close its other six neighbors.
	for point: Vector2i in [Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
			Vector2i(3, 2), Vector2i(5, 2), Vector2i(3, 3)]:
		assert_not_null(_world.grid.place(Vector2i.ONE, point, 0, true))


func _run_to_terminal() -> void:
	for tick: int in range(_world.now, WATCHDOG):
		if not _advance_valid():
			return
		if _task.state in [SimTask.State.DONE, SimTask.State.CANCELLED]:
			break
	assert_true(_world.now <= WATCHDOG)


func _assert_done(expected_cell: Vector2i) -> void:
	assert_eq(_task.state, SimTask.State.DONE)
	assert_eq(_task.drops, 0)
	assert_eq(_completed, [_task.id] as Array[int])
	assert_eq(_worked, [expected_cell] as Array[Vector2i])
	assert_true(_callbacks_valid, "WORK uses the exact live Board claim and actual station lease at a complete vertex")
	assert_eq(_worker.cell, expected_cell)
	assert_almost_eq(_worker.move_progress, 0.0)
	assert_null(_worker.task)
	assert_null(_world.board.get_task(_task.id))
	assert_eq(_station.reserved_by(expected_cell), -1)
	assert_true(_failed.is_empty())
	assert_true(_drops.is_empty())


func _advance_valid() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "", "every real tick retains independent physical invariants")
	assert_true(_world.pending_agents().is_empty())
	return problem.is_empty()


func _on_worked(agent: StaffAgent) -> bool:
	_worked.append(agent.cell)
	# Validate genuine work independently of the expected selection, so the old
	# implementation can complete naturally at the wrong cell and fail assertions.
	var valid: bool = agent == _worker and agent.task == _task \
		and _task.state == SimTask.State.CLAIMED and _task.claimed_by == agent.id \
		and _world.board.get_task(_task.id) == _task and _station.work_cells.has(agent.cell) \
		and _station.reserved_by(agent.cell) == agent.id and agent.move_progress == 0.0
	_callbacks_valid = _callbacks_valid and valid
	return valid


func _on_completed(task: SimTask) -> void:
	if task == _task:
		_completed.append(task.id)


func _on_failed(task: SimTask, reason: StringName) -> void:
	if task == _task:
		_failed.append(reason)


func _on_dropped(task: SimTask, _actor_id: int, reason: StringName) -> void:
	if task == _task:
		_drops.append(reason)
