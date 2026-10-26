extends TestCase
## Director 6408764842: front-row seats stay usable; the rear row blocks paths.
## Synthetic content exercises the cell contract without importing any models.

class Catalogue extends ContentDB:
	var definitions: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return definitions.get(id) as ItemDef

var _cash: int = 1000
var _entries: Array[int] = []


func test_front_seats_link_and_rear_cells_block_in_all_rotations() -> void:
	for turns: int in range(4):
		var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
		var definition: ItemDef = _booth()
		var booth: PlacedItem = grid.place_def(definition, Vector2i(4, 4), turns)
		assert_not_null(booth)
		if booth == null:
			continue
		assert_eq(booth.cells.size(), 4)
		assert_eq(booth.seat_cells.size(), 2)
		assert_eq(booth.seat_cells, _absolute_seats(booth.origin, turns))
		assert_true(booth.work_cells.is_empty())
		assert_false(booth.solid, "partial blocking never makes the whole booth solid")
		var expected_rear: Array[Vector2i] = _absolute_rear(booth.origin, turns)
		assert_eq(booth.blocking_cells, expected_rear)
		for seat: Vector2i in booth.seat_cells:
			assert_true(grid.is_walkable(seat))
			var authored: Vector2i = definition.seat_cells[booth.seat_cells.find(seat)]
			var front: Vector2i = booth.origin + GridMath.rotate_cell(authored + Vector2i.UP, definition.footprint, turns)
			var table: PlacedItem = grid.place_def(_surface(), front)
			assert_not_null(table)
		for rear: Vector2i in expected_rear:
			assert_false(grid.is_walkable(rear))
			assert_false(booth.seat_cells.has(rear))
			assert_false(booth.work_cells.has(rear))
			assert_false(booth.reserve(rear, 99))
			assert_true(grid.find_path(Vector2i.ZERO, rear).is_empty(), "the back is not a reachable goal")
			assert_eq(grid.dining_table_id(rear), 0)
		var plan: DiningSeats.Plan = DiningSeats.derive(grid)
		assert_true(plan.failures.is_empty())
		assert_eq(plan.links.size(), 2)
		for seat: Vector2i in booth.seat_cells:
			assert_eq(grid.dining_furnishing_id(seat), booth.id)
			assert_true(grid.dining_table_id(seat) > 0)
			var path: Array[Vector2i] = grid.find_path(Vector2i.ZERO, seat)
			assert_false(path.is_empty(), "each front seat retains an approach around its table")
			for rear: Vector2i in expected_rear:
				assert_false(path.has(rear), "paths cannot pass through the backrest")


func test_move_and_remove_refresh_only_the_rotated_blocking_cells() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	var definition: ItemDef = _booth()
	var booth: PlacedItem = grid.place_def(definition, Vector2i(2, 2))
	assert_not_null(booth)
	if booth == null:
		return
	for turns: int in range(4):
		var old_cells: Array[Vector2i] = booth.cells.duplicate()
		var next_origin: Vector2i = Vector2i(6, 6) if turns % 2 == 0 else Vector2i(2, 2)
		assert_true(grid.relocate_def(booth.id, next_origin, turns))
		assert_true(grid.item(booth.id) == booth, "move preserves placement identity")
		assert_eq(booth.blocking_cells, _absolute_rear(next_origin, turns))
		for old_cell: Vector2i in old_cells:
			assert_true(grid.is_walkable(old_cell), "the vacated footprint reopens")
		for seat: Vector2i in booth.seat_cells:
			assert_true(grid.is_walkable(seat))
		for rear: Vector2i in booth.blocking_cells:
			assert_false(grid.is_walkable(rear))
	var last_cells: Array[Vector2i] = booth.cells.duplicate()
	assert_true(grid.remove(booth.id))
	for cell: Vector2i in last_cells:
		assert_true(grid.is_walkable(cell), "sale/removal restores the whole floor")
		assert_null(grid.item_at(cell))


