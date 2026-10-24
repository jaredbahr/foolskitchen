extends TestCase
## Player routing and normal MORNING checkpoints; no OPEN state snapshots.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "owner_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "owner_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	for key: String in ["owner", "shop", "menu"]:
		if SaveSystem._providers.has(key):
			_old_providers[key] = SaveSystem._providers[key].duplicate()


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	# Restore the previously registered session providers after this fixture.
	for key: String in ["owner", "shop", "menu"]:
		if _old_providers.has(key):
			var provider: Dictionary = _old_providers[key]
			SaveSystem.register(key, provider["capture"], provider["restore"])
		else:
			SaveSystem._providers.erase(key)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_hotkeys_and_buttons_share_selected_owner_command_and_keep_selection() -> void:
	var main: Node = _start(false)
	var owner: OwnerAgent = _owner(main)
	assert_false(main.call("assign_owner_mode", &"kitchen"))
	_key(main, KEY_K)
	assert_eq(owner.current_mode(), &"rest")
	assert_true(main.call("select_agent", owner.id))
	var keys: Array[Key] = [KEY_K, KEY_F, KEY_H, KEY_R]
	for i: int in keys.size():
		_key(main, keys[i])
		assert_eq(owner.current_mode(), OwnerAgent.MODES[i])
		_assert_selected(main, owner)
	_key(main, KEY_K, true)
	_key(main, KEY_K, false, false)
	assert_eq(owner.current_mode(), &"rest", "echo/release do not issue commands")
	var panel: InspectPanel = main.get_node("Overlay/InspectPanel") as InspectPanel
	(panel.get_node("Panel/Rows/OwnerModes/Kitchen") as Button).pressed.emit()
	assert_eq(owner.current_mode(), &"kitchen")
	_assert_selected(main, owner)
	assert_false(main.call("assign_owner_mode", &"invalid"))
	assert_eq(owner.current_mode(), &"kitchen")
	main.call("clear_selection")
	panel.owner_mode_requested.emit(&"floor")
	assert_eq(owner.current_mode(), &"kitchen", "stale UI requests still pass the selected-owner guard")


func test_owner_assignment_precedes_nearby_agent_and_item_inspection() -> void:
	var main: Node = _start(false)
	var owner: OwnerAgent = _owner(main)
	var world: SimWorld = main.get("world")
	var prep: PlacedItem = _item(main, &"prep_counter")
	# This edge of the real counter lies within Picker's normal cook radius.
	var point: Vector3 = GridMath.cell_to_world(prep.origin + Vector2i(1, 0)) + Vector3(0.2, 0, 0.2)
	var positions: Dictionary = (main.get_node("ShopView") as ShopView).drawn_agent_positions()
	var nearest: int = Picker.pick_agent(point, positions)
	assert_true(nearest >= 0, "the normal picker would find nearby staff first")
	if nearest < 0:
		return
	assert_eq(world.agent(nearest).role, &"cook")
	assert_true(main.call("select_agent", owner.id))
	main.call("select_at_world_position", point)
	assert_eq(owner.current_mode(), &"kitchen")
	_assert_selected(main, owner)
	var pass_item: PlacedItem = _item(main, &"pass_counter")
	assert_null(world.grid.item_at(pass_item.work_cells[1]), "the dining work cell lies outside the footprint")
	main.call("select_at_world_position", GridMath.cell_to_world(pass_item.work_cells[1]))
	assert_eq(owner.current_mode(), &"floor")
	_assert_selected(main, owner)
	main.call("select_at_world_position", GridMath.cell_to_world(_item(main, &"fridge").origin))
	assert_eq(owner.current_mode(), &"kitchen")
	_assert_selected(main, owner)
	main.call("select_at_world_position", GridMath.cell_to_world(_item(main, &"table_2").origin))
	assert_eq(owner.current_mode(), &"floor")
	_assert_selected(main, owner)


