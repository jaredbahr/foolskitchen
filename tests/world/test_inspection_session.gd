extends TestCase
## The real session owns the health inspector's draw, report line, window card,
## hygiene line, demand nudge and save (#302).

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: InspectionTuning = preload("res://data/balance/inspection.tres")
const SLOT: String = "inspection_session"
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


func _level(level: int) -> void:
	var progress: OwnerProgress = _main.get("owner_progress")
	progress.award_bonus(progress.threshold_for(level))


func _next_morning() -> void:
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")


func _streams() -> Dictionary:
	return GameState._capture_save()["rngs"]


func _inspect_today() -> void:
	_sim().inspection.planned_day = Clock.sim.day
	_sim().inspection.planned_tick = 5
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)


func test_a_game_below_level_three_never_creates_the_stream() -> void:
	_start()
	for day: int in 12:
		_next_morning()
	assert_false(_streams().has("inspector"), "no inspections yet, no stream")
	assert_eq(_sim().inspection.planned_tick, -1)


func _below_level_three_run(disabled: bool) -> Dictionary:
	_start()
	if disabled:
		# The same shop with inspections switched off for good.
		var off: InspectionTuning = TUNING.duplicate(true) as InspectionTuning
		off.unlock_level = 1000000
		_sim().inspection.tuning = off
	var served: Array[int] = []
	for day: int in 2:
		assert_true(Clock.sim.start_service())
		_main.call("run_ticks", 6000)
		served.append(_sim().served_today)
		if day == 0:
			assert_true(Clock.sim.next_day())
		assert_true((_main.get("owner_progress") as OwnerProgress).level < TUNING.unlock_level, "still below level 3")
	var result: Dictionary = {"served": served, "streams": GameState._capture_save(),
		"cash": Economy.cash}
	_close()
	Economy.reset(0)
	GameState.new_run(1)
	return result


func test_below_level_three_a_run_is_identical_to_one_with_inspections_off() -> void:
	var with_system: Dictionary = _below_level_three_run(false)
	var without: Dictionary = _below_level_three_run(true)
	assert_true((with_system["served"] as Array).size() == 2 and int((with_system["served"] as Array)[0]) > 0)
	assert_eq(with_system["served"], without["served"], "the same guests served each day")
	assert_eq(with_system["streams"], without["streams"], "every saved random stream is identical")
	assert_eq(with_system["cash"], without["cash"])
	assert_false((with_system["streams"]["rngs"] as Dictionary).has("inspector"))


func test_the_stream_appears_once_inspections_can_happen_and_the_draw_is_seeded() -> void:
	_start()
	_level(TUNING.unlock_level)
	var visits: Array[int] = []
	for day: int in 80:
		_next_morning()
		if _sim().inspection.planned_tick >= 0:
			visits.append(Clock.sim.day)
			_sim().inspection.record(Clock.sim.day, {"grade": &"A", "findings": []})
	assert_true(_streams().has("inspector"))
	assert_true(visits.size() >= 2)
	var first: Array[int] = visits.duplicate()
	_close()
	Economy.reset(0)
	GameState.new_run(1)
	_start()
	_level(TUNING.unlock_level)
	var again: Array[int] = []
	for day: int in 80:
		_next_morning()
		if _sim().inspection.planned_tick >= 0:
			again.append(Clock.sim.day)
			_sim().inspection.record(Clock.sim.day, {"grade": &"A", "findings": []})
	assert_eq(again, first, "the same seed visits on the same days")


func test_the_evening_report_names_the_grade_and_worst_findings() -> void:
	_start()
	_level(TUNING.unlock_level)
	_inspect_today()
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(report)
	assert_true(report.inspection_lines.size() >= 2, str(report.inspection_lines))
	assert_true(report.inspection_lines[0].begins_with("Health inspection: grade "))
	var saved: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(saved.inspection_lines, report.inspection_lines)
	var screen: Node = _main.get_node("Overlay/EveningReport") if _main.has_node("Overlay/EveningReport") else null
	if screen != null:
		var label: Label = screen.get_node_or_null("Panel/Scroll/Content/Inspection") as Label
		assert_not_null(label)
		assert_true(label.visible)
		assert_true(label.text.begins_with("Health inspection: grade "))


