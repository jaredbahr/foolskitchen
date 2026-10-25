extends TestCase
## In-memory content isolates seating rules from asset imports and unlock data.

class Catalogue extends ContentDB:
	var definitions: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return definitions.get(id) as ItemDef

var _content: Catalogue
var _sim: RestaurantSim
var _editor: ShopEditor
var _cash: int = 1000
var _entries: Array[Dictionary] = []
var _changes: Array[Array] = []
var _removed: int = 0


func before_each() -> void:
	_content = Catalogue.new()
	_add(&"chair", ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO])
	_add(&"bench", ItemDef.Category.CHAIR, Vector2i(2, 1), [Vector2i.ZERO, Vector2i.RIGHT])
	_add(&"surface", ItemDef.Category.TABLE, Vector2i(2, 1))
	_add(&"small_surface", ItemDef.Category.TABLE)
	_add(&"builtin_surface", ItemDef.Category.TABLE, Vector2i.ONE, [Vector2i.DOWN])
	_add(&"side_builtin", ItemDef.Category.TABLE, Vector2i.ONE, [Vector2i.RIGHT])
	_add(&"moving_builtin", ItemDef.Category.TABLE, Vector2i.ONE, [Vector2i(2, 2)])
	_add(&"fixed_builtin", ItemDef.Category.TABLE, Vector2i.ONE, [Vector2i(-2, 2)])
	_add(&"stealing_builtin", ItemDef.Category.TABLE, Vector2i.ONE, [Vector2i(1, 1)])
	_add(&"decor", ItemDef.Category.DECOR)
	var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
	grid.set_terrain(Vector2i(0, 9), SimGrid.Terrain.ENTRY)
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(grid)
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))
	_cash = 1000
	_entries.clear()
	_changes.clear()
	_removed = 0
	grid.cells_changed.connect(_record_cells)
	grid.item_removed.connect(_record_removed)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null
	_entries.clear()
	_changes.clear()


func test_invalid_seat_buy_is_read_only_and_rejected_action_records_nothing() -> void:
	var before: Dictionary = _snapshot()
	var previous: EditCheck = _editor.last_check
	var check: EditCheck = _editor.check_buy(&"chair", Vector2i(4, 4))
	assert_false(check.ok)
	assert_eq(check.why, "Place every seat facing a table or counter")
	assert_true(_editor.last_check == previous)
	assert_eq(_snapshot(), before)
	assert_false(_editor.buy(&"chair", Vector2i(4, 4)))
	assert_eq(_editor.last_check.why, check.why)
	assert_eq(_snapshot(), before)


func test_seat_facing_checks_work_in_all_rotations_without_mutation() -> void:
	var origin: Vector2i = Vector2i(4, 4)
	for turns: int in range(4):
		var front: Vector2i = origin + GridMath.rotate_cell(Vector2i.UP, Vector2i.ONE, turns)
		var table: PlacedItem = _place(&"small_surface", front)
		var before: Dictionary = _snapshot()
		assert_true(_editor.check_buy(&"chair", origin, turns).ok)
		assert_false(_editor.check_buy(&"chair", origin, turns + 2).ok)
		assert_eq(_snapshot(), before)
		assert_true(_sim.world.grid.remove(table.id))


func test_partial_bench_is_refused_but_whole_bench_passes_every_rotation() -> void:
	var origin: Vector2i = Vector2i(4, 4)
	var footprint: Vector2i = Vector2i(2, 1)
	for turns: int in range(4):
		var first: Vector2i = origin + GridMath.rotate_cell(Vector2i.UP, footprint, turns)
		var second: Vector2i = origin + GridMath.rotate_cell(Vector2i.RIGHT + Vector2i.UP, footprint, turns)
		var half: PlacedItem = _place(&"small_surface", first)
		var before: Dictionary = _snapshot()
		assert_false(_editor.check_buy(&"bench", origin, turns).ok)
		assert_false(_editor.buy(&"bench", origin, turns))
		assert_eq(_snapshot(), before)
		assert_true(_sim.world.grid.remove(half.id))
		var surface_origin: Vector2i = Vector2i(mini(first.x, second.x), mini(first.y, second.y))
		var whole: PlacedItem = _place(&"surface", surface_origin, turns)
		before = _snapshot()
		assert_true(_editor.check_buy(&"bench", origin, turns).ok)
		assert_eq(_snapshot(), before)
		assert_true(_sim.world.grid.remove(whole.id))


