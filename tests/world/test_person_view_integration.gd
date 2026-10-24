extends TestCase
## Native scene-tree regressions. Source-authored only until supported CI runs.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const INSPECTOR: PackedScene = preload("res://src/ui/inspect_panel.tscn")
var _view: ShopView
var _world: SimWorld
var _restaurant: RestaurantSim
var _old_speed: int = 0


func before_each() -> void:
	_old_speed = Clock.speed
	Clock.set_speed(0)
	_world = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	_restaurant = RestaurantSim.new()
	_restaurant.world = _world
	_view = VIEW.instantiate() as ShopView


func after_each() -> void:
	_view.free()
	_restaurant = null
	_world = null
	Clock.set_speed(_old_speed)


func test_native_roles_use_fixed_looks_hat_and_private_looping_clips() -> void:
	var cook: StaffAgent = _world.add_agent(StaffAgent.new(&"cook")) as StaffAgent
	var server: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	var owner: OwnerAgent = _world.add_agent(OwnerAgent.new()) as OwnerAgent
	cook.cell = Vector2i(1, 1)
	server.cell = Vector2i(3, 1)
	owner.cell = Vector2i(5, 1)
	await _enter_view()
	var expected: Dictionary[StringName, StringName] = {
		&"cook": &"character-male-b", &"server": &"character-male-d", &"owner": &"character-male-a",
	}
	for agent: SimAgent in _world.agents:
		var person: PersonView = _person(agent.id)
		assert_true(person.is_inside_tree())
		assert_true(person.get_meta("person_ready"))
		assert_eq(person.model_name(), expected[agent.role])
		assert_eq(person.position, GridMath.cell_to_world(agent.cell))
		assert_eq(person.get_meta("agent_id"), agent.id)
		assert_eq(person._hat.visible, agent.role == &"cook")
		assert_eq((person.get_node("ModelPivot") as Node3D).scale, Vector3.ONE * ArtScale.CHARACTER_SCALE)
		for clip: StringName in PersonPresentation.CLIPS:
			assert_true(person._player.has_animation(clip))
			assert_eq(person._player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR)
	assert_ne(_person(cook.id)._player.get_animation(&"walk"), _person(server.id)._player.get_animation(&"walk"))
	assert_eq(_world.now, 0)


func test_native_tray_keeps_legacy_shape_and_follows_loaded_hands_and_live_count() -> void:
	var worker: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	worker.cell = Vector2i(1, 1)
	var task: SimTask = SimTask.new(&"deliver", &"server")
	_world.board.post(task, 0)
	assert_true(_world.board.claim(task, worker.id, 0))
	worker.task = task
	task.payload["carried_count"] = 2
	await _enter_view()
	var person: PersonView = _person(worker.id)
	var tray: MeshInstance3D = person.get_node("Tray") as MeshInstance3D
	assert_true(tray.visible)
	assert_eq(person.current_clip(), &"holding-both")
	assert_eq(tray.position, person.carry_anchor_position())
	assert_eq((tray.mesh as BoxMesh).size, Vector3(0.68, 0.045, 0.38))
	task.payload["carried_count"] = 1
	_view._process(0.0)
	assert_false(tray.visible)
	assert_eq(person.current_clip(), &"holding-both")
	task.payload["carried_count"] = 0
	_view._process(0.0)
	assert_eq(person.current_clip(), &"idle")
	assert_eq(_world.now, 0)
	assert_eq(worker.task, task)
	assert_eq(task.state, SimTask.State.CLAIMED)


func test_native_mood_anchor_moves_when_seating_changes_inside_same_state_and_band() -> void:
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	guest.table_item_id = table.id
	guest.seat_cell = table.seat_cells[0]
	guest.cell = guest.seat_cell
	var random_state: int = guest.rng.state
	await _enter_view()
	var person: PersonView = _person(guest.id)
	var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
	var original_position: Vector3 = icon.position
	assert_eq(person.current_clip(), &"idle", "a target seat without its reservation is not occupied")
	assert_true(table.reserve(guest.seat_cell, guest.id))
	_view._process(0.0)
	assert_eq(person.current_clip(), &"sit")
	assert_almost_eq((person.get_node("ModelPivot") as Node3D).position.y, AgentPresentationController.NOMINAL_CHAIR_SEAT_HEIGHT)
	assert_eq(_view.mood_nodes[guest.id], icon)
	assert_eq(icon.updates, 1, "same state and band reuse the native icon")
	assert_ne(icon.position, original_position, "the cached band cannot freeze a moving head anchor")
	var clearance: float = AgentPresentationController.MOOD_CLEARANCE + (icon.dot.mesh as SphereMesh).radius
	assert_eq(icon.position, person.head_anchor_position() + Vector3.UP * clearance)
	assert_eq(icon.get_parent(), person)
	assert_eq(guest.rng.state, random_state)
	assert_eq(table.reserved_by(guest.seat_cell), guest.id)


