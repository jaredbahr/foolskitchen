extends TestCase
## The real session owns the cat's offer, its price, its food and its save.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const CAT: CatTuning = preload("res://data/balance/cat.tres")
const SLOT: String = "cat_session"
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


func _progress() -> OwnerProgress:
	return _main.get("owner_progress")


func _sim() -> RestaurantSim:
	return _main.get("sim")


func _level(level: int) -> void:
	_progress().award_bonus(_progress().threshold_for(level))
	(_main.get("menu_settings") as MenuSettings).set_owner_level(_progress().level)
	(_main.get("shop_editor") as ShopEditor).set_owner_level(_progress().level)
	Economy.cash = 500
	_main.call("_refresh_cat_offer")


func _offer() -> VBoxContainer:
	return _main.get_node("Overlay/MenuPanel/Panel/Content/CatOffer")


func test_offer_appears_at_level_four_in_the_morning_only() -> void:
	_start()
	assert_false(_offer().visible, "no offer at level 1")
	assert_false(_main.call("adopt_cat"))
	_level(CAT.unlock_level - 1)
	assert_false(_offer().visible)
	_level(CAT.unlock_level)
	assert_true(_offer().visible)
	assert_eq((_offer().get_node("Cost") as Label).text, "Biscuit joins your shop for $40. Cat food is $2 a day.")
	assert_false((_offer().get_node("Accept") as Button).disabled)
	Economy.cash = CAT.adoption_price - 1
	_main.call("_refresh_cat_offer")
	assert_true((_offer().get_node("Accept") as Button).disabled)
	assert_eq((_offer().get_node("Refusal") as Label).text, "Not enough cash to adopt a cat")
	Economy.cash = 500
	for phase: int in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]:
		Clock.sim.phase = phase
		_main.call("_refresh_cat_offer")
		assert_false(_offer().visible)
		assert_false(_main.call("adopt_cat"))
	assert_false(_sim().cat.adopted)


func test_adopting_charges_once_and_food_is_charged_every_day() -> void:
	_start()
	_level(CAT.unlock_level)
	var cash: int = Economy.cash
	assert_true(_main.call("adopt_cat"))
	assert_true(_sim().cat.adopted)
	assert_eq(Economy.cash, cash - CAT.adoption_price)
	var entry: Dictionary = Economy.ledger.entries_for_day(Clock.sim.day).back()
	assert_eq(entry["amount"], -CAT.adoption_price)
	assert_false(_main.call("adopt_cat"), "only once")
	assert_eq(Economy.cash, cash - CAT.adoption_price)
	assert_false(_offer().visible, "the offer is gone for good")
	# Through the real close path: once per day, and a repeated close signal
	# on the same day charges nothing more.
	for day: int in 3:
		var day_number: int = Clock.sim.day
		_main.call("_on_service_closed", day_number)
		var after_first: Dictionary = Economy.ledger.day_totals(day_number)
		assert_eq(int(after_first.get(Ledger.CAT_FOOD, 0)), -CAT.daily_food_cost, "day %d: cat food, once" % day_number)
		var cash_after: int = Economy.cash
		_main.call("_on_service_closed", day_number)
		assert_eq(Economy.cash, cash_after, "day %d: a second close signal charges nothing" % day_number)
		assert_eq(int(Economy.ledger.day_totals(day_number).get(Ledger.CAT_FOOD, 0)), -CAT.daily_food_cost)
		Clock.sim.day += 1
		_main.call("_begin_morning")


func test_no_cat_means_no_food_charge() -> void:
	_start()
	_main.call("_charge_closing_costs")
	assert_false(Economy.ledger.day_totals(Clock.sim.day).has(Ledger.CAT_FOOD))


func test_the_evening_report_names_the_cost_in_plain_words() -> void:
	var report: Script = load("res://src/ui/evening_report.gd")
	assert_eq((report.get("MONEY_LABELS") as Dictionary)[Ledger.CAT_FOOD], "Cat food")


