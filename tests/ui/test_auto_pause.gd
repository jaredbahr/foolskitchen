extends TestCase

const TOAST: PackedScene = preload("res://src/ui/auto_pause.tscn")

var _toast: AutoPause
var _preferences: SettingsPreferences
var _path: String


func before_each() -> void:
	_path = "user://test-auto-pause-%d-%d.cfg" % [OS.get_process_id(), get_instance_id()]
	_preferences = SettingsPreferences.new(_path)
	_toast = TOAST.instantiate() as AutoPause


func after_each() -> void:
	_toast.free()
	_preferences.free()
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func test_each_trigger_uses_its_own_preference() -> void:
	for key: StringName in SettingsPreferences.AUTO_PAUSE_DEFAULTS:
		var trigger: AutoPause = AutoPause.new()
		var default_enabled: bool = key != SettingsPreferences.PAUSE_ON_ANGRY_GUEST
		assert_eq(trigger._take_pause(_preferences, key, SimClock.Phase.OPEN, 4, 0), default_enabled, String(key))
		assert_true(_preferences.set_auto_pause_enabled(key, false))
		assert_false(trigger._take_pause(_preferences, key, SimClock.Phase.OPEN, 4, 30_000), String(key))
		assert_true(_preferences.set_auto_pause_enabled(key, true))
		assert_true(trigger._take_pause(_preferences, key, SimClock.Phase.OPEN, 4, 30_000), String(key))
		trigger.free()


func test_cooldown_is_shared_and_only_a_successful_pause_starts_it() -> void:
	var dish: StringName = SettingsPreferences.PAUSE_ON_SOLD_OUT
	var inspector: StringName = SettingsPreferences.PAUSE_ON_INSPECTOR
	assert_false(_toast._take_pause(_preferences, dish, SimClock.Phase.MORNING, 4, 100))
	assert_false(_toast._take_pause(_preferences, dish, SimClock.Phase.OPEN, 0, 100))
	assert_true(_toast._take_pause(_preferences, dish, SimClock.Phase.OPEN, 4, 100))
	assert_false(_toast._take_pause(_preferences, inspector, SimClock.Phase.OPEN, 4, 30_099))
	assert_false(_toast._take_pause(_preferences, inspector, SimClock.Phase.CLOSED, 4, 30_100))
	assert_true(_toast._take_pause(_preferences, inspector, SimClock.Phase.LAST_ORDERS, 4, 30_100))


func test_headless_hud_ignores_all_public_alerts() -> void:
	if DisplayServer.get_name() != "headless":
		return
	var speed: int = Clock.speed
	var clock: SimClock = Clock.sim
	Clock.sim = SimClock.new()
	Clock.sim.start_service()
	Clock.set_speed(4)
	(Engine.get_main_loop() as SceneTree).root.add_child(_toast)
	_toast.activate()
	assert_false(EventBus.dish_sold_out.is_connected(_toast._on_dish_sold_out))
	assert_false(EventBus.health_inspector_arrived.is_connected(_toast._on_health_inspector_arrived))
	assert_false(EventBus.guest_left_angry.is_connected(_toast._on_guest_left_angry))
	EventBus.dish_sold_out.emit("Burger")
	EventBus.health_inspector_arrived.emit()
	EventBus.guest_left_angry.emit()
	assert_eq(Clock.speed, 4)
	assert_false(_toast.visible)
	Clock.sim = clock
	Clock.set_speed(speed)


func test_graphical_test_runner_and_balance_probe_still_cannot_pause() -> void:
	assert_true(AutoPause.supports_runtime("Windows", ["--path", "."]))
	assert_false(AutoPause.supports_runtime("Windows", ["--script=res://tools/run_tests.gd"]))
	assert_false(AutoPause.supports_runtime("X11", ["-s", "tools/balance_probe.gd"]))
