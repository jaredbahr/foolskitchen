extends TestCase
## Day-boundary XP, queued raises, mood and strict saved-state validation.

const TUNING: StaffGrowthTuning = preload("res://data/balance/staff_growth.tres")


func test_authored_tasks_map_to_their_worked_skill() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.skill_for_task(&"cook"), &"cooking")
	for kind: StringName in [&"take_order", &"deliver", &"bus_table", &"wash"]:
		assert_eq(TUNING.skill_for_task(kind), &"service")
	assert_eq(TUNING.skill_for_task(&"clean_spot"), &"cleaning")
	assert_eq(TUNING.xp_for_task(&"unknown"), 0)
	assert_eq(TUNING.needed_for_next_level(5), 0)


func test_small_fixture_leaves_authored_task_xp_unchanged() -> void:
	var authored: Dictionary = TUNING.task_xp.duplicate()
	var tuning: StaffGrowthTuning = _fast_tuning()
	tuning.task_xp[&"cook"] = 999
	tuning.task_xp[&"clean_spot"] = 999
	assert_eq(TUNING.task_xp, authored, "mechanics fixtures cannot retune the shared production resource")


func test_completed_tasks_wait_until_close_and_raise_once_per_skill_up() -> void:
	var tuning: StaffGrowthTuning = _fast_tuning()
	var growth: StaffGrowth = StaffGrowth.new(&"cooking", 3, 30)
	for _index: int in range(4):
		assert_true(growth.record_task(&"cook", tuning))
	assert_eq(growth.earned_today(&"cooking"), 8)
	assert_eq(growth.skill_level(&"cooking"), 3)
	assert_eq(growth.pending_raise_count(), 0)
	var raised: Array[Dictionary] = growth.close_day(tuning)
	assert_eq(raised, [{"skill": "cooking", "level": 4}])
	assert_eq(growth.skill_level(&"cooking"), 4)
	assert_eq(growth.progress_xp(&"cooking"), 0)
	assert_eq(growth.pending_raise_count(), 1)
	assert_eq(growth.close_day(tuning), [], "a second close without work cannot duplicate XP or a raise")
	assert_eq(growth.pending_raise_count(), 1)
	assert_eq(growth.pending_raise()["level"], 4)


func test_xp_goes_to_the_task_skill_and_caps_every_skill_at_five() -> void:
	var tuning: StaffGrowthTuning = _fast_tuning()
	var growth: StaffGrowth = StaffGrowth.new(&"service", 3, 25)
	assert_false(growth.record_task(&"not_a_task", tuning))
	assert_true(growth.record_task(&"clean_spot", tuning))
	assert_eq(growth.earned_today(&"cleaning"), 2)
	assert_eq(growth.earned_today(&"service"), 0)
	growth.close_day(tuning)
	assert_eq(growth.progress_xp(&"cleaning"), 2)
	assert_eq(growth.skill_level(&"service"), 3)
	var cook: StaffGrowth = StaffGrowth.new(&"cooking", 1, 18)
	for _index: int in range(15):
		assert_true(cook.record_task(&"cook", tuning))
	assert_eq(cook.close_day(tuning).size(), 4)
	assert_eq(cook.skill_level(&"cooking"), 5)
	assert_eq(cook.pending_raise_count(), 4)
	assert_eq(cook.progress_xp(&"cooking"), 0)


func test_accept_updates_wage_and_refusal_quits_only_next_morning() -> void:
	var tuning: StaffGrowthTuning = _fast_tuning()
	var growth: StaffGrowth = StaffGrowth.new(&"cooking", 1, 18)
	for _index: int in range(5):
		growth.record_task(&"cook", tuning)
	growth.close_day(tuning)
	assert_eq(growth.pending_raise_count(), 2)
	assert_false(growth.accept_raise(17), "a proposed raise cannot lower pay")
	assert_true(growth.accept_raise(24))
	assert_eq(growth.wage, 24)
	assert_eq(growth.pending_raise_count(), 1)
	assert_true(growth.decline_raise(4))
	assert_eq(growth.mood, 2)
	assert_eq(growth.pending_raise_count(), 0)
	assert_false(growth.should_quit_this_morning(5, false))
	var unhappy: StaffGrowth = StaffGrowth.new(&"cooking", 1, 18)
	for _index: int in range(15):
		unhappy.record_task(&"cook", tuning)
	unhappy.close_day(tuning)
	for _index: int in range(3):
		assert_true(unhappy.decline_raise(4))
	assert_eq(unhappy.mood, 0)
	var due: Dictionary = unhappy.to_dict()
	assert_false(unhappy.decline_raise(4, true), "a direct call cannot rewrite an already scheduled quit")
	assert_eq(unhappy.to_dict(), due)
	assert_false(unhappy.should_quit_this_morning(4, false), "refusal cannot make a person leave immediately")
	assert_true(unhappy.should_quit_this_morning(5, false))
	assert_eq(unhappy.mood, 1, "a settled departure cannot serialize as mood zero without a date")
	assert_false(unhappy.should_quit_this_morning(5, false), "a departure is never replayed")


