extends TestCase
## Scene geometry and read-only synchronization; rendering needs a playtest.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
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
		if (item.def as ItemDef).category != ItemDef.Category.DOOR:
			expected += 1
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
	assert_true(_view.item_nodes[tables[0].id].material_override == _view.item_nodes[tables[1].id].material_override)
	assert_eq(world.now, 0, "view never advances simulation")


func test_all_rotations_match_grid_bounds() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(14, 14))
	var definition: ItemDef = ItemDef.new()
	definition.footprint = Vector2i(3, 2)
	definition.category = ItemDef.Category.TABLE
	for turn: int in range(4):
		grid.place_def(definition, Vector2i(1 + turn * 3, 1), turn)
	_show(SimWorld.new(grid))
	for item: PlacedItem in grid.items():
		var node: MeshInstance3D = _view.item_nodes[item.id]
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
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var agent: StaffAgent = StaffAgent.new(&"cook")
	agent.cell = Vector2i(1, 1)
	agent.path = [Vector2i(1, 1), Vector2i(2, 1)]
	agent.path_index = 1
	agent.move_progress = 0.25
	world.add_agent(agent)
	_show(world)
	var node: MeshInstance3D = _view.agent_nodes[agent.id]
	var expected: Vector3 = GridMath.cell_to_world(agent.cell).lerp(GridMath.cell_to_world(agent.next_cell()), 0.25) + Vector3(0, 0.875, 0)
	assert_eq(node.position, expected)
	assert_almost_eq((node.mesh as CapsuleMesh).height, 1.75)
	assert_almost_eq((node.mesh as CapsuleMesh).radius, 0.25)
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
