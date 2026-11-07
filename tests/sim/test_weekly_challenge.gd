extends TestCase
## Weekly progress is projected from canonical close-day summaries.

const POOL: WeeklyChallengePool = preload("res://data/balance/weekly_challenges.tres")


func test_pool_covers_every_kind_and_targets_scale_from_the_draw_level() -> void:
	assert_true(POOL.is_valid())
	assert_eq(POOL.challenges.size(), 10)
	var kinds: Dictionary[int, bool] = {}
	for challenge: WeeklyChallenge in POOL.challenges:
		kinds[challenge.kind] = true
		assert_true(challenge.is_valid())
		assert_false(challenge.text_template.contains("_"), "authored player text has no internal IDs")
	for kind: int in range(WeeklyChallenge.Kind.SELL_DISH + 1):
		assert_true(kinds.has(kind), "all five challenge kinds are represented")
	var recipe: RecipeDef = _recipe(&"menu_special", "Menu special")
	for challenge: WeeklyChallenge in POOL.challenges:
		var isolated_pool: WeeklyChallengePool = _pool([challenge])
		var state: WeeklyChallengeState = WeeklyChallengeState.new()
		var selected_menu: Array[RecipeDef] = []
		if challenge.kind == WeeklyChallenge.Kind.SELL_DISH:
			selected_menu.append(recipe)
		assert_true(state.begin_week(1, 1, isolated_pool, selected_menu, _rng()),
			"every authored definition can be selected with its required menu")
		var restored: WeeklyChallengeState = WeeklyChallengeState.new()
		assert_true(restored.from_dict(state.to_dict()), "every authored draw can be saved and restored")
	var scaled: WeeklyChallenge = _challenge(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 12, 4)
	assert_eq(scaled.target_at_level(1), 12)
	assert_eq(scaled.target_at_level(3), 20)
	assert_eq(scaled.target_at_level(1000000), WeeklyChallenge.MAX_TARGET)
	var clean_days: WeeklyChallenge = _challenge(WeeklyChallenge.Kind.NO_LOSS_DAYS, 6, 3)
	assert_true(clean_days.is_valid())
	assert_eq(clean_days.target_at_level(1000000), WeeklyChallengeState.WEEK_DAYS,
		"a clean-day goal cannot exceed the available seven service days")


func test_rotation_is_day_one_then_every_seventh_morning_without_repeating() -> void:
	assert_true(WeeklyChallengeState.rotation_day(1))
	assert_false(WeeklyChallengeState.rotation_day(7))
	assert_true(WeeklyChallengeState.rotation_day(8))
	assert_true(WeeklyChallengeState.rotation_day(15))
	var first: WeeklyChallengeState = WeeklyChallengeState.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 71
	assert_true(first.begin_week(1, 1, POOL, [] as Array[RecipeDef], random))
	var first_id: StringName = first.challenge_id
	assert_eq(first.end_day, 7)
	assert_eq(first.last_evaluated_day, 0)
	var next: WeeklyChallengeState = WeeklyChallengeState.new()
	next.previous_challenge_id = first_id
	assert_true(next.begin_week(8, 2, POOL, [] as Array[RecipeDef], random))
	assert_ne(next.challenge_id, first_id, "a challenge cannot repeat in consecutive weeks")
	assert_eq(next.end_day, 14)
	assert_false(next.begin_week(8, 2, POOL, [] as Array[RecipeDef], random),
		"a second draw cannot reroll the same week's challenge")
	assert_true(first.begin_week(8, 2, POOL, [] as Array[RecipeDef], random),
		"a stale unfinished week is replaced at the next rotation without paying it")
	assert_ne(first.challenge_id, first_id)
	assert_eq(first.start_day, 8)
	assert_false(first.begin_week(1, 2, POOL, [] as Array[RecipeDef], random),
		"a rotation cannot move backwards")


func test_serve_goal_keeps_the_weekly_max_and_completes_once() -> void:
	var state: WeeklyChallengeState = _started(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 10)
	var first: Dictionary = state.apply_day(_day(1, 12))
	assert_true(bool(first["completed"]))
	assert_eq(state.progress, 12)
	assert_eq(int(first["reward_cash"]), 25)
	assert_true(state.apply_day(_day(1, 99)).is_empty(), "completed reward cannot be paid twice")
	assert_false(state.begin_week(1, 1, _pool([_challenge(0, 5)]), [] as Array[RecipeDef], _rng()),
		"the same state cannot be rerolled on its draw day")


