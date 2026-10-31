extends TestCase
## Construction, cardinal frontage, lifecycle and camera checks use actual nodes.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const RIG: PackedScene = preload("res://src/world/camera_rig.tscn")

var _viewport: SubViewport


func after_each() -> void:
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()


func test_initial_neighbourhood_construction_and_photo_operations_do_not_create_sim_agents_or_random_streams() -> void:
	await _host()
	var grid: SimGrid = _grid(0)
	var world: SimWorld = SimWorld.new(grid, SimClock.new())
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = world
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 242
	var guest: CustomerAgent = sim.add_customer(grid.entries()[0], random)
	var before: Dictionary = _state(world)
	var private_state: int = random.state
	var dressing: NeighbourhoodDressing = _new_dressing()
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), _frontage(grid, Vector2i.DOWN), [] as Array[AABB])
	assert_eq(dressing.pedestrians.size(), 3)
	assert_not_null(dressing.car)
	assert_eq(_state(world), before, "construction itself must preserve the pre-existing simulation and all globals")
	assert_eq(random.state, private_state)
	assert_true(world.agents[0] == guest)
	for time: float in [0.0, 4.0, 17.0, 65.0]:
		assert_true(dressing.set_review_time(time))
		dressing.advance_display(0.1)
		dressing.rebuild()
		assert_eq(_state(world), before)
		assert_eq(random.state, private_state)
	var observed: Dictionary = dressing.capture_state()
	observed.clear()
	assert_eq(dressing.pedestrians.size(), 3, "editing an observed snapshot cannot alter live actors")


func test_all_four_actual_frontages_use_the_same_outward_lanes_and_complete_actor_bounds_avoid_the_reserve() -> void:
	await _host()
	for quarter: int in 4:
		var grid: SimGrid = _grid(quarter)
		var normal: Vector2i = _normal(quarter)
		var reserve: Rect2i = _rotate_rect(Rect2i(-2, -2, 12, 9), quarter)
		var dressing: NeighbourhoodDressing = _new_dressing()
		dressing.configure(grid, reserve, _frontage(grid, normal), [] as Array[AABB])
		assert_eq(dressing.pedestrians.size(), 3)
		assert_true(dressing.set_review_time(4.0))
		var origin: Vector3 = Vector3.ZERO
		for entry: Vector2i in grid.entries():
			origin += GridMath.cell_to_world(entry)
		origin /= float(grid.entries().size())
		origin += Vector3(normal.x, 0.0, normal.y) * 0.25
		var lanes: Array[float] = [2.755, 6.455, 7.555]
		for index: int in 3:
			var person: PersonView = dressing.pedestrians[index]
			var offset: Vector3 = person.global_position - origin
			assert_almost_eq(offset.dot(Vector3(normal.x, 0.0, normal.y)), lanes[index], 0.001,
				"cardinal rotation preserves the authored pavement lane in metres")
			_assert_meshes_outside(person, _metres(reserve))
		_assert_meshes_outside(dressing.car, _metres(reserve))
		dressing.get_parent().remove_child(dressing)
		dressing.free()


func test_unchanged_rebuild_and_many_display_updates_reuse_actor_nodes_and_static_mesh_resources() -> void:
	await _host()
	var grid: SimGrid = _grid(0)
	var dressing: NeighbourhoodDressing = _new_dressing()
	var inputs: Array[Dictionary] = _frontage(grid, Vector2i.DOWN)
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), inputs, [] as Array[AABB])
	var actors: Array[int] = _actor_ids(dressing)
	var resources: Array[int] = _mesh_resource_ids(dressing.static_root)
	var count: int = _node_count(dressing)
	var world: SimWorld = SimWorld.new(grid)
	var before: Dictionary = _state(world)
	var start: float = dressing.display_seconds
	for index: int in 360:
		dressing.advance_display(1.0 / 60.0)
		dressing.rebuild()
	assert_eq(_actor_ids(dressing), actors)
	assert_eq(_mesh_resource_ids(dressing.static_root), resources)
	assert_eq(_node_count(dressing), count)
	assert_almost_eq(dressing.display_seconds - start, 6.0, 0.0001)
	assert_eq(_state(world), before)
	# configure must retain detached numeric inputs rather than this caller's arrays.
	(inputs[0]["cells"] as Array).clear()
	inputs.clear()
	dressing.rebuild()
	assert_eq(_actor_ids(dressing), actors)
	assert_eq(_mesh_resource_ids(dressing.static_root), resources)


