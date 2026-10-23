extends TestCase
## Synchronous scene/event tests; rendered layout and tween timing need playtesting.

const HUD_SCENE: PackedScene = preload("res://src/ui/hud.tscn")
var _hud: CanvasLayer
var _old_sim: SimClock
var _old_speed: int
var _old_cash: int
var _old_last_speed: int
var _old_accumulator: float
var _speeds: Array[int] = []


func before_each() -> void:
	_old_sim = Clock.sim
	_old_speed = Clock.speed
	_old_cash = Economy.cash
	_old_last_speed = Clock._last_non_zero_speed
	_old_accumulator = Clock._accumulator
	Clock.sim = SimClock.new()
	Clock.set_speed(0)
	Economy.cash = 1234
	_hud = HUD_SCENE.instantiate() as CanvasLayer
	_hud.call("refresh")


func after_each() -> void:
	_hud.free()
	if EventBus.speed_changed.is_connected(_record_speed):
		EventBus.speed_changed.disconnect(_record_speed)
	Clock.sim = _old_sim
	Clock.set_speed(_old_speed)
	Clock._last_non_zero_speed = _old_last_speed
	Clock._accumulator = _old_accumulator
	Economy.cash = _old_cash


func test_initial_labels_and_shared_theme_before_ready() -> void:
	assert_eq((_control("Day") as Label).text, "Day 1")
	assert_eq((_control("Time") as Label).text, "11:00")
	assert_eq((_control("Phase") as Label).text, "Morning")
	assert_eq((_control("Cash") as Label).text, "$1,234")
	assert_eq((_hud.get_node("Top") as Control).theme, load("res://src/ui/theme/main_theme.tres"))


func test_scene_tree_binding_and_exit_cleanup_do_not_require_ready() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_hud)
	_hud.call("refresh")
	var callback: Callable = Callable(_hud, "_on_speed_changed")
	assert_true(EventBus.speed_changed.is_connected(callback))
	tree.root.remove_child(_hud)
	assert_false(EventBus.speed_changed.is_connected(callback))
	assert_false(EventBus.sim_ticked.is_connected(Callable(_hud, "_on_sim_ticked")))
	assert_false(EventBus.day_phase_changed.is_connected(Callable(_hud, "_on_phase_changed")))
	assert_false(EventBus.cash_changed.is_connected(Callable(_hud, "_on_cash_changed")))
	# Both lifecycle paths may fire for the same removal; cleanup is idempotent.
	_hud.call("_exit_tree")
	_hud.call("refresh")
	assert_true(EventBus.speed_changed.is_connected(callback))


func test_refresh_is_idempotent_and_buttons_do_not_capture_keyboard_focus() -> void:
	_hud.call("refresh")
	_hud.call("refresh")
	EventBus.speed_changed.connect(_record_speed)
	(_control("Speed2") as Button).pressed.emit()
	assert_eq(_speeds, [2] as Array[int])
	for name: String in ["Speed0", "Speed1", "Speed2", "Speed4", "Context"]:
		assert_eq((_control(name) as Button).focus_mode, Control.FOCUS_NONE)


func test_keyboard_actions_sync_speed_after_button_click() -> void:
	(_control("Speed2") as Button).pressed.emit()
	var event: InputEventAction = InputEventAction.new()
	event.action = &"speed_4"
	event.pressed = true
	Clock._unhandled_input(event)
	assert_true((_control("Speed4") as Button).button_pressed)
	assert_false((_control("Speed2") as Button).button_pressed)
	event.action = &"speed_pause"
	Clock._unhandled_input(event)
	assert_true((_control("Speed0") as Button).button_pressed)
	Clock._unhandled_input(event)
	assert_true((_control("Speed4") as Button).button_pressed)


func test_speed_signal_only_follows_accepted_requests() -> void:
	EventBus.speed_changed.connect(_record_speed)
	assert_true(Clock.set_speed(2))
	assert_false(Clock.set_speed(3))
	assert_true(Clock.set_speed(2))
	assert_eq(_speeds, [2, 2] as Array[int])


func test_context_cycles_day_and_tick_events_update_clock() -> void:
	Clock.sim.open_ticks = 2
	Clock.sim.last_orders_max_ticks = 1
	var context: Button = _control("Context") as Button
	assert_true(context.visible)
	assert_eq(context.text, "Open shop")
	context.pressed.emit()
	assert_eq(Clock.speed, 1)
	assert_false(context.visible)
	Clock._process(0.1)
	assert_eq((_control("Time") as Label).text, "16:00")
	Clock._process(0.1)
	assert_eq((_control("Phase") as Label).text, "Last orders")
	assert_false(context.visible)
	Clock._process(0.1)
	assert_eq((_control("Phase") as Label).text, "Closed")
	assert_true(context.visible)
	assert_eq(context.text, "Next day")
	context.pressed.emit()
	assert_eq((_control("Day") as Label).text, "Day 2")
	assert_eq(context.text, "Open shop")


func test_cash_events_create_separate_signed_colored_deltas() -> void:
	EventBus.cash_changed.emit(1246, 12, &"sale")
	EventBus.cash_changed.emit(1216, -30, &"cost")
	_hud.call("refresh")
	assert_eq((_control("Cash") as Label).text, "$1,216")
	var deltas: Control = _hud.get_node("Deltas") as Control
	assert_eq(deltas.get_child_count(), 2)
	var gain: Label = deltas.get_child(0) as Label
	var loss: Label = deltas.get_child(1) as Label
	assert_eq(gain.text, "+12")
	assert_eq(loss.text, "−30")
	assert_eq(gain.get_theme_color("font_color"), Color("286B3B"))
	assert_eq(loss.get_theme_color("font_color"), Color("A42E2E"))


func _control(name: String) -> Control:
	return _hud.get_node("Top/Row/" + name) as Control


func _record_speed(speed: int) -> void:
	_speeds.append(speed)
