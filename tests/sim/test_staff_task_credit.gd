extends TestCase
## A real board completion credits the claimant once, never an owner or a drop.

var _world: SimWorld
var _roster: StaffRoster
var _credited: Array[bool] = []


func before_each() -> void:
	_world = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["###", "#.#", "###"])))
	_roster = StaffRoster.new()
	_credited.clear()
	_world.board.task_completed.connect(_on_task_completed)
	for member: StaffMember in _roster.members():
		var agent: StaffAgent = StaffAgent.new(member.role, member.skill)
		agent.configure_member(member, _roster.catalogue.find_trait(member.trait_id))
		_world.add_agent(agent)
	_world.add_agent(OwnerAgent.new())


func after_each() -> void:
	_world.board.task_completed.disconnect(_on_task_completed)


func test_real_board_completion_credits_only_its_rostered_claimant_once() -> void:
	var cook: StaffAgent = _staff(&"starter_cook")
	var server: StaffAgent = _staff(&"starter_server")
	var cooked: SimTask = _task(&"cook")
	_world.board.post(cooked, 0)
	_world.board.complete(cooked)
	assert_true(_credited.is_empty(), "an open task cannot finish or give XP")
	assert_true(_world.board.claim(cooked, cook.id, 0))
	_world.board.complete(cooked)
	_world.board.complete(cooked)
	assert_eq(_credited, [true] as Array[bool], "the board emits completion once")
	assert_eq(_member(&"starter_cook").growth_state().earned_today(&"cooking"), 2)
	assert_eq(_member(&"starter_server").growth_state().earned_today(&"service"), 0)
	assert_false(StaffTaskCredit.credit_completed(null, _world, _roster))

	var delivered: SimTask = _task(&"deliver")
	_world.board.post(delivered, 0)
	assert_true(_world.board.claim(delivered, server.id, 0))
	_world.board.complete(delivered)
	assert_eq(_credited, [true, true] as Array[bool])
	assert_eq(_member(&"starter_server").growth_state().earned_today(&"service"), 1)
	assert_eq(_member(&"starter_cook").growth_state().earned_today(&"service"), 0)
	assert_eq(_roster.close_growth_day(), {})
	assert_eq(_member(&"starter_cook").growth_state().progress_xp(&"cooking"), 2)
	assert_eq(_member(&"starter_server").growth_state().progress_xp(&"service"), 1)


func test_cancel_and_exhausted_drops_never_emit_completed_or_stage_xp() -> void:
	var cook: StaffAgent = _staff(&"starter_cook")
	var cancelled: SimTask = _task(&"cook")
	_world.board.post(cancelled, 0)
	assert_true(_world.board.claim(cancelled, cook.id, 0))
	_world.board.cancel(cancelled)
	_world.board.complete(cancelled)
	assert_false(StaffTaskCredit.credit_completed(cancelled, _world, _roster))
	var dropped: SimTask = _task(&"cook")
	_world.board.post(dropped, 0)
	for attempt: int in range(TaskBoard.MAX_DROPS):
		assert_true(_world.board.claim(dropped, cook.id, attempt))
		_world.board.drop(dropped, &"stuck")
	_world.board.complete(dropped)
	assert_eq(dropped.state, SimTask.State.CANCELLED)
	assert_false(StaffTaskCredit.credit_completed(dropped, _world, _roster))
	assert_true(_credited.is_empty())
	assert_eq(_member(&"starter_cook").growth_state().earned_today(&"cooking"), 0)


func test_owner_unrostered_staff_and_unknown_kind_cannot_credit_xp() -> void:
	var owner: OwnerAgent = _world.agents[2] as OwnerAgent
	var outside: StaffAgent = StaffAgent.new(&"cook", 3)
	outside.member_id = &"someone_else"
	_world.add_agent(outside)
	for agent: StaffAgent in [owner, outside]:
		var task: SimTask = _task(&"cook")
		_world.board.post(task, 0)
		assert_true(_world.board.claim(task, agent.id, 0))
		_world.board.complete(task)
	var unknown: SimTask = _task(&"not_a_task")
	_world.board.post(unknown, 0)
	assert_true(_world.board.claim(unknown, _staff(&"starter_cook").id, 0))
	_world.board.complete(unknown)
	assert_eq(_credited, [false, false, false] as Array[bool])
	assert_eq(_member(&"starter_cook").growth_state().earned_today(&"cooking"), 0)
	assert_eq(_member(&"starter_server").growth_state().earned_today(&"service"), 0)


func _on_task_completed(task: SimTask) -> void:
	_credited.append(StaffTaskCredit.credit_completed(task, _world, _roster))


func _task(kind: StringName) -> SimTask:
	return SimTask.new(kind, &"any", "Finished job")


func _staff(member_id: StringName) -> StaffAgent:
	for agent: SimAgent in _world.agents:
		if agent is StaffAgent and not agent is OwnerAgent \
				and (agent as StaffAgent).member_id == member_id:
			return agent as StaffAgent
	return null


func _member(member_id: StringName) -> StaffMember:
	for member: StaffMember in _roster.members():
		if member.id == member_id:
			return member
	return null
