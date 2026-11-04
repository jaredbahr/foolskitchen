extends TestCase
## The street A-frame sign (#292): where it may stand, what it adds to curb
## appeal, and the words on it. It lives in the exterior decor store, never in
## the grid, so it cannot block a guest's way through the door.

const TUNING: CurbAppealTuning = preload("res://data/balance/curb_appeal.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const GROUND: int = ExteriorSupport.Band.GROUND

var _content: ContentDB
var _grid: SimGrid
var _definition: ItemDef


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_grid = SimGrid.from_ascii(LAYOUT.rows)
	_definition = _content.item(&"a_frame_sign")


func after_each() -> void:
	_content = null
	_grid = null
	_definition = null


func test_item_is_a_35_dollar_level_two_street_decor_piece() -> void:
	assert_not_null(_definition)
	assert_eq(_definition.price, 35)
	assert_eq(_definition.unlock_level, 2)
	assert_eq(_definition.buy_room(), &"decor")
	assert_true(_definition.unique_per_shop)
	assert_true(_definition.placement_layer_valid())
	assert_eq(_definition.wall_mount, ItemDef.WallMount.EXTERIOR)
	assert_eq(_definition.exterior_band, ExteriorSupport.Band.GROUND)
	assert_eq(_definition.footprint, Vector2i.ONE)
	assert_eq(CatalogueText.does(_definition), "Stands on the pavement beside the door and shows your name and today's special")


func test_only_the_pavement_beside_the_street_door_is_allowed() -> void:
	var decor: WallDecor = WallDecor.new()
	for offset: int in [-1, 2]:
		assert_eq(decor.problem(_grid, _definition, _front(offset)), "", "beside the door at %d" % offset)
	for offset: int in [-4, -3, -2, 3, 4, 5]:
		assert_eq(decor.problem(_grid, _definition, _front(offset)), ExteriorSupport.BESIDE_DOOR_ONLY,
			"too far from the door at %d" % offset)


func test_the_cells_in_front_of_the_door_are_the_guests_way_and_stay_clear() -> void:
	var decor: WallDecor = WallDecor.new()
	var entries: Array[Vector2i] = _grid.entries()
	assert_eq(entries.size(), 2)
	for offset: int in [0, 1]:
		var anchor: Vector3i = _front(offset)
		assert_eq(decor.problem(_grid, _definition, anchor), ExteriorSupport.DOORWAY_CLEAR)
		assert_true(entries.has(Vector2i(anchor.x, anchor.y)), "the refused cell is a real entry cell")
	for offset: int in [-1, 2]:
		var anchor: Vector3i = _front(offset)
		assert_false(entries.has(Vector2i(anchor.x, anchor.y)), "an allowed cell is never an entry")
		assert_eq(_grid.terrain(Vector2i(anchor.x, anchor.y)), SimGrid.Terrain.OUTSIDE)


func test_refused_on_inside_faces_other_bands_and_wider_spans() -> void:
	var decor: WallDecor = WallDecor.new()
	assert_ne(decor.problem(_grid, _definition, Vector3i(3, 9, 2)), "", "not on an inside wall")
	assert_ne(decor.problem(_grid, _definition, _front(-1, ExteriorSupport.Band.BODY)), "", "only the ground band")
	assert_ne(decor.problem(_grid, _definition, _front(-1, ExteriorSupport.Band.SILL)), "")
	assert_ne(ExteriorSupport.span_problem(_grid, _front(-1), 2), "", "one cell wide only")
	var other_items: Array[StringName] = [&"menu_board", &"shop_name_sign", &"neon_open_sign"]
	for id: StringName in other_items:
		assert_ne(decor.problem(_grid, _content.item(id), _front(-1)), "", "%s does not stand on the pavement" % id)


func test_a_second_sign_is_refused() -> void:
	var decor: WallDecor = WallDecor.new()
	assert_true(decor.add(&"a_frame_sign", _front(-1), 1, false, ItemDef.WallMount.EXTERIOR))
	assert_eq(decor.problem(_grid, _definition, _front(2)), WallDecor.UNIQUE)
	assert_eq(decor.problem(_grid, _definition, _front(-1)), WallDecor.UNIQUE)
	assert_eq(decor.problem(_grid, _definition, _front(-1), _front(-1)), "", "moving the one sign is fine")


func test_sign_raises_curb_appeal_by_the_authored_value_and_only_once() -> void:
	var decor: WallDecor = WallDecor.new()
	var bare: Dictionary = CurbAppealModel.evaluate(CurbAppealInputs.collect(_grid, WallFinishes.new(), decor, _content, TUNING), TUNING)
	assert_eq(bare.score, 0.0)
	assert_true(decor.add(&"a_frame_sign", _front(-1), 1, false, ItemDef.WallMount.EXTERIOR))
	var rows: Array[Dictionary] = CurbAppealInputs.collect(_grid, WallFinishes.new(), decor, _content, TUNING)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].category, &"a_frame")
	var with_sign: Dictionary = CurbAppealModel.evaluate(rows, TUNING)
	assert_almost_eq(with_sign.score, minf(TUNING.weights[&"a_frame"], TUNING.caps[&"a_frame"]), 0.0000001)
	assert_true(with_sign.score > 0.0)
	assert_true(with_sign.multiplier > bare.multiplier)
	assert_almost_eq(with_sign.multiplier - 1.0, with_sign.score / 100.0 * TUNING.max_bonus, 0.0000001)


