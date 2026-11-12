extends TestCase
## FK-141: New game asks Career or Creative; Continue names a Creative save.

var _nodes: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_scene: Node
var _clock_processed: bool


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "creative_title")
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
	GameMode.set_creative(false)
	GameMode.request_new_game(false)
	Clock.set_speed(0)
	Clock.set_process(_clock_processed)
	Economy.reset(0)
	GameState.new_run(1)


func test_new_game_offers_career_or_creative_with_one_line_each() -> void:
	var title: TitleScreen = _title()
	title.new_button.pressed.emit()
	assert_true(title.mode_choice.visible)
	assert_false(title.menu.visible)
	var career: Button = title.mode_choice.find_child("Career", true, false) as Button
	var creative: Button = title.mode_choice.find_child("Creative", true, false) as Button
	assert_eq(career.text, TitleText.CAREER)
	assert_eq(creative.text, TitleText.CREATIVE)
	var lines: Array[String] = []
	for label: Node in title.mode_choice.find_children("*", "Label", true, false):
		lines.append((label as Label).text)
	assert_true(lines.has(TitleText.CREATIVE_LINE))
	assert_eq(TitleText.CREATIVE_LINE, "Build anything. No money, no limits.")
	assert_true(lines.has(TitleText.CAREER_LINE))
	(title.mode_choice.find_child("Back", true, false) as Button).pressed.emit()
	assert_false(title.mode_choice.visible)
	assert_true(title.menu.visible)


func test_creative_starts_a_creative_game_and_continue_names_it() -> void:
	var title: TitleScreen = _title()
	title.show_mode_choice()
	(title.mode_choice.find_child("Creative", true, false) as Button).pressed.emit()
	await _settle_transition()
	var main: Node = _tree().current_scene
	assert_eq(main.scene_file_path, TitleScreen.MAIN_SCENE)
	assert_true(GameMode.is_creative())
	assert_true((main.get_node("HUD/Top/Row/Creative") as Label).visible)
	assert_true(SaveSystem.list_slots().has("autosave"))
	main.call("request_quit_to_title")
	await _settle_transition()
	var again: TitleScreen = _tree().current_scene as TitleScreen
	assert_not_null(again)
	assert_eq(again.continue_button.text, TitleText.CONTINUE + TitleText.CREATIVE_SUFFIX)
	# Replacing it with a career game keeps the plain label.
	again.show_mode_choice()
	(again.mode_choice.find_child("Career", true, false) as Button).pressed.emit()
	assert_true(again.confirmation.visible, "an existing save still asks first")
	again.confirmation.confirmed.emit()
	await _settle_transition()
	assert_false(GameMode.is_creative())
	_tree().current_scene.call("request_quit_to_title")
	await _settle_transition()
	assert_eq((_tree().current_scene as TitleScreen).continue_button.text, TitleText.CONTINUE)


func _title() -> TitleScreen:
	var title: TitleScreen = (load("res://src/ui/title_screen.tscn") as PackedScene).instantiate() as TitleScreen
	_nodes.append(title)
	_tree().root.add_child(title)
	_tree().current_scene = title
	title.start()
	return title


func _settle_transition() -> void:
	for frame: int in 4:
		await _tree().process_frame
	if _tree().current_scene != null and not _nodes.has(_tree().current_scene):
		_nodes.append(_tree().current_scene)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
