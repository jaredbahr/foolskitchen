extends TestCase
## Synthetic definitions exercise seat links without imports, scene nodes or RNG.

var _changes: int = 0


func test_standalone_chair_faces_surface_in_all_four_rotations() -> void:
	for turns: int in range(4):
		var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
		var chair_def: ItemDef = _definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO])
		var chair: PlacedItem = grid.place_def(chair_def, Vector2i(4, 4), turns)
		var front: Vector2i = chair.origin + GridMath.rotate_cell(Vector2i.UP, Vector2i.ONE, turns)
		var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), front)
		var plan: DiningSeats.Plan = DiningSeats.derive(grid)
		assert_true(plan.failures.is_empty(), "rotation %d links" % turns)
		assert_eq(plan.seats_for(table.id), [chair.origin] as Array[Vector2i])
		assert_eq(plan.links.size(), 1)
		assert_eq(plan.links[0].table_item_id, table.id)
		assert_eq(plan.links[0].furnishing_item_id, chair.id)
		assert_false(plan.links[0].built_in)


func test_two_bench_cells_link_to_physical_table_in_every_rotation() -> void:
	for turns: int in range(4):
		var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
		var footprint: Vector2i = Vector2i(2, 1)
		var bench_def: ItemDef = _definition(ItemDef.Category.CHAIR, footprint,
			[Vector2i.ZERO, Vector2i.RIGHT])
		var bench: PlacedItem = grid.place_def(bench_def, Vector2i(4, 4), turns)
		var front_a: Vector2i = bench.origin + GridMath.rotate_cell(Vector2i.UP, footprint, turns)
		var front_b: Vector2i = bench.origin + GridMath.rotate_cell(Vector2i.RIGHT + Vector2i.UP, footprint, turns)
		var surface_origin: Vector2i = Vector2i(mini(front_a.x, front_b.x), mini(front_a.y, front_b.y))
		var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, footprint), surface_origin, turns)
		var plan: DiningSeats.Plan = DiningSeats.derive(grid)
		assert_true(plan.failures.is_empty(), "bench rotation %d links" % turns)
		assert_eq(plan.seats_for(table.id), bench.seat_cells)
		assert_eq(plan.links.size(), 2)
		for link: DiningSeats.SeatLink in plan.links:
			assert_eq(link.table_item_id, table.id)
			assert_eq(link.furnishing_item_id, bench.id)


func test_authored_built_in_seats_keep_rotated_order_and_identity() -> void:
	var footprint: Vector2i = Vector2i(2, 2)
	var authored: Array[Vector2i] = [Vector2i(-1, 1), Vector2i(2, 1)]
	for turns: int in range(4):
		var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
		var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, footprint, authored),
			Vector2i(4, 4), turns)
		var expected: Array[Vector2i] = []
		for cell: Vector2i in authored:
			expected.append(table.origin + GridMath.rotate_cell(cell, footprint, turns))
		var plan: DiningSeats.Plan = DiningSeats.derive(grid)
		assert_true(plan.failures.is_empty())
		assert_eq(plan.seats_for(table.id), expected)
		assert_eq(plan.links.size(), 2)
		for link: DiningSeats.SeatLink in plan.links:
			assert_true(link.built_in)
			assert_eq(link.table_item_id, table.id)
			assert_eq(link.furnishing_item_id, table.id)


func test_stools_link_to_counter_without_treating_job_capacity_as_seat_limit() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
	var counter_def: ItemDef = _definition(ItemDef.Category.TABLE, Vector2i(3, 1))
	counter_def.capacity = 1
	var counter: PlacedItem = grid.place_def(counter_def, Vector2i(3, 3))
	var first: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO]), Vector2i(3, 4))
	var second: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO]), Vector2i(4, 4))
	var third: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO]), Vector2i(5, 4))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_true(plan.failures.is_empty())
	assert_eq(plan.seats_for(counter.id), [first.origin, second.origin, third.origin] as Array[Vector2i])
	assert_eq(plan.links.size(), 3)
	assert_eq(counter_def.capacity, 1, "deriving does not rewrite authored capacities")


