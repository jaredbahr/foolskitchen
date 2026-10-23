extends TestCase
## Small deterministic day cycles plus manual frame-driver tests.

const ClockScript := preload("res://src/core/clock.gd")

var _driver: ClockScript
var _tick_events: Array[int] = []
var _phase_events: Array[Vector2i] = []


func after_each() -> void:
	if EventBus.sim_ticked.is_connected(_on_sim_ticked):
		EventBus.sim_ticked.disconnect(_on_sim_ticked)
	if EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
		EventBus.day_phase_changed.disconnect(_on_day_phase_changed)
	if _driver != null:
		_driver.free()
		_driver = null


func test_full_day_phase_sequence_and_total_ticks() -> void:
	var clock: SimClock = _small_clock()
	var changes: Array[Vector2i] = []
	clock.phase_changed.connect(func(day: int, phase: SimClock.Phase) -> void:
		changes.append(Vector2i(day, phase)))
	assert_true(clock.start_service())
	_advance(clock, 4)
	assert_eq(clock.phase, SimClock.Phase.LAST_ORDERS)
	clock.notify_restaurant_empty()
	assert_eq(clock.phase, SimClock.Phase.CLOSED)
	assert_true(clock.next_day())
	assert_eq(clock.day, 2)
	assert_eq(clock.tick, 4, "total ticks survive the next-day transition")
	assert_eq(clock.phase_tick, 0)
	assert_eq(changes, [Vector2i(1, SimClock.Phase.OPEN), Vector2i(1, SimClock.Phase.LAST_ORDERS),
		Vector2i(1, SimClock.Phase.CLOSED), Vector2i(2, SimClock.Phase.MORNING)])


func test_advance_does_nothing_in_menu_phases() -> void:
	var clock: SimClock = _small_clock()
	var morning: Dictionary = clock.to_dict()
	_advance(clock, 5)
	assert_eq(clock.to_dict(), morning)
	clock.start_service()
	_advance(clock, 4)
	clock.notify_restaurant_empty()
	var closed: Dictionary = clock.to_dict()
	_advance(clock, 5)
	assert_eq(clock.to_dict(), closed)


func test_open_boundary_is_exact_and_resets_phase_tick() -> void:
	var clock: SimClock = _small_clock()
	clock.start_service()
	_advance(clock, 3)
	assert_eq(clock.phase, SimClock.Phase.OPEN)
	assert_eq(clock.phase_tick, 3)
	clock.advance()
	assert_eq(clock.phase, SimClock.Phase.LAST_ORDERS)
	assert_eq(clock.phase_tick, 0)
	assert_eq(clock.tick, 4)


func test_last_orders_safety_net_closes_at_exact_boundary() -> void:
	var clock: SimClock = _small_clock()
	clock.start_service()
	_advance(clock, 4)
	_advance(clock, 2)
	assert_eq(clock.phase, SimClock.Phase.LAST_ORDERS)
	assert_eq(clock.phase_tick, 2)
	clock.advance()
	assert_eq(clock.phase, SimClock.Phase.CLOSED)
	assert_eq(clock.tick, 7)
	assert_eq(clock.phase_tick, 0)


func test_empty_notification_only_closes_last_orders() -> void:
	var clock: SimClock = _small_clock()
	clock.notify_restaurant_empty()
	assert_eq(clock.phase, SimClock.Phase.MORNING)
	clock.start_service()
	clock.notify_restaurant_empty()
	assert_eq(clock.phase, SimClock.Phase.OPEN)
	_advance(clock, 4)
	clock.notify_restaurant_empty()
	var closed: Dictionary = clock.to_dict()
	clock.notify_restaurant_empty()
	assert_eq(clock.to_dict(), closed)


func test_invalid_transitions_leave_state_unchanged() -> void:
	var clock: SimClock = _small_clock()
	assert_false(clock.next_day())
	assert_eq(clock.day, 1)
	clock.start_service()
	assert_false(clock.start_service())
	assert_false(clock.next_day())
	_advance(clock, 4)
	assert_false(clock.start_service())
	assert_false(clock.next_day())
	clock.notify_restaurant_empty()
	assert_false(clock.start_service())
	assert_true(clock.next_day())
	assert_false(clock.next_day())
	assert_eq(clock.day, 2)


func test_display_minutes_at_start_middle_end_and_menu_phases() -> void:
	var clock: SimClock = _small_clock()
	assert_eq(clock.display_minutes(), 11 * 60)
	clock.start_service()
	assert_eq(clock.display_minutes(), 11 * 60)
	_advance(clock, 2)
	assert_eq(clock.display_minutes(), 16 * 60)
	_advance(clock, 2)
	assert_eq(clock.display_minutes(), 21 * 60)
	clock.advance()
	assert_eq(clock.display_minutes(), 21 * 60)
	clock.notify_restaurant_empty()
	assert_eq(clock.display_minutes(), 21 * 60)
	clock.next_day()
	assert_eq(clock.display_minutes(), 11 * 60)


func test_save_round_trip_preserves_config_and_continuation() -> void:
	var clock: SimClock = _small_clock()
	clock.display_open_minute = 9 * 60
	clock.display_close_minute = 19 * 60
	clock.start_service()
	_advance(clock, 5)
	var restored: SimClock = SimClock.from_dict(clock.to_dict())
	assert_eq(restored.to_dict(), clock.to_dict())
	assert_eq(restored.display_minutes(), clock.display_minutes())
	_advance(clock, 2)
	_advance(restored, 2)
	assert_eq(restored.to_dict(), clock.to_dict())
	assert_eq(restored.phase, SimClock.Phase.CLOSED)
	restored.next_day()
	clock.next_day()
	assert_eq(restored.to_dict(), clock.to_dict())


