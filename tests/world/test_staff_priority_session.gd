extends TestCase
## Real Main/UI command, current work and normal morning save boundaries.
## Preference and save paths remain private; this is not a balance probe.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "staff_priority_session"
const MAX_TASK_TICKS: int = 500 # Existing real bussing fixture's ceiling.

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}
var _preferences: SettingsPreferences
var _old_preferences: Dictionary = {}
var _old_window_scale: float = 1.0
var _old_window_mode: Window.Mode = Window.MODE_WINDOWED
var _old_window_size: Vector2i = Vector2i.ZERO


func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "staff_priority_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers = SaveSystem._providers.duplicate()
	_preferences = tree.root.get_node("Preferences") as SettingsPreferences
	_old_preferences.clear()
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save", "ui_scale_percent",
			"default_open_speed", "fullscreen_enabled", "edge_pan_enabled"]:
		_old_preferences[key] = _preferences.get(key)
	_old_window_scale = tree.root.content_scale_factor
	_old_window_mode = tree.root.mode
	_old_window_size = tree.root.size
	_preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	_preferences.set("_disk_enabled", false)
	_preferences.set("_pending_volume_save", false)
	_preferences.ui_scale_percent = 100
	_preferences.default_open_speed = 1
	_preferences.fullscreen_enabled = false
	_preferences.edge_pan_enabled = false
	Clock.set_speed(0)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	for key: String in _old_preferences:
		_preferences.set(key, _old_preferences[key])
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	if window.mode != _old_window_mode:
		window.mode = _old_window_mode
	if window.size != _old_window_size:
		window.size = _old_window_size
	window.content_scale_factor = _old_window_scale
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_native_requests_work_in_real_phases_and_save_only_next_morning_then_reload() -> void:
	var main: Node = await _start()
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	assert_true(panel.has_signal("job_priority_requested"), "requires the actual typed StaffPanel signal")
	main.call("start")
	main.call("start")
	assert_eq(panel.get_signal_connection_list("job_priority_requested").size(), 1)
	var server: StaffAgent = _employee(main, &"starter_server")
	var owner: OwnerAgent = (main.get("sim") as RestaurantSim).owner_agent()
	var original_file: String = _saved_text()
	var rng_before: Dictionary = GameState._capture_save()
	var books_before: Dictionary = Economy.ledger.to_dict()
	assert_true(main.call("set_staff_visible", true))
	panel.emit_signal("job_priority_requested", server.member_id, &"cleaning", StaffJobPriorities.Level.HIGH)
	_assert_choice(main, server.member_id, &"cleaning", StaffJobPriorities.Level.HIGH)
	assert_eq(_employee(main, server.member_id), server)
	assert_eq((main.get("sim") as RestaurantSim).owner_agent(), owner)
	assert_eq(GameState._capture_save(), rng_before)
	assert_eq(Economy.ledger.to_dict(), books_before)
	assert_eq(_saved_text(), original_file)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 1
	sim.spawner.max_gap = 1
	sim.spawner.reset()
	Clock.sim.open_ticks = 2
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	Clock.set_speed(2)
	assert_true(main.call("set_staff_visible", true))
	panel.emit_signal("job_priority_requested", server.member_id, &"washing", StaffJobPriorities.Level.LOW)
	_assert_choice(main, server.member_id, &"washing", StaffJobPriorities.Level.LOW)
	assert_eq(Clock.speed, 2, "viewing and changing priorities never pauses service")
	Clock.set_speed(0)
	assert_true(main.call("is_staff_visible"))
	assert_false(main.call("can_edit_staff"))
	assert_false(main.call("staff_hire", _roster(main).candidates()[0].id))
	assert_false(main.call("staff_let_go", server.member_id))
	assert_false(main.call("staff_accept_raise", server.member_id))
	assert_false(main.call("staff_decline_raise", server.member_id))
	assert_false(main.call("tray_buy", 1))
	main.call("run_ticks", 1)
	assert_false(sim.customers().is_empty(), "a genuine arrival keeps LAST_ORDERS observable")
	main.call("run_ticks", 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.LAST_ORDERS)
	panel.emit_signal("job_priority_requested", server.member_id, &"bussing", StaffJobPriorities.Level.OFF)
	_assert_choice(main, server.member_id, &"bussing", StaffJobPriorities.Level.OFF)
	main.call("run_ticks", 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(main.call("is_staff_visible"))
	assert_false((main.get_node("Overlay/EveningReport") as Control).visible)
	panel.emit_signal("job_priority_requested", server.member_id, &"serving", StaffJobPriorities.Level.HIGH)
	_assert_choice(main, server.member_id, &"serving", StaffJobPriorities.Level.HIGH)
	assert_eq(_saved_text(), original_file, "service, close and priority changes add no save point")
	var closed_books: Dictionary = Economy.ledger.to_dict()
	assert_true(main.call("set_staff_visible", false))
	assert_true((main.get_node("Overlay/EveningReport") as Control).visible)
	assert_eq(Economy.ledger.to_dict(), closed_books, "returning to the report cannot settle again")
	assert_true(Clock.sim.next_day())
	var saved: Dictionary = _roster(main).to_dict()
	var document: Dictionary = JSON.parse_string(_saved_text())
	assert_eq(document["data"]["staff"], JSON.parse_string(JSON.stringify(saved)))
	var hiring_state: int = GameState.rng(&"hiring").state
	_close(main)
	var reloaded: Node = await _start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(_roster(reloaded).to_dict(), saved)
	assert_eq(GameState.rng(&"hiring").state, hiring_state)
	for job: StringName in StaffJobPriorities.JOBS:
		_assert_choice(reloaded, &"starter_server", job, _roster(reloaded).job_priorities(&"starter_server").priority(job))
	assert_false(FileAccess.file_exists(_save_dir.path_join("preferences.cfg")))


func test_native_change_preserves_real_bus_path_work_and_reservation_then_affects_next_pick() -> void:
	var main: Node = await _start()
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var server: StaffAgent = _employee(main, &"starter_server")
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var original_file: String = _saved_text()
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	assert_true(Clock.sim.start_service())
	Clock.set_speed(0)
	var table: PlacedItem = ShopBuilder.items_with_def(sim.world, &"table_2")[1]
	sim.kitchen.mark_table_dirty(table.id)
	main.call("run_ticks", 2)
	var bus: SimTask = server.task
	assert_not_null(bus)
	if bus == null:
		return
	assert_eq(bus.kind, &"bus_table")
	assert_false(server.path.is_empty(), "the real table reservation includes an in-flight walk")
	var before: Dictionary = _work_snapshot(server, sim.world)
	var rng_before: Dictionary = GameState._capture_save()
	panel.emit_signal("job_priority_requested", server.member_id, &"cleaning", StaffJobPriorities.Level.HIGH)
	assert_eq(_work_snapshot(server, sim.world), before)
	assert_eq(GameState._capture_save(), rng_before)
	var second_table: PlacedItem = ShopBuilder.items_with_def(sim.world, &"table_2")[0]
	var pending_bus: SimTask = null
	var changed_during_work: bool = false
	# Arrival depends on the real first free seat/path. Observe WORK and finish
	# within one existing 500-tick budget, including the first two walk ticks.
	for tick: int in range(2, MAX_TASK_TICKS):
		if not changed_during_work and server.task == bus and server._step_started \
				and bus.steps[server.step_index].kind == TaskStep.Kind.WORK and server.work_left > 0.0:
			assert_ne(server._held_cell, SimGrid.NO_CELL)
			assert_eq(table.reserved_by(server._held_cell), server.id)
			before = _work_snapshot(server, sim.world)
			var books: Dictionary = Economy.ledger.to_dict()
			panel.emit_signal("job_priority_requested", server.member_id, &"bussing", StaffJobPriorities.Level.OFF)
			assert_eq(_work_snapshot(server, sim.world), before)
			assert_eq(Economy.ledger.to_dict(), books)
			_assert_choice(main, server.member_id, &"bussing", StaffJobPriorities.Level.OFF)
			sim.kitchen.mark_table_dirty(second_table.id)
			for task: SimTask in sim.world.board.open_tasks():
				if task.kind == &"bus_table" and task.first_item_id() == second_table.id:
					pending_bus = task
			changed_during_work = true
		main.call("run_ticks", 1)
		if bus.state == SimTask.State.DONE:
			break
	assert_true(changed_during_work, "the command must exercise actual nonzero in-flight work")
	assert_not_null(pending_bus)
	if pending_bus == null:
		return
	assert_eq(bus.state, SimTask.State.DONE)
	assert_false(sim.kitchen.is_table_dirty(table.id))
	assert_null(server.task)
	main.call("run_ticks", 1)
	assert_null(server.task, "the native Off request applies at the next pick")
	assert_eq(pending_bus.state, SimTask.State.OPEN)
	assert_true(sim.kitchen.is_table_dirty(second_table.id))
	assert_eq(_saved_text(), original_file)
	# A genuine completion stages XP on the roster. Save serialization omits
	# that transient row, so the command must use the runtime copy contract.
	var earned: Dictionary = _growth_snapshot(main)
	assert_true(earned[server.member_id]["earned"][&"service"] > 0)
	panel.emit_signal("job_priority_requested", server.member_id, &"washing", StaffJobPriorities.Level.LOW)
	assert_eq(_growth_snapshot(main), earned, "changing one employee cannot discard anyone's earned XP")
	Clock.sim.open_ticks = Clock.sim.phase_tick + 1
	Clock.sim.last_orders_max_ticks = 1
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var closed: Dictionary = _growth_snapshot(main)
	for id: StringName in earned:
		for skill: StringName in StaffGrowth.SKILLS:
			assert_eq(closed[id]["earned"][skill], 0)
			assert_eq(closed[id]["xp"][skill], earned[id]["xp"][skill] + earned[id]["earned"][skill])
	main.call("_on_service_closed", Clock.sim.day)
	assert_eq(_growth_snapshot(main), closed, "a repeated close cannot award the staged XP twice")
	assert_eq(_saved_text(), original_file)


func test_invalid_requests_and_missing_live_employee_leave_saved_and_live_state_atomic() -> void:
	var main: Node = await _start()
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var candidate: StringName = _roster(main).candidates()[0].id
	for request: Array in [[&"starter_server", &"serving", 0], [&"starter_cook", &"cooking", 0],
			[&"starter_server", &"cooking", 3], [&"starter_cook", &"cleaning", 3],
			[&"starter_server", &"unknown", 2], [&"starter_server", &"cleaning", -1],
			[&"starter_server", &"cleaning", 4], [candidate, &"cleaning", 2],
			[&"owner", &"cleaning", 2], [&"missing", &"cleaning", 2]]:
		var before: Dictionary = _command_snapshot(main)
		assert_false(main.call("staff_set_job_priority", request[0], request[1], request[2]))
		panel.emit_signal("job_priority_requested", request[0], request[1], request[2])
		assert_eq(_command_snapshot(main), before)
	var server: StaffAgent = _employee(main, &"starter_server")
	(main.get("world") as SimWorld).remove_agent(server)
	var before: Dictionary = _command_snapshot(main)
	assert_false(main.call("staff_set_job_priority", &"starter_server", &"cleaning", StaffJobPriorities.Level.HIGH))
	assert_eq(_command_snapshot(main), before, "failed live installation cannot commit the staged roster")
	assert_null(_employee(main, &"starter_server"))


func _start() -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("save_slot", SLOT)
	main.set("use_saves", true)
	main.set("new_game_seed_override", 8201)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	main.set_process(false)
	(main.get_node("CameraRig") as CameraRig).set_process(false)
	(main.get_node("ShopView") as ShopView).set_process(false)
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	main.get_parent().remove_child(main)
	main.free()


func _roster(main: Node) -> StaffRoster:
	return main.get("staff_roster") as StaffRoster


func _employee(main: Node, member_id: StringName) -> StaffAgent:
	for agent: SimAgent in (main.get("world") as SimWorld).agents:
		if agent is StaffAgent and not agent is OwnerAgent and (agent as StaffAgent).member_id == member_id:
			return agent as StaffAgent
	return null


func _assert_choice(main: Node, id: StringName, job: StringName, value: int) -> void:
	assert_eq(_roster(main).job_priorities(id).priority(job), value)
	assert_eq(_employee(main, id).job_priorities().priority(job), value)


func _work_snapshot(employee: StaffAgent, world: SimWorld) -> Dictionary:
	var reservations: Dictionary = {}
	for item: PlacedItem in world.grid.items():
		reservations[item.id] = item._reservations.duplicate()
	var task: SimTask = employee.task
	return {"instance": employee.get_instance_id(), "id": employee.id, "member": employee.member_id,
		"role": employee.role, "cell": employee.cell, "path": employee.path.duplicate(),
		"path_index": employee.path_index, "progress": employee.move_progress, "step": employee.step_index,
		"work": employee.work_left, "step_started": employee._step_started, "held_item": employee._held_item_id,
		"held_cell": employee._held_cell, "skills": employee.skills.duplicate(), "roles": employee.priorities.duplicate(),
		"speed": employee.move_speed, "wage": employee.wage, "trait": employee.trait_id,
		"task": task, "task_id": task.id if task != null else 0,
		"task_state": task.state if task != null else -1, "claimant": task.claimed_by if task != null else -1,
		"drops": task.drops if task != null else 0, "reservations": reservations}


func _command_snapshot(main: Node) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var agents: Array[Dictionary] = []
	for agent: SimAgent in world.agents:
		if agent is StaffAgent:
			var employee: StaffAgent = agent as StaffAgent
			var row: Dictionary = _work_snapshot(employee, world)
			var choices: StaffJobPriorities = employee.job_priorities()
			row["jobs"] = choices.to_dict() if choices != null else null
			agents.append(row)
	return {"roster_id": _roster(main).get_instance_id(), "roster": _roster(main).to_dict(), "agents": agents,
		"growth": _growth_snapshot(main),
		"world_tick": world.now, "clock": Clock.sim.to_dict(), "speed": Clock.speed,
		"rng": GameState._capture_save(), "economy": Economy._capture_save(), "file": _saved_text()}


func _growth_snapshot(main: Node) -> Dictionary:
	var result: Dictionary = {}
	for member: StaffMember in _roster(main).members():
		var growth: StaffGrowth = member.growth_state()
		var earned: Dictionary = {}
		var xp: Dictionary = {}
		for skill: StringName in StaffGrowth.SKILLS:
			earned[skill] = growth.earned_today(skill)
			xp[skill] = growth.progress_xp(skill)
		result[member.id] = {"earned": earned, "xp": xp, "saved": growth.to_dict()}
	return result


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))
