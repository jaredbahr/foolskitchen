extends TestCase
## Genuine guest yields induced by a real employee's claimed crossing task.
## Public fixture staging happens in MORNING; no coordinator maps, counters,
## phases, reservations, progress or lifecycle states are manufactured.

const WATCHDOG: int = 512
const WAITER: Vector2i = Vector2i(2, 1)
const POCKET: Vector2i = Vector2i(2, 0)
const CROSSING_GOAL: Vector2i = Vector2i(6, 1)

var _crossed_cells: Array[Vector2i] = []


func before_each() -> void:
	_crossed_cells.clear()


func test_ordinary_queue_retains_first_free_search_and_one_charge_per_tick() -> void:
	var fixture: Dictionary = _fixture(1, false)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var guest: CustomerAgent = (fixture["guests"] as Array[CustomerAgent])[0]
	var private_state: int = guest.rng.state
	var arrivals_state: int = sim.rng.state
	assert_eq(guest.state, CustomerAgent.State.ARRIVING)
	assert_eq(guest._queue_wait, 0)
	for tick: int in 5:
		if not _advance(sim):
			return
		assert_eq(guest.state, CustomerAgent.State.QUEUED)
		assert_eq(guest._queue_wait, tick, "only the first arrival search is free")
		assert_eq(guest.cell, WAITER)
		assert_false(sim.world.movement.is_yielding(guest.id))
	assert_eq(guest.rng.state, private_state)
	assert_eq(sim.rng.state, arrivals_state)


func test_actual_unbooked_waiter_finishes_its_pocket_and_resumes_queue_there() -> void:
	var fixture: Dictionary = _fixture(1)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var guest: CustomerAgent = (fixture["guests"] as Array[CustomerAgent])[0]
	var private_state: int = guest.rng.state
	var saw_partial_yield: bool = false
	var reached_pocket: bool = false
	for tick: int in WATCHDOG:
		var before_wait: int = guest._queue_wait
		var before_state: CustomerAgent.State = guest.state
		if not _advance(sim):
			return
		if before_state == CustomerAgent.State.QUEUED and guest.state == CustomerAgent.State.QUEUED:
			assert_eq(guest._queue_wait, before_wait + 1, "physical yielding cannot freeze active queue patience")
		saw_partial_yield = saw_partial_yield or (sim.world.movement.is_yielding(guest.id) and guest.move_progress > 0.0)
		reached_pocket = reached_pocket or guest.cell == POCKET
		if reached_pocket and not sim.world.movement.is_yielding(guest.id):
			break
	assert_true(saw_partial_yield, "the fixture must traverse a real reserved outbound edge")
	assert_true(reached_pocket)
	assert_eq(guest.cell, POCKET, "an unbooked diner may keep waiting on the ordinary floor it reached")
	assert_eq(guest.move_progress, 0.0)
	assert_true(guest.has_arrived())
	assert_eq(guest.destination(), POCKET, "a future yield cannot resurrect the obsolete door-floor destination")
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(guest.rng.state, private_state)
	assert_eq(sim.served_today, 0)
	assert_eq(sim.lost_today, 0)


func test_public_new_party_booking_at_yield_vertex_replaces_only_obsolete_return() -> void:
	var fixture: Dictionary = _fixture(2)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var party: Party = fixture["party"] as Party
	var guests: Array[CustomerAgent] = fixture["guests"] as Array[CustomerAgent]
	if not _reach_yield(fixture, false):
		return
	var before: Dictionary = sim.world.movement.snapshot()
	var table: PlacedItem = _table(sim)
	assert_true(PartySeating.try_seat(party, sim.world))
	assert_false(sim.world.movement.is_yielding(guests[0].id), "a real NEW seat journey supersedes the old floor return")
	assert_eq(sim.world.movement.snapshot().occupied, before.occupied)
	assert_eq(sim.world.movement.snapshot().next, before.next, "new intent cannot erase a peer's swept/next claims")
	assert_eq(sim.world.movement.snapshot().edges, before.edges)
	_assert_bookings(guests, table)
	_assert_physically_seated(sim, party, guests)


