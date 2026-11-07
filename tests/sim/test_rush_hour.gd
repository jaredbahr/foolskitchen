extends TestCase
## The planned rush stays seeded, bounded by shop hours and absent from old saves.

const TUNING: RushTuning = preload("res://data/balance/rush_hour.tres")

var _provider_calls: int = 0
var _random: RandomNumberGenerator


func before_each() -> void:
	_provider_calls = 0
	_random = RandomNumberGenerator.new()
	_random.seed = 741


func _provider() -> RandomNumberGenerator:
	_provider_calls += 1
	return _random


func test_tuning_and_issue_defaults() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.unlock_level, 2)
	assert_eq(TUNING.min_gap_days, 4)
	assert_almost_eq(TUNING.daily_chance, 0.2)
	assert_eq(TUNING.min_duration_minutes, 45)
	assert_eq(TUNING.max_duration_minutes, 75)
	assert_eq(TUNING.opening_margin_minutes, 30)
	assert_eq(TUNING.last_orders_margin_minutes, 60)
	assert_eq(TUNING.occasions.size(), 8)


func test_ineligible_level_cooldown_and_short_hours_do_not_ask_for_rng() -> void:
	var book: RushHour = RushHour.new(TUNING)
	book.plan_day(1, 1, 660, 1260, Callable(self, "_provider"))
	assert_eq(_provider_calls, 0)
	assert_eq(book.rolled_day, 1)
	book.last_rush_day = 2
	book.plan_day(5, 2, 660, 1260, Callable(self, "_provider"))
	assert_eq(_provider_calls, 0, "Only three days have elapsed")
	book.plan_day(6, 2, 660, 1260, Callable(self, "_provider"))
	assert_eq(_provider_calls, 1, "Exactly four days have elapsed")
	var short: RushHour = RushHour.new(TUNING)
	short.plan_day(7, 2, 660, 794, Callable(self, "_provider"))
	assert_eq(_provider_calls, 1, "134 minutes cannot fit margins and minimum duration")
	assert_eq(short.rolled_day, 7, "No-event mornings are stamped for load idempotence")


func test_exact_legal_window_and_seeded_plan_round_trip() -> void:
	var config: RushTuning = TUNING.duplicate(true) as RushTuning
	config.daily_chance = 1.0
	var book: RushHour = RushHour.new(config)
	book.plan_day(9, 2, 667, 802, Callable(self, "_provider"))
	assert_eq(_provider_calls, 1)
	assert_true(book.has_event())
	assert_eq(book.start_minute, 697)
	assert_eq(book.duration_minutes, 45)
	assert_eq(book.start_minute - 667, TUNING.opening_margin_minutes)
	assert_eq(802 - (book.start_minute + book.duration_minutes), TUNING.last_orders_margin_minutes)
	assert_eq(book.last_rush_day, 0, "Cooldown starts when the scheduled rush actually begins")
	book.mark_started(9, book.start_minute)
	assert_eq(book.last_rush_day, 9)
	var restored: RushHour = RushHour.new(config)
	assert_true(restored.from_dict(book.to_dict()))
	assert_eq(restored.to_dict(), book.to_dict())
	var calls_after_first_roll: int = _provider_calls
	restored.plan_day(9, 2, 667, 802, Callable(self, "_provider"))
	assert_eq(_provider_calls, calls_after_first_roll)


func test_seeded_odds_are_about_one_in_five_among_eligible_mornings() -> void:
	var config: RushTuning = TUNING.duplicate(true) as RushTuning
	var book: RushHour = RushHour.new(config)
	var count: int = 0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 325134
	var provider: Callable = func() -> RandomNumberGenerator: return random
	for day: int in range(1, 2001):
		book.last_rush_day = day - config.min_gap_days
		book.rolled_day = day - 1
		book.plan_day(day, 2, 660, 1260, provider)
		if book.has_event():
			count += 1
	assert_true(count >= 330 and count <= 470, "Observed %d of 2000 eligible days" % count)


func test_multiplier_has_exact_edges_and_ramps() -> void:
	var book: RushHour = RushHour.new(TUNING)
	book.rolled_day = 1
	book.last_rush_day = 1
	book.occasion = "Book club"
	book.start_minute = 700
	book.duration_minutes = 60
	assert_almost_eq(book.multiplier_at(699), 1.0)
	assert_almost_eq(book.multiplier_at(700), 1.0)
	assert_almost_eq(book.multiplier_at(705), 1.75)
	assert_almost_eq(book.multiplier_at(710), 2.5)
	assert_almost_eq(book.multiplier_at(750), 2.5)
	assert_almost_eq(book.multiplier_at(755), 1.75)
	assert_almost_eq(book.multiplier_at(760), 1.0)
	assert_almost_eq(book.multiplier_at(761), 1.0)


