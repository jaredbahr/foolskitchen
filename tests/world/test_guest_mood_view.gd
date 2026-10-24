extends TestCase
## Actual ShopView nodes and caches; appearance still requires rendered review.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const CAPTURE_SCRIPT: GDScript = preload("res://tools/screenshot.gd")

var _view: ShopView
var _sim: RestaurantSim
var _world: SimWorld


func before_each() -> void:
	_world = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	_sim = RestaurantSim.new()
	_sim.world = _world
	_view = VIEW.instantiate() as ShopView


func after_each() -> void:
	_view.free()


func test_only_the_three_waiting_guest_states_receive_native_billboard_icons() -> void:
	var guests: Array[CustomerAgent] = []
	for state: int in range(CustomerAgent.State.LEFT + 1):
		var guest: CustomerAgent = _guest(state as CustomerAgent.State)
		guest._queue_wait = 0
		guest._food_wait = 80 if state == CustomerAgent.State.WAITING_FOOD else 50
		guests.append(guest)
	var staff: StaffAgent = StaffAgent.new(&"customer")
	_world.add_agent(staff)
	_view.show_world(_world)
	assert_eq(_view.mood_nodes.size(), 3)
	assert_false(_view.mood_nodes.has(staff.id), "role text alone never makes staff a guest")
	for guest: CustomerAgent in guests:
		var waiting: bool = guest.state in [CustomerAgent.State.QUEUED,
			CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD]
		assert_eq(_view.mood_nodes.has(guest.id), waiting)
		var body: MeshInstance3D = _view.agent_nodes[guest.id]
		assert_eq(body.has_node("MoodIndicator"), waiting)
		if waiting:
			var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
			assert_eq(icon.get_parent(), body)
			assert_eq(icon.band, guest.mood_band())
			assert_true(icon.position.y + body.position.y > 1.75)
			assert_true(icon.dot.mesh is SphereMesh)
			var material: StandardMaterial3D = icon.dot.material_override as StandardMaterial3D
			assert_eq(material.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED)
			assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
			assert_null(material.albedo_texture)
			assert_eq(icon.mark.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
			assert_eq(icon.mark.text, "!" if guest.state == CustomerAgent.State.WAITING_FOOD else "")
			assert_eq(icon.mark.visible, guest.state == CustomerAgent.State.WAITING_FOOD)


func test_band_and_state_caches_reuse_geometry_and_only_change_presentation_on_band_changes() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.QUEUED)
	_view.show_world(_world)
	var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
	var mesh: Mesh = icon.dot.mesh
	var material: Material = icon.dot.material_override
	assert_eq(icon.updates, 1)
	assert_eq((material as StandardMaterial3D).albedo_color, Color("38764b"))
	guest._queue_wait = 20
	for _frame: int in range(3):
		_view._process(0.1)
	assert_eq(icon.updates, 1, "elapsed time within a band does not update presentation")
	guest.state = CustomerAgent.State.ORDERING
	guest._food_wait = 20
	_view._process(0.1)
	assert_eq(_view._mood_states[guest.id], int(CustomerAgent.State.ORDERING))
	assert_eq(icon.updates, 1, "a waiting-state change in the same band keeps its presentation")
	var elapsed: Array[int] = [50, 80, 90]
	var colors: Array[Color] = [Color("c9a346"), Color("c8743a"), Color("a83e35")]
	var marks: Array[String] = ["", "!", "!!"]
	for index: int in range(elapsed.size()):
		guest._food_wait = elapsed[index]
		_view._process(0.1)
		assert_eq(_view.mood_nodes[guest.id], icon)
		assert_eq(icon.band, index + 1)
		assert_eq(icon.updates, index + 2)
		assert_eq((material as StandardMaterial3D).albedo_color, colors[index])
		assert_eq(icon.mark.text, marks[index])
		assert_eq(icon.mark.visible, not marks[index].is_empty())
		assert_eq(icon.dot.mesh, mesh)
		assert_eq(icon.dot.material_override, material)
	guest.state = CustomerAgent.State.WAITING_FOOD
	for _frame: int in range(3):
		_view._process(0.1)
	assert_eq(icon.updates, 4)
	assert_eq(_view._mood_bands[guest.id], int(CustomerAgent.MoodBand.ABOUT_TO_LEAVE))
	assert_false(icon.set_band(-1))
	assert_false(icon.set_band(4))
	assert_false(icon.set_band(3))
	assert_eq(icon.updates, 4)


