extends TestCase
## A real idle server must not permanently own a cook's reserved station goal.
## Both cases keep production staff ticks, task leases and physical claims.

const PREP_COUNTER: ItemDef = preload("res://data/items/prep_counter.tres")
const WATCHDOG: int = 512
const STATION_CELL: Vector2i = Vector2i(2, 2)
const POCKET_CELL: Vector2i = Vector2i(2, 1)

var _world: SimWorld
var _counter: PlacedItem
var _server: StaffAgent
var _cook: StaffAgent
var _cook_task: SimTask
var _completed: Array[int] = []
var _failed: Array[StringName] = []
var _work_callbacks: int = 0
var _callback_at_station: bool = false
var _callback_owns_station: bool = false
var _callback_owns_task: bool = false
var _server_work_task: SimTask
var _server_work_callbacks: int = 0
var _server_worked_at_station: bool = false


func before_each() -> void:
	_completed.clear()
	_failed.clear()
	_work_callbacks = 0
	_callback_at_station = false
	_callback_owns_station = false
	_callback_owns_task = false
	_server_work_task = null
	_server_work_callbacks = 0
	_server_worked_at_station = false
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"######",
		"#....#",
		"#....#",
		"#....#",
		"######",
	]))
	_counter = grid.place_def(PREP_COUNTER, Vector2i(2, 3))
	assert_not_null(_counter)
	_world = SimWorld.new(grid)
	_world.board.task_completed.connect(_on_completed)
	_world.board.task_failed.connect(_on_failed)
	_server = StaffAgent.new(&"server", 3)
	_server.cell = STATION_CELL
	_world.add_agent(_server)
	_cook = StaffAgent.new(&"cook", 3)
	_cook.cell = Vector2i(1, 2)
	_world.add_agent(_cook)
	_cook_task = SimTask.new(&"cook", &"cook", "Prepare at the counter")
	_cook_task.steps.append(TaskStep.go_to_item(_counter.id, "going to the prep counter"))
	_cook_task.steps.append(TaskStep.work(4, "preparing", _on_prepared))
	assert_true(_world.clock.start_service())


func after_each() -> void:
	_world.board.task_completed.disconnect(_on_completed)
	_world.board.task_failed.disconnect(_on_failed)


func test_idle_lower_id_server_clears_the_cooks_real_reserved_station_goal() -> void:
	if not _claim_station():
		return
	var server_walked: bool = false
	for tick: int in range(_world.now, WATCHDOG):
		if not _advance():
			return
		server_walked = server_walked or _server.move_progress > 0.0
		assert_null(_server.task, "the ineligible server remains genuinely idle during automatic clearance")
		if _cook_task.state == SimTask.State.DONE:
			break
	assert_true(server_walked, "the idle blocker physically walks a claimed edge to clear the goal")
	_assert_cook_finished()
	assert_eq(_completed, [_cook_task.id] as Array[int])


func test_public_server_job_proves_the_same_station_encounter_is_physically_solvable() -> void:
	if not _claim_station():
		return
	var server_task: SimTask = SimTask.new(&"clear_counter", &"server", "Walk away from the counter")
	server_task.steps.append(TaskStep.go_to_cell(POCKET_CELL, "walking to the free pocket"))
	_world.board.post(server_task, _world.now)
	var server_walked: bool = false
	var server_claimed: bool = false
	for tick: int in range(_world.now, WATCHDOG):
		if not _advance():
			return
		server_walked = server_walked or _server.move_progress > 0.0
		server_claimed = server_claimed or _server.task == server_task
		if _cook_task.state == SimTask.State.DONE and server_task.state == SimTask.State.DONE:
			break
	assert_true(server_claimed, "the ordinary server tick claims its eligible public Board job")
	assert_true(server_walked, "the blocker moves continuously instead of being hidden or repositioned")
	assert_eq(server_task.state, SimTask.State.DONE)
	assert_eq(server_task.claimed_by, _server.id)
	assert_eq(server_task.drops, 0)
	assert_eq(_server.cell, POCKET_CELL)
	assert_almost_eq(_server.move_progress, 0.0)
	assert_null(_server.task)
	_assert_cook_finished()
	assert_eq(_completed, [server_task.id, _cook_task.id] as Array[int], "each public job completes exactly once")


