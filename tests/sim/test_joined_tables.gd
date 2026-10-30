extends TestCase
## Initial existing-API fixture: preserve this complete source through first GREEN.

const TABLE: ItemDef = preload("res://data/items/cloth_table.tres")
const CHAIR: ItemDef = preload("res://data/items/chair.tres")
const OUTSIDE_SEATS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(5, 3), Vector2i(7, 3),
	Vector2i(3, 5), Vector2i(5, 5), Vector2i(7, 5)]

var _sim: RestaurantSim
var _tables: Array[PlacedItem] = []
var _chairs: Array[PlacedItem] = []


func before_each() -> void:
	_tables.clear()
	_chairs.clear()
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.new(Vector2i(14, 12)), SimClock.new())
	_sim.world.grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY)
	for origin: Vector2i in [Vector2i(3, 4), Vector2i(5, 4), Vector2i(7, 4)]:
		_tables.append(_sim.world.grid.place_def(TABLE, origin))
	for index: int in OUTSIDE_SEATS.size():
		_chairs.append(_sim.world.grid.place_def(CHAIR, OUTSIDE_SEATS[index], 2 if index < 3 else 0))


func after_each() -> void:
	_tables.clear()
	_chairs.clear()
	_sim = null


func test_three_joined_two_seat_surfaces_have_six_usable_outside_seats() -> void:
	if not _assert_legal_fixture():
		return
	assert_eq(DiningSeats.largest_usable_capacity(_sim.world.grid, Vector2i.ZERO), 6,
		"three joined two-seat tables form one six-seat table")


func test_actual_six_person_party_books_the_joined_surface_without_splitting() -> void:
	if not _assert_legal_fixture():
		return
	var randoms: Array[RandomNumberGenerator] = []
	for index: int in 6:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 24600 + index
		randoms.append(random)
	var party: Party = _sim.add_party(Vector2i.ZERO, randoms)
	assert_not_null(party, "the real party API accepts six people for the joined six-seat table")
	if party == null:
		return
	assert_true(party.is_valid())
	assert_eq(party.size(), 6)
	assert_eq(_sim.customers().size(), 6)
	assert_true(PartySeating.try_seat(party, _sim.world), "the six-person party acquires one complete booking")
	var held: Array[Vector2i] = []
	for guest: CustomerAgent in PartySeating.members(party, _sim.world):
		assert_eq(guest.table_item_id, _sim.world.grid.dining_table_id(guest.seat_cell),
			"each member keeps the physical owner of their booked seat")
		assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT)
		assert_true(OUTSIDE_SEATS.has(guest.seat_cell))
		assert_false(held.has(guest.seat_cell), "each member has a distinct outside seat")
		held.append(guest.seat_cell)
		var booking: PlacedItem = _sim.world.grid.item(guest.table_item_id)
		assert_not_null(booking)
		if booking != null:
			assert_true(_tables.has(booking), "every booking belongs to the joined three-table surface")
			assert_eq(booking.reserved_by(guest.seat_cell), guest.id)
	assert_eq(held.size(), 6)


func _assert_legal_fixture() -> bool:
	assert_eq(TABLE.id, &"cloth_table")
	assert_eq(TABLE.category, ItemDef.Category.TABLE)
	assert_eq(TABLE.capacity, 2)
	assert_eq(TABLE.footprint, Vector2i(2, 1))
	assert_true(TABLE.seat_cells.is_empty(), "all six chairs are standalone, with no duplicate built-ins")
	assert_eq(_tables.size(), 3)
	assert_eq(_chairs.size(), 6)
	var valid: bool = true
	for table: PlacedItem in _tables:
		assert_not_null(table, "each physical two-seat table placed legally")
		valid = valid and table != null
	for chair: PlacedItem in _chairs:
		assert_not_null(chair, "each outside chair placed legally")
		valid = valid and chair != null
	if not valid:
		return false
	var plan: DiningSeats.Plan = DiningSeats.derive(_sim.world.grid)
	assert_true(plan.failures.is_empty(), "every chair faces a real unobstructed dining surface")
	assert_eq(plan.links.size(), 6)
	var linked: Array[Vector2i] = []
	for link: DiningSeats.SeatLink in plan.links:
		assert_true(OUTSIDE_SEATS.has(link.cell))
		assert_false(linked.has(link.cell))
		linked.append(link.cell)
		assert_false(link.built_in)
		assert_true(_sim.world.grid.is_walkable(link.cell))
		assert_true(_sim.world.grid.is_guest_reachable(Vector2i.ZERO, link.cell))
		for table: PlacedItem in _tables:
			assert_false(table.cells.has(link.cell), "internal table cells cannot be seats")
	for seat: Vector2i in OUTSIDE_SEATS:
		assert_true(linked.has(seat))
	return true


