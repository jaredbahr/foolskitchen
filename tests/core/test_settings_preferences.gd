extends TestCase
## Settings use their own user:// file, never a SaveSystem section or slot.

const PANEL: PackedScene = preload("res://src/ui/settings_panel.tscn")

var _model: SettingsPreferences
var _path: String
var _audio_before: Dictionary[StringName, Dictionary] = {}


func before_each() -> void:
	_audio_before.clear()
	for bus: StringName in [&"Master", &"Music", &"Effects"]:
		var index: int = AudioServer.get_bus_index(bus)
		if index >= 0:
			_audio_before[bus] = {
				"volume_db": AudioServer.get_bus_volume_db(index),
				"mute": AudioServer.is_bus_mute(index),
			}
	_path = "user://test-settings-%d-%d.cfg" % [OS.get_process_id(), get_instance_id()]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	_model = SettingsPreferences.new(_path)


func after_each() -> void:
	for bus: StringName in _audio_before:
		var index: int = AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, float(_audio_before[bus]["volume_db"]))
			AudioServer.set_bus_mute(index, bool(_audio_before[bus]["mute"]))
	_model.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func test_missing_file_uses_safe_defaults_without_creating_a_save() -> void:
	assert_false(_model.load_from_disk())
	assert_eq(_model.master_volume_percent, 100)
	assert_eq(_model.music_volume_percent, 100)
	assert_eq(_model.effects_volume_percent, 100)
	assert_eq(_model.ui_scale_percent, 100)
	assert_eq(_model.default_open_speed, 1)
	assert_false(_model.fullscreen_enabled)
	assert_true(_model.edge_pan_enabled)
	assert_true(_model.build_grid_enabled)
	assert_false(FileAccess.file_exists(_path))


func test_runner_disables_default_file_before_autoload_disk_access() -> void:
	assert_false(SettingsPreferences.should_use_disk(SettingsPreferences.DEFAULT_PATH,
		PackedStringArray(["--headless", "--script", "tools/run_tests.gd"])))
	assert_false(SettingsPreferences.should_use_disk(SettingsPreferences.DEFAULT_PATH,
		PackedStringArray(["-s", "C:\\work\\kitchen\\tools\\run_tests.gd"])))
	assert_false(SettingsPreferences.should_use_disk(SettingsPreferences.DEFAULT_PATH,
		PackedStringArray(["--script=res://tools/run_tests.gd"])))
	assert_false(SettingsPreferences.should_use_disk(SettingsPreferences.DEFAULT_PATH,
		PackedStringArray(["--script", "/work/kitchen/tools/parse_all.gd"])))
	assert_true(SettingsPreferences.should_use_disk(SettingsPreferences.DEFAULT_PATH,
		PackedStringArray(["--path", "."])))
	assert_true(SettingsPreferences.should_use_disk(_path,
		PackedStringArray(["--script", "tools/run_tests.gd"])))
	assert_false(bool(Preferences.get("_disk_enabled")))
	# A real ConfigFile with nondefault values is still tested only at _path.
	assert_true(_model.set_edge_pan_enabled(false))
	var restored: SettingsPreferences = SettingsPreferences.new(_path)
	assert_true(restored.load_from_disk())
	assert_false(restored.edge_pan_enabled)
	restored.free()


func test_changes_save_immediately_and_round_trip_all_choices() -> void:
	assert_true(_model.set_volume_percent(&"Master", 42))
	assert_true(FileAccess.file_exists(_path))
	assert_true(_model.set_volume_percent(&"Music", 57))
	assert_true(_model.set_volume_percent(&"Effects", 0))
	assert_true(_model.set_ui_scale_percent(125))
	assert_true(_model.set_default_open_speed(2))
	assert_true(_model.set_fullscreen_enabled(true))
	assert_true(_model.set_edge_pan_enabled(false))
	assert_true(_model.set_build_grid_enabled(false))
	var restored: SettingsPreferences = SettingsPreferences.new(_path)
	assert_true(restored.load_from_disk())
	assert_false(restored.build_grid_enabled)
	assert_eq(restored.master_volume_percent, 42)
	assert_eq(restored.music_volume_percent, 57)
	assert_eq(restored.effects_volume_percent, 0)
	assert_eq(restored.ui_scale_percent, 125)
	assert_eq(restored.default_open_speed, 2)
	assert_true(restored.fullscreen_enabled)
	assert_false(restored.edge_pan_enabled)
	restored.free()


