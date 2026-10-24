extends TestCase
## The real-model tests require the normal Godot import before the test runner.

class TeardownProbe extends MeshInstance3D:
	var observed: Dictionary = {}

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			observed[String(name)] = material_override == null \
				and get_surface_override_material(0) == null

var _views: Array[PropView] = []


func after_each() -> void:
	for view: PropView in _views:
		view.free()
	_views.clear()


func test_every_authored_item_has_a_floor_aligned_scene_inside_its_footprint() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	for definition: ItemDef in content.items():
		assert_not_null(definition.view_scene, String(definition.id))
		if definition.view_scene == null:
			continue
		var instance: Node = definition.view_scene.instantiate()
		var view: PropView = instance as PropView
		assert_not_null(view, String(definition.id))
		if view == null:
			instance.free()
			continue
		_views.append(view)
		assert_eq(view.footprint, definition.footprint, String(definition.id))
		var bounds: AABB = view.get_combined_aabb()
		var half_width: float = float(definition.footprint.x) * GridMath.CELL_SIZE * 0.5
		var half_depth: float = float(definition.footprint.y) * GridMath.CELL_SIZE * 0.5
		assert_true(bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0, String(definition.id))
		assert_almost_eq(bounds.position.y, 0.0, 0.0001, String(definition.id))
		assert_almost_eq(bounds.get_center().x, 0.0, 0.0001, String(definition.id))
		assert_almost_eq(bounds.get_center().z, 0.0, 0.0001, String(definition.id))
		assert_true(bounds.position.x >= -half_width - 0.05, String(definition.id))
		assert_true(bounds.end.x <= half_width + 0.05, String(definition.id))
		assert_true(bounds.position.z >= -half_depth - 0.05, String(definition.id))
		assert_true(bounds.end.z <= half_depth + 0.05, String(definition.id))
		assert_true(view.body_surface_count() > 0, "%s body material names must match imported surfaces" % definition.id)


