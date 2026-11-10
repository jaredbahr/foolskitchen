extends TestCase
## A real session's per-site sections, frozen on one morning and thawed for a
## later one (FK-087 step C2), pass main's whole morning load.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "site_thaw_session"
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


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("skip_owner_picker", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


## A real service and the real Next day button: the morning autosaves.
func _play_day() -> void:
	assert_true(Clock.sim.start_service())
	for _guard: int in 30:
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
		_main.call("run_ticks", 1000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


## A morning with no service in between (the active site's own days do not
## matter here; only the calendar moves).
func _skip_day() -> void:
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


## Step 1 of a switch: the per-site sections as their providers capture them,
## in the shape a save file decodes to.
func _freeze() -> Dictionary:
	var sections: Dictionary = {}
	for key: String in SiteSections.PER_SITE:
		sections[key] = SaveSystem._providers[key]["capture"].call()
	return JSON.parse_string(JSON.stringify(sections))


func _path() -> String:
	return SaveSystem.save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _install_in_save(sections: Dictionary) -> void:
	var document: Dictionary = _document()
	for key: String in sections:
		document["data"][key] = sections[key]
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	DirAccess.remove_absolute(_path() + ".bak")


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _new_game_logged() -> bool:
	var sim: RestaurantSim = _main.get("sim")
	for line: Variant in sim.world.event_log:
		if String(line).contains("starting a new game"):
			return true
	return false


## Two played days give the site renown, history, records and dated stock;
## an order placed for tomorrow leaves a delivery waiting.
func _play_to_frozen_morning() -> int:
	_start()
	_play_day()
	_play_day()
	var book: DeliveryBook = _main.get("deliveries")
	var line: Array[Dictionary] = [{"id": &"bun", "qty": 3, "unit_cost": 2}]
	assert_true(book.place(line, 6, false, Vector2i(Clock.sim.day + 1, DeliveryBook.MORNING)))
	return Clock.sim.day


func test_a_site_frozen_three_days_ago_thaws_and_loads_as_today() -> void:
	var frozen_day: int = _play_to_frozen_morning()
	var frozen: Dictionary = _freeze()
	var frozen_demand: DemandState = _main.get("demand_state")
	assert_true(frozen_demand.renown > 0.0, "two played days earned renown")
	assert_false((_main.get("business_history") as BusinessHistory).summaries().is_empty())
	for _day: int in 3:
		_skip_day()
	var today: int = Clock.sim.day
	assert_eq(today, frozen_day + 3)
	var result: Dictionary = SiteThaw.thaw(frozen, frozen_day, today, SiteThawTunings.authored())
	assert_false(result.is_empty(), "a real frozen site thaws")
	var thawed: Dictionary = result["sections"]
	assert_eq(thawed.keys().size(), SiteSections.PER_SITE.size())
	assert_eq(int(thawed["demand"]["day"]), today)
	assert_true(float(thawed["demand"]["renown"]) < float(frozen["demand"]["renown"]), "renown faded")
	assert_eq(int(thawed["deliveries"]["orders"][0]["day"]), frozen_day + 1 + 3, "the order waits")
	_install_in_save(thawed)
	_close()
	_start()
	assert_eq(Clock.sim.day, today, "the thawed site loaded on today's morning")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_false(_new_game_logged(), "not a new game")
	assert_eq(_json((_main.get("business_history") as BusinessHistory).capture()),
		_json(frozen["business_history"]), "the frozen site's history is installed")
	assert_eq(_json((_main.get("demand_state") as DemandState).to_dict()), thawed["demand"])
	var orders: Array[Dictionary] = (_main.get("deliveries") as DeliveryBook).orders()
	assert_eq(orders.size(), 1)
	assert_eq((orders[0]["due"] as Vector2i).x, today + 1)


func test_a_site_thawed_on_its_own_frozen_morning_is_unchanged_and_loads() -> void:
	var frozen_day: int = _play_to_frozen_morning()
	var frozen: Dictionary = _freeze()
	var result: Dictionary = SiteThaw.thaw(frozen, frozen_day, frozen_day, SiteThawTunings.authored())
	assert_false(result.is_empty())
	assert_eq(JSON.stringify(result["sections"]), JSON.stringify(frozen), "gap 0 is lossless")
	assert_true((result["refunds"] as Array).is_empty())
	_install_in_save(result["sections"])
	_close()
	_start()
	assert_eq(Clock.sim.day, frozen_day)
	assert_false(_new_game_logged(), "not a new game")
	assert_eq(_freeze()["deliveries"], frozen["deliveries"])
