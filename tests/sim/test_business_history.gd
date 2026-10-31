extends TestCase
## Closing summaries preserve paid-food value, exact signed cash and save isolation.

var _history: BusinessHistory


func before_each() -> void:
	_history = BusinessHistory.new()


func test_record_reads_paid_food_profit_cash_and_reputation_without_mutating_report() -> void:
	var report: DayReport = _report(1)
	var before: Dictionary = report.to_dict()
	_history.record(report)
	assert_eq(_history.summaries(), [{"day": 1, "served": 8, "lost": 2,
		"dish_profit": 45, "dish_profit_recorded": true, "cash_change": 80,
		"reputation": 4.25}])
	assert_eq(report.to_dict(), before, "history is a read-only consumer of the closing report")


func test_fifteen_closes_keep_fourteen_newest_in_day_order() -> void:
	for day: int in range(1, 16):
		_history.record(_report(day))
	var rows: Array[Dictionary] = _history.summaries()
	assert_eq(rows.size(), 14)
	for index: int in rows.size():
		assert_eq(rows[index]["day"], index + 2)


func test_same_day_upsert_updates_cash_without_duplication_and_stale_days_are_ignored() -> void:
	_history.record(_report(4))
	var today: DayReport = _report(5)
	_history.record(today)
	today.income[Ledger.SALE] = 120
	today.customers_served = 10
	_history.record(today)
	var rows: Array[Dictionary] = _history.summaries()
	assert_eq(rows.size(), 2)
	assert_eq(rows[1]["served"], 10)
	assert_eq(rows[1]["cash_change"], 100)
	assert_eq(rows[1]["dish_profit"], 65)
	_history.record(_report(3))
	_history.record(_report(4))
	assert_eq(_history.summaries(), rows, "stale earlier reports cannot rewrite saved days")


func test_unknown_paid_food_value_stays_unknown_despite_a_cash_basis_fallback() -> void:
	var report: DayReport = _report(1)
	report.stock_values_recorded = false
	report.food_cost_recorded = false
	assert_false(report.operating_profit_recorded())
	assert_eq(report.operating_profit(), 30, "the existing legacy method has a different basis")
	_history.record(report)
	var row: Dictionary = _history.summaries()[0]
	assert_false(row["dish_profit_recorded"], "zero is only an unknown placeholder")
	assert_eq(row["dish_profit"], 0)
	assert_eq(row["cash_change"], 80)
	var restored: BusinessHistory = BusinessHistory.new()
	assert_true(restored.restore(_history.capture()))
	assert_false(restored.summaries()[0]["dish_profit_recorded"])


func test_record_and_all_returned_views_are_detached() -> void:
	var report: DayReport = _report(1)
	_history.record(report)
	var expected: Array[Dictionary] = _history.summaries()
	report.customers_served = 100
	report.income.clear()
	var rows: Array[Dictionary] = _history.summaries()
	rows[0]["served"] = 99
	rows.clear()
	var recent: Array[Dictionary] = _history.recent()
	recent[0]["cash_change"] = -999
	var saved: Dictionary = _history.capture()
	saved["days"][0]["reputation"] = 0.0
	saved["days"].clear()
	assert_eq(_history.summaries(), expected)


func test_recent_defaults_to_seven_and_handles_zero_negative_and_large_limits() -> void:
	for day: int in range(1, 16):
		_history.record(_report(day))
	assert_eq(_history.recent().size(), 7)
	assert_eq(_history.recent()[0]["day"], 9)
	assert_eq(_history.recent(1)[0]["day"], 15)
	assert_eq(_history.recent(0), [])
	assert_eq(_history.recent(-1), [])
	assert_eq(_history.recent(BusinessHistory.MAX_MONEY), _history.summaries())


func test_capture_has_version_and_only_lightweight_summary_fields() -> void:
	_history.record(_report(1))
	var saved: Dictionary = _history.capture()
	assert_eq(saved, {"version": 1, "days": [{"day": 1, "served": 8, "lost": 2,
		"dish_profit": "45", "dish_profit_recorded": true, "cash_change": "80",
		"reputation": 4.25}]})
	var restored: BusinessHistory = BusinessHistory.new()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	assert_true(restored.restore(decoded), "whole JSON floats restore to typed runtime counts")
	assert_eq(restored.summaries(), _history.summaries())
	assert_eq(typeof(restored.summaries()[0]["day"]), TYPE_INT)
	assert_eq(typeof(restored.summaries()[0]["reputation"]), TYPE_FLOAT)


