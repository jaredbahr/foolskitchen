extends TestCase
## Lifetime records consume finalized reports without changing the game or report.


func test_totals_use_meals_tips_and_every_sold_dish_over_several_days() -> void:
	var records: ShopRecords = ShopRecords.new()
	var first: DayReport = _report(1)
	var input: Dictionary = first.to_dict()
	records.record(first)
	records.record(_report(2))
	var state: Dictionary = records.snapshot()
	assert_eq(state["guests"], 8)
	assert_eq(state["revenue"], 210, "loans, milestone bonuses and ingredient refunds are not revenue")
	assert_eq(state["dishes"], {&"soup": 4, &"toast": 6})
	assert_eq(state["bests"][&"dishes"], {"value": 5, "day": 1})
	assert_eq(first.to_dict(), input)


func test_each_best_keeps_its_first_day_on_ties_and_updates_only_when_beaten() -> void:
	var records: ShopRecords = ShopRecords.new()
	records.record(_report(1))
	assert_eq(records.record(_report(2)), [&"streak"] as Array[StringName])
	for id: StringName in [&"guests", &"profit", &"dishes", &"reputation"]:
		assert_eq(records.snapshot()["bests"][id]["day"], 1)
	var better: DayReport = _report(3)
	better.customers_served = 7
	better.dishes_sold[&"soup"] = 9
	better.income[Ledger.SALE] = 200
	better.reputation_after = 4.5
	assert_eq(records.record(better), ShopRecords.BEST_IDS)
	for id: StringName in ShopRecords.BEST_IDS:
		assert_eq(records.snapshot()["bests"][id]["day"], 3)


func test_unknown_profit_is_not_zero_and_the_first_record_can_be_a_loss() -> void:
	var records: ShopRecords = ShopRecords.new()
	var loss: DayReport = _report(1)
	loss.income = {Ledger.SALE: 5}
	loss.food_cost = 0
	records.record(loss)
	assert_eq(records.snapshot()["bests"][&"profit"], {"value": -25, "day": 1})
	var unknown: DayReport = _report(2)
	unknown.income[Ledger.SALE] = 10000
	unknown.stock_values_recorded = false
	assert_false(unknown.operating_profit_recorded())
	records.record(unknown)
	assert_eq(records.snapshot()["bests"][&"profit"], {"value": -25, "day": 1})
	var fresh: ShopRecords = ShopRecords.new()
	fresh.record(unknown)
	assert_false(fresh.snapshot()["bests"].has(&"profit"))


func test_every_public_service_failure_resets_the_streak_but_administrative_exits_do_not() -> void:
	for reason: StringName in ShopRecords.ANGRY_REASONS:
		var records: ShopRecords = ShopRecords.new()
		records.record(_report(1))
		var unhappy: DayReport = _report(2)
		unhappy.customers_lost = 0 # The reason, not the broader unpaid total, owns this metric.
		unhappy.leave_reasons = {reason: 1}
		records.record(unhappy)
		assert_eq(records.snapshot()["streak"], 0, String(reason))
		var closing: DayReport = _report(3)
		closing.customers_lost = 12
		closing.leave_reasons = {&"closing": 9, &"removed": 3}
		closing.review_cards = [{"stars": 1, "quote": "A paid guest's review is not a departure reason."}]
		records.record(closing)
		assert_eq(records.snapshot()["streak"], 1)
		assert_eq(records.snapshot()["bests"][&"streak"], {"value": 1, "day": 1})


func test_reason_list_tracks_the_actual_public_cancellation_mapping() -> void:
	var existing: Array[StringName] = CustomerAgent.PLAYER_REASONS.duplicate()
	existing.erase(&"closing")
	existing.append(CustomerAgent.player_reason(&"missing_station")) # existing kitchen fallback
	existing.append(&"no_menu") # existing direct departure before an order is placed
	existing.sort()
	var recorded: Array[StringName] = ShopRecords.ANGRY_REASONS.duplicate()
	recorded.sort()
	assert_eq(recorded, existing, "a new public service failure needs an explicit Records decision")


