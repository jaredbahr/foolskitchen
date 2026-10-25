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


func test_native_customer_type_looks_flow_through_existing_shop_bridge() -> void:
	var catalogue: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
	var states: Dictionary[int, int] = {}
	for index: int in catalogue.types.size():
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 1110 + index
		var guest: CustomerAgent = _restaurant.add_customer(Vector2i(index + 1, 2), random, catalogue.types[index])
		guest.state = CustomerAgent.State.QUEUED
		states[guest.id] = random.state
	await _enter_view()
	for guest: CustomerAgent in _restaurant.customers():
		var person: PersonView = _person(guest.id)
		assert_true(person.get_meta("person_ready"))
		assert_eq(person.model_name(), PersonPresentation.model_for(&"customer", guest.id, guest.customer_type_id))
		assert_eq(person.customer_type, guest.customer_type_id)
		assert_eq(person.current_clip(), &"idle")
		assert_eq(guest.rng.state, states[guest.id])
	assert_eq(_world.now, 0)


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
	assert_false(icon.position.is_equal_approx(original_position), "the cached band cannot freeze a moving head anchor")
	var clearance: float = 0.15
	assert_true(icon.position.is_equal_approx(person.head_anchor_position() + Vector3.UP * clearance))
	assert_almost_eq((icon.dot.mesh as SphereMesh).radius, 0.108)
	assert_almost_eq((icon.dot.mesh as SphereMesh).height, 0.216)
	assert_almost_eq(icon.mark.pixel_size, 0.0024)
	assert_eq(icon.get_parent(), person)
	assert_eq(guest.rng.state, random_state)
	assert_eq(table.reserved_by(guest.seat_cell), guest.id)


func test_all_imported_guest_rigs_stay_upright_across_timed_partial_clip_transitions() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.QUEUED)
	await _enter_view()
	var person: PersonView = _person(guest.id)
	person.set_playback_speed(1.0)
	for look: int in range(PersonPresentation.GUEST_MODELS.size()):
		assert_true(person.set_look(&"customer", look))
		assert_eq(person.model_name(), PersonPresentation.GUEST_MODELS[look])
		assert_eq(person._player.get_animation_list().size(), PersonPresentation.CLIPS.size())
		# Sample actual imported tracks after time has passed, not only advance(0).
		for pose: Array in [[true, false], [false, true], [false, false],
				[true, false], [false, true], [false, false]]:
			assert_true(person.set_pose(pose[0], pose[1], false, false, 0.27))
			person.face_direction(Vector3(1.0, 0.0, -1.0))
			person._player.advance(0.37)
			_assert_upright(person)
			person._player.advance(0.61)
			_assert_upright(person)
			assert_eq(person.current_clip(), &"sit" if pose[1] else (&"walk" if pose[0] else &"idle"))
			assert_almost_eq((person.get_node("ModelPivot") as Node3D).position.y, 0.27 if pose[1] else 0.0)
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(_world.now, 0)


func test_native_standing_server_clears_a_fixed_seated_guest_and_drawn_picking() -> void:
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	guest.table_item_id = table.id
	guest.seat_cell = table.seat_cells[0]
	guest.cell = guest.seat_cell
	assert_true(table.reserve(guest.seat_cell, guest.id))
	var server: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	server.cell = guest.cell
	await _enter_view()
	var positions: Dictionary[int, Vector3] = _view.drawn_agent_positions()
	assert_eq(positions[guest.id], GridMath.cell_to_world(guest.seat_cell))
	assert_true(positions[server.id].distance_to(positions[guest.id]) >= 0.45)
	assert_eq(_person(guest.id).current_clip(), &"sit")
	assert_eq(_person(server.id).current_clip(), &"idle")
	assert_eq(Picker.pick_agent(positions[server.id], positions), server.id)
	assert_eq(Picker.pick_agent(positions[guest.id], positions), guest.id)
	assert_eq(server.cell, guest.cell)
	assert_eq(table.reserved_by(guest.seat_cell), guest.id)


