extends TestCase
## D25: floor types. Every cell starts as the free wide planks in the shop's
## own floor colour (nothing stored); laying another type costs its price per
## tile and refunds half the old one, morning or closed only; recolouring is
## free at any time; locked types wait for their owner level; a room fill
## stops at walls and room edges; removed floor forgets its look and undo
## brings it back; saves keep the looks (forgiving), older saves are all
## default, and the vibe sees exactly the old whole-floor paint by default.
## Grid: the starting shell is x 0..13, y 0..10; kitchen x 1..12, y 1..3 plus
## (5..7, 4); dining x 1..12, y 5..9 plus (6..7, 10); street entry (6..7, 11).

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const START_CASH: int = 1000

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = START_CASH
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null
	_ledger = null


func test_every_shop_starts_as_default_planks_with_nothing_stored() -> void:
	assert_eq(_editor.floors.count(), 0)
	var look: FloorFinishes.Finish = _editor.floors.finish(Vector2i(3, 6))
	assert_eq(look.style, FloorStyleDef.DEFAULT_ID)
	assert_eq(look.swatch, LAYOUT.floor_swatch_id)
	assert_eq(look.accent, &"")
	var snapshot: Dictionary = _editor.to_dict()
	assert_eq(int(snapshot["version"]), 5)
	assert_eq(snapshot["floor_style_id"], "planks")
	assert_eq(snapshot["floors"], [] as Array[Array])


func test_laying_costs_per_tile_and_replacing_refunds_half() -> void:
	var cells: Array[Vector2i] = _rect(2, 6, 2, 2)
	var herringbone: Dictionary[Vector2i, FloorFinishes.Finish] = _editor.lay_changes(cells, &"herringbone", &"walnut")
	var check: EditCheck = _editor.check_flooring(herringbone)
	assert_true(check.ok, check.why)
	assert_eq(check.cost, 4 * 3, "four tiles at $3")
	assert_eq(check.refund, 0, "the free planks refund nothing")
	assert_true(_editor.apply_flooring(herringbone), _editor.last_check.why)
	assert_eq(_ledger.cash, START_CASH - 12)
	assert_eq(_editor.last_cash_change, -12)
	assert_eq(_editor.floors.finish(Vector2i(3, 7)).style, &"herringbone")
	assert_eq(_editor.floors.count(), 4)
	# Narrow planks ($1) over herringbone: $4, refund half of $3 per tile ($1 each).
	check = _editor.check_flooring(_editor.lay_changes(cells, &"narrow_planks", &"honey"))
	assert_eq([check.cost, check.refund], [4, 4])
	# A recolour of the same floor type is free.
	check = _editor.check_flooring(_editor.recolour_changes(cells, &"clay"))
	assert_true(check.ok, check.why)
	assert_eq([check.cost, check.refund], [0, 0])
	assert_true(_editor.apply_flooring(_editor.recolour_changes(cells, &"clay")))
	assert_eq(_ledger.cash, START_CASH - 12, "recolouring books nothing")
	assert_eq(_editor.floors.finish(Vector2i(2, 6)).swatch, &"clay")
	assert_eq(_editor.floors.finish(Vector2i(2, 6)).style, &"herringbone")
	# Back to the default planks: stored nothing again.
	assert_true(_editor.apply_flooring(_editor.lay_changes(cells, &"planks", LAYOUT.floor_swatch_id)))
	assert_eq(_editor.floors.count(), 0)
	assert_eq(_ledger.cash, START_CASH - 12 + 4, "half of $3 per tile, rounded down")
	var again: EditCheck = _editor.check_flooring(_editor.lay_changes(cells, &"planks", LAYOUT.floor_swatch_id))
	assert_eq(again.why, ShopEditor.FLOORS_ALREADY)
	assert_eq(_editor.check_flooring(_editor.lay_changes([Vector2i(0, 0)] as Array[Vector2i], &"checker", &"cream")).why,
		ShopEditor.FLOORS_NOT_FLOOR, "walls take no floor")


