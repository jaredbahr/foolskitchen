extends TestCase
## Scene/event tests, including native pause input; Web appearance needs playtesting.

const HUD_SCENE: PackedScene = preload("res://src/ui/hud.tscn")
var _hud: CanvasLayer
var _old_sim: SimClock
var _old_speed: int
var _old_cash: int
var _old_last_speed: int
var _old_accumulator: float
var _speeds: Array[int] = []
var _settings_requests: int = 0


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
	assert_eq((_control("Reputation") as Label).text, "3.0★")
	assert_eq((_control("Reputation") as Label).tooltip_text,
		"3.0 stars from your last 5 reviews")
	assert_eq((_hud.get_node("Top/Row/OwnerProgress/OwnerLevel") as Label).text, "Lv 1")
	assert_almost_eq((_hud.get_node("Top/Row/OwnerProgress/OwnerXPBar") as ProgressBar).value, 0.0)
	_hud.call("set_plate_counts", 9, 12, 2, 1)
	assert_eq((_control("Plates") as Label).text, "Plates 9/12")
	assert_eq((_control("Plates") as Label).tooltip_text, "Clean: 9 | Dirty: 2 | In use: 1")
	_hud.call("set_plate_counts", 9, 12, 2, 1, false)
	assert_eq((_control("Plates") as Label).text, "Plates: buy a sink")
	assert_eq((_control("Plates") as Label).tooltip_text,
		"Plate limits are off in this shop. Buy a sink to enable plates and washing.")
	_hud.call("set_plate_counts", 9, 12, 2, 1)
	assert_eq((_control("Plates") as Label).text, "Plates 9/12", "the same native label returns to active counts")
	assert_eq((_hud.get_node("Top") as Control).theme, load("res://src/ui/theme/main_theme.tres"))


func test_reputation_presentation_survives_refresh_and_tracks_window_count() -> void:
	var cash: Control = _control("Cash")
	var reputation: Label = _control("Reputation") as Label
	assert_eq(reputation.get_index(), cash.get_index() + 1)
	_hud.call("set_reputation", 3.44, 30)
	assert_eq(reputation.text, "3.4★")
	assert_eq(reputation.tooltip_text, "3.4 stars from your last 30 reviews")
	_hud.call("refresh")
	assert_eq(reputation.text, "3.4★")
	_hud.call("set_reputation", 4.0, 7)
	assert_eq(reputation.tooltip_text, "4.0 stars from your last 7 reviews")


func test_owner_level_and_xp_bar_refresh_beside_reputation() -> void:
	var reputation: Label = _control("Reputation") as Label
	var owner: VBoxContainer = _hud.get_node("Top/Row/OwnerProgress") as VBoxContainer
	var label: Label = owner.get_node("OwnerLevel") as Label
	var bar: ProgressBar = owner.get_node("OwnerXPBar") as ProgressBar
	assert_eq(owner.get_index(), reputation.get_index() + 1)
	_hud.call("set_owner_progress", 2, 17, 45)
	assert_eq(label.text, "Lv 2")
	assert_almost_eq(bar.value, 17.0)
	assert_almost_eq(bar.max_value, 45.0)
	assert_eq(label.tooltip_text, "Owner level 2: 17 / 45 XP to next level")
	assert_eq(bar.tooltip_text, label.tooltip_text)
	_hud.call("refresh")
	assert_eq(label.text, "Lv 2")
	assert_almost_eq(bar.value, 17.0)
	_hud.call("set_owner_progress", 3, 100, 50)
	assert_almost_eq(bar.value, 50.0, 0.0001, "the display clamps an invalid overfull fraction")


