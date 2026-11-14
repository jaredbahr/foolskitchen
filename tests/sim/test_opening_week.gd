extends TestCase
## The opening-week chain's pure model and authored data (#494).

const CHAIN: OpeningWeekSet = preload("res://data/balance/opening_week.tres")


func test_authored_chain_is_valid_and_pays_about_six_hundred() -> void:
	assert_true(CHAIN.is_valid())
	assert_eq(CHAIN.goals.size(), 8)
	assert_eq(CHAIN.last_day, 7)
	assert_eq(CHAIN.shown_goals, 3)
	assert_true(CHAIN.total_cash() >= 560 and CHAIN.total_cash() <= 650,
		"the chain pays about $600 in all (Jared, #494): %d" % CHAIN.total_cash())
	var conditions: Dictionary[int, bool] = {}
	for goal: OpeningGoal in CHAIN.goals:
		conditions[goal.condition] = true
		assert_true(goal.reward_cash > 0 and goal.reward_xp > 0, "%s pays cash and a little XP" % goal.id)
		assert_true(goal.reward_xp <= 20, "%s: only a little XP" % goal.id)
	for condition: int in range(OpeningGoal.Condition.PRICE_CHANGED, OpeningGoal.Condition.REPUTATION + 1):
		assert_true(conditions.has(condition), "every condition has a goal: %d" % condition)


func test_each_goal_triggers_from_its_own_condition_and_pays_once() -> void:
	var cases: Array[Array] = [
		[&"change_price", OpeningGoal.Condition.PRICE_CHANGED, 1.0],
		[&"place_decor", OpeningGoal.Condition.DECOR_PLACED, 1.0],
		[&"serve_15", OpeningGoal.Condition.SERVED_TODAY, 15.0],
		[&"drink_on_menu", OpeningGoal.Condition.DRINK_ON_MENU, 1.0],
		[&"owner_on_floor", OpeningGoal.Condition.OWNER_ON_FLOOR, 1.0],
		[&"grow_together", OpeningGoal.Condition.GROW_TOGETHER, 1.0],
		[&"reach_4_stars", OpeningGoal.Condition.REPUTATION, 4.0],
	]
	for row: Array in cases:
		var state: OpeningWeek = OpeningWeek.new()
		var met: Array[OpeningGoal] = state.observe(row[1], row[2], CHAIN)
		assert_eq(met.size(), 1, "%s triggers alone" % row[0])
		if met.size() == 1:
			assert_eq(met[0].id, row[0])
			assert_eq(state.pending_xp, met[0].reward_xp)
		assert_true(state.is_completed(row[0]))
		assert_true(state.observe(row[1], row[2], CHAIN).is_empty(), "%s pays once only" % row[0])
		assert_eq(state.completed_ids(), [row[0]] as Array[StringName], "nothing else is met")


func test_thresholds_and_the_serve_pair() -> void:
	var state: OpeningWeek = OpeningWeek.new()
	assert_true(state.observe(OpeningGoal.Condition.SERVED_TODAY, 14.0, CHAIN).is_empty())
	assert_true(state.observe(OpeningGoal.Condition.REPUTATION, 3.95, CHAIN).is_empty())
	assert_true(state.observe(OpeningGoal.Condition.DRINK_ON_MENU, 0.0, CHAIN).is_empty())
	var both: Array[OpeningGoal] = state.observe(OpeningGoal.Condition.SERVED_TODAY, 25.0, CHAIN)
	assert_eq(both.size(), 2, "a 25-guest day meets both serving goals at once")
	if both.size() == 2:
		assert_eq([both[0].id, both[1].id], [&"serve_15", &"serve_25"])


func test_card_shows_the_next_three_unfinished_goals_in_order() -> void:
	var state: OpeningWeek = OpeningWeek.new()
	assert_eq(_ids(state.shown(CHAIN)), [&"change_price", &"place_decor", &"serve_15"] as Array[StringName])
	state.observe(OpeningGoal.Condition.SERVED_TODAY, 18.0, CHAIN)
	assert_eq(_ids(state.shown(CHAIN)), [&"change_price", &"place_decor", &"drink_on_menu"] as Array[StringName],
		"goals carry over; a done goal makes room for the next")
	state.observe(OpeningGoal.Condition.GROW_TOGETHER, 1.0, CHAIN)
	assert_true(state.is_completed(&"grow_together"), "a goal not yet shown still counts")


