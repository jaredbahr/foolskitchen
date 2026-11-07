extends TestCase

const GAME: PackedScene = preload("res://src/minigames/haggle_game.tscn")
const TERMS: HaggleTuning = preload("res://data/balance/haggle.tres")
var _game: HaggleGame
var _results: Array[float] = []


func before_each() -> void:
	_results.clear()
	_game = GAME.instantiate() as HaggleGame
	(Engine.get_main_loop() as SceneTree).root.add_child(_game)
	_game.finished.connect(_on_finished)
	assert_true(_game.prepare(TERMS, [0.5, 0.5, 0.5] as Array[float]))
	_game.start()
	_game.set_process(false)


func after_each() -> void:
	_game.free()


func _on_finished(result: float) -> void:
	_results.append(result)


func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _advance_to_score(score: float) -> void:
	var index: int = int(_game.snapshot()["round"])
	var marker: float = 0.5 - TERMS.zone_widths[index] * 0.5 * (1.0 - score)
	_game.call("_process", marker / TERMS.speeds[index])


func test_space_averages_three_scores_without_echo_or_held_key_replay() -> void:
	for index: int in 3:
		_advance_to_score(0.6)
		_game.call("_input", _key(KEY_SPACE))
		_game.call("_input", _key(KEY_SPACE, true, true))
		_game.call("_input", _key(KEY_SPACE))
		assert_eq((_game.snapshot()["scores"] as Array).size(), index + 1)
		_game.call("_input", _key(KEY_SPACE, false))
	assert_eq(_results.size(), 1)
	assert_almost_eq(_results[0], 0.6)
	assert_eq(HaggleRules.discount_percent(_results[0], TERMS.max_discount), 6)
	assert_false(_game.visible)
	assert_false(_game.running)


func test_bar_click_uses_the_same_stop_once_and_skip_finishes_once() -> void:
	_advance_to_score(1.0)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_game.call("_on_bar_input", click)
	(_game.get_node("%Stop") as Button).pressed.emit()
	assert_eq((_game.snapshot()["scores"] as Array).size(), 1)
	assert_almost_eq(float(_game.snapshot()["scores"][0]), 1.0)
	(_game.get_node("%Skip") as Button).pressed.emit()
	(_game.get_node("%Skip") as Button).pressed.emit()
	_game.call("_input", _key(KEY_ESCAPE))
	assert_eq(_results, [-1.0] as Array[float])


func test_tab_stays_in_game_and_enter_on_skip_does_not_stop_a_round() -> void:
	assert_true((_game.get_node("%Stop") as Button).has_focus())
	var viewport: Viewport = _game.get_viewport()
	viewport.push_input(_key(KEY_TAB), true)
	viewport.push_input(_key(KEY_TAB, false), true)
	assert_true((_game.get_node("%Skip") as Button).has_focus())
	viewport.push_input(_key(KEY_ENTER), true)
	viewport.push_input(_key(KEY_ENTER, false), true)
	assert_eq(_results, [-1.0] as Array[float])
	assert_eq(_game.snapshot()["scores"], [] as Array[float])


func _mouse(point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	_game.get_viewport().push_input(event, true)


func test_native_bar_stop_release_and_skip_click_each_have_one_effect() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame
	var bar: Control = _game.get_node("%Bar") as Control
	var stop: Button = _game.get_node("%Stop") as Button
	var skip: Button = _game.get_node("%Skip") as Button
	_advance_to_score(1.0)
	_mouse(bar.get_global_rect().get_center(), true)
	assert_eq((_game.snapshot()["scores"] as Array).size(), 1, "bar scores on its actual GUI press")
	_mouse(stop.get_global_rect().get_center(), false)
	assert_eq((_game.snapshot()["scores"] as Array).size(), 1, "release over Stop cannot replay the bar press")
	await tree.process_frame
	_advance_to_score(0.6)
	_mouse(stop.get_global_rect().get_center(), true)
	assert_true(stop.is_pressed(), "Stop receives the native button press")
	assert_eq((_game.snapshot()["scores"] as Array).size(), 1)
	_mouse(stop.get_global_rect().get_center(), false)
	assert_eq((_game.snapshot()["scores"] as Array).size(), 2, "Stop scores once on GUI release")
	await tree.process_frame
	_mouse(skip.get_global_rect().get_center(), true)
	assert_true(skip.is_pressed(), "Skip receives the native button press")
	_mouse(skip.get_global_rect().get_center(), false)
	assert_eq(_results, [-1.0] as Array[float])
	assert_eq((_game.snapshot()["scores"] as Array).size(), 2, "Skip never scores a round")
	assert_false(_game.visible)


func test_invalid_tuning_and_reprepare_cannot_change_a_running_round() -> void:
	var before: Dictionary = _game.snapshot()
	assert_false(_game.prepare(TERMS, [0.6, 0.6, 0.6] as Array[float]))
	assert_eq(_game.snapshot(), before)
	_game.call("_on_skip_pressed")
	var invalid: HaggleTuning = TERMS.duplicate(true) as HaggleTuning
	invalid.zone_widths = [0.4, NAN, 0.1]
	assert_false(_game.prepare(invalid, [0.5, 0.5, 0.5] as Array[float]))
	assert_eq(TERMS.zone_widths, [0.36, 0.26, 0.18] as Array[float])