func test_native_bar_stools_use_measured_surfaces_and_authored_facing_for_every_rotation() -> void:
	var counter_def: ItemDef = load("res://data/items/bar_counter.tres") as ItemDef
	var stool_def: ItemDef = load("res://data/items/bar_stool.tres") as ItemDef
	await _enter_view()
	for turns: int in range(4):
		var counter: PlacedItem = _world.grid.place_def(counter_def, Vector2i(2, 2), turns)
		var seat: Vector2i = counter.origin + GridMath.rotate_cell(Vector2i(0, 1), counter_def.footprint, turns)
		var stool: PlacedItem = _world.grid.place_def(stool_def, seat, turns)
		var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
		guest.table_item_id = counter.id
		guest.seat_cell = seat
		guest.cell = seat
		assert_true(counter.reserve(seat, guest.id))
		_view._process(0.0)
		var person: PersonView = _person(guest.id)
		assert_eq(person.current_clip(), &"sit")
		assert_almost_eq((person.get_node("ModelPivot") as Node3D).position.y, 0.4785)
		var zero: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, Vector2i.ONE, turns)
		var forward: Vector2i = GridMath.rotate_cell(Vector2i.UP, Vector2i.ONE, turns) - zero
		assert_true((-person.global_basis.z).normalized().dot(Vector3(forward.x, 0.0, forward.y)) > 0.9999)
		assert_eq(person.position, GridMath.cell_to_world(seat))
		assert_eq(counter.reserved_by(seat), guest.id)
		assert_eq(stool.reserved_by(seat), -1)
		_world.remove_agent(guest)
		assert_true(_world.grid.remove(stool.id))
		assert_true(_world.grid.remove(counter.id))
		_view._process(0.0)


func test_native_bench_guests_keep_distinct_cells_and_share_the_authored_seat_surface() -> void:
	var table_def: ItemDef = load("res://data/items/cloth_table.tres") as ItemDef
	var bench_def: ItemDef = load("res://data/items/cushioned_bench.tres") as ItemDef
	var table: PlacedItem = _world.grid.place_def(table_def, Vector2i(2, 2))
	var bench: PlacedItem = _world.grid.place_def(bench_def, Vector2i(2, 3))
	var guests: Array[CustomerAgent] = []
	for seat: Vector2i in table.seat_cells:
		var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
		guest.table_item_id = table.id
		guest.seat_cell = seat
		guest.cell = seat
		assert_true(table.reserve(seat, guest.id))
		guests.append(guest)
	assert_eq(guests.size(), 2)
	await _enter_view()
	for guest: CustomerAgent in guests:
		var person: PersonView = _person(guest.id)
		assert_eq(person.current_clip(), &"sit")
		assert_almost_eq((person.get_node("ModelPivot") as Node3D).position.y, 0.264)
		assert_true((-person.global_basis.z).normalized().dot(Vector3.FORWARD) > 0.9999)
		assert_eq(person.position, GridMath.cell_to_world(guest.seat_cell))
		assert_eq(_world.grid.dining_furnishing_id(guest.seat_cell), bench.id)
		assert_eq(table.reserved_by(guest.seat_cell), guest.id)
	assert_almost_eq(_person(guests[0].id).position.distance_to(_person(guests[1].id).position), GridMath.CELL_SIZE)