func test_scaled_window_keeps_every_hud_control_readable_and_build_hints_below_header() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	# A real Window applies content scaling. A plain 1280px SubViewport would
	# miss this regression; embed the Window to avoid changing the test root.
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_embed_subwindows = true
	tree.root.add_child(host)
	var window: Window = Window.new()
	window.borderless = true
	window.size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1600, 900)
	host.add_child(window)
	var view: ShopView = load("res://src/world/shop_view.tscn").instantiate() as ShopView
	_hud.call("bind_shop_view", view)
	_hud.call("set_owner_progress", 2, 17, 45)
	_hud.call("set_plate_counts", 12, 12, 0, 0)
	window.add_child(_hud)
	await _layout_frames()
	assert_true(window.is_embedded(), "the fixture uses an isolated embedded Window")
	assert_eq(window.size, Vector2i(1280, 720))
	_assert_header_layout(window)
	_assert_single_header_row()
	var top: Control = _hud.get_node("Top") as Control
	var usual_height: float = top.size.y
	assert_almost_eq(_hud.call("panel_top"), 112.0)
	_hud.call("set_build_state", true, true, "Keep a clear route to the kitchen and every table.")
	# Match the project virtual base and exercise both requested physical sizes
	# at 125% and 150%. A 150% preference gives 1066.667 logical pixels here.
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		window.size = physical_size
		for percent: int in [125, 150]:
			var scale_factor: float = float(percent) / 100.0
			window.content_scale_factor = scale_factor
			await _layout_frames()
			assert_eq(window.size, physical_size)
			assert_almost_eq(window.content_scale_factor, scale_factor)
			assert_almost_eq(window.get_visible_rect().size.x, 1600.0 / scale_factor, 0.01)
			assert_almost_eq(window.get_visible_rect().size.y, 900.0 / scale_factor, 0.01)
			_assert_header_layout(window)
			_assert_build_hint_layout(window)
			if percent == 150:
				assert_true(top.size.y > usual_height, "150% wraps controls instead of clipping actions")
	# Also cover a native-size virtual base: the same physical Window now has
	# only 853.333 logical pixels. Never divide get_visible_rect() a second time.
	window.size = Vector2i(1280, 720)
	window.content_scale_size = Vector2i(1280, 720)
	await _layout_frames()
	assert_eq(window.size, Vector2i(1280, 720))
	assert_almost_eq(window.get_visible_rect().size.x, 1280.0 / 1.5, 0.01)
	assert_almost_eq(window.get_visible_rect().size.y, 480.0, 0.01)
	_assert_header_layout(window)
	_assert_build_hint_layout(window)
	window.content_scale_size = Vector2i(1600, 900)
	window.content_scale_factor = 1.0
	await _layout_frames()
	_assert_header_layout(window)
	_assert_single_header_row()
	assert_almost_eq(top.size.y, usual_height, 0.01, "returning to 100% restores the usual header height")
	assert_almost_eq((_hud.get_node("BuildHints") as Control).position.y, 104.0)
	assert_almost_eq(_hud.call("panel_top"), 112.0)
	window.remove_child(_hud)
	host.free()
	view.free()


func test_settings_gear_uses_approved_icon_and_stays_available_during_service() -> void:
	var button: Button = _control("Settings") as Button
	assert_eq(button.icon.resource_path, "res://assets/kenney/icons/gear.png")
	assert_eq(button.get_theme_constant("icon_max_width"), 28)
	assert_eq(button.focus_mode, Control.FOCUS_NONE)
	assert_eq(button.tooltip_text, "Settings (Esc)")
	_hud.connect(&"settings_pressed", _record_settings)
	for phase: SimClock.Phase in [SimClock.Phase.MORNING, SimClock.Phase.OPEN,
			SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]:
		Clock.sim.phase = phase
		_hud.call("refresh")
		assert_true(button.visible)
		assert_false(button.disabled, "Settings stays available in every day phase")
		button.pressed.emit()
	assert_eq(_settings_requests, 4)
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var font_color: StringName = &"font_color" if state == &"normal" else StringName("font_%s_color" % state)
		assert_eq(button.get_theme_color(StringName("icon_%s_color" % state)),
			button.theme.get_color(font_color, &"Button"))


func test_paint_button_shares_top_row_and_theme_with_build() -> void:
	var build: Button = _control("Build") as Button
	var paint: Button = _control("Paint") as Button
	assert_eq(paint.get_parent(), build.get_parent())
	assert_eq(paint.get_index(), build.get_index() + 1)
	assert_eq(paint.theme, build.theme)
	assert_eq(paint.focus_mode, Control.FOCUS_NONE)
	assert_true(paint.toggle_mode)


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


func test_open_shop_uses_the_selected_starting_speed() -> void:
	var preferences: SettingsPreferences = SettingsPreferences.new("user://unused-hud-test.cfg")
	preferences.default_open_speed = 2
	_hud.call("bind_preferences", preferences)
	(_control("Context") as Button).pressed.emit()
	assert_eq(Clock.sim.phase, SimClock.Phase.OPEN)
	assert_eq(Clock.speed, 2)
	_hud.call("bind_preferences", null)
	preferences.free()


