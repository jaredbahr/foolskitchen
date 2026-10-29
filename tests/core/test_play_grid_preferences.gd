extends TestCase
## Private preference fixtures prove play/Build independence without shop saves.

const RIG: PackedScene = preload("res://src/world/camera_rig.tscn")
const HUD: PackedScene = preload("res://src/ui/hud.tscn")
const PANEL: PackedScene = preload("res://src/ui/settings_panel.tscn")

var _path: String
var _model: SettingsPreferences
var _nodes: Array[Node] = []


func before_each() -> void:
	_path = "user://test-play-grid-%d-%d.cfg" % [OS.get_process_id(), get_instance_id()]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	_model = SettingsPreferences.new(_path)


func after_each() -> void:
	for index: int in range(_nodes.size() - 1, -1, -1):
		_nodes[index].free()
	_nodes.clear()
	_model.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func test_play_grid_round_trip_keeps_build_choice_separate() -> void:
	assert_true(_model.play_grid_enabled)
	assert_true(_model.set_play_grid_enabled(false))
	assert_true(_model.build_grid_enabled)
	var restored: SettingsPreferences = SettingsPreferences.new(_path)
	assert_true(restored.load_from_disk())
	assert_false(restored.play_grid_enabled)
	assert_true(restored.build_grid_enabled)
	restored.free()
	assert_true(_model.set_build_grid_enabled(false))
	assert_true(_model.set_play_grid_enabled(true))
	assert_false(_model.build_grid_enabled)


func test_older_file_defaults_play_grid_on_and_invalid_value_resets_all() -> void:
	assert_true(_model.set_volume_percent(&"Master", 42))
	assert_true(_model.set_build_grid_enabled(false))
	var config: ConfigFile = ConfigFile.new()
	assert_eq(config.load(_path), OK)
	config.erase_section_key(SettingsPreferences.SECTION, "play_grid")
	assert_eq(config.save(_path), OK)
	assert_true(_model.load_from_disk())
	assert_true(_model.play_grid_enabled)
	assert_false(_model.build_grid_enabled)
	assert_eq(_model.master_volume_percent, 42)
	for invalid: Variant in [0, "false", 1.0]:
		config.set_value(SettingsPreferences.SECTION, "play_grid", invalid)
		assert_eq(config.save(_path), OK)
		assert_false(_model.load_from_disk())
		assert_true(_model.play_grid_enabled)
		assert_true(_model.build_grid_enabled)
		assert_eq(_model.master_volume_percent, 100)


func test_unwritable_play_choice_still_holds_for_session() -> void:
	var model: SettingsPreferences = SettingsPreferences.new("res://settings.cfg")
	assert_false(model.set_play_grid_enabled(false))
	assert_false(model.play_grid_enabled)
	assert_true(model.build_grid_enabled)
	model.free()


func test_g_persists_and_fresh_camera_reads_saved_play_choice() -> void:
	var rig: CameraRig = _rig(_model)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	rig._unhandled_input(key)
	assert_false(rig.grid_visible)
	var restored: SettingsPreferences = SettingsPreferences.new(_path)
	_nodes.append(restored)
	assert_true(restored.load_from_disk())
	var fresh: CameraRig = _rig(restored)
	assert_false(fresh.grid_visible)
	assert_true(fresh.build_grid_visible)
	rig.set_grid_forced(true)
	assert_true(rig.effective_grid_visible())
	rig._unhandled_input(key)
	assert_false(_model.build_grid_enabled)
	assert_false(_model.play_grid_enabled)
	rig.set_grid_forced(false)
	assert_false(rig.effective_grid_visible())
	key.echo = true
	rig._unhandled_input(key)
	assert_false(rig.grid_visible)


func test_walls_tooltip_exposes_g_without_adding_a_hud_control() -> void:
	var hud: CanvasLayer = HUD.instantiate() as CanvasLayer
	_nodes.append(hud)
	hud.call("refresh")
	assert_false(hud.has_node("Top/Row/Grid"), "play grid must not reflow the existing HUD")
	var walls: Button = hud.get_node("Top/Row/Walls") as Button
	assert_true(walls.tooltip_text.contains("G: grid"))
	assert_true(walls.tooltip_text.contains("Cycle walls:"))


func test_settings_checkboxes_persist_and_follow_external_grid_changes() -> void:
	var panel: SettingsPanel = PANEL.instantiate() as SettingsPanel
	_nodes.append(panel)
	panel.bind_preferences(_model)
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	var play: CheckButton = panel.get_node("%PlayGridToggle") as CheckButton
	var build: CheckButton = panel.get_node("%BuildGridToggle") as CheckButton
	assert_true(play.button_pressed)
	assert_true(build.button_pressed)
	play.button_pressed = false
	assert_false(_model.play_grid_enabled)
	assert_true(_model.build_grid_enabled)
	build.button_pressed = false
	assert_false(_model.build_grid_enabled)
	assert_true(_model.set_play_grid_enabled(true))
	assert_true(play.button_pressed)
	assert_false(build.button_pressed)
	var restored: SettingsPreferences = SettingsPreferences.new(_path)
	assert_true(restored.load_from_disk())
	assert_true(restored.play_grid_enabled)
	assert_false(restored.build_grid_enabled)
	restored.free()


func _rig(model: SettingsPreferences) -> CameraRig:
	var rig: CameraRig = RIG.instantiate() as CameraRig
	_nodes.append(rig)
	rig.bind_preferences(model)
	(Engine.get_main_loop() as SceneTree).root.add_child(rig)
	return rig