func test_nudged_drawn_positions_keep_owner_picking_inspection_and_selection_ring() -> void:
	var owner: OwnerAgent = _world.add_agent(OwnerAgent.new(Vector2i(1, 1))) as OwnerAgent
	var cook: StaffAgent = _world.add_agent(StaffAgent.new(&"cook")) as StaffAgent
	cook.cell = owner.cell
	await _enter_view()
	var positions: Dictionary[int, Vector3] = _view.drawn_agent_positions()
	assert_ne(positions[owner.id], positions[cook.id])
	assert_almost_eq(positions[owner.id].y, 0.0)
	assert_eq(Picker.pick_agent(positions[owner.id], positions), owner.id)
	var panel: InspectPanel = INSPECTOR.instantiate() as InspectPanel
	_view.add_child(panel)
	panel.bind_world(_world)
	panel.show_agent(owner.id)
	assert_eq(panel.selected_agent_id, owner.id)
	assert_true(panel.visible)
	var geometry: DebugGeometry = DebugGeometry.new()
	_view.add_child(geometry)
	geometry.update_geometry(_world, positions, _view.drawn_agent_colors(), owner.id, false)
	assert_true(geometry._ring.visible)
	assert_eq(geometry._ring.position, Vector3(positions[owner.id].x, DebugGeometry.RING_HEIGHT, positions[owner.id].z))
	assert_eq(owner.current_mode(), &"rest")
	assert_eq(owner.cell, cook.cell)
	assert_eq(_world.now, 0)


func test_native_removal_and_rebind_free_people_attachments_and_repeated_id_caches() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.QUEUED)
	await _enter_view()
	var person: PersonView = _person(guest.id)
	var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
	var tray: Node = person.get_node("Tray")
	_world.remove_agent(guest)
	_view._process(0.0)
	assert_false(is_instance_valid(person))
	assert_false(is_instance_valid(icon))
	assert_false(is_instance_valid(tray))
	assert_true(_view.agent_nodes.is_empty())
	assert_true(_view._mood_states.is_empty())
	var next_world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var next_cook: StaffAgent = next_world.add_agent(StaffAgent.new(&"cook")) as StaffAgent
	assert_eq(next_cook.id, guest.id)
	_view.show_world(next_world)
	assert_eq(_person(next_cook.id).model_name(), PersonPresentation.COOK_MODEL)
	assert_true(_view.mood_nodes.is_empty())
	_view.show_world(null)
	assert_true(_view.agent_nodes.is_empty())
	assert_true(_view.mood_nodes.is_empty())


func test_playback_matches_clock_speed_and_cleaner_remains_an_explicit_fallback() -> void:
	var cook: StaffAgent = _world.add_agent(StaffAgent.new(&"cook")) as StaffAgent
	var cleaner: StaffAgent = _world.add_agent(StaffAgent.new(&"cleaner")) as StaffAgent
	cleaner.cell = Vector2i(2, 2)
	await _enter_view()
	_world.clock.phase = SimClock.Phase.OPEN
	Clock.set_speed(2)
	_view._process(0.0)
	assert_almost_eq(_person(cook.id)._player.speed_scale, 2.0)
	Clock.set_speed(0)
	_view._process(0.0)
	assert_almost_eq(_person(cook.id)._player.speed_scale, 0.0)
	var fallback: MeshInstance3D = _view.agent_nodes[cleaner.id] as MeshInstance3D
	assert_true(fallback.mesh is CapsuleMesh)
	assert_true(fallback.get_meta("unsupported_role"))
	assert_false(fallback.get_meta("person_ready"))
	assert_eq((fallback.material_override as StandardMaterial3D).albedo_color, ShopView.CLEANER_SWATCH.color)
	assert_eq(_world.now, 0)


func _enter_view() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	tree.root.add_child(_view)
	assert_true(_view.is_inside_tree(), "filtered runs enter the native scene tree before loading rigs")
	_view.set_process(false)
	_view.show_world(_world)


func _person(id: int) -> PersonView:
	var person: PersonView = _view.agent_nodes[id] as PersonView
	assert_not_null(person)
	return person


func _guest(state: CustomerAgent.State) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	var guest: CustomerAgent = _world.add_agent(CustomerAgent.new(_restaurant, random)) as CustomerAgent
	guest.state = state
	guest.cell = Vector2i(1, 1)
	guest.queue_patience = 100
	guest.food_patience = 100
	guest.order = Order.new()
	guest.order.recipe_id = &"tomato_soup"
	return guest


func _table() -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.category = ItemDef.Category.TABLE
	definition.footprint = Vector2i(2, 2)
	definition.seat_cells = [Vector2i(-1, 1), Vector2i(2, 1)]
	return _world.grid.place_def(definition, Vector2i(2, 2))