func test_missing_or_wrong_facing_surface_refuses_seat() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO]), Vector2i(4, 4))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), Vector2i(4, 5))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.failure_for(chair.id), "Place every seat facing a table or counter")
	assert_true(plan.seats_for(table.id).is_empty())
	assert_true(plan.links.is_empty())
	assert_true(grid.remove(table.id))
	assert_eq(DiningSeats.derive(grid).failure_for(chair.id), plan.failure_for(chair.id))


func test_one_invalid_bench_cell_rejects_whole_bench_without_claiming_valid_half() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), Vector2i(3, 3))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
		[Vector2i.ZERO, Vector2i.RIGHT]), Vector2i(3, 4))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.failure_for(bench.id), "Place every seat facing a table or counter")
	assert_true(plan.seats_for(table.id).is_empty())
	assert_true(plan.links.is_empty(), "a rejected furnishing leaves no staged half-seat")
	var later: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i(-2, 0)]), Vector2i(5, 4))
	plan = DiningSeats.derive(grid)
	assert_eq(plan.failure_for(later.id), "")
	assert_eq(plan.seats_for(table.id), [Vector2i(3, 4)] as Array[Vector2i])


func test_built_in_seat_wins_even_when_standalone_furnishing_was_placed_first() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO]), Vector2i(3, 4))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i.ONE,
		[Vector2i.DOWN]), Vector2i(3, 3))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.failure_for(chair.id), "There is already a seat here")
	assert_eq(plan.seats_for(table.id), [Vector2i(3, 4)] as Array[Vector2i])
	assert_eq(plan.links.size(), 1)
	assert_true(plan.links[0].built_in)
	assert_eq(plan.links[0].furnishing_item_id, table.id)


func test_duplicate_authored_built_in_seats_keep_first_table_identity() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var first: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i.ONE,
		[Vector2i(1, 1)]), Vector2i(2, 2))
	var second: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i.ONE,
		[Vector2i(-1, 1)]), Vector2i(4, 2))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.seats_for(first.id), [Vector2i(3, 3)] as Array[Vector2i])
	assert_true(plan.seats_for(second.id).is_empty())
	assert_eq(plan.failure_for(second.id), "There is already a seat here")
	assert_eq(plan.links[0].table_item_id, first.id)


func test_duplicate_standalone_seats_use_stable_placement_order() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), Vector2i(3, 3))
	var first: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO]), Vector2i(3, 4))
	var second: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.LEFT]), Vector2i(4, 4))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.links.size(), 1)
	assert_eq(plan.links[0].furnishing_item_id, first.id)
	assert_eq(plan.failure_for(second.id), "There is already a seat here")
	assert_true(grid.remove(first.id))
	plan = DiningSeats.derive(grid)
	assert_eq(plan.links.size(), 1)
	assert_eq(plan.links[0].furnishing_item_id, second.id)
	assert_eq(plan.links[0].table_item_id, table.id)
	assert_eq(plan.failure_for(second.id), "")


func test_duplicate_cells_inside_one_bench_refuse_whole_furnishing() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), Vector2i(3, 3))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO, Vector2i.ZERO]), Vector2i(3, 4))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.failure_for(bench.id), "There is already a seat here")
	assert_true(plan.seats_for(table.id).is_empty())
	assert_true(plan.links.is_empty())


func test_outside_and_blocked_seats_are_not_staged() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var outside: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.LEFT]), Vector2i.ZERO)
	var solid: ItemDef = _definition(ItemDef.Category.DECOR)
	solid.solid = true
	assert_not_null(grid.place_def(solid, Vector2i(3, 3)))
	var blocked: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.UP]), Vector2i(3, 4))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.failure_for(outside.id), "A seat is outside the shop")
	assert_eq(plan.failure_for(blocked.id), "Keep every seat on a clear floor tile")
	assert_true(plan.links.is_empty())


func test_invalid_built_in_seat_reports_table_without_removing_valid_authored_seat() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(5, 5))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i.ONE,
		[Vector2i.DOWN, Vector2i(-2, 0)]), Vector2i(1, 1))
	var before: Array[Vector2i] = table.seat_cells.duplicate()
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.failure_for(table.id), "A seat is outside the shop")
	assert_eq(plan.seats_for(table.id), [Vector2i(1, 2)] as Array[Vector2i])
	assert_eq(table.seat_cells, before)


