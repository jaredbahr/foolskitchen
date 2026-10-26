extends TestCase
## Production FK-066 paths. UNRUN while the live demo holds engine admission.

const TABLE: ItemDef = preload("res://data/items/table_4.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")

var _arrivals: Array[Dictionary] = []


func before_each() -> void:
	_arrivals.clear()


func test_spawner_publishes_a_complete_party_together_with_private_seeded_streams() -> void:
	var first: RestaurantSim = _empty_service(7)
	var replay: RestaurantSim = _empty_service(7)
	for sim: RestaurantSim in [first, replay]:
		var catalogue: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
		var family: CustomerType = TYPES.find_type(&"family").duplicate() as CustomerType
		family.party_size_min = 3
		family.party_size_max = 3
		catalogue.types = [family]
		assert_true(sim.configure_customer_types(catalogue, 4))
		sim.spawner._remaining = 1
	first.customer_arrived.connect(_record_arrival)
	first.spawner.advance(first)
	replay.spawner.advance(replay)
	assert_eq(first.customers().size(), 3)
	assert_eq(_arrivals.size(), 3)
	var party: Party = first.customers()[0].party
	assert_not_null(party)
	assert_eq(party.size(), 3)
	assert_eq(party.label(), "Party of 3")
	for index: int in 3:
		var guest: CustomerAgent = first.customers()[index]
		var repeated: CustomerAgent = replay.customers()[index]
		assert_eq(guest.party, party)
		assert_eq(guest.cell, first.world.grid.entries()[0])
		assert_eq(guest.state, CustomerAgent.State.ARRIVING)
		assert_eq(guest.rng.seed, repeated.rng.seed)
		assert_eq(guest.rng.state, repeated.rng.state)
		assert_eq(_arrivals[index]["size"], 3, "arrival observers see the entire party")
		assert_eq(_arrivals[index]["installed"], 3)
		assert_eq(_arrivals[index]["tick"], 0)
	assert_ne(first.customers()[0].rng, first.customers()[1].rng)
	assert_ne(first.customers()[0].rng.seed, first.customers()[1].rng.seed)
	assert_eq(first.rng.state, replay.rng.state)


func test_real_ticks_keep_three_waiting_until_one_table_has_three_free_seats() -> void:
	var sim: RestaurantSim = _empty_service(1)
	var small: PlacedItem = sim.world.grid.place(Vector2i.ONE, Vector2i(5, 5), 0, true,
		[], [Vector2i(-1, 0), Vector2i(1, 0)] as Array[Vector2i])
	var party: Party = sim.add_party(Vector2i.ZERO, _randoms(3), TYPES.find_type(&"family"))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	for tick: int in 4:
		sim.advance()
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.QUEUED)
		assert_eq(guest.table_item_id, 0)
		assert_eq(guest._queue_wait, 3)
	for seat: Vector2i in small.seat_cells:
		assert_eq(small.reserved_by(seat), -1)
	var table: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(4, 7))
	assert_true(table.reserve(table.seat_cells[0], 999))
	sim.advance()
	for guest: CustomerAgent in guests:
		assert_eq(guest.table_item_id, table.id)
		assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT)
		assert_eq(table.reserved_by(guest.seat_cell), guest.id)
	assert_eq(table.reserved_by(table.seat_cells[0]), 999)


func test_real_timeout_leaves_all_members_and_records_each_reason_once() -> void:
	var sim: RestaurantSim = _empty_service(42)
	var party: Party = sim.add_party(Vector2i.ZERO, _randoms(3))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	for guest: CustomerAgent in guests:
		guest.queue_patience = 3
	for tick: int in 4:
		sim.advance()
	assert_true(party.departing)
	for guest: CustomerAgent in guests:
		assert_true(guest.state >= CustomerAgent.State.LEAVING)
		assert_eq(guest.leave_reason, &"no_table")
	for tick: int in 100:
		sim.advance()
		if sim.customers().is_empty():
			break
	assert_true(sim.customers().is_empty())
	assert_eq(sim.lost_today, 3)
	assert_eq(sim.leave_reasons_today.get(&"no_table", 0), 3)
	for guest: CustomerAgent in guests:
		sim.record_departure(guest)
	assert_eq(sim.lost_today, 3, "duplicate cleanup never recounts a member")