func test_a_day_without_a_visit_has_no_inspection_lines() -> void:
	_start()
	_level(TUNING.unlock_level)
	_sim().inspection.planned_day = Clock.sim.day
	_sim().inspection.planned_tick = -1
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	var report: DayReport = _main.get("shown_report") as DayReport
	assert_true(report.inspection_lines.is_empty())
	assert_false(report.to_dict().has("inspection_lines"), "older report shape is unchanged")


func test_the_grade_card_hangs_in_the_window_and_stays_until_the_next_inspection() -> void:
	_start()
	var view: ShopView = _main.get_node("ShopView")
	view._process(0.0)
	assert_null(view.wall_finish_view.grade_card(), "no card before an inspection")
	_sim().inspection.record(4, {"grade": &"B", "findings": []})
	view._process(0.0)
	var card: Node3D = view.wall_finish_view.grade_card()
	assert_not_null(card)
	assert_eq((card.get_node("Letter") as Label3D).text, "B")
	_sim().inspection.record(12, {"grade": &"A", "findings": []})
	view._process(0.0)
	assert_eq((view.wall_finish_view.grade_card().get_node("Letter") as Label3D).text, "A")


func test_the_hygiene_overview_shows_the_last_inspection() -> void:
	_start()
	var level_one: HygieneOverview.Snapshot = HygieneOverview.capture(_sim())
	assert_eq(level_one.inspection_line, "", "nothing about inspections before they are possible")
	_level(TUNING.unlock_level)
	_sim().set_customer_level(TUNING.unlock_level)
	assert_eq(HygieneOverview.capture(_sim()).inspection_line, "Last inspection: none yet")
	_sim().inspection.record(12, {"grade": &"B", "findings": []})
	var lines: PackedStringArray = HygieneOverview.lines(HygieneOverview.capture(_sim()))
	assert_eq(lines[lines.size() - 1], "Last inspection: B, day 12")


func test_the_grade_moves_arrivals_for_exactly_seven_days() -> void:
	_start()
	_level(TUNING.unlock_level)
	_next_morning()
	var base: float = _sim().demand_factor
	_sim().inspection.record(Clock.sim.day, {"grade": &"C", "findings": []})
	# The forecast for tomorrow already carries the grade.
	var forecast: Dictionary = _main.call("forecast_next_demand")
	assert_almost_eq(float(forecast["curb_appeal"]), 0.9, 0.0001)
	var day: int = Clock.sim.day
	for offset: int in range(1, 9):
		_next_morning()
		var expected: float = 0.9 if offset <= 7 else 1.0
		assert_almost_eq(_sim().demand_factor, minf(base * expected, 3.0), 0.0001, "day +%d" % offset)
	assert_eq(Clock.sim.day, day + 8)


func test_the_grade_survives_a_save_and_an_old_save_has_none() -> void:
	_start(true)
	_level(TUNING.unlock_level)
	_sim().inspection.record(5, {"grade": &"B", "findings": []})
	_next_morning()
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved: Dictionary = document["data"]["inspection"]
	assert_eq(String(saved["last_grade"]), "B")
	assert_eq(int(saved["last_day"]), 5)
	_close()
	_start(true)
	assert_eq(_sim().inspection.last_grade, &"B")
	assert_eq(_sim().inspection.last_day, 5)
	var view: ShopView = _main.get_node("ShopView")
	view._process(0.0)
	assert_not_null(view.wall_finish_view.grade_card(), "the card is back in the window")
	# An older save has no section at all.
	document["data"].erase("inspection")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close()
	_start(true)
	assert_eq(_sim().inspection.last_grade, &"")


func test_reloading_the_same_morning_does_not_draw_again() -> void:
	_start(true)
	_level(TUNING.unlock_level)
	for day: int in 30:
		_next_morning()
	var state: String = str(GameState.rng(&"inspector").state)
	var planned: int = _sim().inspection.planned_tick
	_main.call("_begin_morning")
	assert_eq(str(GameState.rng(&"inspector").state), state)
	assert_eq(_sim().inspection.planned_tick, planned)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(document["data"]["inspection"]["planned_day"]), Clock.sim.day)
	_close()
	_start(true)
	assert_eq(str(GameState.rng(&"inspector").state), state, "a load keeps the stream where it was")
	assert_eq(_sim().inspection.planned_tick, planned)


func test_a_broken_section_refuses_the_load() -> void:
	_start(true)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	document["data"]["inspection"] = {"version": 1, "last_grade": "Z", "last_day": 3, "planned_day": 1, "planned_tick": -1}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close()
	_start(true)
	assert_eq(_sim().inspection.last_grade, &"")
