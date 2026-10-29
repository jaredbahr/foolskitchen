extends TestCase
## Native session contracts for presentation choices and the existing checkpoint.

const SLOT: String = "owner_character"
var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_providers = SaveSystem._providers.duplicate(true)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	GameState.new_run(1)
	Economy.reset(0)


func test_tools_and_headless_defaults_skip_creation_and_keep_the_old_model() -> void:
	var main: Node = _start(false)
	assert_false(main.call("is_owner_picker_visible"))
	var appearance: OwnerAppearance = main.get("owner_appearance") as OwnerAppearance
	assert_eq(appearance.to_dict(), {"model": "character-male-a", "name": "You"})
	assert_false(GameState._rngs.has(&"owner_appearance"))
	var view: ShopView = main.get_node("ShopView") as ShopView
	view.call("_sync_agents")
	var owner: OwnerAgent = (main.get("sim") as RestaurantSim).owner_agent()
	assert_eq((view.agent_nodes[owner.id] as PersonView).model_name(), OwnerAppearance.DEFAULT_MODEL)
	assert_eq(main.get_node("HUD").get("visible"), true)


func test_new_run_choice_joins_the_first_existing_morning_autosave() -> void:
	var main: Node = _start(true, true)
	assert_true(main.call("is_owner_picker_visible"))
	assert_false(FileAccess.file_exists(_path()), "creation must precede the initial checkpoint")
	var picker: OwnerPicker = main.get("_owner_picker") as OwnerPicker
	assert_true(picker.choose(&"character-female-e"))
	(picker.get_node("%OwnerName") as LineEdit).text = "  Morgan  "
	picker.call("_on_confirm")
	assert_false(main.call("is_owner_picker_visible"))
	assert_true(FileAccess.file_exists(_path()))
	assert_eq(_document()["data"]["owner"]["appearance"], {"model": "character-female-e", "name": "Morgan"})
	_close(main)
	var resumed: Node = _start(true)
	assert_false(resumed.call("is_owner_picker_visible"), "Continue does not reopen the creation picker")
	assert_eq((resumed.get("owner_appearance") as OwnerAppearance).display_name, "Morgan")
	assert_eq((resumed.get("owner_appearance") as OwnerAppearance).model, &"character-female-e")


func test_morning_look_changes_are_free_do_not_save_and_update_shop_and_inspect() -> void:
	var main: Node = _start(true)
	var saved: String = FileAccess.get_file_as_string(_path())
	var books: Dictionary = Economy._capture_save()
	var rng: Dictionary = GameState._capture_save()
	var clock: Dictionary = Clock.sim.to_dict()
	var original_name: String = (main.get("sim") as RestaurantSim).owner_agent().display_name
	assert_true(main.call("owner_set_appearance", &"character-male-f", "Avery"))
	assert_eq(Economy._capture_save(), books)
	assert_eq(GameState._capture_save(), rng)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(FileAccess.get_file_as_string(_path()), saved, "a look change is never a new save point")
	var view: ShopView = main.get_node("ShopView") as ShopView
	view.call("_sync_agents")
	var owner: OwnerAgent = (main.get("sim") as RestaurantSim).owner_agent()
	assert_eq((view.agent_nodes[owner.id] as PersonView).model_name(), &"character-male-f")
	assert_eq(owner.display_name, original_name, "presentation never rewrites the sim agent")
	assert_true(main.call("select_agent", owner.id))
	var panel: InspectPanel = main.get_node("Overlay/InspectPanel") as InspectPanel
	assert_eq(panel.owner_portrait_model(), &"character-male-f")
	assert_true((panel.get_node("Panel/Rows/Title") as Label).text.begins_with("Avery (Owner"))
	var portrait: OwnerCharacterPreview = panel.get_node("Panel/Rows/OwnerPortrait") as OwnerCharacterPreview
	assert_eq(portrait.models(), [&"character-male-f"] as Array[StringName])
	main.call("_begin_morning")
	assert_eq(_document()["data"]["owner"]["appearance"], {"model": "character-male-f", "name": "Avery"})
	_close(main)
	var resumed: Node = _start(true)
	assert_eq((resumed.get("owner_appearance") as OwnerAppearance).model, &"character-male-f")


