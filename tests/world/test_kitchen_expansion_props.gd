extends TestCase
## New kit wrappers and resource contracts. Import, pixels and balance remain
## separate validation stages; fixture checks do not author scale exceptions.

const IDS: Array[StringName] = [&"fryer", &"oven", &"prep_cabinet", &"corner_cabinet"]
const LEVELS: Array[int] = [2, 4, 5, 6]
const STATION_TYPES: Array[StringName] = [&"fryer", &"oven", &"prep_counter", &""]
const MODELS: Dictionary = {
	&"fryer": {"ElectricStove": "kitchenStoveElectric", "Cabinet": "kitchenCabinet"},
	&"oven": {"Stove": "kitchenStove", "DrawerCabinet": "kitchenCabinetDrawer"},
	&"prep_cabinet": {"Cabinet": "kitchenCabinetDrawer"},
	&"corner_cabinet": {"Cabinet": "kitchenCabinetCornerInner"},
}
const STARTER: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _views: Array[PropView] = []


func after_each() -> void:
	for view: PropView in _views:
		view.free()
	_views.clear()


func test_new_kitchen_definitions_spread_unlocks_and_keep_station_and_layout_roles_distinct() -> void:
	for index: int in IDS.size():
		var definition: ItemDef = _definition(IDS[index])
		assert_eq(definition.id, IDS[index])
		assert_eq(definition.unlock_level, LEVELS[index])
		assert_eq(definition.station_type, STATION_TYPES[index])
		assert_true(definition.price > 0, "new equipment has an authored purchase price")
		assert_eq(definition.quality_bonus, 0.0, "content adds no dish-quality calculation")
		assert_true(definition.solid)
		assert_true(definition.placement_layer_valid())
		assert_true(definition.blocking_cells_valid())
		assert_true(definition.seat_cells.is_empty())
		var expected_footprint: Vector2i = Vector2i(2, 1) if definition.id in [&"fryer", &"oven"] else Vector2i.ONE
		assert_eq(definition.footprint, expected_footprint)
		if definition.id == &"corner_cabinet":
			assert_eq(definition.category, ItemDef.Category.DECOR)
			assert_true(definition.work_cells.is_empty(), "the corner piece is layout furniture, not an invented station")
			assert_eq(definition.capacity, 0, "the layout cabinet claims no ingredient storage capacity")
		else:
			assert_eq(definition.category, ItemDef.Category.STATION)
			assert_eq(definition.work_cells, [Vector2i(0, -1)] as Array[Vector2i])
			assert_eq(definition.capacity, 1)
		assert_eq(definition.view_scene.resource_path, "res://assets/props/%s.tscn" % definition.id)


func test_new_station_work_cells_are_clear_and_reachable_at_every_grid_rotation() -> void:
	for id: StringName in IDS:
		var definition: ItemDef = _definition(id)
		if definition.category != ItemDef.Category.STATION:
			continue
		for turns: int in range(4):
			var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
			assert_true(grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY))
			var placed: PlacedItem = grid.place_def(definition, Vector2i(4, 4), turns)
			assert_not_null(placed, "%s rotation %d" % [id, turns])
			assert_false(placed.work_cells.is_empty())
			for cell: Vector2i in placed.work_cells:
				assert_false(placed.cells.has(cell), "work cells lie in the aisle, outside the solid equipment")
				assert_true(grid.is_walkable(cell))
				assert_true(grid.is_reachable(Vector2i.ZERO, cell), "%s has an accessible front at rotation %d" % [id, turns])


func test_expansion_wrappers_use_only_declared_kit_parts_and_the_shared_uniform_furniture_scale() -> void:
	for id: StringName in IDS:
		var definition: ItemDef = _definition(id)
		var view: PropView = definition.view_scene.instantiate() as PropView
		assert_not_null(view)
		_views.append(view)
		view.prepare()
		assert_eq(view.footprint, definition.footprint)
		var parts: Dictionary = MODELS[id]
		assert_eq(view.get_child_count(), parts.size())
		for part_name: String in parts:
			var part: Node3D = view.get_node(NodePath(part_name)) as Node3D
			var art: Node3D = part.get_node("Art") as Node3D
			var model: Node3D = art.get_node("Model") as Node3D
			assert_eq(model.scene_file_path, "res://assets/kenney/furniture/%s.glb" % parts[part_name])
			assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
			assert_almost_eq(absf(art.rotation.y), PI)
			assert_false(part.has_meta(&"art_group"), "the appliance and its counter both use Furniture Kit scale")
		assert_true(view.body_surface_count() > 0, "only existing wood surfaces may receive cabinet paint")


func test_new_kitchen_content_is_not_placed_in_the_default_shop() -> void:
	for placement: ShopPlacement in STARTER.placements:
		assert_false(IDS.has(placement.item_id), "new kitchen choices do not change the starter inventory")


func _definition(id: StringName) -> ItemDef:
	var definition: ItemDef = load("res://data/items/%s.tres" % id) as ItemDef
	assert_not_null(definition, String(id))
	return definition
