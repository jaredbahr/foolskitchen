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
var _staff_requests: int = 0


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
	assert_eq((_control("Reputation") as Label).text, "3.0")
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
	var loan: Label = _control("Loan") as Label
	var reputation: Label = _control("Reputation") as Label
	assert_eq(loan.get_index(), cash.get_index() + 1)
	assert_eq(reputation.get_index(), loan.get_index() + 1)
	assert_false(loan.visible, "a debt-free shop retains the compact financial group")
	_hud.call("set_reputation", 3.44, 30)
	assert_eq(reputation.text, "3.4")
	assert_eq(reputation.tooltip_text, "3.4 stars from your last 30 reviews")
	_hud.call("refresh")
	assert_eq(reputation.text, "3.4")
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
	_assert_one_row_when_native_content_fits()
	var top: Control = _hud.get_node("Top") as Control
	var usual_height: float = top.size.y
	assert_almost_eq(_hud.call("panel_top"), maxf(112.0, top.get_global_rect().end.y + 12.0))
	_hud.call("set_build_state", true, true, "Keep a clear route to the kitchen and every table.")
	# At this intermediate width actions wrap, but the middle remains free.
	window.content_scale_factor = 1600.0 / 1400.0
	await _layout_frames()
	assert_almost_eq(window.get_visible_rect().size.x, 1400.0, 0.01)
	_assert_header_layout(window)
	_assert_build_hint_layout(window)
	var finances: Rect2 = _control("Cash").get_global_rect().merge(_control("Plates").get_global_rect())
	var time_group: Rect2 = _control("Day").get_global_rect().merge(_control("Speed4").get_global_rect())
	var row: Control = _hud.get_node("Top/Row") as Control
	assert_almost_eq(finances.get_center().x, row.get_global_rect().get_center().x, 0.5,
		"finances stay centered when actions wrap and the center has room")
	assert_true(finances.position.x >= time_group.end.x + 23.5)
	assert_true(finances.position.y < time_group.end.y, "time and finances still share the first row")
	assert_true(_control("Walls").global_position.y >= time_group.end.y + 11.5,
		"the intact action group has wrapped below time and finances")
	window.content_scale_factor = 1.0
	# Long status values must keep the same native bounds and group clearance
	# through every requested physical-size and preference combination.
	EventBus.cash_changed.emit(123456789, 0, &"layout")
	_hud.call("set_restaurant_name", "WWWWWWWWWWWWWWWWWWWWWWWW")
	_hud.call("set_owner_progress", 123, 99999, 100000)
	_hud.call("set_plate_counts", 999, 1000, 1, 0)
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
			_assert_one_row_when_native_content_fits()
			_assert_build_hint_layout(window)
			if percent == 150:
				assert_true(top.size.y >= usual_height, "larger UI preserves native group height instead of squeezing controls")
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
	EventBus.cash_changed.emit(123456789, 0, &"layout")
	_hud.call("set_restaurant_name", "WWWWWWWWWWWWWWWWWWWWWWWW")
	_hud.call("set_owner_progress", 123, 99999, 100000)
	_hud.call("set_plate_counts", 999, 1000, 1, 0)
	await _layout_frames()
	_assert_header_layout(window)
	_assert_build_hint_layout(window)
	var settled_height: float = top.size.y
	await tree.process_frame
	assert_almost_eq(top.size.y, settled_height, 0.01, "native minimum changes settle without height oscillation")
	(_control("Context") as Button).hide()
	await _layout_frames()
	_assert_header_layout(window, false)
	(_control("Context") as Button).show()
	EventBus.cash_changed.emit(1234, 0, &"layout")
	_hud.call("set_owner_progress", 2, 17, 45)
	_hud.call("set_plate_counts", 12, 12, 0, 0)
	window.content_scale_size = Vector2i(1600, 900)
	window.content_scale_factor = 1.0
	await _layout_frames()
	_assert_header_layout(window)
	_assert_one_row_when_native_content_fits()
	assert_almost_eq(top.size.y, usual_height, 0.01, "returning to 100% restores the usual header height")
	assert_almost_eq((_hud.get_node("BuildHints") as Control).position.y,
		maxf(104.0, top.get_global_rect().end.y + 6.0))
	assert_almost_eq(_hud.call("panel_top"), maxf(112.0, top.get_global_rect().end.y + 12.0))
	window.remove_child(_hud)
	host.free()
	view.free()


