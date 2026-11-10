extends TestCase
## Production close, read-only report/Goals refresh, morning checkpoint and whole load.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "shop_records_session"
const REJECT: String = "shop_records_test_reject"

var _main: Node
var _old_save_dir: String
var _dir: String
var _providers: Dictionary[String, Dictionary] = {}
var _clock_processing: bool
var _speed: int
var _preferences: SettingsPreferences
var _preference_state: Dictionary = {}
var _rejected_staged: bool = false
var _rejected_live_empty: bool = false


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _dir
	SaveSystem.delete_slot(SLOT)
	_clock_processing = Clock.is_processing()
	_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)
	_preferences = (Engine.get_main_loop() as SceneTree).root.get_node("Preferences") as SettingsPreferences
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save"]:
		_preference_state[key] = _preferences.get(key)
	_preferences.set("_file_path", _dir.path_join("preferences.cfg"))
	_preferences.set("_disk_enabled", false)
	_preferences.set("_pending_volume_save", false)
	_rejected_staged = false
	_rejected_live_empty = false


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _providers
	for key: String in _preference_state:
		_preferences.set(key, _preference_state[key])
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_speed)
	Clock.set_process(_clock_processing)


func test_actual_close_counts_once_and_persists_only_at_the_next_morning() -> void:
	_start()
	var morning: String = _saved()
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(report)
	if report == null:
		return
	assert_true(report.customers_served > 0, "ordinary paid service is non-vacuous")
	var state: Dictionary = _records().snapshot()
	assert_eq(state["guests"], report.customers_served)
	assert_eq(state["dishes"], report.dishes_sold)
	assert_eq(state["revenue"], int(report.income.get(Ledger.SALE, 0)) + int(report.income.get(Ledger.TIP, 0)))
	assert_eq(report.record_lines, [] as Array[String], "the first recorded close sets bests quietly")
	var expected: Dictionary = _records().capture()
	var random_state: Dictionary = GameState.call("_capture_save")
	_main.call("build_report", report.day)
	_main.call("_on_service_closed", report.day)
	assert_true(_main.call("set_goals_visible", true))
	assert_true(_main.call("set_goals_visible", false))
	var refreshed: DayReport = _main.call("build_report", report.day) as DayReport
	assert_eq(refreshed.record_lines, report.record_lines, "reopening keeps this close's notice")
	Economy.add_cash(-7, Ledger.UPGRADES) # An evening purchase can rebuild the report.
	_main.call("_show_evening_report", _main.call("build_report", report.day))
	assert_eq(_records().capture(), expected, "queries, duplicate close and evening spending do not count twice")
	assert_eq(GameState.call("_capture_save"), random_state, "records/UI consume no random draw")
	assert_eq(_saved(), morning, "the existing morning checkpoint remains unchanged through the close/UI")
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_eq(_document()["data"]["shop_records"], _json(expected))
	_close()
	_start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_json(_records().capture()), _json(expected))
	assert_null(_main.get("_loaded_shop_records"))
	assert_eq((_main.call("build_report", 2) as DayReport).record_lines, [] as Array[String])
	_main.call("_new_game")
	assert_eq(_records().snapshot(), ShopRecords.new().snapshot())


func test_legacy_missing_data_and_failed_whole_load_never_reuse_staged_records() -> void:
	_start()
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	_main.call("_on_next_day_pressed")
	var valid: Dictionary = _document()
	var saved_records: Dictionary = valid["data"]["shop_records"].duplicate(true)
	var legacy: Dictionary = valid.duplicate(true)
	legacy["data"].erase("shop_records")
	_write(legacy)
	_close()
	_start(saved_records)
	assert_eq(Clock.sim.day, 2, "the otherwise valid old morning loads")
	assert_eq(_records().snapshot(), ShopRecords.new().snapshot())
	assert_null(_main.get("_loaded_shop_records"))
	var malformed: Dictionary = valid.duplicate(true)
	malformed["data"]["shop_records"]["revenue"] = "not money"
	_write(malformed)
	var rejected_file: String = _saved()
	_close()
	_start(saved_records)
	assert_eq(Clock.sim.day, 1)
	assert_eq(_records().snapshot(), ShopRecords.new().snapshot())
	assert_null(_main.get("_loaded_shop_records"))
	assert_eq(_saved(), rejected_file, "a failed load preserves the rejected checkpoint")
	var late: Dictionary = valid.duplicate(true)
	late["data"][REJECT] = {}
	SaveSystem.register(REJECT, _empty, _reject_after_records)
	_write(late)
	rejected_file = _saved()
	_close()
	_start()
	assert_true(_rejected_staged, "the actual later provider observed a valid detached candidate")
	assert_true(_rejected_live_empty, "the candidate was not installed early")
	assert_eq(Clock.sim.day, 1)
	assert_eq(_records().snapshot(), ShopRecords.new().snapshot())
	assert_null(_main.get("_loaded_shop_records"))
	assert_eq(_saved(), rejected_file)


func _start(staged: Dictionary = {}) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("skip_owner_picker", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	if not staged.is_empty():
		assert_true(_main.call("_restore_shop_records", staged))
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_process(false)
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _records() -> ShopRecords:
	return _main.get("shop_records") as ShopRecords


func _saved() -> String:
	return FileAccess.get_file_as_string(_dir.path_join(SLOT + ".json"))


func _document() -> Dictionary:
	return JSON.parse_string(_saved())


func _write(document: Dictionary) -> void:
	var path: String = _dir.path_join(SLOT + ".json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify(document))
		file.close()
	DirAccess.remove_absolute(path + ".bak")


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _empty() -> Dictionary:
	return {}


func _reject_after_records(_data: Dictionary) -> bool:
	_rejected_staged = _main.get("_loaded_shop_records") is ShopRecords
	_rejected_live_empty = _records().snapshot()["last_day"] == 0
	return false
