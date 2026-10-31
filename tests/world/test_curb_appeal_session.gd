extends TestCase
## Real Main edits and morning checkpoints; no played-service RNG comparison.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "curb_appeal_session"
const FRONT: Vector3i = Vector3i(3, 11, 0)
const CANOPY: Vector3i = Vector3i(6, 11, 4)

var _main: Node
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary[String, Dictionary] = {}
var _old_clock_processing: bool
var _old_speed: int
var _preferences: SettingsPreferences
var _old_preferences: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_clock_processing = Clock.is_processing()
	_old_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)
	_preferences = (Engine.get_main_loop() as SceneTree).root.get_node("Preferences") as SettingsPreferences
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save"]:
		_old_preferences[key] = _preferences.get(key)
	_preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	_preferences.set("_disk_enabled", false)
	_preferences.set("_pending_volume_save", false)


func after_each() -> void:
	_close_main()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	for key: String in _old_preferences:
		_preferences.set(key, _old_preferences[key])
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_old_speed)
	Clock.set_process(_old_clock_processing)


func test_bare_front_is_exactly_neutral_and_report_forecast_queries_are_pure() -> void:
	_start_main()
	_assert_bare()
	assert_eq(_sim().demand_factor, 1.0)
	assert_eq(_sim().arrival_rate(), 1.0, "the bare starter still uses the original day-one rate")
	var live: Dictionary = _main.call("current_demand_snapshot")
	var forecast: Dictionary = _main.call("forecast_next_demand")
	assert_eq(live["curb_appeal"], 1.0)
	assert_eq(forecast["curb_appeal"], 1.0)
	var before: Dictionary = _query_state()
	# The starter street is +Z. Native camera quarters 0/3 look from that side;
	# moving the focus must not turn a back view into a street view.
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	for quarter: int in 4:
		rig.initial_yaw_degrees = 45.0 + float(quarter) * 90.0
		rig.reset_view()
		var faces_street: bool = quarter == 0 or quarter == 3
		assert_eq(_main.call("curb_appeal_street_visible"), faces_street)
		rig.position += Vector3(100.0, 0.0, -100.0)
		assert_eq(_main.call("curb_appeal_street_visible"), faces_street, "pan preserves the facing side")
	assert_eq(_query_state(), before, "camera queries and rotations do not alter the session")
	for repeat: int in 3:
		var returned: Dictionary = _main.call("current_demand_snapshot")
		assert_eq(returned, live)
		returned["curb_appeal"] = 99.0
		var projected: Dictionary = _main.call("forecast_next_demand")
		assert_eq(projected, forecast)
		projected["curb_appeal"] = 99.0
		var report: DayReport = _main.call("build_report", Clock.sim.day) as DayReport
		assert_not_null(report)
		if report != null:
			assert_eq(report.demand_forecast, forecast)
			report.demand_forecast["curb_appeal"] = 99.0
		assert_eq(_query_state(), before, "queries cannot mutate streams, shop, books or checkpoint")


func test_accepted_front_finish_hang_remove_undo_and_redo_refresh_derived_facts() -> void:
	_start_main()
	_stage_finish_unlock()
	assert_true(_main.call("set_build_active", true))
	var invariants: Dictionary = _edit_invariants()
	var bare: Dictionary = _curb()
	if not _finish_front():
		return
	var finished: Dictionary = _curb()
	assert_true(float(finished["score"]) > 0.0)
	_assert_current_factor()
	assert_true(_main.call("shop_hang", &"street_awning_2", CANOPY, &"sage"))
	var decorated: Dictionary = _curb()
	assert_true(float(decorated["score"]) > float(finished["score"]), "a real additional frontage item is observed")
	_assert_current_factor()
	assert_true(int(_main.call("shop_take_down", CANOPY)) >= 0)
	assert_eq(_curb(), finished, "taking down the item removes its contribution immediately")
	_assert_current_factor()
	assert_true(_main.call("undo_edit"))
	assert_eq(_curb(), decorated, "undoing removal restores the decorated state")
	_assert_current_factor()
	assert_true(_main.call("redo_edit"))
	assert_eq(_curb(), finished)
	assert_true(_main.call("undo_edit")) # Undo the removal again.
	assert_true(_main.call("undo_edit")) # Undo the original awning purchase.
	assert_eq(_curb(), finished)
	assert_true(_main.call("undo_edit")) # Undo the finish.
	assert_eq(_curb(), bare)
	_assert_current_factor()
	assert_true(_main.call("redo_edit"))
	assert_eq(_curb(), finished)
	_assert_current_factor()
	assert_eq(_edit_invariants(), invariants, "accepted edits/history never fetch a stream, redraw a gap or save")


