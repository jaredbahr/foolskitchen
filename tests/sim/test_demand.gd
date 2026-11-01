extends TestCase
## Literal demand arithmetic and persistent transition contracts.

const AUTHORED: DemandTuning = preload("res://data/balance/demand.tres")


func test_authored_starting_context_has_five_neutral_factors_and_no_hidden_vibe() -> void:
	assert_true(AUTHORED.is_valid())
	# Measured default-service tuning; literal arithmetic fixtures below retain 60.
	assert_almost_eq(AUTHORED.renown_half_saturation, 90.0)
	var result: DemandBreakdown = DemandBreakdown.evaluate(AUTHORED, 3.0, 0.0, 3, 0.0, 1)
	assert_not_null(result)
	if result == null:
		return
	assert_eq(result.to_dict(), {"reputation": 1.0, "word_of_mouth": 1.0,
		"menu": 1.0, "vibe": 1.0, "curb_appeal": 1.0, "total": 1.0})


func test_reputation_uses_both_literal_segments_and_all_three_knots() -> void:
	var tuning: DemandTuning = _tuning()
	for row: Vector2 in [Vector2(1, 0.6), Vector2(2, 0.8), Vector2(3, 1), Vector2(4, 1.3), Vector2(5, 1.6)]:
		var result: DemandBreakdown = DemandBreakdown.evaluate(tuning, row.x, 0.0, 3, 0.0, 1)
		assert_not_null(result)
		if result != null:
			assert_almost_eq(result.reputation, row.y, 0.00001)
			assert_almost_eq(result.total, row.y, 0.00001)


func test_raw_vibe_and_day_one_grace_are_distinct_contexts() -> void:
	var tuning: DemandTuning = _tuning()
	assert_almost_eq(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 0.0, 1).vibe, 1.0)
	assert_almost_eq(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 0.0, 2).vibe, 0.9)
	assert_almost_eq(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 0.0, 10).vibe, 0.9)
	assert_almost_eq(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 100.0, 2).vibe, 1.15)
	assert_almost_eq(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 50.0, 1).vibe, 1.025)
	assert_almost_eq(DemandBreakdown.evaluate(tuning, 1.0, 0.0, 3, 0.0, 2).total, 0.54)


func test_word_of_mouth_is_neutral_then_diminishes_toward_its_literal_limit() -> void:
	var tuning: DemandTuning = _tuning()
	var zero: DemandBreakdown = DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 0.0, 1)
	var half: DemandBreakdown = DemandBreakdown.evaluate(tuning, 3.0, 60.0, 3, 0.0, 1)
	var larger: DemandBreakdown = DemandBreakdown.evaluate(tuning, 3.0, 180.0, 3, 0.0, 1)
	var huge: DemandBreakdown = DemandBreakdown.evaluate(tuning, 3.0, 1.0e300, 3, 0.0, 1)
	assert_almost_eq(zero.word_of_mouth, 1.0)
	assert_almost_eq(half.word_of_mouth, 1.4)
	assert_almost_eq(larger.word_of_mouth, 1.6)
	assert_true(is_finite(huge.word_of_mouth))
	assert_true(huge.word_of_mouth <= 1.8 and huge.word_of_mouth >= larger.word_of_mouth)
	assert_true(half.word_of_mouth - zero.word_of_mouth > larger.word_of_mouth - half.word_of_mouth)


func test_menu_counts_extra_enabled_dishes_with_a_separate_cap() -> void:
	var tuning: DemandTuning = _tuning()
	for row: Vector2 in [Vector2(0, 1), Vector2(3, 1), Vector2(4, 1.04), Vector2(10, 1.28), Vector2(11, 1.3), Vector2(99, 1.3)]:
		var result: DemandBreakdown = DemandBreakdown.evaluate(tuning, 3.0, 0.0, int(row.x), 0.0, 1)
		assert_almost_eq(result.menu, row.y, 0.00001)


