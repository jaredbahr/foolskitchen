extends TestCase
## Real morning commands/provider/panel; no full-day balance sampling.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
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
	for key: String in ["owner", "shop", "menu", "staff", "plates", "reviews"]:
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
	for key: String in ["owner", "shop", "menu", "staff", "plates", "reviews"]:
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
	assert_false((main.get_node("Overlay/StaffPanel") as StaffPanel).is_visible_in_tree(),
		"an ordinary morning does not open the Staff panel")
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


func test_completed_work_closes_growth_then_morning_applies_skill_and_requested_wage() -> void:
	var main: Node = _start()
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var cook: StaffAgent = _live_staff(main, &"starter_cook")
	assert_not_null(cook)
	if cook == null:
		return
	var original_save: String = FileAccess.get_file_as_string(_path())
	assert_true(Clock.sim.start_service())
	# The authored skill-3 cooking threshold is 110 XP at 2 XP per task.
	for _index: int in range(55):
		var task: SimTask = SimTask.new(&"cook", &"cook", "Completed meal")
		sim.world.board.post(task, sim.world.now)
		assert_true(sim.world.board.claim(task, cook.id, sim.world.now))
		sim.world.board.complete(task)
	assert_eq(_member(main, &"starter_cook").growth_state().earned_today(&"cooking"), 110)
	assert_eq(_member(main, &"starter_server").growth_state().earned_today(&"service"), 0)
	assert_eq(FileAccess.get_file_as_string(_path()), original_save)
	Clock.sim.phase = SimClock.Phase.CLOSED
	main.call("_on_service_closed", 1)
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.WAGES), -55,
		"the old wage was charged before the earned skill was applied")
	assert_eq(_member(main, &"starter_cook").skill, 4)
	assert_eq(cook.skills[&"cook"], 3, "the live shift never changes skill mid-day")
	assert_eq(cook.wage, 30)
	assert_eq(FileAccess.get_file_as_string(_path()), original_save)
	assert_true(Clock.sim.next_day())
	var next_shift_cook: StaffAgent = _live_staff(main, &"starter_cook")
	assert_not_null(next_shift_cook)
	if next_shift_cook == null:
		return
	assert_eq(next_shift_cook.skills[&"cook"], 4)
	assert_eq(next_shift_cook.wage, 30)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	assert_true(panel.is_visible_in_tree(), "the morning raise opens the Staff panel")
	var card: Control = panel.offer_row_for(&"starter_cook")
	assert_not_null(card)
	if card == null:
		return
	assert_true(card.is_visible_in_tree(), "the actual raise card is visible in the scene tree")
	assert_true((card.get_node("Message") as Label).text.contains("Alex (Cook) got better at cooking"))
	var saved_before_choice: String = FileAccess.get_file_as_string(_path())
	(card.get_node("Actions/Accept") as Button).pressed.emit()
	assert_eq(_member(main, &"starter_cook").wage, TUNING.staff_wage(&"cook", 4))
	assert_eq(_live_staff(main, &"starter_cook").wage, TUNING.staff_wage(&"cook", 4))
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.WAGES), -55)
	assert_eq(FileAccess.get_file_as_string(_path()), saved_before_choice,
		"accepting a raise never writes a new save point")
	assert_false(main.call("staff_accept_raise", &"starter_cook"))
	assert_true(Clock.sim.start_service())
	assert_false(main.call("staff_accept_raise", &"starter_cook"))
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(int(_document()["data"]["staff"]["members"][0]["wage"]), TUNING.staff_wage(&"cook", 4),
		"the accepted wage joins only the next ordinary morning save")