func test_empty_save_uses_clock_defaults() -> void:
	var fresh: SimClock = SimClock.new()
	assert_eq(SimClock.from_dict({}).to_dict(), fresh.to_dict())


func test_set_speed_rejects_three_without_changing_current_speed() -> void:
	_make_driver()
	assert_true(_driver.set_speed(2))
	assert_false(_driver.set_speed(3))
	assert_eq(_driver.speed, 2)
	assert_false(_driver.set_speed(-1))
	assert_eq(_driver.speed, 2)


func test_frame_driver_accumulates_fractional_ticks() -> void:
	_make_driver()
	for frame: int in range(3):
		_driver._process(0.025)
	assert_eq(_driver.sim.tick, 0)
	_driver._process(0.025)
	assert_eq(_driver.sim.tick, 1)
	assert_eq(_tick_events, [1])


func test_frame_driver_speed_scales_tick_count_only() -> void:
	_make_driver()
	for multiplier: int in [1, 2, 4]:
		_driver.sim = SimClock.new()
		_driver.sim.start_service()
		_driver.set_speed(multiplier)
		_driver._process(0.5)
		assert_eq(_driver.sim.tick, 5 * multiplier)
		assert_eq(_driver.sim.phase_tick, 5 * multiplier)


func test_slow_frame_is_capped_without_catch_up_on_next_frame() -> void:
	_make_driver()
	_driver._process(10.0)
	assert_eq(_driver.sim.tick, 40)
	assert_eq(_tick_events.size(), 40)
	_driver._process(0.0)
	assert_eq(_driver.sim.tick, 40, "overdue ticks were discarded")
	_driver._process(0.1)
	assert_eq(_driver.sim.tick, 41)


func test_closed_mid_frame_stops_tick_events() -> void:
	_make_driver()
	_driver.sim.open_ticks = 1
	_driver.sim.last_orders_max_ticks = 1
	_driver._process(1.0)
	assert_eq(_driver.sim.phase, SimClock.Phase.CLOSED)
	assert_eq(_driver.sim.tick, 2)
	assert_eq(_tick_events, [1, 2], "menu phases must not emit phantom sim ticks")


func test_menu_frames_do_not_leave_a_backlog() -> void:
	_make_driver()
	_driver.sim = SimClock.new()
	_driver.set_speed(4)
	_driver._process(10.0)
	assert_eq(_driver.sim.tick, 0)
	assert_eq(_tick_events.size(), 0)
	_driver.sim.start_service()
	_driver._process(0.0)
	assert_eq(_driver.sim.tick, 0)


func test_pause_action_remembers_last_nonzero_speed() -> void:
	_make_driver()
	_driver.set_speed(4)
	_press_action(&"speed_pause")
	assert_eq(_driver.speed, 0)
	_driver._process(1.0)
	assert_eq(_driver.sim.tick, 0)
	_press_action(&"speed_pause")
	assert_eq(_driver.speed, 4)
	_driver._process(0.1)
	assert_eq(_driver.sim.tick, 4)


func test_speed_actions_choose_one_two_and_four() -> void:
	_make_driver()
	_press_action(&"speed_4")
	assert_eq(_driver.speed, 4)
	_press_action(&"speed_2")
	assert_eq(_driver.speed, 2)
	_press_action(&"speed_1")
	assert_eq(_driver.speed, 1)


func test_phase_signals_forward_and_restored_clock_rebinds() -> void:
	_make_driver()
	var previous: SimClock = _driver.sim
	_phase_events.clear()
	_driver.sim = _small_clock()
	previous.open_ticks = 1
	previous.advance()
	assert_eq(_phase_events.size(), 0, "the previous sim is disconnected")
	_driver.sim.start_service()
	_advance(_driver.sim, 4)
	_driver.sim.notify_restaurant_empty()
	_driver.sim.next_day()
	assert_eq(_phase_events, [Vector2i(1, SimClock.Phase.OPEN), Vector2i(1, SimClock.Phase.LAST_ORDERS),
		Vector2i(1, SimClock.Phase.CLOSED), Vector2i(2, SimClock.Phase.MORNING)])
	assert_eq(_driver.day, 2)
	assert_eq(_driver.phase, SimClock.Phase.MORNING)
	assert_eq(_driver.tick, 4)


func test_input_map_binds_space_and_number_keys() -> void:
	var bindings: Dictionary[StringName, int] = {
		&"speed_pause": KEY_SPACE, &"speed_1": KEY_1, &"speed_2": KEY_2, &"speed_4": KEY_3,
	}
	for action: StringName in bindings:
		assert_true(InputMap.has_action(action))
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert_eq(events.size(), 1)
		if events.size() == 1:
			var key: InputEventKey = events[0] as InputEventKey
			assert_not_null(key)
			if key != null:
				assert_eq(key.physical_keycode, bindings[action])


func _small_clock() -> SimClock:
	var clock: SimClock = SimClock.new()
	clock.open_ticks = 4
	clock.last_orders_max_ticks = 3
	return clock


func _advance(clock: SimClock, count: int) -> void:
	for step: int in range(count):
		clock.advance()


func _make_driver() -> void:
	_driver = ClockScript.new()
	_driver.sim.open_ticks = 10000
	EventBus.sim_ticked.connect(_on_sim_ticked)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_driver.sim.start_service()
	_driver.set_speed(1)


func _press_action(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	_driver._unhandled_input(event)


func _on_sim_ticked(value: int) -> void:
	_tick_events.append(value)


func _on_day_phase_changed(day: int, phase: int) -> void:
	_phase_events.append(Vector2i(day, phase))
