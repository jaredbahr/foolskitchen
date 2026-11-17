extends TestCase
## FK-177: per-run difficulty presets, changes and save decoding.

const TUNING: Resource = preload("res://data/balance/difficulty.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")
const MESSES: MessTuning = preload("res://data/balance/messes.tres")
const CUSTOM_FLAGS: Dictionary[StringName, bool] = {
	&"buy": false,
	&"buy_premium": true,
	&"hire": true,
	&"wages": false,
	&"prices": true,
	&"jobs": false,
}


func test_authored_modes_and_default_normal_balance() -> void:
	assert_true((TUNING as DifficultyTuning).is_valid())
	assert_eq(Difficulty.MODES, [&"easy", &"normal", &"hard", &"custom"])
	var difficulty: Difficulty = Difficulty.new()
	assert_eq(difficulty.mode(), &"normal")
	assert_true(difficulty.auto(&"buy"))
	assert_true(difficulty.auto(&"buy_premium"))
	for key: StringName in [&"hire", &"wages", &"prices", &"jobs"]:
		assert_false(difficulty.auto(key))
	assert_almost_eq(difficulty.mult(&"patience"), 1.0)
	assert_almost_eq(difficulty.mult(&"rent"), 1.0)
	assert_almost_eq(difficulty.mult(&"messes"), 1.0)
	assert_almost_eq(difficulty.review_bonus(), 0.0)
	assert_eq(Difficulty.mode_name(&"easy"), "Easy")
	assert_eq(Difficulty.mode_name(&"normal"), "Normal")
	assert_eq(Difficulty.mode_name(&"hard"), "Hard")
	assert_eq(Difficulty.mode_name(&"custom"), "Custom")
	assert_eq(Difficulty.mode_name(&"other"), "")


func test_easy_and_hard_flags_and_gentle_multipliers() -> void:
	var difficulty: Difficulty = Difficulty.new()
	assert_true(difficulty.start(&"easy"))
	assert_true(difficulty.auto(&"buy"))
	assert_false(difficulty.auto(&"buy_premium"))
	for key: StringName in [&"hire", &"wages", &"prices", &"jobs"]:
		assert_true(difficulty.auto(key))
	assert_almost_eq(difficulty.mult(&"patience"), 1.25)
	assert_almost_eq(difficulty.mult(&"rent"), 0.9)
	assert_almost_eq(difficulty.mult(&"messes"), 0.7)
	assert_almost_eq(difficulty.review_bonus(), 0.2)
	assert_true(difficulty.start(&"hard"))
	for key: StringName in Difficulty.AUTOMATION_KEYS:
		assert_false(difficulty.auto(key))
	assert_almost_eq(difficulty.mult(&"patience"), 0.9)
	assert_almost_eq(difficulty.mult(&"rent"), 1.1)
	assert_almost_eq(difficulty.mult(&"messes"), 1.2)
	assert_almost_eq(difficulty.review_bonus(), -0.1)
	assert_almost_eq(difficulty.mult(&"unknown"), 1.0)
	assert_false(difficulty.auto(&"unknown"))


func test_custom_flags_are_copied_and_use_normal_numbers() -> void:
	var difficulty: Difficulty = Difficulty.new()
	assert_eq(difficulty.selected_custom_flags(), Difficulty.DEFAULT_CUSTOM_FLAGS)
	assert_true(difficulty.start(&"custom", CUSTOM_FLAGS))
	assert_eq(difficulty.mode(), &"custom")
	assert_eq(difficulty.selected_custom_flags(), CUSTOM_FLAGS)
	assert_eq(difficulty.active_custom_flags(), CUSTOM_FLAGS)
	assert_false(difficulty.auto(&"buy"))
	assert_true(difficulty.auto(&"buy_premium"))
	assert_true(difficulty.auto(&"hire"))
	assert_false(difficulty.auto(&"wages"))
	assert_almost_eq(difficulty.mult(&"patience"), 1.0)
	assert_almost_eq(difficulty.mult(&"rent"), 1.0)
	assert_almost_eq(difficulty.mult(&"messes"), 1.0)
	assert_almost_eq(difficulty.review_bonus(), 0.0)
	var protected: Dictionary = difficulty.selected_custom_flags()
	protected[&"buy"] = true
	assert_false(difficulty.auto(&"buy"))
	assert_false(difficulty.start(&"custom", {&"buy": true}), "invalid flags do not change the run")
	assert_eq(difficulty.selected_custom_flags(), CUSTOM_FLAGS)


