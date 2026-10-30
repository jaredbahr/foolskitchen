extends TestCase

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
class Catalog extends ContentDB:
	var extra: Dictionary[StringName, ItemDef] = {}
	func item(id: StringName) -> ItemDef:
		return extra[id] if extra.has(id) else super.item(id)

var _content: Catalog
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _cash: int

func before_each() -> void:
	_content = Catalog.new()
	assert_true(_content.load_all().is_empty())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_true(errors.is_empty())
	_cash = 1000
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)

func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null

func _can_spend(amount: int) -> bool:
	return amount <= _cash

func _record(amount: int, _category: StringName, _note: String = "") -> void:
	_cash += amount

func test_variant_survives_buy_move_sell_undo_redo() -> void:
	assert_true(_history.buy(&"diner_stool", Vector2i(10, 8), 0, &"", &"stool_chrome_teal"), _editor.last_check.why)
	var placed: PlacedItem = _sim.world.grid.item(_editor.last_item_id)
	assert_eq(placed.variant_id, &"stool_chrome_teal")
	assert_true(_history.move(placed.id, Vector2i(11, 8), 0))
	assert_eq(placed.variant_id, &"stool_chrome_teal")
	assert_true(_history.sell(placed.id) >= 0)
	assert_true(_history.undo())
	assert_eq(_sim.world.grid.item_at(Vector2i(11, 8)).variant_id, &"stool_chrome_teal")
	assert_true(_history.undo())
	assert_eq(_sim.world.grid.item_at(Vector2i(10, 8)).variant_id, &"stool_chrome_teal")
	assert_true(_history.undo())
	assert_eq(_cash, 1000)
	assert_true(_history.redo())
	assert_eq(_sim.world.grid.item_at(Vector2i(10, 8)).variant_id, &"stool_chrome_teal")

func test_snapshot_v7_roundtrip_and_v6_default_and_missing_look() -> void:
	assert_true(_history.buy(&"diner_stool", Vector2i(10, 8), 0, &"", &"stool_chrome_teal"))
	var saved: Dictionary = _editor.to_dict()
	assert_eq(saved.version, 7)
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(saved, LAYOUT, _content, errors)
	assert_true(errors.is_empty())
	var restored: SimWorld = ShopBuilder.build(layout, _content, errors, true)
	assert_eq(restored.grid.item_at(Vector2i(10, 8)).variant_id, &"stool_chrome_teal")
	for row: Dictionary in saved.items:
		row.erase("variant_id")
	saved.version = 6
	layout = ShopEditor.from_dict(saved, LAYOUT, _content, errors)
	assert_true(errors.is_empty())
	for entry: ShopPlacement in layout.placements:
		assert_eq(entry.variant_id, &"")
	saved.version = 7
	for row: Dictionary in saved.items:
		row.variant_id = "removed-look"
	layout = ShopEditor.from_dict(saved, LAYOUT, _content, errors)
	assert_true(errors.is_empty())
	for entry: ShopPlacement in layout.placements:
		assert_eq(entry.variant_id, &"")

func test_variant_changes_derived_theme_without_mutating_definition() -> void:
	var definition: ItemDef = _content.item(&"diner_stool")
	var before: Array[StringName] = definition.theme_tags.duplicate()
	assert_true(_history.buy(definition.id, Vector2i(10, 8), 0, &"", &"stool_chrome_teal"))
	var inputs: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, [])
	var found: bool = false
	for item: VibeModel.Item in inputs.items:
		if item.definition_id == definition.id:
			assert_eq(item.theme_tags, [&"modern"] as Array[StringName])
			found = true
	assert_true(found)
	assert_eq(definition.theme_tags, before)


func test_variant_price_delta_is_charged_refunded_and_restored_exactly() -> void:
	var definition: ItemDef = _content.item(&"potted_plant").duplicate() as ItemDef
	var original: ItemVariant = ItemVariant.new()
	original.id = &"original"
	original.display_name = "Original"
	original.theme_tags = definition.theme_tags.duplicate()
	var alternative: ItemVariant = original.duplicate() as ItemVariant
	alternative.id = &"alternative"
	alternative.display_name = "Alternative"
	alternative.price_delta = 17
	definition.variants = [original, alternative]
	_content.extra[definition.id] = definition
	assert_true(_history.buy(definition.id, Vector2i(12, 8), 0, &"", alternative.id))
	var price: int = definition.price + 17
	assert_eq(_cash, 1000 - price)
	var placed: PlacedItem = _sim.world.grid.item_at(Vector2i(12, 8))
	assert_false(_editor.paint_variant(placed.id, original.id), "free paint must not create a different-priced piece")
	assert_eq(placed.variant_id, alternative.id)
	var refund: int = _history.sell(placed.id)
	assert_eq(refund, price / 2)
	assert_eq(_cash, 1000 - price + refund)
	assert_true(_history.undo())
	assert_eq(_sim.world.grid.item_at(Vector2i(12, 8)).variant_id, alternative.id)
	assert_eq(_cash, 1000 - price)
	assert_true(_history.undo())
	assert_eq(_cash, 1000)
	_cash = definition.price
	assert_false(_editor.check_buy(definition.id, Vector2i(12, 8), 0, null, alternative.id).ok)
	assert_true(_editor.check_buy(definition.id, Vector2i(12, 8)).ok)


func test_free_variant_paint_clears_body_paint_and_undo_restores_both() -> void:
	assert_true(_history.buy(&"diner_stool", Vector2i(10, 8), 0, &"sage", &"stool_chrome_teal"))
	var placed: PlacedItem = _sim.world.grid.item_at(Vector2i(10, 8))
	var cash: int = _cash
	assert_true(_history.paint_variant(placed.id, &"stool_dark_white"))
	assert_eq(placed.variant_id, &"stool_dark_white")
	assert_eq(placed.swatch_id, &"")
	assert_eq(_cash, cash)
	assert_true(_history.undo())
	assert_eq(placed.variant_id, &"stool_chrome_teal")
	assert_eq(placed.swatch_id, &"sage")
	assert_true(_history.redo())
	assert_eq(placed.variant_id, &"stool_dark_white")
	assert_eq(placed.swatch_id, &"")
	var count: int = _history.undo_count()
	_sim.world.clock.start_service()
	assert_true(_history.paint_variant(placed.id, &"stool_chrome_red"))
	assert_eq(_history.undo_count(), count, "service paint does not extend closed-phase history")
	assert_eq(_cash, cash)
	assert_false(_editor.paint_variant(placed.id, &"missing-look"))
	assert_eq(placed.variant_id, &"stool_chrome_red")


func test_authored_variant_theme_tags_are_recognized_by_vibe_tuning() -> void:
	var tuning: VibeTuning = load("res://data/balance/vibe.tres")
	for id: StringName in [&"diner_booth", &"diner_stool"]:
		for look: ItemVariant in _content.item(id).variants:
			assert_false(look.theme_tags.is_empty())
			for tag: StringName in look.theme_tags:
				assert_true(tuning.theme_order.has(tag), "%s has an unknown vibe theme %s" % [look.id, tag])
