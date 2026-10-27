extends TestCase
## New kit wrappers and resource contracts. Import, pixels and balance remain
## separate validation stages; fixture checks do not author scale exceptions.

const IDS: Array[StringName] = [&"fryer", &"oven", &"prep_cabinet", &"corner_cabinet"]
const LEVELS: Dictionary[StringName, int] = {
	&"fryer": 2, &"corner_cabinet": 2, &"oven": 3, &"prep_cabinet": 4,
}
const STATION_TYPES: Dictionary[StringName, StringName] = {
	&"fryer": &"fryer", &"oven": &"oven", &"prep_cabinet": &"prep_counter", &"corner_cabinet": &"",
}
const MODELS: Dictionary = {
	&"fryer": {"ElectricStove": "kitchenStoveElectric", "Cabinet": "kitchenCabinet"},
	&"oven": {"Stove": "kitchenStove", "DrawerCabinet": "kitchenCabinetDrawer"},
	&"prep_cabinet": {"Cabinet": "kitchenCabinetDrawer"},
	&"corner_cabinet": {"Cabinet": "kitchenCabinetCornerInner"},
}
## Food Kit dressing (D19): node -> [model, the furniture part it rests on].
const FOOD: Dictionary = {
	&"fryer": {"Pan": ["frying-pan", "ElectricStove"], "FriesLeft": ["fries", "Cabinet"],
		"FriesRight": ["fries", "Cabinet"], "FriesFront": ["fries", "Cabinet"]},
	&"oven": {"Pie": ["pie", "DrawerCabinet"]},
	&"prep_cabinet": {"Board": ["cutting-board", "Cabinet"]},
	&"corner_cabinet": {},
}
const STARTER: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _views: Array[PropView] = []


func after_each() -> void:
	for view: PropView in _views:
		view.free()
	_views.clear()


func test_new_kitchen_definitions_spread_unlocks_and_keep_station_and_layout_roles_distinct() -> void:
	for id: StringName in IDS:
		var definition: ItemDef = _definition(id)
		assert_eq(definition.id, id)
		assert_eq(definition.unlock_level, LEVELS[id], String(id))
		assert_eq(definition.station_type, STATION_TYPES[id])
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
			assert_true(definition.theme_tags.is_empty(), "a plain kitchen cabinet casts no theme vote")
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
		assert_eq(view.get_child_count(), parts.size() + (FOOD[id] as Dictionary).size())
		for part_name: String in parts:
			var part: Node3D = view.get_node(NodePath(part_name)) as Node3D
			var art: Node3D = part.get_node("Art") as Node3D
			var model: Node3D = art.get_node("Model") as Node3D
			assert_eq(model.scene_file_path, "res://assets/kenney/furniture/%s.glb" % parts[part_name])
			assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
			assert_almost_eq(absf(art.rotation.y), PI)
			assert_false(part.has_meta(&"art_group"), "the appliance and its counter both use Furniture Kit scale")
		assert_true(view.body_surface_count() > 0, "only existing wood surfaces may receive cabinet paint")


func test_food_kit_dressing_rests_on_its_counter_inside_the_footprint() -> void:
	for id: StringName in IDS:
		var definition: ItemDef = _definition(id)
		var view: PropView = definition.view_scene.instantiate() as PropView
		_views.append(view)
		view.prepare()
		var food: Dictionary = FOOD[id]
		for part_name: String in food:
			var entry: Array = food[part_name]
			var part: Node3D = view.get_node(NodePath(part_name)) as Node3D
			var art: Node3D = part.get_node("Art") as Node3D
			var model: Node3D = art.get_node("Model") as Node3D
			assert_eq(model.scene_file_path, "res://assets/kenney/food/%s.glb" % entry[0])
			assert_eq(part.get_meta(&"art_group"), &"food")
			assert_eq(art.scale, Vector3.ONE * ArtScale.FOOD_SCALE, "Food Kit pieces keep the one food scale")
			var support: Node3D = view.get_node(NodePath(entry[1])) as Node3D
			assert_eq(part.get_meta(&"support"), NodePath("../" + entry[1]))
			var top: float = support.position.y + PropView._children_aabb(support).end.y
			assert_almost_eq(part.position.y, top, 0.0001, "%s sits on the counter top" % part_name)
			var bounds: AABB = PropView._children_aabb(part)
			assert_almost_eq(bounds.position.y, 0.0, 0.0001, "%s does not float or sink" % part_name)
			var support_bounds: AABB = PropView._children_aabb(support)
			var low: Vector3 = part.position + bounds.position
			var high: Vector3 = part.position + bounds.end
			assert_true(low.x >= support.position.x + support_bounds.position.x
				and high.x <= support.position.x + support_bounds.end.x
				and low.z >= support.position.z + support_bounds.position.z
				and high.z <= support.position.z + support_bounds.end.z,
				"%s %s stays on its counter's top" % [id, part_name])
		var half: Vector2 = Vector2(definition.footprint) * 0.25
		var all: AABB = view.get_combined_aabb()
		assert_true(all.position.x >= -half.x - 0.05 and all.end.x <= half.x + 0.05, String(id))
		assert_true(all.position.z >= -half.y - 0.05 and all.end.z <= half.y + 0.05, String(id))


func test_fryer_oven_and_stove_dress_differently() -> void:
	var looks: Dictionary[String, StringName] = {}
	for id: StringName in [&"stove", &"fryer", &"oven"]:
		var view: PropView = _definition(id).view_scene.instantiate() as PropView
		_views.append(view)
		var models: Array[String] = []
		for part: Node in view.get_children():
			var model: Node = part.get_node_or_null("Art/Model")
			if model != null:
				models.append(model.scene_file_path.get_file())
		models.sort()
		var look: String = ",".join(models)
		assert_false(looks.has(look), "%s looks the same as %s" % [id, looks.get(look, &"")])
		looks[look] = id


func test_new_kitchen_content_is_not_placed_in_the_default_shop() -> void:
	for placement: ShopPlacement in STARTER.placements:
		assert_false(IDS.has(placement.item_id), "new kitchen choices do not change the starter inventory")


func _definition(id: StringName) -> ItemDef:
	var definition: ItemDef = load("res://data/items/%s.tres" % id) as ItemDef
	assert_not_null(definition, String(id))
	return definition