func test_change_waits_for_effective_morning_and_round_trips() -> void:
	var difficulty: Difficulty = Difficulty.new()
	assert_true(difficulty.request_change(&"custom", CUSTOM_FLAGS, 4))
	assert_eq(difficulty.mode(), &"normal")
	assert_eq(difficulty.pending_mode(), &"custom")
	assert_eq(difficulty.selected_custom_flags(), CUSTOM_FLAGS)
	assert_false(difficulty.apply_morning(3))
	assert_eq(difficulty.for_day(3).mode(), &"normal")
	var forecast: Difficulty = difficulty.for_day(4)
	assert_ne(forecast, difficulty)
	assert_eq(forecast.mode(), &"custom")
	assert_eq(difficulty.mode(), &"normal", "forecast does not mutate the live difficulty")
	var saved: Dictionary = difficulty.to_dict()
	var restored: Difficulty = Difficulty.new()
	assert_true(restored.from_dict(saved))
	assert_eq(restored.to_dict(), saved)
	assert_false(restored.apply_morning(3))
	assert_true(restored.apply_morning(4))
	assert_eq(restored.mode(), &"custom")
	assert_eq(restored.selected_custom_flags(), CUSTOM_FLAGS)
	assert_false(restored.apply_morning(4), "the pending change applies only once")
	assert_true(restored.request_change(&"hard", {}, 5))
	assert_true(restored.request_change(&"custom", CUSTOM_FLAGS, 6), "matching active choice cancels pending")
	assert_true(restored.pending_mode().is_empty())


func test_pending_non_custom_preserves_custom_selection_in_save() -> void:
	var difficulty: Difficulty = Difficulty.new()
	assert_true(difficulty.start(&"custom", CUSTOM_FLAGS))
	assert_true(difficulty.request_change(&"hard", {}, 9))
	var restored: Difficulty = Difficulty.new()
	assert_true(restored.from_dict(difficulty.to_dict()))
	assert_eq(restored.pending_mode(), &"hard")
	assert_eq(restored.selected_custom_flags(), CUSTOM_FLAGS)
	assert_true(restored.apply_morning(9))
	assert_eq(restored.mode(), &"hard")
	assert_eq(restored.selected_custom_flags(), CUSTOM_FLAGS)


func test_old_saves_default_to_normal_and_invalid_data_is_atomic() -> void:
	var difficulty: Difficulty = Difficulty.new()
	assert_true(difficulty.start(&"hard"))
	assert_true(difficulty.from_dict({}))
	assert_eq(difficulty.mode(), &"normal")
	var valid: Dictionary = difficulty.to_dict()
	var invalid_sections: Array[Dictionary] = [
		{"version": 2, "mode": "hard", "custom_flags": _string_flags(CUSTOM_FLAGS)},
		{"version": 1, "mode": "missing", "custom_flags": _string_flags(CUSTOM_FLAGS)},
		{"version": 1, "mode": "easy", "custom_flags": {"buy": true}},
		{"version": 1, "mode": "hard", "custom_flags": _string_flags(CUSTOM_FLAGS), "extra": true},
		{"version": 1.5, "mode": "hard", "custom_flags": _string_flags(CUSTOM_FLAGS)},
		{"version": 1, "mode": "hard", "custom_flags": _string_flags(CUSTOM_FLAGS),
			"pending": {"mode": "easy", "effective_day": 0, "custom_flags": _string_flags(CUSTOM_FLAGS)}},
	]
	for invalid: Dictionary in invalid_sections:
		assert_false(difficulty.from_dict(invalid))
		assert_eq(difficulty.to_dict(), valid, "rejected data leaves state unchanged")
	var json_numbers: Dictionary = valid.duplicate(true)
	json_numbers["version"] = 1.0
	assert_true(difficulty.from_dict(json_numbers), "JSON integer-valued numbers decode")
	assert_eq(difficulty.to_dict(), valid)


func test_difficulty_hooks_scale_guest_patience_review_stars_and_messes() -> void:
	assert_eq(RestaurantSim._difficulty_patience(100, 1.25), 125)
	assert_eq(RestaurantSim._difficulty_patience(100, 0.9), 90)
	assert_eq(RestaurantSim._difficulty_patience(9223372036854775807, 1.25), 9223372036854775807)
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.was_seated = true
	visit.queue_wait_fraction = 0.5
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 5)
	var difficulty: Difficulty = Difficulty.new()
	assert_true(difficulty.start(&"easy"))
	visit.difficulty_review_bonus = difficulty.review_bonus()
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 5)
	assert_true(difficulty.start(&"hard"))
	visit.difficulty_review_bonus = difficulty.review_bonus()
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 4)
	var grid: SimGrid = SimGrid.new(Vector2i(3, 3))
	var dirt: CleanlinessState = CleanlinessState.new(grid, CleanlinessTuning.new(), _random(44))
	assert_almost_eq(dirt._mess_chance(0.5), 0.5)
	dirt.difficulty = difficulty
	assert_almost_eq(dirt._mess_chance(0.5), 0.6)
	var mishap: MishapState = MishapState.new(MESSES, _random(45))
	assert_almost_eq(mishap.spill_chance(false, 0), MESSES.spill_chance_per_cell * 1.2)


static func _string_flags(flags: Dictionary[StringName, bool]) -> Dictionary:
	var result: Dictionary = {}
	for key: StringName in Difficulty.AUTOMATION_KEYS:
		result[String(key)] = flags[key]
	return result


static func _random(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
