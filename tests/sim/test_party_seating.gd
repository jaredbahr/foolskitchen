extends TestCase
## Source-prepared FK-066 coverage. Execution is deferred while the demo runs.

const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const TABLE: ItemDef = preload("res://data/items/table_4.tres")


func test_authored_ranges_and_fixed_singletons_keep_the_random_stream() -> void:
	assert_true(TYPES.is_valid())
	for kind: CustomerType in TYPES.types:
		assert_eq(kind.party_size_min, 2 if kind.id == &"family" else 1)
		assert_eq(kind.party_size_max, 4 if kind.id == &"family" else 2)
		var one: CustomerType = kind.duplicate() as CustomerType
		one.party_size_min = 1
		one.party_size_max = 1
		var random: RandomNumberGenerator = _rng(7)
		var before: int = random.state
		assert_eq(one.draw_party_size(random), 1)
		assert_eq(random.state, before)
	var family: CustomerType = TYPES.find_type(&"family")
	var actual: RandomNumberGenerator = _rng(42)
	var oracle: RandomNumberGenerator = _rng(42)
	for index: int in 40:
		assert_eq(family.draw_party_size(actual), oracle.randi_range(2, 4))
	assert_eq(actual.state, oracle.state)


func test_invalid_ranges_and_member_ids_are_rejected_without_a_draw() -> void:
	var kind: CustomerType = TYPES.types[0].duplicate() as CustomerType
	var random: RandomNumberGenerator = _rng(1)
	var before: int = random.state
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 5)]:
		kind.party_size_min = pair.x
		kind.party_size_max = pair.y
		assert_false(kind.is_valid())
		assert_eq(kind.draw_party_size(random), 0)
	assert_eq(random.state, before)
	assert_false(Party.new().is_valid())
	assert_false(Party.new([1, 1] as Array[int]).is_valid())
	assert_false(Party.new([0, 2] as Array[int]).is_valid())
	assert_true(Party.new([1, 2, 3] as Array[int]).is_valid())
	assert_eq(Party.new([1, 2, 3] as Array[int]).label(), "Party of 3")


func test_three_wait_for_one_table_and_never_split_across_two_small_tables() -> void:
	var sim: RestaurantSim = _sim()
	var small: Array[PlacedItem] = []
	for origin: Vector2i in [Vector2i(2, 3), Vector2i(7, 3)]:
		small.append(sim.world.grid.place(Vector2i.ONE, origin, 0, true,
			[], [Vector2i(-1, 0), Vector2i(1, 0)] as Array[Vector2i]))
	var party: Party = _party(sim, 3)
	assert_false(PartySeating.try_seat(party, sim.world))
	for table: PlacedItem in small:
		for seat: Vector2i in table.seat_cells:
			assert_eq(table.reserved_by(seat), -1, "failed matching leaves no partial hold")
	var large: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(4, 7))
	assert_not_null(large)
	assert_true(PartySeating.try_seat(party, sim.world))
	var seen: Array[Vector2i] = []
	for guest: CustomerAgent in PartySeating.members(party, sim.world):
		assert_eq(guest.table_item_id, large.id)
		assert_eq(large.reserved_by(guest.seat_cell), guest.id)
		assert_false(seen.has(guest.seat_cell))
		seen.append(guest.seat_cell)
		assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT)


func test_other_guests_reservations_and_blocked_seats_reduce_free_capacity() -> void:
	var sim: RestaurantSim = _sim()
	var table: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(4, 5))
	var party: Party = _party(sim, 3)
	assert_true(table.reserve(table.seat_cells[0], 900))
	assert_true(table.reserve(table.seat_cells[1], 901))
	assert_false(PartySeating.try_seat(party, sim.world))
	assert_true(table.release(table.seat_cells[1], 901))
	var blocker: PlacedItem = sim.world.grid.place(Vector2i.ONE, table.seat_cells[1], 0, true)
	assert_false(PartySeating.try_seat(party, sim.world))
	assert_true(sim.world.grid.remove(blocker.id))
	assert_true(PartySeating.try_seat(party, sim.world))
	assert_eq(table.reserved_by(table.seat_cells[0]), 900, "another party's hold is retained")