func test_legacy_owner_section_defaults_without_losing_mode_or_progress() -> void:
	var first: Node = _start(true)
	var document: Dictionary = _document()
	document["data"]["owner"].erase("appearance")
	document["data"]["owner"]["mode"] = "kitchen"
	var progress: Dictionary = document["data"]["owner"]["progress"].duplicate(true)
	_write(document)
	_close(first)
	var resumed: Node = _start(true)
	var appearance: OwnerAppearance = resumed.get("owner_appearance") as OwnerAppearance
	assert_eq(appearance.to_dict(), {"model": "character-male-a", "name": "You"})
	assert_eq((resumed.get("sim") as RestaurantSim).owner_agent().current_mode(), &"kitchen")
	var restored_progress: OwnerProgress = OwnerProgress.new(preload("res://data/balance/progression.tres"))
	assert_true(restored_progress.from_dict(progress))
	assert_eq((resumed.get("owner_progress") as OwnerProgress).to_dict(), restored_progress.to_dict())


func test_staff_action_only_opens_in_the_morning_and_cancel_keeps_the_choice() -> void:
	var main: Node = _start(false)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	(panel.get_node("%OwnerLook") as Button).pressed.emit()
	assert_true(main.call("is_owner_picker_visible"))
	var picker: OwnerPicker = main.get("_owner_picker") as OwnerPicker
	picker.choose(&"character-female-a")
	picker.call("_on_cancel")
	assert_false(main.call("is_owner_picker_visible"))
	assert_eq((main.get("owner_appearance") as OwnerAppearance).model, OwnerAppearance.DEFAULT_MODEL)
	assert_true(Clock.sim.start_service())
	panel.set_phase(Clock.sim.phase)
	assert_true((panel.get_node("%OwnerLook") as Button).disabled)
	assert_false(main.call("show_owner_picker"))
	assert_false(main.call("owner_set_appearance", &"character-male-c", "Changed"))


func test_random_is_explicit_and_uses_no_service_random_stream() -> void:
	var main: Node = _start(false)
	var before: Dictionary = GameState._capture_save()
	assert_true(main.call("show_owner_picker"))
	assert_eq(GameState._capture_save(), before, "opening or selecting a model draws nothing")
	var picker: OwnerPicker = main.get("_owner_picker") as OwnerPicker
	picker.choose(&"character-female-f")
	assert_eq(GameState._capture_save(), before)
	picker.call("_on_random")
	assert_true(GameState._rngs.has(&"owner_appearance"))
	var after: Dictionary = GameState._capture_save()
	(after["rngs"] as Dictionary).erase("owner_appearance")
	assert_eq(after, before, "only the presentation stream changed")
	assert_true(OwnerAppearance.valid_model(picker.selected_model))
	assert_eq((main.get("owner_appearance") as OwnerAppearance).model, OwnerAppearance.DEFAULT_MODEL)


func test_bad_saved_appearance_is_transactional_for_the_existing_owner_section() -> void:
	var main: Node = _start(false)
	assert_true(main.call("owner_set_appearance", &"character-female-d", "Riley"))
	var before: Dictionary = main.call("_capture_owner")
	var bad: Dictionary = before.duplicate(true)
	bad["appearance"]["model"] = "not-a-character"
	assert_false(main.call("_restore_owner", bad))
	assert_eq(main.call("_capture_owner"), before)


func test_long_owner_name_keeps_one_inspector_heading_line_and_full_hover_text() -> void:
	var main: Node = _start(false)
	var name: String = "A very very very long owner name"
	assert_true(main.call("owner_set_appearance", &"character-female-e", name))
	assert_true(main.call("select_agent", (main.get("sim") as RestaurantSim).owner_agent().id))
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	var title: Label = main.get_node("Overlay/InspectPanel/Panel/Rows/Title") as Label
	assert_eq(title.get_line_count(), 1, "long names must not push the owner portrait up into the HUD")
	assert_eq(title.tooltip_text, title.text, "the complete owner name remains available")
	assert_eq(title.mouse_filter, Control.MOUSE_FILTER_PASS, "the tooltip must accept hover")
	assert_eq((main.get("owner_appearance") as OwnerAppearance).display_name, name)


func _start(with_saves: bool, creating: bool = false) -> Node:
	var main: Node = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 1)
	main.set("owner_creation_requested", creating)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