func test_public_new_booking_mid_edge_finishes_exact_old_edge_before_new_journey() -> void:
	var fixture: Dictionary = _fixture(2)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var party: Party = fixture["party"] as Party
	var guests: Array[CustomerAgent] = fixture["guests"] as Array[CustomerAgent]
	if not _reach_yield(fixture, true):
		return
	var guest: CustomerAgent = guests[0]
	var before: Dictionary = sim.world.movement.snapshot()
	var position: Vector3 = guest.movement_position()
	var progress: float = guest.move_progress
	var next: Vector2i = guest.next_cell()
	var table: PlacedItem = _table(sim)
	assert_true(PartySeating.try_seat(party, sim.world))
	assert_true(sim.world.movement.is_stopping(guest.id))
	assert_eq(guest.movement_position(), position)
	assert_eq(guest.move_progress, progress)
	assert_eq(guest.next_cell(), next)
	assert_eq(sim.world.movement.snapshot().occupied, before.occupied)
	assert_eq(sim.world.movement.snapshot().next, before.next)
	assert_eq(sim.world.movement.snapshot().edges, before.edges, "public retargeting retains the exact reserved partial edge")
	_assert_bookings(guests, table)
	if not _finish_reserved_edge(sim, guest, guest.cell, next):
		return
	_assert_physically_seated(sim, party, guests)


func test_same_goal_public_repath_retains_yield_intent_and_physical_claims() -> void:
	var fixture: Dictionary = _fixture(1)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var guest: CustomerAgent = (fixture["guests"] as Array[CustomerAgent])[0]
	if not _reach_yield(fixture, false):
		return
	var goal: Vector2i = guest.destination()
	var before: Dictionary = sim.world.movement.snapshot()
	assert_true(guest.repath(sim.world.grid))
	assert_eq(guest.destination(), goal)
	assert_true(sim.world.movement.is_yielding(guest.id), "same-goal repath is not a NEW destination")
	assert_eq(sim.world.movement.snapshot().occupied, before.occupied)
	assert_eq(sim.world.movement.snapshot().next, before.next)
	assert_eq(sim.world.movement.snapshot().edges, before.edges)
	assert_eq(guest.move_progress, 0.0)


func test_queue_timeout_runs_during_real_reserved_stop_without_second_movement() -> void:
	var fixture: Dictionary = _fixture(1)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var guest: CustomerAgent = (fixture["guests"] as Array[CustomerAgent])[0]
	guest.queue_patience = 24
	if not _reach_yield(fixture, true):
		return
	guest.clear_path()
	assert_true(sim.world.movement.is_stopping(guest.id))
	# Ordinary public speed configuration keeps this genuine claimed edge partial
	# beyond the queue deadline; no budget or coordinator state is shortened.
	guest.move_speed = 0.001
	var edge: Dictionary = _edge(sim.world, guest)
	var private_state: int = guest.rng.state
	var deadline_ticks: int = guest.queue_patience - guest._queue_wait
	var started_tick: int = sim.world.now
	for tick: int in 24:
		var before_wait: int = guest._queue_wait
		var before_progress: float = guest.move_progress
		if not _advance(sim):
			return
		assert_almost_eq(guest.move_progress, before_progress + guest.move_speed)
		assert_eq(_edge(sim.world, guest), edge)
		assert_eq(guest._queue_wait, before_wait + 1)
		if guest.state == CustomerAgent.State.LEAVING:
			break
	assert_eq(sim.world.now - started_tick, deadline_ticks, "the consumed edge neither freezes nor accelerates the queue deadline")
	assert_eq(guest._queue_wait, guest.queue_patience)
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	assert_eq(guest.leave_reason, &"no_table")
	assert_true(sim.world.movement.is_stopping(guest.id))
	assert_eq(_edge(sim.world, guest), edge, "timeout cannot abandon its reserved partial edge")
	assert_eq(guest.rng.state, private_state)


