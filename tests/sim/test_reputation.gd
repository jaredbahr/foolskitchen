extends TestCase
## Pure review scoring and rolling-window checks; no world or autoload needed.

const TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")


func test_authored_weights_and_family_friendly_quote_groups_load() -> void:
	assert_true(TUNING.is_valid())
	assert_almost_eq(TUNING.positive_penalty_threshold, 0.5)
	assert_true(QUOTES.is_valid())
	assert_eq(QUOTES.groups.size(), ReviewQuotes.CAUSES.size())
	var seen: Dictionary[String, bool] = {}
	for cause: StringName in ReviewQuotes.CAUSES:
		for line: String in QUOTES.groups[cause]:
			assert_false(seen.has(line))
			seen[line] = true
	assert_true(seen.size() >= 40)


func test_unserved_is_one_star_and_closing_gives_no_review_or_rng_draw() -> void:
	var book: ReputationBook = ReputationBook.new()
	var tune: ReviewTuning = _certain_tuning()
	var random: RandomNumberGenerator = _random(86001)
	var visit: ReviewVisit = ReviewVisit.new()
	visit.closing = true
	var state: int = random.state
	assert_eq(book.record_visit(visit, tune, QUOTES, random), {})
	assert_eq(random.state, state)
	assert_eq(ReputationBook.score_visit(visit, tune), 0)
	visit.closing = false
	assert_eq(ReputationBook.score_visit(visit, tune), 1)
	var result: Dictionary = book.record_visit(visit, tune, QUOTES, random)
	assert_eq(result["stars"], 1)
	assert_eq(result["cause"], &"never_served")
	assert_false(String(result["quote"]).is_empty())


func test_wait_price_and_dirt_each_lower_a_served_score() -> void:
	var tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	# A substantial single penalty earns three stars and its matching complaint.
	tuning.queue_wait_weight = 2.0
	tuning.food_wait_weight = 2.0
	tuning.overprice_weight = 2.0
	tuning.dirt_weight = 2.0
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	var base: int = ReputationBook.score_visit(visit, tuning)
	assert_eq(base, 5)
	visit.queue_wait_fraction = 1.0
	assert_eq(ReputationBook.score_visit(visit, tuning), 3)
	assert_eq(ReputationBook.cause_of(visit, tuning), &"slow_seating")
	visit.queue_wait_fraction = 0.0
	visit.food_wait_fraction = 1.0
	assert_eq(ReputationBook.score_visit(visit, tuning), 3)
	assert_eq(ReputationBook.cause_of(visit, tuning), &"slow_food")
	visit.food_wait_fraction = 0.0
	visit.price_ratio = 2.0
	assert_eq(ReputationBook.score_visit(visit, tuning), 3)
	assert_eq(ReputationBook.cause_of(visit, tuning), &"too_pricey")
	visit.price_ratio = 1.0
	visit.dirt_fraction = 1.0
	assert_eq(ReputationBook.score_visit(visit, tuning), 3)
	assert_eq(ReputationBook.cause_of(visit, tuning), &"dirty_floor")
	visit.dirt_fraction = 0.0
	visit.price_ratio = 0.8
	assert_eq(ReputationBook.cause_of(visit, tuning), &"great_value")


func test_four_and_five_star_reviews_use_positive_authored_quotes() -> void:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.food_wait_fraction = 0.2
	assert_eq(ReputationBook.score_visit(visit, TUNING), 5)
	assert_eq(ReputationBook.cause_of(visit, TUNING), &"lovely_place")
	visit.food_wait_fraction = 0.8
	assert_eq(ReputationBook.score_visit(visit, TUNING), 4)
	assert_eq(ReputationBook.cause_of(visit, TUNING), &"lovely_place")
	var book: ReputationBook = ReputationBook.new()
	var result: Dictionary = book.record_visit(visit, _certain_tuning(), QUOTES, _random(86005))
	assert_eq(result["stars"], 4)
	assert_eq(result["cause"], &"lovely_place")
	assert_true(QUOTES.groups[&"lovely_place"].has(result["quote"]))
	visit.food_wait_fraction = 0.0
	visit.price_ratio = 0.8
	assert_eq(ReputationBook.cause_of(visit, TUNING), &"great_value")