func test_hours_edits_fit_without_redraw_or_cancel_impossible_event() -> void:
	var config: RushTuning = TUNING.duplicate(true) as RushTuning
	config.daily_chance = 1.0
	var book: RushHour = RushHour.new(config)
	book.plan_day(10, 2, 660, 1260, Callable(self, "_provider"))
	var calls: int = _provider_calls
	var old_duration: int = book.duration_minutes
	book.fit_to_hours(720, 900)
	assert_true(book.has_event())
	assert_eq(_provider_calls, calls)
	assert_true(book.start_minute >= 750)
	assert_true(book.start_minute + book.duration_minutes <= 840)
	assert_true(book.duration_minutes <= old_duration)
	book.fit_to_hours(720, 854)
	assert_false(book.has_event(), "No legal window after margins cancels today's notice")
	assert_eq(_provider_calls, calls, "A canceled plan is never redrawn")
	assert_eq(book.last_rush_day, 0, "A canceled morning plan does not start cooldown")
	assert_eq(book.rolled_day, 10)
	var canceled: Dictionary = book.to_dict()
	var loaded: RushHour = RushHour.new(config)
	assert_true(loaded.from_dict(canceled))
	loaded.plan_day(10, 2, 720, 854, Callable(self, "_provider"))
	assert_false(loaded.has_event(), "Reloading a canceled day cannot create a late offer")
	assert_eq(_provider_calls, calls)


func test_countdown_fractional_ramp_and_overshoot_keep_one_tick_contract() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	var spawner: CustomerSpawner = CustomerSpawner.new(random)
	spawner._remaining = 10
	for _tick: int in 3:
		assert_false(spawner.countdown_tick(2.5))
	assert_true(spawner.countdown_tick(2.5))
	assert_eq(spawner._remaining, 0)
	spawner._remaining = 1
	assert_true(spawner.countdown_tick(2.5))
	assert_eq(spawner._remaining, -1, "Tick work carries through this arrival without spawning twice")
	spawner._remaining = 7 + spawner._remaining
	assert_false(spawner.countdown_tick(1.0))
	assert_eq(spawner._remaining, 5, "Outside the event the old one-countdown-tick behavior resumes")
	spawner.min_gap = 1
	spawner.max_gap = 1
	spawner._remaining = 1
	spawner._rush_extra_ticks = 0.0
	assert_true(spawner.countdown_tick(5.0))
	assert_eq(spawner._remaining, -4)
	var expected_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	expected_rng.state = random.state
	expected_rng.randi_range(1, 1)
	spawner.reset_after_arrival(1.0, 1)
	assert_eq(spawner._remaining, 0, "Tiny next gaps saturate at one possible arrival per tick")
	assert_eq(random.state, expected_rng.state, "One arrival draws one next gap, not a sentinel-triggered extra gap")
	assert_true(spawner.countdown_tick(1.0), "A zero next countdown can make at most one arrival on this tick")


func test_actual_cohort_counts_arrivals_and_only_actual_seat_or_patience_losses() -> void:
	var book: RushHour = RushHour.new(TUNING)
	book.rolled_day = 5
	book.last_rush_day = 5
	book.occasion = "Book club"
	book.start_minute = 700
	book.duration_minutes = 60
	assert_true(book.record_arrivals(5, 701, 4))
	assert_false(book.record_arrivals(5, 760, 3))
	book.record_lost(&"no_table")
	book.record_lost(&"waited_too_long")
	book.record_lost(&"closing")
	assert_eq(book.cohort_arrivals, 4)
	assert_eq(book.cohort_lost_no_seat, 1)
	assert_eq(book.cohort_lost_patience, 1)
	assert_eq(book.report_lines().size(), 1)
	assert_true(book.report_lines()[0].contains("4 guests"))
	assert_true(book.report_lines()[0].contains("1 left without a seat"))


func test_restore_is_atomic_and_no_event_save_omits_cohort_fields() -> void:
	var book: RushHour = RushHour.new(TUNING)
	book.plan_day(1, 1, 660, 1260, Callable(self, "_provider"))
	var snapshot: Dictionary = book.to_dict()
	assert_false(snapshot.has("cohort_arrivals"))
	var restored: RushHour = RushHour.new(TUNING)
	assert_true(restored.from_dict(snapshot))
	var provider_calls: int = _provider_calls
	restored.plan_day(1, 2, 660, 1260, Callable(self, "_provider"))
	assert_eq(_provider_calls, provider_calls,
		"A no-event morning stamp prevents a later same-day redraw after load")
	var before: Dictionary = restored.to_dict()
	var bad: Dictionary = snapshot.duplicate(true)
	bad["start_minute"] = 700
	assert_false(restored.from_dict(bad))
	assert_eq(restored.to_dict(), before)
	bad = snapshot.duplicate(true)
	bad["cohort_arrivals"] = 0
	assert_false(restored.from_dict(bad), "No-event states cannot carry event counters")
	assert_eq(restored.to_dict(), before)
