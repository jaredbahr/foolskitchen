extends TestCase
## FK-335: qualification, lazy odds and saved open-service taper.

const CONFIG: ViralTuning = preload("res://data/balance/viral.tres")
const DEMAND: DemandTuning = preload("res://data/balance/demand.tres")

var _calls: int = 0
var _random: RandomNumberGenerator
var _old_game: Dictionary


func before_each() -> void:
	_calls = 0
	_random = RandomNumberGenerator.new()
	_random.seed = 1234
	_old_game = GameState._capture_save()


func after_each() -> void:
	assert_true(GameState._restore_save(_old_game))


func _provider() -> RandomNumberGenerator:
	_calls += 1
	return _random


func _certain() -> ViralTuning:
	var config: ViralTuning = CONFIG.duplicate(true) as ViralTuning
	config.viral_chance = 1.0
	return config


func test_authored_defaults_and_invalid_tuning() -> void:
	assert_true(CONFIG.is_valid())
	assert_eq(CONFIG.min_served, 25)
	assert_almost_eq(CONFIG.min_happy_share, 0.85)
	assert_almost_eq(CONFIG.viral_chance, 0.15)
	assert_almost_eq(CONFIG.viral_multiplier, 1.35)
	assert_eq(CONFIG.boosted_open_days, 3)
	assert_eq(CONFIG.cooldown_days, 10)
	for field: String in ["min_happy_share", "viral_chance", "viral_multiplier"]:
		var broken: ViralTuning = _certain()
		broken.set(field, NAN)
		assert_false(broken.is_valid(), field)
	var broken: ViralTuning = _certain()
	broken.boosted_open_days = 0
	assert_false(broken.is_valid())


func test_both_thresholds_are_inclusive_and_use_all_guests() -> void:
	var book: ViralReview = ViralReview.new(_certain())
	assert_false(book.close_open_day(1, 24, 0, 24, &"soup", _provider))
	assert_false(book.close_open_day(2, 25, 5, 25, &"soup", _provider), "25/30 is below 85%")
	assert_false(book.close_open_day(3, 25, 0, 21, &"soup", _provider), "21/25 is below 85%")
	assert_eq(_calls, 0, "No stream on any nonqualifying day")
	assert_true(book.close_open_day(4, 34, 6, 34, &"soup", _provider), "34/40 is exactly 85%")
	assert_eq(_calls, 1)
	var minimum: ViralReview = ViralReview.new(_certain())
	assert_true(minimum.close_open_day(1, 25, 0, 25, &"soup", _provider))


func test_zero_chance_and_nonqualifying_named_stream_absence() -> void:
	GameState.new_run(335)
	var config: ViralTuning = CONFIG.duplicate(true) as ViralTuning
	config.viral_chance = 0.0
	var book: ViralReview = ViralReview.new(config)
	assert_false(book.close_open_day(1, 24, 0, 24, &"soup", GameState.rng.bind(&"viral")))
	assert_false((GameState._capture_save()["rngs"] as Dictionary).has("viral"))
	var before: Dictionary = GameState._capture_save()
	book.factor(2)
	book.to_dict()
	assert_eq(GameState._capture_save(), before, "Queries create no stream")
	assert_false(book.close_open_day(2, 25, 0, 25, &"soup", GameState.rng.bind(&"viral")))
	assert_true((GameState._capture_save()["rngs"] as Dictionary).has("viral"))
	assert_eq(book.last_trigger_day, 0)
	assert_eq(book.last_close_day, 2)


func test_three_open_closes_taper_across_calendar_gaps_and_repeated_queries() -> void:
	var book: ViralReview = ViralReview.new(_certain())
	assert_true(book.close_open_day(2, 25, 0, 25, &"soup", _provider))
	assert_almost_eq(book.factor(2), 1.0, 0.00001, "Trigger evening is not boosted")
	var saved: Dictionary = book.to_dict()
	for day: int in [3, 4, 19]:
		assert_almost_eq(book.factor(day), 1.35)
	assert_eq(book.to_dict(), saved, "Calendar queries cannot spend an open day")
	assert_false(book.close_open_day(19, 0, 0, 0, &"", _provider))
	assert_almost_eq(book.factor(19), 1.35, 0.00001, "Closed day's report retains its factor")
	assert_almost_eq(book.factor(20), 1.0 + 0.35 * 2.0 / 3.0)
	assert_false(book.close_open_day(20, 0, 0, 0, &"", _provider))
	assert_almost_eq(book.factor(21), 1.0 + 0.35 / 3.0)
	assert_false(book.close_open_day(23, 0, 0, 0, &"", _provider))
	assert_almost_eq(book.factor(24), 1.0)
	assert_eq(_calls, 1)


