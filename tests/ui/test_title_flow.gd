extends TestCase
## Real scene transitions keep the morning save as the only durable boundary.

var _nodes: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_scene: Node
var _clock_processed: bool


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "title_flow")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot("autosave")
	_old_scene = _tree().current_scene
	_clock_processed = Clock.is_processing()
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			if _tree().current_scene == node:
				_tree().current_scene = null
			if node.is_inside_tree():
				node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()
	_tree().current_scene = _old_scene if is_instance_valid(_old_scene) else null
	SaveSystem.delete_slot("autosave")
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Clock.set_process(_clock_processed)
	Economy.reset(0)
	GameState.new_run(1)


func test_continue_is_hidden_without_a_save_and_visible_for_an_existing_slot() -> void:
	var title: TitleScreen = _title()
	assert_false(title.continue_button.visible)
	_write_placeholder_save()
	title.refresh_save_availability()
	assert_true(title.continue_button.visible)
	SaveSystem.delete_slot("autosave")
	title.refresh_save_availability()
	assert_false(title.continue_button.visible)


func test_new_game_requires_confirmation_and_cancel_preserves_the_exact_save() -> void:
	_write_placeholder_save()
	var saved: String = _saved_text()
	var title: TitleScreen = _title()
	title.request_new_game()
	assert_true(title.confirmation.visible)
	assert_eq(title.confirmation.dialog_text, TitleText.START_OVER)
	title.confirmation.hide()
	assert_eq(_saved_text(), saved)
	assert_true(_tree().current_scene == title)


func test_display_only_backdrop_does_not_load_save_start_service_or_consume_run_rng() -> void:
	_write_placeholder_save()
	var saved: String = _saved_text()
	GameState.new_run(782)
	Economy.reset(499)
	var random: RandomNumberGenerator = GameState.rng(&"customers")
	var stream: int = random.state
	var clock: SimClock = Clock.sim
	var day: Dictionary = clock.to_dict()
	var title: TitleScreen = _title()
	var backdrop: Node = title.get("_backdrop") as Node
	backdrop.call("start")  # Explicit calls must respect display-only mode too.
	assert_true(backdrop.get("display_only"))
	assert_false(backdrop.get("use_saves"))
	assert_false(backdrop.get("_started"))
	assert_true(Clock.sim == clock)
	assert_eq(Clock.sim.to_dict(), day)
	assert_eq(Economy.cash, 499)
	assert_eq(random.state, stream)
	assert_eq(_saved_text(), saved)
	assert_false((backdrop.get_node("HUD") as CanvasLayer).visible)
	var camera: CameraRig = backdrop.get_node("CameraRig") as CameraRig
	var yaw: float = camera.rotation.y
	title.call("_process", 1.0)
	assert_almost_eq(camera.rotation.y - yaw, deg_to_rad(TitleScreen.ORBIT_DEGREES_PER_SECOND))
	title.call("_process", 50.0)
	assert_eq(backdrop.get_node("ShopView").get("_camera_quarter"), 1,
		"the slow orbit updates cutaway walls when it crosses a camera quarter")
	assert_eq(random.state, stream)
	assert_eq(Clock.sim.to_dict(), day)


func test_settings_reuses_the_existing_panel_without_an_in_game_quit_action() -> void:
	var title: TitleScreen = _title()
	title.settings_button.pressed.emit()
	assert_true(title.settings.visible)
	assert_false(title.menu.visible)
	assert_false((title.settings.get_node("Panel/Column/QuitToTitleButton") as Button).visible)
	assert_eq(title.settings.theme, load("res://src/ui/theme/main_theme.tres"))
	title.settings.close_requested.emit()
	assert_false(title.settings.visible)
	assert_true(title.menu.visible)
	assert_eq(SaveSystem.list_slots().size(), 0)