func test_missing_or_invalid_field_discards_the_whole_file() -> void:
	assert_true(_model.set_volume_percent(&"Master", 23))
	var incomplete: ConfigFile = ConfigFile.new()
	incomplete.set_value("preferences", "version", 1)
	incomplete.set_value("preferences", "master_volume", 20)
	assert_eq(incomplete.save(_path), OK)
	assert_false(_model.load_from_disk())
	assert_eq(_model.master_volume_percent, 100)
	assert_eq(_model.ui_scale_percent, 100)
	var invalid: ConfigFile = ConfigFile.new()
	invalid.set_value("preferences", "version", 1)
	invalid.set_value("preferences", "master_volume", "loud")
	invalid.set_value("preferences", "music_volume", 80)
	invalid.set_value("preferences", "effects_volume", 80)
	invalid.set_value("preferences", "ui_scale", 150)
	invalid.set_value("preferences", "default_open_speed", 2)
	invalid.set_value("preferences", "fullscreen", true)
	invalid.set_value("preferences", "edge_pan", false)
	assert_eq(invalid.save(_path), OK)
	assert_false(_model.load_from_disk())
	assert_eq(_model.master_volume_percent, 100)
	assert_eq(_model.ui_scale_percent, 100)
	assert_eq(_model.default_open_speed, 1)
	assert_true(_model.edge_pan_enabled)
	var broken: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	assert_not_null(broken)
	if broken != null:
		broken.store_string("[preferences\nmaster_volume=15")
		broken.close()
	assert_false(_model.load_from_disk())
	assert_eq(_model.master_volume_percent, 100)
	assert_eq(_model.ui_scale_percent, 100)


func test_a_file_from_before_the_build_grid_choice_still_loads() -> void:
	var older: ConfigFile = ConfigFile.new()
	for pair: Array in [["version", 1], ["master_volume", 40], ["music_volume", 80], ["effects_volume", 80],
			["ui_scale", 125], ["default_open_speed", 2], ["fullscreen", false], ["edge_pan", false]]:
		older.set_value("preferences", pair[0], pair[1])
	assert_eq(older.save(_path), OK)
	assert_true(_model.load_from_disk(), "a missing build_grid is not a broken file")
	assert_eq(_model.master_volume_percent, 40)
	assert_false(_model.edge_pan_enabled)
	assert_true(_model.build_grid_enabled, "Build shows the grid by default")
	older.set_value("preferences", "build_grid", 3)
	assert_eq(older.save(_path), OK)
	assert_false(_model.load_from_disk(), "a build_grid that is not true/false discards the file")
	assert_eq(_model.master_volume_percent, 100)


func test_build_grid_choice_holds_for_the_session_when_it_cannot_be_written() -> void:
	var unwritable: SettingsPreferences = SettingsPreferences.new("res://settings.cfg")
	assert_false(unwritable.set_build_grid_enabled(false))
	assert_false(unwritable.build_grid_enabled, "G still hides Build's grid")
	unwritable.free()


func test_invalid_choices_and_unwritable_path_do_not_change_memory() -> void:
	assert_false(_model.set_volume_percent(&"Master", 101))
	assert_false(_model.set_volume_percent(&"Unknown", 50))
	assert_false(_model.set_ui_scale_percent(175))
	assert_false(_model.set_default_open_speed(4))
	assert_eq(_model.master_volume_percent, 100)
	assert_eq(_model.ui_scale_percent, 100)
	var unwritable: SettingsPreferences = SettingsPreferences.new("res://settings.cfg")
	assert_false(unwritable.set_edge_pan_enabled(false))
	assert_true(unwritable.edge_pan_enabled)
	unwritable.free()


