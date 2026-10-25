extends TestCase
## Preparation returns installable copies; live books and progress stay untouched.

const TUNING: ProgressionTuning = preload("res://data/balance/progression.tres")
const MAX_CASH: int = 9223372036854775807
const MIN_CASH: int = -MAX_CASH - 1


func test_one_batch_crosses_a_level_without_recursive_completion_or_input_mutation() -> void:
	var tracker: MilestoneTracker = _tracker(3, 9, 1)
	var owner: OwnerProgress = _owner(94, 3)
	assert_eq(owner.award_day(4, 0, 10)["total_xp"], 1, "ordinary day XP is awarded first")
	var daily: Milestone = _goal(&"daily", Milestone.Condition.SERVED_TODAY, 1.0, 1, 15)
	var level_goal: Milestone = _goal(&"later_level", Milestone.Condition.OWNER_LEVEL, 2.0, 50, 100)
	var catalogue: MilestoneSet = _catalogue([daily, level_goal] as Array[Milestone])
	var observation: MilestoneDay = _day(4, 1, owner.level)
	var before_tracker: Dictionary = tracker.to_dict()
	var before_owner: Dictionary = owner.to_dict()
	var before_day: Dictionary = _day_snapshot(observation)
	var before_goal: Dictionary = _goal_snapshot(daily)
	var before_level_base: int = TUNING.level_base
	var result: MilestoneSettlement = MilestoneSettlement.prepare(tracker, catalogue, observation, owner, -10)
	assert_not_null(result)
	if result == null:
		return
	assert_eq(_ids(result.reached), [&"daily"] as Array[StringName])
	assert_eq(result.cash_reward, 15)
	assert_eq(result.xp_reward, 1)
	assert_eq(result.owner_progress.total_xp, 96)
	assert_eq(result.owner_progress.level, 2)
	assert_eq(result.owner_progress.last_awarded_day, 4)
	assert_eq(result.owner_xp_result["bonus_xp"], 1)
	assert_eq(result.owner_xp_result["levels_gained"], [2] as Array[int])
	assert_eq(result.tracker.last_evaluated_day, 4)
	assert_eq(result.tracker.total_served, 10)
	assert_eq(result.tracker.clean_streak, 2)
	assert_false(result.tracker.is_completed(&"later_level"), "bonus XP cannot recursively meet another goal")
	assert_ne(result.tracker, tracker)
	assert_ne(result.owner_progress, owner)
	assert_ne(result.owner_progress.tuning, owner.tuning)
	assert_ne(result.reached[0], daily)
	assert_eq(_goal_snapshot(result.reached[0]), before_goal)
	# Returned copies may be changed by their owner without altering any input.
	result.tracker.total_served += 1
	result.owner_progress.award_bonus(1)
	result.owner_progress.tuning.level_base += 1
	result.reached[0].reward_cash += 1
	assert_eq(tracker.to_dict(), before_tracker)
	assert_eq(owner.to_dict(), before_owner)
	assert_eq(owner.tuning.level_base, before_level_base)
	assert_eq(TUNING.level_base, before_level_base)
	assert_eq(_day_snapshot(observation), before_day)
	assert_eq(_goal_snapshot(daily), before_goal)


func test_valid_empty_batch_advances_staged_counters_and_allows_zero_xp_at_cap() -> void:
	var tracker: MilestoneTracker = _tracker(3, 7, 2)
	var owner: OwnerProgress = _owner(OwnerProgress.MAX_TOTAL_XP, 4)
	var observation: MilestoneDay = _day(4, 1, owner.level)
	var catalogue: MilestoneSet = _catalogue([
		_goal(&"not_yet", Milestone.Condition.SERVED_TODAY, 100.0, 1, 1),
	] as Array[Milestone])
	var before_tracker: Dictionary = tracker.to_dict()
	var before_owner: Dictionary = owner.to_dict()
	var result: MilestoneSettlement = MilestoneSettlement.prepare(tracker, catalogue, observation, owner, MAX_CASH)
	assert_not_null(result)
	if result == null:
		return
	assert_true(result.reached.is_empty())
	assert_eq(result.cash_reward, 0)
	assert_eq(result.xp_reward, 0)
	assert_eq(result.owner_xp_result["total_xp"], 0)
	assert_eq(result.tracker.last_evaluated_day, 4)
	assert_eq(result.tracker.total_served, 8)
	assert_eq(result.tracker.clean_streak, 3)
	assert_eq(result.owner_progress.to_dict(), before_owner)
	assert_eq(tracker.to_dict(), before_tracker)
	assert_eq(owner.to_dict(), before_owner)


