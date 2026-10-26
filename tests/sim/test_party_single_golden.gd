extends TestCase
## UNRUN source fixtures: every configured party size is one. The frozen
## integration boundaries come from exact main 1f9804e, not expected scores.

const MAIN: Script = preload("res://tests/fixtures/party_single_main.gd")
const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const DIRT: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")


func test_party_size_one_matches_exact_main_seed_1() -> void:
	_compare(1)


func test_party_size_one_matches_exact_main_seed_7() -> void:
	_compare(7)


func test_party_size_one_matches_exact_main_seed_42() -> void:
	_compare(42)


func _compare(seed_value: int) -> void:
	var reference: RestaurantSim = _sim(seed_value, true)
	var current: RestaurantSim = _sim(seed_value, false)
	assert_eq(_snapshot(current), _snapshot(reference), "initial exact-main state")
	for tick: int in 4501:
		reference.advance()
		current.advance()
		assert_eq(_snapshot(current), _snapshot(reference),
			"seed %d singleton state at tick %d" % [seed_value, tick])
		if reference.world.clock.phase == SimClock.Phase.CLOSED:
			break
	assert_eq(current.world.clock.phase, SimClock.Phase.CLOSED)
	assert_true(current.served_today + current.lost_today > 0, "a real service must run")
	assert_true(current.customers().is_empty())
	if seed_value != 42:
		assert_true(current.served_today > 0, "stocked Kitchen must reach individual payments")
	assert_eq(current.served_today, reference.served_today)
	assert_eq(current.reviews_today, reference.reviews_today)
	assert_eq(current.kitchen.plates.total,
		current.kitchen.plates.clean + current.kitchen.plates.dirty + current.kitchen.plates.in_use)


func _sim(seed_value: int, frozen: bool) -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, seed_value, errors, null, false)
	assert_eq(errors, [] as Array[String])
	if frozen:
		var original: RestaurantSim = sim
		sim = MAIN.MainRestaurant.new()
		sim.world = original.world
		sim.menu = original.menu
		sim.staff_spawns = original.staff_spawns
		sim.rng = original.rng
		sim.spawner = MAIN.MainSpawner.new(sim.rng)
	var singles: CustomerTypeCatalogue = TYPES.duplicate(true) as CustomerTypeCatalogue
	for kind: CustomerType in singles.types:
		kind.party_size_min = 1
		kind.party_size_max = 1
	assert_true(sim.configure_customer_types(singles, 4))
	if seed_value != 42:
		for ingredient: IngredientDef in content.ingredients():
			sim.stock.add(ingredient.id, 100, 1)
	sim.kitchen = Kitchen.new(sim, content, sim.stock)
	sim.configure_reviews(ReputationBook.new(), REVIEWS, QUOTES, _rng(seed_value + 9000))
	var dirt: CleanlinessState = CleanlinessState.new(sim.world.grid, DIRT, _rng(seed_value + 5000))
	assert_true(sim.configure_cleanliness(dirt, DIRT))
	sim.start_day()
	assert_true(sim.world.clock.start_service())
	return sim


func _snapshot(sim: RestaurantSim) -> Dictionary:
	var guests: Array = []
	for guest: CustomerAgent in sim.customers():
		guests.append([guest.id, guest.state, guest.cell, guest.path.duplicate(), guest.path_index,
			guest.move_progress, guest.table_item_id, guest.seat_cell, guest.queue_patience,
			guest.food_patience, guest._queue_wait, guest._food_wait, guest._walk_wait,
			guest._eating, guest.leave_reason, guest.paid, guest.customer_type_id,
			guest.arrival_dirt_fraction, guest.rng.seed, guest.rng.state])
	var staff_rows: Array = []
	for agent: SimAgent in sim.world.agents:
		if agent is StaffAgent:
			var staff: StaffAgent = agent as StaffAgent
			staff_rows.append([staff.id, staff.cell, staff.path.duplicate(), staff.path_index,
				staff.move_progress, staff.task.id if staff.task != null else 0,
				staff.step_index, staff.work_left])
	var orders: Array = []
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY,
			Order.State.DELIVERED, Order.State.CANCELLED]:
		for order: Order in sim.orders.orders_in_state(state):
			orders.append([order.id, order.customer_id, order.table_item_id, order.seat_cell,
				order.recipe_id, order.price, order.placed_tick, order.state, order.quality,
				order.cancellation_reason])
	var tasks: Array = []
	for task: SimTask in sim.world.board.open_tasks() + sim.world.board.claimed_tasks():
		tasks.append([task.id, task.kind, task.state, task.claimed_by, task.claimed_tick, task.drops])
	var reservations: Array = []
	for item: PlacedItem in sim.world.grid.items():
		for cell: Vector2i in item.work_cells + item.seat_cells:
			reservations.append([item.id, cell, item.reserved_by(cell)])
	return {"now": sim.world.now, "clock": sim.world.clock.to_dict(), "rng": sim.rng.state,
		"review_rng": sim.review_rng.state, "dirt_rng": sim.cleanliness._rng.state,
		"next_arrival": sim.spawner._remaining, "guests": guests, "staff": staff_rows,
		"orders": orders, "tasks": tasks, "holds": reservations,
		"log": sim.world.event_log.duplicate(), "served": sim.served_today, "lost": sim.lost_today,
		"reasons": sim.leave_reasons_today.duplicate(), "reviews": sim.reviews_today.duplicate(true),
		"scores": sim.review_book.scores(), "stock": sim.stock.to_dict(),
		"plates": sim.kitchen.plates.to_dict(), "dirty_tables": sim.kitchen.dirty_tables.duplicate(),
		"spots": sim.cleanliness.spots()}


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
