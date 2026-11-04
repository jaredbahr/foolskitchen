extends TestCase
## A claimed worker waiting for busy B has already released A. Its body must
## clear A for its real lease owner without abandoning the waiting task.

const PREP_COUNTER: ItemDef = preload("res://data/items/prep_counter.tres")
const A_CELL: Vector2i = Vector2i(2, 2)
const B_CELL: Vector2i = Vector2i(5, 2)
const WATCHDOG: int = 512

var _world: SimWorld
var _a: PlacedItem
var _b: PlacedItem
var _waiter: StaffAgent
var _busy: StaffAgent
var _incoming: StaffAgent
var _waiter_task: SimTask
var _busy_task: SimTask
var _incoming_task: SimTask
var _completed: Array[int] = []
var _failed: Array[StringName] = []
var _drops: Array[StringName] = []
var _waiter_a_callbacks: int = 0
var _waiter_b_callbacks: int = 0
var _busy_callbacks: int = 0
var _incoming_callbacks: int = 0
var _callbacks_valid: bool = true
var _incoming_saw_busy_b: bool = false
var _incoming_saw_passive_waiter: bool = false


func before_each() -> void:
	_completed.clear()
	_failed.clear()
	_drops.clear()
	_waiter_a_callbacks = 0
	_waiter_b_callbacks = 0
	_busy_callbacks = 0
	_incoming_callbacks = 0
	_callbacks_valid = true
	_incoming_saw_busy_b = false
	_incoming_saw_passive_waiter = false
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
	]))
	_a = grid.place_def(PREP_COUNTER, Vector2i(2, 3))
	_b = grid.place_def(PREP_COUNTER, Vector2i(5, 3))
	assert_not_null(_a)
	assert_not_null(_b)
	_world = SimWorld.new(grid)
	_waiter = StaffAgent.new(&"server", 3)
	_waiter.cell = A_CELL
	_world.add_agent(_waiter)
	_busy = StaffAgent.new(&"cook", 3)
	_busy.cell = B_CELL
	_world.add_agent(_busy)
	_incoming = StaffAgent.new(&"cleaner", 3)
	_incoming.cell = Vector2i(1, 2)
	_world.add_agent(_incoming)
	_waiter_task = SimTask.new(&"station_chain", &"server", "Work at A then B")
	_waiter_task.steps.append(TaskStep.go_to_item(_a.id, "going to A"))
	_waiter_task.steps.append(TaskStep.work(1, "working at A", _on_waiter_a))
	_waiter_task.steps.append(TaskStep.go_to_item(_b.id, "waiting for B"))
	_waiter_task.steps.append(TaskStep.work(1, "working at B", _on_waiter_b))
	_busy_task = SimTask.new(&"cook", &"cook", "Work at B")
	_busy_task.steps.append(TaskStep.go_to_item(_b.id, "going to B"))
	_busy_task.steps.append(TaskStep.work(40, "working at B", _on_busy))
	_incoming_task = SimTask.new(&"station_work", &"cleaner", "Work at released A")
	_incoming_task.steps.append(TaskStep.go_to_item(_a.id, "going to released A"))
	_incoming_task.steps.append(TaskStep.work(1, "working at released A", _on_incoming))
	_world.board.task_completed.connect(_on_completed)
	_world.board.task_failed.connect(_on_failed)
	_world.board.task_dropped.connect(_on_dropped)
	_world.board.post(_waiter_task, _world.now)
	_world.board.post(_busy_task, _world.now)
	assert_true(_world.clock.start_service())


func after_each() -> void:
	_world.board.task_completed.disconnect(_on_completed)
	_world.board.task_failed.disconnect(_on_failed)
	_world.board.task_dropped.disconnect(_on_dropped)


