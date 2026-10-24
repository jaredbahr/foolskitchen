extends TestCase
## Scene geometry and read-only synchronization; rendering needs a playtest.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CLEANLINESS_TUNING: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")
var _view: ShopView


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()


func test_tier_one_geometry_counts_and_shared_color_materials() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all().size(), 0)
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(LAYOUT, content, errors)
	assert_eq(errors.size(), 0)
	_show(world)
	var expected: int = 0
	for item: PlacedItem in world.grid.items():
		expected += 1
		assert_not_null(_view.item_nodes[item.id].prop, "authored furniture and doors use their wrapper")
	assert_eq(_view.item_nodes.size(), expected)
	var walls: int = 0
	var floors: int = 0
	for y: int in range(world.grid.size.y):
		for x: int in range(world.grid.size.x):
			var terrain: SimGrid.Terrain = world.grid.terrain(Vector2i(x, y))
			if terrain == SimGrid.Terrain.WALL:
				walls += 1
			elif terrain == SimGrid.Terrain.FLOOR or terrain == SimGrid.Terrain.ENTRY:
				floors += 1
	assert_eq(_view.get_node("Walls").get_child_count(), walls)
	assert_eq(_view.floor_mesh.mesh.get_faces().size(), floors * 6)
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	assert_true(_view.item_nodes[tables[0].id].primary_body_material() == _view.item_nodes[tables[1].id].primary_body_material())
	assert_eq(world.now, 0, "view never advances simulation")


func test_paint_preview_reuses_materials_and_restores_room_colours() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(LAYOUT, content, errors)
	_show(world)
	_view.set_paint(content, &"sage", &"walnut")
	assert_eq(_view.wall_cell_at_ray(Vector3(0.25, 4.0, 0.25), Vector3.DOWN), Vector2i.ZERO)
	var wall: MeshInstance3D = _view.get_node("Walls").get_child(0) as MeshInstance3D
	var wall_material: Material = wall.material_override
	assert_eq((wall_material as StandardMaterial3D).albedo_color, content.swatch(&"sage").color)
	var floor_shader: ShaderMaterial = _view.floor_mesh.material_override as ShaderMaterial
	assert_eq(floor_shader.get_shader_parameter("floor_color"), content.swatch(&"walnut").color)
	_view.preview_paint(&"wall", -1, &"butter")
	assert_eq((wall.material_override as StandardMaterial3D).albedo_color, content.swatch(&"butter").color)
	_view.clear_paint_preview()
	assert_true(wall.material_override == wall_material)
	_view.preview_paint(&"floor", -1, &"cream")
	assert_eq(floor_shader.get_shader_parameter("floor_color"), content.swatch(&"cream").color)
	_view.clear_paint_preview()
	assert_eq(floor_shader.get_shader_parameter("floor_color"), content.swatch(&"walnut").color)
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	tables[0].swatch_id = &"terracotta"
	tables[1].swatch_id = &"terracotta"
	_view.set_paint(content, &"sage", &"walnut")
	var first_material: BaseMaterial3D = _view.item_nodes[tables[0].id].primary_body_material()
	var second_material: BaseMaterial3D = _view.item_nodes[tables[1].id].primary_body_material()
	assert_eq(first_material.albedo_color, content.swatch(&"terracotta").color)
	assert_eq(second_material.albedo_color, first_material.albedo_color)
	assert_true(first_material != second_material, "body tint copies stay local to each model")
	_view.preview_paint(&"item", tables[0].id, &"sage")
	assert_eq(first_material.albedo_color, content.swatch(&"sage").color)
	assert_eq(second_material.albedo_color, content.swatch(&"terracotta").color)
	_view.clear_paint_preview()
	assert_eq(first_material.albedo_color, content.swatch(&"terracotta").color)
	assert_eq(errors, [] as Array[String])


