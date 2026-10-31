extends TestCase
## Real session/report/save boundary. The first regression uses existing APIs
## only, so unchanged main can compile it and fail on the missing observation.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "staff_activity_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}
var _preferences: SettingsPreferences
var _old_preferences: Dictionary = {}
var _old_window_scale: float = 1.0
var _old_window_mode: Window.Mode = Window.MODE_WINDOWED
var _old_window_size: Vector2i = Vector2i.ZERO


func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "staff_activity_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers = SaveSystem._providers.duplicate()
	_preferences = tree.root.get_node("Preferences") as SettingsPreferences
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save", "ui_scale_percent",
			"default_open_speed", "fullscreen_enabled", "edge_pan_enabled"]:
		_old_preferences[key] = _preferences.get(key)
	_old_window_scale = tree.root.content_scale_factor
	_old_window_mode = tree.root.mode
	_old_window_size = tree.root.size
	_preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	_preferences.set("_disk_enabled", false)
	_preferences.set("_pending_volume_save", false)
	_preferences.ui_scale_percent = 100
	_preferences.default_open_speed = 1
	_preferences.fullscreen_enabled = false
	_preferences.edge_pan_enabled = false
	Clock.set_speed(0)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_mains.erase(main)
		main.get_parent().remove_child(main)
		main.free()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	for key: String in _old_preferences:
		_preferences.set(key, _old_preferences[key])
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	if window.mode != _old_window_mode:
		window.mode = _old_window_mode
	if window.size != _old_window_size:
		window.size = _old_window_size
	window.content_scale_factor = _old_window_scale
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_completed_idle_service_report_records_actual_open_hours() -> void:
	var main: Node = await _start()
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	Clock.sim.open_ticks = 2
	Clock.sim.last_orders_max_ticks = 5
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = main.get("shown_report") as DayReport
	assert_not_null(report)
	if report == null:
		return
	var encoded: Dictionary = report.to_dict()
	assert_true(encoded.has("staff_activity"),
		"a completed real service must report measured staff open hours, even when every worker was idle")
	if not encoded.has("staff_activity"):
		return
	assert_eq(encoded["staff_activity"], {"day": 1, "open_ticks": 2, "roles": {
		"cook": {"busy_ticks": 0, "open_ticks": 2},
		"server": {"busy_ticks": 0, "open_ticks": 2}}})


func test_report_optional_observation_round_trips_without_fabricating_legacy_idle() -> void:
	var report: DayReport = DayReport.new()
	assert_eq(report.staff_activity, {})
	assert_false(report.to_dict().has("staff_activity"), "legacy unknown observations stay omitted")
	var input: Dictionary = {"day": 2, "open_ticks": 10, "roles": {
		"cook": {"busy_ticks": 9, "open_ticks": 10},
		"server": {"busy_ticks": 0, "open_ticks": 10}}}
	report.staff_activity = input
	input["roles"]["cook"]["busy_ticks"] = 0
	assert_eq(report.staff_activity["roles"]["cook"]["busy_ticks"], 9)
	var encoded: Dictionary = report.to_dict()
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(encoded)))
	assert_eq(restored.staff_activity, report.staff_activity)
	encoded["staff_activity"]["roles"]["cook"]["busy_ticks"] = 0
	assert_eq(report.staff_activity["roles"]["cook"]["busy_ticks"], 9)
	assert_eq(restored.staff_activity["roles"]["cook"]["busy_ticks"], 9)
	assert_eq(DayReport.from_dict({"day": 3}).staff_activity, {})
	var malformed: DayReport = DayReport.from_dict({"staff_activity": {"day": 2, "open_ticks": 10,
		"roles": {"cook": {"busy_ticks": 11, "open_ticks": 10}}}})
	assert_eq(malformed.staff_activity, {})
	assert_false(malformed.to_dict().has("staff_activity"))


func test_service_report_refresh_and_morning_reset_add_no_save_provider_or_save_point() -> void:
	var main: Node = await _start()
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var original_file: String = _saved_text()
	assert_false(original_file.is_empty())
	var provider_names: Array = SaveSystem._providers.keys()
	provider_names.sort()
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	Clock.sim.open_ticks = 3
	Clock.sim.last_orders_max_ticks = 5
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = main.get("shown_report") as DayReport
	assert_not_null(report)
	if report == null:
		return
	var previous_service: Dictionary = report.staff_activity.duplicate(true)
	assert_false(previous_service.is_empty())
	assert_eq(_saved_text(), original_file, "service and actual closing add no save point")
	var frozen: Dictionary = _session_state(main)
	var report_again: DayReport = main.call("build_report", 1) as DayReport
	assert_eq(report_again.staff_activity, previous_service)
	assert_true(main.call("set_staff_visible", true))
	assert_true(main.call("set_staff_visible", false))
	assert_eq(_session_state(main), frozen, "report and Staff presentation do not alter simulation, RNG or saved bytes")
	assert_true(Clock.sim.next_day())
	assert_eq(sim.staff_activity.snapshot(), {}, "today's observations reset at the existing morning boundary")
	assert_null(main.get("shown_report"))
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	assert_eq((panel.get_node("%TeamActivityHeading") as Label).text, "Last service · Day 1")
	assert_eq((panel.get_node("%TeamActivityRows/CookActivity") as Label).text, "Cooks: busy 0% of open hours")
	assert_eq(report.staff_activity, previous_service, "a morning reset cannot mutate yesterday's detached report")
	assert_ne(_saved_text(), original_file, "the existing next-morning autosave still occurs")
	var after_names: Array = SaveSystem._providers.keys()
	after_names.sort()
	assert_eq(after_names, provider_names, "statistics do not register a new provider")
	assert_false(_saved_text().contains('"staff_activity"'), "current saves have no report provider or live activity counters")
	assert_false(_saved_text().contains('"busy_ticks"'))
	assert_false(FileAccess.file_exists(_save_dir.path_join("preferences.cfg")))


func _start() -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("save_slot", SLOT)
	main.set("use_saves", true)
	main.set("new_game_seed_override", 8201)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	main.set_process(false)
	(main.get_node("CameraRig") as CameraRig).set_process(false)
	(main.get_node("ShopView") as ShopView).set_process(false)
	Clock.set_speed(0)
	return main


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _session_state(main: Node) -> Dictionary:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	return {"clock": Clock.sim.to_dict(), "rng": GameState._capture_save(),
		"economy": Economy._capture_save(), "stock": Economy.stock.to_dict(),
		"roster": (main.get("staff_roster") as StaffRoster).to_dict(),
		"activity": sim.staff_activity.snapshot(), "world_tick": sim.world.now,
		"events": sim.world.event_log.duplicate(), "file": _saved_text()}
