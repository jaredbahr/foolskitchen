extends TestCase
## Safety and bounded liveness over real current/next occupancy and timed edges.
## No historical outcomes or existing golden assertions are changed here.

const TRAITS: StaffCatalogue = preload("res://data/staff/traits.tres")
const WATCHDOG: int = 512

var _previous: Dictionary[int, Dictionary] = {}
var _worked_cells: Array[Vector2i] = []


class Walker extends SimAgent:
	var tick_count: int = 0
	func tick(world: SimWorld) -> void:
		tick_count += 1
		step_move(world)


class StaffWalker extends StaffAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


class GuestWalker extends CustomerAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


class CountedCourier extends CourierAgent:
	var tick_count: int = 0

	func tick(world: SimWorld) -> void:
		tick_count += 1
		super.tick(world)


class TraceWalker extends Walker:
	var injected_trace: Dictionary = {}

	func movement_trace() -> Dictionary:
		return super.movement_trace() if injected_trace.is_empty() else injected_trace.duplicate(true)


class MissingSweep extends MovementCoordinator:
	var omitted: Vector2i = SimGrid.NO_CELL
	var wrong_edge: bool = false

	func snapshot() -> Dictionary:
		var result: Dictionary = super.snapshot()
		result.next.erase(omitted)
		if wrong_edge and not result.edges.is_empty():
			result.edges[0]["from"] = Vector2i(99, 99)
		return result


func after_each() -> void:
	GameState.new_run(1)


func test_stationary_person_keeps_cell_while_another_walks_around() -> void:
	var world: SimWorld = _world(["....", "...."])
	var standing: SimAgent = SimAgent.new()
	standing.cell = Vector2i(1, 0)
	world.add_agent(standing)
	var walking: Walker = _walker(world, Vector2i(0, 0), Vector2i(3, 0))
	for tick: int in WATCHDOG:
		_advance(world)
		if not _safe(world):
			return
		assert_eq(standing.cell, Vector2i(1, 0))
		if walking.cell == Vector2i(3, 0):
			break
	assert_eq(walking.cell, Vector2i(3, 0), "a free detour reaches the actual goal")


func test_partial_edge_holds_current_and_next_and_snapshot_is_detached() -> void:
	var world: SimWorld = _world(["..."])
	var first: Walker = _walker(world, Vector2i(0, 0), Vector2i(1, 0))
	var second: Walker = _walker(world, Vector2i(2, 0), Vector2i(1, 0))
	_advance(world)
	assert_true(_safe(world))
	assert_true(first.move_progress > 0.0)
	assert_eq(first.cell, Vector2i(0, 0), "fractional movement has not vacated the start")
	assert_eq(second.move_progress, 0.0)
	var snapshot: Dictionary = world.movement.snapshot()
	assert_eq(snapshot.occupied[first.cell], first.id)
	assert_eq(snapshot.next[Vector2i(1, 0)], first.id)
	snapshot.occupied.clear()
	snapshot.next.clear()
	snapshot.edges.clear()
	snapshot.pending.clear()
	assert_eq(world.movement.snapshot().occupied.size(), 2)
	assert_eq(world.movement.snapshot().next.get(Vector2i(1, 0)), first.id)
	first.clear_path()
	assert_eq(world.movement.snapshot().next.get(Vector2i(1, 0)), first.id,
		"mid-edge cancellation retains its physical claim until the vertex")
	for tick: int in 3:
		_advance(world)
		if not _safe(world):
			return
	assert_eq(first.cell, Vector2i(1, 0))
	world.remove_agent(first)
	_advance(world)
	assert_true(_safe(world))
	assert_eq(world.movement.snapshot().next.get(Vector2i(1, 0)), second.id,
		"another person can acquire the cleared claim")


func test_head_on_lower_id_tie_yields_into_the_free_pocket_and_both_finish() -> void:
	var world: SimWorld = _world(["##.##", "....."])
	var higher: StaffWalker = _staff(world, Vector2i(1, 1), Vector2i(4, 1))
	var lower: StaffWalker = _staff(world, Vector2i(2, 1), Vector2i(0, 1))
	assert_true(higher.id < lower.id)
	assert_eq(world.movement.priority(world, higher), world.movement.priority(world, lower))
	_assert_passing(world, higher, lower, Vector2i(2, 0), Vector2i(4, 1), Vector2i(0, 1))


func test_food_carrying_beats_lower_id_empty_staff_in_a_head_on_encounter() -> void:
	var world: SimWorld = _world(["##.##", "....."])
	var empty: StaffWalker = _staff(world, Vector2i(2, 1), Vector2i(0, 1))
	var carrying: StaffWalker = _staff(world, Vector2i(1, 1), Vector2i(4, 1))
	var delivery: SimTask = _claimed_delivery(world, carrying)
	delivery.payload = {"pass_id": 123, "carried_count": 1}
	carrying.step_index = 2
	assert_true(empty.id < carrying.id)
	assert_eq(world.movement.priority(world, carrying), 3)
	assert_eq(world.movement.priority(world, empty), 2)
	_assert_passing(world, carrying, empty, Vector2i(2, 0), Vector2i(4, 1), Vector2i(0, 1))