func test_other_selections_keep_ordinary_item_and_agent_inspection() -> void:
	var main: Node = _start(false)
	var owner: OwnerAgent = _owner(main)
	var world: SimWorld = main.get("world")
	assert_true(main.call("select_agent", world.agents[0].id))
	main.call("select_at_world_position", GridMath.cell_to_world(_item(main, &"fridge").origin))
	var state: Dictionary = main.call("inspection_state")
	assert_eq(state["selected_item_id"], _item(main, &"fridge").id)
	assert_eq(owner.current_mode(), &"rest")
	assert_true(main.call("select_agent", owner.id))
	main.call("select_at_world_position", GridMath.cell_to_world(_item(main, &"potted_plant").origin))
	state = main.call("inspection_state")
	assert_eq(state["selected_item_id"], _item(main, &"potted_plant").id)
	assert_eq(state["selected_agent_id"], -1)
	_key(main, KEY_K)
	assert_eq(owner.current_mode(), &"rest")


func test_owner_menu_and_shop_changes_restore_after_next_morning() -> void:
	var first: Node = _start(true)
	var morning_file: String = FileAccess.get_file_as_string(_path())
	assert_true(first.call("shop_move", _item(first, &"potted_plant").id, Vector2i(11, 9), 1))
	assert_true(first.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(first.call("menu_set_price", &"burger", 15))
	var saved_menu: Dictionary = (first.get("menu_settings") as MenuSettings).to_dict()
	assert_true(first.call("select_agent", _owner(first).id))
	assert_true(first.call("assign_owner_mode", &"help"))
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file, "commands leave the current morning checkpoint intact")
	_run_day(first)
	assert_true(Clock.sim.next_day())
	assert_eq(_document()["data"]["owner"], {"mode": "help"})
	var snapshot: Dictionary = (first.get("shop_editor") as ShopEditor).to_dict()
	var cash: int = Economy.cash
	_close(first)
	var second: Node = _start(true)
	assert_eq(Clock.sim.day, 2)
	assert_eq(_owner(second).current_mode(), &"help")
	assert_eq((second.get("shop_editor") as ShopEditor).to_dict(), snapshot)
	assert_eq((second.get("menu_settings") as MenuSettings).to_dict(), saved_menu)
	assert_eq((second.get("sim") as RestaurantSim).price_of((second.get("content") as ContentDB).recipe(&"burger")), 15)
	assert_eq(Economy.cash, cash)
	assert_eq(_owner(second).home_cell(), (second.get("sim") as RestaurantSim).staff_spawns[&"owner"])


func test_missing_owner_section_defaults_to_rest() -> void:
	var first: Node = _start(true)
	assert_true(first.call("select_agent", _owner(first).id))
	assert_true(first.call("assign_owner_mode", &"kitchen"))
	var document: Dictionary = _document()
	document["data"].erase("owner")
	_write(document)
	_close(first)
	var second: Node = _start(true)
	assert_eq(_owner(second).current_mode(), &"rest")
	assert_eq(_document()["data"]["owner"], {"mode": "rest"})


func test_bad_owner_data_starts_fresh_and_commands_leave_failed_slot_untouched() -> void:
	var first: Node = _start(true)
	var document: Dictionary = _document()
	document["data"]["owner"] = {"mode": "invalid"}
	document["data"]["clock"]["day"] = 9
	_write(document)
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start(true)
	assert_eq(Clock.sim.day, 1)
	assert_eq(_owner(second).current_mode(), &"rest")
	assert_eq(FileAccess.get_file_as_string(_path()), broken)
	assert_true(second.call("select_agent", _owner(second).id))
	assert_true(second.call("assign_owner_mode", &"help"))
	assert_eq(FileAccess.get_file_as_string(_path()), broken, "a mode hotkey cannot overwrite the protected failed load")
	_run_day(second)
	assert_true(Clock.sim.next_day())
	assert_eq(_document()["data"]["owner"], {"mode": "help"})


