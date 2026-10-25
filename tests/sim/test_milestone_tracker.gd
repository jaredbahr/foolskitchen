extends TestCase
## Career conditions are day-close pure state; reward application is a later
## Main/ledger integration step and must not be hidden in this evaluator.

const STARTER: MilestoneSet = preload("res://data/milestones/starter.tres")


func test_starter_catalogue_has_twelve_valid_goals_and_every_condition() -> void:
	assert_true(STARTER.is_valid())
	assert_eq(STARTER.milestones.size(), 12)
	var kinds: Dictionary[int, bool] = {}
	for goal: Milestone in STARTER.milestones:
		assert_true(goal.is_valid())
		assert_false(goal.title.contains("_"), "players see names, never internal IDs")
		kinds[goal.condition] = true
	for kind: int in range(Milestone.Condition.CLEAN_STREAK + 1):
		assert_true(kinds.has(kind), "all seven authored condition kinds are present")
	assert_not_null(STARTER.by_id(&"clean_run"))
	assert_null(STARTER.by_id(&"missing_goal"))


func test_each_single_day_condition_completes_at_its_threshold_only_once() -> void:
	var cases: Array[Dictionary] = [
		{"kind": Milestone.Condition.SERVED_TODAY, "target": 10.0, "below": 9.0},
		{"kind": Milestone.Condition.REPUTATION, "target": 3.5, "below": 3.4},
		{"kind": Milestone.Condition.PROFIT_TODAY, "target": 30.0, "below": 29.0},
		{"kind": Milestone.Condition.OWNER_LEVEL, "target": 2.0, "below": 1.0},
		{"kind": Milestone.Condition.STAFF_COUNT, "target": 3.0, "below": 2.0},
	]
	for row: Dictionary in cases:
		var goal: Milestone = _goal(int(row["kind"]), float(row["target"]))
		var catalogue: MilestoneSet = _single(goal)
		var tracker: MilestoneTracker = MilestoneTracker.new()
		var first: MilestoneDay = _day(1)
		_set_condition_value(first, goal.condition, float(row["below"]))
		assert_true(tracker.evaluate_day(first, catalogue).is_empty())
		var second: MilestoneDay = _day(2)
		_set_condition_value(second, goal.condition, goal.target)
		assert_eq(tracker.evaluate_day(second, catalogue), [goal] as Array[Milestone])
		assert_true(tracker.evaluate_day(second, catalogue).is_empty(),
			"the same close cannot pay twice")
		var third: MilestoneDay = _day(3)
		_set_condition_value(third, goal.condition, goal.target)
		assert_true(tracker.evaluate_day(third, catalogue).is_empty(),
			"a completed goal stays completed on later days")


func test_total_served_and_clean_streak_track_across_real_service_days() -> void:
	var total_goal: Milestone = _goal(Milestone.Condition.TOTAL_SERVED, 5.0)
	total_goal.id = &"five_total"
	var clean_goal: Milestone = _goal(Milestone.Condition.CLEAN_STREAK, 2.0)
	clean_goal.id = &"two_clean"
	var catalogue: MilestoneSet = MilestoneSet.new()
	catalogue.milestones = [total_goal, clean_goal] as Array[Milestone]
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var first: MilestoneDay = _day(1)
	first.served_today = 2
	first.lost_today = 0
	assert_true(tracker.evaluate_day(first, catalogue).is_empty())
	var second: MilestoneDay = _day(2)
	second.served_today = 3
	second.lost_today = 1
	assert_eq(tracker.evaluate_day(second, catalogue), [total_goal] as Array[Milestone])
	assert_eq(tracker.clean_streak, 0, "a loss breaks the streak")
	var third: MilestoneDay = _day(3)
	third.served_today = 2
	assert_true(tracker.evaluate_day(third, catalogue).is_empty())
	var fourth: MilestoneDay = _day(4)
	fourth.served_today = 2
	assert_eq(tracker.evaluate_day(fourth, catalogue), [clean_goal] as Array[Milestone])
	assert_eq(tracker.total_served, 9)
	assert_eq(tracker.clean_streak, 2)
	assert_eq(tracker.completed_ids(), [&"five_total", &"two_clean"] as Array[StringName])