func test_invalid_blocking_declarations_fail_before_placement_or_relocation() -> void:
	var invalid: Array[ItemDef] = []
	for cell: Vector2i in [Vector2i(-1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i.ZERO]:
		var outside_or_seat: ItemDef = _booth()
		outside_or_seat.blocking_cells = [cell]
		invalid.append(outside_or_seat)
	var duplicate: ItemDef = _booth()
	duplicate.blocking_cells.append(Vector2i.DOWN)
	invalid.append(duplicate)
	var work_overlap: ItemDef = _booth()
	work_overlap.work_cells = [Vector2i.DOWN]
	invalid.append(work_overlap)
	for definition: ItemDef in invalid:
		var rejected_grid: SimGrid = SimGrid.new(Vector2i(8, 8))
		assert_false(definition.blocking_cells_valid())
		assert_eq(rejected_grid.can_place_def(definition, Vector2i(2, 2)), SimGrid.PlaceResult.INVALID_CELLS)
		assert_null(rejected_grid.place_def(definition, Vector2i(2, 2)))
		assert_null(rejected_grid.place(definition.footprint, Vector2i(2, 2), 0, false,
			definition.work_cells, definition.seat_cells, definition))
		assert_true(rejected_grid.items().is_empty())
		assert_false(ContentDB.validate_definitions([], [], [definition]).is_empty())
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var valid: ItemDef = _booth()
	var placed: PlacedItem = grid.place_def(valid, Vector2i(2, 2))
	assert_not_null(placed)
	if placed == null:
		return
	var original_blocks: Array[Vector2i] = placed.blocking_cells.duplicate()
	valid.blocking_cells.append(Vector2i.ZERO)
	assert_false(grid.relocate_def(placed.id, Vector2i(5, 5), 1))
	assert_eq(placed.origin, Vector2i(2, 2))
	assert_eq(placed.blocking_cells, original_blocks, "failed move leaves captured geometry intact")
	for cell: Vector2i in original_blocks:
		assert_false(grid.is_walkable(cell))


func test_floor_decor_rejects_blocking_cells_and_legacy_solidity_is_unchanged() -> void:
	var rug: ItemDef = ItemDef.new()
	rug.id = &"test_rug"
	rug.solid = false
	rug.placement_layer = ItemDef.PlacementLayer.FLOOR_DECOR
	rug.blocking_cells = [Vector2i.ZERO]
	assert_false(rug.placement_layer_valid())
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	assert_eq(grid.can_place_def(rug, Vector2i(2, 2)), SimGrid.PlaceResult.INVALID_LAYER)
	assert_null(grid.place_def(rug, Vector2i(2, 2)))
	for solid: bool in [false, true]:
		var legacy: ItemDef = ItemDef.new()
		legacy.footprint = Vector2i(2, 2)
		legacy.solid = solid
		var placed: PlacedItem = grid.place_def(legacy, Vector2i(2, 2))
		assert_not_null(placed)
		if placed == null:
			continue
		assert_true(placed.blocking_cells.is_empty())
		for cell: Vector2i in placed.cells:
			assert_eq(grid.is_walkable(cell), not solid)
		assert_true(grid.remove(placed.id))


func test_low_level_placement_validates_actual_footprint_and_interaction_cells() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var definition: ItemDef = _booth()
	assert_true(definition.blocking_cells_valid())
	assert_null(grid.place(Vector2i(2, 1), Vector2i(2, 2), 0, false, [], [], definition),
		"a caller cannot shrink the footprint below its declared backrest cells")
	assert_null(grid.place(Vector2i(2, 2), Vector2i(2, 2), 0, false, [Vector2i.DOWN], [], definition),
		"a caller cannot put a working position in the backrest")
	assert_null(grid.place(Vector2i(2, 2), Vector2i(2, 2), 0, false, [], [Vector2i.DOWN], definition),
		"a caller cannot put a customer in the backrest")
	assert_true(grid.items().is_empty())
	assert_true(grid.is_walkable(Vector2i(2, 3)), "rejections leave the floor unchanged")
	definition.blocking_cells.clear()
	assert_not_null(grid.place(Vector2i.ONE, Vector2i(2, 2), 0, false, [], [], definition),
		"the existing independent-argument API remains unchanged when no blocks are authored")


func test_editor_checks_buy_move_and_rotation_without_mutating_live_paths() -> void:
	_cash = 1000
	_entries.clear()
	var content: Catalogue = Catalogue.new()
	var definition: ItemDef = _booth()
	content.definitions[definition.id] = definition
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY)
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(grid)
	var editor: ShopEditor = ShopEditor.new(sim, content, ShopEditBooks.new(_can_spend, _record_cash))
	var origin: Vector2i = Vector2i(4, 4)
	var rejected: Dictionary = _snapshot(grid, editor)
	assert_false(editor.check_buy(definition.id, origin).ok, "both seats still need facing tables")
	assert_eq(_snapshot(grid, editor), rejected)
	for turns: int in range(4):
		var tables: Array[PlacedItem] = _facing_tables(grid, origin, turns)
		var before: Dictionary = _snapshot(grid, editor)
		assert_true(editor.check_buy(definition.id, origin, turns).ok)
		assert_eq(_snapshot(grid, editor), before, "buy preview is read-only")
		assert_true(editor.buy(definition.id, origin, turns))
		var booth: PlacedItem = grid.item_at(origin)
		assert_not_null(booth)
		if booth == null:
			continue
		assert_eq(booth.blocking_cells, _absolute_rear(origin, turns))
		for rear: Vector2i in booth.blocking_cells:
			assert_false(grid.is_walkable(rear))
		before = _snapshot(grid, editor)
		assert_false(editor.check_move(booth.id, origin, turns + 2).ok, "opposite facing has no table")
		assert_false(editor.move(booth.id, origin, turns + 2))
		assert_eq(_snapshot(grid, editor), before, "refused rotation leaves paths and books intact")
		var destination: Vector2i = Vector2i(8, 8)
		var moved_tables: Array[PlacedItem] = _facing_tables(grid, destination, turns + 1)
		before = _snapshot(grid, editor)
		assert_true(editor.check_move(booth.id, destination, turns + 1).ok)
		assert_eq(_snapshot(grid, editor), before, "move preview is read-only")
		assert_true(editor.move(booth.id, destination, turns + 1))
		assert_eq(booth.blocking_cells, _absolute_rear(destination, turns + 1))
		for cell: Vector2i in _absolute_rear(origin, turns):
			assert_true(grid.is_walkable(cell))
		for rear: Vector2i in booth.blocking_cells:
			assert_false(grid.is_walkable(rear))
		assert_eq(editor.sell(booth.id), 50)
		for table: PlacedItem in tables + moved_tables:
			assert_true(grid.remove(table.id))
	assert_eq(_entries.size(), 8, "one purchase and refund per rotation; moves cost nothing")


