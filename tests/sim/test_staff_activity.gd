extends TestCase
## Observe real task state before advancing. This bookkeeping must never drive
## a task, evaluate its callback, or change the staff member's primary role.

var _world: SimWorld
var _activity: StaffActivity


class PredicateSpy:
	extends RefCounted
	var calls: int = 0


	func waiting(_agent: StaffAgent) -> bool:
		calls += 1
		return false


func before_each() -> void:
	_world = SimWorld.new(SimGrid.from_ascii(PackedStringArray([
		"##########", "#........#", "#........#", "#........#", "##########"])))
	_activity = StaffActivity.new()
	_activity.reset(1)
	_world.clock.open_ticks = 100
	_world.clock.last_orders_max_ticks = 10


func after_each() -> void:
	for agent: SimAgent in _world.agents.duplicate():
		_world.remove_agent(agent)


func test_idle_roles_are_measured_zero_and_absent_roles_remain_unknown() -> void:
	_add_staff(&"cook")
	_add_staff(&"server")
	assert_eq(_activity.snapshot(), {}, "no OPEN samples is unknown, not measured idle")
	assert_true(_world.clock.start_service())
	for _index: int in 4:
		_tick()
	assert_eq(_activity.snapshot(), {"day": 1, "open_ticks": 4, "roles": {
		"cook": {"busy_ticks": 0, "open_ticks": 4},
		"server": {"busy_ticks": 0, "open_ticks": 4}}})


func test_saturated_worker_counts_final_open_tick_and_excludes_last_orders() -> void:
	var cook: StaffAgent = _add_staff(&"cook")
	_post_work(&"cook", 1000)
	assert_true(_world.clock.start_service())
	for _index: int in 100:
		_tick()
	assert_eq(_world.clock.phase, SimClock.Phase.LAST_ORDERS)
	assert_not_null(cook.task)
	var closed_hours: Dictionary = _activity.snapshot()
	assert_eq(closed_hours, {"day": 1, "open_ticks": 100, "roles": {
		"cook": {"busy_ticks": 99, "open_ticks": 100}}},
		"first claim tick is idle; every existing claim including final OPEN tick is busy")
	for _index: int in 10:
		_tick()
	assert_eq(_world.clock.phase, SimClock.Phase.CLOSED)
	assert_eq(_activity.snapshot(), closed_hours, "LAST_ORDERS cannot dilute open-hours utilization")
	_tick()
	assert_eq(_activity.snapshot(), closed_hours)


func test_first_claim_idle_and_completion_tick_busy() -> void:
	var cook: StaffAgent = _add_staff(&"cook", 5)
	var task: SimTask = _post_work(&"cook", 1)
	assert_true(_world.clock.start_service())
	_tick()
	assert_eq(cook.task, task)
	assert_eq(_role("cook"), {"busy_ticks": 0, "open_ticks": 1})
	_tick()
	assert_null(cook.task)
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(_role("cook"), {"busy_ticks": 1, "open_ticks": 2},
		"a completion during world.advance still occupied its incoming interval")
	_tick()
	assert_eq(_role("cook"), {"busy_ticks": 1, "open_ticks": 3})


func test_two_people_average_without_summing_or_diluting_other_roles() -> void:
	_add_staff(&"cook")
	_add_staff(&"cook")
	_add_staff(&"server")
	_post_work(&"cook", 1000)
	assert_true(_world.clock.start_service())
	for _index: int in 4:
		_tick()
	assert_eq(_role("cook"), {"busy_ticks": 3, "open_ticks": 8},
		"both cooks contribute exposure; only the cook holding the real task contributes busy time")
	assert_eq(_role("server"), {"busy_ticks": 0, "open_ticks": 4})
	assert_eq(_activity.snapshot()["open_ticks"], 4)


func test_server_fallback_cleaning_counts_as_server_work() -> void:
	var server: StaffAgent = _add_staff(&"server")
	var task: SimTask = SimTask.new(&"clean_spot", &"cleaner", "Mop floor")
	task.steps.append(TaskStep.work(100, "Mopping"))
	_world.board.post(task, _world.now)
	assert_true(_world.clock.start_service())
	_tick()
	assert_eq(server.task, task, "use the existing server-cleaning fallback, with no cleaner hired")
	_tick()
	assert_eq(_role("server"), {"busy_ticks": 1, "open_ticks": 2})
	assert_false((_activity.snapshot()["roles"] as Dictionary).has("cleaner"))


