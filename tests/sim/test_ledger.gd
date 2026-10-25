extends TestCase
## Ledger reporting, archival, snapshots, and the Economy autoload adapter.

const EconomyScript := preload("res://src/core/economy.gd")

var _economy: EconomyScript
var _events: Array[Dictionary] = []


## Releases only the local adapter and signal observer created by a test.
func after_each() -> void:
	if EventBus.cash_changed.is_connected(_on_cash_changed):
		EventBus.cash_changed.disconnect(_on_cash_changed)
	if _economy != null:
		_economy.free()
		_economy = null


## Categories and days retain separate totals, including every signed flow.
func test_category_totals_daily_income_costs_and_profit() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(1, 100, Ledger.SALE, "meals")
	ledger.record(1, 5, Ledger.TIP)
	ledger.record(1, -12, Ledger.INGREDIENTS)
	ledger.record(1, -20, Ledger.WAGES)
	ledger.record(1, -10, Ledger.RENT)
	ledger.record(1, -5, Ledger.UPGRADES)
	ledger.record(1, 3, Ledger.OTHER)
	ledger.record(2, 50, Ledger.SALE)
	assert_eq(ledger.day_totals(1), {Ledger.SALE: 100, Ledger.TIP: 5,
		Ledger.INGREDIENTS: -12, Ledger.WAGES: -20, Ledger.RENT: -10,
		Ledger.UPGRADES: -5, Ledger.OTHER: 3})
	assert_eq(ledger.day_income(1), 108)
	assert_eq(ledger.day_costs(1), 47)
	assert_eq(ledger.day_profit(1), 61)
	assert_eq(ledger.day_profit(2), 50)
	assert_eq(ledger.cash, 111)
	assert_eq(ledger.day_totals(3), {})
	assert_eq(ledger.day_income(3), 0)
	assert_eq(ledger.day_costs(3), 0)


## Opposite-sign entries in one category preserve gross flows after pruning.
func test_refund_income_and_costs_survive_pruning() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(1, 30, Ledger.SALE)
	ledger.record(1, -4, Ledger.SALE, "refund")
	assert_eq(ledger.day_totals(1), {Ledger.SALE: 26})
	assert_eq(ledger.day_income(1), 30)
	assert_eq(ledger.day_costs(1), 4)
	ledger.prune_before(2)
	assert_eq(ledger.day_totals(1), {Ledger.SALE: 26})
	assert_eq(ledger.day_income(1), 30)
	assert_eq(ledger.day_costs(1), 4)
	assert_eq(ledger.day_profit(1), 26)


## Callers cannot mutate live transaction detail through a report result.
func test_entries_for_day_preserves_order_notes_and_ownership() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(1, 4, Ledger.SALE, "first")
	ledger.record(2, 8, Ledger.SALE, "another day")
	ledger.record(1, 2, Ledger.TIP, "second")
	var entries: Array[Dictionary] = ledger.entries_for_day(1)
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["note"], "first")
	assert_eq(entries[1]["category"], Ledger.TIP)
	entries[0]["amount"] = 999
	entries.clear()
	assert_eq(ledger.entries_for_day(1).size(), 2)
	assert_eq(ledger.day_profit(1), 6)


## Pruning is idempotent and accepts later backdated entries without double counts.
func test_prune_keeps_history_current_detail_and_cash() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(1, 20, Ledger.SALE)
	ledger.record(1, -2, Ledger.WAGES)
	ledger.record(2, 30, Ledger.SALE)
	ledger.prune_before(2)
	assert_eq(ledger.cash, 48)
	assert_eq(ledger.entries_for_day(1).size(), 0)
	assert_eq(ledger.entries_for_day(2).size(), 1)
	assert_eq(ledger.history[1], {Ledger.SALE: 20, Ledger.WAGES: -2})
	ledger.prune_before(2)
	assert_eq(ledger.day_profit(1), 18)
	ledger.record(1, 3, Ledger.TIP)
	assert_eq(ledger.day_income(1), 23)
	ledger.prune_before(2)
	assert_eq(ledger.day_profit(1), 21)
	assert_eq(ledger.day_costs(1), 2)
	assert_eq(ledger.cash, 51)


## Archival bounds history to the 30 calendar days before the cutoff.
func test_history_is_bounded_to_thirty_days() -> void:
	var ledger: Ledger = Ledger.new()
	for day: int in range(1, 36):
		ledger.record(day, day, Ledger.SALE)
	ledger.prune_before(36)
	assert_eq(ledger.history.size(), 30)
	assert_false(ledger.history.has(5))
	assert_true(ledger.history.has(6))
	assert_true(ledger.history.has(35))
	assert_eq(ledger.day_profit(6), 6)
	assert_eq(ledger.cash, 630, "discarding old reports does not discard cash")