func test_restored_edited_layout_uses_existing_escape_for_a_blocked_rear_spawn() -> void:
	var content: Catalogue = Catalogue.new()
	var booth: ItemDef = _booth()
	content.definitions[booth.id] = booth
	var layout: ShopLayout = ShopLayout.new()
	layout.rows = PackedStringArray(["......", "......", "......", "......", "......", "......"])
	var placement: ShopPlacement = ShopPlacement.new()
	placement.item_id = booth.id
	placement.origin = Vector2i(2, 2)
	layout.placements.append(placement)
	layout.staff_spawns[&"cook"] = Vector2i(2, 3)
	var strict_errors: Array[String] = []
	ShopBuilder.build(layout, content, strict_errors)
	assert_eq(strict_errors.size(), 1, "authored layouts still reject blocked spawns")
	var restore_errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(layout, content, restore_errors, true)
	assert_true(restore_errors.is_empty(), "edited layout retains the existing blocked-start escape")
	assert_false(world.grid.is_walkable(Vector2i(2, 3)))
	assert_false(world.grid.find_path(Vector2i(2, 3), Vector2i.ZERO).is_empty())


func test_snapshot_rebuilds_rear_blocks_from_definition_without_new_save_fields() -> void:
	var content: Catalogue = Catalogue.new()
	var booth: ItemDef = _booth()
	content.definitions[booth.id] = booth
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(SimGrid.new(Vector2i(6, 6)))
	assert_not_null(sim.world.grid.place_def(booth, Vector2i(2, 2), 3))
	var editor: ShopEditor = ShopEditor.new(sim, content, ShopEditBooks.new(_can_spend, _record_cash))
	var snapshot: Dictionary = editor.to_dict()
	assert_eq(snapshot["version"], 1)
	assert_false((snapshot["items"][0] as Dictionary).has("blocking_cells"), "blocking is content-derived")
	var template: ShopLayout = ShopLayout.new()
	template.rows = PackedStringArray(["......", "......", "......", "......", "......", "......"])
	var errors: Array[String] = []
	var restored: ShopLayout = ShopEditor.from_dict(snapshot, template, content, errors)
	assert_not_null(restored)
	assert_true(errors.is_empty())
	if restored == null:
		return
	var world: SimWorld = ShopBuilder.build(restored, content, errors)
	assert_true(errors.is_empty())
	var rebuilt: PlacedItem = world.grid.item_at(Vector2i(2, 2))
	assert_not_null(rebuilt)
	if rebuilt == null:
		return
	assert_eq(rebuilt.blocking_cells, _absolute_rear(Vector2i(2, 2), 3))
	for rear: Vector2i in rebuilt.blocking_cells:
		assert_false(world.grid.is_walkable(rear))
	for seat: Vector2i in rebuilt.seat_cells:
		assert_true(world.grid.is_walkable(seat))


