extends TestCase
## Initial existing-API RED: preserve this entire source and setup through GREEN.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node3D
var _viewport: SubViewport
var _old_providers: Dictionary


func before_each() -> void:
	_old_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	SaveSystem._providers = _old_providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_real_shop_has_presentation_only_passers_by_without_changing_agents_door_paths_or_simulation() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var world: SimWorld = _main.get("world") as SimWorld
	assert_not_null(view)
	assert_not_null(world)
	assert_true(view.is_inside_tree())
	assert_true(view.world == world)
	assert_true(Clock.attached_world == world)
	assert_eq(Clock.speed, 0)
	assert_true(world.agents.size() > 0, "the real morning fixture contains its normal staff")
	assert_eq(view.agent_nodes.size(), world.agents.size(), "normal sim people have their existing visual bridge")
	var ids: Array[int] = _agent_ids(world)
	for id: int in ids:
		assert_true(view.agent_nodes.has(id))
		assert_true((view.agent_nodes[id] as Node3D).is_inside_tree())
	var path_before: Dictionary = _door_paths(world.grid)
	var clock_before: Dictionary = world.clock.to_dict()
	var rng_before: Dictionary = GameState.call("_capture_save")
	var economy_before: Dictionary = Economy.call("_capture_save")
	var version_before: int = world.grid.version
	var tick_before: int = world.now
	var providers_before: Array = SaveSystem._providers.keys()
	providers_before.sort()
	await _frames(8)
	assert_eq(_agent_ids(world), ids)
	assert_eq(view.agent_nodes.size(), ids.size())
	assert_eq(_door_paths(world.grid), path_before, "displayed street life never changes the real guest-door routes")
	assert_eq(world.clock.to_dict(), clock_before)
	assert_eq(world.now, tick_before)
	assert_eq(world.grid.version, version_before)
	assert_eq(GameState.call("_capture_save"), rng_before, "display frames consume no named random stream")
	assert_eq(Economy.call("_capture_save"), economy_before)
	var providers_after: Array = SaveSystem._providers.keys()
	providers_after.sort()
	assert_eq(providers_after, providers_before)
	var passers_by: Array[PersonView] = []
	for person: PersonView in _people_below(_main):
		# Owner-character thumbnail previews use a different World3D.
		if person.get_world_3d() == view.get_world_3d() and person.is_visible_in_tree() \
				and not _belongs_to_agent_view(person, view):
			passers_by.append(person)
	assert_true(passers_by.size() >= 2,
		"at least two actual guest-model passers-by exist outside every simulation-agent visual subtree")


func _start() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("owner_creation_requested", false)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	rig.edge_pan_enabled = false
	await _frames(4)


func _agent_ids(world: SimWorld) -> Array[int]:
	var ids: Array[int] = []
	for agent: SimAgent in world.agents:
		ids.append(agent.id)
	return ids


func _door_paths(grid: SimGrid) -> Dictionary:
	var paths: Dictionary = {}
	var destination: Vector2i = Vector2i(6, 9)
	assert_eq(grid.terrain(destination), SimGrid.Terrain.FLOOR)
	assert_true(grid.is_walkable(destination))
	assert_eq(grid.entries().size(), 2)
	for entry: Vector2i in grid.entries():
		assert_eq(grid.terrain(entry), SimGrid.Terrain.ENTRY)
		assert_true(grid.is_walkable(entry))
		var path: Array[Vector2i] = grid.find_guest_path(entry, destination)
		assert_false(path.is_empty(), "the authored street door reaches the actual dining floor")
		paths[entry] = path
	return paths


func _people_below(root: Node) -> Array[PersonView]:
	var people: Array[PersonView] = []
	for child: Node in root.get_children():
		if child is PersonView:
			people.append(child as PersonView)
		people.append_array(_people_below(child))
	return people


func _belongs_to_agent_view(person: PersonView, view: ShopView) -> bool:
	for root: Node3D in view.agent_nodes.values():
		if root == person or root.is_ancestor_of(person):
			return true
	return false