func test_signed_week_profit_accumulates_losses_and_no_loss_days_use_existing_rule() -> void:
	var profit: WeeklyChallengeState = _started(WeeklyChallenge.Kind.OPERATING_PROFIT, 100)
	assert_false(bool(profit.apply_day(_day(1, 0, 0, 60))["completed"]))
	assert_eq(profit.progress, 60)
	assert_false(bool(profit.apply_day(_day(2, 0, 0, -45))["completed"]))
	assert_eq(profit.progress, 15, "an operating loss reduces weekly progress")
	assert_true(bool(profit.apply_day(_day(3, 0, 0, 85))["completed"]))

	var clean: WeeklyChallengeState = _started(WeeklyChallenge.Kind.NO_LOSS_DAYS, 2)
	assert_false(bool(clean.apply_day(_day(1, 0, 0, 0, 0, {}, 1))["completed"]))
	assert_eq(clean.progress, 0, "a lost guest does not count as a clean day")
	assert_false(bool(clean.apply_day(_day(2, 0, 0, 0, 0, {}, 0))["completed"]))
	assert_eq(clean.progress, 1)
	assert_eq(clean.projected_progress(_day(3, 0, 0, 0, 0, {}, 0)), 1,
		"an open clean-looking day is not counted before the close commits it")
	assert_true(bool(clean.apply_day(_day(3, 0, 0, 0, 0, {}, 0))["completed"]))
	assert_eq(clean.projected_progress(_day(4, 0, 0, 0, 0, {}, 0)), 2,
		"the next view shows the clean day after real close committed it")


func test_good_reviews_and_frozen_paid_recipe_use_close_day_summary() -> void:
	var reviews: WeeklyChallengeState = _started(WeeklyChallenge.Kind.GOOD_REVIEWS, 3)
	assert_false(bool(reviews.apply_day(_day(1, 4, 0, 0, 2))["completed"]))
	assert_true(bool(reviews.apply_day(_day(2, 2, 0, 0, 1))["completed"]))

	var recipe: RecipeDef = _recipe(&"tomato_soup", "Tomato soup")
	var sale: WeeklyChallengeState = _started(WeeklyChallenge.Kind.SELL_DISH, 3, recipe)
	assert_eq(sale.dish_id, &"tomato_soup")
	assert_eq(sale.text, "Sell 3 Tomato soup this week")
	assert_false(bool(sale.apply_day(_day(1, 0, 0, 0, 0, {&"burger": 8, &"tomato_soup": 2}))["completed"]))
	assert_true(bool(sale.apply_day(_day(2, 0, 0, 0, 0, {&"tomato_soup": 1}))["completed"]))


func test_last_day_expiry_and_midweek_legacy_start_have_no_fabricated_progress() -> void:
	var expired: WeeklyChallengeState = _started(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 99)
	var outcome: Dictionary = {}
	for day: int in range(1, 8):
		outcome = expired.apply_day(_day(day, 0))
	assert_true(bool(outcome["expired"]))
	assert_eq(expired.status, WeeklyChallengeState.Status.EXPIRED)
	assert_eq(expired.progress, 0)
	assert_eq(int(outcome["reward_cash"]), 0)
	assert_true(expired.apply_day(_day(7, 99)).is_empty())

	var legacy: WeeklyChallengeState = WeeklyChallengeState.new()
	var random: RandomNumberGenerator = _rng()
	assert_true(legacy.begin_legacy_week(4, 1, POOL, [] as Array[RecipeDef], random))
	assert_eq(legacy.start_day, 1)
	assert_eq(legacy.end_day, 7)
	assert_eq(legacy.last_evaluated_day, 3)
	assert_eq(legacy.progress, 0)
	assert_eq(legacy.days_left(4), 4)
	var rng_after_draw: int = random.state
	assert_false(legacy.begin_legacy_week(4, 1, POOL, [] as Array[RecipeDef], random))
	assert_eq(random.state, rng_after_draw, "legacy migration cannot redraw on repeated setup")