func test_duplicate_stale_closes_and_cooldown_boundary_never_redraw() -> void:
	var book: ViralReview = ViralReview.new(_certain())
	assert_true(book.close_open_day(5, 25, 0, 25, &"soup", _provider))
	var saved: Dictionary = book.to_dict()
	assert_false(book.close_open_day(5, 25, 0, 25, &"cake", _provider))
	assert_false(book.close_open_day(4, 25, 0, 25, &"cake", _provider))
	assert_eq(book.to_dict(), saved)
	for day: int in range(6, 15):
		assert_false(book.close_open_day(day, 25, 0, 25, &"cake", _provider))
	assert_eq(_calls, 1, "Day 14 is still inside ten-day trigger interval")
	assert_eq(book.cooldown_remaining(14), 1)
	assert_true(book.close_open_day(15, 25, 0, 25, &"cake", _provider))
	assert_eq(_calls, 2)
	assert_eq(book.dish, &"cake")


func test_seeded_odds_on_independent_qualifying_days() -> void:
	var count: int = 0
	_random.seed = 335031
	for index: int in range(4000):
		var book: ViralReview = ViralReview.new(CONFIG)
		if book.close_open_day(index + 1, 25, 0, 25, &"soup", _provider):
			count += 1
	assert_eq(_calls, 4000)
	assert_true(count >= 510 and count <= 690, "Observed %d of 4000 eligible rolls" % count)


func test_midspell_json_round_trip_and_rng_continuation() -> void:
	GameState.new_run(3351)
	var book: ViralReview = ViralReview.new(_certain())
	assert_true(book.close_open_day(1, 25, 0, 25, &"soup", GameState.rng.bind(&"viral")))
	assert_false(book.close_open_day(2, 0, 0, 0, &"", GameState.rng.bind(&"viral")))
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(book.to_dict())) as Dictionary
	var restored: ViralReview = ViralReview.new(_certain())
	assert_true(restored.from_dict(encoded))
	assert_eq(restored.to_dict(), book.to_dict())
	assert_almost_eq(restored.factor(3), 1.0 + 0.35 * 2.0 / 3.0)
	var random_saved: Dictionary = GameState._capture_save()
	var expected: int = GameState.rng(&"viral").randi()
	assert_true(GameState._restore_save(random_saved))
	assert_eq(GameState.rng(&"viral").randi(), expected)
	assert_true(restored.valid_before_morning(3))
	assert_false(restored.valid_before_morning(2))


func test_malformed_restore_is_atomic_and_capture_is_detached() -> void:
	var book: ViralReview = ViralReview.new(_certain())
	assert_true(book.close_open_day(1, 25, 0, 25, &"soup", _provider))
	var saved: Dictionary = book.to_dict()
	for patch: Dictionary in [{"version": 2}, {"last_close_day": true},
		{"last_trigger_day": 2}, {"days_left": 1}, {"last_close_strength": 1},
		{"last_close_day": 0}, {"dish": 4}, {"days_left": 3.5},
		{"last_close_day": 9007199254740992.0}]:
		var broken: Dictionary = saved.duplicate(true)
		broken.merge(patch, true)
		assert_false(book.from_dict(broken), str(patch))
		assert_eq(book.to_dict(), saved)
	var detached: Dictionary = book.to_dict()
	detached["dish"] = "changed"
	assert_eq(book.dish, &"soup")
	assert_true(ViralReview.new(CONFIG).from_dict(ViralReview.new(CONFIG).to_dict()))


func test_invalid_observations_do_not_mutate_or_request_rng() -> void:
	var book: ViralReview = ViralReview.new(_certain())
	var saved: Dictionary = book.to_dict()
	for row: Array in [[0, 25, 0, 25], [1, -1, 0, 0], [1, 25, -1, 25],
		[1, 25, 0, 26], [1, 9007199254740991, 1, 25]]:
		assert_false(book.close_open_day(row[0], row[1], row[2], row[3], &"soup", _provider))
		assert_eq(book.to_dict(), saved)
	assert_eq(_calls, 0)


func test_demand_uses_separate_factor_once_then_existing_cap() -> void:
	var neutral: DemandBreakdown = DemandBreakdown.evaluate(DEMAND, 3.0, 0.0, 3, 0.0, 1)
	var boosted: DemandBreakdown = DemandBreakdown.evaluate(DEMAND, 3.0, 0.0, 3, 0.0, 1, 1.0, 1.35)
	assert_not_null(neutral)
	assert_not_null(boosted)
	if neutral == null or boosted == null:
		return
	assert_false(neutral.to_dict().has("viral"), "Old neutral shape stays unchanged")
	assert_almost_eq(boosted.total, minf(DEMAND.total_cap, neutral.total * 1.35))
	assert_almost_eq(boosted.curb_appeal, 1.0, 0.00001, "Not hidden in street appeal")
	assert_almost_eq(boosted.to_dict()["viral"], 1.35)
	assert_null(DemandBreakdown.evaluate(DEMAND, 3.0, 0.0, 3, 0.0, 1, 1.0, NAN))
	assert_null(DemandBreakdown.evaluate(DEMAND, 3.0, 0.0, 3, 0.0, 1, 1.0, 0.9))