func _frames(count: int) -> void:
	for index: int in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func test_normal_display_and_actual_walk_animation_advance_without_simulation_and_photo_time_reproduces_both() -> void:
	await _start()
	var dressing: NeighbourhoodDressing = (_main.get_node("ShopView") as ShopView).neighbourhood_dressing
	assert_not_null(dressing)
	if dressing == null:
		return
	assert_eq(dressing.pedestrians.size(), 3)
	assert_not_null(dressing.car)
	assert_true(dressing.is_processing())
	var world: SimWorld = _main.get("world") as SimWorld
	var state: Dictionary = _isolation_snapshot(world)
	var time_before: float = dressing.display_seconds
	var positions: Array[Vector3] = _pedestrian_positions(dressing)
	var phases: Array[float] = _walk_phases(dressing)
	await _frames(6)
	assert_true(dressing.display_seconds > time_before, "the normal enabled process uses display time while the sim is paused")
	assert_ne(_pedestrian_positions(dressing), positions)
	assert_ne(_walk_phases(dressing), phases, "the actual AnimationPlayers advance, not only reported metadata")
	assert_eq(_isolation_snapshot(world), state)
	dressing.set_process(false)
	assert_true(dressing.set_review_time(4.0))
	var photo_positions: Array[Vector3] = _pedestrian_positions(dressing)
	var photo_phases: Array[float] = _walk_phases(dressing)
	var photo_car: Transform3D = dressing.car.transform
	var photo_visible: bool = dressing.car.visible
	dressing.advance_display(1.75)
	assert_eq(_pedestrian_positions(dressing), photo_positions)
	assert_eq(_walk_phases(dressing), photo_phases)
	assert_eq(dressing.car.transform, photo_car)
	assert_eq(dressing.car.visible, photo_visible)
	assert_true(dressing.set_review_time(9.0))
	assert_ne(_pedestrian_positions(dressing), photo_positions)
	assert_true(dressing.set_review_time(4.0))
	assert_eq(_pedestrian_positions(dressing), photo_positions)
	assert_eq(_walk_phases(dressing), photo_phases)
	for invalid: float in [-1.0, NAN, INF]:
		assert_false(dressing.set_review_time(invalid))
		assert_eq(_pedestrian_positions(dressing), photo_positions)
	var elapsed: float = dressing.display_seconds
	for invalid: float in [-1.0, NAN, INF]:
		dressing.advance_display(invalid)
		assert_eq(dressing.display_seconds, elapsed)
	dressing.clear_review_time()
	dressing.advance_display(0.37)
	assert_true(dressing.display_seconds > elapsed)
	assert_ne(_pedestrian_positions(dressing), photo_positions)
	assert_eq(_isolation_snapshot(world), state)


func test_actors_use_existing_guest_models_and_no_neighbourhood_nodes_add_lights_physics_or_pick_targets() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dressing: NeighbourhoodDressing = view.neighbourhood_dressing
	assert_not_null(dressing)
	if dressing == null:
		return
	assert_eq(dressing.pedestrians.size(), 3)
	var fixed_ids: Array[int] = [1, 4, 6]
	for index: int in 3:
		var person: PersonView = dressing.pedestrians[index]
		assert_eq(person.model_name(), PersonPresentation.model_for(&"guest", fixed_ids[index]))
		assert_eq(person.current_clip(), &"walk")
		for agent_view: Node3D in view.agent_nodes.values():
			assert_ne(agent_view.get_instance_id(), person.get_instance_id())
		for item_view: Node3D in view.item_nodes.values():
			assert_ne(item_view.get_instance_id(), person.get_instance_id())
		assert_eq((person.get_node("ModelPivot") as Node3D).scale, Vector3.ONE * ArtScale.CHARACTER_SCALE)
	for node: Node in _nodes_below(dressing):
		assert_false(node is Light3D, "street lamps remain unlit until the night-lighting issue")
		assert_false(node is CollisionObject3D)
		assert_false(node is CollisionShape3D)
		assert_false(node is NavigationRegion3D)
		assert_false(node is RayCast3D)
		assert_false(node.has_meta("agent_id"))
		assert_false(node.has_meta("item_id"))
		if node is MeshInstance3D:
			var mesh: MeshInstance3D = node as MeshInstance3D
			for surface: int in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(surface)
				if material is BaseMaterial3D:
					var base: BaseMaterial3D = material as BaseMaterial3D
					var rgb: Color = Color(base.emission.r, base.emission.g, base.emission.b, 1.0)
					assert_true(not base.emission_enabled or (rgb == Color.BLACK and base.emission_texture == null),
						"the material emits no light: disabled or exact zero RGB without an emission texture")
	var before_agents: Array[int] = _agent_ids(view.world)
	var before_items: Dictionary = view.item_nodes.duplicate()
	for person: PersonView in dressing.pedestrians:
		var origin: Vector3 = person.global_position + Vector3(0.0, 10.0, 0.0)
		assert_eq(view.item_at_ray(origin, Vector3.DOWN), -1,
			"a real ray through a decorative passer-by cannot select shop furniture")
	assert_eq(view.item_nodes, before_items)
	assert_eq(_agent_ids(view.world), before_agents)


