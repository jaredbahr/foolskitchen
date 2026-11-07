extends TestCase
## Actual default day-one observations exercise every authored challenge,
## including unselected definitions, without replaying service for each goal.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const POOL: WeeklyChallengePool = preload("res://data/balance/weekly_challenges.tres")
var _main: Node


func after_each() -> void:
	_close()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _close() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func test_no_authored_weekly_goal_can_complete_on_default_day_one() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	for seed_value: int in [1, 7, 42]:
		_main = MAIN.instantiate()
		_main.set("use_saves", false)
		_main.set("new_game_seed_override", seed_value)
		tree.root.add_child(_main)
		_main.call("start")
		Clock.set_speed(0)
		var menu: Array[RecipeDef] = (_main.get("menu_settings") as MenuSettings).enabled_recipes()
		assert_false(menu.is_empty())
		assert_true(Clock.sim.start_service())
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < 30:
			_main.call("run_ticks", 1000)
			batches += 1
		assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
		assert_eq(Economy.ledger.day_totals(1).get(Ledger.WEEKLY_CHALLENGE_BONUS, 0), 0,
			"seed %d: the real selected challenge pays nothing on day one" % seed_value)
		var report: DayReport = _main.get("shown_report") as DayReport
		var observation: MilestoneDay = _main.call("_milestone_observation", report.purchase_basis_operating_profit())
		assert_true(observation.is_valid())
		print("WEEKLY DEFAULT DAY ONE ", JSON.stringify({"seed": seed_value,
			"served": observation.served_today, "lost": observation.lost_today,
			"good_reviews": observation.good_reviews_today, "operating_profit": observation.operating_profit,
			"paid_dishes": observation.dishes_sold, "weekly_reward": Economy.ledger.day_totals(1).get(Ledger.WEEKLY_CHALLENGE_BONUS, 0)}))
		for definition: WeeklyChallenge in POOL.challenges:
			if definition.kind == WeeklyChallenge.Kind.SELL_DISH:
				for recipe: RecipeDef in menu:
					_assert_not_complete(definition, [recipe] as Array[RecipeDef], observation, seed_value)
			else:
				_assert_not_complete(definition, [] as Array[RecipeDef], observation, seed_value)
		_close()


func _assert_not_complete(definition: WeeklyChallenge, menu: Array[RecipeDef],
		observation: MilestoneDay, seed_value: int) -> void:
	var isolated: WeeklyChallengePool = WeeklyChallengePool.new()
	isolated.challenges = [definition] as Array[WeeklyChallenge]
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 326
	var state: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(state.begin_week(1, 1, isolated, menu, random))
	var outcome: Dictionary = state.apply_day(observation)
	assert_false(outcome.is_empty())
	assert_false(bool(outcome.get("completed", false)),
		"seed %d: %s (%s) cannot complete on default day one; progress %d / %d" % [
			seed_value, definition.id, state.dish_id, state.progress, state.target])
	assert_eq(int(outcome.get("reward_cash", 0)), 0)