func test_party_seat_walk_budget_runs_during_real_partial_retarget_stop_once() -> void:
	var fixture: Dictionary = _fixture(2)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var party: Party = fixture["party"] as Party
	var guests: Array[CustomerAgent] = fixture["guests"] as Array[CustomerAgent]
	if not _reach_yield(fixture, true):
		return
	var guest: CustomerAgent = guests[0]
	var queue_before: int = party.queue_wait
	_table(sim)
	assert_true(PartySeating.try_seat(party, sim.world))
	assert_true(sim.world.movement.is_stopping(guest.id))
	guest.move_speed = 0.001
	var edge: Dictionary = _edge(sim.world, guest)
	for tick: int in CustomerAgent.SEAT_WALK_LIMIT:
		if not _advance(sim):
			return
		assert_eq(_edge(sim.world, guest), edge)
		if guest.state == CustomerAgent.State.QUEUED:
			break
		assert_eq(guest._walk_wait, tick + 1, "a consumed STOP tick spends exactly one seat-walk tick")
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(party.table_item_id, 0)
	assert_eq(party.queue_wait, queue_before + CustomerAgent.SEAT_WALK_LIMIT, "the longest concurrent party walk is charged once")
	for member: CustomerAgent in guests:
		assert_eq(member._walk_wait, 0)
		assert_eq(member._queue_wait, queue_before + CustomerAgent.SEAT_WALK_LIMIT)
	assert_true(sim.world.movement.is_stopping(guest.id))
	assert_eq(_edge(sim.world, guest), edge)


## The street door is far from the waiter's aisle (#305): waiters stand clear of
## the door lane, and these tests are about an aisle waiter being yielded.
func _fixture(count: int, crossing: bool = true) -> Dictionary:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(SimGrid.from_ascii(PackedStringArray([
		"##.####", ".......", "##.....", "##....E", "#######"])))
	assert_true(sim.world.grid.is_walkable(POCKET), "the literal dot at x2 is a real yielding pocket")
	sim.rng.seed = 263
	sim.spawner = CustomerSpawner.new(sim.rng)
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	sim.menu = [preload("res://data/recipes/burger.tres")] as Array[RecipeDef]
	var guests: Array[CustomerAgent] = []
	var party: Party = null
	if count == 1:
		guests.append(sim.add_customer(Vector2i(0, 1), _rng(263)))
	else:
		party = sim.add_party(Vector2i(0, 1), [_rng(263), _rng(264)] as Array[RandomNumberGenerator])
		guests = PartySeating.members(party, sim.world)
	for index: int in guests.size():
		var cell: Vector2i = WAITER if index == 0 else Vector2i(2, 3)
		assert_true(sim.world.reset_agent_position(guests[index], cell))
		assert_true(guests[index].set_destination(sim.world.grid, cell))
	var employee: StaffAgent = StaffAgent.new(&"cleaner")
	employee.cell = Vector2i(1, 1)
	sim.world.add_agent(employee)
	assert_true(sim.world.movement.priority(sim.world, employee) > sim.world.movement.priority(sim.world, guests[0]))
	sim.start_day()
	if crossing:
		var task: SimTask = SimTask.new(&"cross", &"cleaner", "Cross the occupied waiting aisle")
		task.steps = [TaskStep.go_to_cell(CROSSING_GOAL), TaskStep.work(1, "finish crossing", _crossed)]
		sim.world.board.post(task, sim.world.now)
	assert_true(sim.world.clock.start_service())
	return {"sim": sim, "party": party, "guests": guests}


func _reach_yield(fixture: Dictionary, partial: bool) -> bool:
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var guest: CustomerAgent = (fixture["guests"] as Array[CustomerAgent])[0]
	for tick: int in WATCHDOG:
		if not _advance(sim):
			return false
		if sim.world.movement.is_yielding(guest.id) and not guest.has_arrived() \
				and (guest.move_progress > 0.0 if partial else guest.move_progress == 0.0):
			assert_eq(guest.cell, WAITER)
			assert_eq(guest.next_cell(), POCKET)
			return true
	fail("the ordinary crossing task did not create the requested genuine yield phase")
	return false


