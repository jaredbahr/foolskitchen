extends TestCase
## The sites save section (FK-087) round-trips through the real morning save.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "sites_session"
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


func _path() -> String:
	return SaveSystem.save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")


func test_a_save_holding_two_sites_round_trips() -> void:
	_start(true)
	var day: int = Clock.sim.day
	var frozen: Dictionary = {}
	for key: String in ["shop", "menu", "pantry"]:
		frozen[key] = SaveSystem._providers[key]["capture"].call()
	var book: SiteBook = _main.get("site_book")
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", day, frozen))
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	var saved: Dictionary = _document()["data"]["sites"]
	_close()
	_start(true)
	assert_eq(Clock.sim.day, day + 1, "the saved game loaded")
	var loaded: SiteBook = _main.get("site_book")
	assert_eq(loaded.site_ids(), [&"home", &"harbour"] as Array[StringName])
	assert_eq(loaded.frozen_day(&"harbour"), day)
	assert_eq(JSON.parse_string(JSON.stringify(loaded.to_dict())), saved,
		"the frozen site comes back whole")
	var saved_text: String = JSON.stringify(saved)
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	assert_eq(JSON.stringify(_document()["data"]["sites"]), saved_text,
		"saving again after a reload writes the same bytes")


func test_an_old_save_without_sites_loads_as_the_starter_site() -> void:
	_start(true)
	var document: Dictionary = _document()
	var day: int = Clock.sim.day
	document["data"].erase("sites")
	_write(document)
	_close()
	_start(true)
	assert_eq(Clock.sim.day, day, "the old save loaded")
	var book: SiteBook = _main.get("site_book")
	assert_eq(book.site_ids(), [SiteBook.HOME_ID] as Array[StringName])


func test_a_site_frozen_after_this_morning_refuses_the_load() -> void:
	_start(true)
	var document: Dictionary = _document()
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "", Clock.sim.day + 1, {}))
	document["data"]["sites"] = JSON.parse_string(JSON.stringify(book.to_dict()))
	_write(document)
	_close()
	_start(true)
	var loaded: SiteBook = _main.get("site_book")
	assert_eq(loaded.site_count(), 1, "a refused load starts over with the starter site")


func _hours() -> Vector3i:
	return Vector3i(Clock.sim.display_open_minute, Clock.sim.display_close_minute, Clock.sim.open_ticks)


## Saves from before #408 part 1 kept the hours in the clock only: they load
## with those hours, and the next save writes them as the site's own.
func test_an_old_save_without_site_hours_keeps_the_clocks_hours() -> void:
	_start(true)
	var document: Dictionary = _document()
	document["data"].erase("site_hours")
	document["data"]["clock"]["display_open_minute"] = 12 * 60
	document["data"]["clock"]["display_close_minute"] = 20 * 60
	document["data"]["clock"]["open_ticks"] = 8 * 60 * 6
	_write(document)
	_close()
	_start(true)
	assert_eq(_hours(), Vector3i(12 * 60, 20 * 60, 8 * 60 * 6))
	var saved: Dictionary = SaveSystem.capture_sections(PackedStringArray(["site_hours"]))
	assert_eq(JSON.stringify(saved["site_hours"]), JSON.stringify({"version": 1.0, "open_minute": 720.0,
		"close_minute": 1200.0, "open_ticks": 2880.0}))


## The site's own hours win over the clock's copy; hours outside the limits
## reset to the default day without losing the game; a malformed section is
## refused like any other.
func test_saved_site_hours_load_and_bad_ones_reset() -> void:
	_start(true)
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	var day: int = Clock.sim.day
	var document: Dictionary = _document()
	var default_hours: Vector3i = _hours()
	document["data"]["site_hours"] = {"version": 1, "open_minute": 12 * 60, "close_minute": 20 * 60,
		"open_ticks": 100}
	_write(document)
	_close()
	_start(true)
	assert_eq(_hours(), Vector3i(12 * 60, 20 * 60, 100), "the site's own hours, with its service length")
	_close()
	document["data"]["site_hours"]["close_minute"] = 23 * 60 + 45
	_write(document)
	_start(true)
	assert_eq(Clock.sim.day, day, "the game was kept")
	assert_eq(_hours(), default_hours, "hours off the half-hour steps reset")
	_close()
	for bad: Dictionary in [{"version": 1, "open_minute": "noon", "close_minute": 1200, "open_ticks": 1},
			{"version": 2, "open_minute": 720, "close_minute": 1200, "open_ticks": 1},
			{"version": 1, "open_minute": 720, "close_minute": 1200, "open_ticks": 0},
			{"version": 1, "open_minute": 720, "close_minute": 1200, "open_ticks": 1, "extra": 1}]:
		document["data"]["site_hours"] = bad
		_write(document)
		_start(true)
		assert_true(Clock.sim.day != day, "a malformed section refuses the load: %s" % JSON.stringify(bad))
		_close()


## Bad hours in both the clock and its site_hours copy are one problem: the
## load resets them and says so once (#463 review).
func test_bad_hours_in_clock_and_site_hours_are_reported_once() -> void:
	_start(true)
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	var day: int = Clock.sim.day
	var default_hours: Vector3i = _hours()
	var document: Dictionary = _document()
	document["data"]["clock"]["display_open_minute"] = 60
	document["data"]["site_hours"]["open_minute"] = 60
	_write(document)
	_close()
	_start(true)
	assert_eq(Clock.sim.day, day, "the game was kept")
	assert_eq(_hours(), default_hours)
	var notes: int = 0
	for line: Variant in (_main.get("sim") as RestaurantSim).world.event_log:
		if String(line).contains("Saved opening hours were outside the limits"):
			notes += 1
	assert_eq(notes, 1, "reported once")