func test_state_exit_and_guest_removal_free_icons_and_clear_dead_cache_entries() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	guest._food_wait = 90
	_view.show_world(_world)
	var original: GuestMoodIndicator = _view.mood_nodes[guest.id]
	var original_id: int = original.get_instance_id()
	guest.state = CustomerAgent.State.EATING
	_view._process(0.1)
	assert_false(is_instance_valid(original))
	assert_false(_view.mood_nodes.has(guest.id))
	assert_false(_view.agent_nodes[guest.id].has_node("MoodIndicator"))
	assert_eq(_view._mood_states[guest.id], int(CustomerAgent.State.EATING))
	_view._process(0.1)
	assert_eq(_view.mood_nodes.size(), 0)
	guest.state = CustomerAgent.State.QUEUED
	_view._process(0.1)
	assert_true(_view.mood_nodes.has(guest.id))
	assert_ne(_view.mood_nodes[guest.id].get_instance_id(), original_id)
	assert_eq(_view.mood_nodes[guest.id].band, int(CustomerAgent.MoodBand.HAPPY))
	_world.remove_agent(guest)
	_view._process(0.1)
	assert_false(_view.agent_nodes.has(guest.id))
	assert_eq(_view.mood_nodes.size(), 0)
	assert_eq(_view._mood_states.size(), 0)
	assert_eq(_view._mood_bands.size(), 0)


func test_world_rebind_clears_icons_and_caches_even_when_agent_ids_repeat() -> void:
	var first: CustomerAgent = _guest(CustomerAgent.State.QUEUED)
	first._queue_wait = 90
	_view.show_world(_world)
	var old_icon: GuestMoodIndicator = _view.mood_nodes[first.id]
	var next_world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 5151
	var replacement: CustomerAgent = CustomerAgent.new(_sim, random)
	replacement.state = CustomerAgent.State.EATING
	replacement.queue_patience = 100
	next_world.add_agent(replacement)
	assert_eq(replacement.id, first.id)
	_view.show_world(next_world)
	assert_false(is_instance_valid(old_icon))
	assert_eq(_view.mood_nodes.size(), 0)
	assert_eq(_view._mood_states.size(), 1)
	assert_eq(_view._mood_states[replacement.id], int(CustomerAgent.State.EATING))
	assert_eq(_view._mood_bands[replacement.id], int(CustomerAgent.MoodBand.HAPPY))
	replacement.state = CustomerAgent.State.QUEUED
	replacement._queue_wait = 80
	_view._process(0.1)
	assert_eq(_view.mood_nodes[replacement.id].band, int(CustomerAgent.MoodBand.IMPATIENT))
	assert_eq(_view.mood_nodes[replacement.id].updates, 1)
	var next_icon: GuestMoodIndicator = _view.mood_nodes[replacement.id]
	_view.show_world(null)
	assert_false(is_instance_valid(next_icon))
	assert_eq(_view.mood_nodes.size(), 0)
	assert_eq(_view._mood_states.size(), 0)
	assert_eq(_view._mood_bands.size(), 0)
	assert_eq(_view.agent_nodes.size(), 0)