func test_laying_is_closed_only_and_recolouring_works_during_service() -> void:
	var cells: Array[Vector2i] = _rect(2, 6, 2, 1)
	assert_true(_editor.apply_flooring(_editor.lay_changes(cells, &"narrow_planks", &"honey")))
	_sim.world.clock.start_service()
	var lay: EditCheck = _editor.check_flooring(_editor.lay_changes(_rect(5, 6, 1, 1), &"herringbone", &"walnut"))
	assert_false(lay.ok)
	assert_eq(lay.why, ShopEditor.FLOORS_CLOSED)
	var cash: int = _ledger.cash
	assert_true(_history.apply_flooring(_editor.recolour_changes(cells, &"sage")), _editor.last_check.why)
	assert_eq(_editor.floors.finish(Vector2i(3, 6)).swatch, &"sage")
	assert_eq(_ledger.cash, cash)
	assert_eq(_history.undo_count(), 0, "service-time recolours are not undo entries, like paint")


func test_locked_floor_types_wait_for_their_level() -> void:
	_editor.set_owner_level(1)
	var cells: Array[Vector2i] = _rect(2, 6, 1, 1)
	assert_true(_editor.check_flooring(_editor.lay_changes(cells, &"narrow_planks", &"honey")).ok, "starter set")
	assert_true(_editor.check_flooring(_editor.lay_changes(cells, &"herringbone", &"walnut")).ok, "starter set")
	assert_eq(_editor.check_flooring(_editor.lay_changes(cells, &"small_tile", &"cream")).why, "Unlocks at level 2")
	assert_eq(_editor.check_flooring(_editor.lay_changes(cells, &"checker", &"cream", &"charcoal")).why,
		"Unlocks at level 3")
	_editor.set_owner_level(3)
	assert_true(_editor.check_flooring(_editor.lay_changes(cells, &"checker", &"cream", &"charcoal")).ok)
	var bigger: FloorStyleDef = FloorStyleDef.new()
	bigger.unlock_tier = 2
	assert_false(bigger.unlocked(99))
	assert_eq(bigger.locked_reason(99), "Unlocks with a bigger restaurant")
	assert_eq(_content.floor_style(&"checker").locked_reason(3), "")
	assert_eq(_editor.check_flooring(_editor.lay_changes(cells, &"marble", &"cream")).why, "Unknown floor type")
	assert_eq(_editor.check_flooring(_editor.lay_changes(cells, &"checker", &"neon")).why, "Unknown colour")


func test_fill_room_stops_at_walls_doorways_and_other_rooms() -> void:
	var kitchen: Array[Vector2i] = _editor.floor_room_cells(Vector2i(3, 2))
	assert_eq(kitchen.size(), 12 * 3 + 3, "the kitchen, its pass openings included")
	assert_false(kitchen.has(Vector2i(6, 5)), "the dining room is another room")
	var dining: Array[Vector2i] = _editor.floor_room_cells(Vector2i(3, 6))
	assert_eq(dining.size(), 12 * 5 + 2)
	assert_eq(_editor.floor_room_cells(Vector2i(0, 0)), [] as Array[Vector2i], "a wall is no room")
	# An interior wall with a doorway across the dining room splits it in two.
	var grid: SimGrid = _sim.world.grid
	var wall: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 10):
		wall[Vector3i(9, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.DOORWAY if y == 7 else SimGrid.Segment.WALL
	grid.set_segments(wall)
	assert_eq(_editor.floor_room_cells(Vector2i(3, 6)).size(), 8 * 5 + 2, "x 1..8 plus the street opening")
	assert_eq(_editor.floor_room_cells(Vector2i(10, 6)).size(), 4 * 5)
	# The connected same look stops at the same walls.
	assert_eq(_editor.floor_area_cells(Vector2i(10, 6)).size(), 4 * 5)
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(10, 6, 2, 2), &"herringbone", &"walnut")))
	assert_eq(_editor.floor_area_cells(Vector2i(11, 7)), _rect(10, 6, 2, 2))
	assert_eq(_editor.floor_area_cells(Vector2i(12, 9)).size(), 4 * 5 - 4)


func test_removed_floor_forgets_its_look_and_undo_brings_it_back() -> void:
	var lot: Array[Vector2i] = _rect(14, 0, 1, 10)
	assert_true(_history.apply_floor(lot, true), _editor.last_check.why)
	assert_eq(_editor.floors.finish(Vector2i(14, 5)).style, FloorStyleDef.DEFAULT_ID, "new floor is the default")
	assert_true(_history.apply_flooring(_editor.lay_changes(_rect(14, 2, 1, 3), &"narrow_planks", &"sage")))
	assert_true(_history.apply_floor(lot, false), _editor.last_check.why)
	assert_eq(_editor.floors.count(), 0, "the looks went with the floor")
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.floors.count(), 3)
	assert_eq(_editor.floors.finish(Vector2i(14, 3)).style, &"narrow_planks")
	assert_eq(_editor.floors.finish(Vector2i(14, 3)).swatch, &"sage")
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.floors.count(), 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.floors.count(), 3)


