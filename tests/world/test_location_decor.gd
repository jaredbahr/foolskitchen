extends TestCase
## Location interiors (#596): the made starter decor (assets/made/location_decor/,
## tools/build_location_decor.py) and the crockery dresser built from kit pieces.
## Every piece is ordinary decor, buyable at every lot.

const MADE: String = "res://assets/made/location_decor/%s.glb"
const METRICS: String = "res://assets/made/location_decor/location_decor.metrics.json"
const BUDGET: int = 800
## id: [layer, footprint width, price, unlock level, charm]
const CASES: Dictionary[StringName, Array] = {
	&"lifebuoy": [ItemDef.PlacementLayer.WALL, 1, 30, 2, 2],
	&"fishing_net": [ItemDef.PlacementLayer.WALL, 3, 40, 2, 2],
	&"bunting": [ItemDef.PlacementLayer.WALL, 3, 30, 1, 0],
	&"wheat_sheaf": [ItemDef.PlacementLayer.WALL, 1, 20, 1, 1],
	&"skyline_print": [ItemDef.PlacementLayer.WALL, 2, 40, 3, 2],
	&"surfboard": [ItemDef.PlacementLayer.WALL, 1, 45, 2, 2],
	&"beach_sign": [ItemDef.PlacementLayer.WALL, 2, 30, 1, 2],
	&"flour_sacks": [ItemDef.PlacementLayer.NORMAL, 1, 20, 1, 1],
	&"barrel": [ItemDef.PlacementLayer.NORMAL, 1, 25, 2, 1],
	&"shell_jars": [ItemDef.PlacementLayer.SURFACE_DECOR, 1, 15, 1, 1],
}

var _views: Array[Node] = []


func after_each() -> void:
	for view: Node in _views:
		view.free()
	_views.clear()


func test_made_decor_is_buyable_everywhere_with_its_own_model() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	for id: StringName in CASES:
		var entry: Array = CASES[id]
		var definition: ItemDef = content.item(id)
		assert_not_null(definition, String(id))
		if definition == null:
			continue
		assert_eq(definition.category, ItemDef.Category.DECOR, String(id))
		assert_eq(int(definition.placement_layer), int(entry[0]), String(id))
		assert_eq(definition.footprint, Vector2i(int(entry[1]), 1), String(id))
		assert_eq(definition.price, int(entry[2]), String(id))
		assert_eq(definition.unlock_level, int(entry[3]), String(id))
		assert_eq(definition.charm, int(entry[4]), String(id))
		assert_true(definition.lot_tags.is_empty(), "%s is sold at every lot" % id)
		assert_false(definition.paintable, String(id))
		var view: PropView = definition.view_scene.instantiate() as PropView
		_views.append(view)
		var art: Node3D = view.get_child(0).get_node("Art") as Node3D
		assert_eq(art.get_node("Model").scene_file_path, MADE % id, String(id))
		assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE, String(id))
	# Bunting hangs only on the street front, over a door or window, like an awning.
	var bunting: ItemDef = content.item(&"bunting")
	assert_eq(bunting.wall_mount, ItemDef.WallMount.EXTERIOR)
	assert_eq(bunting.exterior_band, ExteriorSupport.Band.CANOPY)


func test_made_models_stay_small() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(METRICS))
	var assets: Dictionary = report.get("assets", {})
	# Every decor item, plus the cord the ceiling pendant now hangs from.
	assert_eq(assets.size(), CASES.size() + 1)
	var ids: Array[StringName] = CASES.keys()
	ids.append(&"pendant_cord")
	for id: StringName in ids:
		assert_true(assets.has(String(id)), String(id))
		if assets.has(String(id)):
			assert_true(int(assets[String(id)]["triangles"]) < BUDGET, "%s stays under %d triangles" % [id, BUDGET])


func test_the_crockery_dresser_is_two_kit_bookcases_with_kit_crockery() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var dresser: ItemDef = content.item(&"crockery_dresser")
	assert_eq(dresser.footprint, Vector2i(2, 1))
	assert_true(dresser.solid)
	assert_eq(dresser.price, 90)
	assert_eq(dresser.charm, 3)
	var view: PropView = dresser.view_scene.instantiate() as PropView
	_views.append(view)
	var food: int = 0
	for part: Node in view.get_children():
		var model: Node = part.get_node("Art/Model")
		assert_true(model.scene_file_path.begins_with("res://assets/kenney/"), "%s is a kit piece" % part.name)
		if part.get_meta(&"art_group", &"furniture") == &"food":
			food += 1
	assert_true(food >= 6, "plates, bowls, cups and mugs on its shelves")