func test_active_lower_id_server_finishes_its_real_work_before_idle_station_clearance() -> void:
	assert_eq(_counter.work_cells, [STATION_CELL] as Array[Vector2i])
	assert_true(_world.movement.can_enter(_world, _server, POCKET_CELL))
	assert_eq(int(_server.priorities.get(&"cook", 0)), 0)
	_server_work_task = SimTask.new(&"station_work", &"server", "Work at the counter")
	_server_work_task.steps.append(TaskStep.go_to_cell(STATION_CELL, "going to the counter"))
	_server_work_task.steps.append(TaskStep.work(40, "working at the counter", _on_server_worked))
	_world.board.post(_server_work_task, _world.now)
	# Claim, arrive through GO_TO_CELL, then perform the first real WORK tick.
	for tick: int in 3:
		if not _advance():
			return
	assert_eq(_server.task, _server_work_task)
	assert_eq(_server_work_task.state, SimTask.State.CLAIMED)
	assert_eq(_server_work_task.claimed_by, _server.id)
	assert_eq(_server.step_index, 1)
	assert_true(_server.work_left > 0.0 and _server.work_left < 40.0)
	assert_eq(_world.movement.priority(_world, _server), 2)
	assert_eq(_world.movement.priority(_world, _cook), 2)
	assert_true(_server.id < _cook.id)
	assert_eq(_server_work_task.timeout_ticks, 600)
	assert_eq(_cook_task.timeout_ticks, 600)
	assert_true(WATCHDOG < _server_work_task.timeout_ticks and WATCHDOG < _cook_task.timeout_ticks)
	_world.board.post(_cook_task, _world.now)
	var cook_claimed_station: bool = false
	var server_walked_after_work: bool = false
	for tick: int in range(_world.now, WATCHDOG):
		var server_was_working: bool = _server_work_task.state == SimTask.State.CLAIMED
		var previous_work: float = _server.work_left
		if not _advance():
			return
		if server_was_working:
			assert_eq(_server.cell, STATION_CELL, "an active lower-ID holder keeps its productive station")
			assert_almost_eq(_server.move_progress, 0.0)
			assert_true(_server.work_left < previous_work, "ordinary server WORK progresses on every tick")
		if _server_work_task.state == SimTask.State.CLAIMED:
			assert_false(_world.movement.is_yielding(_server.id), "the cook's destination cannot preempt active server work")
			assert_eq(_server.task, _server_work_task)
			assert_eq(_work_callbacks, 0, "the cook cannot work through the active holder")
			if _cook.task == _cook_task and _counter.reserved_by(STATION_CELL) == _cook.id:
				cook_claimed_station = true
		else:
			server_walked_after_work = server_walked_after_work or _server.move_progress > 0.0
		if _cook_task.state == SimTask.State.DONE:
			break
	assert_true(cook_claimed_station, "the incoming cook owns a real claim and station lease while the server is working")
	assert_eq(_server_work_callbacks, 1)
	assert_true(_server_worked_at_station, "the active server completes at its actual station under its own Board claim")
	assert_eq(_server_work_task.state, SimTask.State.DONE)
	assert_eq(_server_work_task.drops, 0)
	assert_null(_server.task)
	assert_true(server_walked_after_work, "automatic clearance starts only after the holder becomes idle")
	_assert_cook_finished()
	assert_eq(_completed, [_server_work_task.id, _cook_task.id] as Array[int])


