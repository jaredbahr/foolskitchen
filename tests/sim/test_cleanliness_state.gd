extends TestCase
## Pure dirt cells, seeded arrival/departure hooks, and day-local effects.

const TUNING: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")


func test_authored_bounds_and_report_words() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.max_spots, 12)
	assert_almost_eq(TUNING.dirt_penalty, 0.3)
	assert_eq(TUNING.clean_work_ticks, 30)
	assert_eq([TUNING.spotless_label, TUNING.messy_label, TUNING.grubby_label],
		["Spotless", "A bit messy", "Grubby"])
	var invalid: CleanlinessTuning = TUNING.duplicate() as CleanlinessTuning
	invalid.arrival_chance = 1.1
	assert_false(invalid.is_valid())
	invalid = TUNING.duplicate() as CleanlinessTuning
	invalid.seat_departure_chance = NAN
	assert_false(invalid.is_valid())
	invalid = TUNING.duplicate() as CleanlinessTuning
	invalid.max_spots = 0
	assert_false(invalid.is_valid())
	invalid = TUNING.duplicate() as CleanlinessTuning
	invalid.dirt_penalty = -0.1
	assert_false(invalid.is_valid())
	invalid = TUNING.duplicate() as CleanlinessTuning
	invalid.grubby_at = invalid.messy_at
	assert_false(invalid.is_valid())
	invalid = TUNING.duplicate() as CleanlinessTuning
	invalid.messy_label = "  "
	assert_false(invalid.is_valid())


func test_seat_spot_is_unique_on_walkable_floor_and_does_not_block_it() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["#####", "#...#", "#.#.#", "#...#", "#####"]))
	var tuning: CleanlinessTuning = _certain_tuning()
	var random: RandomNumberGenerator = _random(78001)
	var dirt: CleanlinessState = CleanlinessState.new(grid, tuning, random)
	var seat: Vector2i = Vector2i(1, 1)
	assert_true(dirt.try_spawn_at_departed_seat(seat))
	assert_true(dirt.has_spot(seat))
	assert_true(grid.is_walkable(seat), "a dirt spot cannot block movement")
	var after_first: int = random.state
	assert_false(dirt.try_spawn_at_departed_seat(seat), "one cell holds at most one spot")
	assert_false(dirt.try_spawn_at_departed_seat(Vector2i(2, 2)), "a wall cannot become dirty")
	assert_false(dirt.try_spawn_at_departed_seat(Vector2i(-1, 0)))
	assert_eq(random.state, after_first, "ineligible cells consume no seeded draw")
	assert_eq(dirt.spots(), [seat] as Array[Vector2i])
	assert_true(dirt.clear_spot(seat))
	assert_false(dirt.clear_spot(seat))
	assert_true(grid.is_walkable(seat))


func test_named_rng_can_rebind_only_before_dirt_and_without_a_draw() -> void:
	var original: RandomNumberGenerator = _random(78011)
	var named: RandomNumberGenerator = _random(78012)
	var next_day: RandomNumberGenerator = _random(78013)
	var original_state: int = original.state
	var named_state: int = named.state
	var dirt: CleanlinessState = CleanlinessState.new(
		SimGrid.new(Vector2i(3, 3)), _certain_tuning(), original)
	assert_false(dirt.use_rng(null))
	assert_true(dirt.use_rng(named))
	assert_true(dirt.get("_rng") == named)
	assert_eq(original.state, original_state)
	assert_eq(named.state, named_state, "rebinding consumes no seeded draw")
	assert_true(dirt.try_spawn_at_departed_seat(Vector2i(1, 1)))
	var occupied_state: int = named.state
	assert_false(dirt.use_rng(next_day), "an occupied day keeps its stream")
	assert_true(dirt.clear_spot(Vector2i(1, 1)))
	assert_false(dirt.use_rng(next_day), "cleaning cannot reset a day's history")
	assert_true(dirt.get("_rng") == named)
	assert_eq(named.state, occupied_state)
	dirt.tidy_overnight()
	var next_state: int = next_day.state
	assert_true(dirt.use_rng(next_day))
	assert_true(dirt.get("_rng") == next_day)
	assert_eq(next_day.state, next_state)


