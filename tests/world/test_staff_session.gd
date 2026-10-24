extends TestCase
## Real morning commands/provider/panel; no full-day balance sampling.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "staff_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}
var _viewport: SubViewport


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "staff_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)
	for key: String in ["owner", "shop", "menu", "staff", "plates"]:
		if SaveSystem._providers.has(key):
			_old_providers[key] = SaveSystem._providers[key].duplicate()


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	for key: String in ["owner", "shop", "menu", "staff", "plates"]:
		if _old_providers.has(key):
			var provider: Dictionary = _old_providers[key]
			SaveSystem.register(key, provider["capture"], provider["restore"])
		else:
			SaveSystem._providers.erase(key)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_hire_and_let_go_change_real_agents_and_closing_wages_without_saving() -> void:
	var main: Node = _start()
	var sim: RestaurantSim = main.get("sim")
	var owner: OwnerAgent = sim.owner_agent()
	assert_true(sim.assign_owner(&"floor"))
	var candidate: StaffMember = _roster(main).candidates()[0]
	var original: String = FileAccess.get_file_as_string(_path())
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var customers_rng: int = GameState.rng(&"customers").state
	var hiring_rng: int = GameState.rng(&"hiring").state
	assert_true(main.call("staff_hire", candidate.id))
	assert_eq(sim.world.agents.size(), 4)
	assert_true(sim.owner_agent() == owner)
	assert_eq(owner.current_mode(), &"floor")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.rng(&"customers").state, customers_rng)
	assert_eq(GameState.rng(&"hiring").state, hiring_rng)
	assert_eq(FileAccess.get_file_as_string(_path()), original)
	main.call("_charge_closing_costs")
	assert_eq(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.WAGES), -55 - candidate.wage)
	assert_true(main.call("staff_let_go", candidate.id))
	assert_eq(sim.world.agents.size(), 3)
	assert_eq(_roster(main).total_wages(), 55)
	assert_eq(FileAccess.get_file_as_string(_path()), original)
	Economy.ledger = Ledger.new()
	main.call("_charge_closing_costs")
	assert_eq(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.WAGES), -55)
	assert_true(sim.owner_agent() == owner)


func test_role_minimums_and_service_phase_reject_requests_and_hide_panel() -> void:
	var previous_clock: SimClock = Clock.sim
	var previous_phase: int = previous_clock.phase
	previous_clock.phase = SimClock.Phase.OPEN
	var main: Node = _start(false)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var available: StaffMember = _roster(main).candidates()[0]
	assert_false((panel.row_for(available.id).get_node("Top/Action") as Button).disabled,
		"new-game morning replaces the phase bound before Clock reset")
	for member: StaffMember in _roster(main).members():
		assert_false(main.call("staff_let_go", member.id))
	assert_true(main.call("set_staff_visible", true))
	var candidate: StaffMember = _roster(main).candidates()[0]
	var before: Dictionary = _roster(main).to_dict()
	Clock.sim.start_service()
	assert_false(main.call("is_staff_visible"))
	assert_true((main.get_node("HUD/Top/Row/Staff") as Button).disabled)
	assert_false(main.call("staff_hire", candidate.id))
	assert_false(main.call("staff_let_go", &"starter_cook"))
	assert_false(main.call("set_staff_visible", true))
	assert_eq(_roster(main).to_dict(), before)
	_close(main)
	previous_clock.phase = previous_phase


func test_firing_selected_employee_removes_paused_mesh_inspection_and_ring() -> void:
	var main: Node = _start(false)
	var candidate: StaffMember = _roster(main).candidates()[0]
	assert_true(main.call("staff_hire", candidate.id))
	var sim: RestaurantSim = main.get("sim")
	var hired: StaffAgent = null
	for agent: SimAgent in sim.world.agents:
		if agent is StaffAgent and (agent as StaffAgent).member_id == candidate.id:
			hired = agent as StaffAgent
	assert_not_null(hired)
	if hired == null:
		return
	var view: ShopView = main.get_node("ShopView") as ShopView
	view.call("_process", 0.0)
	assert_true(view.agent_nodes.has(hired.id))
	assert_true(main.call("select_agent", hired.id))
	assert_true((main.get_node("DebugGeometry/SelectionRing") as MeshInstance3D).visible)
	assert_true(main.call("staff_let_go", candidate.id))
	view.call("_process", 0.0)
	assert_false(view.agent_nodes.has(hired.id))
	assert_null(sim.world.agent(hired.id))
	var inspector: InspectPanel = main.get_node("Overlay/InspectPanel") as InspectPanel
	assert_eq(inspector.selected_agent_id, -1)
	assert_false(inspector.visible)
	assert_false((main.get_node("DebugGeometry/SelectionRing") as MeshInstance3D).visible)
	assert_eq(sim.world.now, 0, "paused staffing needs no service tick")


func test_next_morning_persists_roster_and_pool_reload_draws_no_hiring_rng() -> void:
	var first: Node = _start()
	assert_true(first.call("staff_hire", _roster(first).candidates()[0].id))
	assert_true((first.get("sim") as RestaurantSim).kitchen.configure_plates(5))
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(_roster(first).candidates().size(), 3)
	var saved: Dictionary = _roster(first).to_dict()
	var rng_state: int = GameState.rng(&"hiring").state
	assert_eq(_document()["data"]["staff"], JSON.parse_string(JSON.stringify(saved)))
	assert_eq(_document()["data"]["plates"], {"version": 1.0, "total": 5.0})
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_roster(second).to_dict(), saved)
	assert_eq(GameState.rng(&"hiring").state, rng_state)
	assert_eq((second.get("world") as SimWorld).agents.size(), 4)
	assert_eq((second.get("sim") as RestaurantSim).kitchen.plates.total, 5,
		"the same successful world rebuild installs both staff and plate providers")
	second.call("_begin_morning")
	assert_eq(GameState.rng(&"hiring").state, rng_state)
	assert_eq(_roster(second).to_dict(), saved)