func test_opening_menu_notice_stays_one_line_below_the_header_at_native_and_small_widths() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	tree.root.add_child(viewport)
	viewport.add_child(_hud)
	var note: String = "Fries left today's menu: staff can't reach the fryer"
	_hud.call("set_menu_notice", note)
	await _layout_frames()
	var panel: Control = _hud.get_node("MenuNotice") as Control
	var label: Label = _hud.get_node("MenuNotice/Text") as Label
	var header: Control = _hud.get_node("Top") as Control
	assert_true(panel.visible)
	assert_eq(label.text, note)
	assert_true(panel.size.y < 100.0, "an opening note leaves the restaurant visible rather than filling the viewport")
	assert_true(panel.get_global_rect().position.y >= header.get_global_rect().end.y + 5.5)
	# Long lists and a smaller logical viewport still use one line, with the
	# complete explanation available on hover instead of covering the shop.
	viewport.size = Vector2i(854, 480)
	note = note.repeat(6)
	_hud.call("set_menu_notice", note)
	await _layout_frames()
	assert_eq(label.tooltip_text, note)
	assert_true(label.mouse_filter != Control.MOUSE_FILTER_IGNORE, "the full note can be read on hover")
	assert_eq(label.get_line_count(), 1)
	assert_true(panel.size.y < 100.0, "long lists never turn the note into a tall panel")
	assert_true(panel.get_global_rect().position.y >= header.get_global_rect().end.y + 5.5)
	assert_true(viewport.get_visible_rect().encloses(panel.get_global_rect()), "the notice stays inside the smaller viewport")
	_hud.call("set_menu_notice", "")
	assert_false(panel.visible)
	viewport.remove_child(_hud)
	viewport.free()


func test_staff_entry_requests_work_in_every_phase_without_loosening_menu_or_changing_data() -> void:
	_hud.connect(&"staff_pressed", _record_staff)
	var staff: Button = _control("Staff") as Button
	var identity: int = staff.get_instance_id()
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var debt: Dictionary = Economy.loan.to_dict()
	for phase: SimClock.Phase in [SimClock.Phase.MORNING, SimClock.Phase.OPEN,
			SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]:
		Clock.sim.phase = phase
		var clock: Dictionary = Clock.sim.to_dict()
		_hud.call("refresh")
		assert_eq(_control("Staff").get_instance_id(), identity)
		assert_false(staff.disabled, "staff job choices remain reachable during service")
		assert_eq(staff.icon.resource_path, IconCatalogue.path_for(&"chef"))
		assert_eq((_control("Menu") as Button).disabled, phase != SimClock.Phase.MORNING)
		if phase == SimClock.Phase.MORNING:
			assert_eq(staff.tooltip_text, "Hire staff and plan today's wages")
		else:
			assert_true(staff.tooltip_text.contains("Set staff job priorities"))
			assert_true(staff.tooltip_text.contains("morning"))
		var count: int = _staff_requests
		staff.pressed.emit()
		assert_eq(_staff_requests, count + 1)
		assert_eq(Clock.sim.to_dict(), clock)
		assert_eq(Economy.ledger.to_dict(), books)
		assert_eq(Economy.stock.to_dict(), stock)
		assert_eq(Economy.loan.to_dict(), debt)


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
			assert_true(button.has_theme_stylebox_override("normal"), "shared compact padding retains the native styles")
			assert_true(button.has_theme_stylebox_override("pressed"))
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