func test_table_paint_tints_built_in_chair_frames_and_preserves_cushions() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(6, 6)))
	var table: PlacedItem = world.grid.place_def(content.item(&"table_2"), Vector2i(2, 2))
	_show(world)
	var snapshots: Array[Dictionary] = _chair_surfaces(_view.item_nodes[table.id].prop)
	var body_count: int = 0
	var cushion_count: int = 0
	for entry: Dictionary in snapshots:
		if entry["body"]:
			body_count += 1
		else:
			cushion_count += 1
	assert_true(body_count > 0 and cushion_count > 0, "real chair frames and cushions must both be tested")
	table.swatch_id = &"terracotta"
	_view.set_paint(content, &"", &"")
	_assert_chair_tint(snapshots, content.swatch(&"terracotta").color)
	_view.preview_paint(&"item", table.id, &"sage")
	_assert_chair_tint(snapshots, content.swatch(&"sage").color)
	assert_eq(table.swatch_id, &"terracotta", "hover only changes presentation")
	_view.clear_paint_preview()
	_assert_chair_tint(snapshots, content.swatch(&"terracotta").color)
	table.swatch_id = &""
	_view.set_paint(content, &"", &"")
	for entry: Dictionary in snapshots:
		var mesh_node: MeshInstance3D = entry["mesh"]
		assert_eq(mesh_node.get_active_material(entry["index"]), entry["source"], "clearing table paint restores each authored chair surface")
	assert_eq(world.now, 0)


func _chair_surfaces(view: PropView) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child: Node in view.get_children():
		if not child.has_meta(&"seat_cell"):
			continue
		var meshes: Array[MeshInstance3D] = []
		_collect_chair_meshes(child, meshes)
		for mesh_node: MeshInstance3D in meshes:
			for index: int in range(mesh_node.mesh.get_surface_count()):
				var source: BaseMaterial3D = mesh_node.get_active_material(index) as BaseMaterial3D
				result.append({"mesh": mesh_node, "index": index, "source": source, "body": source.resource_name == "wood"})
	return result


func _collect_chair_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		result.append(mesh_node)
	for child: Node in node.get_children():
		_collect_chair_meshes(child, result)


func _assert_chair_tint(surfaces: Array[Dictionary], color: Color) -> void:
	for entry: Dictionary in surfaces:
		var mesh_node: MeshInstance3D = entry["mesh"]
		var active: BaseMaterial3D = mesh_node.get_active_material(entry["index"]) as BaseMaterial3D
		if entry["body"]:
			assert_eq(active.albedo_color, color)
			assert_true(active != entry["source"], "paint keeps a private body material")
		else:
			assert_eq(active, entry["source"], "cushions keep their authored material through paint and preview")


func test_floor_dirt_decals_reuse_geometry_and_follow_cleanliness_without_changing_grid() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var tuning: CleanlinessTuning = CLEANLINESS_TUNING.duplicate() as CleanlinessTuning
	tuning.seat_departure_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 78027
	var dirt: CleanlinessState = CleanlinessState.new(world.grid, tuning, random)
	var first: Vector2i = Vector2i(1, 1)
	var second: Vector2i = Vector2i(2, 2)
	assert_true(dirt.try_spawn_at_departed_seat(first))
	_show(world)
	assert_true(_view.dirt_nodes.is_empty(), "the view needs an explicit state binding")
	_view.bind_cleanliness(dirt)
	assert_eq(_view.dirt_nodes.size(), 1)
	var first_node: MeshInstance3D = _view.dirt_nodes[first]
	assert_eq(first_node.position, GridMath.cell_to_world(first) + Vector3(0.0, 0.015, 0.0))
	assert_true(first_node.mesh is ArrayMesh)
	assert_almost_eq(first_node.mesh.get_aabb().size.y, 0.0)
	var decal_bounds: AABB = first_node.mesh.get_aabb()
	assert_true(decal_bounds.size.x >= 0.35 and decal_bounds.size.z >= 0.3,
		"spots need enough floor coverage to read at the normal camera zoom")
	var decal_faces: PackedVector3Array = first_node.mesh.get_faces()
	for vertex: Vector3 in decal_faces:
		assert_true(vertex.length() <= 0.25, "the decal stays inside its half-metre cell")
	for index: int in range(0, decal_faces.size(), 3):
		var edge_one: Vector3 = decal_faces[index + 1] - decal_faces[index]
		var edge_two: Vector3 = decal_faces[index + 2] - decal_faces[index]
		assert_true(edge_one.cross(edge_two).y < 0.0,
			"the shaded top is a clockwise front face with upward lighting normals")
	var dirt_material: StandardMaterial3D = first_node.material_override as StandardMaterial3D
	assert_eq(dirt_material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL,
		"dirt takes the same scene lighting as the rest of the shop")
	assert_eq(ShopView.DIRT_SWATCH.id, &"walnut", "use the approved warm dark-brown swatch")
	assert_almost_eq(dirt_material.roughness, 1.0)
	assert_almost_eq(dirt_material.metallic_specular, 0.0)
	assert_eq((first_node.material_override as StandardMaterial3D).albedo_color,
		ShopView.DIRT_SWATCH.color)
	assert_true(world.grid.is_walkable(first))
	for _frame: int in range(4):
		_view._process(0.1)
		assert_true(_view.dirt_nodes[first] == first_node, "an unchanged spot keeps its native mesh")
	assert_true(dirt.try_spawn_at_departed_seat(second))
	_view._process(0.1)
	assert_eq(_view.dirt_nodes.size(), 2)
	assert_true(_view.dirt_nodes[second].mesh == first_node.mesh)
	assert_true(_view.dirt_nodes[second].material_override == first_node.material_override)
	assert_true(dirt.clear_spot(first))
	_view._process(0.1)
	assert_false(_view.dirt_nodes.has(first))
	assert_false(is_instance_valid(first_node))
	assert_eq(world.now, 0, "drawing does not advance the simulation")
	_view.show_world(null)
	assert_true(_view.dirt_nodes.is_empty())
	assert_null(_view._cleanliness)