func test_front_edit_uses_existing_demand_once_and_keeps_morning_factors_latched() -> void:
	_start_main()
	var book: ReputationBook = _main.get("reputation") as ReputationBook
	var state: DemandState = _main.get("demand_state") as DemandState
	# A legal divergence after the morning latch makes accidental re-latching visible.
	assert_true(book.from_dict({"version": 1, "scores": [1, 1, 1, 1, 1]}))
	state.renown = 60.0
	var live_before: Dictionary = _main.call("current_demand_snapshot")
	var forecast_before: Dictionary = _main.call("forecast_next_demand")
	var rate_before: float = _sim().arrival_rate()
	assert_true(float(forecast_before["reputation"]) < float(live_before["reputation"]))
	assert_true(float(forecast_before["word_of_mouth"]) > float(live_before["word_of_mouth"]))
	var invariants: Dictionary = _edit_invariants()
	assert_true(_main.call("shop_hang", &"street_awning_2", CANOPY, &"sage"))
	var factor: float = float(_main.get("curb_appeal_factor"))
	assert_true(factor > 1.0 and factor <= 1.1)
	var live: Dictionary = _main.call("current_demand_snapshot")
	var forecast: Dictionary = _main.call("forecast_next_demand")
	for key: String in ["reputation", "word_of_mouth", "menu", "vibe"]:
		assert_eq(live[key], live_before[key], "live %s retains its existing context" % key)
		assert_eq(forecast[key], forecast_before[key], "tomorrow's %s keeps its separate projection" % key)
	assert_almost_eq(float(live["total"]), float(live_before["total"]) * factor)
	assert_almost_eq(_sim().demand_factor, float(live["total"]))
	assert_almost_eq(_sim().arrival_rate(), rate_before * factor, 0.000001,
		"curb appeal enters the existing demand path once, never twice")
	assert_almost_eq(float(forecast["total"]), float(forecast_before["total"]) * factor)
	_assert_current_factor()
	assert_eq(_edit_invariants(), invariants)
	var before_queries: Dictionary = _query_state()
	for repeat: int in 3:
		_main.call("forecast_next_demand")
		_main.call("build_report", Clock.sim.day)
	assert_eq(_query_state(), before_queries)
	_empty_next_morning()
	live = _main.call("current_demand_snapshot")
	assert_eq(live["reputation"], forecast["reputation"], "the next morning performs the real latch")
	assert_eq(live["word_of_mouth"], forecast["word_of_mouth"])
	assert_almost_eq(_sim().demand_factor, float(forecast["total"]))


func test_front_state_saves_only_next_morning_and_reload_recomputes_score_and_factor() -> void:
	_start_main()
	_stage_finish_unlock()
	var morning: String = _saved_text()
	var sections: Array = (_document()["data"] as Dictionary).keys()
	if not _finish_front():
		return
	assert_true(_main.call("shop_hang", &"street_awning_2", CANOPY, &"sage"))
	var decorated: Dictionary = _curb()
	assert_true(float(decorated["score"]) > 0.0)
	assert_eq(_saved_text(), morning, "the entire checkpoint remains untouched after purchases")
	_empty_next_morning()
	var expected_live: Dictionary = _main.call("current_demand_snapshot")
	var expected_forecast: Dictionary = _main.call("forecast_next_demand")
	var expected_items: Array[Array] = _editor().decor.to_rows()
	var expected_finishes: Array[Array] = _editor().walls.to_rows()
	var saved: Dictionary = _document()
	assert_eq((saved["data"] as Dictionary).keys(), sections, "derived curb facts add no save section")
	assert_false((saved["data"] as Dictionary).has("curb_appeal"))
	assert_eq(int(saved["data"]["clock"]["day"]), 2)
	assert_ne(_saved_text(), morning)
	_close_main()
	_start_main()
	assert_eq(Clock.sim.day, 2, "load restores the real morning checkpoint")
	assert_eq(_editor().decor.to_rows(), expected_items)
	assert_eq(_editor().walls.to_rows(), expected_finishes)
	assert_eq(_curb(), decorated, "score/factor are reconstructed from persisted shop facts")
	assert_eq(_main.call("current_demand_snapshot"), expected_live)
	assert_eq(_main.call("forecast_next_demand"), expected_forecast)
	_assert_current_factor()


