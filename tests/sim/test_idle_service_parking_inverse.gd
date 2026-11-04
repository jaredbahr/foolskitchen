extends TestCase
## Public observable inverse contracts; no
## coordinator overrides or recovery-map writes. Uses existing StaffWalker
## convention only for the direct task-null destination API controls.

const WATCHDOG: int = 512
const HOME: Vector2i = Vector2i(2, 1)
const POCKET: Vector2i = Vector2i(2, 0)
const NEW_GOAL: Vector2i = Vector2i(0, 1)
const CROSSING_GOAL: Vector2i = Vector2i(4, 1)
var _world: SimWorld
var _failed: Array[StringName] = []
var _service_callbacks: int = 0
var _server_callbacks: int = 0
var _cook_callbacks: int = 0

class StaffWalker extends StaffAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


func before_each() -> void:
	_failed.clear()
	_service_callbacks = 0
	_server_callbacks = 0
	_cook_callbacks = 0


func after_each() -> void:
	if _world != null:
		_world.board.task_failed.disconnect(_on_failed)
		for actor: SimAgent in _world.agents.duplicate():
			_world.remove_agent(actor)
	_world = null


func test_public_new_staff_goal_at_real_parking_vertex_replaces_only_old_return() -> void:
	_exercise_public_goal(false)


func test_public_new_staff_goal_mid_parking_finishes_exact_reserved_edge() -> void:
	_exercise_public_goal(true)


func _exercise_public_goal(partial: bool) -> void:
	_new_world()
	var crossing: StaffWalker = StaffWalker.new(&"cook")
	crossing.cell = Vector2i(1, 1)
	_world.add_agent(crossing)
	assert_true(crossing.set_destination(_world.grid, CROSSING_GOAL))
	var idle: StaffWalker = StaffWalker.new(&"server")
	idle.cell = HOME
	_world.add_agent(idle)
	assert_true(idle.set_destination(_world.grid, HOME))
	assert_true(_world.clock.start_service())
	var reached: bool = false
	for tick: int in WATCHDOG:
		if not _advance():
			return
		if _world.movement.is_yielding(idle.id) and (idle.move_progress > 0.0 if partial else _at(idle, POCKET)):
			reached = true
			break
	assert_true(reached, "a real outbound yield reaches the declared API intervention phase")
	if not reached:
		return
	var old_next: Vector2i = idle.next_cell()
	var old_cell: Vector2i = idle.cell
	var old_progress: float = idle.move_progress
	var claims: Dictionary = _world.movement.snapshot()
	assert_true(idle.set_destination(_world.grid, NEW_GOAL))
	assert_eq(idle.destination(), NEW_GOAL)
	assert_eq(idle.cell, old_cell)
	assert_eq(idle.move_progress, old_progress)
	if partial:
		assert_true(_world.movement.is_stopping(idle.id))
		assert_eq(idle.next_cell(), old_next)
		assert_eq(_world.movement.snapshot().edges, claims.edges, "NEW intent preserves the exact reserved partial edge")
	var finished_old_edge: bool = not partial
	for tick: int in range(_world.now, WATCHDOG):
		if not _advance():
			return
		assert_eq(idle.destination(), NEW_GOAL, "parking cleanup cannot resurrect the replaced goal")
		if not finished_old_edge:
			if idle.cell != old_cell:
				assert_eq(idle.cell, old_next)
				finished_old_edge = true
			else:
				assert_eq(idle.next_cell(), old_next)
		if _at(crossing, CROSSING_GOAL) and _at(idle, NEW_GOAL):
			break
	assert_true(finished_old_edge)
	assert_true(_at(crossing, CROSSING_GOAL))
	assert_true(_at(idle, NEW_GOAL))
	assert_false(_world.movement.is_yielding(idle.id))


func test_late_public_server_job_posted_during_real_idle_clearance_is_not_starved() -> void:
	_new_world()
	var cook: StaffAgent = StaffAgent.new(&"cook")
	cook.cell = Vector2i(1, 1)
	_world.add_agent(cook)
	var server: StaffAgent = StaffAgent.new(&"server")
	server.cell = HOME
	_world.add_agent(server)
	var service: SimTask = SimTask.new(&"service_control", &"server", "Complete existing service")
	service.steps = [TaskStep.go_to_cell(HOME), TaskStep.work(1, "finish service", _on_service)]
	_world.board.post(service, _world.now)
	assert_true(_world.clock.start_service())
	for tick: int in 32:
		if not _advance():
			return
		if service.state == SimTask.State.DONE:
			break
	assert_eq(service.state, SimTask.State.DONE)
	assert_eq(_service_callbacks, 1)
	assert_eq(service.drops, 0)
	assert_null(server.task)
	assert_eq(server.destination(), HOME)
	var incoming: SimTask = _post_crossing()
	var incoming_started: int = _world.now
	var reached_outbound: bool = false
	for tick: int in WATCHDOG:
		if not _advance():
			return
		if _world.movement.is_yielding(server.id) and server.move_progress > 0.0:
			reached_outbound = true
			break
	assert_true(reached_outbound, "post new work only during a genuine partial clearance walk")
	if not reached_outbound:
		return
	var late: SimTask = SimTask.new(&"late_service", &"server", "Do newly available service")
	late.steps = [TaskStep.go_to_cell(NEW_GOAL), TaskStep.work(1, "finish new service", _on_server)]
	assert_eq(late.timeout_ticks, 600)
	_world.board.post(late, _world.now)
	var claimed: bool = false
	for tick: int in range(_world.now, incoming_started + WATCHDOG):
		if not _advance():
			return
		claimed = claimed or server.task == late
		if incoming.state == SimTask.State.DONE and late.state == SimTask.State.DONE:
			break
	assert_true(claimed)
	assert_eq(late.state, SimTask.State.DONE)
	assert_eq(late.drops, 0)
	assert_eq(_server_callbacks, 1)
	assert_eq(incoming.state, SimTask.State.DONE)
	assert_eq(incoming.drops, 0)
	assert_eq(_cook_callbacks, 1)
	assert_true(_at(server, NEW_GOAL))
	assert_eq(server.destination(), NEW_GOAL)
	assert_false(_world.movement.is_yielding(server.id))
	assert_eq(_failed, [] as Array[StringName])


