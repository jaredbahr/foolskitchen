extends TestCase
## #294: the jukebox's music styles, its place in the catalogue, the vibe it adds
## (doubled in a matching theme, counted once) and how it is saved.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")
const STYLES: Array[StringName] = [&"jukebox_diner_rock", &"jukebox_cafe_jazz", &"jukebox_bar_blues"]
const STYLE_NAMES: Array[String] = ["Diner rock", "Café jazz", "Bar blues"]
const STYLE_THEMES: Array[StringName] = [&"diner", &"cafe", &"bar"]
## Free dining cells in the roomier starter shop (the tables sit on rows 7 and 8).
const SPOT_A: Vector2i = Vector2i(11, 5)
const SPOT_B: Vector2i = Vector2i(9, 5)

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _cash: int


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_true(errors.is_empty())
	_cash = 1000
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(3)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record(amount: int, _category: StringName, _note: String = "") -> void:
	_cash += amount


func test_the_item_is_a_ninety_dollar_decor_piece_unlocked_at_level_three() -> void:
	var definition: ItemDef = _content.item(&"jukebox")
	assert_not_null(definition)
	assert_eq(definition.display_name, "Jukebox")
	assert_eq(definition.category, ItemDef.Category.DECOR)
	assert_eq(definition.buy_room(), &"decor", "listed under Build > Decor")
	assert_eq(definition.price, 90)
	assert_eq(definition.unlock_level, 3)
	assert_true(definition.solid, "solid furniture, not a rug")
	assert_eq(definition.placement_layer, ItemDef.PlacementLayer.NORMAL)
	assert_true(definition.plays_music)
	assert_true(definition.charm > 0)
	assert_not_null(definition.view_scene)


func test_each_style_has_a_player_name_and_a_matching_theme() -> void:
	var definition: ItemDef = _content.item(&"jukebox")
	assert_eq(definition.variants.size(), STYLES.size())
	for index: int in STYLES.size():
		var look: ItemVariant = definition.variants[index]
		assert_eq(look.id, STYLES[index])
		assert_eq(look.display_name, STYLE_NAMES[index])
		assert_true(look.valid())
		assert_eq(look.theme_tags, [STYLE_THEMES[index]] as Array[StringName])
		assert_eq(Jukebox.style_theme(definition, look.id, VIBE.theme_order), STYLE_THEMES[index])
		assert_eq(Jukebox.style_name(definition, look.id), STYLE_NAMES[index])
		assert_eq(CatalogueText.themes_text(definition, look.id), CatalogueText.theme_label(STYLE_THEMES[index]),
			"the theme tag shown beside the style")
		assert_true(Sfx.tuning.loops.has(Jukebox.loop_id(definition, look.id)), "a music loop for " + look.display_name)
	assert_eq(definition.variant_price(&"jukebox_bar_blues"), definition.price, "every style costs the same")


func test_buying_needs_level_three_and_cash_then_places_a_default_style() -> void:
	_editor.set_owner_level(2)
	assert_false(_history.buy(&"jukebox", SPOT_A, 0), "locked below level 3")
	_editor.set_owner_level(3)
	_cash = 89
	assert_false(_history.buy(&"jukebox", SPOT_A, 0), "$90 needed")
	_cash = 1000
	assert_true(_history.buy(&"jukebox", SPOT_A, 0), _editor.last_check.why)
	assert_eq(_cash, 910)
	var placed: PlacedItem = _sim.world.grid.item(_editor.last_item_id)
	assert_eq((placed.def as ItemDef).id, &"jukebox")
	assert_eq(placed.variant_id, &"", "no style chosen means the first")
	assert_eq(Jukebox.style_name(placed.def as ItemDef, placed.variant_id), "Diner rock")
	assert_eq(Jukebox.loop_id(placed.def as ItemDef, placed.variant_id), &"jukebox_diner_rock")
	assert_eq(_sim.world.grid.item_at(SPOT_A), placed)
	assert_true(placed.solid)