func test_role_ratio_pools_person_exposure_when_membership_changes() -> void:
	_add_staff(&"cook")
	var second: StaffAgent = _add_staff(&"cook")
	_post_work(&"cook", 100)
	assert_true(_world.clock.start_service())
	_tick()
	_tick()
	_world.remove_agent(second)
	_tick()
	_tick()
	assert_eq(_role("cook"), {"busy_ticks": 3, "open_ticks": 6},
		"Root's role contract pools busy person-ticks over observed person-ticks")


func test_assigned_owner_is_separate_and_rest_excludes_a_held_claim() -> void:
	var owner: OwnerAgent = OwnerAgent.new(Vector2i(1, 1))
	_world.add_agent(owner)
	_post_work(&"cook", 100)
	assert_true(_world.clock.start_service())
	_tick()
	assert_eq(_activity.snapshot(), {}, "a resting owner provides no assigned open-hour exposure")
	assert_true(owner.assign_mode(&"kitchen"))
	_tick()
	assert_eq(_role("owner"), {"busy_ticks": 0, "open_ticks": 1}, "assignment is not itself busy")
	_tick()
	assert_eq(_role("owner"), {"busy_ticks": 1, "open_ticks": 2})
	assert_false((_activity.snapshot()["roles"] as Dictionary).has("cook"))
	assert_true(owner.assign_mode(&"rest"))
	assert_not_null(owner.task, "the normal owner tick, not the observer, releases disabled work")
	_activity.observe(_world)
	assert_eq(_role("owner"), {"busy_ticks": 1, "open_ticks": 2})
	assert_not_null(owner.task, "observation cannot release a claim")


func test_claimed_travel_and_wait_are_busy_without_evaluating_work() -> void:
	var cook: StaffAgent = _add_staff(&"cook")
	var spy: PredicateSpy = PredicateSpy.new()
	var task: SimTask = SimTask.new(&"cook", &"cook", "Committed job")
	task.steps.append(TaskStep.go_to_cell(Vector2i(8, 3), "Walking"))
	task.steps.append(TaskStep.wait_until(spy.waiting, "Waiting for readiness"))
	_world.board.post(task, _world.now)
	assert_true(_world.clock.start_service())
	_tick()
	_tick()
	assert_false(cook.path.is_empty(), "the real task has begun travelling")
	assert_eq(_role("cook"), {"busy_ticks": 1, "open_ticks": 2})
	# Reach WAIT using ordinary ticks; the observer must never call its predicate.
	for _index: int in 60:
		if cook.step_index == 1:
			break
		_tick()
	assert_eq(cook.step_index, 1)
	_tick()
	assert_true(spy.calls > 0, "the ordinary task has really entered its waiting step")
	var before: Dictionary = _world_state(cook)
	var previous_calls: int = spy.calls
	_activity.observe(_world)
	assert_eq(spy.calls, previous_calls)
	assert_eq(_world_state(cook), before)
	var summary: Dictionary = _activity.snapshot()
	summary["roles"]["cook"]["busy_ticks"] = 0
	assert_ne(_activity.snapshot(), summary, "getters detach nested rows")
	assert_eq(_world_state(cook), before)


func test_stale_wrong_claimant_and_terminal_tasks_are_not_busy() -> void:
	var cook: StaffAgent = _add_staff(&"cook")
	assert_true(_world.clock.start_service())
	var task: SimTask = _post_work(&"cook", 100)
	# Public task state can be stale until the next agent tick. Observe it without
	# executing a tick so the observer's validation is tested independently.
	cook.task = task
	_activity.observe(_world)
	assert_eq(_role("cook"), {"busy_ticks": 0, "open_ticks": 1})
	assert_true(_world.board.claim(task, cook.id + 1, _world.now))
	_activity.observe(_world)
	assert_eq(_role("cook"), {"busy_ticks": 0, "open_ticks": 2})
	task.claimed_by = cook.id
	_world.board.cancel(task)
	_activity.observe(_world)
	assert_eq(_role("cook"), {"busy_ticks": 0, "open_ticks": 3})
	assert_eq(cook.task, task, "observation leaves normal stale-task cleanup to the agent")


