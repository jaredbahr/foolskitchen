extends TestCase
## Authored daily weather is deterministic, idempotent and isolated from every other stream.

const TUNING: WeatherTuning = preload("res://data/balance/weather.tres")
## Native randf consumes exponent then mantissa: measured LCG predecessor gives
## raw1=0xd6790899 (CLZ0), raw2=0xffffffff, independently confirmed as1.0.
const RAND_FLOAT_ONE_STATE: int = 6792046047914391429

var _saved_game: Dictionary


func before_each() -> void:
	_saved_game = GameState.call("_capture_save")


func after_each() -> void:
	assert_true(GameState.call("_restore_save", _saved_game))


func test_shipped_weights_are_authored_and_valid() -> void:
	assert_eq(TUNING.resource_path, "res://data/balance/weather.tres")
	assert_eq([TUNING.sunny_weight, TUNING.cloudy_weight, TUNING.rain_weight], [50.0, 30.0, 20.0])
	assert_true(TUNING.is_valid())
	assert_true(TUNING.validate().is_empty())


func test_same_seed_sequence_matches_an_independent_cumulative_weight_oracle() -> void:
	var first: WeatherState = WeatherState.new()
	var second: WeatherState = WeatherState.new()
	var first_rng: RandomNumberGenerator = _rng(241)
	var second_rng: RandomNumberGenerator = _rng(241)
	var oracle: RandomNumberGenerator = _rng(241)
	var kinds: Dictionary[int, bool] = {}
	for day: int in range(1, 65):
		var value: float = oracle.randf() * 100.0
		var expected: int = 0 if value < 50.0 else (1 if value < 80.0 else 2)
		assert_true(first.ensure_today(day, first_rng, TUNING))
		assert_true(second.ensure_today(day, second_rng, TUNING))
		assert_eq(first.kind, expected, "day%d follows the authored50/30/20 thresholds" % day)
		assert_eq(first.kind, second.kind)
		assert_eq(first_rng.state, oracle.state, "exactly one native random sample per new day")
		assert_eq(second_rng.state, oracle.state)
		kinds[first.kind] = true
	assert_eq(kinds.size(), 3, "the fixed sequence exercises every authored weather kind")


func test_same_selected_day_is_idempotent_without_an_extra_random_draw() -> void:
	var state: WeatherState = WeatherState.new()
	var random: RandomNumberGenerator = _rng(201)
	var expected: RandomNumberGenerator = _rng(201)
	expected.randf()
	assert_true(state.needs_selection(1))
	assert_false(state.is_for_day(0))
	assert_true(state.ensure_today(1, random, TUNING))
	assert_eq(random.state, expected.state)
	var snapshot: Dictionary = state.to_dict()
	for repeat: int in 5:
		assert_true(state.ensure_today(1, random, TUNING))
		assert_eq(state.to_dict(), snapshot)
		assert_eq(random.state, expected.state)
	assert_false(state.needs_selection(1))
	assert_true(state.is_for_day(1))
	assert_true(state.needs_selection(2))


func test_invalid_weights_leave_selected_state_and_rng_untouched() -> void:
	var state: WeatherState = WeatherState.new()
	var random: RandomNumberGenerator = _rng(202)
	assert_true(state.ensure_today(1, random, TUNING))
	var snapshot: Dictionary = state.to_dict()
	var before: int = random.state
	for weights: Array in [[0.0, 0.0, 0.0], [-1.0, 30.0, 20.0], [50.0, -1.0, 20.0],
		[50.0, 30.0, -1.0], [NAN, 30.0, 20.0], [50.0, INF, 20.0], [50.0, 30.0, INF],
		[1.0e308, 1.0e308, 1.0e308]]:
		var invalid: WeatherTuning = _weights(weights[0], weights[1], weights[2])
		assert_false(invalid.is_valid())
		assert_false(invalid.validate().is_empty())
		assert_false(state.ensure_today(2, random, invalid))
		assert_eq(state.to_dict(), snapshot)
		assert_eq(random.state, before, "invalid data never consumes a weather sample")


func test_invalid_days_and_missing_dependencies_do_not_mutate_or_draw() -> void:
	var state: WeatherState = WeatherState.new()
	var random: RandomNumberGenerator = _rng(203)
	assert_false(state.ensure_today(0, random, TUNING))
	assert_false(state.ensure_today(-1, random, TUNING))
	assert_eq(state.day, 0)
	assert_true(state.ensure_today(3, random, TUNING))
	var snapshot: Dictionary = state.to_dict()
	var before: int = random.state
	assert_false(state.ensure_today(2, random, TUNING))
	assert_false(state.ensure_today(4, null, TUNING))
	assert_false(state.ensure_today(4, random, null))
	assert_eq(state.to_dict(), snapshot)
	assert_eq(random.state, before)


func test_zero_weight_outcomes_stay_impossible_at_both_native_random_endpoints() -> void:
	for endpoint: int in [0, 1]:
		var native_control: RandomNumberGenerator = _rng(204)
		native_control.state = 0 if endpoint == 0 else RAND_FLOAT_ONE_STATE
		assert_eq(native_control.randf(), float(endpoint), "the pinned native RNG endpoint fixture is independent of weather")
		for only: int in 3:
			var weights: Array[float] = [0.0, 0.0, 0.0]
			weights[only] = 7.0
			var state: WeatherState = WeatherState.new()
			var random: RandomNumberGenerator = _rng(204)
			random.state = 0 if endpoint == 0 else RAND_FLOAT_ONE_STATE
			assert_true(state.ensure_today(1, random, _weights(weights[0], weights[1], weights[2])))
			assert_eq(state.kind, only, "only the nonzero outcome may win, including native1.0")


