extends TestCase
## Metadata and wrapper checks for the approved Kenney seating and table slice.

const CASES: Array[Dictionary] = [
	{"id": &"wooden_chair", "name": "Wooden chair", "asset": "chair", "category": ItemDef.Category.CHAIR, "price": 10, "unlock": 1, "charm": 0, "tags": [&"rustic", &"diner"], "footprint": Vector2i(1, 1), "solid": false, "capacity": 1, "seats": [Vector2i(0, 0)], "materials": ["wood"]},
	{"id": &"rounded_chair", "name": "Rounded chair", "asset": "chairRounded", "category": ItemDef.Category.CHAIR, "price": 18, "unlock": 2, "charm": 1, "tags": [&"cosy", &"cafe"], "footprint": Vector2i(1, 1), "solid": false, "capacity": 1, "seats": [Vector2i(0, 0)], "materials": ["wood"]},
	{"id": &"modern_chair", "name": "Cushioned modern chair", "asset": "chairModernCushion", "category": ItemDef.Category.CHAIR, "price": 30, "unlock": 3, "charm": 1, "tags": [&"modern"], "footprint": Vector2i(1, 1), "solid": false, "capacity": 1, "seats": [Vector2i(0, 0)], "materials": []},
	{"id": &"modern_frame_chair", "name": "Framed modern chair", "asset": "chairModernFrameCushion", "category": ItemDef.Category.CHAIR, "price": 35, "unlock": 4, "charm": 1, "tags": [&"modern"], "footprint": Vector2i(1, 1), "solid": false, "capacity": 1, "seats": [Vector2i(0, 0)], "materials": []},
	{"id": &"bar_stool", "name": "Bar stool", "asset": "stoolBar", "category": ItemDef.Category.CHAIR, "price": 20, "unlock": 1, "charm": 0, "tags": [&"diner", &"bar"], "footprint": Vector2i(1, 1), "solid": false, "capacity": 1, "seats": [Vector2i(0, 0)], "materials": ["wood"]},
	{"id": &"square_bar_stool", "name": "Square bar stool", "asset": "stoolBarSquare", "category": ItemDef.Category.CHAIR, "price": 25, "unlock": 3, "charm": 1, "tags": [&"rustic", &"bar"], "footprint": Vector2i(1, 1), "solid": false, "capacity": 1, "seats": [Vector2i(0, 0)], "materials": ["wood"]},
	{"id": &"bench", "name": "Two-seat bench", "asset": "bench", "category": ItemDef.Category.CHAIR, "price": 35, "unlock": 2, "charm": 1, "tags": [&"rustic", &"cosy"], "footprint": Vector2i(2, 1), "solid": false, "capacity": 2, "seats": [Vector2i(0, 0), Vector2i(1, 0)], "materials": ["wood"], "bench": true},
	{"id": &"cushioned_bench", "name": "Cushioned two-seat bench", "asset": "benchCushion", "category": ItemDef.Category.CHAIR, "price": 50, "unlock": 3, "charm": 2, "tags": [&"cosy"], "footprint": Vector2i(2, 1), "solid": false, "capacity": 2, "seats": [Vector2i(0, 0), Vector2i(1, 0)], "materials": ["wood"], "bench": true},
	{"id": &"lounge_chair", "name": "Lounge chair", "asset": "loungeChair", "category": ItemDef.Category.CHAIR, "price": 80, "unlock": 5, "charm": 2, "tags": [&"cosy", &"modern"], "footprint": Vector2i(1, 1), "solid": false, "capacity": 1, "seats": [Vector2i(0, 0)], "materials": ["wood"]},
	{"id": &"round_table", "name": "Round table", "asset": "tableRound", "category": ItemDef.Category.TABLE, "price": 55, "unlock": 2, "charm": 1, "tags": [&"cosy", &"cafe"], "footprint": Vector2i(2, 2), "solid": true, "capacity": 2, "seats": [], "materials": ["wood"]},
	{"id": &"cloth_table", "name": "Tablecloth dining table", "asset": "tableCloth", "category": ItemDef.Category.TABLE, "price": 80, "unlock": 3, "charm": 2, "tags": [&"cosy"], "footprint": Vector2i(2, 1), "solid": true, "capacity": 2, "seats": [], "materials": ["wood"]},
	{"id": &"cross_table", "name": "Cross-legged table", "asset": "tableCross", "category": ItemDef.Category.TABLE, "price": 70, "unlock": 4, "charm": 1, "tags": [&"rustic"], "footprint": Vector2i(2, 1), "solid": true, "capacity": 2, "seats": [], "materials": ["wood"]},
	{"id": &"glass_table", "name": "Glass dining table", "asset": "tableGlass", "category": ItemDef.Category.TABLE, "price": 120, "unlock": 6, "charm": 2, "tags": [&"modern"], "footprint": Vector2i(2, 1), "solid": true, "capacity": 2, "seats": [], "materials": []},
]