func _table(sim: RestaurantSim) -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"guest_contract_table"
	definition.category = ItemDef.Category.TABLE
	definition.seat_cells = [Vector2i.LEFT, Vector2i.RIGHT]
	return sim.world.grid.place_def(definition, Vector2i(4, 3))


func _assert_bookings(guests: Array[CustomerAgent], table: PlacedItem) -> void:
	assert_not_null(table)
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT)
		assert_eq(guest.table_item_id, table.id)
		assert_eq(table.reserved_by(guest.seat_cell), guest.id)
		assert_eq(guest.destination(), guest.seat_cell)


func _assert_physically_seated(sim: RestaurantSim, party: Party, guests: Array[CustomerAgent]) -> void:
	for tick: int in CustomerAgent.SEAT_WALK_LIMIT:
		if party.seated:
			break
		if not _advance(sim):
			return
	assert_true(party.seated, "both real guests reach booked seats before the existing seat-walk limit")
	for guest: CustomerAgent in guests:
		assert_eq(guest.cell, guest.seat_cell)
		assert_eq(guest.move_progress, 0.0)
		assert_eq(guest.state, CustomerAgent.State.ORDERING)
	assert_eq(sim.served_today, 0, "movement maintenance never pays a synthetic meal")
	assert_eq(sim.lost_today, 0)


func _edge(world: SimWorld, guest: CustomerAgent) -> Dictionary:
	for edge: Dictionary in world.movement.snapshot().edges:
		if edge.id == guest.id:
			return edge
	return {}


func _advance(sim: RestaurantSim) -> bool:
	var before: Dictionary = MovementInvariants.capture(sim.world)
	sim.advance()
	var problem: String = MovementInvariants.problem(sim.world, before)
	assert_eq(problem, "", "each ordinary service tick preserves physical ownership and traces")
	return problem.is_empty()


func _crossed(agent: SimAgent) -> bool:
	_crossed_cells.append(agent.cell)
	return agent.cell == CROSSING_GOAL and agent.move_progress == 0.0


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _finish_reserved_edge(sim: RestaurantSim, guest: CustomerAgent, origin: Vector2i, next: Vector2i) -> bool:
	for tick: int in 8:
		if not _advance(sim):
			return false
		if guest.cell != origin:
			assert_eq(guest.cell, next, "the old edge's vertex must be physically reached before the new seat journey")
			assert_eq(guest.move_progress, 0.0, "STOP completion does not also advance the new journey")
			assert_false(sim.world.movement.is_stopping(guest.id))
			assert_eq(guest.destination(), guest.seat_cell)
			return true
		assert_eq(guest.next_cell(), next)
		assert_true(sim.world.movement.is_stopping(guest.id))
	fail("the ordinary partial edge did not finish at its existing walking speed")
	return false


