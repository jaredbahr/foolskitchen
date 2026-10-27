extends TestCase
## Pure editor transactions and staging; session/save-provider wiring is separate.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

class Catalog extends ContentDB:
	var extra: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return extra[id] if extra.has(id) else super.item(id)

var _content: Catalog
var _sim: RestaurantSim
var _editor: ShopEditor
var _books: ShopEditBooks
var _cash: int = 1000
var _entries: Array[Dictionary] = []
var _changes: Array[Array] = []
var _removed: int = 0
var _try_reentry: bool = false
var _reentry_result: bool = true
var _refusal: Variant = "Pay off your bank loan first"
var _refusal_amount: int = -1


func before_each() -> void:
	_content = Catalog.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_cash = 1000
	_books = ShopEditBooks.new(_can_spend, _record_cash)
	_editor = ShopEditor.new(_sim, _content, _books)
	_sim.world.grid.cells_changed.connect(_record_cells)
	_sim.world.grid.item_removed.connect(_record_removed)


func after_each() -> void:
	_sim.world.grid.cells_changed.disconnect(_record_cells)
	_sim.world.grid.item_removed.disconnect(_record_removed)
	_editor = null
	_books = null
	_sim = null
	_content = null
	_entries.clear()
	_changes.clear()
	_removed = 0
	_try_reentry = false
	_reentry_result = true
	_refusal = "Pay off your bank loan first"
	_refusal_amount = -1


func test_partial_table_capacity_warning_is_read_only_and_uses_actual_usable_cells() -> void:
	assert_true(_sim.world.grid.remove(_sim.world.grid.item_at(Vector2i(6, 6)).id))
	_editor.set_owner_level(2)  # the four-seat table unlocks at level 2
	var before: Dictionary = _editor.to_dict()
	var cash_before: int = _cash
	var rng_before: int = _sim.rng.state
	var changes_before: int = _changes.size()
	var check: EditCheck = _editor.check_buy(&"table_4", Vector2i(6, 5))
	assert_true(check.ok)
	assert_eq(check.seat_warnings.get(0, ""), "Only 3 of 4 seats usable")
	assert_false(check.unreachable.has(0))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_cash, cash_before)
	assert_eq(_sim.rng.state, rng_before)
	assert_eq(_changes.size(), changes_before)
	assert_true(_editor.buy(&"table_4", Vector2i(6, 5)))
	var table: PlacedItem = _sim.world.grid.item_at(Vector2i(6, 5))
	assert_eq(table.seat_cells.size(), 3)
	assert_eq(DiningSeats.nominal_capacity(_sim.world.grid, table), 4)
	assert_eq(DiningSeats.largest_usable_capacity(_sim.world.grid), 3)
	assert_eq(_editor.check_current().seat_warnings.get(table.id, ""), "Only 3 of 4 seats usable")
	assert_true(_editor.move(table.id, Vector2i(6, 6), 0))
	assert_eq(DiningSeats.largest_usable_capacity(_sim.world.grid), 4)
	assert_false(_editor.check_current().seat_warnings.has(table.id))


func test_service_phases_refuse_every_edit_without_side_effects() -> void:
	var before: Dictionary = _editor.to_dict()
	for phase: SimClock.Phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		_sim.world.clock.phase = phase
		assert_false(_editor.can_edit())
		assert_false(_editor.check_move(_id(&"potted_plant"), Vector2i(11, 9), 0).ok)
		assert_false(_editor.move(_id(&"potted_plant"), Vector2i(11, 9), 0))
		assert_false(_editor.buy(&"chair", Vector2i(4, 9)))
		assert_eq(_editor.sell(_id(&"potted_plant")), -1)
		assert_false(_editor.last_check.why.is_empty())
		assert_eq(_editor.to_dict(), before)
		assert_eq(_entries.size(), 0)
		assert_eq(_changes.size(), 0)
	for phase: SimClock.Phase in [SimClock.Phase.MORNING, SimClock.Phase.CLOSED]:
		_sim.world.clock.phase = phase
		assert_true(_editor.can_edit())