## Horizontal seat surfaces measured from the unchanged approved GLB triangles.
## Lounge seating is the broad low carpet plane; final fit still needs pixels.
const SEAT_SURFACE_Y: Dictionary[StringName, float] = {
	&"wooden_chair": 0.24, &"rounded_chair": 0.22,
	&"modern_chair": 0.24, &"modern_frame_chair": 0.24,
	&"bar_stool": 0.435, &"square_bar_stool": 0.405,
	&"bench": 0.24, &"cushioned_bench": 0.24, &"lounge_chair": 0.23,
}

var _views: Array[PropView] = []


func after_each() -> void:
	for view: PropView in _views:
		view.free()
	_views.clear()


func test_seating_and_table_catalogue_matches_the_approved_entries() -> void:
	for entry: Dictionary in CASES:
		var item_id: StringName = entry["id"]
		var definition: ItemDef = load("res://data/items/%s.tres" % item_id) as ItemDef
		assert_not_null(definition, String(item_id))
		if definition == null:
			continue
		assert_eq(definition.id, item_id)
		assert_eq(definition.display_name, entry["name"])
		assert_eq(definition.category, entry["category"])
		assert_eq(definition.footprint, entry["footprint"])
		assert_eq(definition.solid, entry["solid"])
		assert_true(definition.work_cells.is_empty(), String(item_id))
		assert_eq(definition.seat_cells, entry["seats"])
		assert_eq(definition.capacity, entry["capacity"])
		assert_eq(definition.price, entry["price"])
		assert_eq(definition.unlock_level, entry["unlock"])
		assert_eq(definition.charm, entry["charm"])
		assert_eq(definition.theme_tags, entry["tags"])
		assert_eq(definition.paintable, not (entry["materials"] as Array).is_empty())
		assert_eq(definition.view_scene.resource_path, "res://assets/props/%s.tscn" % item_id)

		var view: PropView = definition.view_scene.instantiate() as PropView
		assert_not_null(view, String(item_id))
		if view == null:
			continue
		_views.append(view)
		view.prepare()
		assert_eq(view.footprint, definition.footprint, String(item_id))
		assert_eq(view.body_material_names, PackedStringArray(entry["materials"]), String(item_id))
		var parts: Array[Node3D] = []
		for child: Node in view.get_children():
			var part: Node3D = child as Node3D
			assert_not_null(part, String(item_id))
			if part == null:
				continue
			parts.append(part)
			assert_false(part.has_meta(&"seat_cell"), "%s keeps seat cells in its definition only" % item_id)
			var art: Node3D = part.get_node("Art") as Node3D
			var model: Node3D = art.get_node("Model") as Node3D
			assert_eq(model.scene_file_path, "res://assets/kenney/furniture/%s.glb" % entry["asset"])
			assert_almost_eq(art.rotation.y, PI)
			assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
		assert_eq(parts.size(), 2 if entry.has("bench") else 1, String(item_id))

		var bounds: AABB = view.get_combined_aabb()
		assert_true(bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0, String(item_id))
		assert_almost_eq(bounds.position.y, 0.0, 0.0001, String(item_id))
		assert_almost_eq(bounds.get_center().x, 0.0, 0.0001, String(item_id))
		assert_almost_eq(bounds.get_center().z, 0.0, 0.0001, String(item_id))
		if SEAT_SURFACE_Y.has(item_id):
			assert_almost_eq(view.seat_surface_y, SEAT_SURFACE_Y[item_id])
			assert_almost_eq(view.seat_surface_height(), SEAT_SURFACE_Y[item_id] * ArtScale.FURNITURE_SCALE)
			assert_true(view.seat_surface_height() > 0.0)
			assert_true(view.seat_surface_height() <= bounds.position.y + bounds.size.y + 0.0001)
		else:
			assert_eq(view.seat_surface_height(), 0.0, "a table does not invent its own seating height")
		for quarter_turns: int in range(4):
			var rotation: Transform3D = Transform3D(Basis(Vector3.UP, float(quarter_turns) * PI * 0.5), Vector3.ZERO)
			var rotated_bounds: AABB = rotation * bounds
			var rotated_footprint: Vector2i = definition.footprint
			if quarter_turns % 2 == 1:
				rotated_footprint = Vector2i(definition.footprint.y, definition.footprint.x)
			var allowed: Rect2 = Rect2(
				-Vector2(rotated_footprint) * GridMath.CELL_SIZE * 0.5,
				Vector2(rotated_footprint) * GridMath.CELL_SIZE
			).grow(0.05)
			assert_true(allowed.encloses(_xz_rect(rotated_bounds)), "%s fits at quarter turn %d" % [item_id, quarter_turns])
			assert_almost_eq(rotated_bounds.position.y, 0.0, 0.0001, String(item_id))


