extends TestCase
## One real day proves the manual probe drives the production session.


func after_each() -> void:
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_default_seed_one_serves_a_guest() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var row: Dictionary = BalanceProbe.run_case(tree, 1, "default", 1)
	assert_false(row.has("error"), str(row.get("error", "")))
	assert_true(int(row.get("served", 0)) > 0, "the default run serves real guests")
	assert_true(row.has("owner_xp") and row["owner_xp"] is int)
	assert_true(int(row["owner_xp"]) >= 0)
	assert_true(row.has("owner_level") and row["owner_level"] is int)
	var level: int = int(row["owner_level"])
	assert_true(level >= 1)
	assert_true(row.has("level_days") and row["level_days"] is Dictionary)
	var level_days: Dictionary = row["level_days"]
	assert_eq(level_days.size(), maxi(0, mini(level, 6) - 1))
	for reached: int in range(2, mini(level, 6) + 1):
		assert_eq(level_days.get(reached), 1, "a level reached in a one-day probe belongs to day one")
	var repeated: Dictionary = BalanceProbe.run_case(tree, 1, "default", 1)
	assert_false(repeated.has("error"), str(repeated.get("error", "")))
	assert_eq(repeated["owner_xp"], row["owner_xp"], "the explicit seed fixes review and owner XP draws")
	assert_eq(repeated["owner_level"], level)
	assert_eq(repeated["level_days"], level_days)


func test_same_seed_replays_probe_output_and_consumes_its_review_stream() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	GameState.new_run(86005)
	var initial_review_state: int = GameState.rng(&"reviews").state
	var first: Dictionary = BalanceProbe.run_case(tree, 86005, "default", 2)
	assert_false(first.has("error"), str(first.get("error", "")))
	var first_review_state: int = GameState.rng(&"reviews").state
	assert_true(first_review_state != initial_review_state,
		"the probe must use its reseeded review stream for real guests")
	var repeated: Dictionary = BalanceProbe.run_case(tree, 86005, "default", 2)
	assert_false(repeated.has("error"), str(repeated.get("error", "")))
	assert_eq(JSON.stringify(repeated), JSON.stringify(first))
	assert_eq(GameState.rng(&"reviews").state, first_review_state)