func test_actual_static_triangles_avoid_maximum_lease_native_pads_and_service_paths() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dressing: NeighbourhoodDressing = view.neighbourhood_dressing
	assert_not_null(dressing)
	if dressing == null:
		return
	var layout: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
	var lease: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
	var lot: Rect2i = ShopFootprint.from_layout(lease.layout_for(layout, 2)).lot
	var forbidden: Array[Rect2] = [_cell_rect(lot)]
	for cell: Vector2i in view.world.grid.cells():
		if view.world.grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			forbidden.append(_cell_rect(Rect2i(cell, Vector2i.ONE)))
	var native: Array[AABB] = view.room_dressing.native_pavement_bounds()
	assert_true(native.size() >= 2, "the original entrance pads retain their own geometry")
	for pad: AABB in native:
		forbidden.append(_xz_rect(pad))
	for tile: PropView in view.segment_view.path_tiles():
		var bounds: AABB = view.global_transform.affine_inverse() * tile.global_transform * tile.get_combined_aabb()
		forbidden.append(_xz_rect(bounds))
	var buildings: Node3D = dressing.find_child("Buildings", true, false) as Node3D
	var lamps: Node3D = dressing.find_child("StreetLamps", true, false) as Node3D
	assert_not_null(buildings)
	assert_not_null(lamps)
	if buildings == null or lamps == null:
		return
	assert_eq(buildings.get_child_count(), 5)
	assert_eq(lamps.get_child_count(), 2)
	for building: Node3D in buildings.get_children():
		assert_false(_positive_overlap(_xz_rect(_visible_mesh_bounds(building, view)), _cell_rect(lot).grow(1.25)),
			"each whole building and roof hull clears the maximum lease")
	var triangles: int = 0
	for mesh: MeshInstance3D in _meshes_below(dressing.static_root):
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		triangles += _assert_mesh_triangles_avoid(mesh, view, forbidden)
	assert_true(triangles > 100, "the actual neighbourhood meshes, including copied pavement, were checked")