func test_bench_wrappers_use_two_unchanged_centered_kit_models() -> void:
	for item_id: StringName in [&"bench", &"cushioned_bench"]:
		var definition: ItemDef = load("res://data/items/%s.tres" % item_id) as ItemDef
		var view: PropView = definition.view_scene.instantiate() as PropView
		_views.append(view)
		view.prepare()
		assert_eq(view.get_child_count(), 2, String(item_id))
		for index: int in range(2):
			var part: Node3D = view.get_child(index) as Node3D
			var expected_x: float = -0.25 if index == 0 else 0.25
			assert_almost_eq(part.position.x, expected_x, 0.0001, String(item_id))
			assert_almost_eq(part.position.y, 0.0, 0.0001, String(item_id))
			assert_almost_eq(part.position.z, 0.0, 0.0001, String(item_id))
			assert_false(part.has_meta(&"seat_cell"), "bench seats are authored in ItemDef")
			var model: Node3D = part.get_node("Art/Model") as Node3D
			var expected_asset: String = "bench" if item_id == &"bench" else "benchCushion"
			assert_eq(model.scene_file_path, "res://assets/kenney/furniture/%s.glb" % expected_asset)
			var part_bounds: AABB = part.transform * PropView._children_aabb(part)
			assert_almost_eq(part_bounds.get_center().x, expected_x, 0.0001, String(item_id))
			assert_almost_eq(part_bounds.get_center().z, 0.0, 0.0001, String(item_id))


func test_bar_counter_keeps_kit_parts_and_supports_two_independent_stools_at_every_rotation() -> void:
	var counter_def: ItemDef = load("res://data/items/bar_counter.tres") as ItemDef
	var stool_def: ItemDef = load("res://data/items/bar_stool.tres") as ItemDef
	assert_eq(counter_def.display_name, "Bar counter")
	assert_eq(counter_def.category, ItemDef.Category.TABLE)
	assert_eq(counter_def.footprint, Vector2i(2, 1))
	assert_true(counter_def.seat_cells.is_empty(), "only placed facing stools supply seats")
	assert_eq(counter_def.unlock_level, 4)
	assert_true(counter_def.price > 0)
	assert_eq(counter_def.theme_tags, [&"bar", &"modern"] as Array[StringName])
	assert_true(counter_def.serve_across, "guests at the counter are served across it (FK-083)")
	var view: PropView = counter_def.view_scene.instantiate() as PropView
	_views.append(view)
	view.prepare()
	assert_eq(view.get_child_count(), 3)
	assert_eq(view.body_material_names, PackedStringArray(["wood"]))
	var bounds: AABB = view.get_combined_aabb()
	assert_almost_eq(bounds.position.y, 0.0, 0.0001)
	assert_almost_eq(bounds.get_center().x, 0.0, 0.0001)
	assert_almost_eq(bounds.get_center().z, 0.0, 0.0001)
	for index: int in range(3):
		var part: Node3D = view.get_child(index) as Node3D
		var art: Node3D = part.get_node("Art") as Node3D
		var model: Node3D = art.get_node("Model") as Node3D
		var asset: String = "kitchenBarEnd" if index == 2 else "kitchenBar"
		assert_eq(model.scene_file_path, "res://assets/kenney/furniture/%s.glb" % asset)
		assert_eq(model.scale, Vector3.ONE, "kit models are never stretched")
		assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
		assert_almost_eq(art.rotation.y, PI)
	for turns: int in range(4):
		var transform: Transform3D = Transform3D(Basis(Vector3.UP, -float(turns) * PI * 0.5), Vector3.ZERO)
		var footprint: Vector2i = GridMath.rotated_footprint(counter_def.footprint, turns)
		var allowed: Rect2 = Rect2(-Vector2(footprint) * GridMath.CELL_SIZE * 0.5,
			Vector2(footprint) * GridMath.CELL_SIZE).grow(0.05)
		assert_true(allowed.encloses(_xz_rect(transform * bounds)), "assembled counter fits at every rotation")
		var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
		var counter: PlacedItem = grid.place_def(counter_def, Vector2i(5, 5), turns)
		for index: int in range(2):
			var cell: Vector2i = counter.origin + GridMath.rotate_cell(Vector2i(index, 1), counter_def.footprint, turns)
			var stool: PlacedItem = grid.place_def(stool_def, cell, turns)
			assert_not_null(stool)
			if stool == null:
				continue
			assert_eq(grid.dining_table_id(cell), counter.id)
			assert_eq(grid.dining_furnishing_id(cell), stool.id)
			assert_true(counter.reserve(cell, 1210 + index))
			assert_eq(stool.reserved_by(cell), -1, "table keeps the guest booking")
		assert_eq(counter.seat_cells.size(), 2)
		assert_true(counter_def.seat_cells.is_empty(), "runtime links never change authored content")


func _xz_rect(bounds: AABB) -> Rect2:
	return Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