func test_ui_scale_applies_to_window_content_scale_factor() -> void:
	var window: Window = Window.new()
	_model.ui_scale_percent = 125
	_model.apply_window(window)
	assert_almost_eq(window.content_scale_factor, 1.25)
	_model.ui_scale_percent = 150
	_model.apply_window(window)
	assert_almost_eq(window.content_scale_factor, 1.5)
	window.free()


func test_panel_exposes_all_choices_and_writes_through_the_model() -> void:
	var panel: SettingsPanel = PANEL.instantiate() as SettingsPanel
	panel.bind_preferences(_model)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(panel)
	await tree.process_frame
	assert_eq(panel.theme, preload("res://src/ui/theme/main_theme.tres"))
	var scale: OptionButton = panel.get_node("Panel/Column/Scroll/Content/ScaleChoice") as OptionButton
	var speed: OptionButton = panel.get_node("Panel/Column/Scroll/Content/SpeedChoice") as OptionButton
	var music: HSlider = panel.get_node("Panel/Column/Scroll/Content/MusicRow/MusicSlider") as HSlider
	var fullscreen_row: HBoxContainer = panel.get_node("Panel/Column/Scroll/Content/FullscreenRow") as HBoxContainer
	assert_eq(scale.item_count, 3)
	assert_eq(speed.item_count, 2)
	assert_eq(fullscreen_row.visible, not OS.has_feature("web"))
	music.value = 35
	scale.item_selected.emit(2)
	speed.item_selected.emit(1)
	assert_eq(_model.music_volume_percent, 35)
	assert_eq(_model.ui_scale_percent, 150)
	assert_eq(_model.default_open_speed, 2)
	assert_true(FileAccess.file_exists(_path))
	panel.free()


func test_slider_previews_audio_without_writes_until_drag_release() -> void:
	assert_true(_model.save_to_disk())
	var before: String = FileAccess.get_file_as_string(_path)
	var panel: SettingsPanel = PANEL.instantiate() as SettingsPanel
	panel.bind_preferences(_model)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(panel)
	await tree.process_frame
	var music: HSlider = panel.get_node("Panel/Column/Scroll/Content/MusicRow/MusicSlider") as HSlider
	music.value = 70
	assert_eq(FileAccess.get_file_as_string(_path), before)
	music.value = 45
	assert_eq(FileAccess.get_file_as_string(_path), before)
	music.value = 0
	assert_eq(FileAccess.get_file_as_string(_path), before)
	assert_eq(_model.music_volume_percent, 0)
	var bus: int = AudioServer.get_bus_index(&"Music")
	if bus >= 0:
		assert_true(AudioServer.is_bus_mute(bus))
	music.drag_ended.emit(true)
	var restored: SettingsPreferences = SettingsPreferences.new(_path)
	assert_true(restored.load_from_disk())
	assert_eq(restored.music_volume_percent, 0)
	restored.free()
	panel.free()


func test_slider_without_drag_saves_after_debounce_and_close_flushes() -> void:
	assert_true(_model.save_to_disk())
	var before: String = FileAccess.get_file_as_string(_path)
	var panel: SettingsPanel = PANEL.instantiate() as SettingsPanel
	panel.bind_preferences(_model)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(panel)
	await tree.process_frame
	var master: HSlider = panel.get_node("Panel/Column/Scroll/Content/MasterRow/MasterSlider") as HSlider
	# Keyboard steps also emit value_changed without a drag_ended signal.
	master.value = 85
	master.value = 60
	assert_eq(FileAccess.get_file_as_string(_path), before)
	await tree.create_timer(SettingsPanel.SAVE_DELAY + 0.1).timeout
	var restored: SettingsPreferences = SettingsPreferences.new(_path)
	assert_true(restored.load_from_disk())
	assert_eq(restored.master_volume_percent, 60)
	master.value = 35
	(panel.get_node("Panel/Column/CloseButton") as Button).pressed.emit()
	assert_true(restored.load_from_disk())
	assert_eq(restored.master_volume_percent, 35)
	restored.free()
	panel.free()
