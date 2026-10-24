extends TestCase
## Native source integration checks; these still require real model import to run.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
var _content: ContentDB
var _view: ShopView


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_view = VIEW.instantiate() as ShopView
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_view)


func after_each() -> void:
	_view.free()
	_content = null


func test_imported_item_bounds_rotate_about_the_footprint_centre_at_floor_level() -> void:
	var definition: ItemDef = _content.item(&"fridge")
	for turns: int in range(4):
		var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
		var item: PlacedItem = world.grid.place_def(definition, Vector2i(2, 2), turns)
		_view.show_world(world)
		var node: ItemVisual = _view.item_nodes[item.id]
		assert_not_null(node.prop)
		assert_null(node.fallback)
		var bounds: AABB = _view.item_bounds(item.id)
		var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, turns)
		assert_almost_eq(bounds.position.y, 0.0)
		assert_almost_eq(bounds.get_center().x, (2.0 + footprint.x * 0.5) * GridMath.CELL_SIZE)
		assert_almost_eq(bounds.get_center().z, (2.0 + footprint.y * 0.5) * GridMath.CELL_SIZE)
		assert_true(bounds.position.x >= 1.0 - 0.05 and bounds.end.x <= 1.0 + footprint.x * GridMath.CELL_SIZE + 0.05)
		assert_true(bounds.position.z >= 1.0 - 0.05 and bounds.end.z <= 1.0 + footprint.y * GridMath.CELL_SIZE + 0.05)
		assert_eq(node.get_meta("item_id"), item.id)
		assert_eq(world.now, 0)


func test_oblique_pick_hits_the_model_before_its_different_projected_floor_cell() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	assert_true(_view.is_inside_tree(), "filtered ray tests wait for scene-tree entry")
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	var item: PlacedItem = world.grid.place_def(_content.item(&"fridge"), Vector2i(2, 2))
	_view.show_world(world)
	var bounds: AABB = _view.item_bounds(item.id)
	var top: Vector3 = bounds.get_center()
	top.y = bounds.end.y
	var origin: Vector3 = top + Vector3(0.0, 2.0, -2.0)
	var direction: Vector3 = Vector3(0.0, -1.0, 1.0)
	var floor_hit: Vector3 = Picker.floor_intersection(origin, direction)
	assert_false(item.cells.has(GridMath.world_to_cell(floor_hit)), "the floor-only picker would miss this model")
	assert_eq(_view.item_at_ray(origin, direction), item.id)
	assert_eq(_view.paint_cell_at_ray(origin, direction), item.origin)
	_view.item_nodes[item.id].hide()
	assert_eq(_view.item_at_ray(origin, direction), -1)
	_view.item_nodes[item.id].show()
	assert_eq(_view.item_at_ray(origin, Vector3.UP), -1)
	assert_eq(world.now, 0)


func test_visible_wall_blocks_model_pick_and_lowered_wall_exposes_it() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	assert_true(_view.is_inside_tree(), "filtered ray tests wait for scene-tree entry")
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	var item: PlacedItem = world.grid.place_def(_content.item(&"fridge"), Vector2i(2, 3))
	assert_true(world.grid.set_terrain(Vector2i(2, 1), SimGrid.Terrain.WALL))
	_view.show_world(world)
	var origin: Vector3 = Vector3(1.25, 1.2, 0.0)
	var direction: Vector3 = Vector3(0.0, -0.2, 1.0)
	_view.set_wall_mode(ShopView.WallMode.UP)
	assert_eq(_view.item_at_ray(origin, direction), ShopView.OCCLUDED_ITEM)
	_view.set_wall_mode(ShopView.WallMode.DOWN)
	assert_eq(_view.item_at_ray(origin, direction), item.id)
	assert_true(world.grid.terrain(Vector2i(2, 1)) == SimGrid.Terrain.WALL, "cutaway cannot alter paths")


func test_selection_uses_combined_bounds_and_follows_move_visibility_and_removal() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	var item: PlacedItem = world.grid.place_def(_content.item(&"fridge"), Vector2i(2, 2))
	_view.show_world(world)
	_view.set_selected_item(item.id)
	assert_not_null(_view.selection_outline)
	assert_eq(_view.selection_outline.get_child_count(), 12)
	assert_eq(_view.selection_outline.transform, _view.item_nodes[item.id].transform)
	var bounds: AABB = _view.item_nodes[item.id].get_aabb()
	var first_rail: MeshInstance3D = _view.selection_outline.get_child(0) as MeshInstance3D
	assert_almost_eq(first_rail.position.y, bounds.position.y)
	assert_almost_eq((first_rail.mesh as BoxMesh).size.x, bounds.size.x + BoundsOutline.WIDTH)
	assert_true(world.grid.relocate_def(item.id, Vector2i(4, 3), 1))
	assert_eq(_view.selection_outline.transform, _view.item_nodes[item.id].transform)
	assert_eq(_view.selection_outline.get_meta("item_id"), item.id)
	_view.item_nodes[item.id].hide()
	_view.refresh_item_selection()
	assert_false(_view.selection_outline.visible)
	_view.item_nodes[item.id].show()
	_view.refresh_item_selection()
	assert_true(_view.selection_outline.visible)
	assert_true(world.grid.remove(item.id))
	assert_false(_view.selection_outline.visible)
	assert_eq(world.now, 0)


func test_missing_scene_uses_the_original_box_dimensions_and_body_paint() -> void:
	var definition: ItemDef = ItemDef.new()
	definition.category = ItemDef.Category.TABLE
	definition.footprint = Vector2i(2, 1)
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(6, 6)))
	var item: PlacedItem = world.grid.place_def(definition, Vector2i(2, 2))
	_view.show_world(world)
	var node: ItemVisual = _view.item_nodes[item.id]
	assert_null(node.prop)
	assert_not_null(node.fallback)
	assert_eq(node.get_aabb().size, Vector3(1.0, ShopView.HEIGHTS[ItemDef.Category.TABLE], 0.5))
	_view.set_paint(_content, &"", &"")
	_view.preview_paint(&"item", item.id, &"sage")
	assert_eq(node.primary_body_material().albedo_color, _content.swatch(&"sage").color)
	_view.clear_paint_preview()
	assert_eq(node.primary_body_material().albedo_color, definition.placeholder_color)