func test_live_invalid_seat_requeues_every_member_without_a_singleton_fallthrough() -> void:
	var sim: RestaurantSim = _empty_service(11)
	var table: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(4, 5))
	var party: Party = sim.add_party(Vector2i.ZERO, _randoms(3))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	sim.advance()
	var seat: Vector2i = guests[0].seat_cell
	var blocker: PlacedItem = sim.world.grid.place(Vector2i.ONE, seat, 0, true)
	assert_not_null(blocker)
	sim.advance()
	assert_eq(party.table_item_id, 0)
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.QUEUED)
		assert_eq(guest.table_item_id, 0)
		assert_eq(guest.seat_cell, SimGrid.NO_CELL)
	for remaining: Vector2i in table.seat_cells:
		assert_eq(table.reserved_by(remaining), -1)
	assert_true(sim.world.grid.remove(blocker.id))
	sim.advance()
	for guest: CustomerAgent in guests:
		assert_eq(guest.table_item_id, table.id)
		assert_eq(table.reserved_by(guest.seat_cell), guest.id)


func test_external_removal_before_seating_releases_the_whole_party() -> void:
	var sim: RestaurantSim = _empty_service(12)
	var table: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(4, 5))
	var party: Party = sim.add_party(Vector2i.ZERO, _randoms(3))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	sim.advance()
	sim.world.remove_agent(guests[0])
	assert_true(party.departing)
	for guest: CustomerAgent in guests:
		assert_true(guest.state >= CustomerAgent.State.LEAVING)
		assert_eq(guest.leave_reason, &"no_table")
	for seat: Vector2i in table.seat_cells:
		assert_eq(table.reserved_by(seat), -1)


func test_food_timeout_ends_every_remaining_unpaid_visit_with_the_same_reason() -> void:
	var sim: RestaurantSim = _empty_service(13)
	sim.world.grid.place_def(TABLE, Vector2i(4, 5))
	var party: Party = sim.add_party(Vector2i.ZERO, _randoms(3))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	assert_true(PartySeating.try_seat(party, sim.world))
	party.seated = true
	for guest: CustomerAgent in guests:
		guest.cell = guest.seat_cell
		guest.state = CustomerAgent.State.WAITING_FOOD
	guests[0].food_patience = 1
	sim.advance()
	assert_true(party.departing)
	for guest: CustomerAgent in guests:
		assert_true(guest.state >= CustomerAgent.State.LEAVING)
		assert_eq(guest.leave_reason, &"waited_too_long")
	for tick: int in 150:
		sim.advance()
		if sim.customers().is_empty():
			break
	assert_true(sim.customers().is_empty())
	assert_eq(sim.lost_today, 3)
	assert_eq(sim.leave_reasons_today.get(&"waited_too_long", 0), 3)


func test_collective_timeout_preserves_a_members_already_recorded_payment() -> void:
	var sim: RestaurantSim = _empty_service(14)
	sim.world.grid.place_def(TABLE, Vector2i(4, 5))
	var party: Party = sim.add_party(Vector2i.ZERO, _randoms(3))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	assert_true(PartySeating.try_seat(party, sim.world))
	party.seated = true
	for guest: CustomerAgent in guests:
		guest.cell = guest.seat_cell
		guest.state = CustomerAgent.State.WAITING_FOOD
	guests[0].order = Order.new()
	guests[0].order.price = 12
	sim.pay(guests[0], guests[0].order)
	guests[0]._leave(sim.world, sim, &"happy")
	guests[0]._leave(sim.world, sim, &"waited_too_long")
	assert_eq(guests[1].state, CustomerAgent.State.WAITING_FOOD,
		"ordinary payment and stale cleanup do not end another member's meal")
	assert_false(party.departing)
	guests[1].food_patience = 1
	sim.advance()
	assert_eq(guests[0].leave_reason, &"happy")
	assert_true(guests[0].paid)
	assert_eq(guests[1].leave_reason, &"waited_too_long")
	assert_eq(guests[2].leave_reason, &"waited_too_long")
	for tick: int in 150:
		sim.advance()
		if sim.customers().is_empty():
			break
	assert_eq(sim.served_today, 1)
	assert_eq(sim.lost_today, 2)
	assert_eq(sim.leave_reasons_today.get(&"happy", 0), 1)
	assert_eq(sim.leave_reasons_today.get(&"waited_too_long", 0), 2)


