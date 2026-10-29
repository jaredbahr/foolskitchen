extends TestCase
## Waiting benches alter only visits that really sit down; no queue cap or
## dining seats are added. Every decision preserves deterministic streams.

const BENCH: ItemDef = preload("res://data/items/waiting_bench.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")


func test_waiting_item_is_buyable_but_never_a_dining_seat_or_restroom_threshold() -> void:
	var sim: RestaurantSim = _empty_sim()
	assert_not_null(sim.world.grid.place_def(BENCH, Vector2i(1, 1)))
	assert_eq(BENCH.category, ItemDef.Category.WAITING)
	assert_eq(CatalogueText.group_for(BENCH), &"seating")
	assert_true(CatalogueText.does(BENCH).contains("never eat here"))
	assert_eq(BENCH.unlock_level, 1)
	assert_eq(DiningSeats.largest_usable_capacity(sim.world.grid), 0)
	assert_eq(sim.seat_count(), 0)
	assert_false(sim.restrooms_expected())
	var guest: CustomerAgent = sim.add_customer(Vector2i(1, 1), _rng(7))
	assert_false(guest._try_seat(sim.world))
	assert_eq(guest.table_item_id, 0)
	assert_eq(guest.order, null)


func test_only_arriving_at_a_reserved_bench_adds_patience_once() -> void:
	var sim: RestaurantSim = _empty_sim()
	var bench: PlacedItem = sim.world.grid.place_def(BENCH, Vector2i(4, 1))
	var guest: CustomerAgent = sim.add_customer(Vector2i(1, 1), _rng(9))
	guest.queue_patience = 20
	guest.move_speed = 1.0
	var stream: int = guest.rng.state
	guest.tick(sim.world)
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(guest.waiting_item_id, bench.id)
	assert_eq(guest.queue_patience, 20, "the walk earns no bonus")
	assert_false(guest.waited_seated)
	for tick: int in 5:
		guest.tick(sim.world)
	assert_true(guest.is_waiting_seated(sim.world))
	assert_true(guest.waited_seated)
	assert_eq(guest.queue_patience, 30)
	for tick: int in 5:
		guest.tick(sim.world)
	assert_eq(guest.queue_patience, 30, "repeated seated ticks never compound")
	assert_eq(guest.rng.state, stream)
	assert_eq(guest.table_item_id, 0)
	assert_null(guest.order)


func test_no_bench_retains_exact_queue_deadline_and_private_rng() -> void:
	var sim: RestaurantSim = _empty_sim()
	var guest: CustomerAgent = sim.add_customer(Vector2i(1, 1), _rng(11))
	guest.queue_patience = 3
	var stream: int = guest.rng.state
	guest.tick(sim.world)
	assert_eq(guest._queue_wait, 0, "arrival's first table search is still free")
	for tick: int in 2:
		guest.tick(sim.world)
		assert_eq(guest.state, CustomerAgent.State.QUEUED)
		assert_eq(guest._queue_wait, tick + 1)
	guest.tick(sim.world)
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	assert_eq(guest.leave_reason, &"no_table")
	assert_eq(guest.queue_patience, 3)
	assert_eq(guest.rng.state, stream)
	assert_false(guest.waited_seated)
	assert_eq(guest.waiting_item_id, 0)


func test_full_bench_leaves_other_waiters_in_the_uncapped_door_queue() -> void:
	var sim: RestaurantSim = _empty_sim()
	var bench: PlacedItem = sim.world.grid.place_def(BENCH, Vector2i(1, 1))
	var guests: Array[CustomerAgent] = []
	for index: int in 5:
		var guest: CustomerAgent = sim.add_customer(Vector2i(1, 1), _rng(index + 20))
		guest.move_speed = 1.0
		guests.append(guest)
	for tick: int in 6:
		for guest: CustomerAgent in guests:
			guest.tick(sim.world)
	var seated: int = 0
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.QUEUED)
		if guest.is_waiting_seated(sim.world):
			seated += 1
	assert_eq(seated, 2)
	assert_eq(bench.reserved_by(bench.seat_cells[0]), guests[0].id)
	assert_eq(bench.reserved_by(bench.seat_cells[1]), guests[1].id)
	assert_eq(guests.size(), 5, "waiting room capacity is never a queue cap")
	assert_eq(guests[2].queue_patience, 300)