## JSON snapshots retain archived gross flows and live typed categories.
func test_json_round_trip_preserves_reports_and_does_not_share_data() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(1, 30, Ledger.SALE)
	ledger.record(1, -2, Ledger.SALE, "refund")
	ledger.prune_before(2)
	ledger.record(2, -3, Ledger.RENT, "rent")
	var snapshot: Dictionary = ledger.to_dict()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var restored: Ledger = Ledger.from_dict(decoded)
	assert_eq(restored.to_dict(), snapshot)
	assert_eq(restored.cash, 25)
	assert_eq(restored.day_income(1), 30)
	assert_eq(restored.day_costs(1), 2)
	assert_eq(restored.entries_for_day(2)[0]["category"], Ledger.RENT)
	decoded["entries"][0]["note"] = "changed"
	assert_eq(restored.entries_for_day(2)[0]["note"], "rent")
	var totals: Dictionary = restored.day_totals(1)
	totals[Ledger.SALE] = 0
	assert_eq(restored.day_profit(1), 28)
	assert_eq(ledger.day_profit(1), 28)


## An empty snapshot starts with the same defaults as a new ledger.
func test_empty_snapshot_has_zero_balance_and_reports() -> void:
	var ledger: Ledger = Ledger.from_dict({})
	assert_eq(ledger.cash, 0)
	assert_eq(ledger.history.size(), 0)
	assert_eq(ledger.entries_for_day(1).size(), 0)
	assert_eq(ledger.day_profit(1), 0)


## Legacy balance assignments and add_cash both create explainable movements.
func test_economy_legacy_cash_and_add_cash_record_and_emit() -> void:
	_make_economy()
	_economy.cash = 30
	_economy.add_cash(-3, Ledger.WAGES)
	assert_eq(_economy.cash, 27)
	assert_eq(_economy.ledger.day_totals(Clock.day), {Ledger.OTHER: 30, Ledger.WAGES: -3})
	assert_eq(_events.size(), 2)
	assert_eq(_events[1]["cash"], 27)
	assert_eq(_events[1]["delta"], -3)
	assert_eq(_events[1]["reason"], Ledger.WAGES)


## A funded purchase updates dated stock before observers receive its cash signal.
func test_buy_ingredient_records_cost_and_batch_atomically() -> void:
	_make_economy()
	_economy.ledger.cash = 20
	assert_true(_economy.buy_ingredient(&"bun", 3, 4))
	assert_eq(_economy.cash, 8)
	assert_eq(_economy.stock.count(&"bun"), 3)
	assert_eq(_economy.ledger.day_totals(Clock.day), {Ledger.INGREDIENTS: -12})
	assert_eq(_economy.stock.to_dict()["batches"]["bun"][0]["bought_day"], str(Clock.day))
	assert_eq(_events.size(), 1)
	assert_eq(_events[0]["stock"], 3)
	assert_eq(_events[0]["delta"], -12)
	assert_eq(_events[0]["reason"], Ledger.INGREDIENTS)


## Insufficient cash leaves both models unchanged and emits no cash movement.
func test_unaffordable_purchase_has_no_side_effects() -> void:
	_make_economy()
	_economy.ledger.cash = 2
	_economy.stock.add(&"bun", 1, Clock.day)
	var before_ledger: Dictionary = _economy.ledger.to_dict()
	var before_stock: Dictionary = _economy.stock.to_dict()
	assert_false(_economy.buy_ingredient(&"bun", 2, 2))
	assert_eq(_economy.ledger.to_dict(), before_ledger)
	assert_eq(_economy.stock.to_dict(), before_stock)
	assert_eq(_events.size(), 0)


## Invalid quantities, prices and overflowing cost products fail without changes.
func test_invalid_purchase_inputs_do_not_change_money_or_stock() -> void:
	_make_economy()
	_economy.ledger.cash = 20
	var before: Dictionary = _economy.ledger.to_dict()
	assert_false(_economy.buy_ingredient(&"", 1, 1))
	assert_false(_economy.buy_ingredient(&"bun", 0, 1))
	assert_false(_economy.buy_ingredient(&"bun", -1, 1))
	assert_false(_economy.buy_ingredient(&"bun", 1, -1))
	assert_false(_economy.buy_ingredient(&"bun", Stock.MAX_QUANTITY, 2))
	assert_eq(_economy.ledger.to_dict(), before)
	assert_eq(_economy.stock.count(&"bun"), 0)
	assert_eq(_events.size(), 0)


## The explicit Phase 1 policy permits exact spending and rejects borrowing.
func test_no_loan_policy_and_zero_cost_purchase() -> void:
	_make_economy()
	_economy.ledger.cash = 20
	assert_true(_economy.can_spend_without_loan(20))
	assert_false(_economy.can_spend_without_loan(21))
	assert_false(_economy.can_spend_without_loan(-1))
	assert_true(_economy.buy_ingredient(&"bun", 2, 0))
	assert_eq(_economy.cash, 20)
	assert_eq(_economy.stock.count(&"bun"), 2)
	assert_true(_economy.buy_ingredient(&"bun", 5, 4))
	assert_eq(_economy.cash, 0)
	assert_false(_economy.buy_ingredient(&"bun", 1, 1))


