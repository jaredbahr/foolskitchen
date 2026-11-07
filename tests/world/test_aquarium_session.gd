extends TestCase
## #125 in the real game session: buying a tank, its cloudiness after four
## mornings (charm and look), and the morning save keeping it.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: AquariumTuning = preload("res://data/balance/aquarium.tres")
const SLOT: String = "aquarium_session"
## Against the kitchen wall of the seed-1 starter dining room, facing the room.
const SPOT: Vector2i = Vector2i(3, 5)
var _main: Node
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start(saves: bool = false) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", saves)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _sim() -> RestaurantSim:
	return _main.get("sim")


func _buy(level: int) -> PlacedItem:
	Economy.add_cash(1000, Ledger.OTHER)
	(_main.get("shop_editor") as ShopEditor).set_owner_level(level)
	if not _main.call("shop_buy", &"aquarium", SPOT, 2):
		return null
	return _sim().world.grid.item((_main.get("shop_editor") as ShopEditor).last_item_id)


func _next_morning() -> void:
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")


func _vibe() -> VibeModel.Result:
	return _main.get("vibe_result")


func _tank_view(tank: PlacedItem) -> AquariumView:
	var view: ShopView = _main.get_node("ShopView")
	return (view.item_nodes[tank.id] as ItemVisual).prop as AquariumView


func test_the_aquarium_unlocks_at_level_three_and_draws_swimming_fish() -> void:
	_start()
	assert_null(_buy(2), "locked below level 3")
	var tank: PlacedItem = _buy(3)
	assert_not_null(tank)
	var view: AquariumView = _tank_view(tank)
	assert_not_null(view, "the tank is drawn by its wrapper")
	assert_true(view.fish.size() >= 4 and view.fish.size() <= 6)
	var before: Transform3D = view.fish[0].transform
	view._process(0.5)
	assert_false(view.fish[0].transform.is_equal_approx(before), "the fish swim")
	assert_false(view.cloudy)
	assert_true(_sim().aquarium.has_tank(tank.id))


func test_four_mornings_later_the_tank_is_cloudy_with_less_charm_and_cleaning_brings_it_back() -> void:
	_start()
	var tank: PlacedItem = _buy(3)
	var clear: float = _vibe().decor_points
	for morning: int in TUNING.cloudy_after_days - 1:
		_next_morning()
		assert_false(_sim().aquarium.is_cloudy(tank.id, Clock.sim.day))
	assert_almost_eq(_vibe().decor_points, clear, 0.000001)
	_next_morning()
	assert_true(_sim().aquarium.is_cloudy(tank.id, Clock.sim.day))
	assert_true(_vibe().decor_points < clear, "a cloudy tank gives less charm")
	var view: ShopView = _main.get_node("ShopView")
	view._process(0.0)
	assert_true(_tank_view(tank).cloudy, "and looks murky")
	assert_true(_sim().aquarium.clean(tank.id, Clock.sim.day))
	assert_almost_eq(_vibe().decor_points, clear, 0.000001, "cleaned: the full charm is back at once")
	view._process(0.0)
	assert_false(_tank_view(tank).cloudy)


func test_selling_a_cloudy_tank_then_undo_keeps_it_cloudy() -> void:
	_start()
	var tank: PlacedItem = _buy(3)
	for morning: int in TUNING.cloudy_after_days:
		_next_morning()
	assert_true(_sim().aquarium.is_cloudy(tank.id, Clock.sim.day))
	var cleaned: int = _sim().aquarium.cleaned_day(tank.id)
	assert_true(_main.call("set_build_active", true))
	assert_true(int(_main.call("shop_sell", tank.id)) > 0)
	assert_null(_sim().world.grid.item_at(SPOT))
	assert_true(_main.call("undo_edit"))
	var back: PlacedItem = _sim().world.grid.item_at(SPOT)
	assert_not_null(back)
	assert_eq(_sim().aquarium.cleaned_day(back.id), cleaned)
	assert_true(_sim().aquarium.is_cloudy(back.id, Clock.sim.day), "Undo brings the cloudy water back too")


func test_during_a_busy_service_the_owner_on_floor_walks_over_and_cleans_it() -> void:
	_start()
	var tank: PlacedItem = _buy(3)
	for morning: int in TUNING.cloudy_after_days:
		_next_morning()
	assert_true(_sim().aquarium.is_cloudy(tank.id, Clock.sim.day))
	# The owner rests until the room is busy, then goes on Floor.
	assert_true(_sim().assign_owner(&"rest"))
	assert_true(Clock.sim.start_service())
	for step: int in 40:
		if _sim().customers().size() >= 2:
			break
		_main.call("run_ticks", 100)
	assert_true(_sim().customers().size() >= 2, "guests are about")
	assert_true(_sim().aquarium.is_cloudy(tank.id, Clock.sim.day), "nobody cleaned it yet")
	assert_true(_sim().assign_owner(&"floor"))
	var cleaned: bool = false
	for step: int in 60:
		_main.call("run_ticks", 100)
		if not _sim().aquarium.is_cloudy(tank.id, Clock.sim.day):
			cleaned = true
			break
	assert_true(cleaned, "cleaned among the guests, with the movement watchdog running")


func test_the_morning_save_keeps_a_cloudy_tank_cloudy() -> void:
	_start(true)
	var tank: PlacedItem = _buy(3)
	for morning: int in TUNING.cloudy_after_days:
		_next_morning()
	assert_true(_sim().aquarium.is_cloudy(tank.id, Clock.sim.day))
	var cleaned: int = _sim().aquarium.cleaned_day(tank.id)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved: Dictionary = document["data"]["aquarium"]
	assert_eq(int(saved["version"]), 1)
	assert_eq((saved["tanks"] as Array).size(), 1, "one row per tank: kind, position and cleaning day")
	var clear_points: float = _vibe().decor_points
	_close()
	_start(true)
	var loaded: PlacedItem = _sim().world.grid.item_at(SPOT)
	assert_not_null(loaded)
	assert_eq(_sim().aquarium.cleaned_day(loaded.id), cleaned)
	assert_true(_sim().aquarium.is_cloudy(loaded.id, Clock.sim.day), "still cloudy after loading")
	assert_almost_eq(_vibe().decor_points, clear_points, 0.000001)


func test_a_game_without_a_tank_saves_an_empty_section_and_an_old_save_loads() -> void:
	_start(true)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved: Dictionary = document["data"]["aquarium"]
	assert_eq(int(saved["version"]), 1)
	assert_true((saved["tanks"] as Array).is_empty())
	document["data"].erase("aquarium")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close()
	_start(true)
	assert_not_null(_sim())
	assert_true(_sim().aquarium.cloudy_ids(_sim().world.grid, Clock.sim.day).is_empty())