func test_passive_claimed_station_waiter_clears_released_a_while_b_is_still_working() -> void:
	if not _establish_passive_waiter():
		return
	_world.board.post(_incoming_task, _world.now)
	var waiter_walked_while_b_busy: bool = false
	var incoming_walked: bool = false
	while _world.now < WATCHDOG and _busy_task.state == SimTask.State.CLAIMED \
			and _incoming_task.state != SimTask.State.DONE:
		var previous_work: float = _busy.work_left
		if not _advance():
			return
		assert_eq(_busy.cell, B_CELL, "productive B work keeps its physical station")
		assert_almost_eq(_busy.move_progress, 0.0)
		assert_true(_busy.work_left < previous_work, "ordinary B work progresses every tick without preemption")
		incoming_walked = incoming_walked or _incoming.move_progress > 0.0
		if _busy_task.state == SimTask.State.CLAIMED:
			waiter_walked_while_b_busy = waiter_walked_while_b_busy or _waiter.move_progress > 0.0
			assert_eq(_b.reserved_by(B_CELL), _busy.id)
			assert_eq(_waiter.task, _waiter_task, "clearance cannot abandon the passive worker's claimed job")
			assert_eq(_waiter_task.state, SimTask.State.CLAIMED)
			assert_eq(_waiter_task.claimed_by, _waiter.id)
			assert_eq(_waiter.step_index, 2)
			assert_eq(_waiter_b_callbacks, 0, "waiting is not productive B work in a pocket")
			assert_eq(_waiter_task.drops, 0)
	assert_true(waiter_walked_while_b_busy, "the passive holder physically clears A before B becomes available")
	assert_true(incoming_walked, "the real later lease owner physically walks to A")
	assert_eq(_incoming_task.state, SimTask.State.DONE, "released A must be usable while B is still busy")
	assert_eq(_incoming_callbacks, 1)
	assert_true(_incoming_saw_busy_b, "the actual A callback proves B is still claimed WORK with positive remaining work and its lease")
	assert_true(_incoming_saw_passive_waiter, "the passive worker keeps its original waiting claim and no B lease after reaching a real pocket")
	if not _finish_all():
		return
	_assert_all_finished()


func test_natural_completion_of_b_proves_the_same_station_chain_can_finish() -> void:
	if not _establish_passive_waiter():
		return
	# Withhold the incoming job until real productive B work finishes. This
	# public capacity release proves the geometry and original chain can drain.
	while _world.now < WATCHDOG and _busy_task.state != SimTask.State.DONE:
		if not _advance():
			return
	assert_eq(_busy_task.state, SimTask.State.DONE)
	assert_eq(_busy_callbacks, 1)
	assert_eq(_waiter.task, _waiter_task)
	assert_eq(_waiter_task.drops, 0)
	assert_eq(_incoming_task.id, 0, "no incoming task was posted before B's ordinary completion")
	_world.board.post(_incoming_task, _world.now)
	if not _finish_all():
		return
	_assert_all_finished()
	assert_false(_incoming_saw_busy_b, "the control deliberately makes A work follow B's natural capacity release")


func _establish_passive_waiter() -> bool:
	assert_eq(_a.work_cells, [A_CELL] as Array[Vector2i])
	assert_eq(_b.work_cells, [B_CELL] as Array[Vector2i])
	assert_true(_waiter.id < _busy.id and _busy.id < _incoming.id)
	for agent: StaffAgent in [_waiter, _busy, _incoming]:
		assert_eq(_world.movement.priority(_world, agent), 2)
	for task: SimTask in [_waiter_task, _busy_task, _incoming_task]:
		assert_eq(task.timeout_ticks, 600)
		assert_true(WATCHDOG < task.timeout_ticks)
	assert_eq(int(_waiter.priorities.get(&"cleaner", 0)), 0)
	assert_eq(int(_incoming.priorities.get(&"server", 0)), 0)
	assert_true(_world.movement.can_enter(_world, _waiter, A_CELL + Vector2i.UP), "a real upper pocket is free")
	# Tick1 claims; tick2 reaches each actual leased station; ticks3/4 finish
	# waiter WORK1; tick5 releases A and waits on the still-held B work cell.
	for tick: int in 5:
		if not _advance():
			return false
	assert_eq(_waiter_a_callbacks, 1)
	assert_eq(_waiter_b_callbacks, 0)
	assert_eq(_busy_callbacks, 0)
	assert_eq(_waiter.cell, A_CELL)
	assert_almost_eq(_waiter.move_progress, 0.0)
	assert_eq(_waiter.task, _waiter_task)
	assert_eq(_waiter_task.state, SimTask.State.CLAIMED)
	assert_eq(_waiter_task.claimed_by, _waiter.id)
	assert_eq(_waiter.step_index, 2)
	assert_false(_waiter._step_started, "the next station journey has not started")
	assert_false(_waiter._waiting_for.is_empty(), "the ordinary worker is really waiting for the busy station")
	assert_eq(_waiter._held_item_id, 0, "waiting released the previous real station lease")
	assert_eq(_waiter._held_cell, SimGrid.NO_CELL)
	assert_eq(_a.reserved_by(A_CELL), -1)
	assert_eq(_busy.task, _busy_task)
	assert_eq(_busy_task.state, SimTask.State.CLAIMED)
	assert_eq(_busy_task.claimed_by, _busy.id)
	assert_eq(_busy.step_index, 1)
	assert_true(_busy.work_left > 0.0)
	assert_eq(_b.reserved_by(B_CELL), _busy.id)
	assert_eq(_incoming_callbacks, 0)
	assert_true(_completed.is_empty())
	return true


