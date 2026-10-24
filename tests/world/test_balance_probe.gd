extends TestCase
## One real day proves the manual probe drives the production session.

const MAIN_SCENE: PackedScene = preload("res://src/world/main.tscn")


func after_each() -> void:
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_default_seed_one_serves_a_guest() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var row: Dictionary = BalanceProbe.run_case(tree, 1, "default", 1)
	assert_false(row.has("error"), str(row.get("error", "")))
	assert_true(int(row.get("served", 0)) > 0, "the default run serves real guests")


func test_default_and_extra_cleaner_use_the_run_seed_before_service() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main: Node = MAIN_SCENE.instantiate()
	main.set("use_saves", false)
	tree.root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	assert_not_null(sim)
	if sim == null:
		tree.root.remove_child(main)
		main.free()
		return
	var startup_rng: RandomNumberGenerator = sim.cleanliness.get("_rng") as RandomNumberGenerator
	GameState.new_run(1)
	assert_false(ProbeSetups.apply("unknown", main), "invalid set-up does not rebind")
	assert_true(sim.cleanliness.get("_rng") == startup_rng)
	assert_true(ProbeSetups.apply("default", main))
	var default_rng: RandomNumberGenerator = GameState.rng(&"cleanliness")
	assert_true(sim.cleanliness.get("_rng") == default_rng)
	assert_eq(sim.cleanliness.spot_count(), 0)
	GameState.new_run(7)
	assert_true(ProbeSetups.apply("extra_cleaner", main))
	var cleaner_rng: RandomNumberGenerator = GameState.rng(&"cleanliness")
	assert_true(sim.cleanliness.get("_rng") == cleaner_rng)
	assert_false(cleaner_rng == default_rng)
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	var cleaner_count: int = 0
	for member: StaffMember in roster.members():
		if member.role == &"cleaner":
			cleaner_count += 1
			assert_eq(member.skill, 3)
			assert_eq(member.wage, sim.pricing_tuning.staff_wage(&"cleaner", 3))
	assert_eq(cleaner_count, 1, "the extra-cleaner scenario hires exactly one cleaner")
	tree.root.remove_child(main)
	main.free()


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
