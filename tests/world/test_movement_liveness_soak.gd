extends TestCase
## #306: real production days that used to lock people in place for good
## (found by tools/liveness_soak.sh). Nobody who wants to move may go longer
## than LIMIT service ticks without getting closer to their real goal (so a
## yield-return shuffle fails too, not only standing still), and the backstop
## may not "fix" jams by sending guests home: at most MAX_GIVE_UPS per case.
## coffee_shop seed 1: an idle server stepping off a cleaned stool waited
## forever on a diagonal cut by the counter (day 3). default seed 20: the
## street door jammed with leaving guests and arriving parties (day 10).

const LIMIT: int = 600
const MAX_GIVE_UPS: int = 2
const CASES: Array[Dictionary] = [
	{"setup": "coffee_shop", "seed": 1, "days": 3},
	{"setup": "default", "seed": 20, "days": 10},
]


func after_each() -> void:
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_busy_days_that_used_to_deadlock_keep_everyone_moving() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for case: Dictionary in CASES:
		var row: Dictionary = LivenessSoak.run_case(tree, int(case["seed"]), String(case["setup"]),
			int(case["days"]), LIMIT, false, 1)
		var label: String = "%s seed %d" % [case["setup"], case["seed"]]
		assert_false(row.has("error"), "%s: %s" % [label, row.get("error", "")])
		assert_eq(int(row.get("stuck_episodes", -1)), 0,
			"%s: nobody stuck over %d ticks (%s)" % [label, LIMIT, row.get("worst", "")])
		assert_true(int(row.get("max_no_progress", LIMIT + 1)) <= LIMIT)
		assert_true(int(row.get("max_goal_stall", LIMIT + 1)) <= LIMIT,
			"%s: everyone gets closer to their goal within %d ticks (max %d)" % [label, LIMIT,
				int(row.get("max_goal_stall", -1))])
		var give_ups: int = int((row.get("reasons", {}) as Dictionary).get("no_way_through", 0))
		assert_true(give_ups <= MAX_GIVE_UPS,
			"%s: %d guests gave up blocked (cap %d)" % [label, give_ups, MAX_GIVE_UPS])
		assert_true(int(row.get("served", 0)) > 0, "%s still serves guests" % label)