func test_pre_pickup_cancelled_or_reclaimed_delivery_does_not_get_food_priority() -> void:
	var world: SimWorld = _world(["...."])
	var staff: StaffWalker = _staff(world, Vector2i(0, 0), Vector2i(3, 0))
	var delivery: SimTask = _claimed_delivery(world, staff)
	delivery.payload = {"pass_id": 123, "carried_count": 1}
	staff.step_index = 1
	assert_eq(world.movement.priority(world, staff), 2, "a claimed pass is not a picked-up plate")
	staff.step_index = 2
	assert_eq(world.movement.priority(world, staff), 3)
	delivery.payload["carried_count"] = 0
	assert_eq(world.movement.priority(world, staff), 2)
	delivery.payload["carried_count"] = 1
	world.board.cancel(delivery, &"test_cancel")
	assert_eq(world.movement.priority(world, staff), 2, "a cancelled stale task cannot win food priority")
	var reclaimed: SimTask = _claimed_delivery(world, staff)
	reclaimed.payload = {"pass_id": 123, "carried_count": 1}
	staff.step_index = 0
	assert_eq(world.movement.priority(world, staff), 2)


func test_staff_beats_an_earlier_guest_in_the_solvable_pocket() -> void:
	var world: SimWorld = _world(["##.##", "....."])
	var guest: Walker = _walker(world, Vector2i(2, 1), Vector2i(0, 1))
	guest.role = &"customer"
	var staff: StaffWalker = _staff(world, Vector2i(1, 1), Vector2i(4, 1))
	assert_true(guest.id < staff.id)
	assert_eq(world.movement.priority(world, guest), 1)
	assert_eq(world.movement.priority(world, staff), 2)
	_assert_passing(world, staff, guest, Vector2i(2, 0), Vector2i(4, 1), Vector2i(0, 1))


func test_occupied_side_pocket_is_never_used_and_release_restores_liveness() -> void:
	var world: SimWorld = _world(["##.##", "....."])
	var higher: StaffWalker = _staff(world, Vector2i(1, 1), Vector2i(4, 1))
	var lower: StaffWalker = _staff(world, Vector2i(2, 1), Vector2i(0, 1))
	var blocker: SimAgent = SimAgent.new()
	blocker.cell = Vector2i(2, 0)
	world.add_agent(blocker)
	var end_blocker: SimAgent = SimAgent.new()
	end_blocker.cell = Vector2i(3, 1)
	world.add_agent(end_blocker)
	for tick: int in 80:
		_advance(world)
		if not _safe(world):
			return
		assert_eq(blocker.cell, Vector2i(2, 0))
	world.remove_agent(blocker)
	world.remove_agent(end_blocker)
	_assert_passing(world, higher, lower, Vector2i(2, 0), Vector2i(4, 1), Vector2i(0, 1))


func test_enclosed_head_on_stays_safe_without_claiming_impossible_progress() -> void:
	var world: SimWorld = _world(["....."])
	var a: StaffWalker = _staff(world, Vector2i(1, 0), Vector2i(4, 0))
	var b: StaffWalker = _staff(world, Vector2i(2, 0), Vector2i(0, 0))
	for tick: int in 160:
		_advance(world)
		if not _safe(world):
			return
	assert_false(a.cell == Vector2i(4, 0) and b.cell == Vector2i(0, 0),
		"a one-cell corridor has no passing space; an event is not successful passage")


func test_three_and_four_person_cycles_resolve_to_goals_with_spare_space() -> void:
	for count: int in [3, 4]:
		var world: SimWorld = _world(["....", "....", "....", "...."])
		var cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2)]
		var agents: Array[Walker] = []
		var goals: Array[Vector2i] = []
		for index: int in count:
			var goal: Vector2i = cells[(index + 1) % count]
			agents.append(_walker(world, cells[index], goal))
			goals.append(goal)
		for tick: int in WATCHDOG:
			_advance(world)
			if not _safe(world):
				return
			var done: bool = true
			for index: int in count:
				done = done and agents[index].cell == goals[index]
			if done:
				break
		for index: int in count:
			assert_eq(agents[index].cell, goals[index], "%d-person cycle reaches actual goals" % count)


