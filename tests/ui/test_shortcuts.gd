extends TestCase
## Shortcut help, project bindings, and real viewport keyboard delivery.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node3D
var _old_sim: SimClock
var _old_speed: int
var _old_last_speed: int
var _old_accumulator: float
var _old_attached_world: SimWorld
var _old_tick_driver: Callable
var _old_driven_world_tick: int
var _old_economy: Dictionary
var _old_game_state: Dictionary
var _old_providers: Dictionary
var _speed_events: Array[int] = []


func before_each() -> void:
	_old_sim = Clock.sim
	_old_speed = Clock.speed
	_old_last_speed = Clock._last_non_zero_speed
	_old_accumulator = Clock._accumulator
	_old_attached_world = Clock.attached_world
	_old_tick_driver = Clock.tick_driver
	_old_driven_world_tick = Clock.driven_world_tick
	_old_economy = Economy._capture_save()
	_old_game_state = GameState._capture_save()
	_old_providers = SaveSystem._providers.duplicate(true)
	_speed_events.clear()
	Clock.set_speed(0)
	EventBus.speed_changed.connect(_record_speed)


func after_each() -> void:
	if EventBus.speed_changed.is_connected(_record_speed):
		EventBus.speed_changed.disconnect(_record_speed)
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	SaveSystem._providers = _old_providers
	Clock.attach_world(_old_attached_world, _old_tick_driver)
	Clock.sim = _old_sim
	Clock.tick_driver = _old_tick_driver
	Clock.driven_world_tick = _old_driven_world_tick
	Clock._accumulator = _old_accumulator
	Clock.set_speed(_old_speed)
	Clock._last_non_zero_speed = _old_last_speed
	Economy._restore_save(_old_economy)
	GameState._restore_save(_old_game_state)


func test_shortcuts_table_covers_every_project_key_action_and_preserves_speed_alias() -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_eq(config.load("res://project.godot"), OK)
	var covered: Dictionary[StringName, bool] = {}
	var seen_groups: Dictionary[String, bool] = {}
	for row: Dictionary in ShortcutsText.ROWS:
		seen_groups[row["group"]] = true
		for action: StringName in row.get("input_actions", []):
			covered[action] = true
	for group_name: String in ShortcutsText.GROUPS:
		assert_true(seen_groups.has(group_name), "%s has a visible section" % group_name)
	for action: String in config.get_section_keys("input"):
		var setting: Variant = config.get_value("input", action)
		var has_key_event: bool = false
		if setting is Dictionary:
			for event: Variant in setting.get("events", []):
				if event is InputEventKey:
					has_key_event = true
					break
		if has_key_event:
			assert_true(covered.has(StringName(action)), "shortcuts table includes project action %s" % action)
	assert_true(covered.has(&"speed_3"))
	assert_true(covered.has(&"speed_4"), "the old speed_4 action remains documented")
	assert_eq(InputMap.action_get_events(&"speed_3").size(), 2, "top-row and keypad 3 are both mapped")
	assert_eq(InputMap.action_get_events(&"speed_4").size(), 1, "legacy speed_4 keeps its original top-row binding")
	assert_true(_action_has_key(&"speed_pause", KEY_SPACE))
	assert_true(_action_has_key(&"speed_1", KEY_1))
	assert_true(_action_has_key(&"speed_2", KEY_2))
	assert_true(_action_has_key(&"speed_3", KEY_3))
	assert_true(_action_has_key(&"speed_4", KEY_3))
	assert_true(_action_has_key(&"speed_1", KEY_KP_1))
	assert_true(_action_has_key(&"speed_2", KEY_KP_2))
	assert_true(_action_has_key(&"speed_3", KEY_KP_3))


func test_top_row_and_keypad_speed_keys_reach_clock_once_and_refresh_hud() -> void:
	await _start_main()
	for input_key: Key in [KEY_1, KEY_KP_1, KEY_2, KEY_KP_2, KEY_3, KEY_KP_3]:
		var expected: int = 1 if input_key in [KEY_1, KEY_KP_1] else (2 if input_key in [KEY_2, KEY_KP_2] else 4)
		var old_count: int = _speed_events.size()
		await _send_key(input_key, true)
		assert_eq(Clock.speed, expected, "key %s selects the intended speed" % input_key)
		assert_eq(_speed_events.size(), old_count + 1, "one physical key emits one speed change")
		assert_true(_speed_button(expected).button_pressed, "HUD highlights the selected speed")
		await _send_key(input_key, false)
		assert_eq(_speed_events.size(), old_count + 1, "key release does not emit another speed change")
	var before_echo: int = _speed_events.size()
	await _send_key(KEY_1, true, true)
	assert_eq(Clock.speed, 4, "key repeat is ignored")
	assert_eq(_speed_events.size(), before_echo, "echo does not emit a speed change")
	await _send_key(KEY_1, false)


