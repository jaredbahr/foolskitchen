extends TestCase
## One real day proves the manual probe drives the production session.

const MAIN_SCENE: PackedScene = preload("res://src/world/main.tscn")


func after_each() -> void:
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_default_seed_one_serves_a_guest() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var row: Dictionary = BalanceProbe.run_case(tree, 1, "default", 1, 3, Vector2i(-1, -1), 1.0, true)
	assert_false(row.has("error"), str(row.get("error", "")))
	assert_true(int(row.get("served", 0)) > 0, "the default run serves real guests")
	var staff_rows: Array = row.get("staff_growth", [])
	assert_true(staff_rows.size() >= 2, "the same real day includes both starter staff")
	var completed: int = 0
	for staff: Dictionary in staff_rows:
		assert_eq(int(staff["day"]), 1)
		assert_true(int(staff["level"]) >= 1 and int(staff["level"]) <= 5)
		assert_true(int(staff["earned"]) >= int(staff["tasks"]))
		completed += int(staff["tasks"])
	assert_true(completed > 0, "the trace observes genuine completed service work")
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


func test_staff_trace_observes_once_only_board_completion_without_awarding_xp() -> void:
	var roster: StaffRoster = StaffRoster.new()
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["..."])))
	var cook: StaffAgent = StaffAgent.new(&"cook", 3)
	cook.member_id = &"starter_cook"
	world.add_agent(cook)
	var owner: OwnerAgent = OwnerAgent.new()
	world.add_agent(owner)
	var trace: BalanceProbe.StaffTrace = BalanceProbe.StaffTrace.new(world)
	world.board.task_completed.connect(trace.on_task_completed)
	var done: SimTask = SimTask.new(&"cook", &"cook", "Finished meal")
	world.board.post(done, 0)
	assert_true(world.board.claim(done, cook.id, 0))
	world.board.complete(done)
	world.board.complete(done)
	var cancelled: SimTask = SimTask.new(&"cook", &"cook", "Cancelled meal")
	world.board.post(cancelled, 0)
	assert_true(world.board.claim(cancelled, cook.id, 0))
	world.board.cancel(cancelled)
	world.board.complete(cancelled)
	var owner_done: SimTask = SimTask.new(&"cook", &"any", "Owner work")
	world.board.post(owner_done, 0)
	assert_true(world.board.claim(owner_done, owner.id, 0))
	world.board.complete(owner_done)
	world.board.task_completed.disconnect(trace.on_task_completed)
	var rows: Array[Dictionary] = trace.capture(roster, 1)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["member"], "Alex")
	assert_eq(rows[0]["tasks"], 1, "owner, cancellation and repeat completion are excluded")
	assert_eq(rows[0]["earned"], StaffRoster.GROWTH_TUNING.xp_for_task(&"cook"))
	assert_eq(rows[0]["xp"], 0, "a read-only trace does not credit the roster")
	assert_eq(roster.members()[0].growth_state().earned_today(&"cooking"), 0)
	assert_eq(rows[1]["tasks"], 0, "an idle starter remains visible")
	assert_eq(rows[1]["earned"], 0)


func test_staff_trace_flag_is_opt_in_and_rejects_ambiguous_values() -> void:
	assert_false(BalanceProbe._parse_args(PackedStringArray())["staff_growth"])
	assert_true(BalanceProbe._parse_args(PackedStringArray(["--staff-growth=true"]))["staff_growth"])
	assert_false(BalanceProbe._parse_args(PackedStringArray(["--staff-growth", "false"]))["staff_growth"])
	assert_true(BalanceProbe._parse_args(PackedStringArray(["--staff-growth=maybe"])).has("error"))


func test_auto_accept_flag_is_opt_in_and_keeps_explicit_false() -> void:
	assert_false(BalanceProbe._parse_args(PackedStringArray())["auto_accept_raises"])
	assert_true(BalanceProbe._parse_args(PackedStringArray(["--auto-accept-raises=true"]))["auto_accept_raises"])
	assert_false(BalanceProbe._parse_args(PackedStringArray(["--auto-accept-raises", "false"]))["auto_accept_raises"])
	assert_true(BalanceProbe._parse_args(PackedStringArray(["--auto-accept-raises=maybe"])).has("error"))


