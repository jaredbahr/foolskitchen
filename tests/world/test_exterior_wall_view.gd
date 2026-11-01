extends TestCase
## Street facings and mounted models use the real shell planes and shared scale.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const FRONT: Vector3i = Vector3i(3, 11, 0)

var _content: ContentDB
var _sim: RestaurantSim
var _view: WallFinishView
var _finishes: WallFinishes
var _decor: WallDecor
var _visuals: Array[ItemVisual] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 240, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_finishes = WallFinishes.new(WallStyleDef.DEFAULT_ID, LAYOUT.wall_swatch_id)
	_decor = WallDecor.new()
	_view = WallFinishView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)
	_view.bind(_sim.world.grid, _content, _finishes, _decor)


func after_each() -> void:
	_view.get_parent().remove_child(_view)
	_view.free()
	for visual: ItemVisual in _visuals:
		visual.free()
	_visuals.clear()
	_view = null
	_sim = null
	_content = null
	_finishes = null
	_decor = null


func test_default_shop_adds_no_finish_mesh_or_purchased_wall_item() -> void:
	assert_true(_view.finish_nodes().is_empty())
	assert_true(_view.item_nodes.is_empty())
	assert_true(_view.finished_faces().is_empty())


func test_exterior_face_frames_point_outward_on_all_four_frontages() -> void:
	for turn: int in 4:
		var grid: SimGrid = _rotated_grid(turn)
		var outside: Vector2i = GridMath.rotate_cell(Vector2i(2, 6), Vector2i(7, 7), turn)
		var face: Vector3i = WallFaces.make(outside, turn)
		assert_true(WallFaces.is_exterior(grid, face))
		var frame: Dictionary = WallFinishView.face_frame(grid, face, false, {} as Dictionary[Vector2i, bool])
		var into: Vector2i = WallFaces.step(face)
		var outward: Vector3 = -Vector3(into.x, 0.0, into.y)
		assert_eq(frame["normal"], outward)
		var shell: Vector3 = GridMath.cell_to_world(outside + into)
		assert_almost_eq(((frame["origin"] as Vector3) - shell).dot(outward),
			GridMath.CELL_SIZE * 0.5 + WallFinishView.FACE_GAP, 0.0001)
		assert_eq(frame["tangent"], Vector3(WallFaces.along(face).x, 0.0, WallFaces.along(face).y))
		assert_almost_eq(float(frame["height"]), ArtScale.WALL_HEIGHT, 0.0001)


func test_inside_and_outside_facings_are_separate_and_follow_the_same_lowered_shell() -> void:
	var inside: Dictionary = WallFinishView.face_frame(_sim.world.grid, Vector3i(3, 9, 2), false,
		{} as Dictionary[Vector2i, bool])
	var outside: Dictionary = WallFinishView.face_frame(_sim.world.grid, FRONT, false,
		{} as Dictionary[Vector2i, bool])
	assert_eq(inside["normal"], Vector3(0, 0, -1))
	assert_eq(outside["normal"], Vector3(0, 0, 1))
	assert_almost_eq((outside["origin"] as Vector3).z - (inside["origin"] as Vector3).z,
		GridMath.CELL_SIZE + WallFinishView.FACE_GAP * 2.0, 0.0001)
	var lowered: Dictionary[Vector2i, bool] = {Vector2i(3, 10): true}
	for face: Vector3i in [FRONT, Vector3i(3, 9, 2)]:
		var frame: Dictionary = WallFinishView.face_frame(_sim.world.grid, face, false, lowered)
		assert_almost_eq(float(frame["height"]), ShopView.LOWERED_HEIGHT, 0.0001)


func test_stale_outside_finishes_never_draw_over_real_window_or_street_door_holes() -> void:
	var window: Vector3i = Vector3i(10, 10, SimGrid.EDGE_NORTH)
	assert_true(_sim.world.grid.set_segment(window, SimGrid.Segment.WINDOW))
	var changes: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	for face: Vector3i in [FRONT, Vector3i(10, 11, 0), Vector3i(6, 11, 0)]:
		changes[face] = FloorFinishes.Finish.new(&"brick", &"sage", &"cream")
	_finishes.set_finishes(changes)
	_view.rebuild()
	assert_eq(_view.finished_faces(), [FRONT] as Array[Vector3i])
	assert_eq(_view.finish_nodes().size(), 1)
	var mesh: Mesh = _view.finish_nodes()[0].mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_false(normals.is_empty())
	for normal: Vector3 in normals:
		assert_almost_eq(normal.dot(Vector3.BACK), 1.0, 0.0001, "the sole facing faces the street")


