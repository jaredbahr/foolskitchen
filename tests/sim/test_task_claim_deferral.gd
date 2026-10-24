extends TestCase
## Actual-world claim selection: no replacement scheduler or mocked scores.

var _world: SimWorld
var _near: PlacedItem
var _far: PlacedItem
var _failure_reasons: Array[StringName] = []


func before_each() -> void:
	_world = SimWorld.new(SimGrid.new(Vector2i(20, 8)))
	_near = _world.grid.place(Vector2i.ONE, Vector2i(2, 1), 0, true,
		[Vector2i(0, 1)] as Array[Vector2i])
	_far = _world.grid.place(Vector2i.ONE, Vector2i(16, 1), 0, true,
		[Vector2i(0, 1)] as Array[Vector2i])
	assert_not_null(_near)
	assert_not_null(_far)
	_failure_reasons.clear()
	_world.board.task_failed.connect(_on_failed)


func after_each() -> void:
	_world = null
	_near = null
	_far = null


func test_opted_in_near_work_defers_to_distant_higher_same_role_work() -> void:
	var server: StaffAgent = _server()
	var washing: SimTask = _post(_near, &"server", 0, true)
	var bussing: SimTask = _post(_far, &"server", 1)
	assert_true(server._score(_world, washing) > server._score(_world, bussing))
	assert_true(server._score(_world, bussing) > 0.0)
	_world.advance()
	assert_eq(server.task, bussing, "higher service work wins despite the sink's distance advantage")
	assert_eq(washing.state, SimTask.State.OPEN)
	assert_eq(washing.drops, 0)
	assert_eq(washing.claimed_tick, -1)


func test_default_false_keeps_the_original_distance_winner() -> void:
	var server: StaffAgent = _server()
	var nearby: SimTask = _post(_near, &"server", 0)
	var distant: SimTask = _post(_far, &"server", 1)
	assert_false(nearby.defer_to_higher_priority)
	assert_false(distant.defer_to_higher_priority)
	assert_true(server._score(_world, nearby) > server._score(_world, distant))
	_world.advance()
	assert_eq(server.task, nearby)
	assert_eq(distant.state, SimTask.State.OPEN)


func test_equal_priority_keeps_distance_and_original_id_ties() -> void:
	var server: StaffAgent = _server()
	var first: SimTask = _post(_near, &"server", 0, true)
	var tied: SimTask = _post(_near, &"server", 0)
	var distant: SimTask = _post(_far, &"server", 0)
	assert_almost_eq(server._score(_world, first), server._score(_world, tied))
	assert_true(server._score(_world, first) > server._score(_world, distant))
	_world.advance()
	assert_eq(server.task, first, "strict score comparison keeps the first posted equal score")
	assert_eq(tied.state, SimTask.State.OPEN)
	assert_eq(distant.state, SimTask.State.OPEN)


func test_different_role_does_not_defer_an_actor_eligible_for_both() -> void:
	var server: StaffAgent = _server()
	server.priorities[&"cook"] = 2
	server.skills[&"cook"] = 3
	var washing: SimTask = _post(_near, &"server", 0, true)
	var cooking: SimTask = _post(_far, &"cook", 3)
	assert_true(server._score(_world, cooking) > 0.0, "the actor really can claim both roles")
	assert_true(server._score(_world, washing) > server._score(_world, cooking))
	_world.advance()
	assert_eq(server.task, washing, "a different task role uses the unchanged score")
	assert_eq(cooking.state, SimTask.State.OPEN)


func test_any_role_is_a_distinct_deferral_group() -> void:
	var server: StaffAgent = _server()
	var washing: SimTask = _post(_near, &"server", 0, true)
	var role_free: SimTask = _post(_far, &"any", 3)
	assert_true(server._score(_world, role_free) > 0.0)
	assert_true(server._score(_world, washing) > server._score(_world, role_free))
	_world.advance()
	assert_eq(server.task, washing)
	assert_eq(role_free.state, SimTask.State.OPEN)


func test_missing_target_does_not_block_a_positive_score_claim() -> void:
	var server: StaffAgent = _server()
	var washing: SimTask = _post(_near, &"server", 0, true)
	var missing: SimTask = SimTask.new(&"test_missing", &"server", "Use a removed station")
	missing.priority = 3
	missing.steps.append(TaskStep.go_to_item(99999))
	_world.board.post(missing, _world.now)
	assert_eq(missing.state, SimTask.State.OPEN)
	assert_almost_eq(server._score(_world, missing), 0.0)
	# Directly tick the actual actor before the world's missing-target backstop,
	# so the OPEN zero-score competitor reaches the real claim selector.
	server.tick(_world)
	assert_eq(server.task, washing)
	assert_eq(missing.state, SimTask.State.OPEN)
	_world.advance()
	assert_eq(missing.state, SimTask.State.CANCELLED)
	assert_eq(_failure_reasons, [&"target_gone"] as Array[StringName])


func test_disabled_role_leaves_both_candidates_unclaimed() -> void:
	var server: StaffAgent = _server()
	server.priorities[&"server"] = 0
	var washing: SimTask = _post(_near, &"server", 0, true)
	var bussing: SimTask = _post(_far, &"server", 1)
	_world.advance()
	assert_null(server.task)
	assert_eq(washing.state, SimTask.State.OPEN)
	assert_eq(bussing.state, SimTask.State.OPEN)
	assert_eq(_world.board.active_count(), 2)