func test_history_undoes_and_redoes_floors_with_exact_cash() -> void:
	var cells: Array[Vector2i] = _rect(2, 6, 2, 2)
	assert_true(_history.apply_flooring(_editor.lay_changes(cells, &"checker", &"cream", &"charcoal")))
	assert_eq(_history.undo_label(), "lay Checker tiles")
	assert_eq(_ledger.cash, START_CASH - 8)
	assert_true(_history.apply_flooring(_editor.recolour_changes(cells, &"clay")))
	assert_eq(_history.undo_label(), "recolour the floor")
	assert_eq(_ledger.cash, START_CASH - 8)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.floors.finish(Vector2i(2, 6)).swatch, &"cream")
	assert_eq(_editor.floors.finish(Vector2i(2, 6)).accent, &"charcoal")
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.floors.count(), 0)
	assert_eq(_ledger.cash, START_CASH, "the exact charge comes back")
	assert_eq(_last_entry()["note"], ShopEditHistory.UNDO_NOTE)
	# Redo ignores the level: the floor was already accepted once.
	_editor.set_owner_level(1)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH - 8)
	assert_eq(_last_entry()["note"], ShopEditHistory.REDO_NOTE)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.floors.finish(Vector2i(3, 7)).swatch, &"clay")
	assert_eq(_editor.floors.finish(Vector2i(3, 7)).style, &"checker")
	assert_eq(_upgrades(), -8)


func test_snapshot_round_trip_keeps_the_looks() -> void:
	_editor.set_owner_level(3)
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(1, 5, 3, 2), &"checker", &"cream", &"charcoal")))
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(3, 1, 2, 1), &"small_tile", &"cream")))
	var snapshot: Dictionary = _editor.to_dict()
	assert_eq((snapshot["floors"] as Array).size(), 8)
	assert_eq((snapshot["floors"] as Array)[0], [3, 1, "small_tile", "cream", ""], "row-major")
	assert_eq((snapshot["floors"] as Array)[2], [1, 5, "checker", "cream", "charcoal"])
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(JSON.parse_string(JSON.stringify(snapshot)), LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(layout.floor_finishes.size(), 8)
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, false, true)
	assert_eq(errors, [] as Array[String])
	var copy: ShopEditor = ShopEditor.new(restored, _content, ShopEditBooks.new(_can_spend, _record), layout)
	assert_eq(copy.floors.to_rows(), _editor.floors.to_rows())
	assert_eq(copy.to_dict()["floors"], snapshot["floors"])


func test_older_snapshots_are_all_default_planks() -> void:
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(1, 5, 3, 2), &"herringbone", &"walnut")))
	var legacy: Dictionary = _editor.to_dict()
	legacy["version"] = 4
	legacy.erase("floors")
	legacy.erase("floor_style_id")
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(legacy, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	assert_eq(layout.floor_style_id, FloorStyleDef.DEFAULT_ID)
	assert_true(layout.floor_finishes.is_empty())
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, false, true)
	var copy: ShopEditor = ShopEditor.new(restored, _content, ShopEditBooks.new(_can_spend, _record), layout)
	assert_eq(copy.floors.count(), 0)