func _claim_station() -> bool:
	assert_eq(_counter.work_cells, [STATION_CELL] as Array[Vector2i], "the real authored counter has exactly one work cell")
	assert_eq(int(_server.priorities.get(&"cook", 0)), 0, "opposite roles prevent the blocker claiming the cook job")
	assert_true(_server.id < _cook.id, "the idle actor wins the ordinary lower-ID tie")
	assert_eq(_world.movement.priority(_world, _server), 2)
	assert_eq(_world.movement.priority(_world, _cook), 2)
	assert_eq(_cook_task.timeout_ticks, 600, "keep the production task timeout")
	assert_true(WATCHDOG < _cook_task.timeout_ticks, "timeout cannot provide the test's escape")
	assert_true(_world.grid.is_walkable(POCKET_CELL))
	assert_true(_world.grid.step_open(STATION_CELL, POCKET_CELL))
	assert_true(_world.movement.can_enter(_world, _server, POCKET_CELL), "a genuine legal yielding pocket is free")
	_world.board.post(_cook_task, _world.now)
	# First tick claims work; second tick acquires the actual item lease and
	# attempts the occupied destination using the normal StaffAgent methods.
	for tick: int in 2:
		if not _advance():
			return false
	assert_null(_server.task)
	assert_eq(_server.cell, STATION_CELL)
	assert_eq(_cook.task, _cook_task)
	assert_eq(_cook_task.state, SimTask.State.CLAIMED)
	assert_eq(_cook_task.claimed_by, _cook.id)
	assert_eq(_counter.reserved_by(STATION_CELL), _cook.id)
	assert_eq(_cook.destination(), STATION_CELL)
	assert_eq(_cook.next_cell(), STATION_CELL)
	assert_eq(_cook.step_index, 0, "productive work has not started away from the station")
	assert_eq(_work_callbacks, 0)
	return true


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "", "every tick preserves bodies, edges, traces and claims")
	assert_eq(_world.agents.size(), 2, "neither actor may disappear to clear the station")
	assert_eq(_world.agent(_server.id), _server)
	assert_eq(_world.agent(_cook.id), _cook)
	assert_true(_server.movement_admitted and _cook.movement_admitted)
	assert_true(_world.pending_agents().is_empty(), "active staff cannot be hidden in pending admission")
	return problem.is_empty()


func _assert_cook_finished() -> void:
	assert_true(_world.now <= WATCHDOG)
	assert_eq(_work_callbacks, 1, "the actual WORK callback runs exactly once before the watchdog")
	assert_true(_callback_at_station, "WORK finishes only at the actual prep-counter cell")
	assert_true(_callback_owns_station, "WORK finishes while the cook still holds its station lease")
	assert_true(_callback_owns_task, "WORK finishes through its actual exclusive Board claim")
	assert_eq(_cook_task.state, SimTask.State.DONE, "the original task finishes before any timeout escape")
	assert_eq(_cook_task.drops, 0, "dropping and reclaiming is not productive clearance")
	assert_null(_world.board.get_task(_cook_task.id))
	assert_null(_cook.task)
	assert_eq(_cook.cell, STATION_CELL)
	assert_almost_eq(_cook.move_progress, 0.0)
	assert_eq(_counter.reserved_by(STATION_CELL), -1, "normal completion releases the actual station lease")
	assert_eq(_failed, [] as Array[StringName])
	assert_eq(_world.agent(_server.id), _server, "the idle blocker stays active after completion")
	assert_eq(_world.agent(_cook.id), _cook)


func _on_prepared(agent: StaffAgent) -> bool:
	_work_callbacks += 1
	_callback_at_station = agent == _cook and agent.cell == STATION_CELL and agent.move_progress == 0.0
	_callback_owns_station = _counter.reserved_by(STATION_CELL) == agent.id
	_callback_owns_task = agent.task == _cook_task and _cook_task.state == SimTask.State.CLAIMED \
		and _cook_task.claimed_by == agent.id and _world.board.get_task(_cook_task.id) == _cook_task
	return _callback_at_station and _callback_owns_station and _callback_owns_task


func _on_completed(task: SimTask) -> void:
	_completed.append(task.id)


func _on_server_worked(agent: StaffAgent) -> bool:
	_server_work_callbacks += 1
	_server_worked_at_station = agent == _server and agent.cell == STATION_CELL and agent.move_progress == 0.0 \
		and agent.task == _server_work_task and _server_work_task.state == SimTask.State.CLAIMED \
		and _server_work_task.claimed_by == agent.id and _world.board.get_task(_server_work_task.id) == _server_work_task
	return _server_worked_at_station


func _on_failed(_task: SimTask, reason: StringName) -> void:
	_failed.append(reason)
