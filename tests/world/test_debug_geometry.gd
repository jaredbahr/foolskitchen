extends TestCase
## Geometry assertions use the meshes actually built, without running the sim.

var _geometry: DebugGeometry
var _world: SimWorld
var _agent: StaffAgent
var _positions: Dictionary[int, Vector3] = {}
var _colors: Dictionary[int, Color] = {}


func before_each() -> void:
	_geometry = DebugGeometry.new()
	_world = SimWorld.new(SimGrid.new(Vector2i(5, 5)))
	_agent = StaffAgent.new(&"server")
	_agent.cell = Vector2i(1, 0)
	_world.add_agent(_agent)
	_agent.path = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 1)]
	_agent.path_index = 2
	_agent.move_progress = 0.3
	_positions = {_agent.id: Vector3(0.9, 0.0, 0.25)}
	_colors = {_agent.id: Color("408b85")}


func after_each() -> void:
	_geometry.free()
	_world = null
	_agent = null
	_positions.clear()
	_colors.clear()


func test_null_and_empty_worlds_have_no_visible_selection_or_paths() -> void:
	_geometry.update_geometry(null, _positions, _colors, _agent.id, true)
	assert_false(_ring().visible)
	assert_eq(_paths().get_child_count(), 0)
	_geometry.update_geometry(SimWorld.new(SimGrid.new()), _positions, _colors, _agent.id, true)
	assert_false(_ring().visible)
	assert_eq(_paths().get_child_count(), 0)


func test_selection_ring_uses_drawn_position_and_stays_visible_with_paths_off() -> void:
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, false)
	assert_true(_ring().visible)
	_assert_vector(_ring().position, Vector3(0.9, DebugGeometry.RING_HEIGHT, 0.25))
	assert_true(_ring().mesh is TorusMesh)
	var material: StandardMaterial3D = _ring().material_override as StandardMaterial3D
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.albedo_color, DebugGeometry.RING_COLOR)
	assert_eq(_paths().get_child_count(), 0)
	_positions[_agent.id] = Vector3(1.1, 0.0, 0.25)
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, false)
	_assert_vector(_ring().position, Vector3(1.1, DebugGeometry.RING_HEIGHT, 0.25))
	_geometry.update_geometry(_world, _positions, _colors, -1, false)
	assert_false(_ring().visible)


func test_paths_start_at_drawn_foot_and_include_only_remaining_cells_in_agent_color() -> void:
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	assert_eq(_paths().get_child_count(), 1)
	var node: MeshInstance3D = _paths().get_child(0) as MeshInstance3D
	var mesh: ImmediateMesh = node.mesh as ImmediateMesh
	assert_eq(mesh.get_surface_count(), 1)
	# ImmediateMesh retains its AABB locally, including with a headless renderer.
	# Check both the exact line commands and the bounds of the mesh built from them.
	var vertices: PackedVector3Array = _geometry._remaining_segments(_agent, _positions[_agent.id])
	assert_eq(vertices.size(), 4)
	_assert_vector(vertices[0], Vector3(0.9, DebugGeometry.PATH_HEIGHT, 0.25))
	_assert_vector(vertices[1], Vector3(1.25, DebugGeometry.PATH_HEIGHT, 0.25))
	_assert_vector(vertices[2], Vector3(1.25, DebugGeometry.PATH_HEIGHT, 0.25))
	_assert_vector(vertices[3], Vector3(1.75, DebugGeometry.PATH_HEIGHT, 0.75))
	var bounds: AABB = mesh.get_aabb()
	_assert_vector(bounds.position, vertices[0])
	assert_almost_eq(bounds.end.x, 1.75)
	assert_almost_eq(bounds.end.z, 0.75)
	var material: StandardMaterial3D = node.material_override as StandardMaterial3D
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.albedo_color, _colors[_agent.id])
	# Reusing the view must replace surfaces rather than retaining old routes.
	_agent.path_index = 3
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	assert_eq(_paths().get_child_count(), 1)
	assert_eq(mesh.get_surface_count(), 1)
	vertices = _geometry._remaining_segments(_agent, _positions[_agent.id])
	assert_eq(vertices.size(), 2)
	_assert_vector(vertices[1], Vector3(1.75, DebugGeometry.PATH_HEIGHT, 0.75))


func test_hiding_paths_missing_snapshots_removal_and_rebind_clear_old_geometry() -> void:
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, false)
	assert_true(_ring().visible)
	assert_eq(_paths().get_child_count(), 0)
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	_positions.clear()
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	assert_false(_ring().visible)
	assert_eq(_paths().get_child_count(), 0)
	_positions[_agent.id] = Vector3(0.9, 0.0, 0.25)
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	_world.remove_agent(_agent)
	# A stale snapshot must not keep a removed agent visible.
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	assert_false(_ring().visible)
	assert_eq(_paths().get_child_count(), 0)
	_geometry.update_geometry(SimWorld.new(SimGrid.new()), _positions, _colors, _agent.id, true)
	_geometry.update_geometry(null, _positions, _colors, _agent.id, true)
	assert_false(_ring().visible)
	assert_eq(_paths().get_child_count(), 0)


func test_finished_paths_clear_and_geometry_never_edits_source_snapshots_or_sim() -> void:
	var path_before: Array[Vector2i] = _agent.path.duplicate()
	var positions_before: Dictionary[int, Vector3] = _positions.duplicate()
	var colors_before: Dictionary[int, Color] = _colors.duplicate()
	var clock_before: Dictionary = _world.clock.to_dict().duplicate(true)
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	assert_eq(_agent.path, path_before)
	assert_eq(_agent.path_index, 2)
	assert_almost_eq(_agent.move_progress, 0.3)
	assert_eq(_agent.cell, Vector2i(1, 0))
	assert_eq(_positions, positions_before)
	assert_eq(_colors, colors_before)
	assert_eq(_world.now, 0)
	assert_eq(_world.clock.to_dict(), clock_before)
	assert_eq(_world.board.active_count(), 0)
	assert_true(_world.event_log.is_empty())
	_agent.path_index = _agent.path.size()
	_geometry.update_geometry(_world, _positions, _colors, _agent.id, true)
	assert_eq(_paths().get_child_count(), 0)
	assert_true(_ring().visible)


func _ring() -> MeshInstance3D:
	return _geometry.get_node("SelectionRing") as MeshInstance3D


func _paths() -> Node3D:
	return _geometry.get_node("Paths") as Node3D


func _assert_vector(actual: Vector3, expected: Vector3) -> void:
	assert_almost_eq(actual.x, expected.x)
	assert_almost_eq(actual.y, expected.y)
	assert_almost_eq(actual.z, expected.z)
