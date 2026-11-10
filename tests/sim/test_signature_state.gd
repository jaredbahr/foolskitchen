extends TestCase
## Signature progression is pure: known paid dishes, explicit phase/day and
## detached versioned state. No menu unlock, save service or RNG participates.

const AUTHORED: SignatureTuning = preload("res://data/balance/signature.tres")


func test_authored_values_and_unspecified_signature_are_neutral() -> void:
	assert_true(AUTHORED.is_valid())
	assert_eq(AUTHORED.signature_unlock_sales, 150)
	assert_almost_eq(AUTHORED.signature_demand_bonus, 1.05)
	assert_eq(AUTHORED.change_cooldown_days, 7)
	var state: SignatureState = _state()
	assert_eq(state.to_dict(), {"version": 1, "sales": {}, "signature_id": "", "last_change_day": 0})
	assert_eq(state.signature_recipe_id(), &"")
	assert_eq(state.sales_for(&"burger"), 0)
	assert_eq(state.sales_for(&"unknown"), 0)
	assert_eq(state.demand_factor(_ids(), AUTHORED), 1.0)
	assert_true(state.record_sale(&"burger", 300))
	assert_true(state.eligible(&"burger", AUTHORED))
	assert_eq(state.signature_recipe_id(), &"", "passing the threshold never auto-selects")
	assert_eq(state.demand_factor(_ids(), AUTHORED), 1.0)


func test_lifetime_paid_counts_are_per_known_recipe_and_checked() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger"))
	assert_true(state.record_sale(&"burger", 148))
	assert_true(state.record_sale(&"tomato_soup", 3))
	assert_eq(state.sales_for(&"burger"), 149)
	assert_eq(state.sales_for(&"tomato_soup"), 3)
	assert_eq(state.sales_for(&"fries"), 0)
	var before: Dictionary = state.to_dict()
	assert_false(state.record_sale(&"unknown", 150))
	assert_false(state.record_sale(&"", 150))
	assert_false(state.record_sale(&"burger", 0))
	assert_false(state.record_sale(&"burger", -1))
	assert_eq(state.to_dict(), before)


func test_149_is_locked_and_150_selects_immediately_only_in_morning() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 149))
	assert_false(state.eligible(&"burger", AUTHORED))
	assert_false(state.select(&"burger", 1, SimClock.Phase.MORNING, AUTHORED))
	assert_true(state.record_sale(&"burger"))
	assert_true(state.eligible(&"burger", AUTHORED))
	var before: Dictionary = state.to_dict()
	for phase: int in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED, -1, 99]:
		assert_false(state.can_select(&"burger", 1, phase, AUTHORED))
		assert_false(state.select(&"burger", 1, phase, AUTHORED))
		assert_eq(state.to_dict(), before)
	assert_false(state.select(&"burger", 0, SimClock.Phase.MORNING, AUTHORED))
	assert_true(state.select(&"burger", 1, SimClock.Phase.MORNING, AUTHORED))
	assert_eq(state.signature_recipe_id(), &"burger")
	assert_eq(state.last_changed_day(), 1)


func test_exact_seven_day_change_boundary_leaves_only_one_signature() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 150))
	assert_true(state.record_sale(&"fries", 150))
	assert_true(state.select(&"burger", 3, SimClock.Phase.MORNING, AUTHORED))
	var before: Dictionary = state.to_dict()
	assert_false(state.select(&"fries", 9, SimClock.Phase.MORNING, AUTHORED), "day+6")
	assert_eq(state.to_dict(), before)
	assert_false(state.select(&"fries", 10, SimClock.Phase.OPEN, AUTHORED))
	assert_true(state.select(&"fries", 10, SimClock.Phase.MORNING, AUTHORED), "day+7")
	assert_eq(state.signature_recipe_id(), &"fries")
	assert_eq(state.last_changed_day(), 10)
	assert_eq(state.demand_factor([&"burger"], AUTHORED), 1.0)
	assert_almost_eq(state.demand_factor([&"burger", &"fries"], AUTHORED), 1.05)
	assert_false(state.select(&"burger", 16, SimClock.Phase.MORNING, AUTHORED))
	assert_true(state.select(&"burger", 17, SimClock.Phase.MORNING, AUTHORED))


