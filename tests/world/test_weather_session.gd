extends TestCase
## Daily weather joins the real morning checkpoint without changing its other state.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "weather_session"

var _main: Node
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	_close_main()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_real_next_morning_checkpoint_saves_chosen_weather_and_its_named_stream() -> void:
	_start_main()
	assert_eq(Clock.sim.day, 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	var first_text: String = FileAccess.get_file_as_string(_path())
	assert_false(first_text.is_empty(), "the normal first morning creates an autosave")
	var first: Dictionary = _dictionary(_document().get("data"), "the first save has its normal data sections")
	var first_clock: Dictionary = _dictionary(first.get("clock"), "the first save contains the real clock")
	assert_eq(first_clock.get("day"), 1.0)
	# Skip service only in this persistence fixture, using the existing next-day path.
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_ne(FileAccess.get_file_as_string(_path()), first_text, "a genuine new morning replaces the checkpoint")
	var data: Dictionary = _dictionary(_document().get("data"), "the new checkpoint has its data sections")
	var saved_clock: Dictionary = _dictionary(data.get("clock"), "the morning checkpoint saves the clock")
	assert_eq(saved_clock, _json(Clock.sim.to_dict()), "the saved day and phase match the live morning")
	assert_eq(data.get("economy"), _json(Economy.call("_capture_save")), "the ordinary books and stock still round-trip")
	var saved_game: Dictionary = _dictionary(data.get("game_state"), "the morning checkpoint saves the named random streams")
	assert_eq(saved_game, _json(GameState.call("_capture_save")), "saved RNGs match the live streams without inspecting by creation")
	var shop: Dictionary = _dictionary(data.get("shop"), "the ordinary shop section remains present")
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	assert_eq(shop.get("items"), _json(editor.to_dict()["items"]), "weather leaves the saved furniture intact")
	var streams: Dictionary = _dictionary(saved_game.get("rngs"), "the normal RNG save includes its stream map")
	# These functional assertions compile against the pre-weather game's existing APIs.
	var weather: Dictionary = _dictionary(data.get("weather"), "the real morning checkpoint includes chosen weather")
	assert_eq(weather.get("day", -1.0), 2.0, "weather is already chosen for the day being saved")
	assert_true(weather.get("kind", -1.0) in [0.0, 1.0, 2.0], "the chosen kind is sunny, cloudy or rain")
	assert_true(streams.has("weather"), "choosing the morning weather saves its own named stream")


func _start_main() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 241)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)


func _close_main() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(_path())
	if text.is_empty():
		fail("the real morning autosave must exist before its sections are inspected")
		return {}
	return _dictionary(JSON.parse_string(text), "the real autosave is a JSON object")


func _dictionary(value: Variant, message: String) -> Dictionary:
	assert_true(value is Dictionary, message)
	return value if value is Dictionary else {}


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


var _reject_reached: bool = false
var _reject_saw_staged_weather: bool = false


func test_current_save_keeps_weather_and_stream_on_the_final_replacement_world() -> void:
	_start_main()
	_advance_morning()
	var expected: Dictionary = _weather().to_dict()
	var saved_stream: Dictionary = _dictionary(_streams().get("weather"), "weather was selected")
	_close_main()
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 241)
	_main.call("initialize")
	var original_world: SimWorld = _main.get("world") as SimWorld
	assert_eq(original_world.weather.day, 0)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)
	var final_world: SimWorld = _main.get("world") as SimWorld
	assert_true(final_world != original_world, "the saved shop creates the final restaurant world")
	assert_true(Clock.attached_world == final_world)
	assert_eq(final_world.weather.to_dict(), expected)
	assert_eq(original_world.weather.day, 0, "staged weather is not installed on the discarded world")
	assert_eq(_streams().get("weather"), saved_stream, "loading today's choice does not draw again")