func test_waiting_pair_releases_bench_and_walks_to_one_table_together() -> void:
	var sim: RestaurantSim = _empty_sim()
	var bench: PlacedItem = sim.world.grid.place_def(BENCH, Vector2i(1, 1))
	var randoms: Array[RandomNumberGenerator] = [_rng(31), _rng(32)]
	var party: Party = sim.add_party(Vector2i(1, 1), randoms)
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	for guest: CustomerAgent in guests:
		guest.move_speed = 1.0
		guest.queue_patience = 20
	for tick: int in 6:
		sim.world.now = tick
		PartySeating.advance_queue(party, sim.world, sim)
	for guest: CustomerAgent in guests:
		assert_true(guest.is_waiting_seated(sim.world))
		assert_eq(guest.queue_patience, 30)
	var table: PlacedItem = _table(sim.world.grid)
	assert_true(PartySeating.try_seat(party, sim.world))
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT)
		assert_eq(guest.table_item_id, table.id)
		assert_eq(guest.waiting_item_id, 0)
		assert_eq(table.reserved_by(guest.seat_cell), guest.id)
	for seat: Vector2i in bench.seat_cells:
		assert_eq(bench.reserved_by(seat), -1)


func test_bench_loss_and_guest_removal_release_all_waiting_holds() -> void:
	var sim: RestaurantSim = _empty_sim()
	var bench: PlacedItem = sim.world.grid.place_def(BENCH, Vector2i(1, 1))
	var guest: CustomerAgent = sim.add_customer(Vector2i(1, 1), _rng(42))
	guest.tick(sim.world)
	assert_true(guest.is_waiting_seated(sim.world))
	sim.world.remove_agent(guest)
	assert_eq(bench.reserved_by(bench.seat_cells[0]), -1)
	var second: CustomerAgent = sim.add_customer(Vector2i(1, 1), _rng(43))
	second.tick(sim.world)
	assert_true(second.is_waiting_seated(sim.world))
	assert_true(sim.world.grid.remove(bench.id))
	second.tick(sim.world)
	assert_eq(second.waiting_item_id, 0)
	assert_false(second.is_waiting_seated(sim.world))
	assert_eq(second.state, CustomerAgent.State.QUEUED)


func test_benches_require_dining_and_street_reachability_but_distance_only_warns() -> void:
	var sim: RestaurantSim = _empty_sim()
	var bench: PlacedItem = sim.world.grid.place_def(BENCH, Vector2i(1, 1))
	assert_eq(WaitingBench.placement_problem(sim.world.grid, bench, RoomRules.guest_reachable(sim.world.grid)), "")
	for kind: int in [SimGrid.Room.KITCHEN, SimGrid.Room.STORAGE, SimGrid.Room.RESTROOM]:
		assert_true(sim.world.grid.set_rooms({bench.seat_cells[0]: kind}))
		assert_eq(WaitingBench.placement_problem(sim.world.grid, bench, RoomRules.guest_reachable(sim.world.grid)),
			WaitingBench.DINING_ONLY)
	assert_true(sim.world.grid.set_rooms({bench.seat_cells[0]: SimGrid.Room.DINING}))
	for y: int in 12:
		assert_true(sim.world.grid.set_terrain(Vector2i(3, y), SimGrid.Terrain.WALL))
	var far: PlacedItem = sim.world.grid.place_def(BENCH, Vector2i(8, 8))
	assert_eq(WaitingBench.placement_problem(sim.world.grid, far, RoomRules.guest_reachable(sim.world.grid)),
		WaitingBench.REACHABLE)
	for y: int in 12:
		assert_true(sim.world.grid.set_terrain(Vector2i(3, y), SimGrid.Terrain.FLOOR))
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var editor: ShopEditor = ShopEditor.new(sim, content, null)
	var check: EditCheck = editor.check_current()
	assert_true(check.ok)
	assert_eq(check.seat_warnings.get(far.id), WaitingBench.FAR_FROM_DOOR)
	assert_false(check.seat_warnings.has(bench.id))


func test_editor_refuses_a_bench_in_staff_rooms_or_cut_off_floor() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 1, errors)
	assert_eq(errors, [] as Array[String])
	var editor: ShopEditor = ShopEditor.new(sim, content, null)
	var check: EditCheck = editor._check_placement(BENCH, Vector2i(10, 2), 0, -1, 0)
	assert_false(check.ok)
	assert_eq(check.why, WaitingBench.DINING_ONLY)
	check = editor._check_placement(BENCH, Vector2i(6, 10), 0, -1, 0)
	assert_true(check.ok, check.why)