func test_exterior_transform_aligns_measured_model_back_without_stretching_in_any_direction() -> void:
	var box: AABB = AABB(Vector3(-0.4, 0.05, -0.35), Vector3(0.8, 0.15, 0.4))
	for turn: int in 4:
		var grid: SimGrid = _rotated_grid(turn)
		var outside: Vector2i = GridMath.rotate_cell(Vector2i(2, 6), Vector2i(7, 7), turn)
		var face: Vector3i = WallFaces.make(outside, turn)
		var anchor: Vector3i = ExteriorSupport.key_for(face, ExteriorSupport.Band.CANOPY)
		var xf: Transform3D = WallFinishView.exterior_transform(grid, anchor, 2, box)
		var into: Vector2i = WallFaces.step(face)
		var outward: Vector3 = -Vector3(into.x, 0.0, into.y)
		assert_true((xf.basis * Vector3.FORWARD).is_equal_approx(outward))
		assert_true(xf.basis.get_scale().is_equal_approx(Vector3.ONE), "mounting never stretches an asset")
		var back: Vector3 = xf * Vector3(box.get_center().x, box.position.y, box.end.z)
		var wall: Vector3 = GridMath.cell_to_world(outside + into) + outward * GridMath.CELL_SIZE * 0.5
		assert_almost_eq((back - wall).dot(outward), WallFinishView.FACE_GAP, 0.0001)
		assert_almost_eq(back.y, ArtScale.EXTERIOR_CANOPY_BOTTOM, 0.0001)


func test_purchased_models_keep_uniform_kit_scale_and_fit_their_authored_span() -> void:
	for id: StringName in [&"street_awning_2", &"street_awning_3", &"street_awning_4",
		&"flower_window_box", &"shop_name_sign", &"string_lights_2", &"string_lights_3", &"string_lights_4"]:
		var definition: ItemDef = _content.item(id)
		assert_not_null(definition, String(id))
		if definition == null:
			continue
		var visual: ItemVisual = ItemVisual.create(definition, 0.2, StandardMaterial3D.new())
		_visuals.append(visual)
		assert_not_null(visual.prop)
		if visual.prop == null:
			continue
		var art: Node3D = visual.prop.get_node("WallMount/Art") as Node3D
		assert_true(art.scale.is_equal_approx(Vector3.ONE * ArtScale.FURNITURE_SCALE), String(id))
		var box: AABB = visual.get_aabb()
		assert_true(box.size.x > 0.0 and box.size.y > 0.0 and box.size.z > 0.0)
		assert_true(box.size.x <= float(definition.footprint.x) * GridMath.CELL_SIZE + 0.05, String(id))
		var anchor: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), definition.exterior_band)
		var xf: Transform3D = WallFinishView.exterior_transform(_sim.world.grid, anchor, definition.footprint.x, box)
		var bounds: AABB = xf * box
		assert_true(bounds.position.y >= 0.0)
		assert_true(bounds.end.y <= ArtScale.WALL_HEIGHT + 0.001, String(id) + " stays under the wall top")
		if id == &"shop_name_sign":
			assert_not_null(visual.restaurant_name_label)
			assert_true(visual.set_restaurant_name("The Copper Spoon"))
			assert_eq(visual.restaurant_name_label.text, "The Copper Spoon")
			assert_false(visual.restaurant_name_label.double_sided)
		elif String(id).begins_with("street_awning"):
			assert_true(bounds.position.y >= 1.10 - 0.001, "%s actual mounted bottom%s clears the doorway" % [id, bounds.position.y])
			assert_true(bounds.end.y <= 1.25 + 0.001, "the awning clears the sign's1.27m bottom")
			assert_eq(visual.prop.body_material_names, PackedStringArray(["carpet"]))