func test_absent_legacy_section_is_sunny_for_saved_day_without_fetching_a_stream() -> void:
	_start_main()
	var legacy: Dictionary = _document()
	var data: Dictionary = legacy["data"]
	data.erase("weather")
	(data["game_state"]["rngs"] as Dictionary).erase("weather")
	_write_document(legacy)
	_close_main()
	_start_main()
	assert_eq(_weather().kind, WeatherState.Kind.SUNNY)
	assert_eq(_weather().day, Clock.sim.day)
	assert_false(_streams().has("weather"), "a legacy sunny choice is already selected without fetching an RNG")
	_advance_morning()
	assert_eq(_weather().day, 2)
	assert_true(_streams().has("weather"), "the next new morning draws normally")
	assert_eq(_document()["data"]["weather"], _json(_weather().to_dict()))


func test_malformed_present_weather_and_mismatched_day_are_failed_loads_not_legacy_defaults() -> void:
	_start_main()
	var valid: Dictionary = _document()
	var fresh_weather: Dictionary = _weather().to_dict()
	var fresh_stream: Variant = _streams().get("weather")
	for bad: Variant in [{}, {"version": 1, "day": 1, "kind": 9},
		{"version": 1, "day": 2, "kind": 2}, ["rain"]]:
		var malformed: Dictionary = valid.duplicate(true)
		malformed["data"]["weather"] = bad
		_write_document(malformed)
		var failing_text: String = FileAccess.get_file_as_string(_path())
		_close_main()
		_start_main()
		assert_eq(_weather().to_dict(), fresh_weather, "a failed load starts a fresh selected day")
		assert_eq(_streams().get("weather"), fresh_stream)
		assert_true(_streams().has("weather"), "malformed present state is not treated as missing legacy state")
		assert_eq(FileAccess.get_file_as_string(_path()), failing_text, "failed startup preserves its existing checkpoint")
	_advance_morning()
	assert_eq(_document()["data"]["weather"]["day"], 2.0, "later normal morning saves resume")


func test_restore_provider_stages_without_live_weather_rng_or_file_changes() -> void:
	_start_main()
	var weather: Dictionary = _weather().to_dict()
	var random: Dictionary = GameState.call("_capture_save")
	var morning: String = FileAccess.get_file_as_string(_path())
	assert_true(_main.call("_restore_weather", {"version": 1, "day": 7, "kind": 2}))
	assert_eq(_weather().to_dict(), weather)
	assert_eq(GameState.call("_capture_save"), random)
	assert_eq(FileAccess.get_file_as_string(_path()), morning)
	assert_false(_main.call("_restore_weather", {"version": 1, "day": 0, "kind": 2}))
	assert_eq(_weather().to_dict(), weather)
	assert_eq(GameState.call("_capture_save"), random)


func test_late_whole_load_failure_cannot_install_staged_weather_or_leak_it_into_new_game() -> void:
	_start_main()
	var fresh_weather: Dictionary = _weather().to_dict()
	var fresh_stream: Variant = _streams().get("weather")
	var document: Dictionary = _document()
	document["data"]["clock"]["day"] = 7
	document["data"]["weather"] = {"version": 1, "day": 7, "kind": 2}
	document["data"]["weather_test_reject"] = {}
	SaveSystem.register("weather_test_reject", _empty_capture, _reject_after_weather)
	_write_document(document)
	var failing_text: String = FileAccess.get_file_as_string(_path())
	_close_main()
	_start_main()
	assert_true(_reject_reached, "the test reaches a real provider after weather restoration")
	assert_true(_reject_saw_staged_weather, "valid day7 rain was staged before the later provider refused")
	assert_eq(_weather().to_dict(), fresh_weather)
	assert_eq(_streams().get("weather"), fresh_stream)
	assert_null(_main.get("_loaded_weather"), "new game clears pending weather after the whole-load failure")
	assert_eq(FileAccess.get_file_as_string(_path()), failing_text)
	_advance_morning()
	assert_eq(_weather().day, 2)
	assert_eq(_document()["data"]["weather"], _json(_weather().to_dict()))


