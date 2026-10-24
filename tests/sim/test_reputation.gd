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