func test_actual_pedestrian_and_car_meshes_stay_clear_of_the_lease_and_door_across_their_display_cycle() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dressing: NeighbourhoodDressing = view.neighbourhood_dressing
	assert_not_null(dressing)
	if dressing == null:
		return
	dressing.set_process(false)
	var layout: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
	var lease: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
	var reserve: Rect2 = _cell_rect(ShopFootprint.from_layout(lease.layout_for(layout, 2)).lot)
	var apron: Rect2 = Rect2(Vector2(2.5, 6.0), Vector2(2.0, 2.2))
	var road: Node3D = dressing.find_child("Road", true, false) as Node3D
	assert_not_null(road)
	if road == null:
		return
	var road_bounds: Rect2 = _xz_rect(_visible_mesh_bounds(road, view))
	var visible_car: bool = false
	var hidden_car: bool = false
	var sweeps: Array[AABB] = []
	for index: int in 3:
		sweeps.append(AABB())
	for sample: int in 241:
		assert_true(dressing.set_review_time(float(sample) * 0.5))
		for index: int in 3:
			var person: PersonView = dressing.pedestrians[index]
			var bounds: AABB = _visible_mesh_bounds(person, view)
			var origin: Vector3 = view.to_local(person.global_position)
			var envelope: AABB = AABB(origin + Vector3(-0.5, -0.05, -0.5), Vector3(1.0, 1.15, 1.0))
			sweeps[index] = envelope if sample == 0 else sweeps[index].merge(envelope)
			assert_true(Rect2(Vector2(origin.x - 0.5, origin.z - 0.5), Vector2.ONE).grow(0.0001).encloses(_xz_rect(bounds)),
				"actual posed vertices fit the whole-path conservative horizontal envelope")
			assert_true(bounds.position.y >= origin.y - 0.05 - 0.0001 and bounds.end.y <= origin.y + 1.10 + 0.0001)
			assert_true(bounds.size.y > 0.5)
			assert_false(_positive_overlap(_xz_rect(bounds), reserve))
			assert_false(_positive_overlap(_xz_rect(bounds), apron))
		if dressing.car.visible:
			visible_car = true
			var bounds: AABB = _visible_mesh_bounds(dressing.car, view)
			assert_true(road_bounds.grow(0.0001).encloses(_xz_rect(bounds)), "the full actual car stays above the actual road surface")
			var near_lane: Rect2 = Rect2(Vector2(road_bounds.position.x, 9.405), Vector2(road_bounds.size.x, 1.20))
			var far_lane: Rect2 = Rect2(Vector2(road_bounds.position.x, 10.605), Vector2(road_bounds.size.x, 1.20))
			assert_true(near_lane.grow(0.0001).encloses(_xz_rect(bounds)) or far_lane.grow(0.0001).encloses(_xz_rect(bounds)),
				"the full car fits one 1.20m lane rather than straddling both")
			assert_false(_positive_overlap(_xz_rect(bounds), reserve))
			assert_false(_positive_overlap(_xz_rect(bounds), apron))
		else:
			hidden_car = true
	for sweep: AABB in sweeps:
		assert_false(_positive_overlap(_xz_rect(sweep), reserve), "the entire straight continuous walker sweep clears the lease")
		assert_false(_positive_overlap(_xz_rect(sweep), apron), "turns and intermediate positions clear the full door apron")
	assert_true(visible_car, "the pooled car actually passes during the authored cycle")
	assert_true(hidden_car, "the same car also has its authored inactive interval")


func _isolation_snapshot(world: SimWorld) -> Dictionary:
	var agents: Array = []
	for agent: SimAgent in world.agents:
		agents.append([agent.id, agent.cell, agent.path.duplicate()])
	return {"agents": agents, "clock": world.clock.to_dict(), "now": world.now,
		"version": world.grid.version, "rng": GameState.call("_capture_save"),
		"economy": Economy.call("_capture_save"), "providers": SaveSystem._providers.keys()}


func _pedestrian_positions(dressing: NeighbourhoodDressing) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for person: PersonView in dressing.pedestrians:
		result.append(person.global_position)
	return result


func _walk_phases(dressing: NeighbourhoodDressing) -> Array[float]:
	var phases: Array[float] = []
	for person: PersonView in dressing.pedestrians:
		var players: Array[Node] = person.find_children("*", "AnimationPlayer", true, false)
		assert_true(players.size() > 0)
		if not players.is_empty():
			var player: AnimationPlayer = players[0] as AnimationPlayer
			assert_true(player.has_animation(&"walk"))
			phases.append(player.current_animation_position)
	return phases