func test_pause_uses_approved_native_icon_with_shared_theme_foreground() -> void:
	var pause: Button = _control("Speed0") as Button
	assert_eq(pause.text, "", "the native icon replaces the font-independent pause shapes")
	assert_eq(pause.icon.resource_path, IconCatalogue.ROOT + "pause.png")
	assert_eq(pause.tooltip_text, "Pause (Space)")
	assert_true(pause.custom_minimum_size.x >= 44.0 and pause.custom_minimum_size.y >= 44.0)
	assert_false((pause.get_node("Pause") as Control).visible, "legacy child paths remain harmless and hidden")
	for speed: int in [0, 1, 2, 4, 0]:
		Clock.set_speed(speed)
		assert_eq(pause.get_theme_color("icon_pressed_color"),
			pause.theme.get_color("font_pressed_color", &"Button"))
		assert_eq(pause.get_theme_color("icon_normal_color"), pause.theme.get_color("font_color", &"Button"))
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
	assert_eq((pause.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color,
		(pause.theme.get_stylebox("pressed", &"Button") as StyleBoxFlat).bg_color)
	var center: Vector2 = pause.get_global_rect().get_center()
	assert_not_null(pause.icon)
	assert_false(pause.expand_icon, "fixed-size native icons reserve their own minimum")
	assert_eq(pause.get_theme_constant("icon_max_width"), 28)
	EventBus.speed_changed.connect(_record_speed)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	tree.root.push_input(motion, true)
	_native_mouse(center, true)
	# Let native drawing update the ink without a model/HUD refresh doing it.
	await tree.process_frame
	await tree.process_frame
	assert_true(pause.get_draw_mode() == BaseButton.DRAW_PRESSED or pause.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED)
	assert_eq(pause.get_theme_color("icon_pressed_color"), pause.theme.get_color(&"font_pressed_color", &"Button"),
		"held native press uses the warm pressed foreground")
	_hud.call("refresh")
	assert_true(pause.get_draw_mode() == BaseButton.DRAW_PRESSED or pause.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED, "refresh preserves the native held press")
	await tree.process_frame
	_native_mouse(center, false)
	assert_eq(_speeds, [0] as Array[int], "the native icon does not intercept or duplicate the button click")
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


func test_every_header_button_has_readable_content_and_tooltip() -> void:
	for name: String in ["Speed0", "Speed1", "Speed2", "Speed4", "Walls", "Build", "Paint",
			"Context", "Menu", "Stock", "Staff", "Settings"]:
		var button: Button = _control(name) as Button
		assert_true(button.icon != null or not button.text.is_empty(), name + " has readable content")
		assert_false(button.tooltip_text.is_empty(), name + " explains its action")
		if button.icon != null:
			assert_true(button.icon.resource_path.begins_with(IconCatalogue.ROOT) \
				or button.icon.resource_path in [IconCatalogue.path_for(&"chef"), IconCatalogue.path_for(&"paint")])
			assert_eq(button.get_theme_constant("icon_max_width"), 28)
	for name: String in ["Speed1", "Speed2", "Speed4", "Build", "Context", "Menu", "Staff"]:
		assert_false((_control(name) as Button).text.is_empty(), name + " keeps its main label")
	assert_eq((_control("Paint") as Button).icon.resource_path, IconCatalogue.path_for(&"paint"))
	assert_eq((_control("Paint") as Button).text, "")
	assert_eq((_control("Paint") as Button).tooltip_text, "Paint walls, floor and furniture (P)")
	assert_eq((_control("Staff") as Button).icon.resource_path, IconCatalogue.path_for(&"chef"))
	assert_eq((_control("Reputation").get_node("ThemeIcon") as TextureRect).texture.resource_path,
		IconCatalogue.ROOT + "star.png")
	for name: String in ["Day", "Time", "Phase", "Cash", "Reputation", "Plates"]:
		assert_false((_control(name) as Label).text.is_empty())
		assert_false(_control(name).tooltip_text.is_empty(), name + " explains the displayed value")


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


func test_loan_chip_is_read_only_uses_existing_theme_and_clears_when_paid() -> void:
	var books: Dictionary = Economy.ledger.to_dict()
	var debt: Dictionary = Economy.loan.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var loan: Label = _control("Loan") as Label
	assert_false(loan.visible)
	_hud.call("set_loan_state", 150, 0.5, 0.05)
	assert_true(loan.visible)
	assert_eq(loan.text, "Loan $150")
	assert_true(loan.tooltip_text.contains("50% of positive daily profit"))
	assert_true(loan.tooltip_text.contains("5% a day"))
	var chip: StyleBoxFlat = loan.get_theme_stylebox("normal") as StyleBoxFlat
	var accent: StyleBoxFlat = (_hud.get_node("Top") as Control).theme.get_stylebox("pressed", "Button") as StyleBoxFlat
	assert_eq(chip.border_color, accent.bg_color)
	assert_eq(loan.get_theme_color("font_color"), _control("Cash").get_theme_color("font_color"))
	var identity: int = loan.get_instance_id()
	_hud.call("refresh")
	_hud.call("set_loan_state", 75, 0.25, 0.04)
	assert_eq(_control("Loan").get_instance_id(), identity)
	assert_eq(loan.text, "Loan $75")
	assert_true(loan.tooltip_text.contains("25% of positive daily profit"))
	_hud.call("set_loan_state", 75, 0.5, 0.045)
	assert_true(loan.tooltip_text.contains("The bank takes up to 50%"), "repayment is also limited by available cash")
	assert_true(loan.tooltip_text.contains("50% of positive daily profit"))
	assert_true(loan.tooltip_text.contains("Interest is 4.5% a day."))
	_hud.call("set_loan_state", 75, 0.5, 0.05)
	assert_true(loan.tooltip_text.contains("Interest is 5% a day."))
	assert_false(loan.tooltip_text.contains("5.0%"), "whole rates keep their compact form")
	_hud.call("set_loan_state", 0, 0.5, 0.05)
	assert_false(loan.visible)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.loan.to_dict(), debt)
	assert_eq(Clock.sim.to_dict(), clock)