func test_native_bench_offsets_follow_rotated_front_without_mutating_sim_or_content() -> void:
	var table_def: ItemDef = load("res://data/items/cloth_table.tres") as ItemDef
	var content_bench_def: ItemDef = load("res://data/items/cushioned_bench.tres") as ItemDef
	var content_seats_before: Array[Vector2i] = content_bench_def.seat_cells.duplicate()
	var authored_offset: float = 0.1
	var bench_origins: Array[Vector2i] = [
		Vector2i(2, 3), Vector2i(5, 1), Vector2i(2, 5), Vector2i(5, 5),
	]
	var tables: Array[PlacedItem] = []
	var benches: Array[PlacedItem] = []
	var bench_definitions: Array[ItemDef] = []
	var guests: Array[CustomerAgent] = []
	var expected_forward: Dictionary[int, Vector3] = {}
	var expected_bench_id: Dictionary[int, int] = {}
	var expected_table_id: Dictionary[int, int] = {}
	var expected_seat_cell: Dictionary[int, Vector2i] = {}
	var random_states: Dictionary[int, int] = {}
	var table_cells_before: Array[Array] = []
	var table_seats_before: Array[Array] = []
	var bench_cells_before: Array[Array] = []
	var bench_seats_before: Array[Array] = []
	for turns: int in range(4):
		var bench_def: ItemDef = content_bench_def.duplicate(true) as ItemDef
		bench_def.seated_forward_offset = authored_offset
		bench_definitions.append(bench_def)
		var rotated_zero: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, bench_def.footprint, turns)
		var rotated_front: Vector2i = GridMath.rotate_cell(Vector2i.UP, bench_def.footprint, turns)
		var front_cell: Vector2i = rotated_front - rotated_zero
		var forward: Vector3 = Vector3(front_cell.x, 0.0, front_cell.y).normalized()
		assert_almost_eq(absf(forward.x) + absf(forward.z), 1.0,
			0.0001, "the authored bench front stays on one grid axis")
		var bench_origin: Vector2i = bench_origins[turns]
		var table: PlacedItem = _world.grid.place_def(table_def, bench_origin + front_cell, turns)
		var bench: PlacedItem = _world.grid.place_def(bench_def, bench_origin, turns)
		assert_not_null(table)
		assert_not_null(bench)
		tables.append(table)
		benches.append(bench)
		table_cells_before.append(table.cells.duplicate())
		table_seats_before.append(table.seat_cells.duplicate())
		bench_cells_before.append(bench.cells.duplicate())
		bench_seats_before.append(bench.seat_cells.duplicate())
		assert_eq(table.quarter_turns, turns)
		assert_eq(bench.quarter_turns, turns)
		assert_eq(bench.def, bench_def)
		assert_almost_eq(bench_def.seated_forward_offset, authored_offset)
		assert_eq(bench.seat_cells.size(), 2)
		for seat: Vector2i in bench.seat_cells:
			assert_true(table.seat_cells.has(seat))
			assert_eq(_world.grid.dining_furnishing_id(seat), bench.id)
			var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
			guest.table_item_id = table.id
			guest.seat_cell = seat
			guest.cell = seat
			assert_true(table.reserve(seat, guest.id))
			guests.append(guest)
			expected_forward[guest.id] = forward
			expected_bench_id[guest.id] = bench.id
			expected_table_id[guest.id] = table.id
			expected_seat_cell[guest.id] = seat
			random_states[guest.id] = guest.rng.state
	var blocker_guest: CustomerAgent = guests[2]
	var server: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	server.cell = blocker_guest.seat_cell
	var server_cell_before: Vector2i = server.cell
	await _enter_view()
	_view._process(0.0)
	var icons: Dictionary[int, GuestMoodIndicator] = {}
	var drawn_positions_before: Dictionary[int, Vector3] = _view.drawn_agent_positions()
	var head_positions_before: Dictionary[int, Vector3] = {}
	var mood_positions_before: Dictionary[int, Vector3] = {}
	for turns: int in range(4):
		var first_guest: CustomerAgent = guests[turns * 2]
		var second_guest: CustomerAgent = guests[turns * 2 + 1]
		var first_person: PersonView = _person(first_guest.id)
		var second_person: PersonView = _person(second_guest.id)
		var forward: Vector3 = expected_forward[first_guest.id]
		assert_true(forward.is_equal_approx(expected_forward[second_guest.id]))
		assert_almost_eq(absf(forward.x) + absf(forward.z), 1.0,
			0.0001, "both bench seats use the rotated cardinal front, not the table-centre diagonal")
		for guest: CustomerAgent in [first_guest, second_guest]:
			var person: PersonView = _person(guest.id)
			var expected_position: Vector3 = GridMath.cell_to_world(guest.seat_cell) + forward * authored_offset
			assert_eq(person.current_clip(), &"sit")
			assert_true(person.position.is_equal_approx(expected_position),
				"ShopView draws each guest along the duplicated definition's rotated front")
			assert_true((-person.global_basis.z).normalized().dot(forward) > 0.9999)
			assert_true(person.get_meta("person_ready"))
			assert_eq(guest.cell, guest.seat_cell)
			assert_eq(_world.grid.item(guest.table_item_id).reserved_by(guest.seat_cell), guest.id)
			assert_eq(_world.grid.dining_furnishing_id(guest.seat_cell), benches[turns].id)
			var icon: GuestMoodIndicator = _view.mood_nodes[guest.id] as GuestMoodIndicator
			icons[guest.id] = icon
			assert_true(icon.position.is_equal_approx(person.head_anchor_position() + Vector3.UP * 0.15))
			assert_true(icon.global_position.is_equal_approx(person.to_global(icon.position)))
			head_positions_before[guest.id] = person.to_global(person.head_anchor_position())
			mood_positions_before[guest.id] = icon.global_position
		assert_almost_eq(first_person.position.distance_to(second_person.position), GridMath.CELL_SIZE)
	assert_true(drawn_positions_before[server.id].distance_to(drawn_positions_before[blocker_guest.id])
		>= AgentPresentationController.MIN_STANDING_DISTANCE,
		"standing-agent separation uses final seated offset positions as blockers")
	assert_eq(server.cell, server_cell_before)
	for turns: int in range(4):
		bench_definitions[turns].seated_forward_offset = 0.2
	_view._process(0.0)
	for guest: CustomerAgent in guests:
		var person: PersonView = _person(guest.id)
		var forward: Vector3 = expected_forward[guest.id]
		var icon: GuestMoodIndicator = icons[guest.id]
		assert_true(person.position.is_equal_approx(drawn_positions_before[guest.id] + forward * 0.1))
		assert_true(person.to_global(person.head_anchor_position()).is_equal_approx(
			head_positions_before[guest.id] + forward * 0.1))
		assert_true(icon.global_position.is_equal_approx(mood_positions_before[guest.id] + forward * 0.1))
		assert_true(icon.position.is_equal_approx(person.head_anchor_position() + Vector3.UP * 0.15))
		assert_eq(_view.mood_nodes[guest.id], icon)
		assert_eq(icon.updates, 1, "unchanged mood bands keep their icon while its world anchor follows the person")
		assert_eq(guest.rng.state, random_states[guest.id])
		assert_eq(guest.cell, expected_seat_cell[guest.id])
		assert_eq(guest.seat_cell, expected_seat_cell[guest.id])
		assert_eq(guest.table_item_id, expected_table_id[guest.id])
		assert_eq(_world.grid.item(guest.table_item_id).reserved_by(guest.seat_cell), guest.id)
		assert_eq(_world.grid.dining_furnishing_id(guest.seat_cell), expected_bench_id[guest.id])
	for turns: int in range(4):
		assert_eq(tables[turns].cells, table_cells_before[turns])
		assert_eq(tables[turns].seat_cells, table_seats_before[turns])
		assert_eq(benches[turns].cells, bench_cells_before[turns])
		assert_eq(benches[turns].seat_cells, bench_seats_before[turns])
		assert_eq(tables[turns].quarter_turns, turns)
		assert_eq(benches[turns].quarter_turns, turns)
		assert_eq(bench_definitions[turns].seated_forward_offset, 0.2)
	assert_eq(content_bench_def.seated_forward_offset, 0.0)
	assert_eq(content_bench_def.seat_cells, content_seats_before)
	assert_true(table_def.seat_cells.is_empty())
	assert_eq(server.cell, server_cell_before)
	assert_eq(_world.now, 0)


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
	Clock.set_speed(1)
	_view._process(0.0)
	assert_almost_eq(_person(cook.id)._player.speed_scale, 1.0)
	Clock.set_speed(2)
	_view._process(0.0)
	assert_almost_eq(_person(cook.id)._player.speed_scale, 2.0)
	Clock.set_speed(0)
	_view._process(0.0)
	assert_almost_eq(_person(cook.id)._player.speed_scale, 0.0)
	_world.clock.phase = SimClock.Phase.LAST_ORDERS
	Clock.set_speed(4)
	_view._process(0.0)
	assert_almost_eq(_person(cook.id)._player.speed_scale, 4.0)
	_world.clock.phase = SimClock.Phase.MORNING
	_view._process(0.0)
	assert_almost_eq(_person(cook.id)._player.speed_scale, 0.0)
	_world.clock.phase = SimClock.Phase.CLOSED
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


func _assert_upright(person: PersonView) -> void:
	assert_true(person._model.global_basis.y.normalized().dot(Vector3.UP) > 0.999)
	var skeleton: Skeleton3D = person._skeleton
	for name: String in ["root", "torso"]:
		var bone: int = skeleton.find_bone(name)
		assert_true(bone >= 0)
		if bone < 0:
			continue
		var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		assert_true(pose.is_finite(), "%s %s has finite imported transforms" % [person.model_name(), name])
		assert_true(pose.basis.y.normalized().dot(Vector3.UP) > 0.95,
			"%s %s stays upright in %s" % [person.model_name(), name, person.current_clip()])


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