func test_diagonal_crossing_and_solid_corner_never_cut_through() -> void:
	var world: SimWorld = _world(["....", "....", "...."])
	var a: Walker = _walker(world, Vector2i(0, 0), Vector2i(1, 1))
	var b: Walker = _walker(world, Vector2i(1, 0), Vector2i(0, 1))
	for tick: int in WATCHDOG:
		_advance(world)
		if not _safe(world):
			return
		if a.has_arrived() and b.has_arrived():
			break
	assert_eq(a.cell, Vector2i(1, 1))
	assert_eq(b.cell, Vector2i(0, 1))
	var corner: SimWorld = _world(["...", "...", "..."])
	assert_not_null(corner.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, true))
	var walker: Walker = _walker(corner, Vector2i(0, 0), Vector2i(2, 2))
	var route: Array[Vector2i] = corner.movement.route(corner, walker, walker.cell, Vector2i(2, 2))
	assert_false(route.is_empty())
	for index: int in range(1, route.size()):
		assert_true(corner.grid.step_open(route[index - 1], route[index]))
		assert_true(corner.grid.is_walkable(route[index]))
		if route[index] - route[index - 1] == Vector2i.ONE:
			assert_true(corner.grid.is_walkable(route[index - 1] + Vector2i.RIGHT))
			assert_true(corner.grid.is_walkable(route[index - 1] + Vector2i.DOWN))


func test_seat_and_bench_permissions_belong_only_to_the_reserved_guest() -> void:
	for kind: StringName in [&"table", &"bench"]:
		var world: SimWorld = _world([".....", ".....", "....."])
		var item: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(2, 1), 0, false,
			[] as Array[Vector2i], [Vector2i.ZERO] as Array[Vector2i])
		assert_not_null(item)
		var restaurant: RestaurantSim = RestaurantSim.new()
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 263
		var guest: GuestWalker = GuestWalker.new(restaurant, random)
		guest.cell = Vector2i(0, 1)
		world.add_agent(guest)
		if kind == &"table":
			guest.table_item_id = item.id
			guest.seat_cell = Vector2i(2, 1)
		else:
			guest.waiting_item_id = item.id
			guest.waiting_cell = Vector2i(2, 1)
		assert_true(item.reserve(Vector2i(2, 1), guest.id))
		var stranger: Walker = _walker(world, Vector2i(4, 1), Vector2i(0, 1))
		assert_true(world.movement.can_enter(world, guest, Vector2i(2, 1)))
		assert_false(world.movement.can_enter(world, stranger, Vector2i(2, 1)))
		var route: Array[Vector2i] = world.movement.route(world, stranger, stranger.cell, Vector2i(0, 1))
		assert_false(route.is_empty())
		assert_false(route.has(Vector2i(2, 1)), "stranger routes around the reserved " + String(kind))
		item.release_all(guest.id)
		assert_false(world.movement.can_enter(world, stranger, Vector2i(2, 1)),
			"an empty furniture seat is still not a public aisle")


func test_flat_floor_decor_remains_walkable() -> void:
	var world: SimWorld = _world(["..."])
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_flat_rug"
	definition.placement_layer = ItemDef.PlacementLayer.FLOOR_DECOR
	definition.solid = false
	definition.footprint = Vector2i.ONE
	definition.work_cells = []
	definition.seat_cells = []
	assert_not_null(world.grid.place_def(definition, Vector2i(1, 0)))
	var walker: Walker = _walker(world, Vector2i.ZERO, Vector2i(2, 0))
	assert_true(world.movement.can_enter(world, walker, Vector2i(1, 0)))
	for tick: int in 12:
		_advance(world)
		if not _safe(world):
			return
	assert_eq(walker.cell, Vector2i(2, 0))


func test_quick_checks_intermediate_edges_and_retains_their_timed_trace() -> void:
	var world: SimWorld = _world([".".repeat(20)])
	var quick: StaffWalker = _staff(world, Vector2i.ZERO, Vector2i(19, 0), true)
	quick.move_speed = quick.movement_multiplier() # Stress multiple edges with the real Quick multiplier.
	var saw_intermediate: bool = false
	for tick: int in 16:
		_advance(world)
		if not _safe(world):
			return
		var trace: Dictionary = quick.movement_trace()
		assert_false(trace.discontinuous)
		if trace.points.size() > 2:
			saw_intermediate = true
	assert_true(saw_intermediate, "completed intermediate centres survive for collision/render inspection")
	var blocked: SimWorld = _world([".".repeat(20)])
	var standing: StaffWalker = StaffWalker.new(&"server", 3)
	standing.cell = Vector2i(8, 0)
	blocked.add_agent(standing)
	var fast: StaffWalker = _staff(blocked, Vector2i.ZERO, Vector2i(19, 0), true)
	fast.move_speed = fast.movement_multiplier()
	for tick: int in 20:
		_advance(blocked)
		if not _safe(blocked):
			return
		assert_true(fast.cell.x < 8, "the intermediate held cell is never skipped")
		assert_eq(standing.cell, Vector2i(8, 0))


