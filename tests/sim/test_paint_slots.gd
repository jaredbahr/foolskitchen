extends TestCase
## Paint slots (#431): per-part colours and materials stay cosmetic, round-trip
## through saves, undo and blueprints, and older saves keep their exact look.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 41, errors)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _cash_change), LAYOUT)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null


func test_items_declare_two_or_three_slots_with_known_materials() -> void:
	var chair: ItemDef = _content.item(&"chair")
	assert_eq(chair.slots().size(), 2)
	assert_eq(chair.main_slot().id, &"frame")
	assert_eq(chair.main_slot().default_material, PaintFinish.WOOD)
	assert_eq(chair.slots()[1].surfaces, PackedStringArray(["carpet"]))
	assert_eq(_content.item(&"bar_counter").slots().size(), 3)
	assert_eq(_content.item(&"diner_booth").slots().size(), 3)
	# Unauthored paintable items keep the single legacy body slot.
	var coffee: ItemDef = _content.item(&"coffee_machine")
	assert_eq(coffee.slots().size(), 1)
	assert_eq(coffee.main_slot().id, &"body")
	assert_eq(coffee.main_slot().default_material, PaintFinish.PAINTED)
	assert_true(_content.item(&"stove").slots().is_empty(), "kitchen stations stay unpainted")
	for definition: ItemDef in _content.items():
		assert_true(definition.slots().size() <= ItemDef.MAX_PAINT_SLOTS, String(definition.id))
		for slot: PaintSlotDef in definition.slots():
			assert_true(PaintFinish.valid(slot.default_material), "%s %s" % [definition.id, slot.id])
	# Broken slot data is refused at load.
	var broken: ItemDef = chair.duplicate() as ItemDef
	var second: PaintSlotDef = PaintSlotDef.new()
	second.id = &"cushion"
	second.display_name = "Cushion"
	broken.paint_slots = [chair.main_slot(), second] as Array[PaintSlotDef]
	assert_false(broken.paint_slots_valid(), "a second slot must name its surfaces")


func test_slot_paint_is_free_round_trips_and_keeps_the_main_colour_for_the_vibe() -> void:
	var table: PlacedItem = _first(&"table_2")
	_sim.world.clock.phase = SimClock.Phase.OPEN
	assert_true(_editor.paint_slot(table.id, &"table", PaintFinish.METAL, &"navy"))
	assert_true(_editor.paint_slot(table.id, &"cushion", &"", &"tomato"))
	assert_false(_editor.paint_slot(table.id, &"legs", &"", &"tomato"), "unknown slot")
	assert_false(_editor.paint_slot(table.id, &"cushion", &"velvet", &"tomato"), "unknown material")
	assert_false(_editor.paint_slot(table.id, &"cushion", &"", &"mauve"), "unknown colour")
	assert_eq(table.swatch_id, &"navy", "the main slot's colour is the body swatch the vibe reads")
	assert_eq(table.paint.material(&"table"), PaintFinish.METAL)
	assert_eq(table.paint.swatch(&"cushion"), &"tomato")
	var inputs: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, [] as Array[RecipeDef])
	var found: bool = false
	for item: VibeModel.Item in inputs.items:
		found = found or item.paint_theme_tags.has(&"modern")
	assert_true(found, "navy (modern) on the main slot still votes")
	var data: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	var restored: RestaurantSim = RestaurantSim.new()
	restored.world = ShopBuilder.build(layout, _content, errors, true)
	var restored_editor: ShopEditor = ShopEditor.new(restored, _content, ShopEditBooks.new(_can_spend, _cash_change), layout)
	assert_eq(restored_editor.to_dict(), _editor.to_dict())
	var copy: PlacedItem = restored.world.grid.item(table.id)
	assert_eq(copy.swatch_id, &"navy")
	assert_eq(copy.paint.material(&"table"), PaintFinish.METAL)
	assert_eq(copy.paint.swatch(&"cushion"), &"tomato")
	# Back to Original clears the part.
	assert_true(_editor.paint_slot(table.id, &"cushion", &"", &""))
	assert_true(table.paint.swatches.is_empty())


func test_older_saves_keep_their_flat_body_paint_and_unpainted_items() -> void:
	var table: PlacedItem = _first(&"table_2")
	var plant: PlacedItem = _first(&"potted_plant")
	assert_true(_editor.paint_item(table.id, &"sage"))
	var data: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	# A version-9 save from before paint slots: rows have no "paint".
	for row: Dictionary in data["items"]:
		row.erase("paint")
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	var by_origin: Dictionary[Vector2i, ShopPlacement] = {}
	for placement: ShopPlacement in layout.placements:
		by_origin[placement.origin] = placement
	var painted: ShopPlacement = by_origin[table.origin]
	assert_eq(painted.swatch_id, &"sage", "the colour is unchanged")
	assert_eq(painted.paint.material(&"table"), PaintFinish.PAINTED,
		"the old flat coat is pinned, not swapped for the new wood default")
	assert_eq(painted.paint.swatches, {} as Dictionary[StringName, StringName])
	assert_true(by_origin[plant.origin].paint.is_empty(), "unpainted pieces stay as they came")
	# Malformed or unknown slot rows are forgiven (looks only).
	data["items"][0]["paint"] = [["nope", "wood", ""], ["frame", "velvet", "sage"], 5, ["cloth", "fabric"]]
	layout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	data["items"][0]["paint"] = "broken"
	assert_not_null(ShopEditor.from_dict(data, LAYOUT, _content, errors))