func test_same_choice_is_idempotent_and_cannot_restart_or_bypass_cooldown() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 150))
	assert_true(state.record_sale(&"fries", 150))
	assert_true(state.select(&"burger", 3, SimClock.Phase.MORNING, AUTHORED))
	assert_true(state.select(&"burger", 8, SimClock.Phase.MORNING, AUTHORED))
	assert_eq(state.last_changed_day(), 3)
	assert_false(state.select(&"burger", 2, SimClock.Phase.MORNING, AUTHORED))
	assert_false(state.select(&"burger", SignatureState.MAX_EXACT_INTEGER + 1, SimClock.Phase.MORNING, AUTHORED))
	assert_false(state.select(&"burger", 9, SimClock.Phase.CLOSED, AUTHORED))
	assert_false(state.select(&"fries", 9, SimClock.Phase.MORNING, AUTHORED))
	assert_true(state.select(&"fries", 10, SimClock.Phase.MORNING, AUTHORED))


func test_disabled_signature_is_kept_and_factor_queries_are_read_only() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 150))
	assert_true(state.select(&"burger", 1, SimClock.Phase.MORNING, AUTHORED))
	var before: Dictionary = state.to_dict()
	var menu: Array[StringName] = [&"fries", &"unknown"]
	assert_eq(state.demand_factor(menu, AUTHORED), 1.0)
	assert_eq(state.signature_recipe_id(), &"burger")
	var expected_menu: Array[StringName] = [&"fries", &"unknown"]
	assert_eq(menu, expected_menu)
	assert_almost_eq(state.demand_factor([&"burger"], AUTHORED), 1.05)
	assert_almost_eq(state.demand_factor([&"burger", &"burger"], AUTHORED), 1.05)
	assert_eq(state.to_dict(), before)


func test_full_catalogue_is_owned_and_independent_of_cookable_menu() -> void:
	var catalogue: Array[StringName] = _ids()
	var state: SignatureState = SignatureState.new(catalogue)
	catalogue.clear()
	catalogue.append(&"unknown")
	# Wine is a known later recipe, regardless of the current enabled menu.
	assert_true(state.record_sale(&"wine", 150))
	assert_true(state.eligible(&"wine", AUTHORED))
	assert_true(state.select(&"wine", 1, SimClock.Phase.MORNING, AUTHORED))
	assert_false(state.record_sale(&"unknown", 150))
	assert_eq(state.demand_factor([&"burger"], AUTHORED), 1.0)
	assert_almost_eq(state.demand_factor([&"wine"], AUTHORED), 1.05)


func test_counts_selection_and_cooldown_survive_native_and_json_restore() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 165))
	assert_true(state.record_sale(&"fries", 150))
	assert_true(state.select(&"burger", 4, SimClock.Phase.MORNING, AUTHORED))
	var before: Dictionary = state.to_dict()
	for payload: Variant in [before, JSON.parse_string(JSON.stringify(before))]:
		var loaded: SignatureState = _state()
		assert_true(loaded.from_dict(payload, 10, AUTHORED))
		assert_eq(loaded.to_dict(), before)
		assert_eq(loaded.sales_for(&"burger"), 165)
		assert_eq(loaded.signature_recipe_id(), &"burger")
		assert_false(loaded.select(&"fries", 10, SimClock.Phase.MORNING, AUTHORED))
		assert_true(loaded.select(&"fries", 11, SimClock.Phase.MORNING, AUTHORED))
	assert_eq(state.to_dict(), before)


