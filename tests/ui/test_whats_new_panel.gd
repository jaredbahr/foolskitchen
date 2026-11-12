extends TestCase
## The What's new panel: contents, ordering, the releases link, and the title
## screen opening it once per new release.

const NOTES: String = "### Players\n- A visible change. (#5)\n\n### What to test\n- Seat a party of four.\n\n### Under the hood\n- Tooling. (#6)\n"
const PANEL: PackedScene = preload("res://src/ui/whats_new_panel.tscn")
const TITLE: PackedScene = preload("res://src/ui/title_screen.tscn")

var _nodes: Array[Node] = []
var _old_scene: Node
var _old_last_seen: String
var _clock_processed: bool


func before_each() -> void:
	_old_scene = _tree().current_scene
	_old_last_seen = Preferences.last_seen_version
	Preferences.last_seen_version = ""
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
	Preferences.last_seen_version = _old_last_seen
	Clock.set_speed(0)
	Clock.set_process(_clock_processed)
	Economy.reset(0)
	GameState.new_run(1)


func test_what_to_test_is_the_first_heading() -> void:
	var panel: WhatsNewPanel = _panel()
	panel.present("v0.2.0", NOTES)
	assert_eq(panel.heading_texts(), PackedStringArray(["What to test", "Players", "Under the hood"]))
	assert_eq(panel.line_count(), 3)
	assert_true(panel.visible)
	assert_eq((panel.get_node("Panel/Column/Title") as Label).text, "What's new in v0.2.0")
	assert_eq((panel.get_node("Panel/Column/Version") as Label).text, "Version v0.2.0")


func test_a_dev_build_says_dev_and_empty_notes_say_so() -> void:
	var panel: WhatsNewPanel = _panel()
	panel.present("dev", "")
	assert_eq((panel.get_node("Panel/Column/Version") as Label).text, "Version dev")
	assert_eq((panel.get_node("Panel/Column/Title") as Label).text, "What's new in this build")
	assert_eq(panel.line_count(), 1)


func test_all_release_notes_opens_the_releases_page() -> void:
	var panel: WhatsNewPanel = _panel()
	var opened: Array[String] = []
	panel.opener = func(url: String) -> void: opened.append(url)
	panel.open_all_notes()
	assert_eq(opened, ["https://github.com/jaredbahr/foolskitchen/releases"] as Array[String])


func test_close_hides_the_panel_and_says_so() -> void:
	var panel: WhatsNewPanel = _panel()
	var closes: Array[int] = []
	panel.close_requested.connect(func() -> void: closes.append(1))
	panel.present("v0.2.0", NOTES)
	panel.close()
	assert_false(panel.visible)
	assert_eq(closes.size(), 1)


func test_title_screen_opens_it_once_for_a_new_release() -> void:
	var title: TitleScreen = _title("v0.2.0", NOTES)
	assert_true(title.whats_new.visible)
	assert_false(title.menu.visible)
	assert_eq(Preferences.last_seen_version, "v0.2.0")
	assert_eq(title.version_label.text, "v0.2.0")
	title.whats_new.close()
	assert_true(title.menu.visible)
	# The next launch of the same version stays quiet; its button still works.
	var again: TitleScreen = _title("v0.2.0", NOTES)
	assert_false(again.whats_new.visible)
	assert_true(again.menu.visible)
	again.whats_new_button.pressed.emit()
	assert_true(again.whats_new.visible)
	# A newer release opens it again.
	var newer: TitleScreen = _title("v0.3.0", NOTES)
	assert_true(newer.whats_new.visible)
	assert_eq(Preferences.last_seen_version, "v0.3.0")


func test_title_screen_dev_build_shows_dev_and_never_opens_by_itself() -> void:
	var title: TitleScreen = _title("dev", NOTES)
	assert_eq(title.version_label.text, "dev")
	assert_false(title.whats_new.visible)
	assert_eq(Preferences.last_seen_version, "")
	var sha: TitleScreen = _title("dev-1a2b3c4", NOTES)
	assert_eq(sha.version_label.text, "dev-1a2b3c4")
	assert_false(sha.whats_new.visible)


func test_settings_has_a_whats_new_button() -> void:
	var settings: SettingsPanel = (load("res://src/ui/settings_panel.tscn") as PackedScene).instantiate() as SettingsPanel
	_nodes.append(settings)
	_tree().root.add_child(settings)
	var button: Button = settings.get_node("%WhatsNewButton") as Button
	assert_eq(button.text, "What's new")
	button.pressed.emit()
	var panel: WhatsNewPanel = settings.get_child(settings.get_child_count() - 1) as WhatsNewPanel
	assert_not_null(panel)
	assert_true(panel.visible)


func _panel() -> WhatsNewPanel:
	var panel: WhatsNewPanel = PANEL.instantiate() as WhatsNewPanel
	_nodes.append(panel)
	_tree().root.add_child(panel)
	return panel


func _title(version: String, notes: String) -> TitleScreen:
	var title: TitleScreen = TITLE.instantiate() as TitleScreen
	title.build_version = version
	title.build_notes = notes
	_nodes.append(title)
	_tree().root.add_child(title)
	_tree().current_scene = title
	title.start()
	return title


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
