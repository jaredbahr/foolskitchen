extends TestCase
## Actual starter doorway, real guest lifecycle and ordered pending births.
## Fixture staging occurs in MORNING; active service never teleports people.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CLUSTER_WATCHDOG: int = 512

var _content: ContentDB
var _sims: Array[RestaurantSim] = []
var _arrived: Array[int] = []
var _departed: Array[int] = []
var _next_seed: int = 263


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_arrived.clear()
	_departed.clear()
	_next_seed = 263


func after_each() -> void:
	for sim: RestaurantSim in _sims:
		sim.customer_arrived.disconnect(_on_arrived)
		sim.customer_left.disconnect(_on_left)
	_sims.clear()


func test_leaving_guest_settles_at_either_actual_entry_without_crossing_an_occupied_other_entry() -> void:
	for index: int in 2:
		_arrived.clear()
		_departed.clear()
		var sim: RestaurantSim = _restaurant()
		var entries: Array[Vector2i] = sim.world.grid.entries()
		assert_eq(entries.size(), 2)
		if entries.size() != 2:
			return
		var exit: Vector2i = entries[index]
		var other: Vector2i = entries[1 - index]
		var leaving: CustomerAgent = _arrival(sim, exit)
		leaving.state = CustomerAgent.State.LEAVING
		leaving.leave_reason = &"no_table"
		var incoming: CustomerAgent = _arrival(sim, other)
		assert_eq(sim.world.agent(incoming.id), incoming)
		assert_true(leaving.set_destination(sim.world.grid, other), "a retained route may still target the other entry")
		assert_eq(leaving.move_progress, 0.0)
		assert_true(sim.world.clock.start_service())
		if not _advance(sim):
			return
		assert_eq(leaving.cell, exit, "departure uses the real door vertex already reached")
		assert_eq(leaving.state, CustomerAgent.State.LEFT)
		assert_null(sim.world.agent(leaving.id), "ordinary RestaurantSim cleanup settles the departure")
		assert_eq(_departed, [leaving.id] as Array[int])
		assert_eq(sim.lost_today, 1)
		assert_eq(_arrived.size(), 2)
		assert_eq(sim.customers().size(), 1, "the incoming visit remains accounted for")


func test_leaving_guest_on_a_partial_edge_between_entries_is_not_removed_mid_edge() -> void:
	var sim: RestaurantSim = _restaurant()
	var entries: Array[Vector2i] = sim.world.grid.entries()
	assert_eq(entries.size(), 2)
	if entries.size() != 2:
		return
	var guest: CustomerAgent = _arrival(sim, entries[0])
	guest.state = CustomerAgent.State.LEAVING
	guest.leave_reason = &"no_table"
	assert_true(guest.set_destination(sim.world.grid, entries[1]))
	# Start a real claimed physical edge through the public movement API in
	# fixture setup. No progress, trace or ownership map is fabricated.
	guest.begin_movement_trace(sim.world.now)
	assert_eq(guest.step_move(sim.world), SimAgent.MoveResult.MOVING)
	guest.end_movement_trace()
	assert_true(guest.move_progress > 0.0 and guest.move_progress < 1.0)
	assert_eq(guest.cell, entries[0])
	assert_true(sim.world.clock.start_service())
	var partial_ticks: int = 0
	for tick: int in 8:
		if not _advance(sim):
			return
		if sim.world.agent(guest.id) == null:
			break
		partial_ticks += 1
		assert_eq(guest.state, CustomerAgent.State.LEAVING)
		assert_true(guest.move_progress > 0.0, "a partial departure cannot disappear just because its source is a door")
		assert_true(_departed.is_empty())
	assert_true(partial_ticks > 0)
	assert_eq(guest.cell, entries[1])
	assert_eq(guest.state, CustomerAgent.State.LEFT)
	assert_null(sim.world.agent(guest.id))
	assert_eq(_departed, [guest.id] as Array[int])
	assert_eq(sim.lost_today, 1)