func test_input_and_returned_counter_dictionaries_never_alias_state() -> void:
	var source: Dictionary = {"version": 1, "sales": {"burger": 150}, "signature_id": "burger", "last_change_day": 2}
	var state: SignatureState = _state()
	assert_true(state.from_dict(source, 2, AUTHORED))
	var before: Dictionary = state.to_dict()
	source["sales"]["burger"] = 999
	source["signature_id"] = "fries"
	var counts: Dictionary[StringName, int] = state.lifetime_sales()
	counts[&"burger"] = 0
	counts[&"unknown"] = 500
	var snapshot: Dictionary = state.to_dict()
	snapshot["sales"]["burger"] = 0
	snapshot["signature_id"] = ""
	assert_eq(state.to_dict(), before)
	assert_eq(state.sales_for(&"burger"), 150)


func test_count_overflow_is_rejected_without_mutation_and_exact_json_max_restores() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", SignatureState.MAX_EXACT_INTEGER))
	var before: Dictionary = state.to_dict()
	assert_false(state.record_sale(&"burger"))
	assert_false(state.record_sale(&"fries", SignatureState.MAX_EXACT_INTEGER + 1))
	assert_eq(state.to_dict(), before)
	var loaded: SignatureState = _state()
	assert_true(loaded.from_dict(JSON.parse_string(JSON.stringify(before)), 1, AUTHORED))
	assert_eq(loaded.sales_for(&"burger"), SignatureState.MAX_EXACT_INTEGER)
	assert_eq(loaded.to_dict(), before)


func test_json_whole_floats_are_valid_but_booleans_and_fractional_numbers_are_not() -> void:
	var state: SignatureState = _state()
	assert_true(state.from_dict({"version": 1.0, "sales": {"burger": 150.0, "fries": 0.0},
		"signature_id": "burger", "last_change_day": 3.0}, 3, AUTHORED))
	assert_eq(state.to_dict(), {"version": 1, "sales": {"burger": 150, "fries": 0},
		"signature_id": "burger", "last_change_day": 3})
	for value: Variant in [true, false, -1, 1.5, "150", NAN, INF, SignatureState.MAX_EXACT_INTEGER + 1]:
		var bad: Dictionary = state.to_dict()
		bad["sales"]["burger"] = value
		_reject_unchanged(state, bad, 3)


func test_malformed_restore_rejects_atomically_with_existing_state() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 180))
	assert_true(state.select(&"burger", 2, SimClock.Phase.MORNING, AUTHORED))
	for value: Variant in [null, [], true, 1, {}, {"version": 1}]:
		_reject_unchanged(state, value, 2)
	for field: String in ["version", "sales", "signature_id", "last_change_day"]:
		var missing: Dictionary = state.to_dict()
		missing.erase(field)
		_reject_unchanged(state, missing, 2)
	for value: Variant in [true, false, 0, 2, 1.5, "1", NAN, INF]:
		var bad: Dictionary = state.to_dict()
		bad["version"] = value
		_reject_unchanged(state, bad, 2)
	for counts: Variant in [null, [], {"unknown": 150}, {"": 150}, {17: 150}, {&"burger": 150}]:
		var bad: Dictionary = state.to_dict()
		bad["sales"] = counts
		_reject_unchanged(state, bad, 2)
	for recipe: Variant in [true, 1, &"burger", "unknown", ""]:
		var bad: Dictionary = state.to_dict()
		bad["signature_id"] = recipe
		_reject_unchanged(state, bad, 2)
	for day: Variant in [true, -1, 0, 1.5, 3, "2", NAN, INF]:
		var bad: Dictionary = state.to_dict()
		bad["last_change_day"] = day
		_reject_unchanged(state, bad, 2)
	var empty_with_day: Dictionary = {"version": 1, "sales": {}, "signature_id": "", "last_change_day": 1}
	_reject_unchanged(state, empty_with_day, 2)
	var extra: Dictionary = state.to_dict()
	extra["unrecognized"] = 1
	_reject_unchanged(state, extra, 2)
	_reject_unchanged(state, state.to_dict(), 0)
	_reject_unchanged(state, state.to_dict(), SignatureState.MAX_EXACT_INTEGER + 1)


