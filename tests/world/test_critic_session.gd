extends TestCase
## The real session wires the food critic (#303): a lazy stream, the morning roll and the save.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const CRITIC: CriticTuning = preload("res://data/balance/critic.tres")
const SLOT: String = "critic_session"
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
	_sim().set_customer_level(_progress().level)


func _always() -> void:
	var tuning: CriticTuning = CRITIC.duplicate() as CriticTuning
	tuning.daily_chance = 1.0
	_sim().critic.tuning = tuning


func _morning(day: int) -> void:
	Clock.sim.day = day
	_main.call("_begin_morning")


func test_below_level_two_no_critic_stream_is_ever_created() -> void:
	_start()
	for day: int in range(2, 12):
		_morning(day)
	assert_false(_sim().critic.pending)
	assert_eq(_sim().critic.last_visit_day, 0)
	assert_false((GameState._capture_save()["rngs"] as Dictionary).has("critic"),
		"shops that cannot have a critic never create the stream")


func test_level_two_rolls_the_morning_once_from_the_named_stream() -> void:
	_start()
	_level(CRITIC.unlock_level)
	_always()
	_morning(2)
	assert_true(_sim().critic.pending)
	assert_eq(_sim().critic.last_visit_day, 2)
	assert_true((GameState._capture_save()["rngs"] as Dictionary).has("critic"))
	var state: int = GameState.rng(&"critic").state
	_main.call("_begin_morning")
	assert_eq(GameState.rng(&"critic").state, state, "the same morning is not rolled twice")
	_morning(3)
	assert_false(_sim().critic.pending, "inside the five-day cooldown")


func test_the_cooldown_and_todays_plan_survive_the_morning_save() -> void:
	_start(true)
	_level(CRITIC.unlock_level)
	_always()
	_morning(4)
	var tells: Array[StringName] = _sim().critic.tells.duplicate()
	assert_eq(tells.size(), 2)
	_morning(5)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved: Dictionary = document["data"]["critic"]
	assert_eq(int(saved["last_visit_day"]), 4)
	_close()
	_start(true)
	assert_eq(Clock.sim.day, 5)
	assert_eq(_sim().critic.last_visit_day, 4, "mid-week, the cooldown is kept")
	assert_false(_sim().critic.can_visit(8, 2))
	assert_true(_sim().critic.can_visit(9, 2))


func test_an_old_save_without_a_critic_section_loads() -> void:
	_start(true)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	document["data"].erase("critic")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close()
	_start(true)
	assert_eq(_sim().critic.last_visit_day, 0)