func test_a_bought_style_is_kept_and_a_change_is_free_and_undoable() -> void:
	assert_true(_history.buy(&"jukebox", SPOT_A, 0, &"", &"jukebox_cafe_jazz"))
	var placed: PlacedItem = _sim.world.grid.item(_editor.last_item_id)
	assert_eq(placed.variant_id, &"jukebox_cafe_jazz")
	var cash: int = _cash
	assert_true(_history.paint_variant(placed.id, &"jukebox_bar_blues"))
	assert_eq(placed.variant_id, &"jukebox_bar_blues")
	assert_eq(_cash, cash, "switching style costs nothing")
	assert_true(_history.undo())
	assert_eq(placed.variant_id, &"jukebox_cafe_jazz")
	assert_true(_history.redo())
	assert_eq(placed.variant_id, &"jukebox_bar_blues")
	assert_false(_history.paint_variant(placed.id, &"no_such_style"), "an unknown style is refused")


func test_the_style_persists_through_save_and_load() -> void:
	assert_true(_history.buy(&"jukebox", SPOT_A, 0))
	var placed: PlacedItem = _sim.world.grid.item(_editor.last_item_id)
	assert_true(_history.paint_variant(placed.id, &"jukebox_bar_blues"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(saved, LAYOUT, _content, errors)
	assert_true(errors.is_empty(), str(errors))
	var restored: SimWorld = ShopBuilder.build(layout, _content, errors, true)
	var loaded: PlacedItem = restored.grid.item_at(SPOT_A)
	assert_not_null(loaded)
	assert_eq((loaded.def as ItemDef).id, &"jukebox")
	assert_eq(loaded.variant_id, &"jukebox_bar_blues")
	assert_eq(Jukebox.counted_item(restored.grid).variant_id, &"jukebox_bar_blues")


func test_a_matching_theme_doubles_the_jukebox_vibe_by_the_data_value() -> void:
	var charm: float = float(_content.item(&"jukebox").charm)
	var baseline: VibeModel.Result = VibeModel.evaluate(_room(&"", &""), VIBE)
	var mismatched: VibeModel.Result = VibeModel.evaluate(_room(&"jukebox", &"cafe"), VIBE)
	var matched: VibeModel.Result = VibeModel.evaluate(_room(&"jukebox", &"diner"), VIBE)
	assert_eq(baseline.active_theme, &"diner")
	assert_eq(mismatched.active_theme, &"diner")
	assert_eq(matched.active_theme, &"diner")
	# Without the matching theme the jukebox is ordinary decor: its charm, once.
	var plain_room: VibeModel.Result = VibeModel.evaluate(_room(&"jukebox", &""), VIBE)
	assert_almost_eq(mismatched.decor_points, plain_room.decor_points, 0.0001, "a wrong-theme style earns no bonus")
	assert_true(plain_room.decor_points > baseline.decor_points, "the jukebox adds vibe like other decor")
	# Matching counts its charm again: with charm above the free allowance every
	# extra charm is worth decor_points_per_charm.
	var bonus: float = charm * (VIBE.music_match_multiplier - 1.0) * VIBE.decor_points_per_charm
	assert_almost_eq(matched.decor_points - mismatched.decor_points, bonus, 0.0001, "the bonus is the data value")
	assert_eq(VIBE.music_match_multiplier, 2.0, "a match doubles it")
	assert_true(matched.score > mismatched.score)


func test_the_bonus_follows_the_shops_theme_not_just_the_style() -> void:
	# A cafe-style jukebox in a diner-themed room is not heard best; the same
	# jukebox in a cafe-themed room is.
	var in_diner: VibeModel.Result = VibeModel.evaluate(_room(&"jukebox", &"cafe"), VIBE)
	var cafe_room: VibeModel.Inputs = _room(&"jukebox", &"cafe", &"cafe")
	var in_cafe: VibeModel.Result = VibeModel.evaluate(cafe_room, VIBE)
	var cafe_plain: VibeModel.Result = VibeModel.evaluate(_room(&"jukebox", &"", &"cafe"), VIBE)
	assert_eq(in_cafe.active_theme, &"cafe")
	assert_true(in_cafe.decor_points > cafe_plain.decor_points)
	assert_eq(in_diner.active_theme, &"diner")


func test_only_one_jukebox_counts_toward_vibe() -> void:
	assert_true(_history.buy(&"jukebox", SPOT_A, 0, &"", &"jukebox_bar_blues"))
	var first: PlacedItem = _sim.world.grid.item(_editor.last_item_id)
	var one: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, [] as Array[RecipeDef])
	var one_result: VibeModel.Result = VibeModel.evaluate(one, VIBE)
	assert_true(_history.buy(&"jukebox", SPOT_B, 0, &"", &"jukebox_diner_rock"))
	var second: PlacedItem = _sim.world.grid.item(_editor.last_item_id)
	var two: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, [] as Array[RecipeDef])
	var two_result: VibeModel.Result = VibeModel.evaluate(two, VIBE)
	assert_eq(_count(one, &"jukebox"), 1)
	assert_eq(_count(two, &"jukebox"), 1, "the second jukebox is left out of the vibe")
	assert_eq(Jukebox.counted_item(_sim.world.grid), first, "the first one placed is the one that counts")
	assert_eq(_first_item(two, &"jukebox").variant_id, &"jukebox_bar_blues")
	assert_almost_eq(two_result.score, one_result.score, 0.0001)
	assert_almost_eq(two_result.decor_points, one_result.decor_points, 0.0001)
	assert_almost_eq(two_result.variety_points, one_result.variety_points, 0.0001)
	assert_almost_eq(two_result.crowding_penalty, one_result.crowding_penalty, 0.0001)
	# Selling the first hands the vibe (and the music) to the other.
	assert_true(_history.sell(first.id) >= 0)
	assert_eq(Jukebox.counted_item(_sim.world.grid), second)
	assert_eq(_first_item(VibeInputs.capture(_sim.world.grid, _content, [] as Array[RecipeDef]), &"jukebox").variant_id,
		&"jukebox_diner_rock")


