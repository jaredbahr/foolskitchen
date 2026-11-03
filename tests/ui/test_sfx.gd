extends TestCase
## #117: the Sfx autoload, its tuning and the shared throttle.

const TUNING: SoundTuning = preload("res://data/audio/sound_tuning.tres")
const ISSUE_CUES: Array[StringName] = [&"click", &"hover", &"door_bell", &"cash", &"star_chime",
	&"level_up", &"milestone", &"back_door", &"delivery_drop"]
const ISSUE_LOOPS: Array[StringName] = [&"room_tone", &"stove_sizzle", &"fryer_bubble", &"coffee_steam"]

var _heard: Array[StringName] = []


func before_each() -> void:
	_heard.clear()
	Sfx.reset_throttle()
	Sfx.cue_played.connect(_on_cue)


func after_each() -> void:
	if Sfx.cue_played.is_connected(_on_cue):
		Sfx.cue_played.disconnect(_on_cue)
	Sfx.stop_loops()
	Sfx.reset_throttle()


func _on_cue(cue: StringName) -> void:
	_heard.append(cue)


func test_tuning_names_every_cue_and_loop_with_a_loaded_stream() -> void:
	assert_true(TUNING.is_valid())
	for cue: StringName in ISSUE_CUES:
		assert_true(TUNING.cues.has(cue), "cue %s" % cue)
		assert_true(TUNING.cues[cue] is AudioStream, "cue %s has a stream" % cue)
		assert_true(TUNING.interval(cue) > 0.0, "cue %s is throttled" % cue)
	for loop: StringName in ISSUE_LOOPS:
		assert_true(TUNING.loops.has(loop), "loop %s" % loop)
		assert_true(TUNING.loops[loop].get_length() >= 3.0, "loop %s is long enough to not drone" % loop)
	assert_almost_eq(TUNING.interval(&"cash"), 0.3, 0.0001, "the issue's cash throttle")


func test_sounds_use_the_effects_bus_that_settings_controls() -> void:
	assert_eq(Sfx.BUS, &"Effects")
	assert_true(AudioServer.get_bus_index(Sfx.BUS) >= 0, "the bus layout has Effects")


func test_throttle_lets_a_cue_through_once_per_interval() -> void:
	var throttle: SoundThrottle = SoundThrottle.new()
	assert_true(throttle.allow(&"cash", 10.0, 0.3))
	assert_false(throttle.allow(&"cash", 10.2, 0.3), "too soon")
	assert_true(throttle.allow(&"door_bell", 10.2, 0.5), "each cue has its own clock")
	assert_true(throttle.allow(&"cash", 10.31, 0.3), "once the interval has passed")
	throttle.reset()
	assert_true(throttle.allow(&"cash", 10.32, 0.3))


func test_play_reports_the_cue_headless_and_throttles_bursts() -> void:
	assert_true(Sfx.play(&"cash"))
	assert_false(Sfx.play(&"cash"), "a burst of payments in one frame plays once")
	assert_true(Sfx.play(&"door_bell"))
	assert_false(Sfx.play(&"no_such_cue"))
	assert_eq(_heard, [&"cash", &"door_bell"] as Array[StringName])


func test_every_button_clicks_including_ones_added_later() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var button: Button = Button.new()
	tree.root.add_child(button)
	button.pressed.emit()
	assert_eq(_heard, [&"click"] as Array[StringName])
	tree.root.remove_child(button)
	tree.root.add_child(button)
	Sfx.reset_throttle()
	_heard.clear()
	button.pressed.emit()
	assert_eq(_heard, [&"click"] as Array[StringName], "re-adding a button never doubles its click")
	button.disabled = true
	button.mouse_entered.emit()
	assert_false(_heard.has(&"hover"), "disabled buttons stay quiet on hover")
	button.free()


func test_loop_levels_clamp_and_stop_together() -> void:
	Sfx.set_loop_level(&"room_tone", 3.0)
	assert_almost_eq(Sfx.loop_level(&"room_tone"), 1.0)
	Sfx.set_loop_level(&"stove_sizzle", 0.5)
	Sfx.set_loop_level(&"no_such_loop", 1.0)
	assert_almost_eq(Sfx.loop_level(&"no_such_loop"), 0.0)
	Sfx.stop_loops()
	for loop: StringName in ISSUE_LOOPS:
		assert_almost_eq(Sfx.loop_level(loop), 0.0, 0.0001, "%s stopped" % loop)


func test_station_level_rises_gently_with_more_busy_stations() -> void:
	assert_almost_eq(SoundDirector.station_level(0), 0.0)
	assert_almost_eq(SoundDirector.station_level(1), SoundDirector.ONE_STATION_LEVEL)
	assert_true(SoundDirector.station_level(2) > SoundDirector.station_level(1))
	assert_almost_eq(SoundDirector.station_level(20), 1.0, 0.0001, "never above full level")


func test_tool_runs_and_headless_runs_stay_silent() -> void:
	assert_true(Sfx.is_silent_run("headless", PackedStringArray()))
	assert_true(Sfx.is_silent_run("X11", PackedStringArray(["--path", ".", "--script", "tools/screenshot.gd"])))
	assert_true(Sfx.is_silent_run("X11", PackedStringArray(["--script=tools/balance_probe.gd"])))
	assert_false(Sfx.is_silent_run("X11", PackedStringArray(["--path", "."])), "the real game plays sound")