func _nodes_below(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		result.append(child)
		result.append_array(_nodes_below(child))
	return result


func _meshes_below(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		result.append(root as MeshInstance3D)
	for child: Node in root.get_children():
		result.append_array(_meshes_below(child))
	return result


func _visible_mesh_bounds(root: Node3D, space: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for mesh: MeshInstance3D in _meshes_below(root):
		if not mesh.is_visible_in_tree():
			continue
		var transform: Transform3D = space.global_transform.affine_inverse() * mesh.global_transform
		if root is PersonView and mesh.skin != null:
			# This unchanged pre-existing diagnostic skins imported vertices; rest AABBs cannot measure a walk pose.
			var posed: Dictionary = SeatedHeadGeometry.skin_vertices(mesh, (root as PersonView)._skeleton)
			assert_eq(posed["error"], "")
			for vertex: Vector3 in posed["vertices"]:
				var point: Vector3 = transform * vertex
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
		else:
			var actual: AABB = transform * mesh.get_aabb()
			bounds = actual if first else bounds.merge(actual)
			first = false
	assert_false(first, "the actor supplies actual visible mesh geometry")
	return bounds


func _cell_rect(cells: Rect2i) -> Rect2:
	return Rect2(Vector2(cells.position) * 0.5, Vector2(cells.size) * 0.5)


func _xz_rect(bounds: AABB) -> Rect2:
	return Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))


func _positive_overlap(a: Rect2, b: Rect2) -> bool:
	return minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x) > 0.0001 \
		and minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y) > 0.0001


func _assert_mesh_triangles_avoid(mesh: MeshInstance3D, space: Node3D, forbidden: Array[Rect2]) -> int:
	var transform: Transform3D = space.global_transform.affine_inverse() * mesh.global_transform
	var count: int = 0
	for surface: int in mesh.mesh.get_surface_count():
		if mesh.mesh is ArrayMesh and (mesh.mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var size: int = indices.size() if not indices.is_empty() else vertices.size()
		for offset: int in range(0, size - 2, 3):
			var points: Array[Vector2] = []
			for corner: int in 3:
				var index: int = indices[offset + corner] if not indices.is_empty() else offset + corner
				var vertex: Vector3 = transform * vertices[index]
				points.append(Vector2(vertex.x, vertex.z))
			for rect: Rect2 in forbidden:
				assert_false(_triangle_overlaps_rect(points, rect), "actual static triangle avoids the reserve and existing native surface")
			count += 1
	return count


func _triangle_overlaps_rect(points: Array[Vector2], rect: Rect2) -> bool:
	var axes: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN]
	for index: int in 3:
		var edge: Vector2 = points[(index + 1) % 3] - points[index]
		if edge.length_squared() > 0.00000001:
			axes.append(Vector2(-edge.y, edge.x).normalized())
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for axis: Vector2 in axes:
		var a_low: float = INF
		var a_high: float = -INF
		var b_low: float = INF
		var b_high: float = -INF
		for point: Vector2 in points:
			a_low = minf(a_low, point.dot(axis))
			a_high = maxf(a_high, point.dot(axis))
		for point: Vector2 in corners:
			b_low = minf(b_low, point.dot(axis))
			b_high = maxf(b_high, point.dot(axis))
		if minf(a_high, b_high) - maxf(a_low, b_low) <= 0.0001:
			return false
	return true


func test_real_main_keeps_the_original_default_shop_framing_and_reserves_the_maximum_lease() -> void:
	await _start()
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	assert_eq(rig.initial_focus, Vector2(3.5, 3.0))
	assert_eq(rig.initial_zoom, 12.0)
	assert_eq(rig.initial_yaw_degrees, 45.0)
	assert_almost_eq(rig.pitch_degrees, 54.7356, 0.0001)
	assert_eq(rig.position, Vector3(3.5, 0.0, 3.0))
	assert_almost_eq(rig.rotation.y, PI / 4.0, 0.0001)
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_eq(camera.size, 12.0)
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var layout: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
	var lease: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
	var expected: Rect2i = ShopFootprint.from_layout(lease.layout_for(layout, 2)).lot
	assert_true(view.neighbourhood_reserved_lot().encloses(expected))
	for cell: Vector2i in view.world.grid.cells():
		if view.world.grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			assert_true(view.neighbourhood_reserved_lot().has_point(cell))


