extends TestCase
## FK-101: restrooms. A Restroom room with a toilet guests can reach is a
## restroom. After ordering a guest may need it: they walk there, stay about
## 20 seconds (one guest per toilet), and come back; the food waits and their
## patience pauses. Below the seat threshold with no restroom nothing is
## drawn; at or above it a guest who can't use one loses patience and says so.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: RestroomTuning = preload("res://data/balance/restroom.tres")

var _content: ContentDB
var _sim: RestaurantSim


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()


func after_each() -> void:
	_sim = null
	_content = null


func test_a_restroom_needs_the_room_and_a_reachable_toilet() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_false(_sim.has_restroom())
	assert_eq(_sim.seat_count(), 6)
	assert_false(_sim.restrooms_matter(), "the starter draws nothing")
	var toilet: PlacedItem = grid.place_def(_content.item(&"toilet"), Vector2i(1, 9), 0)
	assert_not_null(toilet)
	assert_false(_sim.has_restroom(), "a toilet in the dining room is not a restroom")
	grid.set_rooms({Vector2i(1, 9): SimGrid.Room.RESTROOM, Vector2i(1, 8): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	assert_true(_sim.has_restroom())
	assert_true(_sim.restrooms_matter())
	# A toilet guests can only reach through the kitchen does not count.
	grid.remove(toilet.id)
	assert_not_null(grid.place_def(_content.item(&"toilet"), Vector2i(12, 2), 0))
	grid.set_rooms({Vector2i(12, 2): SimGrid.Room.RESTROOM, Vector2i(12, 1): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	assert_false(_sim.has_restroom())


func test_restroom_trip_food_waits_and_patience_pauses() -> void:
	_restroom(Vector2i(1, 9))
	_sim.world.clock.start_service()
	var guest: CustomerAgent = _guest(1.0)
	assert_true(_run_until(guest, &"_waiting_food"))
	assert_ne(guest.restroom, CustomerAgent.Restroom.NONE, "they need the restroom")
	assert_almost_eq(guest.restroom_bonus, TUNING.restroom_review_bonus, 0.0001, "a bit happier")
	assert_true(_run_until(guest, &"_inside"))
	assert_true(guest.in_restroom())
	# The meal arrives while they are away: it waits, and so does patience.
	_sim.orders.set_state(guest.order, Order.State.READY)
	_sim.orders.set_state(guest.order, Order.State.DELIVERED)
	var waited: int = guest._food_wait
	var mood: float = guest.mood()
	var inside: int = 0
	while guest.restroom == CustomerAgent.Restroom.INSIDE and inside < 1000:
		_sim.advance()
		inside += 1
		assert_eq(guest.state, CustomerAgent.State.WAITING_FOOD)
	assert_true(inside >= TUNING.use_ticks - 2 and inside <= TUNING.use_ticks,
		"about 20 seconds inside: %d" % inside)
	assert_true(_run_until(guest, &"_back"))
	assert_eq(guest._food_wait, waited, "patience paused while away")
	assert_almost_eq(guest.mood(), mood)
	assert_eq(guest.cell, guest.seat_cell, "back in the seat")
	assert_true(_run_until(guest, &"_eating"))
	assert_eq(guest.restroom_penalty, 0.0)


func test_one_guest_per_toilet_at_a_time() -> void:
	var toilet: PlacedItem = _restroom(Vector2i(1, 9))
	_sim.world.clock.start_service()
	var first: CustomerAgent = _guest(1.0, 1)
	var second: CustomerAgent = _guest(1.0, 2)
	var both_waiting: bool = false
	var ticks: int = 0
	var overlap: bool = false
	while ticks < 3000 and not (first.restroom == CustomerAgent.Restroom.DONE and second.restroom == CustomerAgent.Restroom.DONE):
		_sim.advance()
		ticks += 1
		if first.in_restroom() and second.in_restroom():
			overlap = true
		if first.in_restroom() and second.restroom == CustomerAgent.Restroom.NEEDED \
				or second.in_restroom() and first.restroom == CustomerAgent.Restroom.NEEDED:
			both_waiting = true
		var holder: int = toilet.reserved_by(toilet.work_cells[0])
		assert_true(holder == -1 or holder == first.id or holder == second.id)
	assert_false(overlap, "never two inside one toilet")
	assert_true(both_waiting, "the second guest waits for the first")
	assert_eq(first.restroom, CustomerAgent.Restroom.DONE)
	assert_eq(second.restroom, CustomerAgent.Restroom.DONE)
	assert_eq(toilet.reserved_by(toilet.work_cells[0]), -1)


func test_below_the_threshold_without_a_restroom_nothing_is_drawn() -> void:
	_sim.world.clock.start_service()
	var guest: CustomerAgent = _guest(1.0)
	assert_true(_run_until(guest, &"_waiting_food"))
	var state: int = guest.rng.state
	assert_eq(guest.restroom, CustomerAgent.Restroom.NONE)
	assert_eq(guest.restroom_bonus, 0.0)
	# The same guest stream as with no restroom code: compare a twin guest
	# whose need chance is zero.
	var twin: CustomerAgent = _guest(0.0)
	assert_true(_run_until(twin, &"_waiting_food"))
	assert_eq(twin.rng.state, state, "identical draws")


func test_at_the_threshold_a_missed_restroom_costs_patience_and_shows_in_the_review() -> void:
	var tuning: RestroomTuning = TUNING.duplicate() as RestroomTuning
	tuning.seat_threshold = 6
	_sim.restroom_tuning = tuning
	assert_true(_sim.restrooms_expected())
	_sim.world.clock.start_service()
	var guest: CustomerAgent = _guest(1.0)
	assert_true(_run_until(guest, &"_waiting_food"))
	_sim.advance()
	assert_eq(guest.restroom, CustomerAgent.Restroom.DONE)
	assert_true(guest._food_wait >= roundi(guest.food_patience * tuning.missed_patience_share), "patience lost")
	assert_eq(guest.state, CustomerAgent.State.WAITING_FOOD, "they stay unless patience runs out")
	assert_eq(guest.restroom_penalty, tuning.missed_review_penalty)
	var visit: ReviewVisit = guest.review_visit(10)
	visit.served = true
	var review: ReviewTuning = load("res://data/balance/reviews.tres") as ReviewTuning
	assert_eq(ReputationBook.cause_of(visit, review), &"no_restroom")
	var quotes: ReviewQuotes = load("res://data/reviews/quotes.tres") as ReviewQuotes
	assert_true(quotes.is_valid())


func test_below_the_threshold_a_busy_restroom_costs_nothing() -> void:
	var toilet: PlacedItem = _restroom(Vector2i(1, 9))
	toilet.reserve(toilet.work_cells[0], 9999)
	_sim.world.clock.start_service()
	var guest: CustomerAgent = _guest(1.0)
	assert_true(_run_until(guest, &"_waiting_food"))
	_sim.advance()
	assert_eq(guest.restroom, CustomerAgent.Restroom.NEEDED, "waits for the busy one")
	_sim.orders.set_state(guest.order, Order.State.READY)
	_sim.orders.set_state(guest.order, Order.State.DELIVERED)
	_sim.advance()
	assert_eq(guest.state, CustomerAgent.State.EATING)
	assert_eq(guest.restroom, CustomerAgent.Restroom.DONE, "the meal came first")
	assert_eq(guest.restroom_penalty, 0.0)


func test_each_use_leaves_a_tidy_job_for_the_cleaners() -> void:
	var tuning: CleanlinessTuning = load("res://data/balance/cleanliness.tres") as CleanlinessTuning
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	assert_true(_sim.configure_cleanliness(CleanlinessState.new(_sim.world.grid, tuning, random), tuning))
	var toilet: PlacedItem = _restroom(Vector2i(1, 9))
	var spot: Vector2i = toilet.work_cells[0]
	_sim.restroom_used(spot)
	assert_true(_sim.cleanliness.has_spot(spot))
	assert_true(_sim.cleanliness.has_restroom_spot(spot))
	# Restroom upkeep is not floor dirt: no patience, review or band effect.
	assert_eq(_sim.cleanliness.spot_count(), 0)
	assert_eq(_sim.cleanliness.dirt_fraction(), 0.0)
	assert_eq(_sim.cleanliness.worst_today_count(), 0)
	assert_eq(_sim.cleanliness.patience_multiplier(), 1.0)
	var task: SimTask = _sim.clean_tasks.task_for(spot)
	assert_not_null(task)
	assert_eq(task.label, "Tidy the restroom")
	# A floor spot on the same cell is still a floor spot, and a mop job.
	_sim.cleanliness.clear_spot(spot)
	assert_false(_sim.cleanliness.has_spot(spot))


func test_a_toilet_needs_its_use_spot_in_the_restroom() -> void:
	var grid: SimGrid = _sim.world.grid
	var toilet: PlacedItem = grid.place_def(_content.item(&"toilet"), Vector2i(1, 9), 0)
	grid.set_rooms({Vector2i(1, 9): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	assert_false(_sim.has_restroom(), "the use spot is in the dining room")
	grid.set_rooms({toilet.work_cells[0]: SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	assert_true(_sim.has_restroom())


func test_a_guest_who_cannot_get_back_ends_the_visit() -> void:
	var toilet: PlacedItem = _restroom(Vector2i(1, 9))
	_sim.world.clock.start_service()
	var guest: CustomerAgent = _guest(1.0)
	assert_true(_run_until(guest, &"_inside"))
	# Shut the restroom in while they are inside: no way back to the seat.
	var spot: Vector2i = toilet.work_cells[0]
	_sim.world.grid.set_segments({SimGrid.edge_between(spot, spot + Vector2i.UP): SimGrid.Segment.WALL,
		SimGrid.edge_between(spot, spot + Vector2i.RIGHT): SimGrid.Segment.WALL} as Dictionary[Vector3i, int])
	var ate: bool = false
	for tick: int in 1500:
		_sim.advance()
		ate = ate or guest.state == CustomerAgent.State.EATING
		if guest.state >= CustomerAgent.State.LEAVING:
			break
	assert_false(ate, "never eats away from the table")
	assert_true(guest.state >= CustomerAgent.State.LEAVING)
	assert_eq(guest.leave_reason, &"no_table")
	assert_eq(toilet.reserved_by(spot), -1)


func test_untyped_guests_use_the_tuned_chance_and_busy_restrooms_say_so() -> void:
	var tuning: RestroomTuning = TUNING.duplicate() as RestroomTuning
	tuning.default_need_chance = 1.0
	_sim.restroom_tuning = tuning
	var toilet: PlacedItem = _restroom(Vector2i(1, 9))
	toilet.reserve(toilet.work_cells[0], 9999)
	tuning.seat_threshold = 6
	_sim.world.clock.start_service()
	var guest: CustomerAgent = _guest(-1.0)
	assert_true(_run_until(guest, &"_waiting_food"))
	assert_ne(guest.restroom, CustomerAgent.Restroom.NONE, "the tuned default chance applies")
	_sim.orders.set_state(guest.order, Order.State.READY)
	_sim.orders.set_state(guest.order, Order.State.DELIVERED)
	_sim.advance()
	assert_true(guest.restroom_was_busy)
	var visit: ReviewVisit = guest.review_visit(10)
	visit.served = true
	assert_eq(ReputationBook.cause_of(visit, load("res://data/balance/reviews.tres") as ReviewTuning), &"restroom_busy")


## A toilet at `cell` facing north (its use spot just north), in a Restroom.
func _restroom(cell: Vector2i) -> PlacedItem:
	var grid: SimGrid = _sim.world.grid
	var toilet: PlacedItem = grid.place_def(_content.item(&"toilet"), cell, 0)
	assert_not_null(toilet)
	var rooms: Dictionary[Vector2i, int] = {cell: SimGrid.Room.RESTROOM}
	for spot: Vector2i in toilet.work_cells:
		rooms[spot] = SimGrid.Room.RESTROOM
	grid.set_rooms(rooms)
	assert_true(_sim.has_restroom())
	return toilet


func _guest(chance: float, seed: int = 42) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
	guest.restroom_chance = chance
	return guest


## Advances until `check` (a method taking the guest) holds. Named methods,
## not lambdas: a lambda in a test script keeps resources alive at exit.
func _run_until(guest: CustomerAgent, check: StringName, limit: int = 3000) -> bool:
	for tick: int in limit:
		if call(check, guest):
			return true
		_sim.advance()
		if guest.state == CustomerAgent.State.LEFT or guest.state == CustomerAgent.State.LEAVING:
			return call(check, guest)
	return call(check, guest)


func _waiting_food(guest: CustomerAgent) -> bool:
	return guest.state == CustomerAgent.State.WAITING_FOOD


func _inside(guest: CustomerAgent) -> bool:
	return guest.restroom == CustomerAgent.Restroom.INSIDE


func _back(guest: CustomerAgent) -> bool:
	return not guest.away()


func _eating(guest: CustomerAgent) -> bool:
	return guest.state == CustomerAgent.State.EATING
