extends TestCase
## #208: the day's light is a pure function of the clock. Morning prep keeps
## the authored rig exactly; nights dim the sun, light the shop and brighten
## glowing signs. Presentation only.

const TUNING: DayLightTuning = preload("res://data/look/day_light.tres")
const RIG: PackedScene = preload("res://src/world/lighting_rig.tscn")
const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _mains: Array[Node] = []


func after_each() -> void:
	for main: Node in _mains:
		if is_instance_valid(main):
			if main.is_inside_tree():
				main.get_parent().remove_child(main)
			main.free()
	_mains.clear()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _clock(phase: SimClock.Phase, phase_tick: int = 0) -> SimClock:
	var clock: SimClock = SimClock.new()
	clock.phase = phase
	clock.phase_tick = phase_tick
	return clock


func test_tuning_is_complete_and_ordered() -> void:
	assert_true(TUNING.is_valid())


func test_default_morning_prep_is_the_authored_rig_exactly() -> void:
	var minute: float = DayLight.minute_for(_clock(SimClock.Phase.MORNING), 0.0, TUNING)
	assert_almost_eq(minute, 600.0, 0.0001, "an hour before the default 11:00 opening")
	var look: DayLight.Look = DayLight.sample(minute, TUNING)
	var rig: Node3D = RIG.instantiate() as Node3D
	var key: DirectionalLight3D = rig.get_node("KeyLight") as DirectionalLight3D
	var fill: DirectionalLight3D = rig.get_node("FillLight") as DirectionalLight3D
	var environment: Environment = (rig.get_node("Environment") as WorldEnvironment).environment
	var sky: ProceduralSkyMaterial = environment.sky.sky_material as ProceduralSkyMaterial
	assert_true(look.key_color.is_equal_approx(key.light_color))
	assert_almost_eq(look.key_energy, key.light_energy)
	assert_almost_eq(look.key_pitch, key.rotation_degrees.x, 0.001)
	assert_almost_eq(look.fill_energy, fill.light_energy)
	assert_true(look.ambient_color.is_equal_approx(environment.ambient_light_color))
	assert_almost_eq(look.ambient_energy, environment.ambient_light_energy)
	assert_true(look.sky_top.is_equal_approx(sky.sky_top_color))
	assert_true(look.sky_horizon.is_equal_approx(sky.sky_horizon_color))
	assert_true(look.sky_ground.is_equal_approx(sky.ground_bottom_color))
	assert_almost_eq(look.interior_energy, 0.0, 0.0001, "no shop lights needed by day")
	assert_almost_eq(look.glow, 1.0, 0.0001, "signs keep their authored glow")
	rig.free()


func test_each_phase_maps_to_its_time_of_day() -> void:
	var clock: SimClock = _clock(SimClock.Phase.OPEN, 0)
	assert_almost_eq(DayLight.minute_for(clock, 0.0, TUNING), 660.0, 0.0001, "opening")
	clock.phase_tick = clock.open_ticks / 2
	assert_almost_eq(DayLight.minute_for(clock, 0.0, TUNING), 960.0, 0.0001, "halfway through service")
	assert_true(DayLight.minute_for(clock, 0.5, TUNING) > 960.0, "the tick fraction moves the light smoothly")
	clock.phase = SimClock.Phase.LAST_ORDERS
	clock.phase_tick = clock.last_orders_max_ticks / 2
	assert_almost_eq(DayLight.minute_for(clock, 0.0, TUNING), 1290.0, 0.0001, "half an hour into last orders")
	assert_almost_eq(DayLight.minute_for(_clock(SimClock.Phase.CLOSED), 0.0, TUNING), 1410.0, 0.0001, "late, after closing")
	var early: SimClock = _clock(SimClock.Phase.MORNING)
	early.display_open_minute = 360
	assert_almost_eq(DayLight.minute_for(early, 0.0, TUNING), 360.0, 0.0001, "never before 06:00 for an early opening")


func test_the_look_is_a_pure_function_of_time() -> void:
	for minute: float in [0.0, 400.0, 600.0, 900.0, 1100.0, 1300.0, 1439.0]:
		var first: DayLight.Look = DayLight.sample(minute, TUNING)
		var second: DayLight.Look = DayLight.sample(minute, TUNING)
		assert_true(first.key_color.is_equal_approx(second.key_color))
		assert_almost_eq(first.key_energy, second.key_energy, 0.0)
		assert_almost_eq(first.interior_energy, second.interior_energy, 0.0)


func test_night_dims_the_sun_lights_the_shop_and_brightens_signs() -> void:
	var noon: DayLight.Look = DayLight.sample(780.0, TUNING)
	var night: DayLight.Look = DayLight.sample(1320.0, TUNING)
	assert_true(night.key_energy < noon.key_energy * 0.5, "the sun is down")
	assert_true(night.interior_energy > 0.5 and noon.interior_energy == 0.0, "the shop's own lights at night only")
	assert_true(night.glow > noon.glow, "signs glow brighter at night")
	assert_true(night.sky_top.get_luminance() < noon.sky_top.get_luminance(), "a dark sky")
	assert_true(night.ambient_energy > 0.1, "never too dark to read the floor")


func test_a_real_session_lights_the_shop_at_night_and_puts_it_out_by_day() -> void:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	main.call("refresh_presentation")
	var rig: Node3D = main.get_node("LightingRig") as Node3D
	var lights: OmniLight3D = rig.get_node_or_null(^"ShopLights") as OmniLight3D
	assert_true(lights == null or not lights.visible, "no shop lights in the morning")
	var world: SimWorld = main.get("world")
	world.clock.phase = SimClock.Phase.CLOSED
	main.call("refresh_presentation")
	lights = rig.get_node_or_null(^"ShopLights") as OmniLight3D
	assert_not_null(lights)
	assert_true(lights.visible and lights.light_energy > 0.5, "the shop is lit after closing")
	var key: DirectionalLight3D = rig.get_node("KeyLight") as DirectionalLight3D
	assert_true(key.light_energy < 0.1, "the sun has set")
	world.clock.phase = SimClock.Phase.MORNING
	main.call("refresh_presentation")
	assert_false(lights.visible, "lights out again for morning prep")
	assert_almost_eq(key.light_energy, 0.4, 0.0001, "the authored morning sun")