func test_boxed_door_losers_allow_cooperative_progress_and_pending_births_keep_their_place() -> void:
	var sim: RestaurantSim = _restaurant()
	var world: SimWorld = sim.world
	var entries: Array[Vector2i] = world.grid.entries()
	assert_eq(entries.size(), 2)
	if entries.size() != 2:
		return
	entries.sort_custom(_left_to_right_cell)
	var left: Vector2i = entries[0]
	var right: Vector2i = entries[1]
	assert_eq(right, left + Vector2i.RIGHT)
	var leavers: Array[CustomerAgent] = []
	for entry: Vector2i in entries:
		var guest: CustomerAgent = _arrival(sim, entry)
		assert_true(world.reset_agent_position(guest, entry + Vector2i.UP * 2))
		guest.state = CustomerAgent.State.LEAVING
		guest.leave_reason = &"no_table"
		assert_true(guest.set_destination(world.grid, entry))
		leavers.append(guest)
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	tables.sort_custom(_left_to_right_table)
	assert_eq(tables.size(), 3)
	if tables.size() != 3:
		return
	var walkers: Array[CustomerAgent] = []
	var starts: Array[Vector2i] = [left + Vector2i.UP, right + Vector2i.UP, left, right]
	var bookings: Array[PlacedItem] = [tables[1], tables[2], tables[0], tables[0]]
	var goals: Array[Vector2i] = [_south_seat(tables[1]), _south_seat(tables[2]),
		_south_seat(tables[0]), _north_seat(tables[0])]
	for index: int in starts.size():
		var entry: Vector2i = left if index % 2 == 0 else right
		var guest: CustomerAgent = _arrival(sim, entry)
		if guest.cell != starts[index]:
			assert_true(world.reset_agent_position(guest, starts[index]))
		assert_true(bookings[index].reserve(goals[index], guest.id))
		guest.table_item_id = bookings[index].id
		guest.booked_table_ids.append(bookings[index].id)
		guest.seat_cell = goals[index]
		guest.state = CustomerAgent.State.WALKING_TO_SEAT
		assert_true(guest.set_destination(world.grid, goals[index]))
		walkers.append(guest)
	# Both genuine births request the occupied left entry. They remain outside
	# active actors, retain all arrival accounting, and must admit in ID order.
	var first_pending: CustomerAgent = _arrival(sim, left)
	var second_pending: CustomerAgent = _arrival(sim, left)
	assert_eq(world.pending_agent(first_pending.id), first_pending)
	assert_eq(world.pending_agent(second_pending.id), second_pending)
	assert_eq(world.pending_agents().size(), 2)
	assert_eq(_arrived.size(), 8)
	for index: int in 2:
		assert_true(leavers[index].id < walkers[index].id, "ordinary lower-ID priority prefers the outgoing guest")
		assert_eq(world.movement.priority(world, leavers[index]), world.movement.priority(world, walkers[index]))
		for cell: Vector2i in world.grid.walkable_neighbours(walkers[index].cell):
			assert_false(world.movement.can_enter(world, walkers[index], cell), "the preferred yielding loser is genuinely boxed")
	assert_true(world.movement.can_enter(world, leavers[0], left + Vector2i.UP * 2 + Vector2i.LEFT),
		"the winning left guest has a real free side pocket")
	assert_true(world.movement.can_enter(world, leavers[1], right + Vector2i.UP * 2 + Vector2i.RIGHT),
		"the winning right guest has a real free side pocket")
	for guest: CustomerAgent in leavers:
		assert_false(entries.has(guest.cell), "this case cannot pass via the already-at-entry correction alone")
	var admitted: Array[int] = []
	var pending: Array[CustomerAgent] = [first_pending, second_pending]
	var all_incoming: Array[CustomerAgent] = walkers.duplicate()
	all_incoming.append_array(pending)
	assert_true(world.clock.start_service())
	for tick: int in CLUSTER_WATCHDOG:
		if not _advance(sim):
			return
		for guest: CustomerAgent in pending:
			if world.agent(guest.id) == guest and not admitted.has(guest.id):
				admitted.append(guest.id)
			if world.pending_agent(guest.id) == guest:
				assert_eq(guest.state, CustomerAgent.State.ARRIVING)
				assert_eq(guest.get("_queue_wait"), 0, "pending births do not consume active queue patience")
		for guest: CustomerAgent in all_incoming:
			if guest.state in [CustomerAgent.State.QUEUED, CustomerAgent.State.LEAVING, CustomerAgent.State.LEFT]:
				fail("door progress must precede requeue/patience/forced-removal escape")
				return
		assert_eq(sim.customers().size() + _departed.size(), 8, "no active or pending person is dropped or hidden")
		if _departed.size() == 2 and admitted.size() == 2 and _all_seated(all_incoming):
			break
	assert_eq(_departed.size(), 2, "both real exiting visits reach a door before the bounded watchdog")
	assert_eq(sim.lost_today, 2, "only the two staged no-table exits settle as losses")
	for guest: CustomerAgent in leavers:
		assert_true(entries.has(guest.cell))
		assert_eq(guest.state, CustomerAgent.State.LEFT)
		assert_null(world.agent(guest.id))
	assert_eq(admitted, [first_pending.id, second_pending.id] as Array[int])
	assert_true(world.pending_agents().is_empty())
	assert_true(_all_seated(all_incoming), "all six real incoming guests physically reach their own dining seats")
	assert_eq(sim.customers().size(), 6)
	assert_eq(_arrived.size(), 8)


func _restaurant() -> RestaurantSim:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 263, errors, null, false)
	assert_eq(errors, [] as Array[String])
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	sim.spawner.reset()
	sim.customer_arrived.connect(_on_arrived)
	sim.customer_left.connect(_on_left)
	_sims.append(sim)
	return sim


func _arrival(sim: RestaurantSim, entry: Vector2i) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = _next_seed
	_next_seed += 1
	return sim.add_customer(entry, random)


func _advance(sim: RestaurantSim) -> bool:
	var before: Dictionary = MovementInvariants.capture(sim.world)
	sim.advance()
	var problem: String = MovementInvariants.problem(sim.world, before)
	assert_eq(problem, "", "every actual tick preserves occupied/next/edge/trace safety")
	return problem.is_empty()


func _all_seated(guests: Array[CustomerAgent]) -> bool:
	for guest: CustomerAgent in guests:
		if guest.cell != guest.seat_cell or guest.state not in [CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD]:
			return false
	return true


func _north_seat(table: PlacedItem) -> Vector2i:
	var result: Vector2i = table.seat_cells[0]
	for cell: Vector2i in table.seat_cells:
		if cell.y < result.y:
			result = cell
	return result


func _south_seat(table: PlacedItem) -> Vector2i:
	var result: Vector2i = table.seat_cells[0]
	for cell: Vector2i in table.seat_cells:
		if cell.y > result.y:
			result = cell
	return result


func _left_to_right_cell(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x


func _left_to_right_table(a: PlacedItem, b: PlacedItem) -> bool:
	return a.origin.x < b.origin.x


func _on_arrived(guest: CustomerAgent) -> void:
	assert_false(_arrived.has(guest.id))
	_arrived.append(guest.id)


func _on_left(guest: CustomerAgent, _reason: StringName) -> void:
	assert_false(_departed.has(guest.id))
	_departed.append(guest.id)