func test_all_table_orders_and_furnishings_first_keep_the_same_geometric_group() -> void:
	for order: Array in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		for chairs_first: bool in [false, true]:
			var grid: SimGrid = _ordered_grid(order, chairs_first)
			var leader: PlacedItem = grid.item_at(Vector2i(3, 4))
			var group: DiningSeats.Group = grid.dining_group(leader.id)
			assert_not_null(group)
			if group == null:
				continue
			assert_eq(group.id, leader.id, "the leftmost table is the geometric leader, regardless of IDs")
			assert_true(group.is_joined())
			assert_eq(_member_origins(grid, group.member_ids), [Vector2i(3, 4), Vector2i(5, 4), Vector2i(7, 4)] as Array[Vector2i])
			assert_eq(group.seat_cells, OUTSIDE_SEATS)
			assert_eq(group.nominal_capacity, 6)
			assert_eq(DiningSeats.largest_usable_capacity(grid, Vector2i.ZERO), 6)
			for member_id: int in group.member_ids:
				assert_eq(grid.dining_group_id(member_id), leader.id)
				assert_eq(grid.dining_group_seats(member_id), OUTSIDE_SEATS)


func test_group_snapshots_are_detached_and_derivation_preserves_physical_holds_and_random_state() -> void:
	assert_true(_assert_legal_fixture())
	var grid: SimGrid = _sim.world.grid
	var owner: int = grid.dining_table_id(OUTSIDE_SEATS[4])
	assert_true(grid.item(owner).reserve(OUTSIDE_SEATS[4], 901))
	var before: Array = _physical_snapshot(grid)
	var random_state: int = _sim.rng.state
	var plan: DiningSeats.Plan = DiningSeats.derive(grid)
	var group: DiningSeats.Group = plan.group_for(_tables[2].id)
	assert_eq(group.seat_cells, OUTSIDE_SEATS)
	assert_eq(_physical_snapshot(grid), before)
	assert_eq(_sim.rng.state, random_state)
	group.member_ids.clear()
	group.seat_cells.clear()
	var cached: DiningSeats.Group = grid.dining_group(_tables[1].id)
	cached.member_ids.clear()
	cached.seat_cells.clear()
	var members: Array[int] = grid.dining_group_members(_tables[0].id)
	members.clear()
	var seats: Array[Vector2i] = grid.dining_group_seats(_tables[0].id)
	seats.clear()
	assert_eq(grid.dining_group_members(_tables[0].id).size(), 3)
	assert_eq(grid.dining_group_seats(_tables[0].id), OUTSIDE_SEATS)
	assert_eq(_physical_snapshot(grid), before)


func test_full_edges_join_but_partial_edges_corners_and_gaps_stay_separate() -> void:
	for row: Array in [[Vector2i(5, 3), Vector2i(2, 2), true],
			[Vector2i(5, 4), Vector2i(2, 2), false], [Vector2i(5, 5), Vector2i(2, 2), false],
			[Vector2i(6, 3), Vector2i(2, 2), false], [Vector2i(5, 3), Vector2i(2, 1), false]]:
		var grid: SimGrid = SimGrid.new(Vector2i(16, 14))
		var first: PlacedItem = grid.place_def(_surface(&"first", Vector2i(2, 2)), Vector2i(3, 3))
		var second: PlacedItem = grid.place_def(_surface(&"second", row[1]), row[0])
		assert_not_null(first)
		assert_not_null(second)
		assert_eq(grid.dining_group_id(first.id) == grid.dining_group_id(second.id), row[2])