func test_cash_edges_and_aggregate_overflow_are_checked_before_any_install() -> void:
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var owner: OwnerProgress = _owner()
	var observation: MilestoneDay = _day(1, 1)
	var catalogue: MilestoneSet = _catalogue([
		_goal(&"cash", Milestone.Condition.SERVED_TODAY, 1.0, 0, 1),
	] as Array[Milestone])
	var exact: MilestoneSettlement = MilestoneSettlement.prepare(tracker, catalogue, observation, owner, MAX_CASH - 1)
	assert_not_null(exact)
	if exact == null:
		return
	assert_eq((MAX_CASH - 1) + exact.cash_reward, MAX_CASH)
	_assert_refused(tracker, catalogue, observation, owner, MAX_CASH)
	var negative: MilestoneSettlement = MilestoneSettlement.prepare(tracker, catalogue, observation, owner, MIN_CASH)
	assert_not_null(negative)
	if negative != null:
		assert_eq(MIN_CASH + negative.cash_reward, MIN_CASH + 1)
	catalogue.milestones.append(_goal(&"second_cash", Milestone.Condition.SERVED_TODAY, 1.0, 1, 1))
	_assert_refused(tracker, catalogue, observation, owner, MAX_CASH - 1)
	assert_true(tracker.completed_ids().is_empty())
	assert_eq(owner.total_xp, 0)


func test_aggregate_xp_cannot_partially_complete_or_pay_a_batch() -> void:
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var owner: OwnerProgress = _owner(OwnerProgress.MAX_TOTAL_XP - 1)
	var observation: MilestoneDay = _day(1, 1, owner.level)
	var first: Milestone = _goal(&"first", Milestone.Condition.SERVED_TODAY, 1.0, 1, 10)
	var catalogue: MilestoneSet = _catalogue([first] as Array[Milestone])
	var exact: MilestoneSettlement = MilestoneSettlement.prepare(tracker, catalogue, observation, owner, 0)
	assert_not_null(exact)
	if exact != null:
		assert_eq(exact.owner_progress.total_xp, OwnerProgress.MAX_TOTAL_XP)
	catalogue.milestones.append(_goal(&"second", Milestone.Condition.SERVED_TODAY, 1.0, 1, 10))
	_assert_refused(tracker, catalogue, observation, owner, 0)
	assert_false(tracker.is_completed(first.id))
	assert_eq(owner.total_xp, OwnerProgress.MAX_TOTAL_XP - 1)


func test_invalid_models_catalogues_and_refused_evaluation_never_return_empty_success() -> void:
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var owner: OwnerProgress = _owner()
	var observation: MilestoneDay = _day(1, 1)
	var goal: Milestone = _goal(&"goal", Milestone.Condition.SERVED_TODAY, 1.0, 1, 1)
	var catalogue: MilestoneSet = _catalogue([goal] as Array[Milestone])
	_assert_refused(null, catalogue, observation, owner, 0)
	_assert_refused(tracker, catalogue, observation, null, 0)
	_assert_refused(tracker, null, observation, owner, 0)
	_assert_refused(tracker, catalogue, null, owner, 0)
	_assert_refused(tracker, _catalogue([goal, goal] as Array[Milestone]), observation, owner, 0)
	goal.reward_cash = -1
	_assert_refused(tracker, catalogue, observation, owner, 0)
	goal.reward_cash = 1
	observation.reputation = NAN
	_assert_refused(tracker, catalogue, observation, owner, 0)
	assert_true(is_nan(observation.reputation))
	observation.reputation = 3.0
	var full_tracker: MilestoneTracker = _tracker(0, MilestoneTracker.MAX_TOTAL_SERVED)
	_assert_refused(full_tracker, catalogue, observation, owner, 0)
	tracker.total_served = -1
	_assert_refused(tracker, catalogue, observation, owner, 0)
	tracker.total_served = 0
	owner.level = 2
	_assert_refused(tracker, catalogue, observation, owner, 0)
	_assert_refused(tracker, catalogue, observation, OwnerProgress.new(null), 0)


