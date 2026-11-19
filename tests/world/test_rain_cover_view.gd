extends TestCase
## Rain-cover canopies fade while building and stay solid while the shop runs (#625).

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")

var _view: ShopView


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()


func test_canopies_fade_in_build_and_frames_stay_solid() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var lot: LotDef = content.lot(&"seaside_cliff")
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(lot.layout_for_id(lot.base_layout.save_layout_id), content, errors)
	assert_eq(errors.size(), 0)
	_view = VIEW.instantiate() as ShopView
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)
	_view.show_world(world)
	var pergola: PlacedItem = ShopBuilder.items_with_def(world, &"pergola")[0]
	var node: ItemVisual = _view.item_nodes[pergola.id]
	assert_eq(_alphas(node, true), [1.0], "solid while the shop runs")
	_view.set_canopies_faded(true)
	assert_true(node.canopy_faded)
	for alpha: float in _alphas(node, true):
		assert_almost_eq(alpha, ItemVisual.CANOPY_FADE_ALPHA, 0.001)
	assert_false(_alphas(node, true).is_empty())
	for alpha: float in _alphas(node, false):
		assert_almost_eq(alpha, 1.0, 0.001, "the frame stays solid")
	# A cover bought while building arrives faded.
	var awning: PlacedItem = world.grid.place_def(content.item(&"awning"), Vector2i(9, 6))
	assert_not_null(awning)
	assert_true(_view.item_nodes.has(awning.id), "the view follows the grid edit")
	for alpha: float in _alphas(_view.item_nodes[awning.id], true):
		assert_almost_eq(alpha, ItemVisual.CANOPY_FADE_ALPHA, 0.001)
	_view.set_canopies_faded(false)
	assert_false(node.canopy_faded)
	assert_eq(_alphas(node, true), [1.0], "solid again once building ends")


## The alpha of every material on the canopy (roof) meshes, or on all the others.
func _alphas(node: ItemVisual, canopy: bool) -> Array[float]:
	var result: Array[float] = []
	for mesh: MeshInstance3D in node.rendered_meshes():
		var roof: bool = node._in_canopy(mesh)
		if roof != canopy:
			continue
		for index: int in mesh.mesh.get_surface_count():
			var material: BaseMaterial3D = mesh.get_active_material(index) as BaseMaterial3D
			var alpha: float = material.albedo_color.a if material != null else 1.0
			if canopy and not result.has(alpha) or not canopy:
				result.append(alpha)
	return result