func test_runtime_weight_changes_are_read_from_the_supplied_data() -> void:
	var state: WeatherState = WeatherState.new()
	var random: RandomNumberGenerator = _rng(205)
	assert_true(state.ensure_today(1, random, _weights(0.0, 9.0, 0.0)))
	assert_eq(state.kind, WeatherState.Kind.CLOUDY)
	assert_true(state.ensure_today(2, random, _weights(0.0, 0.0, 3.0)))
	assert_eq(state.kind, WeatherState.Kind.RAIN)
	assert_true(state.ensure_today(3, random, _weights(2.0, 0.0, 0.0)))
	assert_eq(state.kind, WeatherState.Kind.SUNNY)


func test_json_save_and_copy_keep_the_chosen_day_and_kind_without_drawing() -> void:
	var state: WeatherState = WeatherState.legacy_sunny(7)
	assert_not_null(state)
	assert_eq(state.to_dict(), {"version": 1, "day": 7, "kind": 0})
	var errors: Array[String] = []
	var restored: WeatherState = WeatherState.from_dict(JSON.parse_string(JSON.stringify(
		{"version": 1, "day": 7, "kind": 2})), errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.kind, WeatherState.Kind.RAIN)
	assert_true(restored.is_for_day(7))
	var copied: WeatherState = restored.copy()
	assert_true(copied != restored)
	assert_eq(copied.to_dict(), restored.to_dict())
	copied.kind = WeatherState.Kind.CLOUDY
	assert_eq(restored.kind, WeatherState.Kind.RAIN)


func test_malformed_present_sections_reject_without_touching_input_or_any_stream() -> void:
	var before: Dictionary = GameState.call("_capture_save")
	for malformed: Dictionary in [{}, {"version": 2, "day": 1, "kind": 0},
		{"version": 1, "day": 0, "kind": 0}, {"version": 1, "day": -1, "kind": 0},
		{"version": 1, "day": 1.5, "kind": 0}, {"version": 1, "day": "1", "kind": 0},
		{"version": 1, "day": true, "kind": 0}, {"version": 1, "day": INF, "kind": 0},
		{"version": 1, "day": 1, "kind": -1}, {"version": 1, "day": 1, "kind": 3},
		{"version": 1, "day": 1, "kind": 1.5}, {"version": 1, "day": 1, "kind": "RAIN"},
		{"version": 1, "day": 1, "kind": true}, {"version": 1, "day": 1, "kind": NAN}]:
		var untouched: Dictionary = malformed.duplicate(true)
		var errors: Array[String] = []
		assert_null(WeatherState.from_dict(malformed, errors))
		assert_false(errors.is_empty())
		assert_eq(malformed.keys(), untouched.keys())
		for key: String in untouched:
			var original: Variant = untouched[key]
			var current: Variant = malformed.get(key)
			if original is float and is_nan(original):
				assert_true(current is float and is_nan(current), "validation leaves a supplied NaN untouched")
			else:
				assert_eq(current, original)
	assert_eq(GameState.call("_capture_save"), before)


func test_each_world_owns_a_distinct_fresh_weather_value() -> void:
	var first: SimWorld = SimWorld.new(SimGrid.new(Vector2i(2, 2)))
	var second: SimWorld = SimWorld.new(SimGrid.new(Vector2i(2, 2)))
	assert_not_null(first.weather)
	assert_not_null(second.weather)
	assert_true(first.weather != second.weather)
	assert_eq(first.weather.day, 0)
	assert_true(first.weather.ensure_today(1, _rng(206), _weights(0.0, 0.0, 1.0)))
	assert_eq(first.weather.kind, WeatherState.Kind.RAIN)
	assert_eq(second.weather.day, 0)
	assert_eq(second.weather.kind, WeatherState.Kind.SUNNY)


func test_drawing_weather_never_changes_any_existing_global_stream() -> void:
	GameState.new_run(241)
	for name: StringName in [&"customers", &"reviews", &"cleanliness", &"hiring", &"future_reserved_system"]:
		GameState.rng(name).randf()
	var before: Dictionary = GameState.call("_capture_save")
	var state: WeatherState = WeatherState.new()
	var random: RandomNumberGenerator = _rng(207)
	for day: int in range(1, 21):
		assert_true(state.ensure_today(day, random, TUNING))
	assert_eq(GameState.call("_capture_save"), before, "the pure weather model never fetches or draws another system's RNG")


func test_new_rng_argument_is_used_after_a_caller_stream_reset() -> void:
	var state: WeatherState = WeatherState.new()
	var old: RandomNumberGenerator = _rng(208)
	assert_true(state.ensure_today(1, old, TUNING))
	var old_state: int = old.state
	var current: RandomNumberGenerator = _rng(209)
	var expected: RandomNumberGenerator = _rng(209)
	expected.randf()
	assert_true(state.ensure_today(2, current, TUNING))
	assert_eq(old.state, old_state, "the state never retains the previously supplied RNG")
	assert_eq(current.state, expected.state)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _weights(sunny: float, cloudy: float, rain: float) -> WeatherTuning:
	var tuning: WeatherTuning = WeatherTuning.new()
	tuning.sunny_weight = sunny
	tuning.cloudy_weight = cloudy
	tuning.rain_weight = rain
	return tuning