func test_room_and_segment_mutations_recompute_the_same_room_unblocked_edge_rule() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_eq(grid.dining_group_members(_tables[0].id).size(), 3)
	var changes: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in _tables[1].cells:
		changes[cell] = SimGrid.Room.RESTROOM
	assert_true(grid.set_rooms(changes))
	for table: PlacedItem in _tables:
		assert_eq(grid.dining_group_members(table.id), [table.id] as Array[int])
	for cell: Vector2i in changes:
		changes[cell] = SimGrid.Room.DINING
	assert_true(grid.set_rooms(changes))
	assert_eq(grid.dining_group_members(_tables[2].id).size(), 3)
	assert_true(grid.set_rooms({Vector2i(5, 4): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int]))
	assert_eq(grid.dining_group_members(_tables[1].id).size(), 1, "a table spanning room labels stays standalone")
	assert_true(grid.set_rooms({Vector2i(5, 4): SimGrid.Room.DINING} as Dictionary[Vector2i, int]))
	for kind: SimGrid.Segment in [SimGrid.Segment.WALL, SimGrid.Segment.WINDOW, SimGrid.Segment.STALL_PARTITION]:
		assert_true(grid.set_segment(Vector3i(5, 4, SimGrid.EDGE_WEST), kind))
		assert_eq(grid.dining_group_members(_tables[0].id), [_tables[0].id] as Array[int])
		assert_eq(grid.dining_group_members(_tables[2].id).size(), 2)
		assert_true(grid.set_segment(Vector3i(5, 4, SimGrid.EDGE_WEST), SimGrid.Segment.NONE))
		assert_eq(grid.dining_group_members(_tables[0].id).size(), 3)


func test_relocating_and_removing_a_middle_member_splits_and_rejoins_without_stale_seats() -> void:
	var grid: SimGrid = _sim.world.grid
	var middle: PlacedItem = _tables[1]
	assert_true(grid.relocate_def(middle.id, Vector2i(5, 8), 0))
	assert_true(grid.item(middle.id) == middle)
	for table: PlacedItem in _tables:
		assert_eq(grid.dining_group_members(table.id), [table.id] as Array[int])
	assert_eq(grid.dining_table_id(Vector2i(5, 3)), 0)
	assert_eq(grid.dining_table_id(Vector2i(5, 5)), 0)
	assert_eq(DiningSeats.largest_usable_capacity(grid, Vector2i.ZERO), 2)
	assert_true(grid.relocate_def(middle.id, Vector2i(5, 4), 0))
	assert_eq(grid.dining_group_seats(middle.id), OUTSIDE_SEATS)
	assert_true(grid.remove(middle.id))
	assert_eq(grid.dining_group_id(middle.id), 0)
	assert_null(grid.dining_group(middle.id))
	assert_eq(grid.dining_group_members(_tables[0].id), [_tables[0].id] as Array[int])
	assert_eq(grid.dining_group_members(_tables[2].id), [_tables[2].id] as Array[int])