func test_markers_follow_interpolated_bodies_without_advancing_sim_or_rng() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.QUEUED)
	guest.cell = Vector2i(1, 1)
	guest.path = [Vector2i(1, 1), Vector2i(2, 1)]
	guest.path_index = 1
	guest.move_progress = 0.25
	guest._queue_wait = 80
	var before: Dictionary = _snapshot(guest)
	_view.show_world(_world)
	var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
	var body: MeshInstance3D = _view.agent_nodes[guest.id]
	var expected: Vector3 = GridMath.cell_to_world(guest.cell).lerp(GridMath.cell_to_world(guest.next_cell()), 0.25) \
		+ Vector3(0.0, 0.875 + GuestMoodIndicator.HEAD_OFFSET, 0.0)
	assert_eq(body.transform * icon.position, expected)
	for _frame: int in range(4):
		_view._process(0.1)
	assert_eq(_snapshot(guest), before)
	assert_eq(icon.updates, 1)
	assert_eq(body.transform * icon.position, expected)


func test_capture_evidence_reads_native_bands_independently_and_leaves_sim_unchanged() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.QUEUED)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	tree.root.add_child(_view)
	_view.show_world(_world)
	var before: Dictionary = _snapshot(guest)
	var evidence: Dictionary = CAPTURE_SCRIPT.mood_evidence(_world, _view)
	assert_true(evidence["available"])
	assert_eq(evidence["fixture"], "none")
	assert_eq(evidence["waiting_guests"].size(), 1)
	assert_eq(evidence["visible_indicators"].size(), 1)
	assert_eq(evidence["waiting_guests"][0]["band"], int(CustomerAgent.MoodBand.HAPPY))
	assert_eq(evidence["visible_indicators"][0]["band"], int(CustomerAgent.MoodBand.HAPPY))
	assert_eq(evidence["visible_indicators"][0]["id"], guest.id)
	assert_eq(evidence["visible_indicators"][0]["parent_agent_id"], guest.id)
	# Deliberately change only this test's native view. Evidence must report the
	# mismatch faithfully, so the capture verifier can detect it rather than
	# recomputing an apparently matching indicator from the model.
	_view.mood_nodes[guest.id].set_band(CustomerAgent.MoodBand.ABOUT_TO_LEAVE)
	evidence = CAPTURE_SCRIPT.mood_evidence(_world, _view)
	assert_eq(evidence["waiting_guests"][0]["band"], int(CustomerAgent.MoodBand.HAPPY))
	assert_eq(evidence["visible_indicators"][0]["band"], int(CustomerAgent.MoodBand.ABOUT_TO_LEAVE))
	assert_eq(evidence["visible_indicators"][0]["mark"], "!!")
	_view.mood_nodes[guest.id].hide()
	evidence = CAPTURE_SCRIPT.mood_evidence(_world, _view)
	assert_eq(evidence["waiting_guests"].size(), 1)
	assert_eq(evidence["visible_indicators"].size(), 0)
	assert_eq(_snapshot(guest), before)
	assert_false(CAPTURE_SCRIPT.mood_evidence(_world, null)["available"])


func _guest(state: CustomerAgent.State) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 5151
	var guest: CustomerAgent = CustomerAgent.new(_sim, random)
	guest.state = state
	guest.queue_patience = 100
	guest.food_patience = 100
	guest.order = Order.new()
	guest.order.recipe_id = &"tomato_soup"
	_world.add_agent(guest)
	return guest


func _snapshot(guest: CustomerAgent) -> Dictionary:
	return {"state": guest.state, "queue": [guest.queue_patience, guest._queue_wait],
		"food": [guest.food_patience, guest._food_wait], "walk": guest._walk_wait,
		"eating": guest._eating, "exit": guest._exit_unreachable,
		"cell": guest.cell, "path": guest.path.duplicate(), "path_index": guest.path_index,
		"progress": guest.move_progress, "repath": guest.needs_repath,
		"seat": [guest.table_item_id, guest.seat_cell], "reason": guest.leave_reason,
		"paid": guest.paid, "rng": [guest.rng.seed, guest.rng.state],
		"order": [guest.order.state, guest.order.recipe_id, guest.order.price],
		"world": _world.now, "clock": _world.clock.to_dict(),
		"tasks": _world.board.active_count(), "log": _world.event_log.duplicate()}