func test_open_loan_blocks_big_discretionary_spending_but_not_ingredients() -> void:
	_make_economy()
	_economy.ledger.cash = 100
	_economy.loan.principal = 150
	assert_true(_economy.can_spend_without_loan(80))
	assert_false(_economy.can_buy_discretionary(51))
	assert_true(_economy.can_buy_discretionary(50))
	assert_false(_economy.can_buy_upgrade(1), "even a cheap upgrade waits for repayment")
	assert_true(_economy.buy_ingredient(&"bun", 2, 10))
	assert_eq(_economy.cash, 80)
	assert_eq(_economy.stock.count(&"bun"), 2)
	assert_false(_economy.can_buy_discretionary(81), "ordinary affordability still applies")
	_economy.loan.principal = 0
	assert_true(_economy.can_buy_discretionary(80))
	assert_true(_economy.can_buy_upgrade(1))


func test_loan_settlement_emits_each_ledger_flow_and_restore_is_transactional() -> void:
	_make_economy()
	_economy.ledger.cash = 0
	_economy.loan.principal = 100
	var day: int = maxi(1, Clock.day)
	_economy.add_cash(100, Ledger.SALE)
	_events.clear()
	var result: Dictionary = _economy.settle_loan_day(day)
	assert_eq(result["interest"], 5)
	assert_eq(result["repayment"], 50)
	assert_eq(_economy.cash, 45)
	assert_eq(_events.size(), 2)
	assert_eq(_events[0]["cash"], 95)
	assert_eq(_events[0]["reason"], Ledger.LOAN_INTEREST)
	assert_eq(_events[1]["cash"], 45)
	assert_eq(_events[1]["reason"], Ledger.LOAN_REPAYMENT)
	var saved: Dictionary = _economy._capture_save()
	assert_eq(saved["loan"]["principal"], "50")
	assert_true(_economy._restore_save(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(_economy.loan.principal, 50)
	assert_eq(_economy.loan.last_settled_day, day)
	var before: Dictionary = _economy._capture_save()
	var invalid: Dictionary = saved.duplicate(true)
	invalid["loan"]["principal"] = "bad"
	assert_false(_economy._restore_save(invalid))
	assert_eq(_economy._capture_save(), before, "a bad loan cannot partially restore the books")
	var old_save: Dictionary = saved.duplicate(true)
	old_save.erase("loan")
	assert_true(_economy._restore_save(old_save))
	assert_eq(_economy.loan.principal, 0, "older economy saves start without debt")


func _make_economy() -> void:
	_economy = EconomyScript.new()
	EventBus.cash_changed.connect(_on_cash_changed)


func _on_cash_changed(balance: int, amount: int, reason: StringName) -> void:
	_events.append({"cash": balance, "delta": amount, "reason": reason,
		"stock": _economy.stock.count(&"bun")})


## JSON retains large live entries and archived gross/category amounts exactly.
func test_json_round_trip_preserves_values_above_double_integer_precision() -> void:
	var large: int = 9007199254740993
	var ledger: Ledger = Ledger.new()
	ledger.record(1, large, Ledger.SALE)
	ledger.record(1, -(large - 7), Ledger.RENT)
	ledger.prune_before(2)
	ledger.record(2, large, Ledger.TIP)
	ledger.record(2, -3, Ledger.OTHER)
	var snapshot: Dictionary = ledger.to_dict()
	var restored: Ledger = Ledger.from_dict(JSON.parse_string(JSON.stringify(snapshot)))
	assert_eq(restored.to_dict(), snapshot)
	assert_eq(restored.cash, large + 4)
	assert_eq(restored.day_totals(1)[Ledger.SALE], large)
	assert_eq(restored.day_totals(1)[Ledger.RENT], -(large - 7))
	assert_eq(restored.day_income(1), large)
	assert_eq(restored.day_costs(1), large - 7)
	assert_eq(restored.entries_for_day(2)[0]["amount"], large)


## The largest signed integer and large day numbers survive live and archived JSON.
func test_json_round_trip_preserves_maximum_cash() -> void:
	var maximum: int = 9223372036854775807
	var day: int = 9007199254740993
	var ledger: Ledger = Ledger.new()
	ledger.record(day, maximum, Ledger.SALE)
	var restored: Ledger = Ledger.from_dict(JSON.parse_string(JSON.stringify(ledger.to_dict())))
	assert_eq(restored.cash, maximum)
	assert_eq(restored.entries_for_day(day)[0]["amount"], maximum)
	restored.prune_before(day + 1)
	var archived: Ledger = Ledger.from_dict(JSON.parse_string(JSON.stringify(restored.to_dict())))
	assert_eq(archived.cash, maximum)
	assert_eq(archived.day_totals(day)[Ledger.SALE], maximum)
	assert_eq(archived.day_income(day), maximum)