func test_pending_xp_is_handed_over_once() -> void:
	var state: OpeningWeek = OpeningWeek.new()
	state.observe(OpeningGoal.Condition.PRICE_CHANGED, 1.0, CHAIN)
	state.observe(OpeningGoal.Condition.DECOR_PLACED, 1.0, CHAIN)
	var expected: int = CHAIN.by_id(&"change_price").reward_xp + CHAIN.by_id(&"place_decor").reward_xp
	assert_eq(state.take_pending_xp(), expected)
	assert_eq(state.take_pending_xp(), 0)


func test_chain_ends_after_day_seven_or_when_every_goal_is_done() -> void:
	var state: OpeningWeek = OpeningWeek.new()
	assert_false(state.end_if_due(7, CHAIN), "day 7 is still in the week")
	assert_true(state.is_active())
	assert_true(state.end_if_due(8, CHAIN), "the morning after day 7 ends it")
	assert_false(state.is_active())
	assert_false(state.end_if_due(9, CHAIN), "it ends once")
	assert_true(state.observe(OpeningGoal.Condition.PRICE_CHANGED, 1.0, CHAIN).is_empty(),
		"an ended chain never pays")
	assert_true(state.shown(CHAIN).is_empty())
	var finished: OpeningWeek = OpeningWeek.new()
	for goal: OpeningGoal in CHAIN.goals:
		finished.observe(goal.condition, goal.target, CHAIN)
	assert_true(finished.all_done(CHAIN))
	assert_true(finished.end_if_due(3, CHAIN), "a finished chain ends early")


func test_save_round_trip_and_rejects_malformed_rows() -> void:
	var state: OpeningWeek = OpeningWeek.new()
	state.observe(OpeningGoal.Condition.DECOR_PLACED, 1.0, CHAIN)
	state.observe(OpeningGoal.Condition.PRICE_CHANGED, 1.0, CHAIN)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var loaded: OpeningWeek = OpeningWeek.new()
	assert_true(loaded.from_dict(saved))
	assert_eq(loaded.to_dict(), state.to_dict())
	assert_eq(loaded.completed_ids(), [&"place_decor", &"change_price"] as Array[StringName])
	assert_true(loaded.observe(OpeningGoal.Condition.DECOR_PLACED, 1.0, CHAIN).is_empty(), "no repeat after a load")
	for bad: Variant in [null, {}, {"version": 2, "status": "active", "completed": [], "pending_xp": 0},
			{"version": 1, "status": "paused", "completed": [], "pending_xp": 0},
			{"version": 1, "status": "active", "completed": ["a", "a"], "pending_xp": 0},
			{"version": 1, "status": "active", "completed": [""], "pending_xp": 0},
			{"version": 1, "status": "active", "completed": [], "pending_xp": -1},
			{"version": 1, "status": "active", "completed": [], "pending_xp": 0, "extra": 1}]:
		var candidate: OpeningWeek = OpeningWeek.new()
		candidate.observe(OpeningGoal.Condition.PRICE_CHANGED, 1.0, CHAIN)
		var before: Dictionary = candidate.to_dict()
		assert_false(candidate.from_dict(bad), "rejects %s" % str(bad))
		assert_eq(candidate.to_dict(), before, "a refused row changes nothing")


func test_saves_from_before_the_chain_join_only_inside_the_week() -> void:
	assert_true(OpeningWeek.legacy_for_day(1, CHAIN).is_active())
	assert_true(OpeningWeek.legacy_for_day(7, CHAIN).is_active())
	assert_false(OpeningWeek.legacy_for_day(8, CHAIN).is_active())
	assert_false(OpeningWeek.legacy_for_day(40, CHAIN).is_active())
	assert_false(OpeningWeek.legacy_for_day(1, null).is_active())


func _ids(goals: Array[OpeningGoal]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for goal: OpeningGoal in goals:
		ids.append(goal.id)
	return ids