func test_valid_buy_rotation_and_sell_commit_links_and_exactly_one_money_entry_each() -> void:
	var first: PlacedItem = _place(&"small_surface", Vector2i(4, 3))
	var second: PlacedItem = _place(&"small_surface", Vector2i(5, 4))
	var changes: int = _changes.size()
	assert_true(_editor.buy(&"chair", Vector2i(4, 4)))
	var chair: PlacedItem = _sim.world.grid.item_at(Vector2i(4, 4))
	assert_eq(_cash, 990)
	assert_eq(_entries, [{"amount": -10, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(first.seat_cells, [chair.origin] as Array[Vector2i])
	assert_eq(_sim.world.grid.dining_table_id(chair.origin), first.id)
	var before: Dictionary = _snapshot()
	assert_true(_editor.check_move(chair.id, chair.origin, 1).ok)
	assert_eq(_snapshot(), before)
	assert_true(_editor.move(chair.id, chair.origin, 1))
	assert_true(first.seat_cells.is_empty())
	assert_eq(second.seat_cells, [chair.origin] as Array[Vector2i])
	assert_eq(_sim.world.grid.dining_furnishing_id(chair.origin), chair.id)
	assert_eq(_entries.size(), 1, "moving records no money")
	before = _snapshot()
	assert_true(_editor.check_sell(chair.id).ok)
	assert_eq(_snapshot(), before)
	assert_eq(_editor.sell(chair.id), 5)
	assert_eq(_cash, 995)
	assert_eq(_entries.size(), 2)
	assert_eq(_entries[1], {"amount": 5, "category": Ledger.UPGRADES})
	assert_true(second.seat_cells.is_empty())
	assert_eq(_sim.world.grid.dining_table_id(chair.origin), 0)
	assert_eq(_changes.size(), changes + 3)
	assert_eq(_removed, 1)


func test_valid_bench_cannot_be_orphaned_by_surface_move_or_sale() -> void:
	var table: PlacedItem = _place(&"surface", Vector2i(3, 3))
	var bench: PlacedItem = _place(&"bench", Vector2i(3, 4))
	var before: Dictionary = _snapshot()
	assert_false(_editor.check_move(table.id, Vector2i(3, 2), 0).ok)
	assert_false(_editor.check_sell(table.id).ok)
	assert_eq(_snapshot(), before)
	assert_false(_editor.move(table.id, Vector2i(3, 2), 0))
	assert_eq(_editor.sell(table.id), -1)
	assert_eq(_snapshot(), before)
	assert_true(_editor.check_sell(bench.id).ok, "the furnishing itself can be removed first")


func test_existing_valid_seat_is_checked_when_an_older_table_steals_its_cell() -> void:
	var earlier: PlacedItem = _place(&"stealing_builtin", Vector2i(1, 1))
	var surface: PlacedItem = _place(&"small_surface", Vector2i(3, 2))
	var chair: PlacedItem = _place(&"chair", Vector2i(3, 3))
	assert_eq(_sim.world.grid.dining_table_id(chair.origin), surface.id)
	var before: Dictionary = _snapshot()
	var check: EditCheck = _editor.check_move(earlier.id, Vector2i(2, 2), 0)
	assert_false(check.ok, "failure belongs to a different, later furnishing")
	assert_eq(check.why, "There is already a seat here")
	assert_eq(_snapshot(), before)
	assert_false(_editor.move(earlier.id, Vector2i(2, 2), 0))
	assert_eq(_snapshot(), before)


func test_new_builtin_duplicates_are_refused_after_mapping_preview_ids() -> void:
	var earlier: PlacedItem = _place(&"moving_builtin", Vector2i(1, 1))
	var later: PlacedItem = _place(&"fixed_builtin", Vector2i(6, 1))
	assert_eq(_sim.world.grid.dining_table_id(Vector2i(3, 3)), earlier.id)
	assert_eq(_sim.world.grid.dining_table_id(Vector2i(4, 3)), later.id)
	var before: Dictionary = _snapshot()
	var check: EditCheck = _editor.check_move(earlier.id, Vector2i(2, 1), 0)
	assert_false(check.ok)
	assert_eq(check.why, "Seats cannot share the same floor tile")
	assert_false(_editor.move(earlier.id, Vector2i(2, 1), 0))
	assert_eq(_snapshot(), before)
	check = _editor.check_buy(&"side_builtin", Vector2i(3, 3))
	assert_false(check.ok, "new-buy preview ID 0 participates in duplicate comparison")
	assert_eq(check.why, "Seats cannot share the same floor tile")
	assert_false(_editor.buy(&"side_builtin", Vector2i(3, 3)))
	assert_eq(_snapshot(), before)


func test_unchanged_legacy_duplicate_keeps_original_warning_owner_in_move_preview() -> void:
	var earlier: PlacedItem = _place(&"moving_builtin", Vector2i(1, 1))
	var later: PlacedItem = _place(&"fixed_builtin", Vector2i(5, 1))
	var current: EditCheck = _editor.check_current()
	assert_true(current.ok)
	assert_eq(current.unreachable, [later.id] as Array[int])
	var before: Dictionary = _snapshot()
	var check: EditCheck = _editor.check_move(earlier.id, earlier.origin, earlier.quarter_turns)
	assert_true(check.ok, "unchanged legacy geometry does not block an unrelated proposal")
	assert_eq(check.unreachable, current.unreachable, "moved early IDs are not appended behind later owners")
	assert_eq(_snapshot(), before)


func test_linked_chair_booking_blocks_move_and_sale_without_mutation() -> void:
	var table: PlacedItem = _place(&"surface", Vector2i(3, 3))
	var bench: PlacedItem = _place(&"bench", Vector2i(3, 4))
	assert_true(table.reserve(Vector2i(4, 4), 123))
	assert_eq(bench.reserved_by(Vector2i(4, 4)), -1)
	var before: Dictionary = _snapshot()
	var move: EditCheck = _editor.check_move(bench.id, Vector2i(3, 5), 0)
	var sell: EditCheck = _editor.check_sell(bench.id)
	assert_false(move.ok)
	assert_false(sell.ok)
	assert_eq(move.why, "This item is in use; try next morning")
	assert_eq(sell.why, move.why)
	assert_false(_editor.move(bench.id, Vector2i(3, 5), 0))
	assert_eq(_editor.sell(bench.id), -1)
	assert_eq(_snapshot(), before)
	assert_true(table.release(Vector2i(4, 4), 123))
	assert_true(_editor.check_sell(bench.id).ok)


func test_legacy_loose_chair_does_not_block_unrelated_edits_or_old_save_loading() -> void:
	var chair: PlacedItem = _place(&"chair", Vector2i(1, 1))
	assert_false(DiningSeats.derive(_sim.world.grid).failure_for(chair.id).is_empty())
	assert_true(_editor.buy(&"decor", Vector2i(8, 8)))
	var decor: PlacedItem = _sim.world.grid.item_at(Vector2i(8, 8))
	assert_true(_editor.move(decor.id, Vector2i(7, 8), 0))
	var before: Dictionary = _snapshot()
	assert_false(_editor.check_move(chair.id, Vector2i(2, 1), 0).ok,
		"moving the legacy chair still requires a working new position")
	assert_false(_editor.move(chair.id, Vector2i(2, 1), 0))
	assert_eq(_snapshot(), before)
	var template: ShopLayout = ShopLayout.new()
	template.rows = PackedStringArray(["..........", "..........", "..........", "..........", "..........",
		"..........", "..........", "..........", "..........", "E........."])
	var errors: Array[String] = []
	var restored: ShopLayout = ShopEditor.from_dict(_editor.to_dict(), template, _content, errors)
	assert_not_null(restored)
	assert_true(errors.is_empty())
	assert_eq(_snapshot(), before)
	assert_true(_editor.check_sell(chair.id).ok)
	assert_eq(_editor.sell(chair.id), 5)


func test_blocked_builtin_seat_remains_warning_only_instead_of_seating_refusal() -> void:
	var table: PlacedItem = _place(&"builtin_surface", Vector2i(4, 3))
	var before: Dictionary = _snapshot()
	var check: EditCheck = _editor.check_buy(&"decor", Vector2i(4, 4))
	assert_true(check.ok)
	assert_true(check.unreachable.has(table.id))
	assert_eq(_snapshot(), before)
	assert_true(_editor.buy(&"decor", Vector2i(4, 4)))
	assert_true(table.seat_cells.is_empty())
	check = _editor.check_buy(&"side_builtin", Vector2i(3, 4))
	assert_true(check.ok, "blocked duplicate built-ins do not become a blanket path refusal")
	assert_true(check.unreachable.has(table.id))
	assert_true(check.unreachable.has(0), "new placement warnings still use the existing new-item sentinel")
	assert_true(_editor.check_current().ok)


func test_unreachable_but_valid_linked_seat_remains_path_warning_only() -> void:
	var table: PlacedItem = _place(&"small_surface", Vector2i(4, 3))
	var chair: PlacedItem = _place(&"chair", Vector2i(4, 4))
	for x: int in range(10):
		if x != 5:
			assert_true(_sim.world.grid.set_terrain(Vector2i(x, 5), SimGrid.Terrain.WALL))
	assert_true(_sim.world.grid.is_reachable(Vector2i(0, 9), chair.origin))
	var before: Dictionary = _snapshot()
	var check: EditCheck = _editor.check_buy(&"decor", Vector2i(5, 5))
	assert_true(check.ok)
	assert_true(check.unreachable.has(table.id))
	assert_eq(_snapshot(), before)
	assert_true(_editor.buy(&"decor", Vector2i(5, 5)))
	assert_eq(_sim.world.grid.dining_table_id(chair.origin), table.id)
	assert_false(_sim.world.grid.is_reachable(Vector2i(0, 9), chair.origin))
	assert_true(_editor.check_current().ok)


func _add(id: StringName, category: ItemDef.Category, footprint: Vector2i = Vector2i.ONE,
		seats: Array[Vector2i] = []) -> void:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.display_name = "Test furniture"
	definition.category = category
	definition.footprint = footprint
	definition.seat_cells = seats.duplicate()
	definition.solid = category != ItemDef.Category.CHAIR
	definition.price = 10
	definition.unlock_level = 1
	_content.definitions[id] = definition


func _place(id: StringName, origin: Vector2i, turns: int = 0) -> PlacedItem:
	var placed: PlacedItem = _sim.world.grid.place_def(_content.item(id), origin, turns)
	assert_not_null(placed)
	return placed


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _cash


func _record_cash(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})


func _record_cells(cells: Array[Vector2i]) -> void:
	_changes.append(cells.duplicate())


func _record_removed(_item: PlacedItem) -> void:
	_removed += 1


func _snapshot() -> Dictionary:
	var cells: Array[Dictionary] = []
	for placed: PlacedItem in _sim.world.grid.items():
		cells.append({"id": placed.id, "cells": placed.cells.duplicate(),
			"seat_cells": placed.seat_cells.duplicate(), "work_cells": placed.work_cells.duplicate(),
			"reservations": placed._reservations.duplicate(), "removed": placed.removed})
	return {"shop": _editor.to_dict(), "cash": _cash, "entries": _entries.duplicate(true),
		"changes": _changes.duplicate(true), "removed": _removed, "cells": cells,
		"world_tick": _sim.world.now}
