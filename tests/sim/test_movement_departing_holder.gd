extends TestCase
## Public role jobs reproduce the one-tick skew before reciprocal repathing.
const WATCHDOG: int = 512
var _cells: Dictionary[StringName, Vector2i] = {}
var _calls: Dictionary[StringName, int] = {}
var _callback_physics_ok: bool = true
var _work_still_active: bool = false


func after_each() -> void:
	_cells.clear()
	_calls.clear()
	_callback_physics_ok = true
	_work_still_active = false


func test_delayed_lower_id_cook_finishes_staggered_reciprocal_jobs() -> void:
	_staggered(false)


func test_delayed_lower_id_server_finishes_mirrored_staggered_jobs() -> void:
	_staggered(true)


func test_stationary_work_is_bypassed_before_its_real_work_finishes() -> void:
	var world: SimWorld = _world(2)
	var incoming: StaffAgent = _worker(world, &"cook", Vector2i(1, 0))
	var standing: StaffAgent = _worker(world, &"server", Vector2i(2, 0))
	var a: SimTask = _post(world, &"cook", Vector2i(3, 0), 1)
	var b: SimTask = _post(world, &"server", Vector2i(2, 0), 40)
	for tick: int in WATCHDOG:
		if not _advance_checked(world):
			return
		assert_eq(standing.cell, Vector2i(2, 0), "active stationary work has no departing edge")
		if a.state == SimTask.State.DONE and b.state == SimTask.State.DONE:
			break
	_assert_completed(incoming, a, Vector2i(3, 0))
	_assert_completed(standing, b, Vector2i(2, 0))
	assert_true(_work_still_active, "the incoming worker uses the ordinary bypass while WORK40 is active")


func test_real_partial_edge_keeps_its_claims_until_physical_completion() -> void:
	var world: SimWorld = _world(3)
	var incoming: StaffAgent = _worker(world, &"cook", Vector2i(1, 0))
	var holder: StaffAgent = _worker(world, &"server", Vector2i(2, 0))
	holder.move_speed = 0.05  # Fixture slow edge lasts beyond the unchanged six-tick repath.
	var a: SimTask = _post(world, &"cook", Vector2i(3, 0), 1)
	var b: SimTask = _post(world, &"server", Vector2i(2, 2), 1)
	var observed_partial: bool = false
	for tick: int in WATCHDOG:
		var before_cell: Vector2i = holder.cell
		var before_next: Vector2i = holder.next_cell()
		var before_progress: float = holder.move_progress
		if before_progress > 0.0:
			observed_partial = true
		if not _advance_checked(world):
			return
		if before_progress > 0.0 and holder.cell == before_cell:
			assert_eq(holder.next_cell(), before_next, "a partial edge is not replaced to invent immediate vacancy")
			assert_true(holder.move_progress >= before_progress)
		if a.state == SimTask.State.DONE and b.state == SimTask.State.DONE:
			break
	assert_true(observed_partial)
	_assert_completed(incoming, a, Vector2i(3, 0))
	_assert_completed(holder, b, Vector2i(2, 2))


func _staggered(mirror: bool) -> void:
	var world: SimWorld = _world(2)
	var delayed_role: StringName = &"server" if mirror else &"cook"
	var early_role: StringName = &"cook" if mirror else &"server"
	var delayed_start: Vector2i = Vector2i(1, 0) if mirror else Vector2i(2, 0)
	var early_start: Vector2i = Vector2i(2, 0) if mirror else Vector2i(1, 0)
	var delayed_goal: Vector2i = Vector2i(3, 0) if mirror else Vector2i(0, 0)
	var early_goal: Vector2i = Vector2i(0, 0) if mirror else Vector2i(3, 0)
	var delayed: StaffAgent = _worker(world, delayed_role, delayed_start)
	var early: StaffAgent = _worker(world, early_role, early_start)
	assert_true(delayed.id < early.id)
	assert_eq(world.movement.priority(world, delayed), world.movement.priority(world, early))
	var early_task: SimTask = _post(world, early_role, early_goal, 1)
	if not _advance_checked(world):
		return
	assert_eq(early_task.state, SimTask.State.CLAIMED)
	assert_eq(early_task.claimed_by, early.id)
	assert_null(delayed.task, "no matching role job existed during the first genuine claim tick")
	assert_eq(early.cell, early_start)
	assert_eq(early.move_progress, 0.0)
	var delayed_task: SimTask = _post(world, delayed_role, delayed_goal, 1)
	# Normal Staff.tick claims and returns while the early worker first blocks.
	# No path, private blocked counter or recovery map is fabricated.
	for tick: int in WATCHDOG:
		if not _advance_checked(world):
			return
		if early_task.state == SimTask.State.DONE and delayed_task.state == SimTask.State.DONE:
			break
	_assert_completed(early, early_task, early_goal)
	_assert_completed(delayed, delayed_task, delayed_goal)


func _world(height: int) -> SimWorld:
	var rows: PackedStringArray = PackedStringArray()
	for row: int in height:
		rows.append("....")
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(rows))
	assert_true(world.clock.start_service())
	return world


func _worker(world: SimWorld, role: StringName, point: Vector2i) -> StaffAgent:
	var actor: StaffAgent = StaffAgent.new(role, 3)
	actor.cell = point
	world.add_agent(actor)
	assert_true(actor.movement_admitted)
	return actor


func _post(world: SimWorld, role: StringName, goal: Vector2i, work: int) -> SimTask:
	var task: SimTask = SimTask.new(&"departing_holder", role, "Real staggered role job")
	assert_eq(task.timeout_ticks, 600)
	task.steps.append(TaskStep.go_to_cell(goal))
	task.steps.append(TaskStep.work(work, "work at actual goal", _completed))
	world.board.post(task, world.now)
	return task


func _completed(agent: SimAgent) -> bool:
	_cells[agent.role] = agent.cell
	_calls[agent.role] = _calls.get(agent.role, 0) + 1
	_callback_physics_ok = _callback_physics_ok and agent.move_progress == 0.0 and agent.has_arrived()
	if agent.role == &"cook":
		for other: SimAgent in agent.movement_world().agents:
			var staff: StaffAgent = other as StaffAgent
			if staff != null and staff.role == &"server" and staff.task != null \
					and staff.task.state == SimTask.State.CLAIMED and staff.step_index < staff.task.steps.size() \
					and staff.task.steps[staff.step_index].kind == TaskStep.Kind.WORK and staff.work_left > 0.0:
				_work_still_active = true
	return true


func _assert_completed(actor: StaffAgent, task: SimTask, goal: Vector2i) -> void:
	assert_eq(task.state, SimTask.State.DONE, "the real job completes within512, below its unchanged600 timeout")
	assert_eq(task.drops, 0, "drop/requeue is not successful passage")
	assert_eq(actor.cell, goal)
	assert_eq(actor.move_progress, 0.0)
	assert_true(actor.has_arrived())
	assert_eq(_cells.get(actor.role, SimGrid.NO_CELL), goal)
	assert_eq(_calls.get(actor.role, 0), 1)
	assert_true(_callback_physics_ok)


func _advance_checked(world: SimWorld) -> bool:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	var problem: String = MovementInvariants.problem(world, before)
	assert_eq(problem, "", "every actual tick preserves all persons, seats, claims and timed geometry")
	return problem.is_empty()