func test_legacy_bare_checkpoint_and_fresh_run_do_not_inherit_unsaved_front_score() -> void:
	_start_main()
	# This ordinary shop checkpoint has the pre-curb schema: no derived curb section.
	var legacy: String = _saved_text()
	var data: Dictionary = _document()["data"]
	assert_false(data.has("curb_appeal"))
	assert_true((_editor().decor.to_rows()).is_empty())
	assert_true(_main.call("shop_hang", &"street_awning_2", CANOPY, &"sage"))
	assert_true(float(_main.get("curb_appeal_score")) > 0.0)
	assert_eq(_saved_text(), legacy)
	_close_main()
	_start_main()
	_assert_bare()
	assert_eq(_main.call("current_demand_snapshot"), {"reputation": 1.0, "word_of_mouth": 1.0,
		"menu": 1.0, "vibe": 1.0, "curb_appeal": 1.0, "total": 1.0})
	assert_true(_main.call("shop_hang", &"street_awning_2", CANOPY, &"sage"))
	assert_true(float(_main.get("curb_appeal_score")) > 0.0)
	_close_main()
	SaveSystem.delete_slot(SLOT)
	_start_main()
	_assert_bare()
	assert_eq(Clock.sim.day, 1)
	assert_eq(_sim().arrival_rate(), 1.0)


func _start_main() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	(_main.get_node("CameraRig") as CameraRig).set_process(false)
	(_main.get_node("ShopView") as ShopView).set_process(false)
	Clock.set_speed(0)


func _close_main() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _sim() -> RestaurantSim:
	return _main.get("sim") as RestaurantSim


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _stage_finish_unlock() -> void:
	# Explicit progression fixture, matching the existing demand-session unlock
	# pattern. Brick is level three; buying it still uses the real paid edit.
	var owner: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	assert_false(owner.award_bonus(owner.threshold_for(3)).is_empty())
	assert_eq(owner.level, 3)
	_editor().set_owner_level(owner.level)
	assert_true((_main.get("menu_settings") as MenuSettings).set_owner_level(owner.level))


func _finish_front() -> bool:
	var cash_before: int = Economy.cash
	var accepted: bool = bool(_main.call("shop_wall_finishes", {FRONT:
		FloorFinishes.Finish.new(&"brick", &"sage", &"cream")} as Dictionary[Vector3i, FloorFinishes.Finish]))
	assert_true(accepted, "paid street-front brick finish refused: %s" % _editor().last_check.why)
	if accepted:
		var style: WallStyleDef = (_main.get("content") as ContentDB).wall_style(&"brick")
		assert_eq(Economy.cash, cash_before - style.price, "the unlocked finish still pays its authored price")
	return accepted


func _curb() -> Dictionary:
	return {"score": _main.get("curb_appeal_score"), "factor": _main.get("curb_appeal_factor")}


func _assert_bare() -> void:
	assert_eq(_main.get("curb_appeal_score"), 0.0)
	assert_eq(_main.get("curb_appeal_factor"), 1.0)
	_assert_current_factor()


func _assert_current_factor() -> void:
	var factor: float = float(_main.get("curb_appeal_factor"))
	assert_eq((_main.call("current_demand_snapshot") as Dictionary)["curb_appeal"], factor)
	assert_eq((_main.call("forecast_next_demand") as Dictionary)["curb_appeal"], factor)


func _edit_invariants() -> Dictionary:
	var live: Dictionary = _main.call("current_demand_snapshot")
	return {"rng": GameState.call("_capture_save"), "clock": Clock.sim.to_dict(),
		"world_tick": _sim().world.now, "countdown": _sim().spawner._remaining,
		"progress": (_main.get("demand_state") as DemandState).to_dict(),
		"reviews": (_main.get("reputation") as ReputationBook).to_dict(),
		"latched_reputation": live.get("reputation"), "latched_renown": live.get("word_of_mouth"),
		"save": _saved_text()}


func _query_state() -> Dictionary:
	return {"edit_invariants": _edit_invariants(), "curb": _curb(),
		"economy": Economy.call("_capture_save"), "events": _sim().world.event_log.duplicate(),
		"demand": _sim().demand_factor, "rate": _sim().arrival_rate(),
		"items": _editor().decor.to_rows(), "finishes": _editor().walls.to_rows()}


func _empty_next_morning() -> void:
	# A persistence-boundary fixture, not a played service day or RNG comparison.
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _document() -> Dictionary:
	var value: Variant = JSON.parse_string(_saved_text())
	assert_true(value is Dictionary, "a real morning checkpoint must exist")
	return value if value is Dictionary else {}