func test_courier_pending_admission_and_removal_preserve_identity_without_ticks() -> void:
	var world: SimWorld = _world([".."])
	var route: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]
	var first: CountedCourier = CountedCourier.new(route, 1)
	var second: CountedCourier = CountedCourier.new(route, 1)
	world.add_agent(first)
	world.add_agent(second)
	assert_eq(world.agents.size(), 1)
	assert_eq(world.pending_agents(), [second] as Array[SimAgent])
	assert_null(world.agent(second.id))
	assert_eq(world.pending_agent(second.id), second)
	_advance(world)
	assert_true(_safe(world))
	assert_eq(second.tick_count, 0, "pending is not active service or invisible walking")
	assert_eq(second.cell, route[0])
	assert_false(second.dropped)
	var remembered_id: int = second.id
	world.remove_agent(first)
	_advance(world)
	assert_true(_safe(world))
	assert_eq(world.agent(remembered_id), second)
	assert_true(world.pending_agents().is_empty())
	for claim: Variant in world.movement.snapshot().next.values():
		assert_ne(claim, first.id)
	for tick: int in 120:
		_advance(world)
		if not _safe(world):
			return
		if second.state == CourierAgent.State.GONE:
			break
	assert_eq(second.state, CourierAgent.State.GONE)
	assert_true(second.dropped and second.all_dropped)
	world.remove_agent(second)
	assert_true(world.agents.is_empty() and world.pending_agents().is_empty())
	assert_true(world.movement.snapshot().occupied.is_empty())
	assert_true(world.movement.snapshot().next.is_empty())
	var removed_pending: CountedCourier = CountedCourier.new(route, 1)
	var held: CountedCourier = CountedCourier.new(route, 1)
	world.add_agent(held)
	world.add_agent(removed_pending)
	world.remove_agent(removed_pending)
	assert_null(world.pending_agent(removed_pending.id))
	assert_eq(removed_pending.tick_count, 0)


func test_movement_inspection_and_resolution_do_not_create_or_draw_random_streams() -> void:
	GameState.new_run(263)
	GameState.rng(&"customers")
	GameState.rng(&"reviews")
	var before: Dictionary = GameState.call("_capture_save")
	var world: SimWorld = _world(["##.##", "....."])
	var a: StaffWalker = _staff(world, Vector2i(1, 1), Vector2i(4, 1))
	var b: StaffWalker = _staff(world, Vector2i(2, 1), Vector2i(0, 1))
	for tick: int in WATCHDOG:
		_advance(world)
		if not _safe(world):
			return
		world.movement.route(world, a, a.cell, Vector2i(4, 1))
		world.movement.priority(world, b)
	assert_eq(GameState.call("_capture_save"), before,
		"all existing named streams and their exact signed states remain unchanged")
	GameState.new_run(1)


func test_pending_party_keeps_every_member_and_no_queue_budget_until_admission_or_close() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, 263, errors, null, false)
	assert_eq(errors, [] as Array[String])
	var entry: Vector2i = sim.world.grid.entries()[0]
	var holding: SimAgent = SimAgent.new()
	holding.cell = entry
	sim.world.add_agent(holding)
	assert_true(sim.world.clock.start_service())
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	sim.spawner.reset()
	var randoms: Array[RandomNumberGenerator] = []
	for seed_value: int in [1, 2]:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed_value
		randoms.append(random)
	var party: Party = sim.add_party(entry, randoms)
	assert_not_null(party)
	assert_eq(sim.customers().size(), 2)
	assert_eq(sim.world.pending_agents().size(), 2)
	for tick: int in 20:
		_advance_sim(sim)
		if not _safe(sim.world):
			return
	assert_eq(party.queue_wait, 0, "not-yet-admitted members do not consume the party's queue budget")
	assert_false(party.departing)
	for id: int in party.member_ids:
		var guest: CustomerAgent = sim.world.pending_agent(id) as CustomerAgent
		assert_not_null(guest, "each pending member retains identity")
		if guest != null:
			assert_eq(guest.state, CustomerAgent.State.ARRIVING)
			assert_eq(guest.cell, entry)
	assert_eq(sim.lost_today, 0)
	sim.world.clock.open_ticks = sim.world.clock.phase_tick + 1
	sim.world.clock.last_orders_max_ticks = 1
	_advance_sim(sim)
	_advance_sim(sim)
	assert_eq(sim.world.clock.phase, SimClock.Phase.CLOSED)
	assert_true(sim.customers().is_empty())
	assert_true(sim.world.pending_agents().is_empty())
	assert_eq(sim.lost_today, 2, "closing settles both real pending visits once; neither is hidden or discarded")
	assert_eq(sim.leave_reasons_today.get(&"closing", 0), 2)