func test_the_authored_value_is_data_not_code() -> void:
	var decor: WallDecor = WallDecor.new()
	assert_true(decor.add(&"a_frame_sign", _front(2), 1, false, ItemDef.WallMount.EXTERIOR))
	var tuned: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
	tuned.weights[&"a_frame"] = 3.0
	tuned.caps[&"a_frame"] = 3.0
	var rows: Array[Dictionary] = CurbAppealInputs.collect(_grid, WallFinishes.new(), decor, _content, tuned)
	assert_almost_eq(CurbAppealModel.evaluate(rows, tuned).score, 3.0, 0.0000001)
	tuned.item_categories.erase(&"a_frame_sign")
	assert_eq(CurbAppealInputs.collect(_grid, WallFinishes.new(), decor, _content, tuned), [] as Array[Dictionary])


func test_a_sign_that_no_longer_stands_beside_the_door_stops_counting() -> void:
	var decor: WallDecor = WallDecor.new()
	assert_true(decor.add(&"a_frame_sign", _front(-4), 1, false, ItemDef.WallMount.EXTERIOR))
	assert_eq(CurbAppealInputs.collect(_grid, WallFinishes.new(), decor, _content, TUNING), [] as Array[Dictionary])
	assert_eq(decor.lost_on(_grid), [_front(-4)] as Array[Vector3i])


func test_sign_text_has_the_name_and_the_best_margin_dish() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"burger"), _content.recipe(&"tomato_soup"), _content.recipe(&"fries")]
	var best: RecipeDef = StreetSignText.special(menu)
	var best_margin: int = best.standard_price - best.ingredient_cost()
	for recipe: RecipeDef in menu:
		assert_true(recipe.standard_price - recipe.ingredient_cost() <= best_margin)
	var text: String = StreetSignText.text("Little Lantern", menu)
	assert_eq(text, "Little Lantern\nToday: " + best.display_name)


func test_sign_text_follows_a_price_change_and_a_menu_change() -> void:
	var burger: RecipeDef = _content.recipe(&"burger")
	var soup: RecipeDef = _content.recipe(&"tomato_soup")
	var menu: Array[RecipeDef] = [burger, soup]
	var first: RecipeDef = StreetSignText.special(menu)
	var other: RecipeDef = soup if first == burger else burger
	var prices: Dictionary = {first.id: first.ingredient_cost(), other.id: other.standard_price + 50}
	assert_eq(StreetSignText.special(menu, prices), other, "repricing moves the special")
	assert_eq(StreetSignText.special([other] as Array[RecipeDef]), other)
	assert_eq(StreetSignText.special_line([] as Array[RecipeDef]), "")
	assert_eq(StreetSignText.text("Little Lantern", [] as Array[RecipeDef]), "Little Lantern")


func test_a_cafe_menu_shows_coffee() -> void:
	var coffee: RecipeDef = _content.recipe(&"coffee")
	var croissant: RecipeDef = _content.recipe(&"croissant")
	var menu: Array[RecipeDef] = [croissant, coffee, _content.recipe(&"tea")]
	assert_eq(MenuThemeText.leading_theme(menu), &"cafe")
	var prices: Dictionary = {coffee.id: 1, croissant.id: 99}
	assert_eq(StreetSignText.special(menu, prices), coffee, "a cafe concept always shows Coffee")
	assert_eq(StreetSignText.special_line(menu), "Today: Coffee")
	var diner: Array[RecipeDef] = [_content.recipe(&"burger"), coffee]
	assert_ne(MenuThemeText.leading_theme(diner), &"cafe")


func test_name_falls_back_to_the_default_for_an_unusable_name() -> void:
	assert_eq(StreetSignText.name_line("  Copper & Thyme "), "Copper & Thyme")
	assert_eq(StreetSignText.name_line(""), MenuSettings.DEFAULT_NAME)