func test_authored_tuning_controls_threshold_factor_and_change_interval() -> void:
	var tuning: SignatureTuning = SignatureTuning.new()
	tuning.signature_unlock_sales = 2
	tuning.signature_demand_bonus = 1.10
	tuning.change_cooldown_days = 2
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 2))
	assert_true(state.record_sale(&"fries", 2))
	assert_true(state.select(&"burger", 4, SimClock.Phase.MORNING, tuning))
	assert_almost_eq(state.demand_factor([&"burger"], tuning), 1.10)
	assert_false(state.select(&"fries", 5, SimClock.Phase.MORNING, tuning))
	assert_true(state.select(&"fries", 6, SimClock.Phase.MORNING, tuning))


func test_invalid_tuning_is_neutral_and_rejects_mutations_atomically() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 150))
	assert_true(state.select(&"burger", 1, SimClock.Phase.MORNING, AUTHORED))
	var before: Dictionary = state.to_dict()
	assert_false(state.select(&"burger", 1, SimClock.Phase.MORNING, null))
	assert_false(state.from_dict(before, 1, null))
	assert_eq(state.demand_factor([&"burger"], null), 1.0)
	for bonus: float in [NAN, INF, -1.0, 0.0, 0.99]:
		var tuning: SignatureTuning = SignatureTuning.new()
		tuning.signature_demand_bonus = bonus
		assert_false(tuning.is_valid())
		assert_false(state.select(&"burger", 1, SimClock.Phase.MORNING, tuning))
		assert_false(state.from_dict(before, 1, tuning))
		assert_eq(state.demand_factor([&"burger"], tuning), 1.0)
		assert_eq(state.to_dict(), before)
	var tuning: SignatureTuning = SignatureTuning.new()
	tuning.signature_unlock_sales = 0
	assert_false(tuning.is_valid())
	tuning.signature_unlock_sales = 150
	tuning.change_cooldown_days = 0
	assert_false(tuning.is_valid())
	assert_false(state.select(&"burger", 2, SimClock.Phase.MORNING, tuning))
	tuning.change_cooldown_days = SignatureState.MAX_EXACT_INTEGER + 1
	assert_false(tuning.is_valid())
	tuning.change_cooldown_days = 7
	tuning.signature_unlock_sales = SignatureState.MAX_EXACT_INTEGER + 1
	assert_false(tuning.is_valid())
	assert_eq(state.to_dict(), before)


func test_clear_resets_progress_but_keeps_catalogue_and_initial_choice_immediate() -> void:
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 150))
	assert_true(state.select(&"burger", 100, SimClock.Phase.MORNING, AUTHORED))
	state.clear()
	assert_eq(state.to_dict(), {"version": 1, "sales": {}, "signature_id": "", "last_change_day": 0})
	assert_eq(state.demand_factor(_ids(), AUTHORED), 1.0)
	assert_true(state.record_sale(&"fries", 150))
	assert_true(state.select(&"fries", 1, SimClock.Phase.MORNING, AUTHORED))
	assert_false(state.record_sale(&"unknown", 150))


func _reject_unchanged(state: SignatureState, payload: Variant, day: int) -> void:
	var before: Dictionary = state.to_dict()
	assert_false(state.from_dict(payload, day, AUTHORED))
	assert_eq(state.to_dict(), before)


func _state() -> SignatureState:
	return SignatureState.new(_ids())


func _ids() -> Array[StringName]:
	return [&"burger", &"tomato_soup", &"fries", &"wine"]


func test_a_signature_saved_under_a_lower_threshold_still_loads() -> void:
	var low: SignatureTuning = SignatureTuning.new()
	low.signature_unlock_sales = 2
	var state: SignatureState = _state()
	assert_true(state.record_sale(&"burger", 2))
	assert_true(state.select(&"burger", 4, SimClock.Phase.MORNING, low))
	var restored: SignatureState = _state()
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), 4, AUTHORED),
		"raising the threshold later keeps the saved choice")
	assert_eq(restored.to_dict(), state.to_dict())