func test_shift_paints_every_piece_of_a_kind_in_the_room_as_one_undo_step() -> void:
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(_sim.world, &"table_2")
	assert_true(tables.size() >= 2)
	var ids: Array[int] = _editor.items_alike_in_room(tables[0].id)
	assert_eq(ids.size(), tables.size(), "the starter tables share the dining room")
	assert_true(_history.paint_slot(ids, &"cushion", PaintFinish.FABRIC, &"butter"))
	for table: PlacedItem in tables:
		assert_eq(table.paint.swatch(&"cushion"), &"butter")
	assert_eq(_history.undo_count(), 1)
	assert_true(_history.undo())
	for table: PlacedItem in tables:
		assert_true(table.paint.is_empty())
	assert_true(_history.redo())
	assert_eq(tables[1].paint.material(&"cushion"), PaintFinish.FABRIC)
	# A slot one of the pieces lacks refuses the whole change.
	var plant: PlacedItem = _first(&"potted_plant")
	assert_false(_history.paint_slot([tables[0].id, plant.id] as Array[int], &"cushion", &"", &"sage"))
	assert_eq(tables[0].paint.swatch(&"cushion"), &"butter")


func test_copied_look_sells_back_and_restores_on_undo() -> void:
	_editor.set_owner_level(6)
	var table: PlacedItem = _first(&"table_2")
	assert_true(_history.paint_slot([table.id] as Array[int], &"cushion", PaintFinish.FABRIC, &"berry"))
	var look: PaintLook = table.paint.copy()
	var other: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[1]
	assert_true(_history.apply_look([other.id] as Array[int], &"walnut", look))
	assert_eq(other.swatch_id, &"walnut")
	assert_eq(other.paint.swatch(&"cushion"), &"berry")
	look.set_swatch(&"cushion", &"mint")
	assert_eq(other.paint.swatch(&"cushion"), &"berry", "looks are detached copies")
	var origin: Vector2i = other.origin
	assert_true(_history.sell(other.id) >= 0)
	assert_true(_history.undo())
	var back: PlacedItem = _sim.world.grid.item_at(origin)
	assert_eq(back.swatch_id, &"walnut")
	assert_eq(back.paint.swatch(&"cushion"), &"berry", "undoing a sale brings the piece back with all its parts")


func test_blueprints_carry_slots_and_older_rows_keep_their_flat_coat() -> void:
	var table: PlacedItem = _first(&"table_2")
	assert_true(_editor.paint_slot(table.id, &"cushion", &"", &"teal"))
	assert_true(_editor.paint_slot(table.id, &"table", &"", &"birch"))
	var blueprint: Blueprint = Blueprint.capture(_sim.world.grid, [table.id] as Array[int], "Teal table")
	assert_eq(blueprint.entries[0].paint.swatch(&"cushion"), &"teal")
	var library: BlueprintLibrary = BlueprintLibrary.new()
	var messages: Array[String] = []
	var saved: Dictionary = JSON.parse_string(JSON.stringify({"version": BlueprintLibrary.VERSION, "blueprints": [blueprint.to_dict()]}))
	assert_true(library.restore(saved, _content, messages))
	var entry: ShopPlacement = library.blueprints[0].entries[0]
	assert_eq(entry.swatch_id, &"birch")
	assert_eq(entry.paint.swatch(&"cushion"), &"teal")
	assert_true(entry.paint.material(&"table").is_empty(), "Auto stays Auto")
	saved["blueprints"][0]["entries"][0].erase("paint")
	assert_true(library.restore(saved, _content, messages))
	assert_eq(library.blueprints[0].entries[0].paint.material(&"table"), PaintFinish.PAINTED)
	var reasons: Array[String] = []
	var decoded: Blueprint = BlueprintCode.decode(BlueprintCode.encode(blueprint), _content, reasons)
	assert_not_null(decoded)
	assert_eq(decoded.entries[0].paint.swatch(&"cushion"), &"teal")


func _first(id: StringName) -> PlacedItem:
	var found: Array[PlacedItem] = ShopBuilder.items_with_def(_sim.world, id)
	assert_false(found.is_empty(), "the starter layout has a %s" % id)
	return found[0] if not found.is_empty() else null


func _can_spend(_amount: int) -> bool:
	return true


func _cash_change(_amount: int, _category: StringName) -> void:
	pass


func test_a_look_pasted_on_another_kind_maps_part_by_part() -> void:
	var chair: ItemDef = _content.item(&"chair")
	var booth: ItemDef = _content.item(&"diner_booth")
	var look: PaintLook = PaintLook.new()
	look.set_material(&"frame", PaintFinish.METAL)
	look.set_swatch(&"cushion", &"mint")
	look.set_material(&"cushion", PaintFinish.FABRIC)
	var on_booth: PaintLook = PaintLook.mapped(chair, look, booth)
	assert_eq(on_booth.material(&"seat"), PaintFinish.METAL, "main to main")
	assert_eq(on_booth.swatch(&"shell"), &"mint", "second part to second part")
	assert_eq(on_booth.material(&"shell"), PaintFinish.FABRIC)
	assert_true(on_booth.swatch(&"base").is_empty(), "a part the chair lacks stays as it came")
	assert_true(_editor.look_fits(booth, on_booth))
	var same: PaintLook = PaintLook.mapped(chair, look, chair)
	assert_true(same.equals(look))
	same.set_swatch(&"cushion", &"sky")
	assert_eq(look.swatch(&"cushion"), &"mint", "a pasted look is a copy")
