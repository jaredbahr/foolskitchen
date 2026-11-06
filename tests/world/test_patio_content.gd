extends TestCase
## Outdoor content retains approved seat geometry and uses private kit colours.

const SOURCES: Dictionary[StringName, StringName] = {
	&"patio_table_2": &"table_2",
	&"patio_chair": &"wooden_chair",
	&"patio_waiting_bench": &"waiting_bench",
}


func test_outdoor_definitions_reuse_existing_geometry_prices_and_safe_default_look() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var shared_look: ItemVariant = load("res://data/variants/patio_dark_metal.tres") as ItemVariant
	assert_true(shared_look.valid())
	for id: StringName in SOURCES:
		var definition: ItemDef = content.item(id)
		var source: ItemDef = content.item(SOURCES[id])
		assert_not_null(definition)
		assert_not_null(source)
		if definition == null or source == null:
			continue
		assert_true(definition.catalogue_visible)
		assert_true(definition.outdoor_only)
		assert_false(source.outdoor_only, "adding a patio version never changes indoor furniture")
		assert_eq(definition.unlock_level, 1)
		assert_eq(definition.price, source.price)
		assert_eq(definition.category, source.category)
		assert_eq(definition.footprint, source.footprint)
		assert_eq(definition.solid, source.solid)
		assert_eq(definition.work_cells, source.work_cells)
		assert_eq(definition.seat_cells, source.seat_cells)
		assert_eq(definition.blocking_cells, source.blocking_cells)
		assert_eq(definition.view_scene, source.view_scene, "the existing lowered-backrest wrapper is reused exactly")
		assert_eq(definition.variant(), shared_look)
		assert_eq(definition.variant(&"unknown_saved_look"), shared_look)
		assert_eq(definition.variant_price(), source.price)
		assert_eq(definition.variant_tags(), definition.theme_tags)


func test_outdoor_recipe_recolours_wood_only_and_restores_exact_shared_sources() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var palette: Dictionary[StringName, Color] = KitMaterialColours.colours()
	for id: StringName in SOURCES:
		var definition: ItemDef = content.item(id)
		var view: PropView = definition.view_scene.instantiate() as PropView
		var untouched: PropView = definition.view_scene.instantiate() as PropView
		var before: Array[Dictionary] = _surfaces(view)
		var shared_before: Array[Dictionary] = _surfaces(untouched)
		assert_true(view.set_variant(definition.variant()), String(id))
		var after: Array[Dictionary] = _surfaces(view)
		assert_eq(after.size(), before.size())
		assert_eq(_surfaces(untouched), shared_before, "a second wrapper retains all original materials")
		var painted: int = 0
		for index: int in before.size():
			var original: BaseMaterial3D = before[index]["active"] as BaseMaterial3D
			var active: BaseMaterial3D = after[index]["active"] as BaseMaterial3D
			assert_eq(after[index]["source"], before[index]["source"], "the imported material is immutable")
			if before[index]["name"] == &"wood":
				painted += 1
				assert_ne(active, original)
				assert_eq(active.albedo_color, palette[&"metalDark"])
				assert_ne(original.albedo_color, palette[&"metalDark"])
			else:
				assert_eq(active, original, "cushions keep their original approved material")
		assert_true(painted > 0, "the actual wrapper contains the recipe's wood surface")
		assert_true(view.set_variant(null))
		assert_eq(_surfaces(view), before, "clearing the look restores exact material identities")
		view.free()
		untouched.free()


func _surfaces(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect(root, result)
	return result


func _collect(node: Node, result: Array[Dictionary]) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for index: int in mesh_node.mesh.get_surface_count():
			var source: Material = mesh_node.mesh.surface_get_material(index)
			result.append({"name": StringName(source.resource_name), "source": source,
				"active": mesh_node.get_active_material(index)})
	for child: Node in node.get_children():
		_collect(child, result)