func test_dirt_decals_survive_paint_and_wall_changes_but_hide_on_blocked_floor() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(3, 3)))
	var tuning: CleanlinessTuning = CLEANLINESS_TUNING.duplicate() as CleanlinessTuning
	tuning.seat_departure_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 78028
	var dirt: CleanlinessState = CleanlinessState.new(world.grid, tuning, random)
	var cell: Vector2i = Vector2i(1, 1)
	assert_true(dirt.try_spawn_at_departed_seat(cell))
	_show(world)
	_view.bind_cleanliness(dirt)
	var node: MeshInstance3D = _view.dirt_nodes[cell]
	_view.set_paint(content, &"sage", &"walnut")
	_view.set_wall_mode(ShopView.WallMode.DOWN)
	_view._process(0.1)
	assert_true(_view.dirt_nodes[cell] == node)
	assert_eq((node.material_override as StandardMaterial3D).albedo_color,
		ShopView.DIRT_SWATCH.color)
	assert_true(world.grid.set_terrain(cell, SimGrid.Terrain.WALL))
	assert_false(_view.dirt_nodes.has(cell), "only current walkable floor receives a decal")
	assert_false(is_instance_valid(node))
	assert_true(dirt.has_spot(cell), "the view cannot alter simulation dirt")


func test_cleaner_capsule_uses_curated_sage_instead_of_a_guest_colour() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(3, 3)))
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner", 3)
	cleaner.cell = Vector2i(1, 1)
	world.add_agent(cleaner)
	var guest: SimAgent = SimAgent.new()
	guest.role = &"customer"
	guest.cell = Vector2i(2, 1)
	world.add_agent(guest)
	_show(world)
	var colors: Dictionary[int, Color] = _view.drawn_agent_colors()
	assert_eq(colors[cleaner.id], ShopView.CLEANER_SWATCH.color)
	assert_false(ShopView.CUSTOMER_COLORS.has(colors[cleaner.id]))
	assert_ne(colors[cleaner.id], colors[guest.id])
	var body: MeshInstance3D = _view.agent_nodes[cleaner.id] as MeshInstance3D
	assert_true(body.mesh is CapsuleMesh)
	assert_eq((body.material_override as StandardMaterial3D).albedo_color,
		ShopView.CLEANER_SWATCH.color)


func test_all_rotations_match_grid_bounds() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(14, 14))
	var definition: ItemDef = ItemDef.new()
	definition.footprint = Vector2i(3, 2)
	definition.category = ItemDef.Category.TABLE
	for turn: int in range(4):
		grid.place_def(definition, Vector2i(1 + turn * 3, 1), turn)
	_show(SimWorld.new(grid))
	for item: PlacedItem in grid.items():
		var node: ItemVisual = _view.item_nodes[item.id]
		var bounds: AABB = node.transform * node.get_aabb()
		var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, item.quarter_turns)
		assert_almost_eq(bounds.position.x, item.origin.x * 0.5)
		assert_almost_eq(bounds.position.z, item.origin.y * 0.5)
		assert_almost_eq(bounds.size.x, footprint.x * 0.5)
		assert_almost_eq(bounds.size.z, footprint.y * 0.5)
		assert_eq(node.get_meta("item_id"), item.id)
		assert_almost_eq(node.rotation.y, -item.quarter_turns * PI / 2.0)