func test_depleted_pool_and_custom_roster_restore_without_a_shop_section() -> void:
	var first: Node = _start()
	assert_true(first.call("staff_hire", _roster(first).candidates()[0].id))
	var choices: Dictionary = _roster(first).to_dict()
	var rng_state: int = GameState.rng(&"hiring").state
	var document: Dictionary = _document()
	document["data"]["staff"] = choices
	document["data"].erase("shop")
	_write(document)
	_close(first)
	var second: Node = _start()
	assert_eq(_roster(second).to_dict(), choices)
	assert_eq(_roster(second).candidates().size(), 2)
	assert_eq(GameState.rng(&"hiring").state, rng_state)
	assert_eq((second.get("world") as SimWorld).agents.size(), 4)


func test_old_save_without_staff_gets_default_roster_and_three_candidates() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	document["data"].erase("staff")
	_write(document)
	_close(first)
	var second: Node = _start()
	assert_eq(_roster(second).members().size(), 2)
	assert_eq(_roster(second).total_wages(), 55)
	assert_eq(_roster(second).candidates().size(), 3)
	assert_eq((second.get("world") as SimWorld).agents.size(), 3)
	for member: StaffMember in _roster(second).members():
		assert_eq(member.skill, 3)
		assert_eq(member.trait_id, &"steady")


func test_bad_staff_section_starts_fresh_and_preserves_rejected_file() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	document["data"]["staff"]["members"][0]["skill"] = 0
	_write(document)
	var rejected: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	assert_eq(_roster(second).members().size(), 2)
	assert_eq(_roster(second).total_wages(), 55)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(FileAccess.get_file_as_string(_path()), rejected)


func test_native_staff_controls_survive_refresh_and_fit_web_and_capture_widths() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	var main: Node = _start(false, _viewport)
	main.set_process(false)
	(main.get_node("CameraRig") as CameraRig).set_process(false)
	(main.get_node("ShopView") as ShopView).set_process(false)
	Clock.set_speed(0)
	await _frames(4)
	var button: Button = main.get_node("HUD/Top/Row/Staff") as Button
	var occupied: Array[Rect2] = []
	var hud_bounds: Rect2 = _viewport.get_visible_rect().grow(-12.0)
	for child: Node in main.get_node("HUD/Top/Row").get_children():
		var control: Control = child as Control
		if not control.visible:
			continue
		var rect: Rect2 = control.get_global_rect()
		assert_true(hud_bounds.encloses(rect), "all native HUD controls stay within the viewport margins")
		var minimum: Vector2 = control.get_combined_minimum_size()
		assert_true(rect.size.x >= minimum.x - 0.5 and rect.size.y >= minimum.y - 0.5,
			"wrapped controls keep their full native content")
		for previous: Rect2 in occupied:
			assert_false(rect.intersects(previous), "native HUD controls do not overlap across or within rows")
		assert_true(rect.end.x <= 1280.0, "all native HUD controls stay inside Web width")
		occupied.append(rect)
	var point: Vector2 = button.get_global_rect().get_center()
	_mouse(point, true)
	main.get_node("HUD").call("refresh")
	await _frames(1)
	_mouse(point, false)
	assert_true(main.call("is_staff_visible"))
	await _frames(3)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var candidate: StaffMember = _roster(main).candidates()[0]
	var hire: Button = panel.row_for(candidate.id).get_node("Top/Action") as Button
	var identity: int = hire.get_instance_id()
	point = hire.get_global_rect().get_center()
	_mouse(point, true)
	panel.refresh()
	main.call("refresh_presentation")
	await _frames(1)
	assert_eq(panel.row_for(candidate.id).get_node("Top/Action").get_instance_id(), identity)
	_mouse(point, false)
	assert_eq(_roster(main).members().size(), 3)
	assert_eq(_roster(main).candidates().size(), 2)
	_viewport.size = Vector2i(1600, 900)
	await _frames(4)
	var bounds: Rect2 = (panel.get_node("Panel") as Control).get_global_rect()
	assert_true(Rect2(0.0, 0.0, 1600.0, 900.0).encloses(bounds))
	assert_true(panel.visible)
	var before_close: Dictionary = _roster(main).to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var hiring_state: int = GameState.rng(&"hiring").state
	var close_button: Button = panel.get_node("Panel/Content/Close") as Button
	point = close_button.get_global_rect().get_center()
	_mouse(point, true)
	panel.refresh()
	await _frames(1)
	_mouse(point, false)
	assert_false(main.call("is_staff_visible"))
	assert_eq(_roster(main).to_dict(), before_close)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(GameState.rng(&"hiring").state, hiring_state)
	assert_eq((main.get("world") as SimWorld).now, 0)


func _start(saves: bool = true, host: Node = null) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	_mains.append(main)
	var parent: Node = host if host != null else (Engine.get_main_loop() as SceneTree).root
	parent.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	main.get_parent().remove_child(main)
	main.free()


func _roster(main: Node) -> StaffRoster:
	return main.get("staff_roster") as StaffRoster


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")


func _frames(count: int) -> void:
	for index: int in range(count):
		await (Engine.get_main_loop() as SceneTree).process_frame


func _mouse(point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_viewport.push_input(event, true)