func _rotated_grid(turn: int) -> SimGrid:
	var rows: PackedStringArray = ["       ", " ##### ", " #...# ", " #...# ", " #...# ", " ##.## ", "   E   "]
	var rotated: PackedStringArray = []
	for y: int in 7:
		rotated.append("       ")
	for y: int in 7:
		for x: int in 7:
			var target: Vector2i = GridMath.rotate_cell(Vector2i(x, y), Vector2i(7, 7), turn)
			rotated[target.y] = rotated[target.y].substr(0, target.x) + rows[y][x] + rotated[target.y].substr(target.x + 1)
	return SimGrid.from_ascii(rotated)


func test_street_capture_options_require_the_single_declared_paused_frontage_fixture() -> void:
	var review: Script = load("res://tools/street_front_review.gd")
	for arguments: PackedStringArray in [PackedStringArray(["--street-front-review", "--speed=0", "--frames=60"]),
		PackedStringArray(["--street-front-review", "--speed=0", "--frames=60", "--out=a", "--out=a"])]:
		var valid: Dictionary = review.call("options", arguments)
		assert_true(valid["enabled"])
		assert_eq(valid["error"], "")
	for extra: String in ["--street-front-review", "--menu", "--open", "--street-front-review=bad", "--scene=res://bad.tscn"]:
		var rejected: Dictionary = review.call("options", PackedStringArray(["--street-front-review", "--speed=0", "--frames=60", extra]))
		assert_false(String(rejected["error"]).is_empty(), "mixed or ambiguous capture request refuses: " + extra)


func test_exterior_open_sign_and_ghost_fit_the_single_face_uniformly_and_remain_pickable() -> void:
	var definition: ItemDef = _content.item(&"neon_open_sign")
	assert_eq(_decor.problem(_sim.world.grid, definition, FRONT), "", "the original outside key is still supported")
	assert_true(_decor.add(definition.id, FRONT, definition.footprint.x, false, ItemDef.WallMount.EXTERIOR))
	_view.rebuild()
	var mounted: ItemVisual = _view.item_nodes[FRONT]
	_assert_single_face_neon_bounds(mounted, definition)
	_view.show_ghost(definition, FRONT, true)
	var ghost: ItemVisual = _view.ghost()
	assert_not_null(ghost)
	if ghost != null:
		_assert_single_face_neon_bounds(ghost, definition)
	var largest: MeshInstance3D
	var volume: float = -1.0
	for mesh: MeshInstance3D in mounted.rendered_meshes():
		if mesh.get_aabb().get_volume() > volume:
			largest = mesh
			volume = mesh.get_aabb().get_volume()
	assert_not_null(largest)
	if largest == null:
		return
	var target: Vector3 = largest.global_transform * largest.get_aabb().get_center()
	var origin: Vector3 = target + Vector3(0.0, 0.1, 1.0)
	var hit: Dictionary = _view.item_hit(origin, (target - origin).normalized())
	assert_eq(hit.get("anchor", WallFaces.NO_FACE), FRONT, "fitting preserves picking of the actual rendered sign")


func _assert_single_face_neon_bounds(visual: ItemVisual, definition: ItemDef) -> void:
	var first: bool = true
	var bounds: AABB
	for mesh: MeshInstance3D in visual.rendered_meshes():
		var rendered: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = rendered if first else bounds.merge(rendered)
		first = false
	assert_false(first, "the sign has actual rendered meshes")
	var half_span: float = float(definition.footprint.x) * GridMath.CELL_SIZE * 0.5
	var centre: float = GridMath.cell_to_world(WallFaces.cell(FRONT)).x
	assert_true(bounds.position.x >= centre - half_span - 0.05 - 0.0001,
		"actual OPEN left edge%s stays inside its face plus the ART0.05m allowance" % bounds.position.x)
	assert_true(bounds.end.x <= centre + half_span + 0.05 + 0.0001,
		"actual OPEN right edge%s stays inside its face plus the ART0.05m allowance" % bounds.end.x)
	assert_not_null(visual.prop)
	if visual.prop != null:
		assert_almost_eq(visual.prop.scale.x, visual.prop.scale.y, 0.0001)
		assert_almost_eq(visual.prop.scale.x, visual.prop.scale.z, 0.0001)
		assert_true(visual.prop.scale.x > 0.0 and visual.prop.scale.x <= 1.0, "the fit only scales down uniformly")
