extends TestCase
## Curated paint stays cosmetic across editing, saving and deterministic service.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 41, errors)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _cash_change), LAYOUT)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


func test_curated_swatches_load_with_unique_ids_and_names() -> void:
	assert_eq(_content.swatches().size(), 40)
	# The original twelve keep their exact colours (#431), so old paint is unchanged.
	var legacy: Dictionary[StringName, Color] = {
		&"brick": Color(0.6627451, 0.3764706, 0.3019608), &"butter": Color(0.9019608, 0.7843137, 0.4627451),
		&"charcoal": Color(0.3843137, 0.3529412, 0.3215686), &"clay": Color(0.7137255, 0.5333333, 0.4509804),
		&"cream": Color(0.9137255, 0.8627451, 0.7647059), &"dusty_rose": Color(0.7882353, 0.5843137, 0.5686275),
		&"honey": Color(0.7882353, 0.6039216, 0.3333333), &"moss": Color(0.4078431, 0.4941176, 0.3843137),
		&"sage": Color(0.5529412, 0.6470588, 0.5490196), &"slate_blue": Color(0.4352941, 0.5490196, 0.5764706),
		&"terracotta": Color(0.7803922, 0.4823529, 0.3568627), &"walnut": Color(0.4705882, 0.3254902, 0.2352941),
	}
	for id: StringName in legacy:
		assert_eq(_content.swatch(id).color, Color(legacy[id].r, legacy[id].g, legacy[id].b, 1.0), String(id))
	# The Paint grid: six families in order, 8 + 8 + 8 + 8 + 5 + 3.
	var families: Array[StringName] = []
	for swatch: SwatchDef in _content.palette():
		families.append(swatch.family)
	assert_eq(families.count(&"neutral"), 8)
	assert_eq(families.count(&"wood"), 5)
	assert_eq(families.count(&"metal"), 3)
	assert_eq(families[0], &"neutral")
	assert_eq(families[39], &"metal")
	var ids: Dictionary[StringName, bool] = {}
	for swatch: SwatchDef in _content.swatches():
		assert_false(swatch.id.is_empty())
		assert_false(swatch.display_name.strip_edges().is_empty())
		assert_false(ids.has(swatch.id))
		ids[swatch.id] = true
	assert_not_null(_content.swatch(&"butter"))
	assert_null(_content.swatch(&"unknown"))
	var duplicate: SwatchDef = SwatchDef.new()
	duplicate.id = &"butter"
	duplicate.display_name = "Second Butter"
	var blank: SwatchDef = SwatchDef.new()
	blank.id = &"blank"
	var errors: PackedStringArray = ContentDB.validate_swatches([duplicate, duplicate, blank])
	assert_true(errors.size() >= 2)


func test_paint_is_free_during_service_and_round_trips_in_shop_save() -> void:
	var plant: PlacedItem = _item(&"potted_plant")
	_sim.world.clock.phase = SimClock.Phase.OPEN
	assert_false(_editor.can_edit())
	assert_true(_editor.paint_wall(&"sage"))
	assert_true(_editor.paint_floor(&"terracotta"))
	assert_true(_editor.paint_item(plant.id, &"walnut"))
	assert_false(_editor.paint_item(_item(&"stove").id, &"butter"))
	assert_false(_editor.paint_wall(&"missing"))
	assert_eq(plant.swatch_id, &"walnut")
	var data: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_not_null(layout)
	assert_eq(errors, [] as Array[String])
	var restored: RestaurantSim = RestaurantSim.new()
	restored.world = ShopBuilder.build(layout, _content, errors, true)
	var restored_editor: ShopEditor = ShopEditor.new(restored, _content, ShopEditBooks.new(_can_spend, _cash_change), layout)
	assert_eq(restored_editor.to_dict(), _editor.to_dict(), "JSON round-trip keeps the same paint and placements")
	assert_eq(restored_editor.wall_swatch_id, &"sage")
	assert_eq(restored_editor.floor_swatch_id, &"terracotta")
	assert_eq(restored.world.grid.items()[7].swatch_id, &"walnut")
	assert_eq(errors, [] as Array[String])


func test_move_keeps_paint_and_selling_rebuying_uses_default() -> void:
	_editor.set_owner_level(2)
	var plant: PlacedItem = _item(&"potted_plant")
	assert_true(_editor.paint_item(plant.id, &"moss"))
	assert_true(_editor.move(plant.id, Vector2i(11, 9), 1))
	assert_eq(_sim.world.grid.item(plant.id).swatch_id, &"moss")
	assert_true(_editor.sell(plant.id) >= 0)
	assert_true(_editor.buy(&"potted_plant", Vector2i(11, 9)))
	var replacement: PlacedItem = _sim.world.grid.item_at(Vector2i(11, 9))
	assert_true(replacement.id != plant.id)
	assert_eq(replacement.swatch_id, &"")


func test_unknown_and_missing_saved_swatch_ids_use_authored_defaults() -> void:
	var data: Dictionary = _editor.to_dict()
	data["wall_swatch_id"] = "unknown"
	data["floor_swatch_id"] = 10
	data["items"][7]["swatch_id"] = "unknown"
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_not_null(layout)
	assert_eq(layout.wall_swatch_id, &"")
	assert_eq(layout.floor_swatch_id, &"")
	assert_eq(layout.placements[7].swatch_id, &"")
	data.erase("wall_swatch_id")
	data.erase("floor_swatch_id")
	for row: Dictionary in data["items"]:
		row.erase("swatch_id")
	layout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_not_null(layout)
	assert_eq(layout.placements[7].swatch_id, &"")
	assert_eq(errors, [] as Array[String])


func test_painted_shop_has_identical_seeded_service_results() -> void:
	assert_true(_editor.paint_wall(&"cream"))
	assert_true(_editor.paint_floor(&"brick"))
	assert_true(_editor.paint_item(_item(&"table_2").id, &"sage"))
	var errors: Array[String] = []
	var painted: ShopLayout = ShopEditor.from_dict(_editor.to_dict(), LAYOUT, _content, errors)
	var plain_sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 93, errors)
	var painted_sim: RestaurantSim = RestaurantSim.create(painted, _content, 93, errors)
	assert_eq(errors, [] as Array[String])
	plain_sim.start_day()
	painted_sim.start_day()
	plain_sim.world.clock.start_service()
	painted_sim.world.clock.start_service()
	for tick: int in 500:
		plain_sim.advance()
		painted_sim.advance()
	assert_eq(plain_sim.served_today, painted_sim.served_today)
	assert_eq(plain_sim.lost_today, painted_sim.lost_today)
	assert_eq(plain_sim.leave_reasons_today, painted_sim.leave_reasons_today)
	assert_eq(plain_sim.world.event_log, painted_sim.world.event_log)


func _item(id: StringName) -> PlacedItem:
	for placed: PlacedItem in _sim.world.grid.items():
		if (placed.def as ItemDef).id == id:
			return placed
	return null


func _can_spend(_amount: int) -> bool:
	return true


func _cash_change(_amount: int, _category: StringName) -> void:
	pass
