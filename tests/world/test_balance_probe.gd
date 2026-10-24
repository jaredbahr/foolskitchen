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