func test_checks_and_invalid_spots_do_not_touch_live_state() -> void:
	var before: Dictionary = _editor.to_dict()
	var check: EditCheck = _editor.check_buy(&"chair", Vector2i(2, 8))
	assert_true(check.ok)
	assert_true(_editor.check_move(_id(&"potted_plant"), Vector2i(11, 9), 1).ok)
	assert_true(_editor.check_sell(_id(&"potted_plant")).ok)
	assert_false(_editor.move(_id(&"potted_plant"), Vector2i(-1, 0), 0))
	assert_false(_editor.last_check.why.is_empty())
	assert_false(_editor.buy(&"chair", Vector2i(1, 1)))
	assert_false(_editor.buy(&"not_an_item", Vector2i(4, 9)))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_changes.size(), 0)
	assert_eq(_entries.size(), 0)
	assert_eq(_sim.world.now, 0)


func test_move_and_rotate_preserve_identity_order_and_books() -> void:
	var id: int = _id(&"potted_plant")
	var item: PlacedItem = _sim.world.grid.item(id)
	var order: Array[PlacedItem] = _sim.world.grid.items()
	assert_true(_editor.move(id, Vector2i(11, 9), 0))
	assert_true(_sim.world.grid.item(id) == item)
	assert_eq(item.origin, Vector2i(11, 9))
	assert_eq(_changes.size(), 1)
	assert_true(_editor.move(id, Vector2i(11, 9), 1))
	assert_eq(item.quarter_turns, 1)
	assert_eq(_changes.size(), 2)
	assert_eq(_sim.world.grid.items(), order)
	assert_false(item.removed)
	assert_eq(_removed, 0)
	assert_eq(_entries.size(), 0)
	assert_true(_editor.move(id, Vector2i(11, 9), 1))
	assert_eq(_changes.size(), 2, "identical pose is a no-op")


func test_grid_relocation_rotates_cells_and_emits_one_coherent_union() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_station"
	definition.footprint = Vector2i(2, 1)
	definition.work_cells = [Vector2i(0, -1)]
	definition.seat_cells = [Vector2i(2, 0)]
	var item: PlacedItem = grid.place_def(definition, Vector2i(2, 2))
	grid.place_def(definition, Vector2i(6, 6))
	grid.set_terrain(Vector2i(6, 0), SimGrid.Terrain.WALL)
	grid.cells_changed.connect(_record_cells)
	grid.item_removed.connect(_record_removed)
	assert_true(grid.relocate_def(item.id, Vector2i(3, 2), 1))
	assert_true(grid.item(item.id) == item)
	assert_null(grid.item_at(Vector2i(2, 2)))
	assert_true(grid.item_at(Vector2i(3, 3)) == item)
	assert_true(grid.is_walkable(Vector2i(2, 2)))
	assert_false(grid.is_walkable(Vector2i(3, 3)))
	assert_eq(item.work_cells, [Vector2i(4, 2)] as Array[Vector2i])
	assert_eq(item.seat_cells, [Vector2i(3, 4)] as Array[Vector2i])
	assert_eq(_changes.size(), 1)
	assert_eq(_changes[0], [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)] as Array[Vector2i])
	assert_eq(_removed, 0)
	assert_false(grid.relocate_def(item.id, Vector2i(8, 8), 0))
	assert_false(grid.relocate_def(item.id, Vector2i(6, 6), 0))
	assert_false(grid.relocate_def(item.id, Vector2i(6, 0), 0))
	assert_false(grid.relocate_def(9999, Vector2i.ZERO, 0))
	assert_eq(item.origin, Vector2i(3, 2))
	assert_eq(_changes.size(), 1)
	grid.cells_changed.disconnect(_record_cells)
	grid.item_removed.disconnect(_record_removed)