func test_confirmation_text_stays_readable_with_focus_without_changing_shared_theme_or_padding() -> void:
	var shared: Theme = load("res://src/ui/theme/main_theme.tres") as Theme
	var had_panel: bool = shared.has_stylebox("panel", "AcceptDialog")
	var had_focus: bool = shared.has_color("font_focus_color", "Button")
	var default_panel: StyleBoxFlat = ThemeDB.get_default_theme().get_stylebox("panel", "AcceptDialog") as StyleBoxFlat
	var default_fill: Color = default_panel.bg_color
	var shared_panel: StyleBoxFlat = shared.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var shared_fill: Color = shared_panel.bg_color
	var title: TitleScreen = _title()
	var main: Node = _shop()
	for dialog: ConfirmationDialog in [title.confirmation, main.get_node("Overlay/QuitToTitle")]:
		var panel: StyleBoxFlat = dialog.get_theme_stylebox("panel", "AcceptDialog") as StyleBoxFlat
		assert_eq(panel.bg_color, shared_fill, "dialog content uses the approved cream")
		assert_true(_contrast(dialog.get_label().get_theme_color("font_color"), panel.bg_color) >= 4.5,
			"replacement and progress-loss warnings remain readable")
		for button: Button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
			var normal: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
			assert_true(_contrast(button.get_theme_color("font_focus_color"), normal.bg_color) >= 4.5,
				"focused confirmation and cancel captions remain readable")
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_almost_eq(panel.get_content_margin(side), default_panel.get_content_margin(side),
				0.001, "the correction retains the native dialog padding")
	assert_eq(default_panel.bg_color, default_fill, "the engine fallback style is unchanged")
	assert_eq(shared_panel.bg_color, shared_fill, "the shared panel is unchanged")
	assert_eq(shared.has_stylebox("panel", "AcceptDialog"), had_panel, "other dialogs keep their theme")
	assert_eq(shared.has_color("font_focus_color", "Button"), had_focus, "other buttons keep their theme")


func test_new_game_without_a_save_boots_the_real_shop_and_uses_its_morning_autosave() -> void:
	var title: TitleScreen = _title()
	title.request_new_game()
	await _settle_transition()
	var main: Node = _tree().current_scene
	assert_eq(main.scene_file_path, TitleScreen.MAIN_SCENE)
	assert_true(main.get("_started"))
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(Clock.sim.day, 1)
	assert_true(SaveSystem.list_slots().has("autosave"))


