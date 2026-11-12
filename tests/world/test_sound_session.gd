extends TestCase
## #117 in the real game session: the door bell, coins and room tone follow
## actual service and go quiet when paused or closed. test_default_play_golden
## (which runs the real session) guards that sound never changes the run.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _mains: Array[Node] = []
var _heard: Array[StringName] = []
var _clinks: Array[StringName] = []


func before_each() -> void:
	_heard.clear()
	_clinks.clear()
	Sfx.reset_throttle()
	Sfx.cue_played.connect(_on_cue)
	Sfx.clink_played.connect(_on_clink)


func after_each() -> void:
	if Sfx.cue_played.is_connected(_on_cue):
		Sfx.cue_played.disconnect(_on_cue)
	if Sfx.clink_played.is_connected(_on_clink):
		Sfx.clink_played.disconnect(_on_clink)
	for main: Node in _mains:
		if is_instance_valid(main):
			if main.is_inside_tree():
				main.get_parent().remove_child(main)
			main.free()
	_mains.clear()
	Sfx.stop_loops()
	Sfx.reset_throttle()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _on_cue(cue: StringName) -> void:
	_heard.append(cue)


func _on_clink(kind: StringName) -> void:
	_clinks.append(kind)


func _start() -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _guests(main: Node) -> int:
	var sim: RestaurantSim = main.get("sim")
	return sim.world.agents.filter(func(agent: SimAgent) -> bool: return agent is CustomerAgent).size()


func test_service_rings_the_door_and_takes_payment_with_sound() -> void:
	var main: Node = _start()
	assert_true(Clock.sim.start_service())
	var guard: int = 0
	while not _heard.has(&"cash") and guard < 4000:
		main.call("run_ticks", 1)
		guard += 1
	assert_true(_heard.has(&"door_bell"), "a guest walked in: %s" % [_heard])
	assert_true(_heard.has(&"cash"), "a guest paid: %s" % [_heard])


func test_room_tone_follows_the_crowd_and_stops_when_paused_or_closed() -> void:
	var main: Node = _start()
	var sound: SoundDirector = main.get("sound")
	assert_not_null(sound, "the session owns a sound director")
	Clock.set_speed(1)
	main.call("refresh_presentation")
	assert_almost_eq(Sfx.loop_level(&"room_tone"), 0.0, 0.0001, "silent in the morning")
	Clock.set_speed(0)
	assert_true(Clock.sim.start_service())
	var guard: int = 0
	while _guests(main) < 2 and guard < 4000:
		main.call("run_ticks", 1)
		guard += 1
	Clock.set_speed(1)
	main.call("refresh_presentation")
	var expected: float = minf(float(_guests(main)) / float(Sfx.ambience.room_tone_full_guests), 1.0)
	assert_true(Sfx.loop_level(&"room_tone") > 0.0, "a room with guests has a tone")
	assert_almost_eq(Sfx.loop_level(&"room_tone"), expected, 0.0001, "scaled by the crowd")
	Clock.set_speed(0)
	main.call("refresh_presentation")
	assert_almost_eq(Sfx.loop_level(&"room_tone"), 0.0, 0.0001, "paused is silent")



## #366: clinks follow real events while the shop is open and running.
func test_a_delivered_meal_sets_a_plate_down_with_a_clink() -> void:
	var main: Node = _start()
	Clock.set_speed(1)
	main.call("refresh_presentation")
	assert_true(_clinks.is_empty(), "nothing clinks in the morning: %s" % [_clinks])
	assert_true(Clock.sim.start_service())
	var guard: int = 0
	while not _clinks.has(&"plate") and guard < 6000:
		main.call("run_ticks", 1)
		guard += 1
	assert_true(_clinks.has(&"plate"), "a meal reached a table: %s" % [_clinks])
	for kind: StringName in _clinks:
		assert_true([&"plate", &"glass", &"cutlery", &"dish_stack", &"sink"].has(kind), "known clink %s" % kind)


func test_a_paused_shop_and_the_title_backdrop_stay_quiet() -> void:
	var main: Node = _start()
	Clock.set_speed(0)
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 2500)
	assert_true(_clinks.is_empty(), "paused service never clinks: %s" % [_clinks])
	var sound: SoundDirector = main.get("sound")
	sound.display_only = true
	Clock.set_speed(1)
	main.call("run_ticks", 2500)
	assert_true(_clinks.is_empty(), "a display-only session never clinks: %s" % [_clinks])
	assert_almost_eq(Sfx.loop_level(&"room_tone"), 0.0, 0.0001, "nor plays the room tone")
	for layer: StringName in AmbienceTuning.CHATTER_LAYERS:
		assert_almost_eq(Sfx.loop_level(layer), 0.0, 0.0001, "nor chatter")