func test_protected_refusal_clamps_immediately_and_keeps_saved_state_valid() -> void:
	var growth: StaffGrowth = StaffGrowth.new(&"service", 1, 20)
	var tuning: StaffGrowthTuning = _fast_tuning()
	for _index: int in range(30):
		growth.record_task(&"deliver", tuning)
	growth.close_day(tuning)
	var remaining: int = growth.pending_raise_count()
	for mood_after: int in [2, 1, 1, 1]:
		assert_true(growth.decline_raise(8, true))
		remaining -= 1
		assert_eq(growth.mood, mood_after)
		assert_eq(growth.quit_due_day(), 0)
		assert_eq(growth.pending_raise_count(), remaining)
		var restored: StaffGrowth = StaffGrowth.new()
		assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(growth.to_dict()))))
		assert_eq(restored.to_dict(), growth.to_dict())
	assert_false(growth.should_quit_this_morning(9, false))
	assert_false(growth.decline_raise(8, true), "the empty queue is still guarded")


func test_legacy_scheduled_quit_is_protected_at_the_morning_boundary() -> void:
	var growth: StaffGrowth = StaffGrowth.new(&"service", 1, 20)
	var tuning: StaffGrowthTuning = _fast_tuning()
	for _index: int in range(30):
		growth.record_task(&"deliver", tuning)
	growth.close_day(tuning)
	for _index: int in range(3):
		assert_true(growth.decline_raise(8))
	assert_eq(growth.mood, 0)
	assert_false(growth.should_quit_this_morning(9, true))
	assert_eq(growth.mood, 1)
	assert_false(growth.should_quit_this_morning(10, false))


func test_json_roundtrip_and_invalid_decoder_leave_live_state_unchanged() -> void:
	var growth: StaffGrowth = StaffGrowth.new(&"cooking", 3, 30)
	var tuning: StaffGrowthTuning = _fast_tuning()
	for _index: int in range(4):
		growth.record_task(&"cook", tuning)
	growth.close_day(tuning)
	var saved: Dictionary = growth.to_dict()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored: StaffGrowth = StaffGrowth.new()
	assert_true(restored.from_dict(decoded))
	assert_eq(restored.to_dict(), saved)
	var invalid: Array[Dictionary] = []
	var row: Dictionary = decoded.duplicate(true)
	row["version"] = 2
	invalid.append(row)
	row = decoded.duplicate(true)
	row["skills"]["cooking"] = 6
	invalid.append(row)
	row = decoded.duplicate(true)
	row["xp"]["service"] = -1
	invalid.append(row)
	row = decoded.duplicate(true)
	row["mood"] = 4
	invalid.append(row)
	row = decoded.duplicate(true)
	row["mood"] = 0
	invalid.append(row)
	row = decoded.duplicate(true)
	row["quit_day"] = 9
	invalid.append(row)
	row = decoded.duplicate(true)
	row["raises"][0]["skill"] = "unknown"
	invalid.append(row)
	row = decoded.duplicate(true)
	row["raises"][0].erase("level")
	row["raises"][0]["unrelated"] = 4
	invalid.append(row)
	row = decoded.duplicate(true)
	row["raises"].append(row["raises"][0].duplicate())
	invalid.append(row)
	row = decoded.duplicate(true)
	row["extra"] = true
	invalid.append(row)
	for document: Dictionary in invalid:
		assert_false(restored.from_dict(document))
		assert_eq(restored.to_dict(), saved)
	assert_eq(StaffGrowth.new(&"service", 3, 25).mood, 3, "old saves get the default mood")


func _fast_tuning() -> StaffGrowthTuning:
	var tuning: StaffGrowthTuning = TUNING.duplicate(true) as StaffGrowthTuning
	# Small mechanic fixtures stay independent of provisional production pacing.
	tuning.task_xp[&"cook"] = 2
	tuning.task_xp[&"clean_spot"] = 2
	tuning.next_level_xp = PackedInt32Array([4, 6, 8, 10])
	return tuning