func test_reset_changes_day_and_forgets_previous_exposure() -> void:
	_add_staff(&"cook")
	_post_work(&"cook", 100)
	assert_true(_world.clock.start_service())
	_tick()
	_tick()
	var previous: Dictionary = _activity.snapshot()
	_activity.reset(2)
	assert_eq(_activity.snapshot(), {})
	_activity.observe(_world)
	assert_eq(_activity.snapshot(), {"day": 2, "open_ticks": 1, "roles": {
		"cook": {"busy_ticks": 1, "open_ticks": 1}}})
	assert_eq(previous, {"day": 1, "open_ticks": 2, "roles": {
		"cook": {"busy_ticks": 1, "open_ticks": 2}}})


func test_public_snapshot_normalizes_json_and_rejects_invalid_known_rows() -> void:
	var input: Dictionary = {"day": 3.0, "open_ticks": 10.0, "private": 8, "roles": {
		"cook": {"busy_ticks": 9.0, "open_ticks": 10.0, "private": 4},
		"unknown": {"busy_ticks": 999, "open_ticks": 1}}}
	var normalized: Dictionary = StaffActivity.public_snapshot(input)
	assert_eq(normalized, {"day": 3, "open_ticks": 10, "roles": {
		"cook": {"busy_ticks": 9, "open_ticks": 10}}})
	input["roles"]["cook"]["busy_ticks"] = 0
	assert_eq(normalized["roles"]["cook"]["busy_ticks"], 9)
	for invalid: Variant in [true, "1", -1, 0.5, NAN, INF, {}, []]:
		var broken: Dictionary = normalized.duplicate(true)
		broken["roles"]["server"] = {"busy_ticks": invalid, "open_ticks": 10}
		assert_eq(StaffActivity.public_snapshot(broken), {}, "one invalid known row invalidates the optional summary")
	for invalid: Variant in [0, -1, true, "2", 1.5, INF]:
		var broken: Dictionary = normalized.duplicate(true)
		broken["open_ticks"] = invalid
		assert_eq(StaffActivity.public_snapshot(broken), {})
	for invalid: Variant in [0, -1, true, "2", 1.5, NAN]:
		var broken: Dictionary = normalized.duplicate(true)
		broken["day"] = invalid
		assert_eq(StaffActivity.public_snapshot(broken), {})
	var excessive: Dictionary = normalized.duplicate(true)
	excessive["roles"]["cook"]["busy_ticks"] = 11
	assert_eq(StaffActivity.public_snapshot(excessive), {})
	assert_eq(StaffActivity.public_snapshot({"day": 1, "open_ticks": 1, "roles": {"stranger": {}}}), {})
	assert_eq(StaffActivity.public_snapshot(null), {})


func _add_staff(role: StringName, skill: int = 3) -> StaffAgent:
	var staff: StaffAgent = StaffAgent.new(role, skill)
	staff.cell = Vector2i(1, 1)
	_world.add_agent(staff)
	return staff


func _post_work(role: StringName, duration: int) -> SimTask:
	var task: SimTask = SimTask.new(&"cook" if role == &"cook" else &"take_order", role, "Long job")
	task.steps.append(TaskStep.work(duration))
	_world.board.post(task, _world.now)
	return task


func _tick() -> void:
	_activity.observe(_world)
	_world.advance()


func _role(role: String) -> Dictionary:
	return (_activity.snapshot().get("roles", {}) as Dictionary).get(role, {})


func _world_state(staff: StaffAgent) -> Dictionary:
	return {"now": _world.now, "clock": _world.clock.to_dict(), "events": _world.event_log.duplicate(),
		"cell": staff.cell, "path": staff.path.duplicate(), "path_index": staff.path_index,
		"move_progress": staff.move_progress, "step": staff.step_index, "work": staff.work_left,
		"task": staff.task, "task_state": staff.task.state if staff.task != null else -1,
		"claimant": staff.task.claimed_by if staff.task != null else -1,
		"claimed": _world.board.claimed_tasks().duplicate(), "open": _world.board.open_tasks().duplicate()}