func test_commands_leave_current_checkpoint_intact_then_next_morning_reloads_mode() -> void:
	var main: Node = _start(true)
	assert_true(main.call("select_agent", _owner(main).id))
	var before: String = FileAccess.get_file_as_string(_path())
	_key(main, KEY_F)
	assert_eq(_owner(main).current_mode(), &"floor")
	assert_eq(FileAccess.get_file_as_string(_path()), before)
	assert_true(Clock.sim.start_service())
	_key(main, KEY_K)
	assert_eq(FileAccess.get_file_as_string(_path()), before)
	main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	_key(main, KEY_H)
	assert_eq(_owner(main).current_mode(), &"help")
	assert_eq(FileAccess.get_file_as_string(_path()), before, "no unsupported OPEN/CLOSED snapshot is written")
	assert_true(Clock.sim.next_day())
	assert_eq(_document()["data"]["owner"], {"mode": "help"})
	assert_eq(int(_document()["data"]["clock"]["phase"]), int(SimClock.Phase.MORNING))
	assert_eq(_owner(main).current_mode(), &"help")
	_close(main)
	var resumed: Node = _start(true)
	assert_eq(Clock.sim.day, 2)
	assert_eq(_owner(resumed).current_mode(), &"help")


func test_owner_adds_zero_wages_with_normal_cook_and_server_charges_preserved() -> void:
	var main: Node = _start(false)
	assert_false(TUNING.wages.has(&"owner"))
	assert_true(main.call("select_agent", _owner(main).id))
	assert_true(main.call("assign_owner_mode", &"kitchen"))
	var before: int = Economy.cash
	main.call("_charge_closing_costs")
	var wages: int = TUNING.wages[&"cook"] + TUNING.wages[&"server"]
	assert_eq(Economy.cash, before - wages - TUNING.daily_rent)
	assert_eq(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.WAGES), -wages)
	assert_eq((main.call("build_report", Clock.sim.day) as DayReport).costs.get(Ledger.WAGES), wages)


func test_inspection_reports_actual_selected_owner_cooking_task() -> void:
	var main: Node = _start(false)
	var owner: OwnerAgent = _owner(main)
	assert_true(main.call("select_agent", owner.id))
	assert_true(main.call("assign_owner_mode", &"kitchen"))
	assert_true(Clock.sim.start_service())
	for tick: int in 900:
		main.call("run_ticks", 1)
		if owner.task != null and owner.task.role == &"cook":
			break
	assert_not_null(owner.task, "the real kitchen posts cooking work for the factory owner")
	if owner.task == null:
		return
	var state: Dictionary = main.call("inspection_state")
	_assert_selected(main, owner)
	assert_eq(state["selected_task_id"], owner.task.id)
	assert_eq(state["selected_task_role"], "cook")
	assert_eq(state["selected_task_label"], owner.task.label)
	assert_eq(state["selected_task_state"], int(SimTask.State.CLAIMED))
	assert_eq(state["selected_task_claimant"], owner.id)
	assert_eq(state["selected_task_step"], owner.step_index)
	assert_eq(state["world_tick"], (main.get("world") as SimWorld).now)


func _start(with_saves: bool) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
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


func _owner(main: Node) -> OwnerAgent:
	return (main.get("sim") as RestaurantSim).owner_agent()


func _item(main: Node, id: StringName) -> PlacedItem:
	return ShopBuilder.items_with_def(main.get("world"), id)[0]


func _assert_selected(main: Node, owner: OwnerAgent) -> void:
	var state: Dictionary = main.call("inspection_state")
	assert_eq(state["selected_agent_id"], owner.id)
	assert_eq(state["selected_item_id"], -1)
	assert_eq(state["selected_role"], "owner")
	assert_eq(state["panel_visible"], true)
	assert_eq(state["owner_mode"], String(owner.current_mode()))


func _key(main: Node, code: Key, echo: bool = false, pressed: bool = true) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.echo = echo
	event.pressed = pressed
	main.call("_unhandled_input", event)


func _run_day(main: Node) -> void:
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		assert_eq(DirAccess.remove_absolute(_path() + ".bak"), OK)
