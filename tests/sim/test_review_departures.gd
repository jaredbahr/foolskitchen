extends TestCase
## Departure integration uses the live guest measurements and a dedicated RNG.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")

var _sim: RestaurantSim
var _book: ReputationBook
var _review_rng: RandomNumberGenerator
var _events: Array[Dictionary] = []


func before_each() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, content, 86011, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_book = ReputationBook.new()
	_review_rng = _random(86012)
	var certain: ReviewTuning = TUNING.duplicate() as ReviewTuning
	certain.review_chance = 1.0
	_sim.configure_reviews(_book, certain, QUOTES, _review_rng)
	_sim.review_recorded.connect(_on_review)
	_events.clear()


func test_paid_departure_uses_actual_waits_and_price_then_records_once() -> void:
	var guest: CustomerAgent = _guest()
	guest.queue_patience = 100
	guest.food_patience = 200
	guest._queue_wait = 75
	guest._food_wait = 100
	guest.order = Order.new()
	guest.order.recipe_id = _sim.menu[0].id
	guest.order.price = _sim.menu[0].standard_price * 2
	_sim.pay(guest, guest.order)
	var visit: ReviewVisit = guest.review_visit(_sim.menu[0].standard_price)
	assert_true(visit.served)
	assert_almost_eq(visit.queue_wait_fraction, 0.75)
	assert_almost_eq(visit.food_wait_fraction, 0.5)
	assert_almost_eq(visit.price_ratio, 2.0)
	assert_eq(visit.dirt_fraction, 0.0)
	_sim.record_departure(guest)
	assert_eq(_sim.reviews_today.size(), 1)
	assert_eq(_events.size(), 1)
	assert_eq(_sim.reviews_today[0]["stars"], ReputationBook.score_visit(visit, TUNING))
	assert_false(_sim.reviews_today[0].has("cause"))
	assert_eq(_sim.reviews_today[0]["before"], 3.0)
	assert_eq(_sim.reviews_today[0]["after"], _book.average())
	assert_false(String(_sim.reviews_today[0]["quote"]).is_empty())
	_events[0]["stars"] = 0
	assert_eq(_sim.reviews_today[0]["stars"], ReputationBook.score_visit(visit, TUNING))
	_sim.record_departure(guest)
	assert_eq(_sim.reviews_today.size(), 1)
	assert_eq(_events.size(), 1)
	assert_eq(_book.scores().size(), 6)


func test_unserved_departure_scores_one_but_closing_never_draws() -> void:
	var unserved: CustomerAgent = _guest()
	unserved.leave_reason = &"no_table"
	_sim.record_departure(unserved)
	assert_eq(_sim.reviews_today.size(), 1)
	assert_eq(_sim.reviews_today[0]["stars"], 1)
	assert_eq(_sim.lost_today, 1)
	var closing: CustomerAgent = _guest()
	closing.leave_reason = &"closing"
	var state: int = _review_rng.state
	_sim.record_departure(closing)
	assert_eq(_review_rng.state, state)
	assert_eq(_sim.reviews_today.size(), 1)
	assert_eq(_events.size(), 1)
	assert_eq(_sim.lost_today, 2)
	var paid_at_cutoff: CustomerAgent = _guest()
	paid_at_cutoff.order = Order.new()
	paid_at_cutoff.order.recipe_id = _sim.menu[0].id
	paid_at_cutoff.order.price = _sim.menu[0].standard_price
	_sim.pay(paid_at_cutoff, paid_at_cutoff.order)
	_sim.world.clock.phase = SimClock.Phase.CLOSED
	state = _review_rng.state
	_sim.record_departure(paid_at_cutoff)
	assert_eq(paid_at_cutoff.leave_reason, &"happy")
	assert_eq(_review_rng.state, state)
	assert_eq(_sim.reviews_today.size(), 1)


func test_review_rng_does_not_advance_arrival_or_guest_streams() -> void:
	var guest_random: RandomNumberGenerator = _random(86013)
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], guest_random)
	guest.leave_reason = &"no_table"
	var arrival_state: int = _sim.rng.state
	var guest_state: int = guest_random.state
	var review_state: int = _review_rng.state
	_sim.record_departure(guest)
	assert_ne(_review_rng.state, review_state)
	assert_eq(_sim.rng.state, arrival_state)
	assert_eq(guest_random.state, guest_state)


func test_same_named_seed_replays_the_departure_row() -> void:
	var first: CustomerAgent = _guest()
	first.leave_reason = &"no_table"
	_sim.record_departure(first)
	var expected: Dictionary = _sim.reviews_today[0].duplicate()
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var replay: RestaurantSim = RestaurantSim.create(LAYOUT, content, 86011, errors, null, false)
	assert_eq(errors, [] as Array[String])
	var certain: ReviewTuning = TUNING.duplicate() as ReviewTuning
	certain.review_chance = 1.0
	replay.configure_reviews(ReputationBook.new(), certain, QUOTES, _random(86012))
	var repeated: CustomerAgent = replay.add_customer(replay.world.grid.entries()[0], _random(86016))
	repeated.leave_reason = &"no_table"
	replay.record_departure(repeated)
	assert_eq(replay.reviews_today, [expected] as Array[Dictionary])


func test_start_day_resets_rows_and_snapshots_persistent_reputation() -> void:
	var guest: CustomerAgent = _guest()
	guest.leave_reason = &"no_table"
	_sim.record_departure(guest)
	assert_almost_eq(_book.average(), 16.0 / 6.0)
	_sim.start_day()
	assert_eq(_sim.reviews_today, [] as Array[Dictionary])
	assert_almost_eq(_sim.reputation_before_day, _book.average())
	assert_eq(_book.scores().size(), 6)
	assert_eq(_events.size(), 1)


func test_unconfigured_sim_keeps_departure_counts_without_review_draws() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var plain: RestaurantSim = RestaurantSim.create(LAYOUT, content, 86014, errors, null, false)
	assert_eq(errors, [] as Array[String])
	var guest: CustomerAgent = plain.add_customer(plain.world.grid.entries()[0], _random(86015))
	guest.leave_reason = &"no_table"
	plain.record_departure(guest)
	assert_eq(plain.lost_today, 1)
	assert_eq(plain.reviews_today.size(), 0)
	assert_eq(plain.review_book.scores().size(), 5)


func _guest() -> CustomerAgent:
	return _sim.add_customer(_sim.world.grid.entries()[0], _random(86016))


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random


func _on_review(row: Dictionary) -> void:
	_events.append(row)