func test_mid_edge_clear_and_repath_finish_the_reserved_edge_before_any_actor_work() -> void:
	var world: SimWorld = _world([".....", "....."])
	var walker: Walker = _walker(world, Vector2i.ZERO, Vector2i(4, 0))
	_advance(world)
	assert_true(_safe(world))
	var position: Vector3 = GridMath.cell_to_world(walker.cell).lerp(
		GridMath.cell_to_world(walker.next_cell()), walker.move_progress)
	var calls: int = walker.tick_count
	walker.clear_path()
	assert_almost_eq(walker.move_progress, 0.25)
	assert_eq(walker.next_cell(), Vector2i(1, 0))
	assert_true(world.movement.snapshot().stopping.has(walker.id))
	assert_true(walker.set_destination(world.grid, Vector2i(0, 1)))
	assert_true(position.is_equal_approx(GridMath.cell_to_world(walker.cell).lerp(
		GridMath.cell_to_world(walker.next_cell()), walker.move_progress)), "no cancellation snap or reverse")
	for tick: int in 3:
		_advance(world)
		if not _safe(world):
			return
		assert_eq(walker.tick_count, calls, "stopping consumes travel ticks without actor/productive work")
	assert_eq(walker.cell, Vector2i(1, 0))
	assert_eq(walker.move_progress, 0.0)
	for tick: int in 64:
		_advance(world)
		if not _safe(world):
			return
		if walker.cell == Vector2i(0, 1):
			break
	assert_true(walker.tick_count > calls)
	assert_eq(walker.cell, Vector2i(0, 1), "the deferred route begins after the reserved edge finishes")


func test_courier_routes_around_empty_and_foreign_seats_via_real_outdoor_pockets() -> void:
	for reserved: bool in [false, true]:
		var world: SimWorld = _world(["..."])
		var seat: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, false,
			[] as Array[Vector2i], [Vector2i.ZERO] as Array[Vector2i])
		if reserved:
			assert_true(seat.reserve(Vector2i(1, 0), 999))
		var route: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
		var courier: CountedCourier = CountedCourier.new(route, 1)
		world.add_agent(courier)
		assert_false(world.movement.can_enter(world, courier, Vector2i(1, 0)))
		assert_true(world.movement.can_enter(world, courier, Vector2i(0, -1)), "outdoor yielding pocket is legal")
		var alternate: Array[Vector2i] = world.movement.route(world, courier, courier.cell, Vector2i(2, 0))
		assert_false(alternate.is_empty())
		assert_false(alternate.has(Vector2i(1, 0)))
		courier.install_movement_route(alternate)
		var pocket_used: bool = false
		for tick: int in 128:
			_advance(world)
			if not _safe(world):
				return
			pocket_used = pocket_used or courier.cell.y == -1
			if courier.state == CourierAgent.State.UNLOADING:
				break
		assert_eq(courier.state, CourierAgent.State.UNLOADING)
		assert_true(pocket_used, "the actual courier walked the legal outdoor detour")


func test_oracle_rejects_bad_actual_segments_even_with_empty_remaining_path() -> void:
	for bad_corner: bool in [false, true]:
		var world: SimWorld = _world(["....", "....", "...."])
		var walker: TraceWalker = TraceWalker.new()
		walker.cell = Vector2i.ZERO
		world.add_agent(walker)
		var before: Dictionary = MovementInvariants.capture(world)
		var finish: Vector2i = Vector2i(1, 1) if bad_corner else Vector2i(2, 0)
		if bad_corner:
			assert_not_null(world.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, true))
		assert_true(world.reset_agent_position(walker, finish))
		world.now += 1 # Deliberately malformed observed history, not a simulated move.
		walker.injected_trace = _injected(world.now, [GridMath.cell_to_world(Vector2i.ZERO),
			GridMath.cell_to_world(finish)], [0.0, 1.0])
		var invalid: String = MovementInvariants.problem(world, before)
		assert_true(invalid.contains("solid") if bad_corner else invalid.contains("centre"),
			"the oracle rejects the actual illegal segment, not merely future routes")


func test_oracle_rejects_current_and_completed_empty_or_foreign_seat_use() -> void:
	for reserved: bool in [false, true]:
		var world: SimWorld = _world(["..."])
		var seat: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, false,
			[] as Array[Vector2i], [Vector2i.ZERO] as Array[Vector2i])
		if reserved:
			assert_true(seat.reserve(Vector2i(1, 0), 999))
		var walker: TraceWalker = TraceWalker.new()
		walker.cell = Vector2i.ZERO
		world.add_agent(walker)
		var before: Dictionary = MovementInvariants.capture(world)
		assert_true(world.reset_agent_position(walker, Vector2i(2, 0)))
		world.now += 1
		walker.injected_trace = _injected(world.now, [GridMath.cell_to_world(Vector2i.ZERO),
			GridMath.cell_to_world(Vector2i(1, 0)), GridMath.cell_to_world(Vector2i(2, 0))], [0.0, 0.5, 1.0])
		assert_true(MovementInvariants.problem(world, before).contains("seat"), "completed foreign/empty seat edge rejected")
		walker.cell = Vector2i(1, 0)
		assert_true(MovementInvariants.problem(world, before).contains("current cell"), "current seat cannot hide behind a legal future path")