func test_larger_front_reserve_rebuild_keeps_pooled_actors_and_time_while_moving_the_entire_street_outside_it() -> void:
	await _host()
	var grid: SimGrid = _grid(0)
	var dressing: NeighbourhoodDressing = _new_dressing()
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), _frontage(grid, Vector2i.DOWN), [] as Array[AABB])
	dressing.advance_display(2.0)
	var elapsed: float = dressing.display_seconds
	var actors: Array[int] = _actor_ids(dressing)
	var before_generation: int = int(dressing.capture_state()["rebuild_generation"])
	var wider: Rect2i = Rect2i(-4, -3, 16, 15)
	dressing.configure(grid, wider, _frontage(grid, Vector2i.DOWN), [] as Array[AABB])
	assert_eq(_actor_ids(dressing), actors)
	assert_eq(dressing.display_seconds, elapsed)
	assert_true(int(dressing.capture_state()["rebuild_generation"]) > before_generation)
	var origin_z: float = 4.0
	var reserve_shift: float = 2.0
	for index: int in 3:
		var lanes: Array[float] = [2.755, 6.455, 7.555]
		assert_almost_eq(dressing.pedestrians[index].global_position.z - origin_z, reserve_shift + lanes[index], 0.001)
		_assert_meshes_outside(dressing.pedestrians[index], _metres(wider))
	_assert_meshes_outside(dressing.car, _metres(wider))
	# Growing a real built cell also refreshes geometry; actor identities remain pooled.
	assert_true(grid.set_terrain(Vector2i(0, 7), SimGrid.Terrain.FLOOR))
	dressing.rebuild()
	assert_eq(_actor_ids(dressing), actors)
	assert_eq(dressing.display_seconds, elapsed)


func test_null_and_missing_frontages_leave_no_visible_geometry_and_allow_safe_reconfiguration() -> void:
	await _host()
	var grid: SimGrid = _grid(0)
	var dressing: NeighbourhoodDressing = _new_dressing()
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), _frontage(grid, Vector2i.DOWN), [] as Array[AABB])
	dressing.configure(null, Rect2i(), [] as Array[Dictionary], [] as Array[AABB])
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_false(dressing.static_root.is_visible_in_tree())
	for person: PersonView in dressing.pedestrians:
		assert_false(person.is_visible_in_tree())
	if is_instance_valid(dressing.car):
		assert_false(dressing.car.is_visible_in_tree())
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), [] as Array[Dictionary], [] as Array[AABB])
	assert_false(dressing.static_root.is_visible_in_tree())
	for person: PersonView in dressing.pedestrians:
		assert_false(person.is_visible_in_tree())
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), _frontage(grid, Vector2i.DOWN), [] as Array[AABB])
	assert_eq(dressing.pedestrians.size(), 3)
	assert_eq(_actor_ids(dressing).size(), 4)
	for person: PersonView in dressing.pedestrians:
		assert_true(person.is_visible_in_tree())


func test_camera_extension_changes_only_the_selected_clamp_side_and_never_the_default_view() -> void:
	await _host()
	var rig: CameraRig = RIG.instantiate() as CameraRig
	_viewport.add_child(rig)
	rig.set_process(false)
	for normal: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]:
		rig.frame_area(Vector2(3.5, 3.0), Vector2(5.5, 5.0), 12.0, true)
		var frame: Array = _camera_frame(rig)
		assert_true(rig.set_street_pan_extension(normal, 3.0))
		assert_eq(_camera_frame(rig), frame)
		var low: Vector2 = Vector2(-2.0, -2.0) + Vector2(mini(normal.x, 0), mini(normal.y, 0)) * 3.0
		var high: Vector2 = Vector2(9.0, 8.0) + Vector2(maxi(normal.x, 0), maxi(normal.y, 0)) * 3.0
		rig.position = Vector3(-100.0, 0.0, -100.0)
		rig.step_view(0.01, Vector2.ZERO)
		assert_eq(rig.position, Vector3(low.x, 0.0, low.y))
		rig.position = Vector3(100.0, 0.0, 100.0)
		rig.step_view(0.01, Vector2.ZERO)
		assert_eq(rig.position, Vector3(high.x, 0.0, high.y))
		assert_eq(rig.pan_center, Vector2(3.5, 3.0))
		assert_eq(rig.pan_limits, Vector2(5.5, 5.0))
	assert_false(rig.set_street_pan_extension(Vector2i.ONE, 3.0))
	assert_false(rig.set_street_pan_extension(Vector2i.ZERO, 3.0))
	for value: float in [-1.0, NAN, INF]:
		assert_false(rig.set_street_pan_extension(Vector2i.DOWN, value))
	rig.frame_area(Vector2(3.5, 3.0), Vector2(5.5, 5.0), 12.0, true)
	rig.position = Vector3(100.0, 0.0, 100.0)
	rig.step_view(0.01, Vector2.ZERO)
	assert_eq(rig.position, Vector3(9.0, 0.0, 8.0), "ordinary re-framing clears the previous street extension")