func test_cleanup_completed_after_service_close_is_flushed_before_morning_save() -> void:
	var main: Node = _start()
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var saved: Dictionary = _roster(main).to_dict()
	# One genuinely completed bus task will cross the authored skill-3 threshold.
	saved["members"][1]["growth"]["xp"]["service"] = 109
	var choices: StaffRoster = StaffRoster.new(TUNING)
	assert_true(choices.from_dict(saved))
	assert_true(sim.set_staff_roster(choices.members()))
	main.set("staff_roster", choices)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	panel.bind_roster(choices)
	var credit_connections: int = 0
	for connection: Dictionary in sim.world.board.get_signal_connection_list(&"task_completed"):
		var handler: Callable = connection["callable"]
		if handler.get_object() == main and handler.get_method() == &"_on_staff_task_completed":
			credit_connections += 1
	assert_eq(credit_connections, 1, "the live board has one session XP connection")
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(sim.world, &"table_2")
	assert_true(tables.size() >= 2)
	if tables.size() < 2:
		return
	var original_save: String = FileAccess.get_file_as_string(_path())
	assert_true(Clock.sim.start_service())
	sim.kitchen.mark_table_dirty(tables[0].id)
	var cleanup: SimTask = _bus_task_for(sim, tables[0].id)
	assert_not_null(cleanup)
	if cleanup == null:
		return
	Clock.sim.phase = SimClock.Phase.LAST_ORDERS
	sim.advance()
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(cleanup.state != SimTask.State.DONE,
		"the actual service_closed signal precedes completion of cleanup")
	assert_eq(_member(main, &"starter_server").growth_state().progress_xp(&"service"), 109)
	assert_eq(_member(main, &"starter_server").growth_state().pending_raise_count(), 0)
	var closing_books: Dictionary = Economy.ledger.to_dict()
	# Explicit sim driving exercises the existing cleanup API. Production Clock
	# and Main.run_ticks still stop at CLOSED; this test changes neither driver.
	for _index: int in range(500):
		sim.advance()
		if cleanup.state == SimTask.State.DONE:
			break
	assert_eq(cleanup.state, SimTask.State.DONE)
	assert_false(sim.kitchen.is_table_dirty(tables[0].id))
	assert_eq(cleanup.claimed_by, _live_staff(main, &"starter_server").id)
	sim.world.board.complete(cleanup)
	assert_eq(_member(main, &"starter_server").growth_state().earned_today(&"service"), 1,
		"the stable rostered claimant is credited once after closing")
	assert_eq(_live_staff(main, &"starter_server").skill_for(&"server"), 3)
	assert_eq(Economy.ledger.to_dict(), closing_books, "cleanup never closes the books twice")
	assert_eq(FileAccess.get_file_as_string(_path()), original_save)
	sim.kitchen.mark_table_dirty(tables[1].id)
	var unfinished: SimTask = _bus_task_for(sim, tables[1].id)
	assert_not_null(unfinished)
	if unfinished == null:
		return
	assert_true(Clock.sim.next_day())
	assert_eq(unfinished.state, SimTask.State.CANCELLED,
		"overnight tidying cancels unfinished work without granting task XP")
	assert_eq(_member(main, &"starter_server").skill, 4)
	assert_eq(_member(main, &"starter_server").growth_state().earned_today(&"service"), 0)
	assert_eq(_member(main, &"starter_server").growth_state().progress_xp(&"service"), 0)
	assert_eq(_member(main, &"starter_server").growth_state().pending_raise_count(), 1)
	assert_eq(_live_staff(main, &"starter_server").skill_for(&"server"), 4)
	var morning_staff: Dictionary = _document()["data"]["staff"]
	var server_row: Dictionary = morning_staff["members"][1]
	assert_eq(int(server_row["skill"]), 4)
	assert_eq(int(server_row["growth"]["xp"]["service"]), 0)
	assert_eq(server_row["growth"]["raises"].size(), 1)
	assert_eq(int(server_row["growth"]["raises"][0]["level"]), 4)
	assert_not_null(panel.offer_row_for(&"starter_server"))
	_close(main)
	var restored: Node = _start()
	# Compare the complete saved representation on both sides: JSON restores
	# untyped arrays/floats, while the live roster uses typed arrays/integers.
	var restored_staff: Dictionary = JSON.parse_string(JSON.stringify(_roster(restored).to_dict()))
	assert_eq(restored_staff, morning_staff)
	assert_eq(_live_staff(restored, &"starter_server").skill_for(&"server"), 4)
	restored.call("_begin_morning")
	assert_eq(_member(restored, &"starter_server").growth_state().pending_raise_count(), 1,
		"load and repeated morning setup cannot duplicate cleanup XP or its offer")
	assert_eq(_document()["data"]["staff"], morning_staff)