func _finish_all() -> bool:
	while _world.now < WATCHDOG and (_waiter_task.state != SimTask.State.DONE \
			or _busy_task.state != SimTask.State.DONE or _incoming_task.state != SimTask.State.DONE):
		if not _advance():
			return false
	return true


func _assert_all_finished() -> void:
	assert_true(_world.now <= WATCHDOG)
	assert_eq(_completed.size(), 3)
	for task: SimTask in [_waiter_task, _busy_task, _incoming_task]:
		assert_eq(task.state, SimTask.State.DONE)
		assert_eq(task.drops, 0)
		assert_eq(_completed.count(task.id), 1, "each original Board task completes once without reclaim")
		assert_null(_world.board.get_task(task.id))
	assert_eq(_waiter_a_callbacks, 1)
	assert_eq(_waiter_b_callbacks, 1)
	assert_eq(_busy_callbacks, 1)
	assert_eq(_incoming_callbacks, 1)
	assert_true(_callbacks_valid, "every actual WORK callback runs under its own station lease and live Board claim")
	assert_eq(_a.reserved_by(A_CELL), -1)
	assert_eq(_b.reserved_by(B_CELL), -1)
	assert_null(_waiter.task)
	assert_null(_busy.task)
	assert_null(_incoming.task)
	assert_true(_failed.is_empty())
	assert_true(_drops.is_empty())


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "", "each ordinary tick preserves the complete physical movement oracle")
	assert_eq(_world.agents, [_waiter, _busy, _incoming] as Array[SimAgent])
	for agent: StaffAgent in [_waiter, _busy, _incoming]:
		assert_eq(_world.agent(agent.id), agent)
		assert_true(agent.movement_admitted)
	assert_true(_world.pending_agents().is_empty())
	assert_true(_drops.is_empty(), "clearance cannot cancel or reclaim any original job")
	assert_true(_failed.is_empty())
	return problem.is_empty()


func _valid_work(agent: StaffAgent, expected: StaffAgent, task: SimTask, station: PlacedItem, cell: Vector2i) -> bool:
	var valid: bool = agent == expected and agent.cell == cell and agent.move_progress == 0.0 \
		and station.reserved_by(cell) == agent.id and agent.task == task \
		and task.state == SimTask.State.CLAIMED and task.claimed_by == agent.id \
		and _world.board.get_task(task.id) == task
	_callbacks_valid = _callbacks_valid and valid
	return valid


func _on_waiter_a(agent: StaffAgent) -> bool:
	_waiter_a_callbacks += 1
	return _valid_work(agent, _waiter, _waiter_task, _a, A_CELL)


func _on_waiter_b(agent: StaffAgent) -> bool:
	_waiter_b_callbacks += 1
	return _valid_work(agent, _waiter, _waiter_task, _b, B_CELL)


func _on_busy(agent: StaffAgent) -> bool:
	_busy_callbacks += 1
	return _valid_work(agent, _busy, _busy_task, _b, B_CELL)


func _on_incoming(agent: StaffAgent) -> bool:
	_incoming_callbacks += 1
	_incoming_saw_busy_b = _busy.task == _busy_task and _busy_task.state == SimTask.State.CLAIMED \
		and _busy_task.claimed_by == _busy.id and _busy.step_index == 1 and _busy.work_left > 0.0 \
		and _busy.cell == B_CELL and _busy.move_progress == 0.0 and _b.reserved_by(B_CELL) == _busy.id
	_incoming_saw_passive_waiter = _waiter.task == _waiter_task and _waiter_task.state == SimTask.State.CLAIMED \
		and _waiter_task.claimed_by == _waiter.id and _waiter_task.drops == 0 and _waiter.step_index == 2 \
		and not _waiter._step_started and not _waiter._waiting_for.is_empty() \
		and _waiter._held_item_id == 0 and _waiter._held_cell == SimGrid.NO_CELL \
		and _waiter.cell != A_CELL and _waiter.move_progress == 0.0 and _waiter.has_arrived() \
		and _b.reserved_by(B_CELL) != _waiter.id
	return _valid_work(agent, _incoming, _incoming_task, _a, A_CELL)


func _on_completed(task: SimTask) -> void:
	_completed.append(task.id)


func _on_failed(_task: SimTask, reason: StringName) -> void:
	_failed.append(reason)


func _on_dropped(_task: SimTask, _actor_id: int, reason: StringName) -> void:
	_drops.append(reason)