func test_text_focus_blocks_speed_keys_and_f1_in_real_viewport_input() -> void:
	await _start_main()
	assert_true(_main.call("set_menu_visible", true))
	var line: LineEdit = _main.get_node("Overlay/MenuPanel/Panel/Content/Identity/NameRow/RestaurantName") as LineEdit
	line.grab_focus()
	await _frame()
	assert_eq(_main.get_viewport().gui_get_focus_owner(), line)
	var speed_count: int = _speed_events.size()
	Clock._unhandled_input(_key_event(KEY_1, true))
	assert_eq(Clock.speed, 0, "the Clock owner also rejects the key when text is focused")
	assert_eq(_speed_events.size(), speed_count, "Clock focus guard emits no speed change")
	await _send_key(KEY_1, true)
	assert_eq(Clock.speed, 0, "a focused LineEdit does not trigger a speed action")
	await _send_key(KEY_1, false)
	await _send_key(KEY_F1, true)
	assert_false(_main.call("is_shortcuts_visible"), "F1 does not steal focus from text entry")
	await _send_key(KEY_F1, false)
	line.release_focus()
	_main.call("set_menu_visible", false)
	await _frame()

	var text: TextEdit = TextEdit.new()
	text.name = "ShortcutFocusText"
	text.focus_mode = Control.FOCUS_ALL
	text.custom_minimum_size = Vector2(300.0, 120.0)
	_main.get_node("Overlay").add_child(text)
	text.grab_focus()
	await _frame()
	assert_eq(_main.get_viewport().gui_get_focus_owner(), text)
	await _send_key(KEY_KP_2, true)
	assert_eq(Clock.speed, 0, "a focused TextEdit blocks keypad speed input too")
	await _send_key(KEY_KP_2, false)
	text.release_focus()
	text.queue_free()
	await _frame()

	assert_true(_main.call("show_owner_picker", true))
	var owner_name: LineEdit = _main.get_node("Overlay/OwnerPicker/Panel/ContentScroll/Rows/OwnerName") as LineEdit
	owner_name.grab_focus()
	await _frame()
	assert_eq(_main.get_viewport().gui_get_focus_owner(), owner_name)
	await _send_key(KEY_3, true)
	assert_eq(Clock.speed, 0, "the owner-name field does not trigger the third speed")
	await _send_key(KEY_3, false)
	await _send_key(KEY_F1, true)
	assert_false(_main.call("is_shortcuts_visible"), "the owner picker keeps F1 reserved for text entry")
	await _send_key(KEY_F1, false)


func test_f1_panel_is_modal_nonpausing_and_escape_restores_focus() -> void:
	await _start_main()
	var focus_target: Button = Button.new()
	focus_target.name = "PriorFocus"
	focus_target.text = "Prior focus"
	focus_target.focus_mode = Control.FOCUS_ALL
	focus_target.custom_minimum_size = Vector2(120.0, 34.0)
	var overlay: CanvasLayer = _main.get_node("Overlay") as CanvasLayer
	overlay.add_child(focus_target)
	overlay.move_child(focus_target, overlay.get_node("ShortcutsPanel").get_index())
	focus_target.grab_focus()
	await _frame()
	var speed_before: int = Clock.speed
	await _send_key(KEY_F1, true)
	assert_true(_main.call("is_shortcuts_visible"))
	var help_panel: Control = _main.get_node("Overlay/ShortcutsPanel") as Control
	assert_eq(help_panel.mouse_filter, Control.MOUSE_FILTER_STOP, "the full-screen panel blocks clicks through it")
	assert_eq((help_panel.get_node("Backdrop") as Control).mouse_filter, Control.MOUSE_FILTER_STOP)
	var headings: HBoxContainer = help_panel.get_node("Panel/Column/Columns") as HBoxContainer
	assert_eq(headings.get_child_count(), 2, "the reference has Key and Action columns")
	var content: VBoxContainer = help_panel.get_node("Panel/Column/Scroll/Content") as VBoxContainer
	assert_true(content.get_child_count() > 3, "the grouped reference rows are built from the shared table")
	for child: Node in content.get_children():
		if child is HBoxContainer:
			assert_eq((child as HBoxContainer).get_child_count(), 2, "each shortcut row uses two columns")
	assert_eq(Clock.speed, speed_before, "opening help does not pause the simulation")
	assert_eq(_main.get_viewport().gui_get_focus_owner(), help_panel.get_node("Panel/Column/Header/Close"))
	await _send_key(KEY_1, true)
	assert_eq(Clock.speed, speed_before, "modal keyboard input does not change game speed")
	await _send_key(KEY_1, false)
	await _send_key(KEY_ESCAPE, true)
	assert_false(_main.call("is_shortcuts_visible"))
	assert_eq(_main.get_viewport().gui_get_focus_owner(), focus_target, "closing restores the prior live focus")
	await _send_key(KEY_ESCAPE, false)
	await _send_key(KEY_F1, true)
	assert_true(_main.call("is_shortcuts_visible"))
	await _send_key(KEY_F1, false)
	await _send_key(KEY_F1, true)
	assert_false(_main.call("is_shortcuts_visible"), "F1 toggles the panel closed")
	await _send_key(KEY_F1, false)