func _booth() -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_deep_booth"
	definition.category = ItemDef.Category.CHAIR
	definition.footprint = Vector2i(2, 2)
	definition.solid = false
	definition.blocking_cells = [Vector2i(0, 1), Vector2i(1, 1)]
	definition.seat_cells = [Vector2i(0, 0), Vector2i(1, 0)]
	definition.price = 100
	return definition


func _surface() -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_surface"
	definition.category = ItemDef.Category.TABLE
	return definition


func _absolute_rear(origin: Vector2i, turns: int) -> Array[Vector2i]:
	var expected: Array[Vector2i] = []
	# Literal expectations stay independent of production cell rotation.
	var by_turn: Array[Array] = [
		[Vector2i(0, 1), Vector2i(1, 1)], [Vector2i(0, 0), Vector2i(0, 1)],
		[Vector2i(1, 0), Vector2i(0, 0)], [Vector2i(1, 1), Vector2i(1, 0)],
	]
	for rear: Vector2i in by_turn[posmod(turns, 4)]:
		expected.append(origin + rear)
	return expected


func _absolute_seats(origin: Vector2i, turns: int) -> Array[Vector2i]:
	var expected: Array[Vector2i] = []
	var by_turn: Array[Array] = [
		[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(1, 1)],
		[Vector2i(1, 1), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(0, 0)],
	]
	for seat: Vector2i in by_turn[posmod(turns, 4)]:
		expected.append(origin + seat)
	return expected


func _facing_tables(grid: SimGrid, origin: Vector2i, turns: int) -> Array[PlacedItem]:
	var result: Array[PlacedItem] = []
	var by_turn: Array[Array] = [
		[Vector2i(0, -1), Vector2i(1, -1)], [Vector2i(2, 0), Vector2i(2, 1)],
		[Vector2i(1, 2), Vector2i(0, 2)], [Vector2i(-1, 1), Vector2i(-1, 0)],
	]
	for front: Vector2i in by_turn[posmod(turns, 4)]:
		var table: PlacedItem = grid.place_def(_surface(), origin + front)
		assert_not_null(table)
		if table != null:
			result.append(table)
	return result


func _snapshot(grid: SimGrid, editor: ShopEditor) -> Dictionary:
	var paths: Array[bool] = []
	var cells: Array[Dictionary] = []
	for placed: PlacedItem in grid.items():
		cells.append({"cells": placed.cells.duplicate(), "blocking": placed.blocking_cells.duplicate(),
			"seats": placed.seat_cells.duplicate(), "work": placed.work_cells.duplicate()})
	for y: int in range(grid.size.y):
		for x: int in range(grid.size.x):
			paths.append(grid.is_walkable(Vector2i(x, y)))
	return {"shop": editor.to_dict(), "cells": cells, "walkability": paths, "cash": _cash, "entries": _entries.duplicate()}


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _cash


func _record_cash(amount: int, _category: StringName) -> void:
	_cash += amount
	_entries.append(amount)