func test_last_supported_week_round_trips_and_unavailable_dish_pool_does_not_draw() -> void:
	var latest: WeeklyChallengeState = WeeklyChallengeState.new()
	var latest_rng: RandomNumberGenerator = _rng()
	assert_true(latest.begin_week(WeeklyChallengeState.MAX_DAY - 7, 1,
		_pool([_challenge(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 4)]), [] as Array[RecipeDef], latest_rng))
	assert_true(latest.end_day <= WeeklyChallengeState.MAX_DAY,
		"the last legal weekly rotation remains within the saved day bound")
	var latest_restored: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(latest_restored.from_dict(latest.to_dict()),
		"a challenge created at the latest legal rotation day remains restorable")
	var latest_legacy: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(latest_legacy.begin_legacy_week(WeeklyChallengeState.MAX_DAY - 1, 1,
		_pool([_challenge(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 4)]), [] as Array[RecipeDef], _rng()))
	assert_eq(latest_legacy.end_day, WeeklyChallengeState.MAX_DAY - 1)
	var latest_legacy_restored: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(latest_legacy_restored.from_dict(latest_legacy.to_dict()),
		"late days in the final legal week still migrate to a restorable challenge")
	var max_day_legacy: WeeklyChallengeState = WeeklyChallengeState.new()
	var max_day_rng: RandomNumberGenerator = _rng()
	var max_day_rng_before: int = max_day_rng.state
	assert_false(max_day_legacy.begin_legacy_week(WeeklyChallengeState.MAX_DAY, 1,
		_pool([_challenge(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 4)]), [] as Array[RecipeDef], max_day_rng),
		"the final rotation cannot create a week whose end exceeds MAX_DAY")
	assert_eq(max_day_rng.state, max_day_rng_before,
		"an out-of-range week is rejected before consuming RNG")
	var dish_only: WeeklyChallengeState = WeeklyChallengeState.new()
	var no_dish_rng: RandomNumberGenerator = _rng()
	var before: int = no_dish_rng.state
	assert_false(dish_only.begin_week(1, 1,
		_pool([_challenge(WeeklyChallenge.Kind.SELL_DISH, 4)]), [] as Array[RecipeDef], no_dish_rng))
	assert_eq(no_dish_rng.state, before, "an unavailable dish goal fails before drawing or consuming RNG")
	assert_false(dish_only.begin_legacy_week(4, 1,
		_pool([_challenge(WeeklyChallenge.Kind.SELL_DISH, 4)]), [] as Array[RecipeDef], no_dish_rng))
	assert_eq(no_dish_rng.state, before, "legacy setup also preserves RNG when no menu dish is eligible")
	var oversized_id: WeeklyChallenge = _challenge(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 4)
	oversized_id.id = StringName("x".repeat(WeeklyChallenge.MAX_ID_LENGTH + 1))
	assert_false(oversized_id.is_valid(), "authored IDs share the strict saved-state bound")
	var long_recipe: RecipeDef = _recipe(&"tea", "x".repeat(WeeklyChallenge.MAX_DISH_NAME_LENGTH + 1))
	var long_name_rng: RandomNumberGenerator = _rng()
	var long_name_before: int = long_name_rng.state
	assert_false(dish_only.begin_week(1, 1,
		_pool([_challenge(WeeklyChallenge.Kind.SELL_DISH, 4)]), [long_recipe] as Array[RecipeDef], long_name_rng))
	assert_eq(long_name_rng.state, long_name_before,
		"a dish that cannot fit into a restorable challenge is rejected before RNG draw")
	var padded_name: RecipeDef = _recipe(&"tea", "  Tea  ")
	var padded_state: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(padded_state.begin_week(1, 1,
		_pool([_challenge(WeeklyChallenge.Kind.SELL_DISH, 4)]), [padded_name] as Array[RecipeDef], _rng()))
	assert_eq(padded_state.dish_name, "Tea", "the frozen player-facing name is trimmed before save")
	var padded_restored: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(padded_restored.from_dict(padded_state.to_dict()))


