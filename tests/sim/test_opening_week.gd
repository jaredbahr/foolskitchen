extends TestCase
## The goal chains' pure model and authored data (#494 Opening week, #514
## Week 2 and the hand-over between them).

const CHAIN: OpeningWeekSet = preload("res://data/balance/opening_week.tres")
const WEEK_TWO: OpeningWeekSet = preload("res://data/balance/week_two.tres")
const CHAINS: GoalChainSequence = preload("res://data/balance/goal_chains.tres")


func test_authored_chain_is_valid_and_pays_about_six_hundred() -> void:
	assert_true(CHAIN.is_valid())
	assert_eq(CHAIN.goals.size(), 8)
	assert_eq(CHAIN.id, &"opening_week")
	assert_eq(CHAIN.title, "Opening week")
	assert_eq(CHAIN.days, 7)
	assert_eq(CHAIN.shown_goals, 3)
	assert_true(CHAIN.total_cash() >= 560 and CHAIN.total_cash() <= 650,
		"the chain pays about $600 in all (Jared, #494): %d" % CHAIN.total_cash())
	var conditions: Dictionary[int, bool] = {}
	for goal: OpeningGoal in CHAIN.goals:
		conditions[goal.condition] = true
		assert_true(goal.reward_cash > 0 and goal.reward_xp > 0, "%s pays cash and a little XP" % goal.id)
		assert_true(goal.reward_xp <= 20, "%s: only a little XP" % goal.id)
	for condition: int in range(OpeningGoal.Condition.PRICE_CHANGED, OpeningGoal.Condition.FIVE_STAR_REVIEWS_TODAY + 1):
		assert_true(conditions.has(condition), "every condition has a goal: %d" % condition)


