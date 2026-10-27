extends TestCase
## Native wrapper source contracts; rendered fit still needs a real capture.

const TABLE: ItemDef = preload("res://data/items/table_4.tres")
const GEOMETRY: GDScript = preload("res://tools/seated_head_geometry.gd")
const CATALOGUE: GDScript = preload("res://tools/seated_head_catalogue.gd")

var _view: PropView


func before_each() -> void:
	_view = TABLE.view_scene.instantiate() as PropView
	_view.prepare()


func after_each() -> void:
	_view.free()


func test_four_seat_wrapper_uses_only_unchanged_approved_native_models() -> void:
	assert_eq(_view.footprint, TABLE.footprint)
	assert_eq(_view.body_material_names, PackedStringArray(["wood"]))
	var table_pieces: int = 0
	var chairs: int = 0
	for node: Node in _view.get_children():
		var part: Node3D = node as Node3D
		var art: Node3D = part.get_node("Art") as Node3D
		var model: Node3D = art.get_node("Model") as Node3D
		assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
		if part.has_meta(&"seat_cell"):
			assert_eq(model.scene_file_path, "res://assets/kenney/furniture/chairCushion.glb")
			chairs += 1
		else:
			assert_eq(model.scene_file_path, "res://assets/kenney/furniture/table.glb")
			table_pieces += 1
	assert_eq(table_pieces, 3)
	assert_eq(chairs, 4)


func test_each_chair_matches_one_authored_cell_and_faces_the_table() -> void:
	var seats: Array[Vector2i] = []
	for node: Node in _view.get_children():
		var part: Node3D = node as Node3D
		if not part.has_meta(&"seat_cell"):
			continue
		var cell: Vector2i = part.get_meta(&"seat_cell")
		assert_true(TABLE.seat_cells.has(cell))
		assert_false(seats.has(cell))
		seats.append(cell)
		var expected: Vector3 = Vector3(
			(float(cell.x) + 0.5 - float(TABLE.footprint.x) / 2.0) * GridMath.CELL_SIZE,
			0.0, (float(cell.y) + 0.5 - float(TABLE.footprint.y) / 2.0) * GridMath.CELL_SIZE)
		assert_almost_eq(part.position.x, expected.x)
		assert_almost_eq(part.position.z, expected.z)
		var toward_table: Vector3 = Vector3(-part.position.x, 0.0, -part.position.z).normalized()
		assert_true((-part.basis.z).normalized().dot(toward_table) > 0.9999,
			String(part.name) + " faces the same table centre as its seated guest")
	assert_eq(seats.size(), 4)


func test_four_seat_classification_matches_cushioned_kit_and_its_measured_exception() -> void:
	var original: PropView = (load("res://assets/props/table_2.tscn") as PackedScene).instantiate() as PropView
	original.prepare()
	var original_parts: Array[Dictionary] = GEOMETRY.seat_parts(original, original)
	var party_parts: Array[Dictionary] = GEOMETRY.seat_parts(_view, _view)
	assert_false(original_parts.is_empty())
	assert_false(party_parts.is_empty())
	assert_eq(GEOMETRY._backrest_status(original, original_parts), "unclassified_kit")
	assert_eq(GEOMETRY._backrest_status(_view, party_parts), "unclassified_kit")
	for part: Dictionary in party_parts:
		assert_false(part["is_backrest"], "a joined kit mesh is not an identified backrest surface")
	assert_true(CATALOGUE.KNOWN_KIT_FAILURE_IDS.has("table_4"),
		"measured: the same chairCushion crossing class as table_2 (see tools/seated_head_probe.md)")
	original.free()


func test_native_table_pieces_fit_the_authored_footprint_without_stretching() -> void:
	var half_x: float = float(TABLE.footprint.x) * GridMath.CELL_SIZE / 2.0
	var half_z: float = float(TABLE.footprint.y) * GridMath.CELL_SIZE / 2.0
	for node: Node in _view.get_children():
		var part: Node3D = node as Node3D
		if part.has_meta(&"seat_cell"):
			continue
		var bounds: AABB = part.transform * PropView._children_aabb(part)
		assert_true(bounds.position.x >= -half_x - 0.05)
		assert_true(bounds.end.x <= half_x + 0.05)
		assert_true(bounds.position.z >= -half_z - 0.05)
		assert_true(bounds.end.z <= half_z + 0.05)


func test_four_seat_table_unlocks_at_owner_level_two() -> void:
	assert_eq(TABLE.unlock_level, 2, "players can prepare before pairs arrive at level 3")
	assert_true(TABLE.catalogue_visible)
