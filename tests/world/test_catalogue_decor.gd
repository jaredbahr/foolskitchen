extends TestCase
## Focused metadata and wrapper checks for the first furniture catalogue decor set.

const CASES: Array[Dictionary] = [
	{"id": &"rug_round", "name": "Round rug", "asset": "rugRound", "price": 30, "unlock": 1, "charm": 1, "tags": [&"cosy", &"rustic"], "footprint": Vector2i(2, 2), "solid": false, "paintable": false},
	{"id": &"rug_rectangle", "name": "Rectangular rug", "asset": "rugRectangle", "price": 45, "unlock": 2, "charm": 2, "tags": [&"cosy"], "footprint": Vector2i(4, 2), "solid": false, "paintable": false},
	{"id": &"rug_square", "name": "Square rug", "asset": "rugSquare", "price": 40, "unlock": 2, "charm": 2, "tags": [&"modern"], "footprint": Vector2i(2, 2), "solid": false, "paintable": false},
	{"id": &"plant_small_1", "name": "Small plant", "asset": "plantSmall1", "price": 15, "unlock": 1, "charm": 1, "tags": [&"cosy"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
	{"id": &"plant_small_2", "name": "Leafy plant", "asset": "plantSmall2", "price": 20, "unlock": 2, "charm": 1, "tags": [&"modern", &"cafe"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
	{"id": &"plant_small_3", "name": "Tall plant", "asset": "plantSmall3", "price": 25, "unlock": 3, "charm": 1, "tags": [&"rustic"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
	{"id": &"bookcase_open_low", "name": "Low open bookcase", "asset": "bookcaseOpenLow", "price": 65, "unlock": 3, "charm": 2, "tags": [&"cosy", &"rustic"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
	{"id": &"coat_rack_standing", "name": "Standing coat rack", "asset": "coatRackStanding", "price": 25, "unlock": 2, "charm": 1, "tags": [&"diner"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
	{"id": &"speaker", "name": "Speaker", "asset": "speaker", "price": 75, "unlock": 4, "charm": 2, "tags": [&"modern", &"bar"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
	{"id": &"television_vintage", "name": "Vintage television", "asset": "televisionVintage", "price": 150, "unlock": 6, "charm": 3, "tags": [&"diner", &"bar"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
	{"id": &"side_table", "name": "Side table", "asset": "sideTable", "price": 35, "unlock": 2, "charm": 1, "tags": [&"rustic", &"cafe"], "footprint": Vector2i(1, 1), "solid": true, "paintable": true},
]

var _views: Array[PropView] = []


func after_each() -> void:
	for view: PropView in _views:
		view.free()
	_views.clear()


func test_decor_catalogue_data_and_wrappers_match_the_approved_entries() -> void:
	for entry: Dictionary in CASES:
		var item_id: StringName = entry["id"]
		var item_path: String = "res://data/items/%s.tres" % item_id
		var definition: ItemDef = load(item_path) as ItemDef
		assert_not_null(definition, String(item_id))
		if definition == null:
			continue
		assert_eq(definition.id, item_id)
		assert_eq(definition.display_name, entry["name"])
		assert_eq(definition.category, ItemDef.Category.DECOR)
		assert_eq(definition.footprint, entry["footprint"])
		assert_eq(definition.solid, entry["solid"])
		assert_true(definition.work_cells.is_empty(), String(item_id))
		assert_true(definition.seat_cells.is_empty(), String(item_id))
		assert_eq(definition.price, entry["price"])
		assert_eq(definition.unlock_level, entry["unlock"])
		assert_eq(definition.charm, entry["charm"])
		assert_eq(definition.theme_tags, entry["tags"])
		assert_eq(definition.paintable, entry["paintable"])
		assert_not_null(definition.view_scene, String(item_id))
		if definition.view_scene == null:
			continue

		var view: PropView = definition.view_scene.instantiate() as PropView
		assert_not_null(view, String(item_id))
		if view == null:
			continue
		_views.append(view)
		assert_eq(view.footprint, definition.footprint, String(item_id))
		var art: Node3D = view.get_child(0).get_node("Art") as Node3D
		var model: Node3D = art.get_node("Model") as Node3D
		assert_eq(model.scene_file_path, "res://assets/kenney/furniture/%s.glb" % entry["asset"])
		assert_almost_eq(art.rotation.y, PI)
		assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
		if definition.paintable:
			assert_eq(view.body_material_names, PackedStringArray(["wood"]), String(item_id))
		else:
			assert_true(view.body_material_names.is_empty(), String(item_id))

		var bounds: AABB = view.get_combined_aabb()
		assert_true(bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0, String(item_id))
		assert_almost_eq(bounds.position.y, 0.0, 0.0001, String(item_id))
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


func _xz_rect(bounds: AABB) -> Rect2:
	return Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
