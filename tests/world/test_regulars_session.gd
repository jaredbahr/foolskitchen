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


func _start(saves: bool) -> Node:
	var scene: PackedScene = load("res://src/world/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 166)
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