func test_reserved_relocation_refuses_even_after_closing() -> void:
	_sim.world.clock.phase = SimClock.Phase.CLOSED
	var item: PlacedItem = _sim.world.grid.item(_id(&"fridge"))
	var cell: Vector2i = item.work_cells[0]
	assert_true(item.reserve(cell, 77))
	var before: Dictionary = _editor.to_dict()
	assert_false(_editor.move(item.id, Vector2i(1, 2), 2))
	assert_true(_editor.last_check.why.contains("in use; try next morning"))
	assert_false(_sim.world.grid.relocate_def(item.id, Vector2i(1, 2), 2))
	assert_eq(item.reserved_by(cell), 77)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_changes.size(), 0)
	assert_eq(_entries.size(), 0)


func test_purchase_books_one_upgrade_and_repeat_invalid_purchase_is_free() -> void:
	var price: int = _content.item(&"chair").price
	assert_true(_editor.buy(&"chair", Vector2i(2, 8)))
	assert_eq(_cash, 1000 - price)
	assert_eq(_entries, [{"amount": -price, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(_changes.size(), 1)
	assert_false(_editor.buy(&"chair", Vector2i(2, 8)))
	assert_eq(_entries.size(), 1)
	assert_eq(_changes.size(), 1)


func test_level_locked_purchase_keeps_books_unchanged_but_starter_plant_stays_editable() -> void:
	var starter: int = _id(&"potted_plant")
	var snapshot: Dictionary = _editor.to_dict()
	var check: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(11, 9))
	assert_false(check.ok)
	assert_eq(check.why, "Unlocks at level 2")
	assert_false(_editor.buy(&"potted_plant", Vector2i(11, 9)))
	assert_eq(_cash, 1000)
	assert_eq(_entries.size(), 0)
	assert_eq(_changes.size(), 0)
	assert_eq(_editor.to_dict(), snapshot)
	assert_true(_editor.check_move(starter, Vector2i(11, 9), 0).ok)
	var errors: Array[String] = []
	assert_not_null(ShopEditor.from_dict(snapshot, LAYOUT, _content, errors))
	assert_eq(errors, [] as Array[String], "old layouts may contain the starter plant")
	_editor.set_owner_level(2)
	assert_true(_editor.buy(&"potted_plant", Vector2i(11, 9)))
	assert_eq(_cash, 985)
	assert_eq(_entries.size(), 1)
	_editor.set_owner_level(1)
	assert_false(_editor.buy(&"potted_plant", Vector2i(12, 9)))
	assert_true(_editor.check_sell(starter).ok)
	assert_eq(_entries.size(), 1)


func test_insufficient_cash_cannot_borrow_or_place() -> void:
	_cash = 0
	var before: Dictionary = _editor.to_dict()
	assert_false(_editor.check_buy(&"chair", Vector2i(4, 9)).ok)
	assert_false(_editor.buy(&"chair", Vector2i(4, 9)))
	assert_eq(_cash, 0)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_entries.size(), 0)
	assert_eq(_changes.size(), 0)


func test_sell_releases_cells_cancels_targeted_work_and_refunds_once() -> void:
	var item: PlacedItem = _sim.world.grid.item(_id(&"table_2"))
	assert_true(item.reserve(item.seat_cells[0], 88))
	var task: SimTask = SimTask.new(&"bus_table", &"server", "Clear table")
	task.steps.append(TaskStep.go_to_item(item.id, "walk", true))
	_sim.world.board.post(task, _sim.world.now)
	assert_true(_sim.world.board.claim(task, 88, _sim.world.now))
	var refund: int = _editor.sell(item.id)
	assert_eq(refund, 20)
	assert_true(_editor.last_check.ok)
	assert_eq(_cash, 1020)
	assert_true(item.removed)
	assert_eq(item.reserved_by(item.seat_cells[0]), -1)
	assert_eq(task.state, SimTask.State.CANCELLED)
	assert_eq(_sim.world.board.active_count(), 0)
	assert_eq(_entries, [{"amount": 20, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(_editor.sell(item.id), -1)
	assert_eq(_entries.size(), 1)
	assert_eq(_changes.size(), 1)
	assert_eq(_removed, 1)


func test_odd_and_zero_refunds_are_distinct_from_refusal() -> void:
	for price: int in [5, 0]:
		var definition: ItemDef = ItemDef.new()
		definition.id = StringName("test_price_%d" % price)
		definition.price = price
		_content.extra[definition.id] = definition
		assert_true(_editor.buy(definition.id, Vector2i(4, 9)))
		var id: int = _sim.world.grid.item_at(Vector2i(4, 9)).id
		assert_eq(_editor.sell(id), 2 if price == 5 else 0)
		assert_true(_editor.last_check.ok)
	assert_eq(_entries.size(), 4)


func test_last_required_station_and_door_guards_use_real_categories() -> void:
	for def_id: StringName in [&"fridge", &"prep_counter", &"stove", &"pass_counter", &"sink"]:
		assert_false(_editor.check_sell(_id(def_id)).ok)
		assert_eq(_editor.sell(_id(def_id)), -1)
	assert_true(_editor.buy(&"door", Vector2i(4, 8)))
	assert_false(_editor.check_sell(_id(&"door")).ok)
	assert_eq(_editor.sell(_id(&"door")), -1)
	assert_true(_editor.buy(&"fridge", Vector2i(1, 8)))
	assert_eq(_editor.sell(_id(&"fridge")), 40, "a second fridge permits a sale")
	assert_false(_editor.check_sell(_id(&"fridge")).ok)


func test_unreachable_seats_and_each_pass_side_warn_but_do_not_block() -> void:
	_editor.set_owner_level(2)
	var table_id: int = _id(&"table_2")
	assert_true(_editor.buy(&"potted_plant", Vector2i(1, 7)))
	var check: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(4, 7))
	assert_true(check.ok)
	assert_true(check.unreachable.has(table_id))
	assert_true(_editor.buy(&"potted_plant", Vector2i(4, 7)))
	check = _editor.check_buy(&"potted_plant", Vector2i(5, 3))
	assert_true(check.ok)
	assert_true(check.unreachable.has(_id(&"pass_counter")))
	assert_true(_editor.buy(&"potted_plant", Vector2i(5, 3)))


func test_new_unreachable_station_warning_uses_zero_id() -> void:
	# At the top wall the unrotated fridge's work cell is on the boundary wall.
	var check: EditCheck = _editor.check_buy(&"fridge", Vector2i(4, 1))
	assert_false(check.ok, "existing prep counter still blocks overlapping purchase")
	check = _editor.check_buy(&"fridge", Vector2i(11, 1))
	assert_true(check.ok)
	assert_true(check.unreachable.has(0))
	assert_eq(_changes.size(), 0)


func test_snapshot_round_trip_stages_layout_and_preserves_stable_order() -> void:
	assert_true(_editor.move(_id(&"potted_plant"), Vector2i(11, 9), 3))
	assert_true(_editor.buy(&"chair", Vector2i(2, 8)))
	var original: Dictionary = _editor.to_dict()
	var data: Dictionary = JSON.parse_string(JSON.stringify(original))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_not_null(layout)
	assert_eq(errors, [] as Array[String])
	var restored: RestaurantSim = RestaurantSim.new()
	restored.world = ShopBuilder.build(layout, _content, errors, true)
	var editor: ShopEditor = ShopEditor.new(restored, _content, _books)
	assert_eq(editor.to_dict(), original)
	assert_eq(_editor.to_dict(), original)
	assert_eq(_entries.size(), 1, "decoding does not replay purchases")
	data["items"][0]["origin"][0] = 99
	assert_eq(editor.to_dict(), original, "decoded layout does not alias input")


func test_invalid_snapshots_leave_live_state_and_template_unchanged() -> void:
	var original: Dictionary = _editor.to_dict()
	var invalid: Array[Dictionary] = [{}, {"version": 1, "items": "bad"}]
	var unknown: Dictionary = original.duplicate(true)
	unknown["items"][0]["def_id"] = "missing"
	invalid.append(unknown)
	var fractional: Dictionary = original.duplicate(true)
	fractional["items"][0]["origin"] = [1.5, 1]
	invalid.append(fractional)
	var overlap: Dictionary = original.duplicate(true)
	overlap["items"][1]["origin"] = overlap["items"][0]["origin"].duplicate()
	invalid.append(overlap)
	var missing: Dictionary = original.duplicate(true)
	var rows: Array = missing["items"]
	rows.remove_at(0)
	invalid.append(missing)
	for data: Dictionary in invalid:
		var errors: Array[String] = []
		assert_null(ShopEditor.from_dict(data, LAYOUT, _content, errors))
		assert_false(errors.is_empty())
		assert_eq(_editor.to_dict(), original)
	assert_eq(LAYOUT.placements.size(), 9)
	assert_eq(_changes.size(), 0)
	assert_eq(_entries.size(), 0)


func test_import_cannot_remove_a_template_door() -> void:
	var template: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	var door: ShopPlacement = ShopPlacement.new()
	door.item_id = &"door"
	door.origin = Vector2i(4, 8)
	template.placements.append(door)
	var errors: Array[String] = []
	assert_null(ShopEditor.from_dict(_editor.to_dict(), template, _content, errors))
	assert_false(errors.is_empty())


func test_edited_spawn_allowance_preserves_authored_checks_and_escape() -> void:
	_editor.set_owner_level(2)
	var spawn: Vector2i = LAYOUT.staff_spawns[&"server"]
	assert_true(_editor.buy(&"potted_plant", spawn))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(_editor.to_dict(), LAYOUT, _content, errors)
	assert_not_null(layout)
	ShopBuilder.build(layout, _content, errors)
	assert_false(errors.is_empty(), "authored layout default remains strict")
	errors.clear()
	var world: SimWorld = ShopBuilder.build(layout, _content, errors, true)
	assert_eq(errors, [] as Array[String])
	assert_false(world.grid.is_walkable(spawn))
	var agent: SimAgent = SimAgent.new()
	agent.cell = spawn
	assert_true(agent.set_destination(world.grid, world.grid.entries()[0]))
	assert_eq(agent.path[0], spawn)
	for index: int in range(200):
		if agent.has_arrived():
			break
		assert_ne(agent.step_move(world), SimAgent.MoveResult.BLOCKED)
	assert_true(agent.has_arrived(), "staff can leave furniture covering the spawn")
	var invalid: ShopLayout = layout.duplicate(true) as ShopLayout
	invalid.staff_spawns[&"server"] = Vector2i(-1, -1)
	ShopBuilder.build(invalid, _content, errors, true)
	assert_false(errors.is_empty(), "the allowance does not accept outside spawns")


func test_grid_signal_reentry_cannot_charge_a_second_purchase() -> void:
	_try_reentry = true
	assert_true(_editor.buy(&"chair", Vector2i(2, 8)))
	assert_false(_reentry_result)
	assert_true(_editor.last_check.ok)
	assert_eq(_entries.size(), 1)
	assert_eq(_changes.size(), 1)


func test_second_sink_can_be_sold_but_last_sink_is_preserved() -> void:
	var first: int = _id(&"sink")
	assert_true(_editor.buy(&"sink", Vector2i(12, 1), 2))
	assert_true(_editor.check_sell(first).ok)
	assert_eq(_editor.sell(first), 20)
	var remaining: int = _id(&"sink")
	var before: Dictionary = _editor.to_dict()
	var entries: int = _entries.size()
	assert_false(_editor.check_sell(remaining).ok)
	assert_eq(_editor.last_check.why, "")  # The read-only check does not replace last_check.
	assert_eq(_editor.sell(remaining), -1)
	assert_true(_editor.last_check.why.contains("sink"))
	assert_eq(_entries.size(), entries)
	assert_eq(_editor.to_dict(), before)


func test_custom_purchase_refusal_preserves_read_only_checks_and_atomic_rejection() -> void:
	_cash = 0
	_books = ShopEditBooks.new(_can_spend, _record_cash, _purchase_refusal)
	_editor = ShopEditor.new(_sim, _content, _books)
	var snapshot: Dictionary = _editor.to_dict()
	var check: EditCheck = _editor.check_buy(&"chair", Vector2i(4, 9))
	assert_false(check.ok)
	assert_eq(check.why, "Pay off your bank loan first")
	assert_eq(_refusal_amount, _content.item(&"chair").price)
	assert_eq(_editor.last_check.why, "", "a proposal does not replace the last transaction")
	assert_false(_editor.buy(&"chair", Vector2i(4, 9)))
	assert_eq(_editor.last_check.why, check.why)
	assert_eq(_editor.to_dict(), snapshot)
	assert_eq(_cash, 0)
	assert_eq(_entries.size(), 0)
	assert_eq(_changes.size(), 0)
	_cash = 1000
	_refusal_amount = -1
	assert_true(_editor.check_buy(&"chair", Vector2i(2, 8)).ok)
	assert_eq(_refusal_amount, -1, "an allowed purchase does not request a refusal")
	assert_eq(_entries.size(), 0)


func test_optional_purchase_refusal_keeps_legacy_reason_for_missing_empty_or_invalid_answer() -> void:
	_cash = 0
	var legacy: String = "Not enough cash; furniture cannot use a loan"
	assert_eq(_editor.check_buy(&"chair", Vector2i(4, 9)).why, legacy)
	_books = ShopEditBooks.new(_can_spend, _record_cash, _purchase_refusal)
	_editor = ShopEditor.new(_sim, _content, _books)
	for answer: Variant in ["", "  ", 12, null]:
		_refusal = answer
		assert_eq(_editor.check_buy(&"chair", Vector2i(4, 9)).why, legacy)
	_books = ShopEditBooks.new(_can_spend, _record_cash, Callable())
	_editor = ShopEditor.new(_sim, _content, _books)
	assert_eq(_editor.check_buy(&"chair", Vector2i(4, 9)).why, legacy)
	assert_eq(_entries.size(), 0)
	assert_eq(_changes.size(), 0)


func test_rug_buy_move_and_sell_preserve_the_occupied_table_and_book_once() -> void:
	_editor.set_owner_level(6)
	var grid: SimGrid = _sim.world.grid
	var table: PlacedItem = grid.item(_id(&"table_2"))
	var table_origin: Vector2i = table.origin
	var seats: Array[Vector2i] = table.seat_cells.duplicate()
	var seat: Vector2i = seats[0]
	assert_true(table.reserve(seat, 77))
	var before: Dictionary = _editor.to_dict()
	assert_true(_editor.check_buy(&"rug_rectangle", Vector2i(1, 6)).ok)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_changes.size(), 0)
	assert_eq(_entries.size(), 0)
	assert_true(_editor.buy(&"rug_rectangle", Vector2i(1, 6)))
	var rug: PlacedItem = grid.item_on_layer(table.origin, ItemDef.PlacementLayer.FLOOR_DECOR)
	assert_not_null(rug)
	if rug == null:
		return
	var price: int = _content.item(&"rug_rectangle").price
	assert_eq(_cash, 1000 - price)
	assert_eq(_entries, [{"amount": -price, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_true(_editor.move(rug.id, Vector2i(1, 8), 0))
	assert_true(_editor.move(rug.id, Vector2i(1, 6), 0))
	assert_true(grid.item(rug.id) == rug)
	assert_true(grid.item(table.id) == table)
	assert_eq(table.origin, table_origin)
	assert_eq(table.seat_cells, seats)
	assert_eq(table.reserved_by(seat), 77)
	assert_eq(grid.dining_table_id(seat), table.id)
	assert_eq(_entries.size(), 1, "moving floor decor never books a purchase")
	var refund: int = floori(float(price) * 0.5)
	assert_eq(_editor.sell(rug.id), refund)
	assert_eq(_cash, 1000 - price + refund)
	assert_eq(_entries.size(), 2)
	assert_eq(_removed, 1)
	assert_eq(_changes.size(), 4)
	assert_true(rug.removed)
	assert_false(table.removed)
	assert_eq(grid.item_at(table_origin), table)
	assert_null(grid.item_on_layer(table_origin, ItemDef.PlacementLayer.FLOOR_DECOR))
	assert_eq(table.reserved_by(seat), 77)
	assert_true(grid.is_walkable(seat))
	assert_false(grid.is_walkable(table.origin))


func test_floor_overlap_and_terrain_refusals_leave_books_grid_and_signals_unchanged() -> void:
	_editor.set_owner_level(6)
	assert_true(_editor.buy(&"rug_rectangle", Vector2i(1, 6)))
	assert_true(_editor.buy(&"rug_round", Vector2i(9, 7)))
	var rug: PlacedItem = _sim.world.grid.item_on_layer(Vector2i(1, 6), ItemDef.PlacementLayer.FLOOR_DECOR)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _cash
	var entries: int = _entries.size()
	var changes: int = _changes.size()
	assert_false(_editor.check_buy(&"rug_round", Vector2i(1, 6)).ok)
	assert_false(_editor.buy(&"rug_round", Vector2i(1, 6)))
	assert_false(_editor.check_move(rug.id, Vector2i(9, 7), 0).ok)
	assert_false(_editor.move(rug.id, Vector2i(9, 7), 0))
	assert_false(_editor.buy(&"rug_rectangle", Vector2i(13, 9)))
	assert_false(_editor.buy(&"rug_round", Vector2i(0, 6)))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_cash, cash)
	assert_eq(_entries.size(), entries)
	assert_eq(_changes.size(), changes)
	assert_eq(_removed, 0)
	assert_eq(_sim.world.now, 0)


func test_floor_layer_does_not_change_the_service_edit_policy() -> void:
	assert_true(_editor.buy(&"rug_round", Vector2i(1, 6)))
	var rug: PlacedItem = _sim.world.grid.item_on_layer(Vector2i(1, 6), ItemDef.PlacementLayer.FLOOR_DECOR)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _cash
	var entries: int = _entries.size()
	var changes: int = _changes.size()
	for phase: SimClock.Phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		_sim.world.clock.phase = phase
		assert_false(_editor.check_move(rug.id, Vector2i(4, 8), 0).ok)
		assert_false(_editor.move(rug.id, Vector2i(4, 8), 0))
		assert_false(_editor.buy(&"rug_round", Vector2i(4, 8)))
		assert_eq(_editor.sell(rug.id), -1)
		assert_eq(_editor.to_dict(), before)
		assert_eq(_cash, cash)
		assert_eq(_entries.size(), entries)
		assert_eq(_changes.size(), changes)
		assert_eq(_removed, 0)


func test_version_one_rug_and_table_round_trip_in_either_wire_order() -> void:
	_editor.set_owner_level(6)
	assert_true(_editor.buy(&"rug_rectangle", Vector2i(1, 6)))
	var original: Dictionary = _editor.to_dict()
	assert_eq(original["version"], ShopEditor.SNAPSHOT_VERSION)
	for reverse_order: bool in [false, true]:
		var expected: Dictionary = original.duplicate(true)
		if reverse_order:
			(expected["items"] as Array).reverse()
		var document: Dictionary = JSON.parse_string(JSON.stringify(expected))
		var errors: Array[String] = []
		var layout: ShopLayout = ShopEditor.from_dict(document, LAYOUT, _content, errors)
		assert_not_null(layout)
		assert_eq(errors, [] as Array[String])
		if layout == null:
			continue
		var restored: RestaurantSim = RestaurantSim.new()
		restored.world = ShopBuilder.build(layout, _content, errors, true)
		assert_eq(errors, [] as Array[String])
		var copy: ShopEditor = ShopEditor.new(restored, _content, _books, layout)
		assert_eq(copy.to_dict(), expected, "wire order is retained rather than sorting gameplay items by layer")
		var table: PlacedItem = restored.world.grid.item_on_layer(Vector2i(2, 6), ItemDef.PlacementLayer.NORMAL)
		var rug: PlacedItem = restored.world.grid.item_on_layer(Vector2i(2, 6), ItemDef.PlacementLayer.FLOOR_DECOR)
		assert_not_null(table)
		assert_not_null(rug)
		if table == null or rug == null:
			continue
		assert_eq((table.def as ItemDef).id, &"table_2")
		assert_eq((rug.def as ItemDef).id, &"rug_rectangle")
		assert_eq(restored.world.grid.item_at(Vector2i(2, 6)), table)
		for seat: Vector2i in table.seat_cells:
			assert_true(restored.world.grid.is_walkable(seat))
			assert_eq(restored.world.grid.dining_table_id(seat), table.id)
			assert_eq(restored.world.grid.item_on_layer(seat, ItemDef.PlacementLayer.FLOOR_DECOR), rug)
	assert_eq(_editor.to_dict(), original)
	assert_eq(_entries.size(), 1, "decoding never replays the rug purchase")
	assert_eq(_changes.size(), 1)


func test_snapshot_item_cap_accepts_two_layers_but_rejects_same_layer_duplicates() -> void:
	var normal: ItemDef = ItemDef.new()
	normal.id = &"tiny_normal"
	normal.category = ItemDef.Category.DECOR
	normal.solid = false
	var floor_def: ItemDef = normal.duplicate(true) as ItemDef
	floor_def.id = &"tiny_floor"
	floor_def.placement_layer = ItemDef.PlacementLayer.FLOOR_DECOR
	_content.extra[normal.id] = normal
	_content.extra[floor_def.id] = floor_def
	var template: ShopLayout = ShopLayout.new()
	template.id = &"two_layers"
	template.rows = PackedStringArray(["."])
	var rows: Array[Dictionary] = [
		{"def_id": "tiny_normal", "origin": [0, 0], "quarter_turns": 0, "swatch_id": ""},
		{"def_id": "tiny_floor", "origin": [0, 0], "quarter_turns": 0, "swatch_id": ""},
	]
	var before: Dictionary = _editor.to_dict()
	for reverse_order: bool in [false, true]:
		var ordered: Array[Dictionary] = rows.duplicate(true)
		if reverse_order:
			ordered.reverse()
		var errors: Array[String] = []
		var layout: ShopLayout = ShopEditor.from_dict({"version": 1, "items": ordered}, template, _content, errors)
		assert_not_null(layout)
		assert_eq(errors, [] as Array[String])
		if layout == null:
			continue
		var restored: SimWorld = ShopBuilder.build(layout, _content, errors)
		assert_eq(errors, [] as Array[String])
		assert_eq(restored.grid.items_at(Vector2i.ZERO).size(), 2)
		assert_true(restored.grid.is_walkable(Vector2i.ZERO))
	var errors: Array[String] = []
	var duplicate: Array[Dictionary] = [rows[0], rows[0]]
	assert_null(ShopEditor.from_dict({"version": 1, "items": duplicate}, template, _content, errors))
	assert_false(errors.is_empty())
	errors.clear()
	assert_null(ShopEditor.from_dict({"version": 1, "items": [rows[0], rows[1], rows[1]]}, template, _content, errors))
	assert_true(errors.has("Too many shop items"))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_entries.size(), 0)
	assert_eq(_changes.size(), 0)
	assert_eq(template.placements.size(), 0)


func _purchase_refusal(amount: int) -> Variant:
	_refusal_amount = amount
	return _refusal


func _id(def_id: StringName) -> int:
	return ShopBuilder.items_with_def(_sim.world, def_id)[0].id


func _can_spend(amount: int) -> bool:
	return amount >= 0 and _cash >= amount


func _record_cash(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})


func _record_cells(cells: Array[Vector2i]) -> void:
	_changes.append(cells.duplicate())
	if _try_reentry:
		_try_reentry = false
		_reentry_result = _editor.buy(&"chair", Vector2i(3, 8))


func _record_removed(_item: PlacedItem) -> void:
	_removed += 1