func test_missing_legacy_history_and_explicit_empty_section_clear_successfully() -> void:
	_history.record(_report(1))
	assert_true(_history.restore({}))
	assert_eq(_history.summaries(), [])
	assert_true(_history.valid_before(1))
	_history.record(_report(1))
	assert_true(_history.restore({"version": 1, "days": []}))
	assert_eq(_history.capture(), {"version": 1, "days": []})


func test_malformed_present_sections_fail_without_clearing_existing_history() -> void:
	_history.record(_report(7))
	var expected: Array[Dictionary] = _history.summaries()
	for data: Dictionary in [{"version": 1}, {"days": []},
			{"version": 2, "days": []}, {"version": true, "days": []},
			{"version": "1", "days": []}, {"version": 1.5, "days": []},
			{"version": 1, "days": {}}, {"version": 1, "days": [null]}]:
		assert_false(_history.restore(data))
		assert_eq(_history.summaries(), expected)


func test_restore_is_atomic_when_a_later_row_is_invalid() -> void:
	_history.record(_report(7))
	var expected: Array[Dictionary] = _history.summaries()
	var invalid: Dictionary = _saved_row(21)
	invalid["served"] = -1
	assert_false(_history.restore({"version": 1, "days": [_saved_row(20), invalid]}))
	assert_eq(_history.summaries(), expected)


func test_duplicate_and_out_of_order_days_are_rejected_without_sorting_or_mutation() -> void:
	_history.record(_report(7))
	var expected: Array[Dictionary] = _history.summaries()
	for days: Array in [[_saved_row(2), _saved_row(2)],
			[_saved_row(3), _saved_row(1), _saved_row(2)]]:
		assert_false(_history.restore({"version": 1, "days": days}))
		assert_eq(_history.summaries(), expected)


func test_restore_retains_newest_fourteen_but_validates_discarded_older_rows() -> void:
	var days: Array[Dictionary] = []
	for day: int in range(1, 21):
		days.append(_saved_row(day))
	assert_true(_history.restore({"version": 1, "days": days}))
	assert_eq(_history.summaries().size(), 14)
	assert_eq(_history.summaries()[0]["day"], 7)
	assert_eq(_history.summaries()[13]["day"], 20)
	var expected: Array[Dictionary] = _history.summaries()
	days[0]["lost"] = -1
	assert_false(_history.restore({"version": 1, "days": days}))
	assert_eq(_history.summaries(), expected, "invalid discarded rows cannot be silently skipped")


func test_restore_detaches_input_and_discards_unrelated_payload_fields() -> void:
	var row: Dictionary = _saved_row(1)
	row["unrelated"] = {"mutable": [1, 2, 3]}
	var data: Dictionary = {"version": 1, "days": [row], "extra": true}
	assert_true(_history.restore(data))
	row["served"] = 900
	data["days"].clear()
	assert_eq(_history.summaries()[0]["served"], 8)
	assert_false(_history.summaries()[0].has("unrelated"))
	assert_eq(_history.capture().keys().size(), 2)


func test_signed_int64_money_bounds_round_trip_through_decimal_json_strings() -> void:
	var first: Dictionary = _saved_row(1)
	first["dish_profit"] = str(BusinessHistory.MIN_MONEY)
	first["cash_change"] = str(BusinessHistory.MAX_MONEY)
	var second: Dictionary = _saved_row(2)
	second["dish_profit"] = str(BusinessHistory.MAX_MONEY)
	second["cash_change"] = str(BusinessHistory.MIN_MONEY)
	assert_true(_history.restore({"version": 1, "days": [first, second]}))
	var rows: Array[Dictionary] = _history.summaries()
	assert_eq(rows[0]["dish_profit"], BusinessHistory.MIN_MONEY)
	assert_eq(rows[0]["cash_change"], BusinessHistory.MAX_MONEY)
	assert_eq(rows[1]["dish_profit"], BusinessHistory.MAX_MONEY)
	assert_eq(rows[1]["cash_change"], BusinessHistory.MIN_MONEY)
	var restored: BusinessHistory = BusinessHistory.new()
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(_history.capture()))
	assert_true(restored.restore(encoded))
	assert_eq(restored.summaries(), rows)