func test_photo_name_and_desktop_only_shortcuts() -> void:
	assert_eq(PhotoMode.file_name(3, 9 * 60 + 5), "fools_kitchen_3_0905.png")
	assert_eq(PhotoMode.file_name(12, 0), "fools_kitchen_12_0000.png")
	assert_true(PhotoMode.available(false))
	assert_false(PhotoMode.available(true))
	var desktop: Array[Dictionary] = ShortcutsText.rows_for("Game", PhotoMode.available(false))
	var web: Array[Dictionary] = ShortcutsText.rows_for("Game", PhotoMode.available(true))
	assert_eq(desktop.size(), web.size() + 2)
	assert_eq(desktop[-2]["keys"], "F12")
	assert_eq(desktop[-1]["keys"], "Shift + F12")
	for row: Dictionary in web:
		assert_false(String(row["keys"]).contains("F12"))


func test_held_photo_mode_keeps_camera_keys_and_restores_original_visibility() -> void:
	await _start_main()
	var photo: PhotoMode = _main.get_node("PhotoMode")
	var hud: CanvasLayer = _main.get_node("HUD")
	var overlay: CanvasLayer = _main.get_node("Overlay")
	var debug: Node3D = _main.get_node("DebugGeometry")
	var camera: CameraRig = _main.get_node("CameraRig")
	var speed: int = Clock.speed
	var grid: bool = camera.effective_grid_visible()
	var turn: int = camera.camera_quarter()
	overlay.hide()
	debug.hide()
	await _send_photo_toggle()
	assert_true(photo.held)
	assert_false(hud.visible)
	assert_false(overlay.visible)
	assert_false(debug.visible)
	assert_eq(camera.grid_material.get_shader_parameter("grid_visible"), false)
	await _send_key(KEY_Q, true)
	await _send_key(KEY_Q, false)
	assert_eq(camera.camera_quarter(), posmod(turn - 1, 4), "camera input stays available in photo mode")
	await _send_key(KEY_ESCAPE, true)
	await _send_key(KEY_ESCAPE, false)
	assert_false(photo.held)
	assert_true(hud.visible)
	assert_false(overlay.visible)
	assert_false(debug.visible)
	assert_eq(camera.grid_material.get_shader_parameter("grid_visible"), grid)
	assert_eq(Clock.speed, speed)
	assert_false(_main.call("is_settings_visible"), "Escape only leaves photo mode")
	await _send_photo_toggle()
	assert_true(photo.held)
	await _send_photo_toggle()
	assert_false(photo.held)
	assert_true(hud.visible)
	assert_false(overlay.visible)


func _send_photo_toggle() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = _key_event(KEY_F12, pressed)
		event.shift_pressed = true
		Input.parse_input_event(event)
		await _frame()


func _start_main() -> void:
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	await _frame()
	Clock.set_speed(0)
	assert_true(_main.is_inside_tree())
	assert_false(_main.call("is_shortcuts_visible"))


func _send_key(code: Key, pressed: bool, echo: bool = false) -> void:
	Input.parse_input_event(_key_event(code, pressed, echo))
	await _frame()


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _speed_button(speed: int) -> Button:
	return _main.get_node("HUD/Top/Row/Speed%d" % speed) as Button


func _action_has_key(action: StringName, code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null and key.physical_keycode == code:
			return true
	return false


func _key_event(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _record_speed(value: int) -> void:
	_speed_events.append(value)