func test_derive_uses_authored_seats_without_mutating_runtime_lists_or_reservations() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i.ONE,
		[Vector2i.DOWN]), Vector2i(3, 3))
	var authored: Array[Vector2i] = (table.def as ItemDef).seat_cells.duplicate()
	assert_true(table.reserve(Vector2i(3, 4), 91))
	table.seat_cells.append(Vector2i(6, 6))
	var before: Array[Dictionary] = _snapshot(grid)
	_changes = 0
	grid.cells_changed.connect(_on_cells_changed)
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_eq(plan.seats_for(table.id), [Vector2i(3, 4)] as Array[Vector2i], "old derived cells do not become authored seats")
	assert_eq(_snapshot(grid), before)
	assert_eq((table.def as ItemDef).seat_cells, authored)
	assert_eq(table.reserved_by(Vector2i(3, 4)), 91)
	assert_eq(_changes, 0)
	var detached: Array[Vector2i] = plan.seats_for(table.id)
	detached.append(Vector2i.ONE)
	assert_eq(plan.seats_for(table.id), [Vector2i(3, 4)] as Array[Vector2i])
	(plan.table_seats[table.id] as Array).append(Vector2i(5, 5))
	assert_eq(_snapshot(grid), before, "even editing the staged plan cannot edit the grid")


func test_removed_surface_leaves_diagnostic_without_reusing_old_derived_links() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), Vector2i(3, 3))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO]), Vector2i(3, 4))
	assert_eq(DiningSeats.derive(grid).links.size(), 1)
	assert_true(grid.remove(table.id))
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_false(plan.table_seats.has(table.id))
	assert_eq(plan.failure_for(chair.id), "Place every seat facing a table or counter")
	assert_true(plan.links.is_empty())
	assert_eq(chair.seat_cells, [chair.origin] as Array[Vector2i])


func test_missing_grid_and_chair_without_seat_cells_have_readable_failures() -> void:
	assert_eq(DiningSeats.derive(null).failure_for(0), "The shop is unavailable")
	var grid: SimGrid = SimGrid.new(Vector2i(4, 4))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[] as Array[Vector2i]), Vector2i(1, 1))
	assert_eq(DiningSeats.derive(grid).failure_for(chair.id), "This seat has no seating position")


func test_generic_placements_and_non_dining_definitions_keep_existing_behavior() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(6, 6))
	var generic: PlacedItem = grid.place(Vector2i.ONE, Vector2i(1, 1), 0, false,
		[] as Array[Vector2i], [Vector2i.ZERO] as Array[Vector2i], Resource.new())
	var decor: PlacedItem = grid.place_def(_definition(ItemDef.Category.DECOR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(3, 3))
	var before: Array[Dictionary] = _snapshot(grid)
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	assert_true(plan.table_seats.is_empty())
	assert_true(plan.links.is_empty())
	assert_true(plan.failures.is_empty())
	assert_eq(_snapshot(grid), before)
	assert_eq(generic.seat_cells, [generic.origin] as Array[Vector2i])
	assert_eq(decor.seat_cells, [decor.origin] as Array[Vector2i])


func _definition(category: ItemDef.Category, footprint: Vector2i = Vector2i.ONE,
		seats: Array[Vector2i] = []) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"synthetic_dining_item"
	definition.display_name = "Dining item"
	definition.category = category
	definition.footprint = footprint
	definition.solid = category == ItemDef.Category.TABLE
	definition.seat_cells = seats.duplicate()
	return definition


func _snapshot(grid: SimGrid) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for placed: PlacedItem in grid.items():
		items.append({"id": placed.id, "definition": placed.def, "origin": placed.origin,
			"rotation": placed.quarter_turns, "cells": placed.cells.duplicate(),
			"work_cells": placed.work_cells.duplicate(), "seat_cells": placed.seat_cells.duplicate(),
			"reservations": placed._reservations.duplicate(), "removed": placed.removed})
	return items


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	_changes += 1
