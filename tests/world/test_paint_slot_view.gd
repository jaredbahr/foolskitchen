extends TestCase
## Paint slots in the view (#431): each slot paints only its own surfaces in
## its material; the legacy flat coat is drawn exactly as before.

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_content = null


func test_cushion_and_frame_paint_their_own_surfaces_in_their_materials() -> void:
	var chair: ItemDef = _content.item(&"chair")
	var view: PropView = chair.view_scene.instantiate() as PropView
	view.prepare()
	var look: PaintLook = PaintLook.new()
	look.set_swatch(&"cushion", &"tomato")
	view.set_slot_paint(ShopView.slot_paints(chair, &"sage", look, _content))
	var frame: BaseMaterial3D = _active(view, "wood")
	var cushion: BaseMaterial3D = _active(view, "carpet")
	assert_eq(frame.albedo_color, _colour(&"sage"), "the palette colour is the material colour")
	assert_not_null(frame.albedo_texture, "the frame wears its default wood grain")
	assert_true(frame.uv1_triplanar, "object-space grain: no UVs or meshes change")
	assert_eq(cushion.albedo_color, _colour(&"tomato"))
	assert_eq(cushion.albedo_texture, PaintMaterials.texture(PaintFinish.FABRIC))
	# A chosen material wins over the slot default; Paint is flat.
	look.set_material(&"frame", PaintFinish.PAINTED)
	view.set_slot_paint(ShopView.slot_paints(chair, &"sage", look, _content))
	assert_null(_active(view, "wood").albedo_texture)
	assert_eq(_active(view, "wood").albedo_color, _colour(&"sage"))
	# Metal is a sheen, still in the palette colour.
	look.set_material(&"cushion", PaintFinish.METAL)
	view.set_slot_paint(ShopView.slot_paints(chair, &"sage", look, _content))
	assert_true(_active(view, "carpet").metallic > 0.0)
	# Clearing puts the kit materials back exactly.
	view.clear_body_tint()
	assert_null(_override(view, "wood"))
	assert_null(_override(view, "carpet"))
	view.free()


func test_legacy_flat_coat_uses_the_unchanged_body_tint_path() -> void:
	var table: ItemDef = _content.item(&"table_2")
	var legacy: PaintLook = PaintLook.legacy(table, &"sage")
	assert_true(ShopView.flat_body_only(table, true, legacy), "an old save's coat is drawn by set_body_tint")
	assert_true(ShopView.flat_body_only(table, false, PaintLook.new()), "unpainted stays unpainted")
	assert_false(ShopView.flat_body_only(table, true, PaintLook.new()), "a new coat wears the slot's wood")
	var coffee: ItemDef = _content.item(&"coffee_machine")
	assert_true(ShopView.flat_body_only(coffee, true, PaintLook.new()), "single legacy body slots paint flat")
	var rug: ItemDef = _content.item(&"rug_round")
	assert_false(ShopView.flat_body_only(rug, false, PaintLook.new()), "slots with their own surfaces use layers")


func test_slot_paint_leaves_other_views_surfaces_alone() -> void:
	var tank: ItemDef = _content.item(&"aquarium")
	var view: PropView = tank.view_scene.instantiate() as PropView
	view.prepare()
	var glass: MeshInstance3D = null
	var glass_index: int = -1
	for mesh_node: MeshInstance3D in _meshes(view):
		for index: int in mesh_node.mesh.get_surface_count():
			if mesh_node.mesh.surface_get_material(index).resource_name == "aquariumGlass":
				glass = mesh_node
				glass_index = index
	assert_not_null(glass)
	var cloudy: StandardMaterial3D = StandardMaterial3D.new()
	glass.set_surface_override_material(glass_index, cloudy)
	var look: PaintLook = PaintLook.new()
	look.set_swatch(&"trim", &"brass")
	view.set_slot_paint(ShopView.slot_paints(tank, &"walnut", look, _content))
	view.set_slot_paint(ShopView.slot_paints(tank, &"", PaintLook.new(), _content))
	assert_eq(glass.get_surface_override_material(glass_index), cloudy, "the cloudy glass stays the aquarium's")
	view.free()


func test_material_patterns_are_deterministic_and_light() -> void:
	for material: StringName in [PaintFinish.WOOD, PaintFinish.FABRIC, PaintFinish.METAL]:
		var first: Image = PaintMaterials.pattern(material)
		var second: Image = PaintMaterials.pattern(material)
		assert_eq(first.get_data(), second.get_data(), "%s is drawn the same every time" % material)
		for y: int in range(0, PaintMaterials.SIZE, 7):
			for x: int in range(0, PaintMaterials.SIZE, 5):
				var shade: float = first.get_pixel(x, y).r
				assert_true(shade >= 0.79 and shade <= 1.0, "%s stays light so the colour reads" % material)
	assert_null(PaintMaterials.texture(PaintFinish.PAINTED))


func _colour(id: StringName) -> Color:
	var colour: Color = _content.swatch(id).color
	return Color(colour.r, colour.g, colour.b, 1.0)


func _active(view: PropView, surface: String) -> BaseMaterial3D:
	for mesh_node: MeshInstance3D in _meshes(view):
		for index: int in mesh_node.mesh.get_surface_count():
			if mesh_node.mesh.surface_get_material(index).resource_name == surface:
				return mesh_node.get_active_material(index) as BaseMaterial3D
	return null


func _override(view: PropView, surface: String) -> Material:
	for mesh_node: MeshInstance3D in _meshes(view):
		for index: int in mesh_node.mesh.get_surface_count():
			if mesh_node.mesh.surface_get_material(index).resource_name == surface:
				return mesh_node.get_surface_override_material(index)
	return null


func _meshes(view: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for found: Node in view.find_children("*", "MeshInstance3D", true, false):
		if (found as MeshInstance3D).mesh != null:
			result.append(found as MeshInstance3D)
	return result


func test_going_back_to_a_flat_coat_clears_other_parts() -> void:
	var chair: ItemDef = _content.item(&"chair")
	var view: PropView = chair.view_scene.instantiate() as PropView
	view.prepare()
	var look: PaintLook = PaintLook.new()
	look.set_swatch(&"cushion", &"tomato")
	view.set_slot_paint(ShopView.slot_paints(chair, &"sage", look, _content))
	view.set_body_tint(_colour(&"sage"))
	assert_null(_override(view, "carpet"), "undoing the cushion leaves it as it came")
	assert_eq(_active(view, "wood").albedo_color, _colour(&"sage"))
	view.free()
