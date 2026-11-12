extends TestCase
## #306: real production days that used to lock people in place for good
## (found by tools/liveness_soak.sh). Nobody who wants to move may go longer
## than LIMIT service ticks without getting closer to their real goal (so a
## yield-return shuffle fails too, not only standing still), and the backstop
## may not "fix" jams by sending guests home: at most MAX_GIVE_UPS per case.
## coffee_shop seed 1: an idle server stepping off a cleaned stool waited
## forever on a diagonal cut by the counter (day 3). default seed 20: the
## street door jammed with leaving guests and arriving parties (day 10).
## coffee_shop seed 2 with a health inspector every day: the visitor walks
## the busy room and leaves on its own feet, never taken out as blocked.
## bar seed 2: leaving guests in the busy bar corridor waited over 700 ticks
## (day 11) while newer escapes took the held way from them (#317).
## bar seed 8 with the soak's seeded morning edits: a one-cell way in behind
## the door, queued guests packing the door and the cells beside it, held a
## leaving guest for 884 ticks on day 12 (#322).
## coffee_shop seed 6 with edits: a server waiting for the coffee machine the
## cook had booked stood in the cook's short way to it; the cook went round
## the counter and the backstop sent it back, round and round for 530 ticks
## on day 12 (#453).

const LIMIT: int = 600
## Staff tasks time out at 600 ticks, which would hide a longer staff stall.
const STAFF_LIMIT: int = 450
const MAX_GIVE_UPS: int = 2
const CASES: Array[Dictionary] = [
	{"setup": "coffee_shop", "seed": 1, "days": 3},
	{"setup": "default", "seed": 20, "days": 10},
	{"setup": "coffee_shop", "seed": 2, "days": 2, "inspector": true},
	{"setup": "bar", "seed": 2, "days": 11},
	{"setup": "bar", "seed": 8, "days": 12, "edits": true},
	{"setup": "coffee_shop", "seed": 6, "days": 12, "edits": true},
]


func after_each() -> void:
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_busy_days_that_used_to_deadlock_keep_everyone_moving() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for case: Dictionary in CASES:
		var row: Dictionary = LivenessSoak.run_case(tree, int(case["seed"]), String(case["setup"]),
			int(case["days"]), LIMIT, bool(case.get("edits", false)), 1, bool(case.get("inspector", false)), STAFF_LIMIT)
		var label: String = "%s seed %d%s" % [case["setup"], case["seed"], " (edits)" if case.get("edits", false) else ""]
		assert_false(row.has("error"), "%s: %s" % [label, row.get("error", "")])
		assert_eq(int(row.get("stuck_episodes", -1)), 0,
			"%s: nobody stuck over %d ticks (%s)" % [label, LIMIT, row.get("worst", "")])
		assert_true(int(row.get("max_no_progress", LIMIT + 1)) <= LIMIT)
		assert_true(int(row.get("max_staff_stall", STAFF_LIMIT + 1)) <= STAFF_LIMIT,
			"%s: staff get closer to their goal within %d ticks" % [label, STAFF_LIMIT])
		assert_true(int(row.get("max_goal_stall", LIMIT + 1)) <= LIMIT,
			"%s: everyone gets closer to their goal within %d ticks (max %d)" % [label, LIMIT,
				int(row.get("max_goal_stall", -1))])
		var give_ups: int = int((row.get("reasons", {}) as Dictionary).get("no_way_through", 0))
		assert_true(give_ups <= MAX_GIVE_UPS,
			"%s: %d guests gave up blocked (cap %d)" % [label, give_ups, MAX_GIVE_UPS])
		assert_true(int(row.get("served", 0)) > 0, "%s still serves guests" % label)
		if bool(case.get("inspector", false)):
			assert_eq(int(row.get("inspector_visits", 0)), int(case["days"]), "%s: the inspector came every day" % label)
			assert_eq(int(row.get("inspector_removed", -1)), 0, "%s: the inspector always walked out" % label)
			assert_true(int(row.get("inspector_max_stall", LIMIT + 1)) <= LIMIT,
				"%s: the inspector kept moving (max %d)" % [label, int(row.get("inspector_max_stall", -1))])
