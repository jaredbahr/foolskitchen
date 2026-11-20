extends TestCase
## Location interiors (#596): the made starter decor (assets/made/location_decor/,
## tools/build_location_decor.py) and the crockery dresser built from kit pieces,
## and the premium showpieces (#206) built by the same script.
## Every piece is ordinary decor, buyable at every lot.

const MADE: String = "res://assets/made/location_decor/%s.glb"
const METRICS: String = "res://assets/made/location_decor/location_decor.metrics.json"
const BUDGET: int = 800
## id: [layer, footprint width, price, unlock level, charm]
const CASES: Dictionary[StringName, Array] = {
	&"lifebuoy": [ItemDef.PlacementLayer.WALL, 1, 30, 7, 2],
	&"fishing_net": [ItemDef.PlacementLayer.WALL, 3, 40, 8, 2],
	&"bunting": [ItemDef.PlacementLayer.WALL, 3, 30, 6, 0],
	&"wheat_sheaf": [ItemDef.PlacementLayer.WALL, 1, 20, 9, 1],
	&"skyline_print": [ItemDef.PlacementLayer.WALL, 2, 40, 9, 2],
	&"surfboard": [ItemDef.PlacementLayer.WALL, 1, 45, 7, 2],
	&"beach_sign": [ItemDef.PlacementLayer.WALL, 2, 30, 6, 2],
	&"crossed_paddles": [ItemDef.PlacementLayer.WALL, 3, 55, 6, 2],
	&"millstone": [ItemDef.PlacementLayer.NORMAL, 2, 90, 8, 2],
	&"flour_sacks": [ItemDef.PlacementLayer.NORMAL, 1, 20, 6, 1],
	&"barrel": [ItemDef.PlacementLayer.NORMAL, 1, 25, 7, 1],
	&"shell_jars": [ItemDef.PlacementLayer.SURFACE_DECOR, 1, 15, 8, 1],
	# The premium showpieces (#206): solid floor pieces, priced for diminishing returns.
	&"display_case": [ItemDef.PlacementLayer.NORMAL, 2, 420, 10, 6],
	&"gramophone": [ItemDef.PlacementLayer.NORMAL, 1, 480, 11, 6],
	&"jukebox_neon": [ItemDef.PlacementLayer.NORMAL, 1, 650, 12, 7],
	&"chef_statue": [ItemDef.PlacementLayer.NORMAL, 1, 900, 13, 8],
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
		assert_eq(definition.paintable, id == &"jukebox_neon", String(id))
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


func test_premium_pieces_follow_the_charm_curve_and_only_the_deluxe_jukebox_glows() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var last_price: int = 0
	var last_charm: int = 0
	for id: StringName in [&"display_case", &"gramophone", &"jukebox_neon", &"chef_statue"]:
		var definition: ItemDef = content.item(id)
		assert_true(definition.solid, "%s stands on the floor" % id)
		assert_true(definition.price > last_price and definition.charm >= last_charm, "%s costs more and charms at least as much" % id)
		assert_true(definition.price / maxi(definition.charm, 1) > 60, "%s is for showing off, not the efficient buy" % id)
		last_price = definition.price
		last_charm = definition.charm
		assert_eq(definition.glow_color.a > 0.0, id == &"jukebox_neon", "%s glow" % id)
		assert_eq(definition.plays_music, id == &"jukebox_neon", "only the deluxe jukebox plays music (%s)" % id)
	# The plain jukebox keeps its id, level and music.
	var plain: ItemDef = content.item(&"jukebox")
	assert_true(plain.plays_music)
	assert_eq(plain.unlock_level, 3)