func test_native_loan_chip_stays_in_financial_group_and_releases_space_at_supported_scales() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_embed_subwindows = true
	tree.root.add_child(host)
	var window: Window = Window.new()
	window.borderless = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1600, 900)
	host.add_child(window)
	var view: ShopView = load("res://src/world/shop_view.tscn").instantiate() as ShopView
	_hud.call("bind_shop_view", view)
	_hud.call("set_plate_counts", 999, 999, 0, 0)
	_hud.call("set_owner_progress", 99, 1234, 9999)
	EventBus.cash_changed.emit(999999999, 0, Ledger.OTHER)
	window.add_child(_hud)
	var loan: Label = _control("Loan") as Label
	var header_theme: Theme = (_hud.get_node("Top") as Control).theme
	var accent: StyleBoxFlat = header_theme.get_stylebox("pressed", "Button") as StyleBoxFlat
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		window.size = physical_size
		for scale_factor: float in [1.0, 1.25, 1.5]:
			window.content_scale_factor = scale_factor
			_hud.call("set_loan_state", 999999999, 0.5, 0.05)
			await _layout_frames()
			_assert_header_layout(window)
			_assert_readable_control(loan, window)
			assert_eq((loan.get_theme_stylebox("normal") as StyleBoxFlat).border_color, accent.bg_color,
				"a HUD bound before tree entry retains the assigned warm theme")
			var row: Control = _hud.get_node("Top/Row") as Control
			assert_true(row.get_global_rect().grow(0.5).encloses(loan.get_global_rect()))
			assert_true(loan.global_position.x >= _control("Cash").get_global_rect().end.x + 5.5)
			assert_true(_control("Reputation").global_position.x >= loan.get_global_rect().end.x + 5.5)
			for child: Node in row.get_children():
				var control: Control = child as Control
				if control != null and control != loan and control.visible:
					assert_false(loan.get_global_rect().intersects(control.get_global_rect()), "loan chip does not cover " + String(control.name))
			assert_true(float(_hud.call("panel_top")) >= (_hud.get_node("Top") as Control).get_global_rect().end.y + 12.0)
			_hud.call("set_loan_state", 0, 0.5, 0.05)
			await _layout_frames()
			assert_false(loan.visible)
			assert_almost_eq(_control("Reputation").global_position.x - _control("Cash").get_global_rect().end.x,
				6.0, 0.5, "a repaid loan releases all chip width and its extra gap")
	window.remove_child(_hud)
	host.free()
	view.free()


func _layout_frames() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(4):
		await tree.process_frame