func test_a_jukebox_behind_the_scenes_is_not_counted() -> void:
	# Kitchen cells are staff-only; guests never see or hear the machine there.
	var kitchen: Vector2i = Vector2i(2, 3)
	assert_ne(_sim.world.grid.room(kitchen), SimGrid.Room.DINING)
	var placed: PlacedItem = _sim.world.grid.place_def(_content.item(&"jukebox"), kitchen, 0)
	assert_not_null(placed)
	assert_null(Jukebox.counted_item(_sim.world.grid))
	assert_eq(_count(VibeInputs.capture(_sim.world.grid, _content, [] as Array[RecipeDef]), &"jukebox"), 0)


func test_the_music_loops_are_short_small_streams_on_the_effects_bus() -> void:
	assert_eq(Sfx.BUS, &"Effects", "the Effects volume controls the music")
	for style: StringName in STYLES:
		var stream: AudioStream = Sfx.tuning.loops[style]
		assert_true(stream.get_length() > 8.0 and stream.get_length() < 30.0, "%s is a short loop" % style)
		assert_true(Sfx.tuning.loop_gain_db(style) <= -12.0, "%s plays quietly" % style)


## One diner room: a table's chair and a poster set the theme; an optional
## jukebox with a style theme. `room_theme` is the tag the furniture carries.
func _room(jukebox_id: StringName, style_theme: StringName, room_theme: StringName = &"diner") -> VibeModel.Inputs:
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	for x: int in 8:
		for y: int in 6:
			inputs.floor_cells.append(Vector2i(x, y))
	for index: int in 2:
		var chair: VibeModel.Item = VibeModel.Item.new()
		chair.definition_id = &"test_chair"
		chair.category = ItemDef.Category.CHAIR
		chair.theme_tags = [room_theme] as Array[StringName]
		chair.cells = [Vector2i(index, 0)] as Array[Vector2i]
		inputs.items.append(chair)
	var poster: VibeModel.Item = VibeModel.Item.new()
	poster.definition_id = &"test_poster"
	poster.charm = 3.0
	poster.theme_tags = [room_theme] as Array[StringName]
	poster.cells = [Vector2i(3, 0)] as Array[Vector2i]
	inputs.items.append(poster)
	if jukebox_id.is_empty():
		return inputs
	var machine: VibeModel.Item = VibeModel.Item.new()
	machine.definition_id = jukebox_id
	machine.charm = float(_content.item(&"jukebox").charm)
	machine.theme_tags = [style_theme] as Array[StringName] if not style_theme.is_empty() else ([] as Array[StringName])
	machine.music_theme = style_theme
	machine.cells = [Vector2i(5, 0)] as Array[Vector2i]
	inputs.items.append(machine)
	return inputs


func _count(inputs: VibeModel.Inputs, id: StringName) -> int:
	var total: int = 0
	for item: VibeModel.Item in inputs.items:
		if item.definition_id == id:
			total += 1
	return total


func _first_item(inputs: VibeModel.Inputs, id: StringName) -> VibeModel.Item:
	for item: VibeModel.Item in inputs.items:
		if item.definition_id == id:
			return item
	return null
