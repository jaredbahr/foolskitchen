extends TestCase
## Public three-body control: real completed service, a third worker's real
## journey to the first park target, then a physically completed second yield.
## No actor logic override, active reset, private write or timeout adjustment.

const WATCHDOG: int = 512
const SERVICE: Vector2i = Vector2i(2, 1)
const PARK: Vector2i = Vector2i(3, 0)
const INCOMING_GOAL: Vector2i = Vector2i(3, 1)
var _world: SimWorld
var _third: StaffAgent
var _cook: StaffAgent
var _idle: StaffAgent
var _service: SimTask
var _incoming: SimTask
var _occupation: SimTask
var _followup: SimTask
var _alternate: Vector2i = SimGrid.NO_CELL
var _service_callbacks: int = 0
var _incoming_callbacks: int = 0
var _occupation_callbacks: int = 0
var _followup_callbacks: int = 0
var _failed: Array[Dictionary] = []
var _witnesses: Array[Dictionary] = []


func after_each() -> void:
	if _world != null:
		print("IDLE_RETAINED_PARK_WITNESSES " + JSON.stringify(_witnesses))
		_world.board.task_failed.disconnect(_on_failed)
		for actor: SimAgent in _world.all_agents():
			_world.remove_agent(actor)
	_world = null
	_third = null
	_cook = null
	_idle = null
	_service = null
	_incoming = null
	_occupation = null
	_followup = null


func test_reyielded_idle_server_retires_first_park_taken_by_real_third_worker() -> void:
	# P is two cardinal edges from the server and one from the third worker.
	# The incoming route is 1,1 -> 2,1 -> 3,1; P is off that real route.
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["###..##", ".......", "###.###"]))
	_world = SimWorld.new(grid)
	_third = _add_staff(&"cleaner", Vector2i(4, 0))
	_cook = _add_staff(&"cook", Vector2i(1, 1))
	_idle = _add_staff(&"server", SERVICE)
	_world.board.task_failed.connect(_on_failed)
	assert_true(_third.id < _cook.id and _cook.id < _idle.id)
	assert_eq(_world.movement.priority(_world, _third), _world.movement.priority(_world, _idle))
	assert_eq(_world.movement.priority(_world, _cook), _world.movement.priority(_world, _idle))
	_service = _post(&"finished_service", &"server", SERVICE, 1, _service_done)
	assert_true(_world.clock.start_service())
	for tick: int in WATCHDOG:
		if not _advance():
			return
		if _service.state == SimTask.State.DONE:
			break
	assert_eq(_service.state, SimTask.State.DONE)
	assert_eq(_service_callbacks, 1)
	assert_eq(_service.drops, 0)
	assert_null(_idle.task)
	assert_true(_idle.has_arrived())
	assert_eq(_idle.destination(), SERVICE, "completed real service supplies the historical goal")
	if _service.state != SimTask.State.DONE:
		return
	_witness("completed_service")

	_incoming = _post(&"incoming_work", &"cook", INCOMING_GOAL, 4, _incoming_done)
	var deadline: int = _world.now + WATCHDOG
	var saw_first_park: bool = false
	for tick: int in range(maxi(0, deadline - _world.now)):
		if not _advance():
			return
		if _world.movement.is_yielding(_idle.id) and not _idle.has_arrived():
			saw_first_park = true
			break
	assert_true(saw_first_park, "fixture must establish a genuine first outbound yield")
	if not saw_first_park:
		return
	assert_eq(_idle.path.back(), PARK, "prove the endpoint before posting the third actor's job")
	if _idle.path.back() != PARK:
		return
	assert_eq(_idle.cell, SERVICE)
	assert_true(_idle.move_progress > 0.0)
	assert_null(_idle.task)
	assert_false(_idle.carries_food())
	assert_eq(_idle.destination(), SERVICE, "the temporary route has not fabricated a public goal")
	assert_eq(_third.cell, Vector2i(4, 0))
	assert_null(_third.task)
	_witness("first_outbound_park")
	_occupation = _post(&"third_worker_visit", &"cleaner", PARK, 4, _occupation_done)

	var saw_third_at_park: bool = false
	var saw_reyield: bool = false
	var saw_alternate_arrival: bool = false
	for tick: int in range(maxi(0, deadline - _world.now)):
		if not _advance():
			return
		if _third.cell == PARK and _third.move_progress == 0.0:
			if not saw_third_at_park:
				_witness("third_physically_at_first_park")
			saw_third_at_park = true
		if saw_third_at_park and _world.movement.is_yielding(_idle.id) \
				and not _idle.path.is_empty() and _idle.path.back() != PARK:
			if not saw_reyield:
				assert_null(_idle.task)
				assert_eq(_third.cell, PARK)
				assert_ne(_idle.cell, PARK, "the first park was never physically reached by the idle server")
				assert_false(_world.movement.snapshot()["returning"].has(_idle.id),
					"this must be a second outbound yield, not merely return travel")
				_alternate = _idle.path.back()
				_witness("second_outbound_yield")
			saw_reyield = true
		if saw_reyield and _idle.has_arrived() and _idle.move_progress == 0.0 and _idle.cell == _alternate:
			saw_alternate_arrival = true
			_witness("alternate_physically_reached")
			break
	assert_true(saw_third_at_park, "the old endpoint is occupied through a real Board journey")
	assert_true(saw_reyield, "the test must establish actual nonarrived re-yield")
	assert_true(saw_alternate_arrival, "retirement is tested only after the alternate vertex is really reached")
	if not saw_alternate_arrival:
		return
	assert_ne(_alternate, SERVICE)
	assert_ne(_alternate, PARK)
	assert_eq(_third.cell, PARK)
	assert_null(_idle.task)
	assert_false(_idle.carries_food())
	for row: Dictionary in _world.movement.snapshot()["cooperative"]:
		assert_ne(int(row["id"]), _idle.id, "no cooperative hold is being shortened at this checkpoint")

	assert_true(_world.now < deadline, "all active phases share the same512-tick bound")
	if _world.now >= deadline:
		return
	# One normal begin_tick observes the completed second pocket. This is the
	# policy assertion; the following real job is a separate liveness witness.
	if not _advance():
		return
	_witness("after_completed_pocket_observed")
	assert_false(_world.movement.is_yielding(_idle.id), "true idle staff must not retain the superseded occupied first park")
	assert_eq(_idle.cell, _alternate)
	assert_eq(_idle.move_progress, 0.0)
	assert_eq(_idle.destination(), _alternate, "retire only at the real completed alternate pocket")
	_followup = _post(&"followup_service", &"server", _alternate, 1, _followup_done)
	for tick: int in range(maxi(0, deadline - _world.now)):
		if not _advance():
			return
		if _incoming.state == SimTask.State.DONE and _occupation.state == SimTask.State.DONE \
				and _followup.state == SimTask.State.DONE:
			break
	_witness("final")
	assert_eq(_incoming.state, SimTask.State.DONE)
	assert_eq(_occupation.state, SimTask.State.DONE)
	assert_eq(_followup.state, SimTask.State.DONE, "the completed second pocket releases ordinary task claiming")
	assert_eq(_incoming_callbacks, 1)
	assert_eq(_occupation_callbacks, 1)
	assert_eq(_followup_callbacks, 1)
	assert_eq(_incoming.drops, 0)
	assert_eq(_occupation.drops, 0)
	assert_eq(_followup.drops, 0)
	assert_eq(_failed, [] as Array[Dictionary])
	assert_false(_world.movement.is_yielding(_idle.id))
	assert_eq(_idle.destination(), _idle.cell)