func test_factors_multiply_curb_hook_and_total_cap_applies_after_product() -> void:
	var tuning: DemandTuning = _tuning()
	var combined: DemandBreakdown = DemandBreakdown.evaluate(tuning, 4.0, 60.0, 5, 100.0, 2, 1.1)
	# 1.3 * 1.4 * 1.08 * 1.15 * 1.1, independently evaluated arithmetic.
	assert_almost_eq(combined.total, 2.486484, 0.00001)
	assert_almost_eq(combined.curb_appeal, 1.1)
	var capped: DemandBreakdown = DemandBreakdown.evaluate(tuning, 5.0, 1000000.0, 99, 100.0, 2, 2.0)
	assert_almost_eq(capped.total, 3.0)
	assert_true(capped.reputation * capped.word_of_mouth * capped.menu * capped.vibe * capped.curb_appeal > 3.0)


func test_breakdown_dictionary_is_detached_from_the_captured_result() -> void:
	var result: DemandBreakdown = DemandBreakdown.evaluate(_tuning(), 3.0, 0.0, 3, 0.0, 1)
	var snapshot: Dictionary = result.to_dict()
	snapshot["total"] = 0.25
	snapshot["reputation"] = 9.0
	assert_almost_eq(result.total, 1.0)
	assert_almost_eq(result.reputation, 1.0)


func test_invalid_fact_inputs_return_null_without_a_partial_breakdown() -> void:
	var tuning: DemandTuning = _tuning()
	assert_null(DemandBreakdown.evaluate(null, 3.0, 0.0, 3, 0.0, 1))
	for stars: float in [NAN, INF, -1.0, 0.0, 6.0]:
		assert_null(DemandBreakdown.evaluate(tuning, stars, 0.0, 3, 0.0, 1))
	for renown: float in [NAN, INF, -1.0]:
		assert_null(DemandBreakdown.evaluate(tuning, 3.0, renown, 3, 0.0, 1))
	for score: float in [NAN, INF, -1.0, 100.1]:
		assert_null(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, score, 1))
	for curb: float in [NAN, INF, -1.0, 0.0]:
		assert_null(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 0.0, 1, curb))
	assert_null(DemandBreakdown.evaluate(tuning, 3.0, 0.0, -1, 0.0, 1))
	assert_null(DemandBreakdown.evaluate(tuning, 3.0, 0.0, 3, 0.0, 0))


func test_invalid_authored_curves_and_party_data_are_rejected() -> void:
	for field: String in ["renown_per_happy_guest", "renown_daily_decay", "renown_half_saturation",
		"menu_per_extra_dish", "menu_max_bonus", "vibe_min_factor", "vibe_score_max", "total_cap", "party_growth_full_factor"]:
		var tuning: DemandTuning = _tuning()
		tuning.set(field, NAN)
		assert_false(tuning.is_valid(), field)
	var tuning: DemandTuning = _tuning()
	tuning.reputation_stars = PackedFloat32Array([1, 1, 5])
	assert_false(tuning.is_valid())
	tuning = _tuning()
	tuning.reputation_factors = PackedFloat32Array([0.6, 1.6, 1.0])
	assert_false(tuning.is_valid())
	tuning = _tuning()
	tuning.party_size_weights = PackedFloat32Array([0, 0, 0, 0, 0, 0])
	assert_false(tuning.is_valid())
	tuning = _tuning()
	tuning.renown_daily_decay = 1.01
	assert_false(tuning.is_valid())
	tuning = _tuning()
	tuning.party_growth_full_factor = 1.0
	assert_false(tuning.is_valid())


func test_renown_award_and_next_morning_decay_have_independent_idempotent_guards() -> void:
	var tuning: DemandTuning = _tuning()
	var state: DemandState = DemandState.legacy_for_day(1)
	state.renown = 100.0
	assert_true(state.begin_morning(1, tuning))
	assert_almost_eq(state.renown, 100.0, 0.00001)
	assert_true(state.award_close(1, 20, 1.2, tuning))
	assert_almost_eq(state.renown, 120.0)
	assert_eq(state.last_award_day, 1)
	assert_eq(state.last_decay_day, 1)
	assert_true(state.award_close(1, 20, 1.2, tuning))
	assert_almost_eq(state.renown, 120.0, 0.00001)
	assert_true(state.begin_morning(2, tuning))
	assert_almost_eq(state.renown, 114.0, 0.00001)
	assert_eq(state.day, 2)
	assert_eq(state.last_decay_day, 2)
	assert_eq(state.last_service_day, 1)
	assert_almost_eq(state.last_service_factor, 1.2)
	assert_true(state.begin_morning(2, tuning))
	assert_almost_eq(state.renown, 114.0, 0.00001)