func test_placement_removal_and_rebinding_disconnect_old_grid() -> void:
	var first: SimWorld = SimWorld.new(SimGrid.new(Vector2i(6, 6)))
	_show(first)
	var definition: ItemDef = ItemDef.new()
	var item: PlacedItem = first.grid.place_def(definition, Vector2i(1, 1))
	assert_true(_view.item_nodes.has(item.id))
	assert_true(first.grid.remove(item.id))
	assert_false(_view.item_nodes.has(item.id))
	var callback: Callable = Callable(_view, "_on_cells_changed")
	_view.show_world(SimWorld.new(SimGrid.new()))
	assert_false(first.grid.cells_changed.is_connected(callback))
	first.grid.place_def(definition, Vector2i(2, 2))
	assert_eq(_view.item_nodes.size(), 0)


func test_agents_interpolate_and_reconcile_without_writing_sim() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var agent: StaffAgent = StaffAgent.new(&"cook")
	agent.cell = Vector2i(1, 1)
	agent.path = [Vector2i(1, 1), Vector2i(2, 1)]
	agent.path_index = 1
	agent.move_progress = 0.25
	world.add_agent(agent)
	_show(world)
	assert_true(_view.is_inside_tree())
	var node: PersonView = _view.agent_nodes[agent.id] as PersonView
	var expected: Vector3 = GridMath.cell_to_world(agent.cell).lerp(GridMath.cell_to_world(agent.next_cell()), 0.25)
	assert_eq(node.position, expected)
	assert_eq(node.model_name(), PersonPresentation.COOK_MODEL)
	assert_eq(node.current_clip(), &"walk")
	assert_true(node.get_meta("person_ready"))
	assert_almost_eq((node.get_node("ModelPivot") as Node3D).scale.x, ArtScale.CHARACTER_SCALE)
	_view._process(0.1)
	assert_true(node.rotation.y < 0.0)
	assert_eq(agent.move_progress, 0.25)
	assert_eq(world.now, 0)
	var server: StaffAgent = StaffAgent.new(&"server")
	world.add_agent(server)
	_view._process(0.1)
	assert_eq(_view.agent_nodes.size(), 2)
	world.remove_agent(agent)
	_view._process(0.1)
	assert_false(_view.agent_nodes.has(agent.id))


func test_doors_are_not_rendered_and_terrain_changes_rebuild_floor() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(2, 2)))
	var door: ItemDef = ItemDef.new()
	door.category = ItemDef.Category.DOOR
	world.grid.place_def(door, Vector2i.ZERO)
	_show(world)
	assert_eq(_view.item_nodes.size(), 0)
	world.grid.set_terrain(Vector2i(1, 1), SimGrid.Terrain.WALL)
	assert_eq(_view.get_node("Walls").get_child_count(), 1)
	assert_eq(_view.floor_mesh.mesh.get_faces().size(), 18)


func test_unparent_cleanup_and_show_world_reconnect_are_idempotent() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new())
	_show(world)
	var changed: Callable = Callable(_view, "_on_cells_changed")
	var removed: Callable = Callable(_view, "_on_item_removed")
	assert_true(world.grid.cells_changed.is_connected(changed))
	_view.get_parent().remove_child(_view)
	assert_false(world.grid.cells_changed.is_connected(changed))
	assert_false(world.grid.item_removed.is_connected(removed))
	_view.call("_exit_tree")
	_view.show_world(world)
	_view.show_world(world)
	assert_true(world.grid.cells_changed.is_connected(changed))
	assert_true(world.grid.item_removed.is_connected(removed))
	_view.show_world(null)
	assert_null(_view.floor_mesh)
	assert_false(world.grid.cells_changed.is_connected(changed))
	assert_false(world.grid.item_removed.is_connected(removed))


func _show(world: SimWorld) -> void:
	_view = VIEW.instantiate() as ShopView
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_view)
	_view.show_world(world)