func test_oracle_reconstructs_completed_source_claims_and_rejects_blanket_discontinuity() -> void:
	var world: SimWorld = _world(["..."])
	var coordinator: MissingSweep = MissingSweep.new()
	world.movement = coordinator
	var walker: TraceWalker = TraceWalker.new()
	walker.cell = Vector2i.ZERO
	walker.move_speed = 1.0
	world.add_agent(walker)
	assert_true(walker.set_destination(world.grid, Vector2i(1, 0)))
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	assert_eq(MovementInvariants.problem(world, before), "", "the uncorrupted actual fixture is valid")
	coordinator.omitted = Vector2i.ZERO
	assert_true(MovementInvariants.problem(world, before).contains("claim"), "finished edge source cannot silently disappear")
	coordinator.omitted = SimGrid.NO_CELL
	walker.injected_trace = walker.movement_trace()
	walker.injected_trace["discontinuous"] = true
	walker.injected_trace["discontinuity_cause"] = "admission"
	assert_true(MovementInvariants.problem(world, before).contains("discontinuity"), "an existing active actor cannot claim a new birth")
	var crossing_a: Dictionary = _injected(1, [Vector3.ZERO, Vector3(1, 0, 1)], [0.0, 1.0])
	var crossing_b: Dictionary = _injected(1, [Vector3(1, 0, 0), Vector3(0, 0, 1)], [0.0, 1.0])
	crossing_a["discontinuous"] = true
	assert_true(MovementInvariants._traces_touch(crossing_a, crossing_b), "a flag never removes a person from pair geometry")


func test_prior_seat_permission_is_only_the_first_departure_source_not_a_return_or_corner() -> void:
	for corner: bool in [false, true]:
		var world: SimWorld = _world(["....", "....", "....", "...."])
		var seat_cell: Vector2i = Vector2i(1, 1)
		var seat: PlacedItem = world.grid.place(Vector2i.ONE, seat_cell, 0, false,
			[] as Array[Vector2i], [Vector2i.ZERO] as Array[Vector2i])
		assert_true(seat.reserve(seat_cell, 1))
		var walker: TraceWalker = TraceWalker.new()
		walker.cell = seat_cell
		world.add_agent(walker)
		var before: Dictionary = MovementInvariants.capture(world)
		assert_eq(walker.id, 1)
		seat.release_all(walker.id)
		var finish: Vector2i = Vector2i(1, 2)
		assert_true(world.reset_agent_position(walker, finish))
		world.now += 1
		var points: Array[Vector3] = [GridMath.cell_to_world(seat_cell), GridMath.cell_to_world(Vector2i(2, 1))]
		if not corner:
			points.append(GridMath.cell_to_world(seat_cell))
		points.append(GridMath.cell_to_world(finish))
		var times: Array[float] = []
		times.assign([0.0, 0.5, 1.0] if corner else [0.0, 0.3, 0.6, 1.0])
		walker.injected_trace = _injected(world.now, points, times)
		assert_true(MovementInvariants._actual_segments(world, walker, before).error.contains("seat"),
			"a later target/revisit or diagonal corner cannot reuse old source ownership")
		walker.cell = Vector2i(2, 1)
		walker.injected_trace = _injected(world.now, [GridMath.cell_to_world(seat_cell),
			GridMath.cell_to_world(walker.cell)], [0.0, 1.0])
		assert_eq(MovementInvariants._actual_segments(world, walker, before).error, "",
			"the actual first departure source remains justified by observed prior ownership")


func test_oracle_requires_the_exact_actual_partial_edge_even_with_correct_cell_claims() -> void:
	var world: SimWorld = _world(["..."])
	var coordinator: MissingSweep = MissingSweep.new()
	world.movement = coordinator
	_walker(world, Vector2i.ZERO, Vector2i(2, 0))
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	assert_eq(MovementInvariants.problem(world, before), "")
	coordinator.wrong_edge = true
	assert_true(MovementInvariants.problem(world, before).contains("edge record"),
		"correct occupied/next maps cannot conceal a fabricated partial edge")