func test_legacy_saved_day_has_no_retroactive_decay_and_skips_apply_explicit_exponent() -> void:
	var tuning: DemandTuning = _tuning()
	var legacy: DemandState = DemandState.legacy_for_day(10)
	assert_eq(legacy.day, 10)
	assert_eq(legacy.last_decay_day, 10)
	assert_almost_eq(legacy.renown, 0.0)
	legacy.renown = 100.0
	assert_true(legacy.begin_morning(10, tuning))
	assert_almost_eq(legacy.renown, 100.0)
	assert_true(legacy.begin_morning(12, tuning))
	assert_almost_eq(legacy.renown, 90.25, 0.00001)
	var before: Dictionary = legacy.to_dict()
	assert_false(legacy.begin_morning(11, tuning))
	assert_eq(legacy.to_dict(), before)
	assert_null(DemandState.legacy_for_day(0))


func test_state_json_roundtrip_and_returned_dictionary_are_detached() -> void:
	var state: DemandState = DemandState.legacy_for_day(2)
	state.renown = 57.0
	assert_true(state.award_close(2, 3, 1.25, _tuning()))
	var snapshot: Dictionary = state.to_dict()
	var restored: DemandState = DemandState.new()
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(snapshot))))
	assert_eq(restored.to_dict(), snapshot)
	snapshot["renown"] = 999.0
	assert_almost_eq(state.renown, 60.0)
	assert_almost_eq(restored.renown, 60.0)


func test_malformed_state_rejects_atomically_instead_of_partially_installing() -> void:
	var state: DemandState = DemandState.legacy_for_day(7)
	state.renown = 44.0
	var original: Dictionary = state.to_dict()
	for field: String in ["version", "day", "last_decay_day", "last_award_day", "last_service_day"]:
		for bad: Variant in [true, 1.5, NAN, INF, "7", null]:
			var broken: Dictionary = original.duplicate(true)
			broken[field] = bad
			assert_false(state.from_dict(broken), field)
			assert_eq(state.to_dict(), original, field)
	for field: String in ["renown", "last_service_factor"]:
		for bad: Variant in [true, -1.0, NAN, INF, 1.0e300, "7", null]:
			var broken: Dictionary = original.duplicate(true)
			broken[field] = bad
			assert_false(state.from_dict(broken), field)
			assert_eq(state.to_dict(), original, field)
	for patch: Dictionary in [{"last_decay_day": 6}, {"last_award_day": 8},
		{"last_service_day": 1}, {"last_service_factor": 1.1}]:
		var broken: Dictionary = original.duplicate(true)
		broken.merge(patch, true)
		assert_false(state.from_dict(broken))
		assert_eq(state.to_dict(), original)


func test_invalid_close_and_morning_requests_leave_state_unchanged() -> void:
	var state: DemandState = DemandState.legacy_for_day(3)
	state.renown = 20.0
	var before: Dictionary = state.to_dict()
	assert_false(state.award_close(2, 1, 1.0, _tuning()))
	assert_false(state.award_close(3, -1, 1.0, _tuning()))
	assert_false(state.award_close(3, 1, 0.0, _tuning()))
	assert_false(state.award_close(3, 1, NAN, _tuning()))
	assert_false(state.begin_morning(2, _tuning()))
	assert_false(state.begin_morning(3, null))
	assert_eq(state.to_dict(), before)


func _tuning() -> DemandTuning:
	# Literal fixture calibration, independent of later balance-only data tuning.
	var tuning: DemandTuning = DemandTuning.new()
	tuning.reputation_stars = PackedFloat32Array([1, 3, 5])
	tuning.reputation_factors = PackedFloat32Array([0.6, 1, 1.6])
	tuning.renown_per_happy_guest = 1.0
	tuning.renown_daily_decay = 0.05
	tuning.renown_max_factor = 1.8
	tuning.renown_half_saturation = 60.0
	tuning.starting_dishes = 3
	tuning.menu_per_extra_dish = 0.04
	tuning.menu_max_bonus = 0.30
	tuning.vibe_min_factor = 0.9
	tuning.vibe_max_factor = 1.15
	tuning.vibe_score_max = 100.0
	tuning.intro_days = 1
	tuning.intro_vibe_floor = 1.0
	tuning.total_cap = 3.0
	return tuning