func test_shop_world_replacement_frees_old_neighbourhood_and_null_world_leaves_no_stale_actor_roots() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var old: NeighbourhoodDressing = view.neighbourhood_dressing
	assert_not_null(old)
	if old == null:
		return
	var old_root: WeakRef = weakref(old)
	var actors: Array[WeakRef] = []
	for person: PersonView in old.pedestrians:
		actors.append(weakref(person))
	var replacement_grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))
	var replacement: SimWorld = SimWorld.new(replacement_grid)
	view.show_world(replacement, Rect2i(-2, -2, 12, 9))
	await _frames(2)
	assert_null(old_root.get_ref())
	for person: WeakRef in actors:
		assert_null(person.get_ref())
	assert_true(view.world == replacement)
	assert_eq(view.neighbourhood_dressing.pedestrians.size(), 3)
	assert_true(view.agent_nodes.is_empty())
	var roots: int = 0
	for node: Node in _nodes_below(view):
		if node is NeighbourhoodDressing:
			roots += 1
	assert_eq(roots, 1)
	view.show_world(null)
	await _frames(2)
	assert_true(view.neighbourhood_dressing == null or not is_instance_valid(view.neighbourhood_dressing))
	for node: Node in _nodes_below(view):
		assert_false(node is NeighbourhoodDressing)
		assert_false(node is PersonView)


func test_real_back_door_alley_and_bought_floor_rebuild_preserve_actors_and_exclude_the_actual_native_paths() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dressing: NeighbourhoodDressing = view.neighbourhood_dressing
	assert_not_null(dressing)
	if dressing == null:
		return
	var actors: Array[int] = []
	for person: PersonView in dressing.pedestrians:
		actors.append(person.get_instance_id())
	var car_id: int = dressing.car.get_instance_id()
	var elapsed: float = dressing.display_seconds
	var pads: Array[AABB] = view.room_dressing.native_pavement_bounds()
	assert_true(_main.call("shop_walls", {Vector3i(13, 6, SimGrid.EDGE_WEST): SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	assert_true(_main.call("shop_floor", [Vector2i(-1, 7), Vector2i(-1, 8), Vector2i(-1, 9)] as Array[Vector2i], true))
	assert_eq(view.world.grid.terrain(Vector2i(-1, 8)), SimGrid.Terrain.FLOOR)
	assert_eq(view.world.grid.segment(Vector3i(13, 6, SimGrid.EDGE_WEST)), SimGrid.Segment.DOORWAY,
		"unrelated west growth preserves the installed east doorway")
	assert_eq(WallRules.back_door_side(view.world.grid, Vector3i(13, 6, SimGrid.EDGE_WEST)), Vector2i.RIGHT,
		"the surviving opening is still an actual outside back door")
	assert_true(view.neighbourhood_dressing == dressing)
	assert_true(dressing.display_seconds >= elapsed)
	assert_eq(dressing.car.get_instance_id(), car_id)
	for index: int in 3:
		assert_eq(dressing.pedestrians[index].get_instance_id(), actors[index])
	assert_eq(view.room_dressing.native_pavement_bounds(), pads, "the existing entrance pads keep their real bounds")
	var paths: Array[PropView] = view.segment_view.path_tiles()
	assert_false(paths.is_empty(), "a real installed back door supplies actual native alley geometry")
	var forbidden: Array[Rect2] = []
	for path: PropView in paths:
		forbidden.append(_xz_rect(view.global_transform.affine_inverse() * path.global_transform * path.get_combined_aabb()))
	for cell: Vector2i in view.world.grid.cells():
		if view.world.grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			forbidden.append(_cell_rect(Rect2i(cell, Vector2i.ONE)))
	var count: int = 0
	for mesh: MeshInstance3D in _meshes_below(dressing.static_root):
		count += _assert_mesh_triangles_avoid(mesh, view, forbidden)
	assert_true(count > 100)
	var snapshot: Dictionary = _isolation_snapshot(view.world)
	dressing.advance_display(5.0)
	dressing.rebuild()
	assert_eq(_isolation_snapshot(view.world), snapshot)