func test_adoption_and_name_survive_the_morning_save_but_position_does_not() -> void:
	_start(true)
	_level(CAT.unlock_level)
	assert_true(_main.call("adopt_cat"))
	_sim().cat.cat_name = "Mochi"
	Clock.sim.day += 1
	_main.call("_begin_morning")
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved: Dictionary = document["data"]["cat"]
	assert_eq(saved.keys().size(), 3, "only its version, adoption and name")
	assert_eq(int(saved["version"]), 1)
	assert_eq(saved["adopted"], true)
	assert_eq(saved["name"], "Mochi")
	_close()
	_start(true)
	assert_true(_sim().cat.adopted)
	assert_eq(_sim().cat.cat_name, "Mochi")
	assert_ne(_sim().cat.cell, SimGrid.NO_CELL, "it is back on its bed this morning")
	assert_eq(_sim().cat.cell, _sim().cat.bed())
	assert_false(_offer().visible, "an adopted cat is never offered again")


func test_an_old_save_without_a_cat_loads_with_no_cat() -> void:
	_start(true)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	document["data"].erase("cat")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close()
	_start(true)
	assert_false(_sim().cat.adopted)
	assert_eq(_sim().cat.cat_name, "Biscuit")


func test_a_broken_cat_section_refuses_the_whole_load_like_any_other() -> void:
	_start(true)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	document["data"]["cat"] = {"version": 1, "adopted": "maybe", "name": "Biscuit"}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close()
	_start(true)
	assert_false(_sim().cat.adopted)


func test_the_cat_is_drawn_only_once_adopted_and_follows_its_state() -> void:
	_start()
	var view: ShopView = _main.get_node("ShopView")
	assert_not_null(view.cat_view)
	view._process(0.0)
	assert_false(view.cat_view.visible, "no cat before adoption")
	_level(CAT.unlock_level)
	assert_true(_main.call("adopt_cat"))
	view._process(0.0)
	assert_true(view.cat_view.visible)
	assert_eq(view.cat_view.current_clip(), &"nap", "asleep on its bed in the morning")
	var floor_at: Vector3 = GridMath.cell_to_world(_sim().cat.cell)
	assert_almost_eq(view.cat_view.position.x, floor_at.x)
	assert_almost_eq(view.cat_view.position.z, floor_at.z)
	assert_almost_eq(view.cat_view.position.y, 0.0, 0.0001, "on the floor")
	_sim().cat.state = RestaurantCat.State.STANDING
	view._process(0.0)
	assert_eq(view.cat_view.current_clip(), &"idle")
	# A step: drawn between its two cells, walking.
	var cat: RestaurantCat = _sim().cat
	var open: Array[Vector2i] = _sim().world.grid.guest_neighbours(cat.cell)
	assert_false(open.is_empty())
	cat.from_cell = cat.cell
	cat.cell = open[0]
	cat.state = RestaurantCat.State.WALKING
	cat.step_total = 8
	cat.step_done = 4
	view._process(0.0)
	assert_eq(view.cat_view.current_clip(), &"walk")
	var halfway: Vector3 = GridMath.cell_to_world(cat.from_cell).lerp(GridMath.cell_to_world(cat.cell), 0.5)
	assert_true(view.cat_view.position.distance_to(halfway) < 0.13, "between the cells, not snapped")


func test_a_game_with_no_cat_has_no_cat_stream() -> void:
	var first: Dictionary = _no_cat_streams()
	var second: Dictionary = _no_cat_streams()
	assert_false((first["rngs"] as Dictionary).has("cat"), "no cat, no stream")
	assert_eq(first, second, "and the other streams are exactly as without the feature")


func test_loading_an_adopted_game_restores_the_cat_stream() -> void:
	_start(true)
	_level(CAT.unlock_level)
	assert_true(_main.call("adopt_cat"))
	var warmup: RestaurantCat = _sim().cat
	for tick: int in 3000:
		warmup.advance(_sim().world.grid, [])
	Clock.sim.day += 1
	_main.call("_begin_morning")
	var unsaved: Array[Vector2i] = _cat_walk()
	assert_true(unsaved.size() > 10, "a real walk")
	_close()
	_start(true)
	assert_true(_sim().cat.adopted)
	assert_eq(_cat_walk(), unsaved, "the saved stream gives the same next walk")


func _cat_walk() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cat: RestaurantCat = _sim().cat
	var last: Vector2i = SimGrid.NO_CELL
	for tick: int in 6000:
		cat.advance(_sim().world.grid, [])
		if cat.cell != last:
			last = cat.cell
			out.append(last)
	return out


func _no_cat_streams() -> Dictionary:
	_start()
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 600)
	var saved: Dictionary = GameState._capture_save()
	_close()
	Economy.reset(0)
	GameState.new_run(1)
	return saved