func test_cash_events_create_separate_signed_colored_deltas() -> void:
	EventBus.cash_changed.emit(1246, 12, &"sale")
	EventBus.cash_changed.emit(1216, -30, &"cost")
	_hud.call("refresh")
	assert_eq((_control("Cash") as Label).text, "$1,216")
	var deltas: Control = _hud.get_node("Deltas") as Control
	assert_eq(deltas.get_child_count(), 2)
	var gain: Label = deltas.get_child(0) as Label
	var loss: Label = deltas.get_child(1) as Label
	assert_eq(gain.text, "+$12")
	assert_eq(loss.text, "−$30")
	var bar_bottom: float = (_hud.get_node("Top") as Control).get_global_rect().end.y
	for delta: Label in [gain, loss]:
		assert_true(delta.position.y >= bar_bottom, "the change appears below the top bar, never over the cash")
	assert_eq(gain.get_theme_color("font_color"), Color("286B3B"))
	assert_eq(loss.get_theme_color("font_color"), Color("A42E2E"))


func test_same_frame_costs_show_as_one_total() -> void:
	var deltas: Control = _hud.get_node("Deltas") as Control
	var before: int = deltas.get_child_count()
	EventBus.cash_changed.emit(290, -10, &"ingredients")
	EventBus.cash_changed.emit(274, -16, &"ingredients")
	EventBus.cash_changed.emit(286, 12, &"sale")
	assert_eq(deltas.get_child_count(), before + 2, "same-sign changes merge; a gain starts a new label")
	assert_eq((deltas.get_child(before) as Label).text, "−$26")
	assert_eq((deltas.get_child(before + 1) as Label).text, "+$12")


func test_every_speed_change_has_exactly_one_pressed_button_using_shared_styles() -> void:
	var shared_theme: Theme = load("res://src/ui/theme/main_theme.tres") as Theme
	for speed: int in [0, 1, 2, 4, 2, 0]:
		Clock.set_speed(speed)
		var pressed: int = 0
		for value: int in [0, 1, 2, 4]:
			var button: Button = _control("Speed%d" % value) as Button
			if button.button_pressed:
				pressed += 1
			assert_eq(button.button_pressed, value == speed)
			assert_false(button.has_theme_color_override("font_color"))
			assert_false(button.has_theme_color_override("font_pressed_color"))
			assert_false(button.has_theme_stylebox_override("normal"))
			assert_false(button.has_theme_stylebox_override("pressed"))
			assert_eq(button.theme, shared_theme, "each button uses the same resource, not inline styles")
			# The runner executes before tree readiness, when Control's inherited
			# theme cache can still hold constructor defaults. Inspect the actual
			# assigned Theme resource; entered/rendered controls refresh that cache.
			var normal: StyleBoxFlat = button.theme.get_stylebox("normal", "Button") as StyleBoxFlat
			var active: StyleBoxFlat = button.theme.get_stylebox("pressed", "Button") as StyleBoxFlat
			assert_true(normal != active)
			assert_eq(normal.border_width_left, 2)
			assert_true(active.bg_color != normal.bg_color)
			assert_true(button.theme.get_color("font_color", "Button").is_equal_approx(Color("3B2A20")))
			assert_true(button.theme.get_color("font_pressed_color", "Button").is_equal_approx(Color("F3E6CC")))
		assert_eq(pressed, 1)


func test_wall_button_tracks_c_key_and_rebinding_without_duplicate_cycles() -> void:
	var view: ShopView = load("res://src/world/shop_view.tscn").instantiate() as ShopView
	_hud.call("bind_shop_view", view)
	_hud.call("bind_shop_view", view)
	var button: Button = _control("Walls") as Button
	assert_eq(button.text, "Walls: Cutaway")
	button.pressed.emit()
	assert_eq(view.wall_mode, ShopView.WallMode.DOWN)
	assert_eq(button.text, "Walls: Down")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	view._unhandled_input(key)
	assert_eq(button.text, "Walls: Up")
	view.free()
	_hud.call("refresh")
	assert_true(button.disabled)


