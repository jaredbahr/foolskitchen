extends TestCase
## Explicit close-data fixtures exercise the real Main morning/save lifecycle.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "viral_session"

var _main: Node
var _providers: Dictionary[String, Dictionary]
var _old_dir: String
var _dir: String
var _processing: bool
var _speed: int
var _late_reject: bool = false
var _staged_before_reject: bool = false


func before_each() -> void:
	_providers = SaveSystem._providers.duplicate(true)
	_old_dir = SaveSystem.save_dir
	_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _dir
	_processing = Clock.is_processing()
	_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)
	_late_reject = false
	_staged_before_reject = false
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_speed)
	Clock.set_process(_processing)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 335)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _path() -> String:
	return _dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path())) as Dictionary


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify(document))
		file.close()
	DirAccess.remove_absolute(_path() + ".bak")


func _qualifying_close() -> void:
	(_main.get("viral_tuning") as ViralTuning).viral_chance = 1.0
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	# This is declared close data, not a played service or a balance measurement.
	sim.served_today = 34
	sim.lost_today = 6
	sim.leave_reasons_today[&"happy"] = 34
	var sold: Dictionary[StringName, int] = {&"tomato_soup": 20, &"grilled_cheese": 14}
	_main.set("dishes_sold_today", sold)
	Clock.sim.phase = SimClock.Phase.CLOSED
	_main.call("_on_service_closed", Clock.sim.day)


func test_close_rolls_once_without_saving_and_report_queries_are_pure() -> void:
	_start()
	var checkpoint: String = FileAccess.get_file_as_string(_path())
	assert_false((GameState._capture_save()["rngs"] as Dictionary).has("viral"))
	_qualifying_close()
	var book: ViralReview = _main.get("viral_review") as ViralReview
	assert_true(book.triggered_on(1))
	assert_eq(book.dish, &"tomato_soup")
	assert_eq(FileAccess.get_file_as_string(_path()), checkpoint, "Close is not an autosave")
	var state: Dictionary = book.to_dict()
	var random: Dictionary = GameState._capture_save()
	for index: int in range(3):
		_main.call("_on_service_closed", 1)
		var report: DayReport = _main.call("build_report", 1) as DayReport
		assert_eq(report.viral_line, ViralReviewText.evening("Tomato soup"))
		assert_almost_eq(report.demand_forecast["viral"], 1.35)
	assert_eq(book.to_dict(), state)
	assert_eq(GameState._capture_save(), random)
	assert_eq(FileAccess.get_file_as_string(_path()), checkpoint)


func test_next_morning_saves_and_reload_preserves_remaining_services_and_stream() -> void:
	_start()
	_qualifying_close()
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.day, 2)
	var book: ViralReview = _main.get("viral_review") as ViralReview
	var state: Dictionary = book.to_dict()
	var random: Dictionary = GameState._capture_save()
	var saved_stream: Dictionary = (random["rngs"] as Dictionary)["viral"].duplicate(true)
	assert_eq(_document()["data"]["game_state"]["rngs"]["viral"], saved_stream)
	assert_eq(_document()["data"]["viral"], JSON.parse_string(JSON.stringify(state)))
	assert_almost_eq((_main.call("current_demand_snapshot") as Dictionary)["viral"], 1.35)
	_close()
	_start()
	assert_eq(Clock.sim.day, 2)
	assert_eq((_main.get("viral_review") as ViralReview).to_dict(), state)
	# Loading a morning redraws the existing customers' first arrival gap.
	# Preserve every other stream/key/seed; normalize only that known state.
	# The viral stream and its next draw must continue the checkpoint exactly.
	var loaded: Dictionary = GameState._capture_save()
	assert_eq(loaded["master_seed"], random["master_seed"])
	assert_eq((loaded["rngs"] as Dictionary).get("viral"), saved_stream)
	var prior_customers: Dictionary = (random["rngs"] as Dictionary)["customers"]
	var loaded_customers: Dictionary = (loaded["rngs"] as Dictionary)["customers"]
	assert_eq(loaded_customers.get("seed"), prior_customers["seed"], "Customer seed stays fixed")
	assert_true(loaded_customers.has("state"), "The customer state key must still exist")
	var comparable: Dictionary = loaded.duplicate(true)
	comparable["rngs"]["customers"]["state"] = prior_customers["state"]
	assert_eq(comparable, random, "Only the ordinary customer first-gap state may advance")
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = String(saved_stream["seed"]).to_int()
	expected.state = String(saved_stream["state"]).to_int()
	assert_eq(GameState.rng(&"viral").randi(), expected.randi(), "Exact next-draw continuation")
	assert_eq(_document()["data"]["viral"], JSON.parse_string(JSON.stringify(state)),
		"The existing morning autosave preserves the same remaining services")
	var notice: Label = (_main.get("_menu_panel") as MenuPanel).get_node("%ViralNotice") as Label
	assert_true(notice.text.contains("+35%"))


func test_old_save_absent_section_and_new_game_are_neutral() -> void:
	_start()
	var document: Dictionary = _document()
	document["data"].erase("viral")
	_write(document)
	_close()
	_start()
	assert_almost_eq((_main.get("viral_review") as ViralReview).factor(1), 1.0)
	assert_false((_main.call("current_demand_snapshot") as Dictionary).has("viral"))
	assert_false((GameState._capture_save()["rngs"] as Dictionary).has("viral"))
	_qualifying_close()
	_main.call("_new_game")
	assert_eq((_main.get("viral_review") as ViralReview).last_trigger_day, 0)
	assert_almost_eq((_main.get("viral_review") as ViralReview).factor(2), 1.0)


func test_later_provider_rejection_never_installs_staged_spell() -> void:
	_start()
	_qualifying_close()
	assert_true(Clock.sim.next_day())
	var document: Dictionary = _document()
	document["data"]["viral_reject"] = {}
	SaveSystem.register("viral_reject", _empty, _reject)
	_write(document)
	var rejected_bytes: String = FileAccess.get_file_as_string(_path())
	_close()
	_start()
	assert_true(_late_reject)
	assert_true(_staged_before_reject, "Real provider order reached staged viral before rejecting")
	assert_null(_main.get("_loaded_viral"))
	assert_eq((_main.get("viral_review") as ViralReview).last_trigger_day, 0)
	assert_eq(FileAccess.get_file_as_string(_path()), rejected_bytes)


func _empty() -> Dictionary:
	return {}


func _reject(_data: Dictionary) -> bool:
	_late_reject = true
	var staged: ViralReview = _main.get("_loaded_viral") as ViralReview
	_staged_before_reject = staged != null and staged.last_trigger_day == 1
	return false