func test_signature_quote_requires_positive_consumed_context_and_preserves_measured_cause() -> void:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	var ordinary_rng: RandomNumberGenerator = _random(86055)
	var signature_rng: RandomNumberGenerator = _random(86055)
	var ordinary: Dictionary = ReputationBook.new().record_visit(visit, _certain_tuning(),
		QUOTES, ordinary_rng)
	visit.ate_signature_dish = true
	var signature: Dictionary = ReputationBook.new().record_visit(visit, _certain_tuning(),
		QUOTES, signature_rng)
	assert_eq(signature["stars"], ordinary["stars"])
	assert_eq(signature["cause"], ordinary["cause"], "the measured cause is unchanged")
	assert_true(QUOTES.groups[&"signature_dish"].has(signature["quote"]))
	visit.food_wait_fraction = 1.0
	visit.queue_wait_fraction = 1.0
	var poor: Dictionary = ReputationBook.new().record_visit(visit, _certain_tuning(),
		QUOTES, _random(86056))
	assert_true(int(poor["stars"]) < 4)
	assert_false(QUOTES.groups[&"signature_dish"].has(poor["quote"]),
		"a low-scoring served guest cannot praise the signature")


func test_no_signature_visit_keeps_the_original_chance_and_one_quote_draw() -> void:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	var expected_rng: RandomNumberGenerator = _random(86058)
	var actual_rng: RandomNumberGenerator = _random(86058)
	assert_true(expected_rng.randf() < 1.0)
	var cause: StringName = ReputationBook.cause_of(visit, _certain_tuning())
	var used: Dictionary[String, bool] = {}
	var expected_quote: String = QUOTES.pick(cause, expected_rng, used)
	var actual: Dictionary = ReputationBook.new().record_visit(visit, _certain_tuning(),
		QUOTES, actual_rng)
	assert_eq(actual["cause"], cause)
	assert_eq(actual["quote"], expected_quote)
	assert_eq(actual_rng.state, expected_rng.state)


func test_review_visit_records_only_completed_dining_plates_including_a_delivered_side() -> void:
	var sim: RestaurantSim = RestaurantSim.new()
	var guest: CustomerAgent = CustomerAgent.new(sim, _random(86057))
	var main_order: Order = Order.new()
	main_order.recipe_id = &"burger"
	main_order.state = Order.State.DELIVERED
	var side: Order = Order.new()
	side.recipe_id = &"coffee"
	side.state = Order.State.DELIVERED
	guest.order = main_order
	guest.extra_order = side
	guest.paid = true
	assert_true(guest.review_visit(12).consumed_recipe_ids.is_empty(),
		"payment alone is not proof of eating")
	guest._eating = guest.eat_ticks
	assert_eq(guest.review_visit(12).consumed_recipe_ids, [&"burger", &"coffee"])
	side.state = Order.State.CANCELLED
	assert_eq(guest.review_visit(12).consumed_recipe_ids, [&"burger"])
	guest.takeaway = true
	assert_true(guest.review_visit(12).consumed_recipe_ids.is_empty())
	guest.takeaway = false
	guest.paid = false
	assert_true(guest.review_visit(12).consumed_recipe_ids.is_empty())


func test_diffuse_low_penalties_use_positive_threshold_even_at_three_stars() -> void:
	var tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	tuning.queue_wait_weight = 0.45
	tuning.food_wait_weight = 0.45
	tuning.overprice_weight = 0.45
	tuning.dirt_weight = 0.45
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.queue_wait_fraction = 1.0
	visit.food_wait_fraction = 1.0
	visit.price_ratio = 2.0
	visit.dirt_fraction = 1.0
	assert_eq(ReputationBook.score_visit(visit, tuning), 3)
	assert_eq(ReputationBook.cause_of(visit, tuning), &"lovely_place")
	tuning.positive_penalty_threshold = 0.4
	assert_eq(ReputationBook.cause_of(visit, tuning), &"slow_seating")
	tuning.positive_penalty_threshold = -0.1
	assert_false(tuning.is_valid())