func test_saved_looks_decode_forgivingly() -> void:
	var snapshot: Dictionary = _editor.to_dict()
	snapshot["floor_style_id"] = "lava"
	snapshot["floors"] = [
		[2, 6, "herringbone", "walnut", ""],
		[2, 6, "checker", "cream", "charcoal"],
		[3, 6, "marble", "cream", ""],
		[4, 6, "checker", "neon", "glitter"],
		[0, 0, "checker", "cream", ""],
		[5, 6, "narrow_planks"],
		"junk",
		[6.5, 6, "checker", "cream", ""],
		[7, 6, "narrow_planks", "", ""],
	]
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String], "floor looks never refuse a save")
	assert_not_null(layout)
	assert_eq(layout.floor_style_id, FloorStyleDef.DEFAULT_ID, "unknown default type: the planks")
	assert_eq(layout.floor_finishes.get(Vector2i(2, 6)), PackedStringArray(["herringbone", "walnut", ""]), "first row wins")
	assert_false(layout.floor_finishes.has(Vector2i(3, 6)), "unknown type: the default")
	assert_eq(layout.floor_finishes.get(Vector2i(4, 6)), PackedStringArray(["checker", "cream", "charcoal"]),
		"unknown colours: the floor type's own")
	assert_false(layout.floor_finishes.has(Vector2i(0, 0)), "not floor")
	assert_false(layout.floor_finishes.has(Vector2i(5, 6)), "malformed")
	assert_eq(layout.floor_finishes.get(Vector2i(7, 6)), PackedStringArray(["narrow_planks", "", ""]),
		"the original brown is a colour too")
	assert_eq(layout.floor_finishes.size(), 3)
	snapshot["floors"] = "nonsense"
	assert_not_null(ShopEditor.from_dict(snapshot, LAYOUT, _content, errors))


func test_content_validation() -> void:
	assert_eq(ContentDB.validate_floor_styles(_floor_defs(), _content.swatches()), PackedStringArray())
	var styles: Array[FloorStyleDef] = _content.floor_styles()
	assert_eq(styles[0].id, FloorStyleDef.DEFAULT_ID, "catalogue order starts with the free planks")
	var broken: FloorStyleDef = FloorStyleDef.new()
	broken.id = &"herringbone"
	broken.display_name = " "
	broken.price = -1
	broken.default_swatch = &"neon"
	var with_broken: Array[FloorStyleDef] = _floor_defs()
	with_broken.append(broken)
	var errors: PackedStringArray = ContentDB.validate_floor_styles(with_broken, _content.swatches())
	for expected: String in ["duplicated", "display_name", "price", "unknown colour"]:
		assert_true(Array(errors).any(func(error: String) -> bool: return error.contains(expected)), expected)
	var without: Array[FloorStyleDef] = []
	for style: FloorStyleDef in _floor_defs():
		if style.id != FloorStyleDef.DEFAULT_ID:
			without.append(style)
	assert_true(Array(ContentDB.validate_floor_styles(without, _content.swatches())).any(
		func(error: String) -> bool: return error.contains("missing")))
	var priced: FloorStyleDef = _content.floor_style(FloorStyleDef.DEFAULT_ID).duplicate() as FloorStyleDef
	priced.price = 2
	var with_priced: Array[FloorStyleDef] = without.duplicate()
	with_priced.append(priced)
	assert_eq(ContentDB.validate_floor_styles(with_priced, _content.swatches()).size(), 1)


func test_vibe_sees_the_old_floor_paint_by_default_and_the_majority_after() -> void:
	assert_eq(_editor.floor_vibe_swatch(), _editor.floor_swatch_id)
	var before: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, _sim.menu, &"", _editor.floor_swatch_id)
	var after: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, _sim.menu, &"", _editor.floor_vibe_swatch())
	assert_eq(after.floor_paint_theme_tags, before.floor_paint_theme_tags)
	assert_true(_editor.paint_floor(&"honey"), "the legacy whole-floor paint still sets the default")
	assert_eq(_editor.floors.finish(Vector2i(3, 6)).swatch, &"honey")
	assert_eq(_editor.floor_vibe_swatch(), &"honey")
	# Guests see the dining room: the kitchen's colour never counts.
	assert_true(_editor.apply_flooring(_editor.recolour_changes(_editor.floor_room_cells(Vector2i(3, 2)), &"slate_blue")))
	assert_eq(_editor.floor_vibe_swatch(), &"honey")
	var dining: Array[Vector2i] = _editor.floor_room_cells(Vector2i(3, 6))
	assert_true(_editor.apply_flooring(_editor.recolour_changes(dining.slice(0, 40), &"sage")))
	assert_eq(_editor.floor_vibe_swatch(), &"sage", "most of the guests' floor")


func _floor_defs() -> Array[FloorStyleDef]:
	return _content.floor_styles()


func _rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in range(y, y + h):
		for column: int in range(x, x + w):
			out.append(Vector2i(column, row))
	return out


func _upgrades() -> int:
	return int(_ledger.day_totals(1).get(Ledger.UPGRADES, 0))


func _last_entry() -> Dictionary:
	var entries: Array[Dictionary] = _ledger.entries_for_day(1)
	return entries.back() if not entries.is_empty() else {}


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)