func test_near_one_fraction_duplicate_centre_can_complete_then_turn_without_false_clipping() -> void:
	var world: SimWorld = _world(["....", "....", "...."])
	var quick: StaffWalker = _staff(world, Vector2i.ZERO, Vector2i(3, 1), true)
	quick.move_speed = quick.movement_multiplier()
	quick.install_movement_route([Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
	assert_true(world.movement.try_step(world, quick, Vector2i(1, 0)))
	quick.move_progress = 1.0 - 0.00000001
	var before: Dictionary = MovementInvariants.capture(world)
	assert_true((before.active[quick.id].position as Vector3).is_equal_approx(GridMath.cell_to_world(Vector2i(1, 0))))
	world.advance()
	var trace: Dictionary = quick.movement_trace()
	assert_true(trace.points.size() >= 4)
	assert_true((trace.points[0] as Vector3).is_equal_approx(trace.points[1]),
		"the scalar completion records a centre already rounded in Vector3")
	assert_eq(quick.cell, Vector2i(1, 1))
	assert_eq(MovementInvariants.problem(world, before), "", "real completion evidence allows the subsequent legal turn")


func test_linked_bench_and_chair_projected_seats_use_one_physical_table_lease() -> void:
	for width: int in [1, 2]:
		var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
		var table_def: ItemDef = _dining_definition(ItemDef.Category.TABLE, Vector2i(2, 1))
		var furnishing_def: ItemDef = _dining_definition(ItemDef.Category.CHAIR, Vector2i(width, 1))
		furnishing_def.seat_cells.assign([Vector2i.ZERO] if width == 1 else [Vector2i.ZERO, Vector2i.RIGHT])
		var table: PlacedItem = grid.place_def(table_def, Vector2i(3, 3))
		var furnishing: PlacedItem = grid.place_def(furnishing_def, Vector2i(3, 4))
		var world: SimWorld = SimWorld.new(grid)
		var walker: Walker = _walker(world, Vector2i(1, 4), Vector2i(2, 4))
		var seat: Vector2i = furnishing.origin
		assert_eq(grid.dining_table_id(seat), table.id)
		assert_eq(grid.dining_furnishing_id(seat), furnishing.id)
		assert_true(table.reserve(seat, walker.id))
		assert_eq(furnishing.reserved_by(seat), -1)
		assert_eq(MovementInvariants._cell_problem(world, walker, seat), "",
			"an unreserved projection does not erase the table's actual lease")
		assert_true(furnishing.reserve(seat, 999))
		assert_true(MovementInvariants._cell_problem(world, walker, seat).contains("foreign"),
			"any conflicting foreign physical hold still rejects")


func test_real_staff_repath_mid_edge_cannot_start_work_before_the_ultimate_goal() -> void:
	var world: SimWorld = _world([".....", "....."])
	var staff: StaffAgent = StaffAgent.new(&"cook", 3)
	staff.cell = Vector2i.ZERO
	world.add_agent(staff)
	var goal: Vector2i = Vector2i(4, 0)
	var task: SimTask = SimTask.new(&"movement_work", &"cook", "Walk then work")
	task.steps = [TaskStep.go_to_cell(goal), TaskStep.work(2, "Work only at goal", _on_real_work)]
	world.board.post(task, world.now)
	for tick: int in 8:
		_advance(world)
		if not _safe(world):
			return
		if staff.move_progress == 0.75:
			break
	assert_eq(staff.move_progress, 0.75)
	staff.needs_repath = true
	_advance(world) # Stop is created inside the real StaffAgent._walk call.
	assert_true(_safe(world))
	assert_eq(staff.cell, Vector2i(1, 0))
	assert_eq(staff.step_index, 0, "finishing the truncated edge is not ultimate GO_TO_CELL arrival")
	assert_eq(staff.work_left, 0.0)
	assert_true(_worked_cells.is_empty())
	for tick: int in 128:
		_advance(world)
		if not _safe(world):
			return
		if staff.cell != goal:
			assert_eq(staff.step_index, 0)
			assert_eq(staff.work_left, 0.0)
			assert_true(_worked_cells.is_empty())
		if task.state == SimTask.State.DONE:
			break
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(_worked_cells, [goal] as Array[Vector2i], "the real work callback fires once at the actual goal")


func test_real_customer_repath_mid_edge_cannot_leave_or_be_removed_before_the_exit() -> void:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = _world(["....E"])
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 263
	sim.spawner = CustomerSpawner.new(random)
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	sim.spawner.reset()
	assert_true(sim.world.clock.start_service())
	var private_random: RandomNumberGenerator = RandomNumberGenerator.new()
	private_random.seed = 263
	var guest: CustomerAgent = CustomerAgent.new(sim, private_random)
	guest.cell = Vector2i.ZERO
	guest.state = CustomerAgent.State.LEAVING
	sim.world.add_agent(guest)
	for tick: int in 3:
		_advance_sim(sim)
		if not _safe(sim.world):
			return
	assert_eq(guest.move_progress, 0.75)
	guest.needs_repath = true
	_advance_sim(sim) # Uses real exit routing and RestaurantSim departure cleanup.
	assert_true(_safe(sim.world))
	assert_eq(guest.cell, Vector2i(1, 0))
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	assert_eq(sim.world.agent(guest.id), guest, "the real visit remains active before reaching the door")
	assert_eq(sim.lost_today, 0)
	for tick: int in 128:
		_advance_sim(sim)
		if not _safe(sim.world):
			return
		if sim.world.agent(guest.id) == null:
			break
		assert_eq(guest.state, CustomerAgent.State.LEAVING)
	assert_eq(guest.cell, Vector2i(4, 0))
	assert_eq(guest.state, CustomerAgent.State.LEFT)
	assert_null(sim.world.agent(guest.id))
	assert_eq(sim.lost_today, 1)
	sim.record_departure(guest)
	assert_eq(sim.lost_today, 1, "the actual exit is recorded once")


func _on_real_work(agent: SimAgent) -> bool:
	_worked_cells.append(agent.cell)
	return true


func _dining_definition(category: ItemDef.Category, footprint: Vector2i) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_linked_furniture"
	definition.category = category
	definition.footprint = footprint
	definition.solid = category == ItemDef.Category.TABLE
	return definition


func _injected(tick: int, points: Array[Vector3], times: Array[float]) -> Dictionary:
	return {"tick": tick, "points": points, "times": times, "discontinuous": false, "discontinuity_cause": ""}


func _world(rows: Array[String]) -> SimWorld:
	return SimWorld.new(SimGrid.from_ascii(PackedStringArray(rows)))


func _walker(world: SimWorld, at: Vector2i, goal: Vector2i) -> Walker:
	var agent: Walker = Walker.new()
	agent.cell = at
	world.add_agent(agent)
	assert_true(agent.set_destination(world.grid, goal))
	return agent


func _staff(world: SimWorld, at: Vector2i, goal: Vector2i, quick: bool = false) -> StaffWalker:
	var agent: StaffWalker = StaffWalker.new(&"server", 3)
	if quick:
		var member: StaffMember = StaffMember.new()
		member.role = &"server"
		member.trait_id = &"quick"
		agent.configure_member(member, TRAITS.find_trait(&"quick"))
	agent.cell = at
	world.add_agent(agent)
	assert_true(agent.set_destination(world.grid, goal))
	return agent


func _claimed_delivery(world: SimWorld, agent: StaffAgent) -> SimTask:
	var task: SimTask = SimTask.new(&"deliver", &"server", "Test delivery")
	world.board.post(task, world.now)
	assert_true(world.board.claim(task, agent.id, world.now))
	agent.task = task
	return task


func _safe(world: SimWorld) -> bool:
	var problem: String = MovementInvariants.problem(world, _previous.get(world.get_instance_id(), {}))
	if not problem.is_empty():
		fail("tick %d: %s" % [world.now, problem])
		return false
	return true


func _assert_passing(world: SimWorld, higher: SimAgent, lower: SimAgent, pocket: Vector2i,
		higher_goal: Vector2i, lower_goal: Vector2i) -> void:
	var yielded: bool = false
	for tick: int in WATCHDOG:
		_advance(world)
		if not _safe(world):
			return
		yielded = yielded or lower.cell == pocket
		if higher.cell == higher_goal and lower.cell == lower_goal:
			break
	assert_true(yielded, "the lower-priority person actually uses the legal passing pocket")
	assert_eq(higher.cell, higher_goal, "higher-priority goal reached before the watchdog")
	assert_eq(lower.cell, lower_goal, "lower-priority goal reached before the watchdog")


func _advance(world: SimWorld) -> void:
	_previous[world.get_instance_id()] = MovementInvariants.capture(world)
	world.advance()


func _advance_sim(sim: RestaurantSim) -> void:
	_previous[sim.world.get_instance_id()] = MovementInvariants.capture(sim.world)
	sim.advance()


func test_infeasible_diagonal_intent_cannot_veto_a_free_cardinal_step() -> void:
	var world: SimWorld = _world(["...", "...", "..."])
	var shared: Vector2i = Vector2i(0, 2)
	var final_cardinal: Vector2i = Vector2i(2, 2)
	var diagonal: Walker = _walker(world, Vector2i(1, 1), shared)
	var cardinal: Walker = _walker(world, Vector2i(0, 1), shared)
	assert_true(diagonal.id < cardinal.id)
	assert_eq(world.movement.priority(world, diagonal), world.movement.priority(world, cardinal))
	assert_eq(diagonal.next_cell(), shared)
	assert_eq(cardinal.next_cell(), shared)
	assert_true(world.movement.can_enter(world, cardinal, shared), "the cardinal destination is physically free")
	assert_false(world.movement.can_enter(world, diagonal, cardinal.cell), "the lower-ID diagonal's corner is occupied")
	_advance(world)
	if not _safe(world):
		return
	assert_true(cardinal.move_progress > 0.0, "an infeasible higher-priority intention cannot reserve a physically free target")
	var changed_goal: bool = false
	# The first checked tick above is included in the existing512tick bound.
	for tick: int in range(1, WATCHDOG):
		_advance(world)
		if not _safe(world):
			return
		if not changed_goal and cardinal.cell == shared and cardinal.move_progress == 0.0:
			assert_true(cardinal.set_destination(world.grid, final_cardinal),
				"after physically reaching the shared target, use the public API to choose a distinct final goal")
			changed_goal = true
		if changed_goal and diagonal.cell == shared and diagonal.has_arrived() \
				and cardinal.cell == final_cardinal and cardinal.has_arrived():
			break
	assert_true(changed_goal, "the higher-ID person actually reaches the formerly contested target")
	assert_eq(diagonal.cell, shared, "the original lower-ID goal is reached before the bounded watchdog")
	assert_true(diagonal.has_arrived())
	assert_eq(cardinal.cell, final_cardinal, "both final goals are physically distinct and achieved")
	assert_true(cardinal.has_arrived())