func _assert_header_layout(window: Window, context_visible: bool = true) -> void:
	var top: Control = _hud.get_node("Top") as Control
	var row: Control = _hud.get_node("Top/Row") as Control
	_assert_restaurant_title(window)
	var pixels: Rect2 = Rect2(Vector2.ZERO, Vector2(window.size))
	assert_true(pixels.grow(0.5).encloses(_drawn_rect(top, window)), "the whole header stays inside the physical Window")
	var gear: Button = _control("Settings") as Button
	assert_eq(gear.get_combined_minimum_size(), Vector2(46.0, 46.0),
		"the native gear minimum uses the 28px icon instead of its 100px source texture")
	var occupied: Array[Rect2] = []
	for name: String in ["Day", "Time", "Phase", "Speed0", "Speed1", "Speed2", "Speed4",
			"Walls", "Build", "Paint", "Cash", "Reputation", "OwnerProgress", "Plates", "Context", "Menu", "Stock", "Staff", "Settings"]:
		var control: Control = _control(name)
		if name == "Context" and not context_visible:
			assert_false(control.is_visible_in_tree(), "the hidden service action releases its layout space")
			continue
		assert_true(control.is_visible_in_tree(), name + " remains visible at every scale")
		_assert_readable_control(control, window)
		assert_true(top.get_global_rect().grow(0.5).encloses(control.get_global_rect()), name + " stays inside its header")
		assert_true(row.get_global_rect().grow(0.5).encloses(control.get_global_rect()), name + " stays inside its row")
		var rect: Rect2 = _drawn_rect(control, window)
		for previous: Rect2 in occupied:
			assert_false(rect.intersects(previous), name + " does not cover another HUD control")
		occupied.append(rect)
	for path: String in ["OwnerProgress/OwnerLevel", "OwnerProgress/OwnerXPBar",
			"Reputation/ThemeIcon"]:
		_assert_readable_control(row.get_node(path) as Control, window)
	_assert_three_groups()


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


func _assert_one_row_when_native_content_fits() -> void:
	var row: Container = _hud.get_node("Top/Row") as Container
	assert_true(row.get_combined_minimum_size().x <= row.size.x + 0.5, "the widest intact group fits")
	# Measure actual native control minima independently of the container's
	# packing result. Icons may legitimately require another row even at 100%.
	var required_width: float = 24.0 * 2.0
	var visible_count: int = 0
	for name: String in ["Day", "Time", "Phase", "Speed0", "Speed1", "Speed2", "Speed4", "Cash",
			"Reputation", "OwnerProgress", "Plates", "Walls", "Build", "Paint", "Context", "Menu", "Stock", "Staff", "Settings"]:
		var control: Control = _control(name)
		if control.visible:
			required_width += control.get_combined_minimum_size().x
			visible_count += 1
	required_width += 6.0 * float(visible_count - 3)
	if required_width > row.size.x:
		_assert_three_groups()
		return
	var first: Rect2 = _control("Day").get_global_rect()
	var shared_top: float = first.position.y
	var shared_bottom: float = first.end.y
	var previous_end: float = first.position.x
	# Labels shrink to their text height and center within the native flow line.
	# Check a shared row band and order rather than requiring equal top edges.
	for name: String in ["Day", "Time", "Phase", "Speed0", "Speed1", "Speed2", "Speed4", "Cash",
			"Reputation", "OwnerProgress", "Plates", "Walls", "Build", "Paint", "Context", "Menu", "Stock", "Staff", "Settings"]:
		var rect: Rect2 = _control(name).get_global_rect()
		assert_true(rect.position.x >= previous_end - 0.01, "a fitting row keeps " + name + " in left-to-right group order")
		previous_end = rect.end.x
		shared_top = maxf(shared_top, rect.position.y)
		shared_bottom = minf(shared_bottom, rect.end.y)
	assert_true(shared_bottom > shared_top, "every fitting header control shares a positive vertical row band")


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


func _assert_three_groups() -> void:
	var groups: Array[Array] = [
		["Day", "Time", "Phase", "Speed0", "Speed1", "Speed2", "Speed4"],
		["Cash", "Loan", "Reputation", "OwnerProgress", "Plates", "SoldOut"],
		["Walls", "Build", "Paint", "Context", "Menu", "Stock", "Staff", "Settings"],
	]
	var bounds: Array[Rect2] = []
	for names: Array in groups:
		var union: Rect2 = Rect2()
		var count: int = 0
		var previous_end: float = 0.0
		var shared_top: float = -INF
		var shared_bottom: float = INF
		for name: String in names:
			var control: Control = _control(name)
			if not control.visible:
				continue
			var rect: Rect2 = control.get_global_rect()
			if count > 0:
				assert_true(rect.position.x >= previous_end + 5.5, name + " has space inside its group")
			union = rect if count == 0 else union.merge(rect)
			previous_end = rect.end.x
			shared_top = maxf(shared_top, rect.position.y)
			shared_bottom = minf(shared_bottom, rect.end.y)
			count += 1
		assert_true(shared_bottom > shared_top, "an intact group shares one vertical band")
		bounds.append(union)
	for index: int in range(1, bounds.size()):
		var before: Rect2 = bounds[index - 1]
		var after: Rect2 = bounds[index]
		var same_row: bool = minf(before.end.y, after.end.y) > maxf(before.position.y, after.position.y)
		if same_row:
			assert_true(after.position.x >= before.end.x + 23.5, "adjacent groups have a clear 24px gap")
		else:
			assert_true(after.position.y >= before.end.y + 11.5, "wrapped groups have a clear 12px row gap")
	var row: Control = _hud.get_node("Top/Row") as Control
	assert_almost_eq(bounds[0].position.x, row.global_position.x, 0.5, "time stays at the left")
	assert_almost_eq(bounds[2].end.x, row.get_global_rect().end.x, 0.5, "actions stay at the right")