func test_auto_accept_settles_all_requests_through_real_main_and_rejects_service() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var main: Node = MAIN_SCENE.instantiate()
	main.set("use_saves", false)
	tree.root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	var saved: Dictionary = roster.to_dict()
	saved["members"][0]["skill"] = 5
	saved["members"][0]["growth"]["skills"]["cooking"] = 5
	saved["members"][0]["growth"]["skills"]["cleaning"] = 2
	saved["members"][0]["growth"]["raises"] = [
		{"skill": "cooking", "level": 4}, {"skill": "cooking", "level": 5},
		{"skill": "cleaning", "level": 2}]
	saved["members"][1]["skill"] = 4
	saved["members"][1]["growth"]["skills"]["service"] = 4
	saved["members"][1]["growth"]["raises"] = [{"skill": "service", "level": 4}]
	assert_true(roster.from_dict(saved))
	assert_true(sim.set_staff_roster(roster.members()))
	var books: Dictionary = Economy.ledger.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var random: Dictionary = GameState.call("_capture_save")
	var accepted: Dictionary = BalanceProbe._accept_morning_raises(main)
	assert_false(accepted.has("error"), str(accepted.get("error", "")))
	assert_eq(accepted.get("accepted"), 4, "all members and queued no-pay acknowledgements settle")
	roster = main.get("staff_roster") as StaffRoster
	for member: StaffMember in roster.members():
		assert_eq(member.growth_state().pending_raise_count(), 0)
		assert_eq(member.growth_state().mood, 3)
		var expected: int = sim.pricing_tuning.staff_wage(member.role, member.skill)
		assert_eq(member.wage, expected)
		var found: bool = false
		for agent: SimAgent in sim.world.agents:
			if agent is StaffAgent and not agent is OwnerAgent \
					and (agent as StaffAgent).member_id == member.id:
				assert_eq((agent as StaffAgent).wage, expected,
					"using Main updates the live wage as well as the roster")
				found = true
		assert_true(found)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(GameState.call("_capture_save"), random)
	assert_eq(sim.world.now, 0, "choosing raises requires no service ticks")
	assert_eq(BalanceProbe._accept_morning_raises(main), {"accepted": 0})
	assert_true(Clock.sim.start_service())
	var before: Dictionary = roster.to_dict()
	assert_true(BalanceProbe._accept_morning_raises(main).has("error"))
	assert_eq(roster.to_dict(), before)
	tree.root.remove_child(main)
	main.free()


func test_staff_summary_reports_each_skill_up_day_and_live_wage_without_awarding_xp() -> void:
	var roster: StaffRoster = StaffRoster.new()
	var before: Dictionary = BalanceProbe._staff_levels(roster)
	var saved: Dictionary = roster.to_dict()
	saved["members"][0]["skill"] = 5
	saved["members"][0]["growth"]["skills"]["cooking"] = 5
	saved["members"][0]["growth"]["skills"]["cleaning"] = 2
	saved["members"][1]["skill"] = 4
	saved["members"][1]["growth"]["skills"]["service"] = 4
	assert_true(roster.from_dict(saved))
	var events: Array[Dictionary] = BalanceProbe._staff_level_ups(before, roster, 5)
	assert_eq(events.size(), 4, "a multi-level day retains every crossed level and secondary skill")
	assert_eq(events[0]["level"], 4)
	assert_eq(events[1]["level"], 5)
	assert_eq(events[2]["skill"], &"cleaning")
	assert_eq(events[3]["skill"], &"service")
	var summary: Array[Dictionary] = BalanceProbe._staff_summary(roster, events)
	assert_eq(summary.size(), 3)
	var line: String = BalanceProbe._format_staff_summary("default", 7, summary[0])
	assert_true(line.contains("L4: day 5, L5: day 5"))
	assert_true(line.contains("Alex | Cooking"))
	assert_eq(summary[0]["wage"], roster.members()[0].wage)
	assert_eq(roster.to_dict(), saved, "summarizing does not accept raises or mutate progression")
