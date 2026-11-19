extends TestCase
## Starter decor (#596): the pieces a lot's building comes with are flagged, and
## their charm counts half towards the vibe. The flag is saved and follows a
## moved piece; a piece bought new always counts in full.

const LOT: StringName = &"beachfront_boardwalk"
const SIGN_AT: Vector3i = Vector3i(19, 1, 0)
const MOVED_TO: Vector3i = Vector3i(13, 1, 0)
const NEW_AT: Vector3i = Vector3i(12, 2, 3)

var _content: ContentDB
var _layout: ShopLayout
var _sim: RestaurantSim
var _editor: ShopEditor


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_layout = _content.lot(LOT).base_layout
	var errors: Array[String] = []
	_sim = RestaurantSim.create(_layout, _content, 596, errors, Stock.new())
	assert_eq(errors, [] as Array[String])
	_editor = _editor_for(_sim, _layout)


func after_each() -> void:
	_editor = null
	_sim = null
	_layout = null
	_content = null


func _editor_for(sim: RestaurantSim, layout: ShopLayout) -> ShopEditor:
	var editor: ShopEditor = ShopEditor.new(sim, _content, ShopEditBooks.new(_any_spend, _no_cash), layout)
	editor.set_owner_level(5)
	return editor


func _any_spend(_amount: int) -> bool:
	return true


func _no_cash(_amount: int, _category: StringName, _note: String = "") -> void:
	pass


func _placed(sim: RestaurantSim, id: StringName) -> PlacedItem:
	for placed: PlacedItem in sim.world.grid.items():
		if (placed.def as ItemDef).id == id:
			return placed
	return null


## Each decor item's charm share in the vibe, by item id (the highest share wins).
func _shares(sim: RestaurantSim, editor: ShopEditor) -> Dictionary[StringName, float]:
	var inputs: VibeModel.Inputs = VibeInputs.capture(sim.world.grid, _content, [] as Array[RecipeDef], &"", &"",
		editor.decor_vibe_items(), {} as Dictionary[int, float], editor.decor_vibe_scales())
	var out: Dictionary[StringName, float] = {}
	for item: VibeModel.Item in inputs.items:
		if item.category == ItemDef.Category.DECOR:
			out[item.definition_id] = maxf(out.get(item.definition_id, 0.0), item.charm_scale)
	return out


func _free_guest_cell(sim: RestaurantSim, definition: ItemDef) -> Vector2i:
	var guests: Dictionary[Vector2i, bool] = RoomRules.guest_floor(sim.world.grid)
	for cell: Vector2i in guests:
		if _editor.check_move(_placed(sim, definition.id).id, cell, 0).ok:
			return cell
	return Vector2i(-1, -1)


func test_starter_decor_charm_counts_half() -> void:
	assert_eq(VibeInputs.STARTER_CHARM_SHARE, 0.5)
	var shares: Dictionary[StringName, float] = _shares(_sim, _editor)
	assert_eq(shares.get(&"potted_plant"), 0.5)
	assert_eq(shares.get(&"beach_sign"), 0.5)
	assert_true(_editor.decor.item(SIGN_AT).starter)
	# Bought pieces count in full, next to the starter ones.
	assert_true(_editor.hang(&"beach_sign", NEW_AT))
	assert_false(_editor.decor.item(NEW_AT).starter)
	var scales: Array[float] = _editor.decor_vibe_scales()
	assert_true(scales.has(1.0) and scales.has(0.5))


func test_a_sold_starter_piece_bought_again_counts_in_full() -> void:
	var plant: PlacedItem = _placed(_sim, &"potted_plant")
	assert_true(plant.starter)
	var origin: Vector2i = plant.origin
	assert_true(_editor.sell(plant.id) >= 0)
	assert_true(_editor.buy(&"potted_plant", origin))
	assert_false(_placed(_sim, &"potted_plant").starter)
	assert_eq(_shares(_sim, _editor).get(&"potted_plant"), 1.0)
	assert_true(_editor.take_down(SIGN_AT) >= 0)
	assert_true(_editor.hang(&"beach_sign", SIGN_AT))
	assert_false(_editor.decor.item(SIGN_AT).starter, "a sign hung again is bought new")


func test_undoing_a_sale_brings_the_starter_piece_back_as_starter() -> void:
	var history: ShopEditHistory = ShopEditHistory.new(_editor, _sim.world.grid)
	var plant: PlacedItem = _placed(_sim, &"potted_plant")
	assert_true(history.sell(plant.id) >= 0)
	assert_true(history.undo())
	assert_true(_placed(_sim, &"potted_plant").starter)
	assert_true(history.take_down(SIGN_AT) >= 0)
	assert_true(history.undo())
	assert_true(_editor.decor.item(SIGN_AT).starter)


func test_a_moved_starter_piece_keeps_its_flag() -> void:
	var plant: PlacedItem = _placed(_sim, &"potted_plant")
	var to: Vector2i = _free_guest_cell(_sim, plant.def as ItemDef)
	assert_ne(to, Vector2i(-1, -1), "the plant has somewhere to go")
	assert_true(_editor.move(plant.id, to, 0))
	assert_true(_placed(_sim, &"potted_plant").starter)
	var wall_to: Vector3i = MOVED_TO
	assert_true(_editor.rehang(SIGN_AT, wall_to))
	assert_true(_editor.decor.item(wall_to).starter)
	assert_eq(_shares(_sim, _editor).get(&"beach_sign"), 0.5)


func test_the_starter_flag_survives_a_save_round_trip() -> void:
	var plant: PlacedItem = _placed(_sim, &"potted_plant")
	var origin: Vector2i = plant.origin
	assert_true(_editor.move(plant.id, _free_guest_cell(_sim, plant.def as ItemDef), 0))
	assert_true(_editor.rehang(SIGN_AT, MOVED_TO))
	assert_true(_editor.buy(&"potted_plant", origin), "a new plant where the starter one stood")
	var original: Dictionary = _editor.to_dict()
	var data: Dictionary = JSON.parse_string(JSON.stringify(original))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, _layout, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	var restored: RestaurantSim = RestaurantSim.new()
	restored.world = ShopBuilder.build(layout, _content, errors, true)
	var editor: ShopEditor = ShopEditor.new(restored, _content, ShopEditBooks.new(_any_spend, _no_cash), layout)
	assert_eq(editor.to_dict(), original)
	var flags: Array[bool] = []
	for placed: PlacedItem in restored.world.grid.items():
		if (placed.def as ItemDef).id == &"potted_plant":
			flags.append(placed.starter)
	flags.sort()
	assert_eq(flags, [false, true] as Array[bool], "the moved starter plant and a bought one")
	assert_true(editor.decor.item(MOVED_TO).starter)
	assert_eq(editor.decor.starter_anchors().size(), _layout.starter_wall_items.size())


func test_an_old_save_without_flags_loads_with_full_charm() -> void:
	var data: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	data.erase("starter_wall_items")
	for row: Dictionary in data["items"]:
		row.erase("starter")
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, _layout, _content, errors)
	assert_eq(errors, [] as Array[String])
	var restored: RestaurantSim = RestaurantSim.new()
	restored.world = ShopBuilder.build(layout, _content, errors, true)
	var editor: ShopEditor = ShopEditor.new(restored, _content, ShopEditBooks.new(_any_spend, _no_cash), layout)
	for placed: PlacedItem in restored.world.grid.items():
		assert_false(placed.starter, String((placed.def as ItemDef).id))
	assert_true(editor.decor.starter_anchors().is_empty())
	assert_false(editor.decor_vibe_scales().has(0.5))
	assert_false(editor.to_dict().has("starter_wall_items"))
