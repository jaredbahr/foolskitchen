extends TestCase
## Real role tasks isolate symmetric actor-aware replanning before priority yield.

const WATCHDOG: int = 512

var _callback_cells: Dictionary[StringName, Vector2i] = {}
var _callback_counts: Dictionary[StringName, int] = {}
var _stationary_work_active_at_crossing: bool = false


func after_each() -> void:
	_callback_cells.clear()
	_callback_counts.clear()
	_stationary_work_active_at_crossing = false


func test_equal_priority_reciprocal_role_jobs_finish_in_a_two_row_passing_space() -> void:
	_crossing(false)


func test_reversing_creation_order_keeps_both_real_role_jobs_live() -> void:
	_crossing(true)


func test_stationary_real_work_holder_is_bypassed_before_work_finishes() -> void:
	var world: SimWorld = _world()
	var incoming: StaffAgent = _worker(world, &"cook", Vector2i(1, 0))
	var standing: StaffAgent = _worker(world, &"server", Vector2i(2, 0))
	var incoming_task: SimTask = _post(world, &"cook", Vector2i(3, 0), 1)
	var standing_task: SimTask = _post(world, &"server", Vector2i(2, 0), 40)
	assert_eq(world.movement.priority(world, incoming), world.movement.priority(world, standing))
	for tick: int in WATCHDOG:
		if not _advance_checked(world):
			return
		assert_eq(standing.cell, Vector2i(2, 0), "productive stationary WORK is not pushed aside when a free bypass exists")
		if incoming_task.state == SimTask.State.DONE and standing_task.state == SimTask.State.DONE:
			break
	assert_eq(incoming_task.state, SimTask.State.DONE)
	assert_eq(standing_task.state, SimTask.State.DONE)
	assert_true(_stationary_work_active_at_crossing, "the incoming role completes via the free row while the other actual WORK40 remains active")
	assert_eq(_callback_cells.get(&"cook", SimGrid.NO_CELL), Vector2i(3, 0))
	assert_eq(_callback_cells.get(&"server", SimGrid.NO_CELL), Vector2i(2, 0))
	assert_eq(_callback_counts.get(&"cook", 0), 1)
	assert_eq(_callback_counts.get(&"server", 0), 1)
	assert_eq(incoming_task.drops, 0)
	assert_eq(standing_task.drops, 0)


func _crossing(reverse_ids: bool) -> void:
	var world: SimWorld = _world()
	var cook: StaffAgent
	var server: StaffAgent
	if reverse_ids:
		server = _worker(world, &"server", Vector2i(2, 0))
		cook = _worker(world, &"cook", Vector2i(1, 0))
	else:
		cook = _worker(world, &"cook", Vector2i(1, 0))
		server = _worker(world, &"server", Vector2i(2, 0))
	var cook_task: SimTask = _post(world, &"cook", Vector2i(3, 0), 1)
	var server_task: SimTask = _post(world, &"server", Vector2i(0, 0), 1)
	assert_eq(world.movement.priority(world, cook), world.movement.priority(world, server))
	assert_true(cook.id > server.id if reverse_ids else cook.id < server.id)
	for tick: int in WATCHDOG:
		if not _advance_checked(world):
			return
		if cook_task.state == SimTask.State.DONE and server_task.state == SimTask.State.DONE:
			break
	assert_eq(cook.cell, Vector2i(3, 0), "the cook physically reaches the actual original destination")
	assert_eq(server.cell, Vector2i(0, 0), "the server physically reaches the actual original destination")
	assert_eq(cook_task.state, SimTask.State.DONE)
	assert_eq(server_task.state, SimTask.State.DONE)
	assert_eq(_callback_cells.get(&"cook", SimGrid.NO_CELL), Vector2i(3, 0))
	assert_eq(_callback_cells.get(&"server", SimGrid.NO_CELL), Vector2i(0, 0))
	assert_eq(_callback_counts.get(&"cook", 0), 1)
	assert_eq(_callback_counts.get(&"server", 0), 1)
	assert_eq(cook_task.drops, 0, "movement must finish before the unchanged default timeout, without requeue escape")
	assert_eq(server_task.drops, 0)


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["....", "...."])))
	assert_true(world.clock.start_service())
	return world


func _worker(world: SimWorld, role: StringName, cell: Vector2i) -> StaffAgent:
	var worker: StaffAgent = StaffAgent.new(role, 3)
	worker.cell = cell
	world.add_agent(worker)
	assert_true(worker.movement_admitted)
	return worker


func _post(world: SimWorld, role: StringName, goal: Vector2i, work: int) -> SimTask:
	var task: SimTask = SimTask.new(&"crossing", role, "Real role crossing")
	assert_eq(task.timeout_ticks, 600, "the existing default task budget remains unchanged")
	task.steps.append(TaskStep.go_to_cell(goal))
	task.steps.append(TaskStep.work(work, "work at actual goal", _record_completion))
	world.board.post(task, world.now)
	return task


func _record_completion(agent: SimAgent) -> bool:
	_callback_cells[agent.role] = agent.cell
	_callback_counts[agent.role] = _callback_counts.get(agent.role, 0) + 1
	if agent.role == &"cook":
		var world: SimWorld = agent.movement_world()
		for other: SimAgent in world.agents:
			var staff: StaffAgent = other as StaffAgent
			if staff != null and staff.role == &"server" and staff.task != null \
					and staff.task.state == SimTask.State.CLAIMED \
					and staff.step_index >= 0 and staff.step_index < staff.task.steps.size() \
					and staff.task.steps[staff.step_index].kind == TaskStep.Kind.WORK \
					and staff._step_started and staff.work_left > 0.0:
				_stationary_work_active_at_crossing = true
	return true


func _advance_checked(world: SimWorld) -> bool:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	var problem: String = MovementInvariants.problem(world, before)
	assert_eq(problem, "", "every real tick preserves all people, seats, swept cells and trace geometry")
	return problem.is_empty()