func test_resting_owner_physically_returns_to_unchanged_home_after_yield() -> void:
	_new_world()
	var cook: StaffAgent = StaffAgent.new(&"cook")
	cook.cell = Vector2i(1, 1)
	_world.add_agent(cook)
	var owner: OwnerAgent = OwnerAgent.new(HOME)
	_world.add_agent(owner)
	assert_true(owner.set_destination(_world.grid, HOME))
	assert_eq(owner.current_mode(), &"rest")
	assert_true(cook.id < owner.id, "the incoming cook wins only the ordinary stable ID tie")
	assert_eq(_world.movement.priority(_world, cook), _world.movement.priority(_world, owner))
	var incoming: SimTask = _post_crossing()
	assert_true(_world.clock.start_service())
	var saw_yield: bool = false
	var saw_outbound_motion: bool = false
	var saw_away_vertex: bool = false
	var saw_return: bool = false
	for tick: int in WATCHDOG:
		if not _advance():
			return
		var yielding: bool = _world.movement.is_yielding(owner.id)
		saw_yield = saw_yield or yielding
		saw_outbound_motion = saw_outbound_motion or (yielding and owner.cell == HOME and owner.move_progress > 0.0)
		saw_away_vertex = saw_away_vertex or (yielding and owner.cell != HOME and owner.has_arrived() and owner.move_progress == 0.0)
		saw_return = saw_return or (saw_away_vertex and owner.next_cell() == HOME and owner.move_progress > 0.0)
		assert_eq(owner.home_cell(), HOME)
		assert_eq(owner.destination(), HOME, "owner home is not retired as an idle service destination")
		assert_null(owner.task)
		if saw_return and incoming.state == SimTask.State.DONE and _at(owner, HOME) and not yielding:
			break
	assert_true(saw_yield)
	assert_true(saw_outbound_motion, "the real Owner traverses a claimed outbound edge")
	assert_true(saw_away_vertex, "the real Owner physically reaches an off-home yield vertex without pinning its cell")
	assert_true(saw_return, "the return home physically traverses its final edge")
	assert_true(_at(owner, HOME))
	assert_false(_world.movement.is_yielding(owner.id))
	assert_eq(incoming.state, SimTask.State.DONE)
	assert_eq(incoming.drops, 0)
	assert_eq(_cook_callbacks, 1)
	assert_null(owner.task)
	assert_eq(_failed, [] as Array[StringName])

func _new_world() -> void:
	_world = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["##.##", "....."])))
	_world.board.task_failed.connect(_on_failed)


func _post_crossing() -> SimTask:
	var incoming: SimTask = SimTask.new(&"crossing", &"cook", "Cross the occupied aisle")
	incoming.steps = [TaskStep.go_to_cell(CROSSING_GOAL), TaskStep.work(1, "finish crossing", _on_cook)]
	assert_eq(incoming.timeout_ticks, 600)
	_world.board.post(incoming, _world.now)
	return incoming


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "")
	assert_eq(_world.agents.size(), 2)
	assert_true(_world.pending_agents().is_empty())
	for actor: SimAgent in _world.agents:
		assert_true(actor.movement_admitted)
	return problem.is_empty()


func _at(actor: SimAgent, cell: Vector2i) -> bool:
	return actor.cell == cell and actor.has_arrived() and actor.move_progress == 0.0


func _on_service(actor: SimAgent) -> bool:
	_service_callbacks += 1
	assert_true(_at(actor, HOME))
	return _at(actor, HOME) and _owns_public_task(actor)


func _on_server(actor: SimAgent) -> bool:
	_server_callbacks += 1
	assert_true(_at(actor, NEW_GOAL))
	return _at(actor, NEW_GOAL) and _owns_public_task(actor)


func _on_cook(actor: SimAgent) -> bool:
	_cook_callbacks += 1
	assert_true(_at(actor, CROSSING_GOAL))
	return _at(actor, CROSSING_GOAL) and _owns_public_task(actor)


func _on_failed(_task: SimTask, reason: StringName) -> void:
	_failed.append(reason)


func _owns_public_task(actor: SimAgent) -> bool:
	if not actor is StaffAgent:
		return false
	var staff: StaffAgent = actor as StaffAgent
	var owned: bool = staff.task != null and staff.task.state == SimTask.State.CLAIMED \
		and staff.task.claimed_by == actor.id and _world.board.get_task(staff.task.id) == staff.task
	assert_true(owned, "callback executes under the actual exclusive public Board claim")
	return owned
