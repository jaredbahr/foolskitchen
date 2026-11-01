extends TestCase
## The real shop owns guide triggers and uses only its morning save boundary.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const Guide := preload("res://src/ui/hints.gd")
const SLOT: String = "autosave"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _clock_processing: bool
var _old_scene: Node


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "hints_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_clock_processing = Clock.is_processing()
	Clock.set_process(false)
	Clock.set_speed(0)
	_old_scene = _tree().current_scene


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	_tree().current_scene = _old_scene if is_instance_valid(_old_scene) else null
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Clock.set_process(_clock_processing)
	Economy.reset(0)
	GameState.new_run(1)


func test_menu_hint_and_got_it_leave_menu_usable_and_wait_for_actual_close() -> void:
	var main: Node = _start()
	var guide: Guide = _guide(main)
	assert_eq(guide.active_hint, Guide.Step.MENU)
	var bubble: Control = _bubble(main)
	assert_true(bubble.visible)
	assert_eq((bubble.get_node("Bubble/Column/Text") as Label).text, Guide.text_for(Guide.Step.MENU))
	_got_it(main)
	assert_eq(guide.active_hint, -1)
	main.call("refresh_hints")
	assert_eq(guide.active_hint, -1)
	(main.get_node("HUD/Top/Row/Menu") as Button).pressed.emit()
	assert_true(main.call("is_menu_visible"))
	main.call("refresh_hints")
	assert_ne(guide.active_hint, Guide.Step.STOCK)
	assert_true(main.call("set_menu_visible", false))
	main.call("refresh_hints")
	assert_eq(guide.active_hint, Guide.Step.STOCK)
	_got_it(main)
	assert_eq(guide.active_hint, Guide.Step.BUILD)
	_got_it(main)
	assert_eq(guide.active_hint, Guide.Step.OPEN)


func test_hint_skip_and_acknowledgement_do_not_save_or_change_simulation_state() -> void:
	var main: Node = _start()
	var saved: String = _saved_text()
	var clock: Dictionary = Clock.sim.to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var stream: int = GameState.rng(&"customers").state
	Clock.set_speed(2)
	main.call("refresh_hints")
	_got_it(main)
	_skip(main)
	assert_eq(Clock.speed, 2, "hint controls never force a pause")
	assert_false(_tree().paused)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(GameState.rng(&"customers").state, stream)
	assert_eq(_saved_text(), saved, "guide actions wait for the morning checkpoint")
	assert_eq(_guide(main).next_hint, Guide.Step.COMPLETE)
	assert_false(_bubble(main).visible)
	_next_morning()
	assert_eq(_guide(main).active_hint, -1)
	assert_false(_bubble(main).visible)


func test_guide_overlay_has_no_full_screen_input_shield_and_controls_still_work() -> void:
	var main: Node = _start(false)
	var bubble: Control = _bubble(main)
	assert_eq(bubble.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var card: Control = bubble.get_node("Bubble") as Control
	assert_true(card.mouse_filter != Control.MOUSE_FILTER_STOP,
		"the bubble background does not consume unrelated world input")
	for path: String in ["Bubble/Column/Actions/GotIt", "Bubble/Column/Actions/SkipGuide"]:
		var button: Button = bubble.get_node(path) as Button
		assert_false(button.disabled)
		assert_true(button.mouse_filter != Control.MOUSE_FILTER_IGNORE)
	assert_true(main.call("set_menu_visible", true), "a hint does not lock the Menu")
	assert_true(main.call("set_menu_visible", false))
	assert_true(Clock.sim.start_service(), "a hint does not force the suggested actions before opening")
	Clock.set_speed(2)
	main.call("refresh_hints")
	assert_eq(Clock.speed, 2)
	var tick: int = Clock.sim.tick
	main.call("run_ticks", 2)
	assert_eq(Clock.sim.tick, tick + 2, "service advances while the guide is present")


func test_real_guest_dirty_table_and_report_state_trigger_the_service_hints() -> void:
	var main: Node = _start(false)
	_got_it(main)
	assert_true(main.call("set_menu_visible", true))
	assert_true(main.call("set_menu_visible", false))
	_got_it(main)  # Stock.
	_got_it(main)  # Build.
	_got_it(main)  # Open.
	assert_true(Clock.sim.start_service())
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, -1)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 41
	var guest: CustomerAgent = CustomerAgent.new(sim, random)
	guest.cell = sim.world.grid.entries()[0]
	guest.state = CustomerAgent.State.QUEUED
	sim.world.add_agent(guest)
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, Guide.Step.QUEUE)
	_got_it(main)
	assert_eq(_guide(main).active_hint, -1)
	for item: PlacedItem in sim.world.grid.items():
		if item.def is ItemDef and (item.def as ItemDef).category == ItemDef.Category.TABLE:
			sim.kitchen.mark_table_dirty(item.id)
			break
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, Guide.Step.DIRTY)
	_got_it(main)
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, -1, "persistent dirt does not repeat the hint")
	sim.world.remove_agent(guest)
	Clock.sim.phase = SimClock.Phase.CLOSED
	main.call("_on_service_closed", Clock.sim.day)
	assert_true((main.get_node("Overlay/EveningReport") as Control).visible)
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, Guide.Step.REPORT)
	_got_it(main)
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, -1)