func test_matching_backtracks_instead_of_stranding_the_last_member() -> void:
	var left: Vector2i = Vector2i(1, 1)
	var right: Vector2i = Vector2i(2, 1)
	var choices: Array[Array] = [[left, right], [left]]
	var seats: Array[Vector2i] = []
	assert_true(PartySeating._match(choices, 0, seats))
	assert_eq(seats, [right, left] as Array[Vector2i])


func test_timeout_leaves_every_member_and_counts_each_reason_once() -> void:
	var sim: RestaurantSim = _sim()
	var party: Party = _party(sim, 3)
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	for guest: CustomerAgent in guests:
		guest.queue_patience = 2
	for tick: int in 3:
		sim.world.now = tick
		for guest: CustomerAgent in guests:
			PartySeating.advance_queue(party, sim.world, sim)
		assert_eq(party.queue_wait, tick, "party size never accelerates the wait timer")
	assert_true(party.departing)
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.LEAVING)
		assert_eq(guest.leave_reason, &"no_table")
		sim.world.remove_agent(guest)
		sim.record_departure(guest)
	assert_eq(sim.lost_today, 3)
	assert_eq(sim.leave_reasons_today.get(&"no_table", 0), 3)
	assert_eq(sim.served_today, 0)


func test_failed_seat_walk_releases_every_hold_and_charges_elapsed_time_once() -> void:
	var sim: RestaurantSim = _sim()
	var table: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(4, 5))
	var party: Party = _party(sim, 3)
	assert_true(PartySeating.try_seat(party, sim.world))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	for index: int in guests.size():
		guests[index]._walk_wait = 10 + index
	PartySeating.requeue(party, sim.world, sim)
	assert_eq(party.queue_wait, 12)
	assert_eq(party.table_item_id, 0)
	for seat: Vector2i in table.seat_cells:
		assert_eq(table.reserved_by(seat), -1)
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.QUEUED)
		assert_eq(guest._queue_wait, 12)
		assert_eq(guest._walk_wait, 0)
		assert_eq(guest.table_item_id, 0)
		assert_true(guest.path.is_empty())


func test_orders_start_only_after_all_members_reach_the_same_table() -> void:
	var sim: RestaurantSim = _sim()
	sim.menu = [preload("res://data/recipes/burger.tres")] as Array[RecipeDef]
	var table: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(4, 5))
	var party: Party = _party(sim, 3)
	assert_true(PartySeating.try_seat(party, sim.world))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	guests[0].cell = guests[0].seat_cell
	PartySeating.finish_seating(party, sim.world, sim)
	assert_false(party.seated)
	assert_true(sim.world.board.open_tasks().is_empty())
	for guest: CustomerAgent in guests:
		guest.cell = guest.seat_cell
	PartySeating.finish_seating(party, sim.world, sim)
	assert_true(party.seated)
	assert_eq(sim.world.board.open_tasks().size(), 3)
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.ORDERING)
		assert_true(guest._take_order(SimAgent.new()))
		assert_not_null(guest.order)
		assert_eq(guest.order.customer_id, guest.id)
		assert_eq(guest.order.table_item_id, table.id)
		assert_eq(guest.order.seat_cell, guest.seat_cell)
	assert_ne(guests[0].order, guests[1].order, "orders remain individual")
	PartySeating.leave_waiting(party, sim.world, sim)
	assert_false(party.departing, "seated diners retain individual food/payment outcomes")


func test_four_seat_table_places_with_all_seats_reachable_in_every_rotation() -> void:
	assert_eq(TABLE.footprint, Vector2i(2, 3))
	assert_eq(TABLE.capacity, 4)
	assert_eq(TABLE.price, 90)
	for turns: int in 4:
		var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
		var table: PlacedItem = grid.place_def(TABLE, Vector2i(4, 4), turns)
		assert_not_null(table)
		assert_eq(table.seat_cells.size(), 4)
		for seat: Vector2i in table.seat_cells:
			assert_true(grid.is_walkable(seat))
			assert_true(grid.is_reachable(Vector2i.ZERO, seat))
			assert_false(grid.walkable_neighbours(seat).is_empty())


func _sim() -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(SimGrid.new(Vector2i(12, 12)), SimClock.new())
	return sim


func _party(sim: RestaurantSim, count: int) -> Party:
	var ids: Array[int] = []
	for index: int in count:
		var guest: CustomerAgent = sim.add_customer(Vector2i(0, 0), _rng(index + 1))
		ids.append(guest.id)
	return Party.new(ids)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