func test_pause_uses_mouse_ignoring_shapes_with_shared_theme_foreground() -> void:
	var pause: Button = _control("Speed0") as Button
	assert_eq(pause.text, "", "pause needs no font glyph or platform fallback")
	assert_eq(pause.tooltip_text, "Pause (Space)")
	assert_true(pause.custom_minimum_size.x >= 44.0 and pause.custom_minimum_size.y >= 44.0)
	var icon: Control = pause.get_node("Pause") as Control
	var bars: HBoxContainer = icon.get_node("Bars") as HBoxContainer
	assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(bars.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(bars.get_child_count(), 2)
	for speed: int in [0, 1, 2, 4, 0]:
		Clock.set_speed(speed)
		var color_name: StringName = &"font_pressed_color" if speed == 0 else &"font_color"
		for bar: ColorRect in [bars.get_node("Left") as ColorRect, bars.get_node("Right") as ColorRect]:
			assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
			assert_eq(bar.custom_minimum_size, Vector2(4.0, 14.0))
			assert_eq(bar.color, pause.theme.get_color(color_name, &"Button"))
		assert_eq(pause.button_pressed, speed == 0)


func test_native_pause_click_and_physical_space_keep_one_speed_selection() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	tree.root.add_child(_hud)
	Clock.set_speed(2)
	await tree.process_frame
	await tree.process_frame
	var pause: Button = _control("Speed0") as Button
	assert_true(_hud.is_node_ready())
	assert_eq(pause.focus_mode, Control.FOCUS_NONE)
	assert_eq(pause.get_theme_stylebox("pressed"), pause.theme.get_stylebox("pressed", &"Button"))
	var center: Vector2 = pause.get_global_rect().get_center()
	for name: String in ["Left", "Right"]:
		var bar: ColorRect = pause.get_node("Pause/Bars/" + name) as ColorRect
		assert_true(bar.is_visible_in_tree())
		assert_true(bar.size.x > 0.0 and bar.size.y > 0.0)
		assert_true(pause.get_global_rect().encloses(bar.get_global_rect()))
	EventBus.speed_changed.connect(_record_speed)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	tree.root.push_input(motion, true)
	_native_mouse(center, true)
	# Let native drawing update the ink without a model/HUD refresh doing it.
	await tree.process_frame
	await tree.process_frame
	assert_true(pause.get_draw_mode() == BaseButton.DRAW_PRESSED or pause.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED)
	for name: String in ["Left", "Right"]:
		var bar: ColorRect = pause.get_node("Pause/Bars/" + name) as ColorRect
		assert_eq(bar.color, pause.theme.get_color(&"font_pressed_color", &"Button"), "held native press uses the pressed foreground before release")
	_hud.call("refresh")
	assert_true(pause.get_draw_mode() == BaseButton.DRAW_PRESSED or pause.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED, "refresh preserves the native held press")
	await tree.process_frame
	_native_mouse(center, false)
	assert_eq(_speeds, [0] as Array[int], "shapes do not intercept or duplicate the native button click")
	assert_true(pause.button_pressed)
	_native_space(true)
	_native_space(false)
	assert_eq(_speeds, [0, 2] as Array[int], "physical Space still reaches the existing clock shortcut")
	assert_true((_control("Speed2") as Button).button_pressed)
	assert_false(pause.button_pressed)
	_native_space(true)
	_native_space(false)
	assert_eq(_speeds, [0, 2, 0] as Array[int])
	assert_true(pause.button_pressed)
	assert_false((_control("Speed2") as Button).button_pressed)


func _native_mouse(position: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	(Engine.get_main_loop() as SceneTree).root.push_input(event, true)


func _native_space(down: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = down
	(Engine.get_main_loop() as SceneTree).root.push_input(event, true)


func _layout_frames() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(4):
		await tree.process_frame


func _assert_header_layout(window: Window) -> void:
	var top: Control = _hud.get_node("Top") as Control
	var row: Control = _hud.get_node("Top/Row") as Control
	var pixels: Rect2 = Rect2(Vector2.ZERO, Vector2(window.size))
	assert_true(pixels.grow(0.5).encloses(_drawn_rect(top, window)), "the whole header stays inside the physical Window")
	var gear: Button = _control("Settings") as Button
	assert_eq(gear.get_combined_minimum_size(), Vector2(46.0, 46.0),
		"the native gear minimum uses the 28px icon instead of its 100px source texture")
	var occupied: Array[Rect2] = []
	for name: String in ["Day", "Time", "Phase", "Speed0", "Speed1", "Speed2", "Speed4",
			"Walls", "Build", "Paint", "Cash", "Reputation", "OwnerProgress", "Plates", "Context", "Menu", "Staff", "Settings"]:
		var control: Control = _control(name)
		assert_true(control.is_visible_in_tree(), name + " remains visible at every scale")
		_assert_readable_control(control, window)
		assert_true(top.get_global_rect().grow(0.5).encloses(control.get_global_rect()), name + " stays inside its header")
		assert_true(row.get_global_rect().grow(0.5).encloses(control.get_global_rect()), name + " stays inside its row")
		var rect: Rect2 = _drawn_rect(control, window)
		for previous: Rect2 in occupied:
			assert_false(rect.intersects(previous), name + " does not cover another HUD control")
		occupied.append(rect)
	for path: String in ["OwnerProgress/OwnerLevel", "OwnerProgress/OwnerXPBar",
			"Speed0/Pause/Bars/Left", "Speed0/Pause/Bars/Right"]:
		_assert_readable_control(row.get_node(path) as Control, window)


func _assert_readable_control(control: Control, window: Window) -> void:
	var minimum: Vector2 = control.get_combined_minimum_size()
	assert_true(control.size.x > 0.0 and control.size.y > 0.0, str(control.name) + " has a drawn area")
	assert_true(control.size.x >= minimum.x - 0.5 and control.size.y >= minimum.y - 0.5,
		str(control.name) + " retains enough room for its full native content")
	assert_true(window.get_visible_rect().grow(0.5).encloses(control.get_global_rect()),
		str(control.name) + " stays within logical UI bounds")
	var pixels: Rect2 = Rect2(Vector2.ZERO, Vector2(window.size))
	assert_true(pixels.grow(0.5).encloses(_drawn_rect(control, window)),
		str(control.name) + " stays within physical pixel bounds")


func _assert_single_header_row() -> void:
	var row: HFlowContainer = _hud.get_node("Top/Row") as HFlowContainer
	assert_eq(row.get_line_count(), 1, "100% keeps the native header on one flow line")
	var first: Rect2 = _control("Day").get_global_rect()
	var shared_top: float = first.position.y
	var shared_bottom: float = first.end.y
	var previous_end: float = first.position.x
	# Labels shrink to their text height and center within the native flow line.
	# Check a shared row band and order rather than requiring equal top edges.
	for name: String in ["Day", "Time", "Phase", "Speed0", "Speed1", "Speed2", "Speed4", "Walls",
			"Build", "Paint", "Cash", "Reputation", "OwnerProgress", "Plates", "Context", "Menu", "Staff", "Settings"]:
		var rect: Rect2 = _control(name).get_global_rect()
		assert_true(rect.position.x >= previous_end - 0.01, "100% keeps " + name + " in left-to-right row order")
		previous_end = rect.end.x
		shared_top = maxf(shared_top, rect.position.y)
		shared_bottom = minf(shared_bottom, rect.end.y)
	assert_true(shared_bottom > shared_top, "every 100% header control shares a positive vertical row band")


func _assert_build_hint_layout(window: Window) -> void:
	var top: Control = _hud.get_node("Top") as Control
	var hints: Control = _hud.get_node("BuildHints") as Control
	assert_true(hints.is_visible_in_tree())
	_assert_readable_control(hints, window)
	assert_true(hints.global_position.y >= top.get_global_rect().end.y + 6.0,
		"build instructions move below the wrapped header")
	assert_false(_drawn_rect(top, window).intersects(_drawn_rect(hints, window)))
	assert_true(float(_hud.call("panel_top")) >= top.get_global_rect().end.y + 12.0,
		"morning panels receive clearance below the final header height")


func _drawn_rect(control: Control, window: Window) -> Rect2:
	return window.get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _control(name: String) -> Control:
	return _hud.get_node("Top/Row/" + name) as Control


func _record_speed(speed: int) -> void:
	_speeds.append(speed)


func _record_settings() -> void:
	_settings_requests += 1