func test_state_round_trip_and_atomic_rejection_preserve_frozen_week() -> void:
	var original: WeeklyChallengeState = _started(WeeklyChallenge.Kind.SELL_DISH, 8, _recipe(&"tea", "Tea"))
	assert_false(bool(original.apply_day(_day(1, 0, 0, 0, 0, {&"tea": 2}))["completed"]))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(original.to_dict()))
	var restored: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(restored.from_dict(snapshot))
	assert_eq(restored.to_dict(), original.to_dict())
	var before: Dictionary = restored.to_dict()
	snapshot["target"] = -1
	assert_false(restored.from_dict(snapshot))
	assert_eq(restored.to_dict(), before, "a rejected restore does not partly install fields")
	var negative_count: Dictionary = before.duplicate(true)
	negative_count["progress"] = -1
	assert_false(restored.from_dict(negative_count), "count goals cannot restore negative progress")
	var negative_profit: WeeklyChallengeState = _started(WeeklyChallenge.Kind.OPERATING_PROFIT, 100)
	negative_profit.apply_day(_day(1, 0, 0, -45))
	var negative_profit_restored: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(negative_profit_restored.from_dict(negative_profit.to_dict()),
		"signed operating profit progress can be negative and round-trips")
	var impossible_clean_target: Dictionary = before.duplicate(true)
	impossible_clean_target["kind"] = WeeklyChallenge.Kind.NO_LOSS_DAYS
	impossible_clean_target["target"] = 8
	impossible_clean_target["dish_id"] = ""
	impossible_clean_target["dish_name"] = ""
	impossible_clean_target["text"] = "Finish 8 days without losing a guest"
	assert_false(restored.from_dict(impossible_clean_target),
		"saved clean-day challenges cannot exceed one service week")
	assert_false(restored.apply_day(_day(3, 0)).size() > 0,
		"a skipped close day cannot silently advance progress")
	var unserved_positive_review: MilestoneDay = _day(1, 0)
	unserved_positive_review.good_reviews_today = 1
	assert_true(unserved_positive_review.is_valid(),
		"the observation validates fields independently without imposing a new cross-field rule")
	var excessive_reviews: MilestoneDay = _day(1, 0)
	excessive_reviews.good_reviews_today = MilestoneDay.MAX_COUNT + 1
	assert_false(excessive_reviews.is_valid(), "review observations remain independently bounded")
	var overflowing_sales: MilestoneDay = _day(1, 0, 0, 0, 0,
		{&"tea": MilestoneDay.MAX_COUNT, &"soup": 1})
	assert_false(overflowing_sales.is_valid(), "aggregate paid sales cannot overflow observation bounds")


func test_settlement_is_prepared_without_mutating_live_state_and_pays_once() -> void:
	var live: WeeklyChallengeState = _started(WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, 1)
	var before: Dictionary = live.to_dict()
	var settlement: WeeklyChallengeSettlement = WeeklyChallengeSettlement.prepare(live, _day(1, 1), 10)
	assert_not_null(settlement)
	if settlement == null:
		return
	assert_eq(live.to_dict(), before, "preparation is pure")
	assert_true(settlement.completed)
	assert_eq(settlement.cash_reward, 25)
	assert_eq(settlement.report_text, "Weekly challenge: +$25")
	assert_eq(settlement.state.status, WeeklyChallengeState.Status.COMPLETED)
	assert_null(WeeklyChallengeSettlement.prepare(settlement.state, _day(1, 1), 35),
		"an already completed close has no second settlement")
	assert_null(WeeklyChallengeSettlement.prepare(live, _day(1, 1), 9223372036854775807),
		"the cash overflow is refused before state installation")


func _started(kind: int, target: int, recipe: RecipeDef = null) -> WeeklyChallengeState:
	var challenge: WeeklyChallenge = _challenge(kind, target)
	var state: WeeklyChallengeState = WeeklyChallengeState.new()
	var menu: Array[RecipeDef] = []
	if recipe != null:
		menu.append(recipe)
	assert_true(state.begin_week(1, 1, _pool([challenge]), menu, _rng()))
	return state


func _challenge(kind: int, target: int, per_level: int = 0) -> WeeklyChallenge:
	var challenge: WeeklyChallenge = WeeklyChallenge.new()
	challenge.id = StringName("goal_%d_%d" % [kind, target])
	challenge.kind = kind
	challenge.text_template = "Sell {target} {dish} this week" if kind == WeeklyChallenge.Kind.SELL_DISH \
		else "Reach {target} this week"
	challenge.base_target = target
	challenge.per_level = per_level
	challenge.reward_cash = 25
	return challenge


func _pool(challenges: Array[WeeklyChallenge]) -> WeeklyChallengePool:
	var pool: WeeklyChallengePool = WeeklyChallengePool.new()
	pool.challenges = challenges
	return pool


func _recipe(id: StringName, name: String) -> RecipeDef:
	var recipe: RecipeDef = RecipeDef.new()
	recipe.id = id
	recipe.display_name = name
	return recipe


func _day(day: int, served: int, lost: int = 0, profit: int = 0,
		good_reviews: int = 0, sales: Dictionary[StringName, int] = {}, clean_loss: int = -1) -> MilestoneDay:
	var observation: MilestoneDay = MilestoneDay.new()
	observation.day = day
	observation.served_today = served
	observation.lost_today = clean_loss if clean_loss >= 0 else lost
	observation.operating_profit = profit
	observation.good_reviews_today = good_reviews
	observation.dishes_sold = sales.duplicate()
	return observation


func _rng() -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 426
	return random