func test_unlock_level_and_missing_day_do_not_invent_completions() -> void:
	var goal: Milestone = _goal(Milestone.Condition.CLEAN_STREAK, 2.0)
	goal.unlock_level = 3
	var catalogue: MilestoneSet = _single(goal)
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var first: MilestoneDay = _day(1)
	first.owner_level = 2
	tracker.evaluate_day(first, catalogue)
	var skipped: MilestoneDay = _day(3)
	skipped.owner_level = 3
	assert_true(tracker.evaluate_day(skipped, catalogue).is_empty())
	assert_eq(tracker.clean_streak, 1, "missing day resets consecutive-day progress")
	var fourth: MilestoneDay = _day(4)
	fourth.owner_level = 3
	assert_eq(tracker.evaluate_day(fourth, catalogue), [goal] as Array[Milestone])


func test_json_round_trip_preserves_once_only_state_and_replay_is_deterministic() -> void:
	var first: MilestoneTracker = MilestoneTracker.new()
	var opening: MilestoneDay = _day(1)
	opening.served_today = 20
	opening.reputation = 3.6
	opening.operating_profit = 50
	opening.owner_level = 2
	opening.staff_count = 3
	var reached: Array[Milestone] = first.evaluate_day(opening, STARTER)
	assert_false(reached.is_empty())
	var saved: Dictionary = first.to_dict()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored: MilestoneTracker = MilestoneTracker.new()
	assert_true(restored.from_dict(decoded))
	assert_eq(restored.to_dict(), saved)
	var next: MilestoneDay = _day(2)
	next.served_today = 19
	next.owner_level = 2
	var a: Array[Milestone] = first.evaluate_day(next, STARTER)
	var b: Array[Milestone] = restored.evaluate_day(next, STARTER)
	assert_eq(_ids(a), _ids(b), "same day data produces the same new goals after load")
	assert_eq(first.to_dict(), restored.to_dict())
	assert_true(restored.evaluate_day(next, STARTER).is_empty())


func test_replaced_catalogue_history_round_trips_after_another_completion() -> void:
	for former_count: int in [63, 64]:
		var former: MilestoneSet = _historical_catalogue(former_count)
		assert_true(former.is_valid())
		var original: MilestoneTracker = MilestoneTracker.new()
		var first_day: MilestoneDay = _day(1)
		first_day.served_today = 1
		assert_eq(_ids(original.evaluate_day(first_day, former)), _ids(former.milestones))
		var previous_save: Dictionary = JSON.parse_string(JSON.stringify(original.to_dict()))
		var tracker: MilestoneTracker = MilestoneTracker.new()
		assert_true(tracker.from_dict(previous_save))

		var new_goal: Milestone = _goal(Milestone.Condition.SERVED_TODAY, 1.0)
		new_goal.id = &"new_goal"
		var next_day: MilestoneDay = _day(2)
		next_day.served_today = 1
		assert_eq(tracker.evaluate_day(next_day, _single(new_goal)), [new_goal] as Array[Milestone])
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(tracker.to_dict()))
		var restored: MilestoneTracker = MilestoneTracker.new()
		assert_true(restored.from_dict(snapshot), "a replaced catalogue can grow lifetime history past 64")
		assert_eq(restored.to_dict(), tracker.to_dict())
		var expected_ids: Array[StringName] = _ids(former.milestones)
		expected_ids.append(new_goal.id)
		expected_ids.sort()
		assert_eq(restored.completed_ids(), expected_ids, "removed goals retain their completed IDs")
		assert_true(restored.evaluate_day(next_day, _single(new_goal)).is_empty(),
			"replaying the saved close cannot return a second reward")
		assert_eq(restored.to_dict(), tracker.to_dict())

		var reintroduced: MilestoneSet = MilestoneSet.new()
		reintroduced.milestones = [new_goal, former.milestones[0]] as Array[Milestone]
		var later_day: MilestoneDay = _day(3)
		later_day.served_today = 1
		assert_true(restored.evaluate_day(later_day, reintroduced).is_empty(),
			"returning a removed goal cannot pay it again on a later day")
		assert_eq(restored.completed_ids(), expected_ids)


func test_late_invalid_history_id_rejects_transactionally_after_former_size_boundary() -> void:
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var first_day: MilestoneDay = _day(1)
	first_day.served_today = 1
	tracker.evaluate_day(first_day, _single(_goal(Milestone.Condition.SERVED_TODAY, 1.0)))
	var original: Dictionary = tracker.to_dict()
	for bad_id: Variant in [7, "", "former_00"]:
		var invalid: Dictionary = original.duplicate(true)
		var ids: Array = []
		for index: int in 64:
			ids.append("former_%02d" % index)
		ids.append(bad_id)
		invalid["completed"] = ids
		invalid["total_served"] = 10
		invalid["clean_streak"] = 2
		invalid["last_evaluated_day"] = 2
		assert_false(tracker.from_dict(invalid), "bad IDs beyond entry 64 still reject the whole snapshot")
		assert_eq(tracker.to_dict(), original, "neither counters nor earlier valid IDs may be installed")