func test_arrival_uses_sorted_free_floor_neighbours_and_respects_capacity() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["#####", "#.E.#", "#####"]))
	var tuning: CleanlinessTuning = _certain_tuning()
	tuning.max_spots = 2
	tuning.grubby_at = 2
	var random: RandomNumberGenerator = _random(78002)
	var dirt: CleanlinessState = CleanlinessState.new(grid, tuning, random)
	var entry: Vector2i = Vector2i(2, 1)
	var first: Vector2i = dirt.try_spawn_on_arrival(entry)
	assert_true([Vector2i(1, 1), Vector2i(3, 1)].has(first))
	var second: Vector2i = dirt.try_spawn_on_arrival(entry)
	assert_ne(second, first)
	assert_true([Vector2i(1, 1), Vector2i(3, 1)].has(second))
	assert_eq(dirt.spots(), [Vector2i(1, 1), Vector2i(3, 1)] as Array[Vector2i])
	var at_cap: int = random.state
	assert_eq(dirt.try_spawn_on_arrival(entry), SimGrid.NO_CELL)
	assert_false(dirt.try_spawn_at_departed_seat(Vector2i(1, 1)))
	assert_eq(random.state, at_cap)
	assert_eq(dirt.spot_count(), 2)
	assert_eq(dirt.try_spawn_on_arrival(Vector2i(1, 1)), SimGrid.NO_CELL,
		"an ordinary floor cell is not a street entry")


func test_same_seed_replays_arrival_and_seat_spawns_without_a_global_rng() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["#####", "#.E.#", "#...#", "#####"]))
	var tuning: CleanlinessTuning = TUNING.duplicate() as CleanlinessTuning
	tuning.arrival_chance = 0.5
	tuning.seat_departure_chance = 0.5
	var first_rng: RandomNumberGenerator = _random(78003)
	var second_rng: RandomNumberGenerator = _random(78003)
	var first: CleanlinessState = CleanlinessState.new(grid, tuning, first_rng)
	var second: CleanlinessState = CleanlinessState.new(grid, tuning, second_rng)
	var first_results: Array[Vector2i] = []
	var second_results: Array[Vector2i] = []
	for index: int in range(12):
		first_results.append(first.try_spawn_on_arrival(Vector2i(2, 1)))
		second_results.append(second.try_spawn_on_arrival(Vector2i(2, 1)))
		var seat: Vector2i = Vector2i(1 + index % 3, 2)
		assert_eq(first.try_spawn_at_departed_seat(seat), second.try_spawn_at_departed_seat(seat))
	assert_eq(first_results, second_results)
	assert_eq(first.spots(), second.spots())
	assert_eq(first_rng.state, second_rng.state)


func test_worst_daily_band_and_patience_sample_survive_cleaning_until_overnight() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(4, 2))
	var tuning: CleanlinessTuning = _certain_tuning()
	tuning.max_spots = 4
	tuning.grubby_at = 3
	var dirt: CleanlinessState = CleanlinessState.new(grid, tuning, _random(78004))
	assert_eq(dirt.worst_category(), CleanlinessState.Band.SPOTLESS)
	assert_eq(dirt.worst_category_label(), "Spotless")
	assert_almost_eq(dirt.patience_multiplier(), 1.0)
	assert_true(dirt.try_spawn_at_departed_seat(Vector2i(2, 0)))
	assert_eq(dirt.worst_category(), CleanlinessState.Band.A_BIT_MESSY)
	assert_eq(dirt.worst_category_label(), "A bit messy")
	var sampled_at_arrival: float = dirt.patience_multiplier()
	assert_almost_eq(sampled_at_arrival, 0.925)
	assert_true(dirt.try_spawn_at_departed_seat(Vector2i(0, 1)))
	assert_true(dirt.try_spawn_at_departed_seat(Vector2i(1, 0)))
	assert_almost_eq(dirt.dirt_fraction(), 0.75)
	assert_almost_eq(dirt.patience_multiplier(), 0.775)
	assert_almost_eq(sampled_at_arrival, 0.925, 0.0001,
		"an existing guest keeps their arrival sample")
	assert_eq(dirt.worst_today_count(), 3)
	assert_eq(dirt.worst_category(), CleanlinessState.Band.GRUBBY)
	assert_eq(dirt.worst_category_label(), "Grubby")
	assert_true(dirt.clear_spot(Vector2i(2, 0)))
	assert_true(dirt.clear_spot(Vector2i(0, 1)))
	assert_true(dirt.clear_spot(Vector2i(1, 0)))
	assert_eq(dirt.spot_count(), 0)
	assert_eq(dirt.worst_today_count(), 3, "cleaning cannot rewrite the evening's worst moment")
	assert_eq(dirt.worst_category_label(), "Grubby")
	dirt.tidy_overnight()
	assert_eq(dirt.spot_count(), 0)
	assert_eq(dirt.worst_today_count(), 0)
	assert_eq(dirt.worst_category_label(), "Spotless")


func _certain_tuning() -> CleanlinessTuning:
	var tuning: CleanlinessTuning = TUNING.duplicate() as CleanlinessTuning
	tuning.arrival_chance = 1.0
	tuning.seat_departure_chance = 1.0
	return tuning


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random