func test_real_builtin_seam_positions_do_not_count_and_standalone_seat_order_is_unchanged() -> void:
	var definition: ItemDef = preload("res://data/items/table_2.tres")
	var grid: SimGrid = SimGrid.new(Vector2i(16, 12))
	var first: PlacedItem = grid.place_def(definition, Vector2i(3, 4))
	assert_eq(first.seat_cells, [Vector2i(2, 5), Vector2i(5, 5)] as Array[Vector2i])
	assert_eq(DiningSeats.usable_cells(grid, first, Vector2i.ZERO), first.seat_cells)
	var second: PlacedItem = grid.place_def(definition, Vector2i(5, 4))
	var third: PlacedItem = grid.place_def(definition, Vector2i(7, 4))
	assert_eq(grid.dining_group_members(third.id), [first.id, second.id, third.id] as Array[int])
	assert_eq(grid.dining_group_seats(second.id), [Vector2i(2, 5), Vector2i(9, 5)] as Array[Vector2i])
	assert_eq(DiningSeats.nominal_capacity(grid, second), 2, "four authored seam chairs are inside the union")
	assert_eq(DiningSeats.largest_usable_capacity(grid, Vector2i.ZERO), 2)
	for seam: Vector2i in [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		assert_false(grid.dining_group_seats(first.id).has(seam))


func test_mixed_table_ids_join_while_real_counter_and_booth_do_not_bridge_groups() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(20, 16))
	var first: PlacedItem = grid.place_def(TABLE, Vector2i(3, 4))
	var mixed: PlacedItem = grid.place_def(preload("res://data/items/glass_table.tres"), Vector2i(5, 4))
	var counter: PlacedItem = grid.place_def(preload("res://data/items/bar_counter.tres"), Vector2i(7, 4))
	var remote: PlacedItem = grid.place_def(TABLE, Vector2i(9, 4))
	assert_eq(grid.dining_group_members(first.id), [first.id, mixed.id] as Array[int])
	assert_eq(grid.dining_group_members(counter.id), [counter.id] as Array[int])
	assert_eq(grid.dining_group_members(remote.id), [remote.id] as Array[int])
	var booth: PlacedItem = grid.place_def(preload("res://data/items/diner_booth.tres"), Vector2i(3, 5))
	assert_not_null(booth)
	assert_eq(grid.dining_group_id(booth.id), 0)
	assert_eq(grid.dining_group_members(first.id), [first.id, mixed.id] as Array[int])
	assert_eq(first.seat_cells, [Vector2i(3, 5), Vector2i(4, 5)] as Array[Vector2i])
	assert_false(grid.is_walkable(Vector2i(3, 6)), "the booth back remains solid")


func test_group_reservation_is_atomic_across_physical_members_and_preserves_foreign_and_own_holds() -> void:
	var grid: SimGrid = _sim.world.grid
	var seats: Array[Vector2i] = OUTSIDE_SEATS.duplicate()
	var ids: Array[int] = [101, 102, 103, 104, 105, 106]
	var owner: PlacedItem = grid.item(grid.dining_table_id(seats[4]))
	assert_true(owner.reserve(seats[4], 999))
	assert_false(grid.reserve_dining_seats(_tables[0].id, seats, ids))
	for index: int in seats.size():
		var physical: PlacedItem = grid.item(grid.dining_table_id(seats[index]))
		assert_eq(physical.reserved_by(seats[index]), 999 if index == 4 else -1)
	assert_true(owner.release(seats[4], 999))
	assert_true(_tables[0].reserve(seats[0], ids[0]))
	assert_false(grid.reserve_dining_seats(_tables[0].id, [seats[0], seats[0]] as Array[Vector2i], [101, 102] as Array[int]))
	assert_eq(_tables[0].reserved_by(seats[0]), 101)
	assert_false(grid.reserve_dining_seats(_tables[0].id, seats, [101, 102, 103, 104, 105] as Array[int]))
	assert_false(grid.reserve_dining_seats(_tables[0].id, seats, [101, 102, 103, 104, 105, 105] as Array[int]))
	assert_true(grid.reserve_dining_seats(_tables[2].id, seats, ids))
	for index: int in seats.size():
		assert_eq(grid.dining_owner_id(_tables[1].id, seats[index]), grid.dining_table_id(seats[index]))
		assert_eq(grid.item(grid.dining_table_id(seats[index])).reserved_by(seats[index]), ids[index])
	for table: PlacedItem in _tables:
		assert_true(grid.dining_group_has_reservations(table.id))