func test_money_accepts_safe_whole_json_numbers_and_rejects_lossy_or_malformed_values() -> void:
	var row: Dictionary = _saved_row(1)
	row["dish_profit"] = -12.0
	row["cash_change"] = float(BusinessHistory.MAX_EXACT_INTEGER)
	assert_true(_history.restore({"version": 1.0, "days": [row]}))
	assert_eq(_history.summaries()[0]["dish_profit"], -12)
	assert_eq(_history.summaries()[0]["cash_change"], BusinessHistory.MAX_EXACT_INTEGER)
	# The raw JSON number also preserves this boundary; the decimal GDScript
	# float literal rounds before the decoder sees it in Godot 4.7.2.
	row["cash_change"] = JSON.parse_string("9007199254740991")
	assert_true(_history.restore({"version": 1, "days": [row]}))
	assert_eq(_history.summaries()[0]["cash_change"], BusinessHistory.MAX_EXACT_INTEGER)
	var expected: Array[Dictionary] = _history.summaries()
	for bad: Variant in ["9223372036854775808", "-9223372036854775809",
			"1e3", "+1", " 1", "01", "-0", "--1", "", null,
			1.5, true, NAN, INF, -INF, 9007199254740992.0]:
		for field: String in ["dish_profit", "cash_change"]:
			var invalid: Dictionary = _saved_row(2)
			invalid[field] = bad
			assert_false(_history.restore({"version": 1, "days": [invalid]}), field)
			assert_eq(_history.summaries(), expected)


func test_invalid_counts_flags_and_reputation_fail_atomically() -> void:
	_history.record(_report(7))
	var expected: Array[Dictionary] = _history.summaries()
	for field: String in ["day", "served", "lost"]:
		for bad: Variant in [-1, true, "2", 0.5, NAN, INF, 9007199254740992]:
			var invalid: Dictionary = _saved_row(1)
			invalid[field] = bad
			assert_false(_history.restore({"version": 1, "days": [invalid]}), field)
			assert_eq(_history.summaries(), expected)
	var zero_day: Dictionary = _saved_row(0)
	assert_false(_history.restore({"version": 1, "days": [zero_day]}))
	for bad: Variant in [false, "3", -0.1, 5.1, NAN, INF, {}]:
		var invalid: Dictionary = _saved_row(1)
		invalid["reputation"] = bad
		assert_false(_history.restore({"version": 1, "days": [invalid]}))
	for bad: Variant in [0, 1.0, "true", null]:
		var invalid: Dictionary = _saved_row(1)
		invalid["dish_profit_recorded"] = bad
		assert_false(_history.restore({"version": 1, "days": [invalid]}))
	assert_eq(_history.summaries(), expected)


func test_valid_before_is_separate_from_intrinsic_restore_and_requires_a_later_morning() -> void:
	assert_true(_history.restore({"version": 1, "days": [_saved_row(2), _saved_row(4)]}))
	assert_false(_history.valid_before(4))
	assert_true(_history.valid_before(5))
	assert_false(_history.valid_before(0))
	assert_false(_history.valid_before(-1))
	assert_eq(_history.summaries().size(), 2, "boundary checks do not clear or rewrite rows")


func test_invalid_or_null_live_reports_are_ignored() -> void:
	_history.record(_report(7))
	var expected: Array[Dictionary] = _history.summaries()
	_history.record(null)
	for field: String in ["day", "customers_served", "customers_lost"]:
		var invalid: DayReport = _report(8)
		invalid.set(field, -1)
		_history.record(invalid)
	var invalid_reputation: DayReport = _report(8)
	invalid_reputation.reputation_after = NAN
	_history.record(invalid_reputation)
	assert_eq(_history.summaries(), expected)


func _report(day: int) -> DayReport:
	var report: DayReport = DayReport.new()
	report.day = day
	report.customers_served = 8
	report.customers_lost = 2
	report.income = {Ledger.SALE: 100, Ledger.MILESTONE_BONUS: 50}
	report.costs = {Ledger.INGREDIENTS: 40, Ledger.WAGES: 20, Ledger.RENT: 10}
	report.stock_values_recorded = true
	report.food_cost = 25
	report.food_cost_recorded = true
	report.reputation_after = 4.25
	return report


func _saved_row(day: int) -> Dictionary:
	return {"day": day, "served": 8, "lost": 2, "dish_profit": "45",
		"dish_profit_recorded": true, "cash_change": "80", "reputation": 4.25}