func test_confirmed_new_game_replaces_the_old_run_through_the_f10_reset_route() -> void:
	var main: Node = _shop()
	Clock.sim.day = 7
	main.call("_begin_morning")
	main.call("request_quit_to_title")
	await _settle_transition()
	var title: TitleScreen = _tree().current_scene as TitleScreen
	assert_not_null(title)
	title.request_new_game()
	assert_true(title.confirmation.visible)
	title.confirmation.confirmed.emit()
	await _settle_transition()
	assert_eq(_tree().current_scene.scene_file_path, TitleScreen.MAIN_SCENE)
	assert_eq(Clock.sim.day, 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


func test_quit_to_title_during_service_warns_pauses_and_cancel_keeps_the_shop() -> void:
	var main: Node = _shop()
	var saved: String = _saved_text()
	assert_true(Clock.sim.start_service())
	Clock.set_speed(2)
	main.call("request_quit_to_title")
	var dialog: ConfirmationDialog = main.get_node("Overlay/QuitToTitle") as ConfirmationDialog
	assert_true(dialog.visible)
	assert_eq(dialog.dialog_text, TitleText.LOST_PROGRESS)
	assert_eq(Clock.speed, 0)
	dialog.canceled.emit()
	dialog.hide()
	assert_eq(Clock.speed, 2)
	assert_true(_tree().current_scene == main)
	assert_eq(_saved_text(), saved)


func test_quit_then_continue_reloads_the_morning_without_saving_service_changes() -> void:
	var main: Node = _shop()
	var morning_cash: int = Economy.cash
	var saved: String = _saved_text()
	assert_true(Clock.sim.start_service())
	Economy.add_cash(77, Ledger.OTHER)
	main.call("request_quit_to_title")
	(main.get_node("Overlay/QuitToTitle") as ConfirmationDialog).confirmed.emit()
	await _settle_transition()
	var title: TitleScreen = _tree().current_scene as TitleScreen
	assert_not_null(title)
	assert_eq(_saved_text(), saved, "quitting never writes the shop")
	assert_true(title.continue_button.visible)
	title.continue_game()
	await _settle_transition()
	assert_eq(_tree().current_scene.scene_file_path, TitleScreen.MAIN_SCENE)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(Economy.cash, morning_cash, "Continue uses the existing morning restore")


func test_menu_and_service_settings_both_expose_quit_to_title() -> void:
	var main: Node = _shop()
	var menu: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	assert_eq((menu.get_node("Panel/Content/Header/QuitToTitleButton") as Button).text, TitleText.QUIT_TO_TITLE)
	assert_true(main.call("set_settings_visible", true))
	var settings: SettingsPanel = main.get_node("Overlay/SettingsPanel") as SettingsPanel
	assert_true((settings.get_node("Panel/Column/QuitToTitleButton") as Button).visible)
	assert_true(Clock.sim.start_service())
	settings.quit_to_title_requested.emit()
	assert_true((main.get_node("Overlay/QuitToTitle") as ConfirmationDialog).visible)


func test_return_actions_fit_menu_and_settings_at_1280_and_150_percent() -> void:
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_embed_subwindows = true
	_nodes.append(host)
	_tree().root.add_child(host)
	var window: Window = Window.new()
	window.borderless = true
	window.size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_factor = 1.5
	host.add_child(window)
	var main: Node = (load(TitleScreen.MAIN_SCENE) as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 1)
	window.add_child(main)
	main.call("start")
	assert_true(main.call("set_menu_visible", true))
	for frame: int in 4:
		await _tree().process_frame
	var menu_panel: Control = main.get_node("Overlay/MenuPanel/Panel") as Control
	var menu_quit: Button = main.get_node("Overlay/MenuPanel/Panel/Content/Header/QuitToTitleButton") as Button
	assert_true(menu_panel.get_global_rect().encloses(menu_quit.get_global_rect()))
	assert_true(window.get_visible_rect().encloses(menu_panel.get_global_rect()))
	assert_true(main.call("set_settings_visible", true))
	for frame: int in 4:
		await _tree().process_frame
	var settings_panel: Control = main.get_node("Overlay/SettingsPanel/Panel") as Control
	var settings_quit: Button = main.get_node("Overlay/SettingsPanel/Panel/Column/QuitToTitleButton") as Button
	var close: Button = main.get_node("Overlay/SettingsPanel/Panel/Column/CloseButton") as Button
	assert_true(settings_panel.get_global_rect().encloses(settings_quit.get_global_rect()))
	assert_true(settings_panel.get_global_rect().encloses(close.get_global_rect()))
	assert_true(window.get_visible_rect().encloses(settings_panel.get_global_rect()))


func _title() -> TitleScreen:
	var title: TitleScreen = (load("res://src/ui/title_screen.tscn") as PackedScene).instantiate() as TitleScreen
	_nodes.append(title)
	_tree().root.add_child(title)
	_tree().current_scene = title
	title.start()
	return title


func _shop() -> Node:
	var main: Node = (load(TitleScreen.MAIN_SCENE) as PackedScene).instantiate()
	main.set("new_game_seed_override", 1)
	_nodes.append(main)
	_tree().root.add_child(main)
	_tree().current_scene = main
	main.call("start")
	return main


func _settle_transition() -> void:
	for frame: int in 4:
		await _tree().process_frame
	if _tree().current_scene != null and not _nodes.has(_tree().current_scene):
		_nodes.append(_tree().current_scene)


func _write_placeholder_save() -> void:
	DirAccess.make_dir_recursive_absolute(_save_dir)
	var file: FileAccess = FileAccess.open(_save_dir.path_join("autosave.json"), FileAccess.WRITE)
	file.store_string('{"version":1,"data":{}}')
	file.close()


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join("autosave.json"))


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _contrast(a: Color, b: Color) -> float:
	var first: Color = a.srgb_to_linear()
	var second: Color = b.srgb_to_linear()
	var la: float = first.get_luminance()
	var lb: float = second.get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