func test_active_catalogue_still_rejects_more_than_sixty_four_goals() -> void:
	assert_true(_historical_catalogue(64).is_valid())
	assert_false(_historical_catalogue(65).is_valid())


func test_progress_projection_returns_raw_units_for_every_condition_without_mutation() -> void:
	var catalogue: MilestoneSet = _condition_catalogue()
	var tracker: MilestoneTracker = MilestoneTracker.new()
	assert_true(tracker.from_dict({"version": 1, "completed": ["former_goal"],
		"total_served": 10, "clean_streak": 2, "last_evaluated_day": 2}))
	var observation: MilestoneDay = _day(3)
	observation.served_today = 4
	observation.reputation = 3.5
	observation.operating_profit = -20
	observation.owner_level = 3
	observation.staff_count = 4
	var before: Dictionary = tracker.to_dict()
	var values: Dictionary[StringName, float] = tracker.progress_values(catalogue, observation)
	var expected: Array[float] = [4.0, 3.5, -20.0, 14.0, 3.0, 4.0, 3.0]
	assert_eq(values.size(), expected.size())
	for kind: int in range(expected.size()):
		var id: StringName = StringName("condition_%d" % kind)
		assert_true(is_finite(values[id]))
		assert_eq(values[id], expected[kind])
	assert_eq(tracker.to_dict(), before)
	assert_eq(observation.served_today, 4)
	assert_eq(observation.owner_level, 3)
	assert_eq(catalogue.milestones[0].target, 1.0)


func test_progress_projection_uses_recorded_closed_day_then_projects_consecutive_gap_and_loss() -> void:
	var catalogue: MilestoneSet = _condition_catalogue()
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var first: MilestoneDay = _day(1)
	first.served_today = 5
	tracker.evaluate_day(first, catalogue)
	var recorded: Dictionary = tracker.to_dict()
	var closed: Dictionary[StringName, float] = tracker.progress_values(catalogue, first)
	assert_eq(closed[&"condition_3"], 5.0, "the closed day is not added to the career total twice")
	assert_eq(closed[&"condition_6"], 1.0, "a displayed close cannot extend its clean streak")
	var second: MilestoneDay = _day(2)
	second.served_today = 3
	var projected: Dictionary[StringName, float] = tracker.progress_values(catalogue, second)
	assert_eq(projected[&"condition_3"], 8.0)
	assert_eq(projected[&"condition_6"], 2.0)
	assert_eq(tracker.to_dict(), recorded)
	tracker.evaluate_day(second, catalogue)
	assert_eq(tracker.progress_values(catalogue, second), projected)
	var before: Dictionary = tracker.to_dict()
	var gap: MilestoneDay = _day(4)
	gap.served_today = 1
	var after_gap: Dictionary[StringName, float] = tracker.progress_values(catalogue, gap)
	assert_eq(after_gap[&"condition_3"], 9.0)
	assert_eq(after_gap[&"condition_6"], 1.0)
	var loss: MilestoneDay = _day(3)
	loss.served_today = 1
	loss.lost_today = 1
	assert_eq(tracker.progress_values(catalogue, loss)[&"condition_6"], 0.0)
	assert_eq(tracker.progress_values(catalogue, first), {} as Dictionary[StringName, float])
	assert_eq(tracker.to_dict(), before, "display projections never install future or stale observations")


