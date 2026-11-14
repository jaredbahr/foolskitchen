extends TestCase
## Named cast joins the existing morning save and actual sale/report paths.

const SLOT: String = "regulars_session"
var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "regulars_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_providers = SaveSystem._providers.duplicate()
	Clock.set_speed(0)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_promotion_waits_for_morning_autosave_and_round_trips_named_identity() -> void:
	var main: Node = _start(true)
	var before: String = FileAccess.get_file_as_string(_path())
	var profile: RegularProfile = _promote(main)
	assert_eq(FileAccess.get_file_as_string(_path()), before, "a promotion never writes a save")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	assert_eq(sim.regulars, main.get("regulars"))
	var identity: Dictionary = profile.to_dict()
	main.call("_begin_morning")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	assert_eq(document["data"]["regulars"]["profiles"].size(), 1)
	assert_eq(document["data"]["regulars"]["profiles"][0], JSON.parse_string(JSON.stringify(identity)))
	_close(main)
	var loaded: Node = _start(true)
	var cast: RegularCast = loaded.get("regulars") as RegularCast
	assert_eq(cast.profiles.size(), 1)
	assert_eq(cast.profiles[0].to_dict(), identity)
	assert_eq((loaded.get("sim") as RestaurantSim).regulars, cast)


func test_legacy_save_without_section_restores_empty_cast_without_regular_rng() -> void:
	var main: Node = _start(true)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	document["data"].erase("regulars")
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close(main)
	var loaded: Node = _start(true)
	assert_eq((loaded.get("regulars") as RegularCast).profiles.size(), 0)
	assert_false(GameState._rngs.has(&"regulars"))


func test_favourite_tip_credits_existing_ledger_once_with_payment_guard() -> void:
	var main: Node = _start(false)
	var profile: RegularProfile = _promote(main)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 51
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	guest.regular_profile = profile
	guest.regular_favourite_available = true
	var order: Order = Order.new()
	order.price = 20
	order.recipe_id = profile.favourite_dish
	var before: int = Economy.cash
	sim.pay(guest, order)
	sim.pay(guest, order)
	assert_eq(Economy.cash - before, 22)
	var totals: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
	assert_eq(totals.get(Ledger.SALE), 20)
	assert_eq(totals.get(Ledger.TIP), 2)


func test_report_preserves_player_facing_regular_notes_and_menu_marks_favourite() -> void:
	var main: Node = _start(false)
	var profile: RegularProfile = _promote(main)
	var cast: RegularCast = main.get("regulars") as RegularCast
	cast.visited_today.append(profile.id)
	var report: DayReport = main.call("build_report", Clock.sim.day) as DayReport
	assert_true(" ".join(report.regulars_lines).contains(profile.display_name))
	assert_eq(DayReport.from_dict(report.to_dict()).regulars_lines, report.regulars_lines)
	main.call("_refresh_menu_details")
	# The production MenuPanel's explicit presentation API is covered by its
	# focused view tests; this boundary must accept active cast favourites.
	assert_true(cast.favourite_on_menu(profile.favourite_dish))


func test_two_day_one_rugs_can_bring_a_named_regular_back_by_day_eight() -> void:
	var main: Node = _start(false, 1)
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	assert_eq(owner.level, 1)
	var starting_vibe: float = (main.get("vibe_result") as VibeModel.Result).score
	var opening_demand_before: Dictionary = main.call("current_demand_snapshot")
	var next_day_demand_before: Dictionary = main.call("forecast_next_demand")
	var cash: int = Economy.cash
	assert_true(main.call("set_build_active", true))
	var mode: BuildMode = main.get("build_mode") as BuildMode
	for cell: Vector2i in [Vector2i(1, 11), Vector2i(12, 11)]:
		assert_true(mode.begin_buy(&"rug_round", cell))
		assert_true(mode.commit())
	assert_eq(cash - Economy.cash, 60, "two catalogue purchases at $30 each")
	assert_true(main.call("set_build_active", false))
	var score: float = (main.get("vibe_result") as VibeModel.Result).score
	var opening_demand_after: Dictionary = main.call("current_demand_snapshot")
	var next_day_demand_after: Dictionary = main.call("forecast_next_demand")
	var cast: RegularCast = main.get("regulars") as RegularCast
	assert_true(starting_vibe < cast.tuning.min_vibe)
	assert_true(score >= cast.tuning.min_vibe)
	assert_eq(opening_demand_before["vibe"], opening_demand_after["vibe"], "the day-one floor still applies")
	assert_true(float(next_day_demand_after["vibe"]) > float(next_day_demand_before["vibe"]))
	var first_promotion: int = 0
	var first_return: int = 0
	for day: int in range(1, 9):
		assert_eq(Clock.sim.day, day)
		assert_true(Clock.sim.start_service())
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < 30:
			main.call("run_ticks", 1000)
			batches += 1
		assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
		if first_promotion == 0 and not cast.new_today.is_empty():
			first_promotion = day
		if not cast.visited_today.is_empty():
			first_return = day
			break
		if day < 8:
			assert_true(Clock.sim.next_day())
	print("EARLY REGULARS ", JSON.stringify({"vibe_before": starting_vibe, "vibe_after": score,
		"day_one_before": opening_demand_before["vibe"], "day_one_after": opening_demand_after["vibe"],
		"day_two_before": next_day_demand_before["vibe"], "day_two_after": next_day_demand_after["vibe"],
		"first_promotion": first_promotion, "first_return": first_return}))
	assert_true(first_promotion >= cast.tuning.min_day, "actual paid visits promote a named regular")
	assert_true(first_return >= 6 and first_return <= 8, "the named regular returns during service by day eight")


func _promote(main: Node) -> RegularProfile:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var cast: RegularCast = main.get("regulars") as RegularCast
	var dish: StringName = sim.menu[0].id
	cast.observe_visit("returning", &"regular", 1, 5.0, 20.0, dish, Vector2i(3, 6), 0.9, true,
		GameState.rng.bind(&"regulars"))
	var profile: RegularProfile = cast.observe_visit("returning", &"regular", 6, 5.0, 20.0,
		dish, Vector2i(3, 6), 0.9, true, GameState.rng.bind(&"regulars"))
	assert_not_null(profile)
	return profile


func _start(saves: bool, seed_value: int = 166) -> Node:
	var scene: PackedScene = load("res://src/world/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", seed_value)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")
