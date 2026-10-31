extends TestCase
## Floor mess contrast reads the same per-cell main colour as the floor shader.

var _view: ShopView
var _content: ContentDB
var _world: SimWorld
var _dirt: CleanlinessState
var _random: RandomNumberGenerator


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_world = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var tuning: CleanlinessTuning = load("res://data/balance/cleanliness.tres").duplicate() as CleanlinessTuning
	tuning.seat_departure_chance = 1.0
	_random = RandomNumberGenerator.new()
	_random.seed = 127
	_dirt = CleanlinessState.new(_world.grid, tuning, _random)
	_view = (load("res://src/world/shop_view.tscn") as PackedScene).instantiate() as ShopView
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)
	_view.show_world(_world)
	_view.set_paint(_content, &"", &"")
	_view.bind_cleanliness(_dirt)


func after_each() -> void:
	_view.free()
	_dirt = null
	_world = null
	_content = null


func test_existing_dirt_changes_contrast_with_floor_paint_without_replacing_its_node() -> void:
	var cell: Vector2i = Vector2i(1, 1)
	assert_true(_dirt.try_spawn_at_departed_seat(cell))
	_view._process(0.0)
	var node: MeshInstance3D = _view.dirt_nodes[cell]
	var stream: int = _random.state
	assert_eq(_fill(node), ShopView.DIRT_LIGHT_SWATCH.color)
	_view.set_paint(_content, &"", &"cream")
	assert_eq(_fill(node), ShopView.DIRT_SWATCH.color)
	assert_true(_view.dirt_nodes[cell] == node)
	_view.preview_paint(&"floor", -1, &"walnut")
	assert_eq(_fill(node), ShopView.DIRT_LIGHT_SWATCH.color)
	_view.clear_paint_preview()
	assert_eq(_fill(node), ShopView.DIRT_SWATCH.color)
	assert_eq(_random.state, stream, "redrawing never consumes the simulation stream")
	assert_eq(_world.now, 0)
	assert_eq(_dirt.spot_count(), 1)


func test_cell_finish_and_preview_override_the_shop_paint_for_every_floor_style() -> void:
	var dark: Vector2i = Vector2i(1, 1)
	var light: Vector2i = Vector2i(2, 1)
	assert_true(_dirt.add_spill(dark))
	assert_true(_dirt.add_spill(light, true))
	var floors: FloorFinishes = FloorFinishes.new(&"wide_planks", &"cream")
	_view.set_paint(_content, &"", &"cream")
	_view.bind_floor_finishes(floors)
	for style: FloorStyleDef in _content.floor_styles():
		floors.set_finishes({dark: FloorFinishes.Finish.new(style.id, &"walnut", &"cream"),
			light: FloorFinishes.Finish.new(style.id, &"cream", &"walnut")}
			as Dictionary[Vector2i, FloorFinishes.Finish])
		assert_eq(_view.drawn_floor_main_color(dark), _content.swatch(&"walnut").color, style.display_name)
		assert_eq(_view.drawn_floor_main_color(light), _content.swatch(&"cream").color, style.display_name)
		assert_eq(_fill(_view.dirt_nodes[dark]), ShopView.DIRT_LIGHT_SWATCH.color, style.display_name)
		assert_eq(_fill(_view.dirt_nodes[light]), ShopView.DIRT_SWATCH.color, style.display_name)
	_view.preview_floor_finishes({dark: FloorFinishes.Finish.new(&"small_tile", &"cream", &"walnut")}
		as Dictionary[Vector2i, FloorFinishes.Finish])
	assert_eq(_fill(_view.dirt_nodes[dark]), ShopView.DIRT_SWATCH.color)
	_view.clear_floor_preview()
	assert_eq(_fill(_view.dirt_nodes[dark]), ShopView.DIRT_LIGHT_SWATCH.color)


func test_all_palette_swatches_choose_the_greater_contrast_and_keep_a_darker_outline() -> void:
	var cell: Vector2i = Vector2i(1, 1)
	assert_true(_dirt.add_spill(cell))
	_view._process(0.0)
	for swatch: SwatchDef in _content.swatches():
		_view.set_paint(_content, &"", swatch.id)
		var fill: Color = _fill(_view.dirt_nodes[cell])
		var floor_luma: float = swatch.color.get_luminance()
		var other: Color = ShopView.DIRT_SWATCH.color if fill == ShopView.DIRT_LIGHT_SWATCH.color \
			else ShopView.DIRT_LIGHT_SWATCH.color
		assert_true(absf(fill.get_luminance() - floor_luma) >= absf(other.get_luminance() - floor_luma), swatch.display_name)
		var outline: MeshInstance3D = _view.dirt_nodes[cell].get_node("Outline") as MeshInstance3D
		assert_true(_fill(outline).get_luminance() < fill.get_luminance(), swatch.display_name)
		assert_true(outline.scale.x > 1.0 and outline.scale.x == outline.scale.z)
		assert_true(outline.mesh.get_aabb().size.x * outline.scale.x < GridMath.CELL_SIZE)


func test_broken_plate_uses_the_approved_unmodified_model_until_the_spot_is_cleaned() -> void:
	var cell: Vector2i = Vector2i(1, 1)
	assert_true(_dirt.add_spill(cell))
	_view._process(0.0)
	var node: MeshInstance3D = _view.dirt_nodes[cell]
	assert_false(node.has_node("BrokenPlate"))
	assert_true(_dirt.add_spill(cell, true))
	_view._process(0.0)
	assert_true(_view.dirt_nodes[cell] == node, "adding fragments retains the existing spill")
	var holder: Node3D = node.get_node("BrokenPlate") as Node3D
	var model: Node3D = holder.get_child(0) as Node3D
	assert_eq(model.scene_file_path, "res://assets/kenney/food/plate-broken.glb")
	assert_eq(model.scale, Vector3.ONE * ArtScale.FOOD_SCALE)
	assert_not_null(node.get_node_or_null("PlateContrast"))
	var bounds: AABB = PropView._children_aabb(holder)
	assert_true(bounds.size.x <= GridMath.CELL_SIZE and bounds.size.z <= GridMath.CELL_SIZE)
	for frame: int in 3:
		_view._process(0.1)
		assert_true(node.get_node("BrokenPlate") == holder, "unchanged fragments keep their native model")
	assert_true(_dirt.clear_spot(cell))
	_view._process(0.0)
	assert_false(_view.dirt_nodes.has(cell))
	assert_false(is_instance_valid(holder))
	assert_true(_dirt.add_spill(cell, true))
	_view._process(0.0)
	_dirt.tidy_overnight()
	_view._process(0.0)
	assert_true(_view.dirt_nodes.is_empty())


func _fill(node: MeshInstance3D) -> Color:
	return (node.material_override as StandardMaterial3D).albedo_color