func test_each_goal_triggers_from_its_own_condition_and_pays_once() -> void:
	var cases: Array[Array] = [
		[&"change_price", OpeningGoal.Condition.PRICE_CHANGED, 1.0],
		[&"place_decor", OpeningGoal.Condition.DECOR_PLACED, 1.0],
		[&"serve_15", OpeningGoal.Condition.SERVED_TODAY, 15.0],
		[&"drink_on_menu", OpeningGoal.Condition.DRINK_ON_MENU, 1.0],
		[&"owner_on_floor", OpeningGoal.Condition.OWNER_ON_FLOOR, 1.0],
		[&"grow_together", OpeningGoal.Condition.GROW_TOGETHER, 1.0],
		[&"five_star_day", OpeningGoal.Condition.FIVE_STAR_REVIEWS_TODAY, 5.0],
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
	assert_true(state.observe(OpeningGoal.Condition.FIVE_STAR_REVIEWS_TODAY, 4.0, CHAIN).is_empty())
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
	assert_true(OpeningWeek.legacy_for_day(1, CHAINS).is_active())
	assert_true(OpeningWeek.legacy_for_day(7, CHAINS).is_active())
	assert_eq(OpeningWeek.legacy_for_day(7, CHAINS).current(CHAINS), CHAIN)
	assert_false(OpeningWeek.legacy_for_day(8, CHAINS).is_active())
	assert_false(OpeningWeek.legacy_for_day(40, CHAINS).is_active())
	assert_false(OpeningWeek.legacy_for_day(1, null).is_active())


func _ids(goals: Array[OpeningGoal]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for goal: OpeningGoal in goals:
		ids.append(goal.id)
	return ids


# --- Week 2 (#514) -----------------------------------------------------------

func test_week_two_is_authored_and_pays_about_seven_hundred() -> void:
	assert_true(CHAINS.is_valid())
	assert_eq(CHAINS.chains, [CHAIN, WEEK_TWO] as Array[OpeningWeekSet], "Opening week, then Week 2")
	assert_eq(CHAINS.natural_start(0), 1)
	assert_eq(CHAINS.natural_start(1), 8, "Week 2's window is days 8 to 14")
	assert_true(WEEK_TWO.is_valid())
	assert_eq(WEEK_TWO.id, &"week_two")
	assert_eq(WEEK_TWO.title, "Week 2")
	assert_eq(WEEK_TWO.days, 7)
	assert_eq(WEEK_TWO.shown_goals, 3)
	assert_eq(_ids(WEEK_TWO.goals), [&"bigger_lease", &"lay_floor", &"big_table", &"fried_dish",
		&"hire_cleaner", &"seat_group", &"serve_30", &"calm_day"] as Array[StringName], "the approved order")
	var rewards: Array[int] = []
	for goal: OpeningGoal in WEEK_TWO.goals:
		rewards.append(goal.reward_cash)
		assert_true(goal.reward_xp > 0 and goal.reward_xp <= 20, "%s: a little XP" % goal.id)
	assert_eq(rewards, [150, 60, 60, 80, 60, 60, 100, 130] as Array[int], "the approved rewards")
	assert_eq(WEEK_TWO.total_cash(), 700)
	assert_eq(WEEK_TWO.by_id(&"big_table").item_ids, [&"table_4", &"round_table"] as Array[StringName])
	assert_eq(WEEK_TWO.by_id(&"fried_dish").station_type, &"fryer")
	assert_eq(WEEK_TWO.by_id(&"hire_cleaner").role, &"cleaner")
	assert_eq(WEEK_TWO.by_id(&"calm_day").leave_reasons, [&"waited_too_long"] as Array[StringName])
	assert_eq(WEEK_TWO.by_id(&"calm_day").target, 3.5)
	assert_eq(WEEK_TWO.by_id(&"calm_day").max_turned_away, 0, "nobody gives up waiting (Jared)")
	assert_eq(WEEK_TWO.by_id(&"lay_floor").target, 6.0)
	assert_eq(WEEK_TWO.by_id(&"serve_30").target, 30.0)
	assert_eq(WEEK_TWO.by_id(&"seat_group").target, 2.0)


func test_each_week_two_goal_triggers_from_its_own_condition_and_pays_once() -> void:
	var cases: Array[Array] = [
		[&"bigger_lease", OpeningGoal.Condition.LEASE_EXPANDED, 1.0],
		[&"lay_floor", OpeningGoal.Condition.FLOOR_ADDED, 6.0],
		[&"big_table", OpeningGoal.Condition.ITEM_PLACED, 1.0],
		[&"fried_dish", OpeningGoal.Condition.DISH_AT_STATION, 1.0],
		[&"hire_cleaner", OpeningGoal.Condition.STAFF_ROLE, 1.0],
		[&"seat_group", OpeningGoal.Condition.GROUP_SEATED, 2.0],
		[&"serve_30", OpeningGoal.Condition.SERVED_TODAY, 30.0],
		[&"calm_day", OpeningGoal.Condition.CALM_DAY_STARS, 3.5],
	]
	for row: Array in cases:
		var state: OpeningWeek = _week_two()
		var met: Array[OpeningGoal] = state.observe(row[1], row[2], WEEK_TWO, row[0])
		assert_eq(met.size(), 1, "%s triggers alone" % row[0])
		if met.size() == 1:
			assert_eq(met[0].id, row[0])
			assert_eq(state.pending_xp, met[0].reward_xp)
		assert_true(state.observe(row[1], row[2], WEEK_TWO, row[0]).is_empty(), "%s pays once only" % row[0])
		assert_eq(state.completed_ids(), [row[0]] as Array[StringName], "nothing else is met")


func test_week_two_thresholds() -> void:
	var state: OpeningWeek = _week_two()
	var observations: Array[Array] = [
		[OpeningGoal.Condition.FLOOR_ADDED, 5.0, &""],
		[OpeningGoal.Condition.GROUP_SEATED, 1.0, &""],
		[OpeningGoal.Condition.SERVED_TODAY, 29.0, &""],
		[OpeningGoal.Condition.CALM_DAY_STARS, 3.4, &"calm_day"],
		[OpeningGoal.Condition.CALM_DAY_STARS, 0.0, &"calm_day"],
		[OpeningGoal.Condition.LEASE_EXPANDED, 0.0, &""],
		[OpeningGoal.Condition.STAFF_ROLE, 0.0, &"hire_cleaner"],
		[OpeningGoal.Condition.ITEM_PLACED, 0.0, &"big_table"],
		[OpeningGoal.Condition.ITEM_PLACED, -2.0, &"big_table"],
	]
	for row: Array in observations:
		assert_true(state.observe(row[0], row[1], WEEK_TWO, row[2]).is_empty(), "below target: %s" % str(row))
	assert_true(state.observe(OpeningGoal.Condition.ITEM_PLACED, 1.0, WEEK_TWO, &"another_goal").is_empty(),
		"a value for another goal never meets this one")
	assert_true(state.completed_ids().is_empty())
	assert_eq(state.observe(OpeningGoal.Condition.CALM_DAY_STARS, 4.2, WEEK_TWO, &"calm_day").size(), 1)
	assert_eq(state.observe(OpeningGoal.Condition.GROUP_SEATED, 8.0, WEEK_TWO).size(), 1, "a booked party of eight counts")


func test_goal_parameters_are_validated() -> void:
	var goal: OpeningGoal = WEEK_TWO.by_id(&"big_table").duplicate() as OpeningGoal
	assert_true(goal.is_valid())
	goal.item_ids = []
	assert_false(goal.is_valid(), "an item goal names its items")
	goal = WEEK_TWO.by_id(&"fried_dish").duplicate() as OpeningGoal
	goal.station_type = &""
	assert_false(goal.is_valid(), "a station goal names its station")
	goal = WEEK_TWO.by_id(&"hire_cleaner").duplicate() as OpeningGoal
	goal.role = &""
	assert_false(goal.is_valid(), "a staff goal names its role")
	goal = WEEK_TWO.by_id(&"calm_day").duplicate() as OpeningGoal
	goal.target = 5.5
	assert_false(goal.is_valid(), "no rating above five stars")
	goal.target = 3.5
	goal.max_turned_away = -1
	assert_false(goal.is_valid(), "a negative allowance is invalid")
	goal = WEEK_TWO.by_id(&"serve_30").duplicate() as OpeningGoal
	goal.target = 3.5
	assert_false(goal.is_valid(), "only a rating may be fractional")
	var broken: OpeningWeekSet = WEEK_TWO.duplicate() as OpeningWeekSet
	broken.title = ""
	assert_false(broken.is_valid(), "a chain has a title")


func test_week_two_starts_the_morning_after_opening_week_and_runs_seven_days() -> void:
	var state: OpeningWeek = OpeningWeek.starting(CHAINS)
	assert_eq(state.current(CHAINS), CHAIN)
	assert_eq(state.last_day(CHAIN), 7)
	assert_false(state.advance(7, CHAINS), "an active chain does not hand over")
	assert_true(state.end_if_due(8, CHAIN))
	assert_true(state.advance(8, CHAINS), "the morning after day 7")
	assert_true(state.is_active())
	assert_eq(state.current(CHAINS), WEEK_TWO)
	assert_eq(state.start_day, 8)
	assert_eq(state.last_day(WEEK_TWO), 14, "days 8 to 14")
	assert_true(state.completed_ids().is_empty(), "a fresh list of goals")
	assert_false(state.end_if_due(14, WEEK_TWO))
	assert_true(state.end_if_due(15, WEEK_TWO))
	assert_false(state.advance(15, CHAINS), "no chain after Week 2")
	assert_eq(state.status, OpeningWeek.Status.FINISHED)
	assert_null(state.current(CHAINS))
	assert_false(state.advance(16, CHAINS))


func test_an_early_finish_starts_week_two_the_next_morning() -> void:
	var state: OpeningWeek = OpeningWeek.starting(CHAINS)
	for goal: OpeningGoal in CHAIN.goals:
		state.observe(goal.condition, goal.target, CHAIN)
	var xp: int = state.pending_xp
	assert_true(state.end_if_due(4, CHAIN), "every goal done on day 4")
	assert_true(state.advance(5, CHAINS))
	assert_eq(state.start_day, 5)
	assert_eq(state.last_day(WEEK_TWO), 11, "seven days from its start")
	assert_eq(state.pending_xp, xp, "waiting XP is never lost in the hand-over")


func test_old_saves_get_week_two_inside_its_window() -> void:
	for day: int in [8, 12, 14]:
		var state: OpeningWeek = OpeningWeek.legacy_for_day(day, CHAINS)
		assert_true(state.advance(day, CHAINS), "day %d is inside Week 2's window" % day)
		assert_eq(state.current(CHAINS), WEEK_TWO)
		assert_eq(state.start_day, 8)
		assert_eq(state.last_day(WEEK_TWO), 14, "an old save keeps the days that remain")
	var late: OpeningWeek = OpeningWeek.legacy_for_day(15, CHAINS)
	assert_false(late.advance(15, CHAINS), "past day 14 there is no chain")
	assert_false(late.is_active())
	# A version-1 save (Opening week alone) that ended early on day 4.
	var v1: OpeningWeek = OpeningWeek.new()
	assert_true(v1.from_dict({"version": 1, "status": "ended", "completed": ["change_price"], "pending_xp": 0}))
	assert_eq(v1.current(CHAINS), CHAIN, "version 1 held the Opening week")
	assert_eq(v1.start_day, 1)
	assert_true(v1.advance(5, CHAINS))
	assert_eq([v1.start_day, v1.last_day(WEEK_TWO)], [5, 11])
	var v1_active: OpeningWeek = OpeningWeek.new()
	assert_true(v1_active.from_dict({"version": 1, "status": "active", "completed": ["change_price"], "pending_xp": 5}))
	assert_true(v1_active.is_active())
	assert_eq(v1_active.completed_ids(), [&"change_price"] as Array[StringName])
	assert_eq(v1_active.pending_xp, 5)
	assert_eq(v1_active.to_dict()["version"], 2, "it saves as version 2")


func test_version_two_round_trip_and_bad_rows() -> void:
	var state: OpeningWeek = OpeningWeek.legacy_for_day(9, CHAINS)
	state.advance(9, CHAINS)
	state.observe(OpeningGoal.Condition.SERVED_TODAY, 40.0, WEEK_TWO)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	assert_eq(saved["chain"], "week_two")
	assert_eq(int(saved["start_day"]), 8)
	var loaded: OpeningWeek = OpeningWeek.new()
	assert_true(loaded.from_dict(saved))
	assert_eq(loaded.to_dict(), state.to_dict())
	assert_eq(loaded.current(CHAINS), WEEK_TWO)
	var finished: OpeningWeek = OpeningWeek.new()
	assert_true(finished.from_dict(OpeningWeek.ended().to_dict()))
	assert_eq(finished.status, OpeningWeek.Status.FINISHED)
	var good: Dictionary = {"version": 2, "chain": "week_two", "start_day": 8, "status": "active",
		"completed": [], "pending_xp": 0}
	for change: Array in [["version", 3], ["chain", 1], ["start_day", 0], ["start_day", 1.5],
			["status", "paused"], ["completed", "x"]]:
		var bad: Dictionary = good.duplicate()
		bad[change[0]] = change[1]
		assert_false(OpeningWeek.new().from_dict(bad), "rejects %s" % str(change))
	var short: Dictionary = good.duplicate()
	short.erase("chain")
	assert_false(OpeningWeek.new().from_dict(short), "a version-2 row has every field")
	assert_false(OpeningWeek.new().from_dict({"version": 1, "status": "finished", "completed": [], "pending_xp": 0}),
		"version 1 never finished")


func test_an_unknown_chain_retires_quietly() -> void:
	var state: OpeningWeek = OpeningWeek.new()
	assert_true(state.from_dict({"version": 2, "chain": "removed_chain", "start_day": 8, "status": "active",
		"completed": [], "pending_xp": 0}))
	assert_null(state.current(CHAINS))
	assert_true(state.end_if_due(9, state.current(CHAINS)))
	assert_false(state.advance(9, CHAINS), "it never restarts the first chain")
	assert_eq(state.status, OpeningWeek.Status.FINISHED)


func test_creative_and_tools_have_no_chain() -> void:
	var state: OpeningWeek = OpeningWeek.ended()
	assert_false(state.is_active())
	assert_false(state.end_if_due(9, WEEK_TWO))
	assert_false(state.advance(9, CHAINS), "a finished state never starts a chain")
	assert_null(state.current(CHAINS))


func _week_two() -> OpeningWeek:
	var state: OpeningWeek = OpeningWeek.legacy_for_day(8, CHAINS)
	state.advance(8, CHAINS)
	return state