func _front(offset: int, band: int = GROUND) -> Vector3i:
	var doors: Array[Vector2i] = ExteriorSupport.door_cells(_grid)
	assert_eq(doors.size(), 2, "the starter has its real two-cell street door")
	var into: Vector2i = -WallRules.street_side(_grid)
	var direction: int = WallFaces.DIRS.find(into)
	var along: Vector2i = WallFaces.DIRS[posmod(direction + 1, 4)]
	var first: Vector2i = doors[0]
	for cell: Vector2i in doors:
		if cell.x * along.x + cell.y * along.y < first.x * along.x + first.y * along.y:
			first = cell
	return ExteriorSupport.key_for(WallFaces.make(first + along * offset - into, direction), band)


func test_the_caps_of_every_family_sum_to_the_score_ceiling() -> void:
	var total: float = 0.0
	for category: StringName in CurbAppealTuning.CATEGORIES:
		total += TUNING.caps[category]
	assert_eq(total, 100.0, "family caps fill the 0 to 100 score exactly, never more")


func test_exact_curb_score_with_the_sign_and_a_name_board() -> void:
	var decor: WallDecor = WallDecor.new()
	assert_true(decor.add(&"a_frame_sign", _front(-1), 1, false, ItemDef.WallMount.EXTERIOR))
	assert_true(decor.add(&"shop_name_sign", ExteriorSupport.key_for(_front(0, 0), ExteriorSupport.Band.HEADER), 2,
		false, ItemDef.WallMount.EXTERIOR))
	var rows: Array[Dictionary] = CurbAppealInputs.collect(_grid, WallFinishes.new(), decor, _content, TUNING)
	var result: Dictionary = CurbAppealModel.evaluate(rows, TUNING)
	# One of each family: its authored weight (below its cap), straight from data.
	assert_almost_eq(result.score, 15.0 + 6.0, 0.0000001)
	assert_almost_eq(result.multiplier, 1.0 + 21.0 / 100.0 * 0.10, 0.0000001)


func test_placing_undoing_and_redoing_the_sign_through_the_editor() -> void:
	var setup: Dictionary = _editor_setup()
	var editor: ShopEditor = setup["editor"]
	var history: ShopEditHistory = setup["history"]
	var anchor: Vector3i = _front(-1)
	assert_true(history.hang(&"a_frame_sign", anchor))
	assert_eq(setup["ledger"].cash, 3000 - 35)
	assert_true(history.undo())
	assert_null(editor.decor.item(anchor))
	assert_eq(setup["ledger"].cash, 3000)
	assert_true(history.redo())
	assert_eq(editor.decor.item(anchor).def_id, &"a_frame_sign")
	assert_false(history.hang(&"a_frame_sign", _front(2)), "a second sign is refused")


func test_a_saved_sign_round_trips_and_a_hand_edited_second_sign_is_dropped() -> void:
	var setup: Dictionary = _editor_setup()
	var editor: ShopEditor = setup["editor"]
	var first: Vector3i = _front(-1)
	var second: Vector3i = _front(2)
	assert_true(setup["history"].hang(&"a_frame_sign", first))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(editor.to_dict()))
	assert_eq(snapshot["wall_items"], [[float(first.x), float(first.y), float(first.z), "a_frame_sign", 2.0, ""]])
	assert_true(first.z >= 20 and first.z <= 23)
	assert_eq(_decoded_rows(snapshot), editor.decor.to_rows())
	snapshot["wall_items"].append([float(second.x), float(second.y), float(second.z), "a_frame_sign", 2.0, ""])
	assert_eq(_decoded_rows(snapshot).size(), 1, "only one sign survives a hand-edited save")
	assert_eq(_decoded_rows(snapshot)[0][0], first.x)


func _editor_setup() -> Dictionary:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 240, errors, null, false)
	assert_eq(errors, [] as Array[String])
	var ledger: Ledger = Ledger.new()
	ledger.cash = 3000
	var books: ShopEditBooks = ShopEditBooks.new(func(amount: int) -> bool: return amount <= ledger.cash,
		func(amount: int, category: StringName, note: String = "") -> void: ledger.record(1, amount, category, note))
	var editor: ShopEditor = ShopEditor.new(sim, _content, books, LAYOUT)
	editor.set_owner_level(6)
	return {"editor": editor, "history": ShopEditHistory.new(editor, sim.world.grid), "ledger": ledger, "sim": sim}


## Loads a saved snapshot the way a morning load does and returns the decor rows.
func _decoded_rows(snapshot: Dictionary) -> Array[Array]:
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	var sim: RestaurantSim = RestaurantSim.create(layout, _content, 240, errors, null, false, true)
	var editor: ShopEditor = ShopEditor.new(sim, _content, ShopEditBooks.new(func(_a: int) -> bool: return true,
		func(_a: int, _c: StringName, _n: String = "") -> void: pass), layout)
	return editor.decor.to_rows()