func test_reentering_the_same_morning_does_not_redraw_weather() -> void:
	_start_main()
	var weather: Dictionary = _weather().to_dict()
	var stream: Variant = _streams().get("weather")
	for repeat: int in 3:
		_main.call("_begin_morning")
		assert_eq(_weather().to_dict(), weather)
		assert_eq(_streams().get("weather"), stream)
		assert_eq(_document()["data"]["weather"], _json(weather))


func test_game_state_reset_uses_the_new_named_weather_stream_at_the_next_morning() -> void:
	_start_main()
	GameState.new_run(91241)
	assert_false(_streams().has("weather"))
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = hash("91241:weather")
	expected.randf()
	_advance_morning()
	var actual: Dictionary = _dictionary(_streams().get("weather"), "the new run creates its own weather stream")
	assert_eq(actual.get("seed"), str(expected.seed))
	assert_eq(actual.get("state"), str(expected.state), "the next morning never uses a retained pre-reset RNG")


func test_invalid_main_tuning_does_not_even_fetch_a_missing_weather_stream() -> void:
	_start_main()
	GameState.new_run(91242)
	(_main.get("world") as SimWorld).weather = WeatherState.new()
	_main.set("weather_tuning", WeatherTuning.new())
	var before: Dictionary = GameState.call("_capture_save")
	var morning: String = FileAccess.get_file_as_string(_path())
	assert_false(_main.call("_select_morning_weather"))
	assert_eq(_weather().day, 0)
	assert_eq(GameState.call("_capture_save"), before)
	assert_false(_streams().has("weather"))
	assert_eq(FileAccess.get_file_as_string(_path()), morning)


func test_weather_presentation_changes_no_gameplay_streams_or_checkpoint() -> void:
	_start_main()
	var before: Dictionary = _gameplay_snapshot()
	var morning: String = FileAccess.get_file_as_string(_path())
	var world: SimWorld = _main.get("world") as SimWorld
	assert_false(world.grid.find_guest_path(world.grid.entries()[0], Vector2i(6, 9)).is_empty())
	for kind: int in [WeatherState.Kind.SUNNY, WeatherState.Kind.CLOUDY, WeatherState.Kind.RAIN]:
		world.weather.kind = kind as WeatherState.Kind
		_main.call("refresh_presentation")
		assert_eq(_gameplay_snapshot(), before)
		assert_eq(FileAccess.get_file_as_string(_path()), morning, "a forecast/view refresh is never a save point")


func _weather() -> WeatherState:
	return (_main.get("world") as SimWorld).weather


func _streams() -> Dictionary:
	var game: Dictionary = GameState.call("_capture_save")
	return _dictionary(game.get("rngs"), "the live named-stream map exists")


func _advance_morning() -> void:
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	Clock.set_speed(0)


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify(document))
		file.close()
	DirAccess.remove_absolute(_path() + ".bak")


func _empty_capture() -> Dictionary:
	return {}


func _reject_after_weather(_data: Dictionary) -> bool:
	_reject_reached = true
	var staged: Variant = _main.get("_loaded_weather")
	_reject_saw_staged_weather = staged is WeatherState and staged.day == 7 and staged.kind == WeatherState.Kind.RAIN
	return false


func _gameplay_snapshot() -> Dictionary:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	var world: SimWorld = _main.get("world") as SimWorld
	var vibe: VibeModel.Result = _main.get("vibe_result") as VibeModel.Result
	return {"clock": Clock.sim.to_dict(), "world_tick": world.now, "economy": Economy.call("_capture_save"),
		"rngs": GameState.call("_capture_save"), "items": editor.to_dict()["items"],
		"menu": (_main.get("menu_settings") as MenuSettings).to_dict(),
		"arrivals": [sim.spawner.min_gap, sim.spawner.max_gap],
		"path": world.grid.find_guest_path(world.grid.entries()[0], Vector2i(6, 9)),
		"vibe": [vibe.score, vibe.active_theme, vibe.arrival_theme_strength]}