func test_skip_progress_is_written_next_morning_and_survives_a_real_reload() -> void:
	var first: Node = _start()
	var morning: String = _saved_text()
	assert_true((_document()["data"] as Dictionary).has("hints"))
	_skip(first)
	assert_eq(_saved_text(), morning)
	_next_morning()
	assert_eq(int(_document()["data"]["hints"]["next_hint"]), Guide.Step.COMPLETE)
	var snapshot: Dictionary = _guide(first).capture()
	_close(first)
	var second: Node = _start()
	assert_eq(_guide(second).capture(), snapshot)
	assert_eq(_guide(second).active_hint, -1)
	assert_false(_bubble(second).visible)


func test_unfinished_guide_progress_loads_into_the_day_two_hint() -> void:
	var first: Node = _start()
	_got_it(first)
	assert_true(first.call("set_menu_visible", true))
	assert_true(first.call("set_menu_visible", false))
	first.call("refresh_hints")
	assert_eq(_guide(first).active_hint, Guide.Step.STOCK)
	_next_morning()
	assert_eq(_guide(first).active_hint, Guide.Step.DAY_TWO)
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_guide(second).active_hint, Guide.Step.DAY_TWO)
	_got_it(second)
	assert_eq(_guide(second).next_hint, Guide.Step.COMPLETE)
	second.call("refresh_hints")
	assert_false(_bubble(second).visible)


func test_older_save_without_hints_loads_complete_even_on_day_one() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	(document["data"] as Dictionary).erase("hints")
	_write_document(document)
	_remove_backup()
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.day, 1)
	assert_eq(_guide(second).next_hint, Guide.Step.COMPLETE)
	assert_eq(_guide(second).active_hint, -1)
	assert_false(_bubble(second).visible)
	_next_morning()
	assert_eq(_guide(second).active_hint, -1)


func test_settings_show_guide_again_restarts_and_saves_only_next_morning() -> void:
	var first: Node = _start()
	_skip(first)
	_next_morning()
	assert_eq(_guide(first).next_hint, Guide.Step.COMPLETE)
	var saved: String = _saved_text()
	assert_true(first.call("set_settings_visible", true))
	var settings: SettingsPanel = first.get_node("Overlay/SettingsPanel") as SettingsPanel
	var replay: Button = settings.get_node("%ShowGuideButton") as Button
	assert_true(replay.visible)
	assert_eq(replay.text, "Show guide again")
	replay.pressed.emit()
	assert_eq(_saved_text(), saved, "Settings replay never saves the shop directly")
	assert_true(first.call("set_settings_visible", false))
	first.call("refresh_hints")
	assert_eq(_guide(first).active_hint, Guide.Step.MENU)
	_next_morning()
	assert_eq(_guide(first).active_hint, Guide.Step.DAY_TWO)
	assert_ne(int(_document()["data"]["hints"]["next_hint"]), Guide.Step.COMPLETE)
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.day, 3)
	assert_eq(_guide(second).active_hint, Guide.Step.DAY_TWO,
		"the replay's morning origin survives the registered save section")


func test_start_over_route_gives_the_new_run_a_fresh_guide() -> void:
	var first: Node = _start()
	_skip(first)
	_next_morning()
	_tree().current_scene = first
	_mains.erase(first)
	first.call("start_over")
	for frame: int in 4:
		await _tree().process_frame
	var fresh: Node = _tree().current_scene
	assert_not_null(fresh)
	if fresh == null:
		return
	_mains.append(fresh)
	fresh.set("guide_for_tools", true)
	fresh.call("start")
	fresh.call("refresh_hints")
	assert_eq(Clock.sim.day, 1)
	assert_eq(_guide(fresh).active_hint, Guide.Step.MENU)
	assert_ne(_guide(fresh).next_hint, Guide.Step.COMPLETE)