func test_progress_projection_rejects_invalid_or_overflowing_inputs_without_counting_a_closed_day_twice() -> void:
	var tracker: MilestoneTracker = MilestoneTracker.new()
	assert_true(tracker.from_dict({"version": 1, "completed": [],
		"total_served": MilestoneTracker.MAX_TOTAL_SERVED, "clean_streak": 1, "last_evaluated_day": 1}))
	var catalogue: MilestoneSet = _condition_catalogue()
	var before: Dictionary = tracker.to_dict()
	var closed: MilestoneDay = _day(1)
	closed.served_today = 1
	assert_eq(tracker.progress_values(catalogue, closed)[&"condition_3"], float(MilestoneTracker.MAX_TOTAL_SERVED))
	var overflow: MilestoneDay = _day(2)
	overflow.served_today = 1
	assert_true(tracker.progress_values(catalogue, overflow).is_empty())
	assert_true(tracker.progress_values(_single(_goal(Milestone.Condition.OWNER_LEVEL, 1.0)), overflow).is_empty(),
		"a different visible condition cannot hide cumulative counter overflow")
	var valid: MilestoneDay = _day(2)
	assert_eq(tracker.progress_values(catalogue, valid)[&"condition_3"], float(MilestoneTracker.MAX_TOTAL_SERVED))
	assert_true(tracker.progress_values(null, valid).is_empty())
	assert_true(tracker.progress_values(MilestoneSet.new(), valid).is_empty())
	assert_true(tracker.progress_values(catalogue, null).is_empty())
	valid.reputation = INF
	assert_true(tracker.progress_values(catalogue, valid).is_empty())
	assert_eq(tracker.to_dict(), before)
	tracker.total_served = -1
	var malformed: Dictionary = tracker.to_dict()
	assert_true(tracker.progress_values(catalogue, closed).is_empty())
	assert_eq(tracker.to_dict(), malformed)


func test_malformed_snapshot_or_catalogue_never_partially_changes_progress() -> void:
	var tracker: MilestoneTracker = MilestoneTracker.new()
	var goal: Milestone = _goal(Milestone.Condition.SERVED_TODAY, 1.0)
	var invalid: MilestoneSet = MilestoneSet.new()
	invalid.milestones = [goal, goal] as Array[Milestone]
	var first: MilestoneDay = _day(1)
	first.served_today = 1
	assert_true(tracker.evaluate_day(first, invalid).is_empty())
	assert_eq(tracker.last_evaluated_day, 0)
	assert_eq(tracker.evaluate_day(first, _single(goal)), [goal] as Array[Milestone])
	var original: Dictionary = tracker.to_dict()
	for bad: Variant in [null, {}, {"version": 1, "completed": [&"goal", &"goal"],
			"total_served": 1, "clean_streak": 1, "last_evaluated_day": 1},
			{"version": 1, "completed": [], "total_served": -1,
			"clean_streak": 0, "last_evaluated_day": 1}]:
		assert_false(tracker.from_dict(bad))
		assert_eq(tracker.to_dict(), original)
	var with_removed: Dictionary = original.duplicate(true)
	with_removed["completed"] = ["former_goal"]
	assert_true(tracker.from_dict(with_removed))
	assert_true(tracker.is_completed(&"former_goal"))


func _condition_catalogue() -> MilestoneSet:
	var catalogue: MilestoneSet = MilestoneSet.new()
	for kind: int in range(Milestone.Condition.CLEAN_STREAK + 1):
		var goal: Milestone = _goal(kind, 1.0)
		goal.id = StringName("condition_%d" % kind)
		catalogue.milestones.append(goal)
	return catalogue


func _historical_catalogue(count: int) -> MilestoneSet:
	var catalogue: MilestoneSet = MilestoneSet.new()
	for index: int in count:
		var goal: Milestone = _goal(Milestone.Condition.SERVED_TODAY, 1.0)
		goal.id = StringName("former_%02d" % index)
		catalogue.milestones.append(goal)
	return catalogue


func _goal(kind: int, target: float) -> Milestone:
	var goal: Milestone = Milestone.new()
	goal.id = &"goal"
	goal.title = "A little victory"
	goal.description = "Complete a measured goal."
	goal.condition = kind
	goal.target = target
	goal.reward_xp = 1
	return goal


func _single(goal: Milestone) -> MilestoneSet:
	var catalogue: MilestoneSet = MilestoneSet.new()
	catalogue.milestones = [goal] as Array[Milestone]
	return catalogue


func _day(day_number: int) -> MilestoneDay:
	var observation: MilestoneDay = MilestoneDay.new()
	observation.day = day_number
	return observation


func _set_condition_value(observation: MilestoneDay, kind: int, value: float) -> void:
	match kind:
		Milestone.Condition.SERVED_TODAY:
			observation.served_today = int(value)
		Milestone.Condition.REPUTATION:
			observation.reputation = value
		Milestone.Condition.PROFIT_TODAY:
			observation.operating_profit = int(value)
		Milestone.Condition.OWNER_LEVEL:
			observation.owner_level = int(value)
		Milestone.Condition.STAFF_COUNT:
			observation.staff_count = int(value)


func _ids(goals: Array[Milestone]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for goal: Milestone in goals:
		ids.append(goal.id)
	return ids