func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _new_dressing() -> NeighbourhoodDressing:
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	return dressing


func _grid(quarter: int) -> SimGrid:
	var base: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	for cell: Vector2i in base.cells():
		grid.set_terrain(_rotate(cell, quarter), base.terrain(cell))
	return grid


func _frontage(grid: SimGrid, normal: Vector2i) -> Array[Dictionary]:
	return [{"cells": grid.entries().duplicate(), "normal": normal}] as Array[Dictionary]


func _normal(quarter: int) -> Vector2i:
	return [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT][quarter]


func _rotate(cell: Vector2i, quarter: int) -> Vector2i:
	match quarter:
		1:
			return Vector2i(7 - cell.y, cell.x)
		2:
			return Vector2i(7 - cell.x, 7 - cell.y)
		3:
			return Vector2i(cell.y, 7 - cell.x)
	return cell


func _rotate_rect(rect: Rect2i, quarter: int) -> Rect2i:
	var cells: Array[Vector2i] = [_rotate(rect.position, quarter), _rotate(rect.end - Vector2i.ONE, quarter),
		_rotate(Vector2i(rect.end.x - 1, rect.position.y), quarter), _rotate(Vector2i(rect.position.x, rect.end.y - 1), quarter)]
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell: Vector2i in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	return Rect2i(low, high - low + Vector2i.ONE)


func _metres(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) * 0.5, Vector2(rect.size) * 0.5)


func _state(world: SimWorld) -> Dictionary:
	var agents: Array = []
	for agent: SimAgent in world.agents:
		agents.append([agent.id, agent.cell, agent.path.duplicate()])
	return {"agents": agents, "grid_version": world.grid.version, "clock": world.clock.to_dict(),
		"now": world.now, "rng": GameState.call("_capture_save"), "economy": Economy.call("_capture_save"),
		"providers": SaveSystem._providers.keys()}


func _actor_ids(dressing: NeighbourhoodDressing) -> Array[int]:
	var result: Array[int] = []
	for person: PersonView in dressing.pedestrians:
		result.append(person.get_instance_id())
	if is_instance_valid(dressing.car):
		result.append(dressing.car.get_instance_id())
	return result


func _mesh_resource_ids(root: Node) -> Array[int]:
	var result: Array[int] = []
	for child: Node in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			result.append((child as MeshInstance3D).mesh.get_instance_id())
		result.append_array(_mesh_resource_ids(child))
	return result


func _node_count(root: Node) -> int:
	var count: int = 1
	for child: Node in root.get_children():
		count += _node_count(child)
	return count


func _assert_meshes_outside(root: Node, forbidden: Rect2) -> void:
	for child: Node in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).is_visible_in_tree():
			var mesh: MeshInstance3D = child as MeshInstance3D
			if mesh.mesh != null:
				var box: AABB = mesh.global_transform * mesh.get_aabb()
				var rect: Rect2 = Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
				assert_false(minf(rect.end.x, forbidden.end.x) - maxf(rect.position.x, forbidden.position.x) > 0.0001 \
					and minf(rect.end.y, forbidden.end.y) - maxf(rect.position.y, forbidden.position.y) > 0.0001)
		_assert_meshes_outside(child, forbidden)


func _camera_frame(rig: CameraRig) -> Array:
	return [rig.initial_focus, rig.initial_zoom, rig.initial_yaw_degrees, rig.pitch_degrees,
		rig.transform, (rig.get_node("Camera3D") as Camera3D).transform,
		(rig.get_node("Camera3D") as Camera3D).size]