func test_capacity_is_not_capped_to_party_limit_and_explicit_seven_is_rejected_without_installing_guests() -> void:
	var grid: SimGrid = _sim.world.grid
	var fourth: PlacedItem = grid.place_def(TABLE, Vector2i(9, 4))
	assert_not_null(fourth)
	assert_not_null(grid.place_def(CHAIR, Vector2i(9, 3), 2))
	assert_not_null(grid.place_def(CHAIR, Vector2i(9, 5), 0))
	assert_eq(DiningSeats.largest_usable_capacity(grid, Vector2i.ZERO), 8)
	var randoms: Array[RandomNumberGenerator] = []
	var states: Array[int] = []
	for index: int in 7:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 24670 + index
		randoms.append(random)
		states.append(random.state)
	assert_null(_sim.add_party(Vector2i.ZERO, randoms))
	assert_true(_sim.customers().is_empty())
	assert_false(Party.new([1, 2, 3, 4, 5, 6, 7] as Array[int]).is_valid())
	for index: int in randoms.size():
		assert_eq(randoms[index].state, states[index])


func _ordered_grid(order: Array, chairs_first: bool) -> SimGrid:
	var grid: SimGrid = SimGrid.new(Vector2i(14, 12))
	if chairs_first:
		_add_outside_chairs(grid)
	for index: int in order:
		assert_not_null(grid.place_def(TABLE, Vector2i(3 + index * 2, 4)))
	if not chairs_first:
		_add_outside_chairs(grid)
	return grid


func _add_outside_chairs(grid: SimGrid) -> void:
	for index: int in OUTSIDE_SEATS.size():
		assert_not_null(grid.place_def(CHAIR, OUTSIDE_SEATS[index], 2 if index < 3 else 0))


func _member_origins(grid: SimGrid, members: Array[int]) -> Array[Vector2i]:
	var origins: Array[Vector2i] = []
	for member_id: int in members:
		origins.append(grid.item(member_id).origin)
	return origins


func _surface(id: StringName, footprint: Vector2i) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.category = ItemDef.Category.TABLE
	definition.solid = true
	definition.footprint = footprint
	return definition


func _physical_snapshot(grid: SimGrid) -> Array:
	var result: Array = []
	for item: PlacedItem in grid.items():
		result.append([item.id, item.origin, item.quarter_turns, item.cells.duplicate(),
			item.seat_cells.duplicate(), item._reservations.duplicate()])
	return result


func test_rotating_the_entire_real_cloth_and_chair_fixture_preserves_six_outside_seats() -> void:
	for turns: int in 4:
		var grid: SimGrid = SimGrid.new(Vector2i(16, 16))
		var tables: Array[PlacedItem] = []
		for x: int in [3, 5, 7]:
			# Rotate both occupied cells independently, then take their minimum.
			var a: Vector2i = _rotate_fixture_cell(Vector2i(x, 4), turns)
			var b: Vector2i = _rotate_fixture_cell(Vector2i(x + 1, 4), turns)
			tables.append(grid.place_def(TABLE, Vector2i(mini(a.x, b.x), mini(a.y, b.y)), turns))
		var expected: Array[Vector2i] = []
		for index: int in OUTSIDE_SEATS.size():
			var cell: Vector2i = _rotate_fixture_cell(OUTSIDE_SEATS[index], turns)
			expected.append(cell)
			assert_not_null(grid.place_def(CHAIR, cell, ((2 if index < 3 else 0) + turns) % 4))
		assert_eq(grid.dining_group_members(tables[0].id).size(), 3)
		var seats: Array[Vector2i] = grid.dining_group_seats(tables[0].id)
		assert_eq(seats.size(), 6)
		for cell: Vector2i in expected:
			assert_true(seats.has(cell))
		assert_eq(DiningSeats.largest_usable_capacity(grid, Vector2i.ZERO), 6)


func _rotate_fixture_cell(cell: Vector2i, turns: int) -> Vector2i:
	match turns:
		1:
			return Vector2i(15 - cell.y, cell.x)
		2:
			return Vector2i(15 - cell.x, 15 - cell.y)
		3:
			return Vector2i(cell.y, 15 - cell.x)
	return cell