func _add_staff(role: StringName, start: Vector2i) -> StaffAgent:
	var actor: StaffAgent = StaffAgent.new(role)
	actor.cell = start
	_world.add_agent(actor)
	assert_eq(actor.cell, start)
	assert_true(actor.movement_admitted)
	return actor


func _post(kind: StringName, role: StringName, goal: Vector2i, work: int, done: Callable) -> SimTask:
	var task: SimTask = SimTask.new(kind, role, String(kind))
	task.steps = [TaskStep.go_to_cell(goal), TaskStep.work(work, "real controlled work", done)]
	assert_eq(task.timeout_ticks, 600)
	_world.board.post(task, _world.now)
	return task


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "", "every tick preserves bodies, claims, swept cells and continuous speed")
	assert_eq(_world.agents.size(), 3)
	assert_true(_world.pending_agents().is_empty())
	return problem.is_empty()


func _service_done(actor: SimAgent) -> bool:
	_service_callbacks += 1
	return _check_work(actor, _idle, SERVICE)


func _incoming_done(actor: SimAgent) -> bool:
	_incoming_callbacks += 1
	return _check_work(actor, _cook, INCOMING_GOAL)


func _occupation_done(actor: SimAgent) -> bool:
	_occupation_callbacks += 1
	return _check_work(actor, _third, PARK)


func _followup_done(actor: SimAgent) -> bool:
	_followup_callbacks += 1
	return _check_work(actor, _idle, _alternate)


func _check_work(actor: SimAgent, expected: StaffAgent, goal: Vector2i) -> bool:
	assert_eq(actor.id, expected.id)
	assert_eq(actor.cell, goal)
	assert_eq(actor.move_progress, 0.0, "productive callbacks require real nonpartial arrival")
	return actor.id == expected.id and actor.cell == goal and actor.move_progress == 0.0


func _on_failed(task: SimTask, reason: StringName) -> void:
	_failed.append({"id": task.id, "reason": String(reason)})


func _witness(phase: String) -> void:
	var actors: Array[Dictionary] = []
	for actor: StaffAgent in [_third, _cook, _idle]:
		var path: Array[Array] = []
		for cell: Vector2i in actor.path:
			path.append([cell.x, cell.y])
		actors.append({"id": actor.id, "cell": [actor.cell.x, actor.cell.y],
			"next": [actor.next_cell().x, actor.next_cell().y], "progress": actor.move_progress,
			"goal": [actor.destination().x, actor.destination().y], "arrived": actor.has_arrived(),
			"yielding": _world.movement.is_yielding(actor.id),
			"returning": _world.movement.snapshot()["returning"].has(actor.id),
			"path": path, "path_index": actor.path_index,
			"task_id": actor.task.id if actor.task != null else 0,
			"task_state": int(actor.task.state) if actor.task != null else -1})
	_witnesses.append({"phase": phase, "tick": _world.now, "actors": actors})