func _drawn_rect(control: Control, window: Window) -> Rect2:
	return window.get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _control(name: String) -> Control:
	return _hud.get_node("Top/Row/" + name) as Control


func _record_speed(speed: int) -> void:
	_speeds.append(speed)


func _record_settings() -> void:
	_settings_requests += 1


func _record_staff() -> void:
	_staff_requests += 1


func test_restaurant_name_can_be_set_before_ready_and_survives_refresh() -> void:
	_hud.call("set_restaurant_name", "  Copper Cafe  ")
	var label: Label = _hud.get_node("Top/Row/RestaurantName") as Label
	assert_eq(label.text, "Copper Cafe")
	_hud.call("refresh")
	assert_eq(label.text, "Copper Cafe")
	assert_eq(label.tooltip_text, "Copper Cafe")
	_hud.call("set_restaurant_name", "   ")
	assert_eq(label.text, MenuSettings.DEFAULT_NAME)


## The name title is the first line inside the cream header: inside the panel and
## row, above every control, and either fully drawn or cut with an ellipsis.
func _assert_restaurant_title(window: Window) -> void:
	var title: Label = _control("RestaurantName") as Label
	var top: Control = _hud.get_node("Top") as Control
	var row: Control = _hud.get_node("Top/Row") as Control
	assert_true(title.is_visible_in_tree())
	_assert_readable_control(title, window)
	var rect: Rect2 = title.get_global_rect()
	assert_true(top.get_global_rect().grow(0.5).encloses(rect), "the restaurant title sits inside the header panel")
	assert_true(row.get_global_rect().grow(0.5).encloses(rect), "the restaurant title never widens the header row")
	for child: Node in row.get_children():
		var control: Control = child as Control
		if control != null and control != title and control.visible:
			assert_true(control.get_global_rect().position.y >= rect.end.y - 0.01, "the title stays above " + String(control.name))
	var font: Font = title.get_theme_font("font")
	var width: float = font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
	if width > title.size.x:
		assert_eq(title.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "a long name is cut with an ellipsis")


func test_restaurant_title_contrasts_with_its_header_panel() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_hud)
	await tree.process_frame
	var title: Label = _control("RestaurantName") as Label
	var top: PanelContainer = _hud.get_node("Top") as PanelContainer
	assert_true(title.get_parent().get_parent() == top, "the title is drawn on the header panel")
	var panel: StyleBoxFlat = top.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(panel)
	var ratio: float = _contrast(title.get_theme_color("font_color"), panel.bg_color)
	assert_true(ratio >= 4.5, "title text contrast %.2f is at least 4.5" % ratio)
	assert_eq(title.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "a long name never overflows the header")
	assert_eq(top.offset_top, 12.0, "the header keeps its usual top offset")
	tree.root.remove_child(_hud)


func test_restaurant_title_fits_header_at_1280_by_720_and_150_percent() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
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
	window.content_scale_factor = 1.5
	host.add_child(window)
	window.add_child(_hud)
	var title: Label = _control("RestaurantName") as Label
	var top: Control = _hud.get_node("Top") as Control
	for value: String in [MenuSettings.DEFAULT_NAME, "Mama's Diner", "W".repeat(24)]:
		_hud.call("set_restaurant_name", value)
		await _layout_frames()
		assert_eq(title.text, value)
		_assert_header_layout(window)
		assert_almost_eq(top.get_global_rect().position.y, 12.0, 0.01)
		assert_true(_drawn_rect(title, window).end.x <= float(window.size.x) + 0.5, value + " stays on screen")
	window.remove_child(_hud)
	host.free()


static func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