func test_owner_can_serve_and_defers_by_task_role() -> void:
	var owner: OwnerAgent = OwnerAgent.new(Vector2i(2, 2))
	assert_true(owner.assign_mode(&"floor"))
	_world.add_agent(owner)
	var washing: SimTask = _post(_near, &"server", 0, true)
	var bussing: SimTask = _post(_far, &"server", 1)
	assert_eq(owner.role, &"owner")
	assert_true(owner._score(_world, bussing) > 0.0)
	assert_true(owner._score(_world, washing) > owner._score(_world, bussing))
	_world.advance()
	assert_eq(owner.task, bussing, "owner role is not mistaken for task eligibility")
	assert_eq(washing.state, SimTask.State.OPEN)


func test_second_worker_can_wash_after_higher_work_is_claimed_in_the_same_tick() -> void:
	var first: StaffAgent = _server()
	var second: StaffAgent = _server()
	var washing: SimTask = _post(_near, &"server", 0, true)
	var bussing: SimTask = _post(_far, &"server", 1)
	_world.advance()
	assert_eq(first.task, bussing)
	assert_eq(second.task, washing, "the tick's cached competitor is now CLAIMED")
	assert_eq(bussing.claimed_by, first.id)
	assert_eq(washing.claimed_by, second.id)
	assert_eq(bussing.claimed_tick, _world.now)
	assert_eq(washing.claimed_tick, _world.now)
	assert_eq(bussing.drops, 0)
	assert_eq(washing.drops, 0)


func test_claimed_washing_is_not_preempted_or_retimed() -> void:
	var server: StaffAgent = _server()
	var washing: SimTask = _post(_near, &"server", 0, true)
	_world.advance()
	_world.advance()
	assert_eq(server.task, washing)
	assert_eq(server.step_index, 1)
	var claimed_at: int = washing.claimed_tick
	var timeout: int = washing.timeout_ticks
	var bussing: SimTask = _post(_far, &"server", 1)
	_world.advance()
	assert_eq(server.task, washing)
	assert_eq(washing.state, SimTask.State.CLAIMED)
	assert_eq(washing.claimed_tick, claimed_at)
	assert_eq(washing.timeout_ticks, timeout)
	assert_eq(washing.drops, 0)
	assert_eq(server.step_index, 1)
	assert_true(server.work_left > 0.0 and server.work_left < 30.0)
	assert_eq(bussing.state, SimTask.State.OPEN)


func test_unreachable_present_higher_work_exhausts_normal_drops_then_washing_progresses() -> void:
	var server: StaffAgent = _server()
	var washing: SimTask = _post(_near, &"server", 0, true)
	var blocked: SimTask = SimTask.new(&"test_blocked", &"server", "Use blocked work cell")
	blocked.priority = 1
	blocked.steps.append(TaskStep.go_to_work_cell(_far.id, 0))
	_world.grid.set_terrain(_far.work_cells[0], SimGrid.Terrain.WALL)
	_world.board.post(blocked, _world.now)
	assert_not_null(_world.grid.item(_far.id), "the higher task has a real existing target")
	assert_true(server._score(_world, blocked) > 0.0)
	for attempt: int in range(TaskBoard.MAX_DROPS):
		_world.advance()
		assert_eq(server.task, blocked)
		assert_eq(blocked.state, SimTask.State.CLAIMED)
		assert_eq(washing.state, SimTask.State.OPEN)
		_world.advance()
		assert_null(server.task)
		assert_eq(blocked.drops, attempt + 1)
		assert_eq(washing.drops, 0)
	assert_eq(blocked.state, SimTask.State.CANCELLED)
	assert_eq(_failure_reasons, [&"dropped_too_often"] as Array[StringName])
	_world.advance()
	assert_eq(server.task, washing, "ordinary self-healing eventually releases the deferred work")
	for tick: int in range(60):
		_world.advance()
		if washing.state == SimTask.State.DONE:
			break
	assert_eq(washing.state, SimTask.State.DONE)
	assert_eq(washing.drops, 0)
	assert_eq(server.cell, _near.work_cells[0])
	assert_eq(_near.reserved_by(_near.work_cells[0]), -1)
	assert_eq(_world.board.active_count(), 0)


func _server() -> StaffAgent:
	var server: StaffAgent = StaffAgent.new(&"server", 3)
	server.cell = Vector2i(2, 2)
	_world.add_agent(server)
	return server


func _post(item: PlacedItem, task_role: StringName, priority: int, defer_claim: bool = false) -> SimTask:
	var task: SimTask = SimTask.new(&"test_claim", task_role, "Use station")
	task.priority = priority
	if defer_claim:
		task.defer_to_higher_priority = true
	task.steps.append(TaskStep.go_to_item(item.id))
	task.steps.append(TaskStep.work(30))
	_world.board.post(task, _world.now)
	return task


func _on_failed(_task: SimTask, reason: StringName) -> void:
	_failure_reasons.append(reason)
