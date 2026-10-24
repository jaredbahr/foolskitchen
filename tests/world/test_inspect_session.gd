extends TestCase
## Presentation wiring uses the real session without changing its simulation.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node3D


func before_each() -> void:
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_floor_picking_prefers_drawn_agent_then_item_then_empty_floor() -> void:
	var world: SimWorld = _main.get("world") as SimWorld
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var item: PlacedItem = world.grid.items()[0]
	var point: Vector3 = GridMath.cell_to_world(item.cells[0])
	var agent: SimAgent = world.agents[0]
	for id: int in view.agent_nodes:
		view.agent_nodes[id].position = Vector3(100.0 + id, 0.875, 100.0)
	view.agent_nodes[agent.id].position = point + Vector3(0.0, 0.875, 0.0)
	_main.call("select_at_world_position", point)
	var state: Dictionary = _main.call("inspection_state")
	assert_eq(state["selected_agent_id"], agent.id, "the drawn agent wins over furniture")
	assert_eq(state["selected_item_id"], -1)
	view.agent_nodes[agent.id].position = Vector3(100.0, 0.875, 100.0)
	_main.call("select_at_world_position", point)
	state = _main.call("inspection_state")
	assert_eq(state["selected_item_id"], item.id)
	_main.call("select_at_world_position", Vector3(-10.0, 0.0, -10.0))
	state = _main.call("inspection_state")
	assert_eq(state["selected_agent_id"], -1)
	assert_eq(state["selected_item_id"], -1)
	assert_false(state["panel_visible"])
	assert_eq(world.now, 0, "picking never advances the world")


func test_f3_toggles_once_and_escape_clears_selection() -> void:
	var world: SimWorld = _main.get("world") as SimWorld
	_main.call("select_agent", world.agents[0].id)
	assert_false(_main.call("is_debug_visible"))
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F3
	key.pressed = true
	_main.call("_unhandled_input", key)
	assert_true(_main.call("is_debug_visible"))
	key.echo = true
	_main.call("_unhandled_input", key)
	assert_true(_main.call("is_debug_visible"))
	key.echo = false
	key.pressed = false
	_main.call("_unhandled_input", key)
	assert_true(_main.call("is_debug_visible"))
	key.pressed = true
	_main.call("_unhandled_input", key)
	assert_false(_main.call("is_debug_visible"))
	key.physical_keycode = KEY_ESCAPE
	_main.call("_unhandled_input", key)
	var state: Dictionary = _main.call("inspection_state")
	assert_eq(state["selected_agent_id"], -1)
	assert_false(state["panel_visible"])
	assert_eq(world.now, 0)


func test_removed_guest_clears_inspector_and_selection_while_paused() -> void:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 41
	var guest: CustomerAgent = CustomerAgent.new(sim, rng)
	guest.cell = sim.world.grid.entries()[0]
	sim.world.add_agent(guest)
	assert_true(_main.call("select_agent", guest.id))
	var state: Dictionary = _main.call("inspection_state")
	assert_eq(state["selected_role"], "guest")
	sim.world.remove_agent(guest)
	_main.call("refresh_presentation")
	state = _main.call("inspection_state")
	assert_eq(state["selected_agent_id"], -1)
	assert_false(state["panel_visible"])
	assert_eq(sim.world.now, 0)


func test_morning_refresh_replaces_yesterdays_task_without_a_tick() -> void:
	var world: SimWorld = _main.get("world") as SimWorld
	var staff: StaffAgent = world.agents[0] as StaffAgent
	var task: SimTask = SimTask.new(&"cook", &"cook", "Yesterday's kitchen task")
	world.board.post(task, world.now)
	assert_true(world.board.claim(task, staff.id, world.now))
	staff.task = task
	_main.call("select_agent", staff.id)
	var why: Label = _main.get_node("Overlay/InspectPanel/Panel/Rows/Why") as Label
	assert_eq(why.text, staff.why())
	var previous: String = why.text
	_main.call("_begin_morning")
	assert_null(staff.task)
	assert_eq(why.text, staff.why(), "paused morning refresh follows the completed cleanup")
	assert_true(why.text != previous, "the old task is no longer displayed")
	assert_eq(world.now, 0)


func test_presentation_leaves_ticks_cash_rng_paths_tasks_and_logs_unchanged() -> void:
	var world: SimWorld = _main.get("world") as SimWorld
	var before: Dictionary = _snapshot(world)
	_main.call("select_agent", world.agents[0].id)
	_main.call("set_debug_visible", true)
	_main.call("_process", 0.1)
	_main.call("refresh_presentation")
	_main.call("clear_selection")
	_main.call("set_debug_visible", false)
	assert_eq(_snapshot(world), before)


func _snapshot(world: SimWorld) -> Dictionary:
	var agents: Array[Dictionary] = []
	for agent: SimAgent in world.agents:
		agents.append({"id": agent.id, "cell": agent.cell, "path": agent.path.duplicate(), "index": agent.path_index})
	return {
		"now": world.now, "clock": Clock.sim.tick, "cash": Economy.cash,
		"rng": GameState.rng(&"customers").state, "agents": agents,
		"open": world.board.open_tasks().duplicate(), "claimed": world.board.claimed_tasks().duplicate(),
		"log": world.event_log.duplicate(), "speed": Clock.speed,
	}