func test_lower_id_ordinary_party_tick_never_moves_higher_id_stop_before_its_slot() -> void:
	var fixture: Dictionary = _fixture(2, false)
	var sim: RestaurantSim = fixture["sim"] as RestaurantSim
	var party: Party = fixture["party"] as Party
	var guests: Array[CustomerAgent] = fixture["guests"] as Array[CustomerAgent]
	var lower: CustomerAgent = guests[0]
	var higher: CustomerAgent = guests[1]
	var bench: PlacedItem = sim.world.grid.place_def(
		preload("res://data/items/waiting_bench.tres"), Vector2i(4, 3))
	assert_not_null(bench)
	assert_true(lower.id < higher.id)
	var partial: bool = false
	var increment: float = 0.0
	for tick: int in 64:
		if not _advance(sim):
			return
		var delta: Vector2i = higher.next_cell() - higher.cell
		var length: float = GridMath.DIAGONAL_COST if delta.x != 0 and delta.y != 0 else 1.0
		increment = higher.move_speed / length
		if higher.waiting_item_id == bench.id and higher.move_progress > 0.0 \
				and higher.move_progress + increment < 1.0 \
				and not sim.world.movement.is_yielding(lower.id) \
				and not sim.world.movement.is_stopping(lower.id):
			partial = true
			break
	assert_true(partial, "the higher-ID member starts a real booked-bench edge at ordinary speed")
	if not partial:
		return
	# Public cancellation retains the real edge and the valid bench booking.
	higher.clear_path()
	assert_true(sim.world.movement.is_stopping(higher.id))
	assert_false(sim.world.movement.is_yielding(higher.id))
	var edge: Dictionary = _edge(sim.world, higher)
	var before_progress: float = higher.move_progress
	var before_wait: int = party.queue_wait
	var private_states: Array[int] = [lower.rng.state, higher.rng.state]
	if not _advance(sim):
		return
	assert_almost_eq(higher.move_progress, before_progress + increment, 0.00001,
		"the lower-ID queue controller cannot move a STOP actor before its own coordinator slot")
	assert_eq(_edge(sim.world, higher), edge)
	assert_eq(party.queue_wait, before_wait + 1, "the shared queue clock still advances once")
	assert_eq(party.last_queue_tick, sim.world.now)
	assert_eq(lower._queue_wait, party.queue_wait)
	assert_eq(higher._queue_wait, party.queue_wait)
	assert_eq([lower.rng.state, higher.rng.state] as Array[int], private_states)
	assert_eq(bench.reserved_by(higher.waiting_cell), higher.id)


func test_new_bench_booking_created_by_lower_leader_moves_higher_partial_guest_once() -> void:
	var sim: RestaurantSim = RestaurantSim.new()
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"#######", "E......", "##.....", "##E....", "#######"]))
	sim.world = SimWorld.new(grid)
	sim.rng.seed = 263
	sim.spawner = CustomerSpawner.new(sim.rng)
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	var party: Party = sim.add_party(Vector2i(0, 1), [_rng(263), _rng(264)] as Array[RandomNumberGenerator])
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	var lower: CustomerAgent = guests[0]
	var higher: CustomerAgent = guests[1]
	# A small explicit geometry fixture: the higher-ID entrant has a genuine
	# ENTRY-to-FLOOR approach while the admitted leader already waits inside.
	assert_true(sim.world.reset_agent_position(lower, Vector2i(2, 1)))
	assert_true(sim.world.reset_agent_position(higher, Vector2i(2, 3)))
	sim.start_day()
	assert_true(sim.world.clock.start_service())
	if not _advance(sim):
		return
	assert_eq(higher.state, CustomerAgent.State.QUEUED)
	assert_eq(higher.cell, Vector2i(2, 3))
	assert_eq(higher.next_cell(), Vector2i(2, 2))
	assert_eq(higher.move_progress, 0.25)
	assert_eq(higher.waiting_item_id, 0)
	assert_false(sim.world.movement.is_stopping(higher.id))
	assert_false(sim.world.movement.is_yielding(lower.id))
	# Ordinary availability, no prior reservation/map/pose or state fabrication.
	var bench: PlacedItem = grid.place_def(preload("res://data/items/waiting_bench.tres"), Vector2i(4, 3))
	assert_not_null(bench)
	var edge: Dictionary = _edge(sim.world, higher)
	var before_progress: float = higher.move_progress
	var before_wait: int = party.queue_wait
	if not _advance(sim):
		return
	assert_eq(higher.waiting_item_id, bench.id, "the leader's ordinary queue decision finds the newly available bench")
	assert_true(sim.world.movement.is_stopping(higher.id), "the real NEW bench goal hands off the already partial edge")
	assert_almost_eq(higher.move_progress, before_progress + higher.move_speed, 0.00001,
		"a STOP created inside _queue_inside moves once in its own coordinator slot")
	assert_eq(_edge(sim.world, higher), edge)
	assert_eq(higher.cell, Vector2i(2, 3))
	assert_eq(higher.next_cell(), Vector2i(2, 2))
	assert_eq(party.queue_wait, before_wait + 1)
	assert_eq(higher._queue_wait, party.queue_wait)
	assert_eq(lower._queue_wait, party.queue_wait)
	assert_eq(bench.reserved_by(higher.waiting_cell), higher.id)
