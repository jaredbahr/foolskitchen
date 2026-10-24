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