func test_three_rejected_requests_remove_redundant_cook_next_morning_once() -> void:
	var main: Node = _start()
	_install_queued_raises(main, true)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var original_save: String = FileAccess.get_file_as_string(_path())
	var departing: StaffAgent = _live_staff(main, &"starter_cook")
	assert_not_null(departing)
	if departing == null:
		return
	for mood_after: int in [2, 1, 0]:
		var card: Control = panel.offer_row_for(&"starter_cook")
		assert_not_null(card)
		if card == null:
			return
		(card.get_node("Actions/NotNow") as Button).pressed.emit()
		assert_eq(_member(main, &"starter_cook").growth_state().mood, mood_after)
	assert_null(panel.offer_row_for(&"starter_cook"))
	assert_eq(FileAccess.get_file_as_string(_path()), original_save)
	assert_eq(_roster(main).members().size(), 3, "the cook stays until the next morning")
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(_roster(main).members().size(), 2)
	assert_null((main.get("world") as SimWorld).agent(departing.id))
	var notices: VBoxContainer = panel.get_node("Panel/Content/Scroll/List/MorningNotices") as VBoxContainer
	assert_true(panel.is_visible_in_tree(), "a departure opens the morning Staff panel")
	assert_true(notices.is_visible_in_tree(), "the departure notice is visible to the player")
	assert_eq(notices.get_child_count(), 1)
	if notices.get_child_count() == 0:
		return
	assert_true((notices.get_child(0) as Label).is_visible_in_tree())
	assert_eq((notices.get_child(0) as Label).text,
		"Alex left after their raise requests were refused.")
	assert_eq(_document()["data"]["staff"]["members"].size(), 2)
	main.call("_begin_morning")
	assert_eq(_roster(main).members().size(), 2)
	assert_true(notices.visible, "repeating setup keeps the morning notice without another departure")
	assert_eq(notices.get_child_count(), 1)


func test_last_cook_stays_at_mood_one_with_readable_morning_notice() -> void:
	var main: Node = _start(false)
	_install_queued_raises(main, false)
	for _index: int in range(3):
		assert_true(main.call("staff_decline_raise", &"starter_cook"))
	assert_eq(_member(main, &"starter_cook").growth_state().mood, 0)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(_roster(main).members().size(), 2)
	assert_not_null(_live_staff(main, &"starter_cook"))
	assert_eq(_member(main, &"starter_cook").growth_state().mood, 1)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var notices: VBoxContainer = panel.get_node("Panel/Content/Scroll/List/MorningNotices") as VBoxContainer
	assert_true(panel.is_visible_in_tree(), "a protected worker's notice opens the Staff panel")
	assert_true(notices.is_visible_in_tree())
	assert_eq(notices.get_child_count(), 1)
	if notices.get_child_count() == 0:
		return
	assert_eq((notices.get_child(0) as Label).text, "Alex stayed to keep the kitchen running.")
	assert_false((notices.get_child(0) as Label).text.contains("starter_cook"))
	main.call("_begin_morning")
	assert_eq(notices.get_child_count(), 1)


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


func _member(main: Node, id: StringName) -> StaffMember:
	for member: StaffMember in _roster(main).members():
		if member.id == id:
			return member
	return null


func _live_staff(main: Node, id: StringName) -> StaffAgent:
	for agent: SimAgent in (main.get("world") as SimWorld).agents:
		if agent is StaffAgent and not agent is OwnerAgent \
				and (agent as StaffAgent).member_id == id:
			return agent as StaffAgent
	return null


func _bus_task_for(sim: RestaurantSim, table_id: int) -> SimTask:
	for task: SimTask in sim.world.board.open_tasks():
		if task.kind == &"bus_table" and int(task.payload.get("table_item_id", 0)) == table_id:
			return task
	return null


func _install_queued_raises(main: Node, extra_cook: bool) -> void:
	var saved: Dictionary = _roster(main).to_dict()
	if extra_cook:
		var backup: Dictionary = saved["members"][0].duplicate(true)
		backup["id"] = "backup_cook"
		backup["name"] = "Robin Backup"
		saved["members"].append(backup)
	var cook: Dictionary = saved["members"][0]
	cook["skill"] = 5
	cook["wage"] = TUNING.staff_wage(&"cook", 1)
	cook["growth"]["skills"]["cooking"] = 5
	cook["growth"]["wage"] = cook["wage"]
	cook["growth"]["raises"] = [
		{"skill": "cooking", "level": 2},
		{"skill": "cooking", "level": 3},
		{"skill": "cooking", "level": 4},
		{"skill": "cooking", "level": 5}]
	var choices: StaffRoster = StaffRoster.new(TUNING)
	assert_true(choices.from_dict(saved))
	assert_true((main.get("sim") as RestaurantSim).set_staff_roster(choices.members()))
	main.set("staff_roster", choices)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	panel.bind_roster(choices)
	var notices: Array[Dictionary] = []
	panel.set_morning(Clock.sim.day, notices)


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
