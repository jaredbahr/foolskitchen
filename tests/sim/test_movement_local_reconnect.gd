extends TestCase
## A distant two-body cut cannot prevent safe local progress around an idle
## intermediate cook. Public real jobs create all claims and productive work.

const WATCHDOG: int = 512
const START: Vector2i = Vector2i(5, 2)
const IDLE: Vector2i = Vector2i(4, 2)
const RECONNECT: Vector2i = Vector2i(3, 2)
const GOAL: Vector2i = Vector2i(0, 2)
var _world: SimWorld
var _idle: StaffAgent
var _incoming: StaffAgent
var _upper: StaffAgent
var _lower: StaffAgent
var _service: SimTask
var _incoming_job: SimTask
var _upper_job: SimTask
var _lower_job: SimTask
var _service_callbacks: int = 0
var _incoming_callbacks: int = 0
var _upper_callbacks: int = 0
var _lower_callbacks: int = 0
var _failed: Array[Dictionary] = []
var _witnesses: Array[Dictionary] = []


func after_each() -> void:
	print("LOCAL_RECONNECT_WITNESSES " + JSON.stringify(_witnesses))
	if _world != null:
		_world.board.task_failed.disconnect(_on_failed)
		for actor: SimAgent in _world.all_agents():
			_world.remove_agent(actor)
	_world = null
	_idle = null
	_incoming = null
	_upper = null
	_lower = null
	_service = null
	_incoming_job = null
	_upper_job = null
	_lower_job = null


func test_local_bypass_progresses_before_distant_two_person_cut_releases() -> void:
	# The north dead end is the ordinary first yield pocket. Returning from it
	# restores the static route through the cook. The south row legally bypasses
	# that cook, but the two real workers at x1 cut every complete avoid route.
	_world = SimWorld.new(SimGrid.from_ascii(PackedStringArray([
		"##########", "#####.####", "..........", ".........."])))
	_idle = _add(&"cook", IDLE)
	_incoming = _add(&"server", START)
	_upper = _add(&"cleaner", Vector2i(1, 2))
	_lower = _add(&"cleaner", Vector2i(1, 3))
	_world.board.task_failed.connect(_on_failed)
	assert_true(_idle.id < _incoming.id)
	assert_eq(_world.movement.priority(_world, _idle), _world.movement.priority(_world, _incoming))
	_service = _post(&"completed_cook_service", &"cook", IDLE, 1, _service_done)
	assert_true(_world.clock.start_service())
	for tick: int in 64:
		if not _advance():
			return
		if _service.state == SimTask.State.DONE:
			break
	assert_eq(_service.state, SimTask.State.DONE)
	assert_eq(_service_callbacks, 1)
	assert_eq(_service.drops, 0)
	assert_null(_idle.task)
	assert_true(_idle.has_arrived())
	assert_eq(_idle.destination(), IDLE)
	if _service.state != SimTask.State.DONE:
		return

	_upper_job = _post(&"upper_cut_work", &"cleaner", _upper.cell, 200, _upper_done)
	_lower_job = _post(&"lower_cut_work", &"cleaner", _lower.cell, 200, _lower_done)
	_incoming_job = _post(&"beyond_cut_work", &"server", GOAL, 1, _incoming_done)
	var deadline: int = _world.now + WATCHDOG
	var established: bool = false
	for tick: int in 32:
		if not _advance():
			return
		if _incoming.task == _incoming_job and _incoming.next_cell() == IDLE \
				and _incoming.move_progress == 0.0 and _working(_upper, _upper_job) and _working(_lower, _lower_job):
			established = true
			break
	assert_true(established, "the real blocked GO and both real stationary WORK claims must precede the policy assertion")
	if not established:
		return
	assert_eq(_incoming.cell, START)
	assert_eq(_incoming.destination(), GOAL)
	assert_true(_world.movement.route(_world, _incoming, START, GOAL, true).is_empty(),
		"the complete avoid-all-people route is genuinely cut downstream")
	var local: Array[Vector2i] = _world.movement.route(_world, _incoming, START, RECONNECT, true)
	assert_true(local.size() > 1, "a legal all-claims-avoiding local reconnection really exists")
	assert_false(local.has(IDLE))
	assert_false(local.has(_upper.cell))
	assert_false(local.has(_lower.cell))
	assert_eq(_upper.cell, Vector2i(1, 2))
	assert_eq(_lower.cell, Vector2i(1, 3))
	_witness("global_cut_and_local_bypass")

	var crossed_while_cut_work_active: bool = false
	for tick: int in range(maxi(0, deadline - _world.now)):
		if not _advance():
			return
		assert_eq(_idle.cell, IDLE, "local replanning preserves the lower-ID idle cook's right of way")
		assert_null(_idle.task)
		assert_eq(_incoming.destination(), GOAL, "a local splice cannot replace the productive goal with its waypoint")
		if not crossed_while_cut_work_active and _incoming.cell.x < IDLE.x \
				and _working(_upper, _upper_job) and _working(_lower, _lower_job) \
				and _upper.cell == Vector2i(1, 2) and _lower.cell == Vector2i(1, 3):
			crossed_while_cut_work_active = true
			assert_eq(_upper_callbacks, 0)
			assert_eq(_lower_callbacks, 0)
			assert_eq(_incoming_callbacks, 0, "passing the local waypoint is never productive arrival")
			_witness("passed_idle_before_distant_release")
		if _incoming_job.state == SimTask.State.DONE and _upper_job.state == SimTask.State.DONE \
				and _lower_job.state == SimTask.State.DONE:
			break
	_witness("final")
	assert_true(crossed_while_cut_work_active, "a distant two-person cut must not postpone legal upstream progress until its real WORK finishes")
	assert_eq(_incoming_job.state, SimTask.State.DONE)
	assert_eq(_upper_job.state, SimTask.State.DONE)
	assert_eq(_lower_job.state, SimTask.State.DONE)
	assert_eq(_incoming_callbacks, 1)
	assert_eq(_upper_callbacks, 1)
	assert_eq(_lower_callbacks, 1)
	assert_eq(_incoming.cell, GOAL)
	assert_eq(_incoming.move_progress, 0.0)
	assert_eq(_incoming_job.drops, 0)
	assert_eq(_upper_job.drops, 0)
	assert_eq(_lower_job.drops, 0)
	assert_eq(_failed, [] as Array[Dictionary])