func test_food_uses_food_scale_and_rests_on_the_counter_without_tint() -> void:
	var definition: ItemDef = load("res://data/items/prep_counter.tres") as ItemDef
	var view: PropView = definition.view_scene.instantiate() as PropView
	_views.append(view)
	view.prepare()
	var board: Node3D = view.get_node("Board") as Node3D
	var board_art: Node3D = board.get_node("Art") as Node3D
	var cabinet_art: Node3D = view.get_node("CabinetLeft/Art") as Node3D
	assert_eq(board_art.scale, Vector3.ONE * ArtScale.FOOD_SCALE)
	assert_eq(cabinet_art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
	assert_true(board.position.y > 0.0, "the board rests above the cabinet, not on the floor")
	var board_meshes: Array[MeshInstance3D] = []
	_collect_meshes(board, board_meshes)
	view.set_body_tint(Color.RED)
	for mesh_node: MeshInstance3D in board_meshes:
		for index: int in range(mesh_node.mesh.get_surface_count()):
			assert_null(mesh_node.get_surface_override_material(index), "food stays in its original kit material")


func test_combined_bounds_keep_source_transforms_and_ignore_wrapper_world_pose() -> void:
	var source: StandardMaterial3D = _material("wood")
	var view: PropView = _fixture(source, _material("metal"))
	var model: Node3D = view.get_node("Body/Art/Source") as Node3D
	model.scale = Vector3.ONE * 2.0
	model.position = Vector3(0.3, 0.1, -0.2)
	var source_transform: Transform3D = model.transform
	var art: Node3D = view.get_node("Body/Art") as Node3D
	art.rotation.y = PI
	var before: AABB = view.get_combined_aabb()
	assert_eq(model.transform, source_transform, "the imported root's intrinsic scale and pivot are preserved")
	assert_almost_eq(before.position.y, 0.0)
	assert_almost_eq(before.get_center().x, 0.0)
	assert_almost_eq(before.get_center().z, 0.0)
	view.position = Vector3(8.0, 2.0, -7.0)
	view.rotation.y = PI * 0.5
	assert_eq(view.get_combined_aabb(), before, "bounds stay in wrapper space for the caller's own item rotation")
	view.prepare()
	assert_eq(view.get_combined_aabb(), before, "preparation is idempotent")


func test_body_tint_is_local_reversible_and_preserves_trim_glass_and_food() -> void:
	var wood: StandardMaterial3D = _material("wood")
	var metal: StandardMaterial3D = _material("metal")
	var first: PropView = _fixture(wood, metal)
	var second: PropView = _fixture(wood, metal)
	var first_body: MeshInstance3D = first.get_node("Body/Art/Source") as MeshInstance3D
	var second_body: MeshInstance3D = second.get_node("Body/Art/Source") as MeshInstance3D
	var trim: MeshInstance3D = first.get_node("Body/Art/Trim") as MeshInstance3D
	var glass: MeshInstance3D = first.get_node("Body/Art/Glass") as MeshInstance3D
	var food: MeshInstance3D = first.get_node("Food/Art/Source") as MeshInstance3D
	var original_override: StandardMaterial3D = _material("wood")
	first_body.set_surface_override_material(0, original_override)
	var original_color: Color = original_override.albedo_color
	first.set_body_tint(Color.RED)
	assert_eq(first.body_surface_count(), 1)
	var tinted: BaseMaterial3D = first_body.get_active_material(0) as BaseMaterial3D
	assert_true(tinted != original_override and tinted != wood)
	assert_eq(tinted.albedo_color, Color.RED)
	assert_eq(original_override.albedo_color, original_color)
	assert_eq(second_body.get_active_material(0), wood, "another copy still shares the unpainted kit resource")
	assert_eq(trim.get_active_material(0), metal)
	assert_null(trim.get_surface_override_material(0))
	assert_null(glass.get_surface_override_material(0))
	assert_null(food.get_surface_override_material(0), "even a same-named food material is excluded")
	first.set_body_tint(Color.BLUE)
	assert_eq(first_body.get_active_material(0), tinted, "changing a swatch reuses the local tint copy")
	first.clear_body_tint()
	assert_eq(first_body.get_surface_override_material(0), original_override)


func test_named_body_accessor_ignores_earlier_trim_and_glass_surfaces() -> void:
	var wood: StandardMaterial3D = _material("wood")
	var metal: StandardMaterial3D = _material("metal")
	var view: PropView = _fixture(wood, metal)
	var art: Node3D = view.get_node("Body/Art") as Node3D
	art.move_child(art.get_node("Trim"), 0)
	art.move_child(art.get_node("Glass"), 1)
	assert_eq(view.active_body_material(), wood)
	view.set_body_tint(Color.RED)
	assert_eq(view.active_body_material().albedo_color, Color.RED)
	assert_eq((art.get_node("Trim") as MeshInstance3D).get_active_material(0), metal)
	view.clear_body_tint()
	assert_eq(view.active_body_material(), wood)


func test_item_teardown_unbinds_private_materials_before_descendant_delete() -> void:
	var observed: Dictionary = {}
	var source: StandardMaterial3D = _material("wood")
	var source_color: Color = source.albedo_color
	var shared_mesh: BoxMesh = BoxMesh.new()
	shared_mesh.material = source
	var holder: Node3D = Node3D.new()
	var item: ItemVisual = ItemVisual.new()
	holder.add_child(item)
	var nested: Node3D = Node3D.new()
	item.add_child(nested)
	var geometry: TeardownProbe = TeardownProbe.new()
	geometry.name = "Geometry"
	geometry.mesh = shared_mesh
	geometry.material_override = source
	geometry.observed = observed
	item.add_child(geometry)
	var surface: TeardownProbe = TeardownProbe.new()
	surface.name = "Surface"
	surface.mesh = shared_mesh
	surface.observed = observed
	nested.add_child(surface)
	item.set_ghost_tint(Color.RED)
	assert_not_null(geometry.material_override)
	assert_true(geometry.material_override != source, "the box branch owns a private geometry override")
	assert_not_null(surface.get_surface_override_material(0), "the model branch owns a private surface override")
	assert_true(observed.is_empty())
	# This deliberately starts outside the tree, as do several real preview paths.
	# The descendant observers run before their own native mesh destructors.
	holder.free()
	assert_eq(observed, {"Geometry": true, "Surface": true}, "all bindings are detached before child deletion")
	assert_eq(shared_mesh.material, source, "teardown never changes shared mesh materials")
	assert_eq(source.albedo_color, source_color)


func test_optional_scene_defaults_to_absent_for_the_world_box_fallback() -> void:
	assert_null(ItemDef.new().view_scene)


func _fixture(body_material: StandardMaterial3D, trim_material: StandardMaterial3D) -> PropView:
	var view: PropView = PropView.new()
	view.body_material_names = PackedStringArray(["wood"])
	var part: Node3D = Node3D.new()
	part.name = "Body"
	view.add_child(part)
	var art: Node3D = Node3D.new()
	art.name = "Art"
	part.add_child(art)
	art.add_child(_mesh("Source", body_material))
	art.add_child(_mesh("Trim", trim_material))
	art.add_child(_mesh("Glass", _material("glass")))
	var food_part: Node3D = Node3D.new()
	food_part.name = "Food"
	food_part.set_meta(&"art_group", &"food")
	view.add_child(food_part)
	var food_art: Node3D = Node3D.new()
	food_art.name = "Art"
	food_part.add_child(food_art)
	food_art.add_child(_mesh("Source", body_material))
	_views.append(view)
	return view


func _mesh(node_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.name = node_name
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.2, 0.4, 0.3)
	box.material = material
	mesh_node.mesh = box
	return mesh_node


func _material(material_name: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = material_name
	return material


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		result.append(mesh_node)
	for child: Node in node.get_children():
		_collect_meshes(child, result)