func test_seated_wait_gets_its_own_quote_but_real_food_complaints_still_win() -> void:
	var sim: RestaurantSim = _empty_sim()
	sim.world.grid.place_def(BENCH, Vector2i(1, 1))
	var guest: CustomerAgent = sim.add_customer(Vector2i(1, 1), _rng(51))
	guest.tick(sim.world)
	guest.paid = true
	guest._queue_wait = 400
	var visit: ReviewVisit = guest.review_visit(12)
	assert_true(visit.waited_seated)
	assert_eq(ReputationBook.cause_of(visit, REVIEWS), &"comfortable_wait")
	assert_false(QUOTES.pick(&"comfortable_wait", _rng(51), {}).contains("too long"))
	visit.food_wait_fraction = 1.0
	visit.queue_wait_fraction = 0.0
	visit.price_ratio = 3.0
	assert_ne(ReputationBook.cause_of(visit, REVIEWS), &"comfortable_wait")


func test_real_busy_service_seats_a_bench_waiter_instead_of_losing_them() -> void:
	var without: Dictionary = _busy_service(false)
	var with_bench: Dictionary = _busy_service(true)
	print("WAITING_BENCH_BUSY without=%s with=%s" % [without, with_bench])
	assert_eq(without["served"], 0)
	assert_eq(without["lost"], 1)
	assert_eq(with_bench["served"], 1)
	assert_eq(with_bench["lost"], 0)
	assert_true(with_bench["sat_waiting"])


func test_waiting_bench_uses_the_existing_item_save_format_without_visit_state() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 1, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(sim.world.grid.place_def(BENCH, Vector2i(6, 10)))
	var editor: ShopEditor = ShopEditor.new(sim, content, null, LAYOUT)
	var saved: Dictionary = editor.to_dict()
	assert_eq(saved["version"], 6)
	assert_false(str(saved).contains("waiting_item_id"))
	assert_false(str(saved).contains("waited_seated"))
	var layout: ShopLayout = ShopEditor.from_dict(saved, LAYOUT, content, errors)
	assert_not_null(layout)
	assert_eq(errors, [] as Array[String])
	var restored: RestaurantSim = RestaurantSim.create(layout, content, 1, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(WaitingBench.benches(restored.world.grid).size(), 1)
	assert_eq(restored.seat_count(), sim.seat_count())
	assert_true(restored.customers().is_empty())
	for seat: Vector2i in WaitingBench.benches(restored.world.grid)[0].seat_cells:
		assert_eq(WaitingBench.benches(restored.world.grid)[0].reserved_by(seat), -1)


func test_waiting_seats_cannot_be_shared_with_dining_seats() -> void:
	var sim: RestaurantSim = _empty_sim()
	var table: PlacedItem = _table(sim.world.grid)
	var bench: PlacedItem = sim.world.grid.place_def(BENCH, table.seat_cells[0] + Vector2i.LEFT)
	assert_not_null(bench)
	assert_eq(WaitingBench.placement_problem(sim.world.grid, bench, RoomRules.guest_reachable(sim.world.grid)),
		WaitingBench.DINING_OVERLAP)


func _busy_service(with_bench: bool) -> Dictionary:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 1, errors, stock)
	assert_eq(errors, [] as Array[String])
	if with_bench:
		assert_not_null(sim.world.grid.place_def(BENCH, Vector2i(6, 10)))
	var tables: Array[PlacedItem] = []
	for item: PlacedItem in sim.world.grid.items():
		if (item.def as ItemDef).category == ItemDef.Category.TABLE:
			tables.append(item)
			for seat: Vector2i in item.seat_cells:
				assert_true(item.reserve(seat, 900))
	assert_true(sim.world.clock.start_service())
	sim.spawner._remaining = 1000000
	var guest: CustomerAgent = sim.add_customer(Vector2i(6, 10), _rng(100))
	guest.queue_patience = 120
	var sat_waiting: bool = false
	for tick: int in 2400:
		if tick == 150:
			for table: PlacedItem in tables:
				table.release_all(900)
		sim.advance()
		sat_waiting = sat_waiting or guest.is_waiting_seated(sim.world)
		if sim.customers().is_empty():
			break
	return {"served": sim.served_today, "lost": sim.lost_today, "sat_waiting": sat_waiting}


func _empty_sim() -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(Vector2i(0, 1), SimGrid.Terrain.ENTRY)
	sim.world = SimWorld.new(grid, SimClock.new())
	assert_true(sim.world.clock.start_service())
	return sim


func _table(grid: SimGrid) -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_table"
	definition.category = ItemDef.Category.TABLE
	definition.seat_cells = [Vector2i.LEFT, Vector2i.RIGHT]
	return grid.place_def(definition, Vector2i(6, 4))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