func test_gaps_restart_and_a_zero_guest_close_without_unhappy_departures_is_clean() -> void:
	var records: ShopRecords = ShopRecords.new()
	records.record(_report(1))
	records.record(_report(2))
	assert_eq(records.snapshot()["streak"], 2)
	var empty: DayReport = _report(5)
	empty.customers_served = 0
	empty.dishes_sold.clear()
	empty.income.clear()
	records.record(empty)
	assert_eq(records.snapshot()["streak"], 1)
	assert_eq(records.snapshot()["bests"][&"streak"], {"value": 2, "day": 2})


func test_duplicate_stale_and_invalid_reports_do_not_add_totals_or_rewrite_a_close() -> void:
	var records: ShopRecords = ShopRecords.new()
	records.record(_report(4))
	var expected: Dictionary = records.capture()
	var repeated: DayReport = _report(4)
	repeated.income[Ledger.SALE] = 900
	assert_eq(records.record(repeated), [] as Array[StringName])
	records.record(_report(3))
	records.record(null)
	var invalid: DayReport = _report(5)
	invalid.dishes_sold[&"toast"] = -1
	records.record(invalid)
	assert_eq(records.capture(), expected)


func test_snapshots_and_capture_are_detached_from_live_state_and_inputs() -> void:
	var records: ShopRecords = ShopRecords.new()
	var report: DayReport = _report(1)
	records.record(report)
	var expected: Dictionary = records.capture()
	var view: Dictionary = records.snapshot()
	view["bests"][&"guests"]["value"] = 999
	view["dishes"].clear()
	var saved: Dictionary = records.capture()
	saved["bests"].clear()
	report.dishes_sold.clear()
	assert_eq(records.capture(), expected)


func test_exact_currency_json_roundtrip_and_missing_legacy_records() -> void:
	var records: ShopRecords = ShopRecords.new()
	records.record(_report(7))
	var data: Dictionary = records.capture()
	data["revenue"] = str(ShopRecords.MAX_MONEY)
	data["bests"][&"profit"]["value"] = str(ShopRecords.MIN_MONEY)
	var restored: ShopRecords = ShopRecords.new()
	assert_true(restored.restore(JSON.parse_string(JSON.stringify(data))))
	assert_eq(restored.snapshot()["revenue"], ShopRecords.MAX_MONEY)
	assert_eq(restored.snapshot()["bests"][&"profit"]["value"], ShopRecords.MIN_MONEY)
	var expected: Dictionary = restored.capture()
	restored.record(_report(8))
	assert_eq(restored.capture(), expected, "overflow rejects the whole incoming day")
	assert_false(restored.valid_before(7))
	assert_true(restored.valid_before(8))
	assert_true(restored.restore({}))
	assert_eq(restored.snapshot(), ShopRecords.new().snapshot())


func test_malformed_restore_is_atomic_and_never_installs_partial_totals() -> void:
	var records: ShopRecords = ShopRecords.new()
	records.record(_report(3))
	var expected: Dictionary = records.capture()
	var cases: Array[Dictionary] = [{"version": 1}]
	for field: String in ["last_day", "guests", "streak", "revenue"]:
		var bad: Dictionary = expected.duplicate(true)
		bad[field] = true
		cases.append(bad)
	var future: Dictionary = expected.duplicate(true)
	future["bests"][&"guests"]["day"] = 4
	cases.append(future)
	var count: Dictionary = expected.duplicate(true)
	count["dishes"][&"soup"] = 1.5
	cases.append(count)
	var money: Dictionary = expected.duplicate(true)
	money["revenue"] = "9223372036854775808"
	cases.append(money)
	var stars: Dictionary = expected.duplicate(true)
	stars["bests"][&"reputation"]["value"] = NAN
	cases.append(stars)
	for bad: Dictionary in cases:
		assert_false(records.restore(bad))
		assert_eq(records.capture(), expected)


func _report(day: int) -> DayReport:
	var report: DayReport = DayReport.new()
	report.day = day
	report.customers_served = 4
	report.dishes_sold = {&"soup": 2, &"toast": 3}
	report.income = {Ledger.SALE: 100, Ledger.TIP: 5, Ledger.BANK_LOAN: 500,
		Ledger.MILESTONE_BONUS: 75, Ledger.INGREDIENTS: 7}
	report.costs = {Ledger.WAGES: 20, Ledger.RENT: 10}
	report.stock_values_recorded = true
	report.food_cost_recorded = true
	report.food_cost = 25
	report.reputation_after = 3.5
	return report