func test_virtual_reviews_age_out_and_arrival_curve_has_data_endpoints() -> void:
	var book: ReputationBook = ReputationBook.new()
	assert_eq(book.scores(), [3, 3, 3, 3, 3])
	assert_eq(book.average(), 3.0)
	assert_eq(book.arrival_multiplier(TUNING), 1.0)
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	var tune: ReviewTuning = _certain_tuning()
	var random: RandomNumberGenerator = _random(86002)
	for _index: int in range(30):
		book.record_visit(visit, tune, QUOTES, random)
	assert_eq(book.scores().size(), 30)
	assert_eq(book.average(), 5.0)
	assert_eq(book.arrival_multiplier(TUNING), 1.2)
	var low: ReputationBook = ReputationBook.new()
	var unserved: ReviewVisit = ReviewVisit.new()
	for _index: int in range(30):
		low.record_visit(unserved, tune, QUOTES, random)
	assert_eq(low.average(), 1.0)
	assert_eq(low.arrival_multiplier(TUNING), 0.8)


func test_named_rng_injection_replays_review_and_quote_draws() -> void:
	var first: ReputationBook = ReputationBook.new()
	var repeated: ReputationBook = ReputationBook.new()
	var a: RandomNumberGenerator = _random(86003)
	var b: RandomNumberGenerator = _random(86003)
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.food_wait_fraction = 0.8
	for _index: int in range(40):
		assert_eq(first.record_visit(visit, TUNING, QUOTES, a),
			repeated.record_visit(visit, TUNING, QUOTES, b))
	assert_eq(first.to_dict(), repeated.to_dict())
	assert_eq(a.state, b.state)


func test_positive_quotes_are_unique_until_exhausted_and_replay_per_seed() -> void:
	var first: ReputationBook = ReputationBook.new()
	var replay: ReputationBook = ReputationBook.new()
	var first_rng: RandomNumberGenerator = _random(101001)
	var replay_rng: RandomNumberGenerator = _random(101001)
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	var tuning: ReviewTuning = _certain_tuning()
	var group: PackedStringArray = QUOTES.groups[&"lovely_place"]
	var used: Dictionary[String, bool] = {}
	var first_quote: String = ""
	for index: int in range(group.size() + 1):
		var row: Dictionary = first.record_visit(visit, tuning, QUOTES, first_rng)
		assert_eq(row, replay.record_visit(visit, tuning, QUOTES, replay_rng))
		assert_eq(row["cause"], &"lovely_place")
		var quote: String = row["quote"]
		assert_true(group.has(quote))
		if index == 0:
			first_quote = quote
		if index < group.size():
			assert_false(used.has(quote), "each unused positive line appears once")
			used[quote] = true
		else:
			assert_true(used.has(quote), "exhaustion falls back to a valid repeat")
	assert_eq(used.size(), group.size())
	assert_eq(first_rng.state, replay_rng.state)
	assert_eq(first.scores(), replay.scores())
	assert_eq(first.to_dict().size(), 2, "day-local quote history is not saved")
	first.begin_day()
	first_rng.seed = 101001
	assert_eq(first.record_visit(visit, tuning, QUOTES, first_rng)["quote"], first_quote,
		"a new day may use the same first quote again")


func test_json_roundtrip_and_invalid_decoder_are_transactional() -> void:
	var book: ReputationBook = ReputationBook.new()
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	book.record_visit(visit, _certain_tuning(), QUOTES, _random(86004))
	var saved: Dictionary = book.to_dict()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored: ReputationBook = ReputationBook.new()
	assert_true(restored.from_dict(decoded))
	assert_eq(restored.to_dict(), saved)
	var invalid: Array[Dictionary] = []
	var row: Dictionary = decoded.duplicate(true)
	row["version"] = 2
	invalid.append(row)
	row = decoded.duplicate(true)
	row["scores"] = []
	invalid.append(row)
	row = decoded.duplicate(true)
	row["scores"][0] = 2.5
	invalid.append(row)
	row = decoded.duplicate(true)
	row["scores"][0] = 6
	invalid.append(row)
	row = decoded.duplicate(true)
	row["extra"] = true
	invalid.append(row)
	for document: Dictionary in invalid:
		assert_false(restored.from_dict(document))
		assert_eq(restored.to_dict(), saved)


func _certain_tuning() -> ReviewTuning:
	var tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	tuning.review_chance = 1.0
	return tuning


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random