func _add(role: StringName, start: Vector2i) -> StaffAgent:
	var actor: StaffAgent = StaffAgent.new(role, 3)
	actor.cell = start
	_world.add_agent(actor)
	assert_true(actor.movement_admitted)
	assert_eq(actor.cell, start)
	return actor


func _post(kind: StringName, role: StringName, goal: Vector2i, work: int, done: Callable) -> SimTask:
	var task: SimTask = SimTask.new(kind, role, String(kind))
	assert_eq(task.timeout_ticks, 600)
	task.steps = [TaskStep.go_to_cell(goal), TaskStep.work(work, "real controlled work", done)]
	_world.board.post(task, _world.now)
	return task


func _working(actor: StaffAgent, job: SimTask) -> bool:
	return job.state == SimTask.State.CLAIMED and job.claimed_by == actor.id and actor.task == job \
		and actor.step_index == 1 and actor._step_started and actor.work_left > 0.0


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "", "every real tick retains body, seat, edge, swept-cell and continuous-speed invariants")
	assert_eq(_world.agents.size(), 4)
	assert_true(_world.pending_agents().is_empty())
	return problem.is_empty()


func _check(actor: SimAgent, expected: StaffAgent, goal: Vector2i) -> bool:
	assert_eq(actor.id, expected.id)
	assert_eq(actor.cell, goal)
	assert_eq(actor.move_progress, 0.0)
	assert_true(actor.has_arrived())
	return actor.id == expected.id and actor.cell == goal and actor.move_progress == 0.0 and actor.has_arrived()


func _service_done(actor: SimAgent) -> bool:
	_service_callbacks += 1
	return _check(actor, _idle, IDLE)


func _incoming_done(actor: SimAgent) -> bool:
	_incoming_callbacks += 1
	return _check(actor, _incoming, GOAL)


func _upper_done(actor: SimAgent) -> bool:
	_upper_callbacks += 1
	return _check(actor, _upper, Vector2i(1, 2))


func _lower_done(actor: SimAgent) -> bool:
	_lower_callbacks += 1
	return _check(actor, _lower, Vector2i(1, 3))


func _on_failed(task: SimTask, reason: StringName) -> void:
	_failed.append({"id": task.id, "reason": String(reason)})


func _witness(phase: String) -> void:
	var actors: Array[Dictionary] = []
	for actor: StaffAgent in [_idle, _incoming, _upper, _lower]:
		actors.append({"id": actor.id, "cell": [actor.cell.x, actor.cell.y],
			"next": [actor.next_cell().x, actor.next_cell().y], "progress": actor.move_progress,
			"goal": [actor.destination().x, actor.destination().y], "yielding": _world.movement.is_yielding(actor.id),
			"task_id": actor.task.id if actor.task != null else 0})
	_witnesses.append({"phase": phase, "tick": _world.now, "actors": actors})