func test_json_reload_preserves_long_history_and_replay_or_reintroduced_goals_cannot_reward_twice() -> void:
	var tracker: MilestoneTracker = _tracker(1, 2, 1)
	var saved: Dictionary = tracker.to_dict()
	for index: int in range(65):
		saved["completed"].append("former_%02d" % index)
	assert_true(tracker.from_dict(JSON.parse_string(JSON.stringify(saved))))
	var owner: OwnerProgress = _owner(0, 2)
	var observation: MilestoneDay = _day(2, 1)
	var daily: Milestone = _goal(&"new_goal", Milestone.Condition.SERVED_TODAY, 1.0, 10, 5)
	var catalogue: MilestoneSet = _catalogue([daily] as Array[Milestone])
	var result: MilestoneSettlement = MilestoneSettlement.prepare(tracker, catalogue, observation, owner, 0)
	assert_not_null(result)
	if result == null:
		return
	var restored_tracker: MilestoneTracker = MilestoneTracker.new()
	var restored_owner: OwnerProgress = OwnerProgress.new(TUNING)
	assert_true(restored_tracker.from_dict(JSON.parse_string(JSON.stringify(result.tracker.to_dict()))))
	assert_true(restored_owner.from_dict(JSON.parse_string(JSON.stringify(result.owner_progress.to_dict()))))
	assert_eq(restored_tracker.completed_ids().size(), 66)
	assert_eq(restored_tracker.to_dict(), result.tracker.to_dict())
	assert_eq(restored_owner.to_dict(), result.owner_progress.to_dict())
	_assert_refused(restored_tracker, catalogue, observation, restored_owner, 5)
	assert_eq(restored_owner.award_day(3, 0, 0)["total_xp"], 0)
	catalogue.milestones.append(_goal(&"former_00", Milestone.Condition.SERVED_TODAY, 1.0, 100, 100))
	var next_day: MilestoneSettlement = MilestoneSettlement.prepare(restored_tracker, catalogue, _day(3, 1), restored_owner, 5)
	assert_not_null(next_day)
	if next_day != null:
		assert_true(next_day.reached.is_empty())
		assert_eq(next_day.cash_reward, 0)
		assert_eq(next_day.xp_reward, 0)
		assert_eq(next_day.tracker.completed_ids(), restored_tracker.completed_ids())


func _assert_refused(live_tracker: MilestoneTracker, catalogue: MilestoneSet,
		observation: MilestoneDay, live_owner: OwnerProgress, cash: int) -> void:
	var before_tracker: Dictionary = live_tracker.to_dict() if live_tracker != null else {}
	var before_owner: Dictionary = live_owner.to_dict() if live_owner != null else {}
	var before_day: Dictionary = _day_snapshot(observation) if observation != null else {}
	assert_null(MilestoneSettlement.prepare(live_tracker, catalogue, observation, live_owner, cash))
	if live_tracker != null:
		assert_eq(live_tracker.to_dict(), before_tracker)
	if live_owner != null:
		assert_eq(live_owner.to_dict(), before_owner)
	if observation != null:
		assert_eq(_day_snapshot(observation), before_day)


func _owner(xp: int = 0, day: int = 0) -> OwnerProgress:
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	assert_true(progress.from_dict({"version": 1, "total_xp": xp,
		"level": progress.level_at(xp), "last_awarded_day": day}))
	return progress


func _tracker(day: int, served: int, streak: int = 0) -> MilestoneTracker:
	var progress: MilestoneTracker = MilestoneTracker.new()
	assert_true(progress.from_dict({"version": 1, "completed": [], "total_served": served,
		"clean_streak": streak, "last_evaluated_day": day}))
	return progress


func _catalogue(goals: Array[Milestone]) -> MilestoneSet:
	var catalogue: MilestoneSet = MilestoneSet.new()
	catalogue.milestones = goals
	return catalogue


func _goal(id: StringName, kind: int, target: float, xp: int, cash: int) -> Milestone:
	var goal: Milestone = Milestone.new()
	goal.id = id
	goal.title = "An earned reward"
	goal.description = "Complete an authored day-close goal."
	goal.condition = kind
	goal.target = target
	goal.reward_xp = xp
	goal.reward_cash = cash
	return goal


func _ids(goals: Array[Milestone]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for goal: Milestone in goals:
		ids.append(goal.id)
	return ids


func _day(day: int, served: int, owner_level: int = 1) -> MilestoneDay:
	var observation: MilestoneDay = MilestoneDay.new()
	observation.day = day
	observation.served_today = served
	observation.owner_level = owner_level
	return observation


func _day_snapshot(observation: MilestoneDay) -> Dictionary:
	return {"day": observation.day, "served": observation.served_today, "lost": observation.lost_today,
		"reputation": str(observation.reputation), "profit": observation.operating_profit,
		"owner_level": observation.owner_level, "staff_count": observation.staff_count}


func _goal_snapshot(goal: Milestone) -> Dictionary:
	return {"id": goal.id, "title": goal.title, "description": goal.description,
		"condition": goal.condition, "target": goal.target, "xp": goal.reward_xp,
		"cash": goal.reward_cash, "unlock_level": goal.unlock_level}