func test_real_kitchen_party_gets_three_individual_orders_payments_and_reviews() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = ShopLayout.new()
	layout.id = &"party_service_fixture"
	layout.display_name = "Party service fixture"
	layout.rows = LAYOUT.rows.duplicate()
	layout.staff_spawns = LAYOUT.staff_spawns.duplicate()
	for placement: ShopPlacement in LAYOUT.placements:
		if content.item(placement.item_id).category != ItemDef.Category.TABLE:
			layout.placements.append(placement.duplicate(true) as ShopPlacement)
	var large: ShopPlacement = ShopPlacement.new()
	large.item_id = &"table_4"
	large.origin = Vector2i(3, 6)
	layout.placements.append(large)
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, 19, errors, stock)
	assert_eq(errors, [] as Array[String])
	sim.menu = [content.recipe(&"burger")] as Array[RecipeDef]
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()
	var tuning: ReviewTuning = REVIEWS.duplicate() as ReviewTuning
	tuning.review_chance = 1.0
	sim.configure_reviews(ReputationBook.new(), tuning, QUOTES, _rng(29))
	assert_true(sim.world.clock.start_service())
	var party: Party = sim.add_party(sim.world.grid.entries()[0], _randoms(3))
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	# These existing kitchen-test budgets isolate lifecycle from balance tuning.
	for guest: CustomerAgent in guests:
		guest.food_patience = 5000
		guest.eat_ticks = 3
	var paid_count: int = 0
	for tick: int in 4000:
		sim.advance()
		if sim.customers().is_empty():
			break
	assert_true(party.seated)
	assert_eq(sim.served_today, 3)
	assert_eq(sim.lost_today, 0)
	assert_true(sim.customers().is_empty())
	var order_ids: Array[int] = []
	var seats: Array[Vector2i] = []
	for guest: CustomerAgent in guests:
		assert_not_null(guest.order)
		if guest.order == null:
			continue
		assert_true(guest.paid)
		assert_eq(guest.order.state, Order.State.DELIVERED)
		assert_eq(guest.order.customer_id, guest.id)
		assert_eq(guest.order.table_item_id, party.table_item_id)
		assert_false(order_ids.has(guest.order.id))
		assert_false(seats.has(guest.order.seat_cell))
		assert_eq(guest.leave_reason, &"happy")
		order_ids.append(guest.order.id)
		seats.append(guest.order.seat_cell)
		paid_count += 1
	assert_eq(paid_count, 3)
	assert_eq(sim.reviews_today.size(), 3, "each paid member samples its own review")
	assert_eq(sim.kitchen.plates.total,
		sim.kitchen.plates.clean + sim.kitchen.plates.dirty + sim.kitchen.plates.in_use)


func _empty_service(seed_value: int) -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY)
	sim.world = SimWorld.new(grid)
	sim.rng.seed = seed_value
	sim.spawner = CustomerSpawner.new(sim.rng)
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()
	assert_true(sim.world.clock.start_service())
	return sim


func _record_arrival(guest: CustomerAgent) -> void:
	var sim: RestaurantSim = guest._restaurant.get_ref() as RestaurantSim
	_arrivals.append({"size": guest.party.size() if guest.party != null else 0,
		"installed": sim.customers().size(), "tick": sim.world.now})


func _randoms(count: int) -> Array[RandomNumberGenerator]:
	var result: Array[RandomNumberGenerator] = []
	for index: int in count:
		result.append(_rng(100 + index))
	return result


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