func test_settings_replay_during_service_waits_for_the_next_morning() -> void:
	var main: Node = _start()
	_skip(main)
	var saved: String = _saved_text()
	assert_true(Clock.sim.start_service())
	Clock.set_speed(2)
	assert_true(main.call("set_settings_visible", true))
	var settings: SettingsPanel = main.get_node("Overlay/SettingsPanel") as SettingsPanel
	(settings.get_node("%ShowGuideButton") as Button).pressed.emit()
	assert_true(main.call("set_settings_visible", false))
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, -1, "morning planning hints wait until the shop is closed")
	assert_false(_bubble(main).visible)
	assert_eq(Clock.speed, 2)
	assert_eq(_saved_text(), saved)
	_next_morning()
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, Guide.Step.MENU)
	_close(main)
	var loaded: Node = _start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_guide(loaded).active_hint, Guide.Step.MENU)


func test_tools_and_title_backdrop_suppress_guide_until_explicitly_requested() -> void:
	var main: Node = _start(false, false)
	assert_false(_bubble(main).visible)
	main.set("guide_for_tools", true)
	main.call("refresh_hints")
	assert_eq(_guide(main).active_hint, Guide.Step.MENU)
	assert_true(_bubble(main).visible)
	_close(main)
	var backdrop: Node = MAIN.instantiate()
	backdrop.set("display_only", true)
	backdrop.set("guide_for_tools", true)
	_mains.append(backdrop)
	_tree().root.add_child(backdrop)
	backdrop.call("start")
	backdrop.call("refresh_hints")
	assert_false(_bubble(backdrop).visible)
	assert_false(backdrop.get("_started"))


func test_title_settings_hide_replay_when_no_session_owns_the_guide() -> void:
	var title: TitleScreen = (load("res://src/ui/title_screen.tscn") as PackedScene).instantiate() as TitleScreen
	_mains.append(title)
	_tree().root.add_child(title)
	title.start()
	title.settings_button.pressed.emit()
	assert_true(title.settings.visible)
	var replay: Button = title.settings.get_node("%ShowGuideButton") as Button
	assert_false(replay.visible, "title Settings has no run whose guide it could restart")
	assert_eq(SaveSystem.list_slots().size(), 0)


func test_owner_creation_keeps_the_hidden_menu_hint_fresh_until_confirmation() -> void:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	main.set("guide_for_tools", true)
	main.set("owner_creation_requested", true)
	main.set("new_game_seed_override", 1)
	_mains.append(main)
	_tree().root.add_child(main)
	main.call("start")
	assert_true(main.call("is_owner_picker_visible"))
	assert_false((main.get_node("HUD") as CanvasLayer).visible)
	main.call("refresh_hints")
	assert_eq(_guide(main).next_hint, Guide.Step.MENU,
		"temporary hidden HUD during owner creation is not an unavailable hint target")
	assert_eq(_guide(main).active_hint, -1)
	assert_false(_bubble(main).visible)
	main.call("_on_owner_appearance_confirmed", OwnerAppearance.MODELS[0], "Chef")
	main.call("refresh_hints")
	assert_false(main.call("is_owner_picker_visible"))
	assert_true((main.get_node("HUD") as CanvasLayer).visible)
	assert_eq(_guide(main).active_hint, Guide.Step.MENU)


func _start(with_saves: bool = true, guide_for_tools: bool = true) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	main.set("skip_owner_picker", true)
	main.set("new_game_seed_override", 1)
	main.set("guide_for_tools", guide_for_tools)
	_mains.append(main)
	_tree().root.add_child(main)
	main.call("start")
	main.call("refresh_hints")
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if _tree().current_scene == main:
		_tree().current_scene = null
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _guide(main: Node) -> Guide:
	return main.get("hints") as Guide


func _bubble(main: Node) -> Control:
	return main.get_node("Overlay/HintsBubble") as Control


func _got_it(main: Node) -> void:
	(_bubble(main).get_node("Bubble/Column/Actions/GotIt") as Button).pressed.emit()
	main.call("refresh_hints")


func _skip(main: Node) -> void:
	(_bubble(main).get_node("Bubble/Column/Actions/SkipGuide") as Button).pressed.emit()
	main.call("refresh_hints")


func _next_morning() -> void:
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_path())


func _document() -> Dictionary:
	return JSON.parse_string(_saved_text())


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")
