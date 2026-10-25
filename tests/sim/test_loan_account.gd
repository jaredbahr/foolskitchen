extends TestCase
## Pure day-close bank flows keep every dollar in the dated ledger.

const TERMS: LoanTuning = preload("res://data/balance/loans.tres")


func test_shortfall_is_covered_in_fifty_dollar_steps_without_opening_day_interest() -> void:
	var ledger: Ledger = Ledger.new()
	var account: LoanAccount = LoanAccount.new()
	ledger.record(1, -64, Ledger.RENT)
	var result: Dictionary = account.settle_day(ledger, 1, TERMS)
	assert_eq(result["advance"], 100)
	assert_eq(result["interest"], 0)
	assert_eq(result["repayment"], 0)
	assert_eq(result["operating_profit"], -64,
		"financing income cannot become operating profit or award owner XP")
	assert_eq(account.principal, 100)
	assert_eq(ledger.cash, 36)
	assert_eq(ledger.day_totals(1), {Ledger.RENT: -64, Ledger.BANK_LOAN: 100})
	assert_eq(ledger.day_profit(1), 36)
	assert_eq(ledger.cash, -64 + 100, "loan income is a real cash movement")


func test_existing_loan_charges_interest_once_then_repays_from_operating_profit() -> void:
	var ledger: Ledger = Ledger.new()
	var account: LoanAccount = LoanAccount.new()
	account.principal = 100
	ledger.record(1, 100, Ledger.SALE)
	var first: Dictionary = account.settle_day(ledger, 1, TERMS)
	assert_eq(first["interest"], 5)
	assert_eq(first["repayment"], 50)
	assert_eq(first["advance"], 0)
	assert_eq(first["operating_profit"], 100)
	assert_eq(account.principal, 50)
	assert_eq(ledger.cash, 45)
	assert_eq(ledger.day_totals(1), {Ledger.SALE: 100,
		Ledger.LOAN_INTEREST: -5, Ledger.LOAN_REPAYMENT: -50})
	var snapshot: Dictionary = ledger.to_dict()
	assert_true(account.settle_day(ledger, 1, TERMS).is_empty())
	assert_eq(ledger.to_dict(), snapshot, "repeated close cannot charge interest")
	ledger.record(2, 200, Ledger.SALE)
	var second: Dictionary = account.settle_day(ledger, 2, TERMS)
	assert_eq(second["interest"], 3, "5% of the remaining $50 rounds to $3")
	assert_eq(second["repayment"], 50, "repayment cannot exceed principal")
	assert_eq(account.principal, 0)
	assert_eq(ledger.cash, 192)
	ledger.record(3, 10, Ledger.SALE)
	assert_eq(account.settle_day(ledger, 3, TERMS)["interest"], 0)
	assert_eq(ledger.cash, 202)


func test_one_dollar_profit_retires_the_last_dollar_without_unbalanced_cash() -> void:
	var ledger: Ledger = Ledger.new()
	var account: LoanAccount = LoanAccount.new()
	account.principal = 1
	ledger.record(1, 1, Ledger.SALE)
	var result: Dictionary = account.settle_day(ledger, 1, TERMS)
	assert_eq(result["interest"], 0)
	assert_eq(result["repayment"], 1)
	assert_eq(result["advance"], 0)
	assert_eq(account.principal, 0)
	assert_eq(ledger.day_totals(1), {Ledger.SALE: 1, Ledger.LOAN_REPAYMENT: -1})
	assert_eq(ledger.cash, 0, "the remaining dollar goes through the cash ledger")
	assert_true(account.settle_day(ledger, 1, TERMS).is_empty(),
		"the same day cannot repay twice")


func test_interest_shortfall_extends_debt_and_every_category_balances() -> void:
	var ledger: Ledger = Ledger.new()
	var account: LoanAccount = LoanAccount.new()
	account.principal = 100
	var result: Dictionary = account.settle_day(null, 1, TERMS)
	assert_true(result.is_empty(), "a missing ledger cannot mutate the account")
	result = account.settle_day(ledger, 1, TERMS)
	assert_eq(result["interest"], 5)
	assert_eq(result["repayment"], 0)
	assert_eq(result["advance"], 50)
	assert_eq(account.principal, 150)
	assert_eq(ledger.cash, 45)
	assert_eq(ledger.day_totals(1), {Ledger.LOAN_INTEREST: -5, Ledger.BANK_LOAN: 50})
	assert_eq(ledger.day_profit(1), ledger.cash)


func test_loan_snapshot_is_decimal_and_invalid_data_is_rejected() -> void:
	var account: LoanAccount = LoanAccount.new()
	account.principal = 9007199254740993
	account.last_settled_day = 12
	var saved: Dictionary = account.to_dict()
	assert_eq(saved["principal"], "9007199254740993")
	var restored: LoanAccount = LoanAccount.from_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_not_null(restored)
	if restored != null:
		assert_eq(restored.to_dict(), saved)
	for invalid: Variant in [null, {}, {"version": 1, "principal": -2,
			"last_settled_day": "1"}, {"version": 1, "principal": "-2",
			"last_settled_day": "1"}, {"version": 1, "principal": "3.5",
			"last_settled_day": "1"}, {"version": 1, "principal": "3",
			"last_settled_day": "-1"}]:
		assert_null(LoanAccount.from_dict(invalid))
	assert_eq(TERMS.daily_interest, 0.05)
	assert_eq(TERMS.repay_share, 0.5)
	assert_true(TERMS.is_valid())


func test_first_advance_history_survives_repayment_reload_and_later_borrowing() -> void:
	var ledger: Ledger = Ledger.new()
	var account: LoanAccount = LoanAccount.new()
	assert_true(account.settle_day(null, 1, TERMS).is_empty())
	assert_false(account.has_borrowed, "an invalid settlement cannot consume the introduction")
	ledger.record(1, -10, Ledger.RENT)
	var first: Dictionary = account.settle_day(ledger, 1, TERMS)
	assert_true(first["first_advance"])
	assert_true(account.has_borrowed)
	assert_true(account.settle_day(ledger, 1, TERMS).is_empty())
	ledger.record(2, account.principal * 2, Ledger.SALE)
	assert_false(account.settle_day(ledger, 2, TERMS)["first_advance"])
	assert_eq(account.principal, 0)
	var restored: LoanAccount = LoanAccount.from_dict(JSON.parse_string(JSON.stringify(account.to_dict())))
	assert_not_null(restored)
	if restored == null:
		return
	assert_true(restored.has_borrowed, "paid-off history remains durable")
	ledger.record(3, -200, Ledger.RENT)
	var later: Dictionary = restored.settle_day(ledger, 3, TERMS)
	assert_true(int(later["advance"]) > 0)
	assert_false(later["first_advance"], "a later loan does not repeat the first introduction")


func test_legacy_loan_history_is_inferred_and_present_flags_must_be_boolean() -> void:
	var legacy: Dictionary = {"version": 1, "principal": "100", "last_settled_day": "2"}
	var restored: LoanAccount = LoanAccount.from_dict(legacy)
	assert_not_null(restored)
	if restored != null:
		assert_true(restored.has_borrowed, "an existing loan already had its introduction")
	legacy["principal"] = "0"
	restored = LoanAccount.from_dict(legacy)
	assert_not_null(restored)
	if restored != null:
		assert_false(restored.has_borrowed, "paid-off history was not stored by the older format")
	for invalid: Variant in ["true", 1, null]:
		legacy["has_borrowed"] = invalid
		assert_null(LoanAccount.from_dict(legacy))
	legacy["principal"] = "100"
	legacy["has_borrowed"] = false
	assert_null(LoanAccount.from_dict(legacy), "an active loan cannot claim no borrowing history")


func test_exact_minimum_cash_rejects_without_consuming_close_or_history() -> void:
	var ledger: Ledger = _boundary_ledger(LoanAccount.MIN_CURRENCY)
	var account: LoanAccount = _boundary_account(0)
	_assert_settlement_rejected(ledger, account)
	ledger.cash = 0
	assert_false(account.settle_day(ledger, 3, TERMS).is_empty(),
		"a rejected unrepresentable close leaves that day available")
	assert_eq(account.last_settled_day, 3)


func test_near_minimum_cash_rejects_interest_unrepresentable_advance_and_exact_minimum_projection() -> void:
	# Interest underflows; then interest fits and repayment is zero but the
	# required rounded advance is unrepresentable; finally shortage cannot negate.
	for fixture: Dictionary in [
		{"cash": LoanAccount.MIN_CURRENCY + 4, "profit": 0},
		{"cash": LoanAccount.MIN_CURRENCY + 6, "profit": 100},
		{"cash": LoanAccount.MIN_CURRENCY + 5, "profit": 0},
	]:
		var ledger: Ledger = _boundary_ledger(int(fixture["cash"]), int(fixture["profit"]))
		_assert_settlement_rejected(ledger, _boundary_account(100))


func test_maximum_principal_cannot_extend_without_headroom() -> void:
	_assert_settlement_rejected(_boundary_ledger(0), _boundary_account(LoanAccount.MAX_CURRENCY))


func test_maximum_cash_caps_full_profit_repayment_after_interest_without_overflow() -> void:
	var all_profit: LoanTuning = TERMS.duplicate(true) as LoanTuning
	all_profit.repay_share = 1.0
	var ledger: Ledger = _boundary_ledger(LoanAccount.MAX_CURRENCY, LoanAccount.MAX_CURRENCY)
	var account: LoanAccount = _boundary_account(LoanAccount.MAX_CURRENCY)
	var result: Dictionary = account.settle_day(ledger, 3, all_profit)
	assert_false(result.is_empty())
	if result.is_empty():
		return
	var interest: int = roundi(float(LoanAccount.MAX_CURRENCY) * all_profit.daily_interest)
	assert_eq(result["interest"], interest)
	assert_eq(result["repayment"], LoanAccount.MAX_CURRENCY - interest)
	assert_eq(result["advance"], 0)
	assert_eq(ledger.cash, 0)
	assert_eq(account.principal, interest)
	assert_eq(ledger.day_costs(3), LoanAccount.MAX_CURRENCY)
	assert_eq(ledger.day_profit(3), 0)
	assert_eq(account.last_settled_day, 3)
	assert_true(account.has_borrowed)


func test_principal_1000_cash_60_profit_30_repays_available_ten_without_a_new_advance() -> void:
	var ledger: Ledger = _boundary_ledger(60, 30)
	var account: LoanAccount = _boundary_account(1000)
	var result: Dictionary = account.settle_day(ledger, 3, TERMS)
	assert_false(result.is_empty())
	if result.is_empty():
		return
	assert_eq(result["operating_profit"], 30)
	assert_eq(result["interest"], 50)
	assert_eq(result["repayment"], 10)
	assert_eq(result["advance"], 0)
	assert_eq(ledger.cash, 0)
	assert_eq(account.principal, 990)
	assert_eq(ledger.day_totals(3), {Ledger.SALE: 30,
		Ledger.LOAN_INTEREST: -50, Ledger.LOAN_REPAYMENT: -10})
	var saved: Dictionary = ledger.to_dict()
	assert_true(account.settle_day(ledger, 3, TERMS).is_empty())
	assert_eq(ledger.to_dict(), saved, "cash-limited repayment still settles only once")


func test_repayment_cash_cap_keeps_interest_shortfalls_zero_share_and_principal_cap() -> void:
	for fixture: Dictionary in [
		{"principal": 1000, "cash": 50, "profit": 30, "share": 0.5,
			"interest": 50, "repayment": 0, "advance": 0, "end_cash": 0, "end_principal": 1000},
		{"principal": 1000, "cash": 20, "profit": 30, "share": 0.5,
			"interest": 50, "repayment": 0, "advance": 50, "end_cash": 20, "end_principal": 1050},
		{"principal": 1000, "cash": -30, "profit": -30, "share": 0.5,
			"interest": 50, "repayment": 0, "advance": 100, "end_cash": 20, "end_principal": 1100},
		{"principal": 1000, "cash": 60, "profit": 30, "share": 0.0,
			"interest": 50, "repayment": 0, "advance": 0, "end_cash": 10, "end_principal": 1000},
		{"principal": 20, "cash": 100, "profit": 100, "share": 0.5,
			"interest": 1, "repayment": 20, "advance": 0, "end_cash": 79, "end_principal": 0},
	]:
		var ledger: Ledger = _boundary_ledger(int(fixture["cash"]), int(fixture["profit"]))
		var account: LoanAccount = _boundary_account(int(fixture["principal"]))
		var terms: LoanTuning = TERMS.duplicate(true) as LoanTuning
		terms.repay_share = float(fixture["share"])
		var result: Dictionary = account.settle_day(ledger, 3, terms)
		assert_false(result.is_empty())
		if result.is_empty():
			continue
		assert_eq(result["operating_profit"], int(fixture["profit"]))
		assert_eq(result["interest"], int(fixture["interest"]))
		assert_eq(result["repayment"], int(fixture["repayment"]))
		assert_eq(result["advance"], int(fixture["advance"]))
		assert_eq(ledger.cash, int(fixture["end_cash"]))
		assert_eq(account.principal, int(fixture["end_principal"]))


func test_largest_representable_rounded_advance_succeeds_and_next_shortage_rejects() -> void:
	var largest_advance: int = LoanAccount.MAX_CURRENCY - LoanAccount.MAX_CURRENCY % TERMS.borrowing_step
	assert_true(largest_advance < LoanAccount.MAX_CURRENCY,
		"the authored $50 borrowing step leaves a rounding boundary below INT64_MAX")
	for shortage: int in [largest_advance - 1, largest_advance]:
		var ledger: Ledger = _boundary_ledger(-shortage)
		var account: LoanAccount = _boundary_account(0)
		var history: Dictionary = ledger.to_dict()["history"]
		var result: Dictionary = account.settle_day(ledger, 3, TERMS)
		assert_false(result.is_empty(), "large but representable debt must remain accepted")
		if result.is_empty():
			continue
		assert_eq(result["advance"], largest_advance)
		assert_eq(account.principal, largest_advance)
		assert_eq(ledger.cash, largest_advance - shortage)
		assert_eq(ledger.day_totals(3), {Ledger.BANK_LOAN: largest_advance})
		assert_eq(ledger.to_dict()["history"], history)
		assert_eq(account.last_settled_day, 3)
		assert_true(account.has_borrowed)
		assert_true(result["first_advance"])
	if largest_advance < LoanAccount.MAX_CURRENCY:
		_assert_settlement_rejected(_boundary_ledger(-(largest_advance + 1)), _boundary_account(0))


func test_full_profit_share_caps_maximum_daily_profit_before_float_conversion() -> void:
	var all_profit: LoanTuning = TERMS.duplicate(true) as LoanTuning
	all_profit.repay_share = 1.0
	var ledger: Ledger = _boundary_ledger(LoanAccount.MAX_CURRENCY, LoanAccount.MAX_CURRENCY)
	var account: LoanAccount = _boundary_account(100)
	var result: Dictionary = account.settle_day(ledger, 3, all_profit)
	assert_false(result.is_empty())
	if result.is_empty():
		return
	assert_eq(result["repayment"], 100)
	assert_eq(result["interest"], 5)
	assert_eq(result["advance"], 0)
	assert_eq(account.principal, 0)
	assert_eq(ledger.cash, LoanAccount.MAX_CURRENCY - 105)
	assert_eq(ledger.day_profit(3), LoanAccount.MAX_CURRENCY - 105)


## Restore real decimal-string snapshots, including archived ledger history.
func _boundary_ledger(cash: int, profit: int = 0) -> Ledger:
	var original: Ledger = Ledger.new()
	original.record(1, 7, Ledger.TIP)
	original.record(1, -2, Ledger.RENT)
	original.prune_before(2)
	original.cash = 0
	if profit > 0:
		original.record(3, profit, Ledger.SALE)
	elif profit < 0:
		original.record(3, profit, Ledger.RENT)
	var saved: Dictionary = original.to_dict()
	saved["cash"] = str(cash)
	var restored: Ledger = Ledger.from_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_eq(restored.cash, cash)
	assert_eq(restored.day_totals(1), {Ledger.TIP: 7, Ledger.RENT: -2})
	return restored


func _boundary_account(principal: int) -> LoanAccount:
	return LoanAccount.from_dict({"version": 1, "principal": str(principal),
		"last_settled_day": "2", "has_borrowed": principal > 0})


func _assert_settlement_rejected(ledger: Ledger, account: LoanAccount,
		terms: LoanTuning = TERMS) -> void:
	var books: Dictionary = ledger.to_dict()
	var saved: Dictionary = account.to_dict()
	var borrowed: bool = account.has_borrowed
	assert_true(account.settle_day(ledger, 3, terms).is_empty())
	assert_eq(ledger.to_dict(), books, "rejection retains cash, entries and archived gross/category history")
	assert_eq(account.to_dict(), saved, "rejection retains principal and the once-per-day guard")
	assert_eq(account.has_borrowed, borrowed, "rejection cannot consume the first-loan introduction")


func test_ten_forced_loss_days_end_solvent_with_balanced_books() -> void:
	var ledger: Ledger = Ledger.new()
	var account: LoanAccount = LoanAccount.new()
	var all_movements: int = 0
	for day: int in range(1, 11):
		ledger.record(day, -64, Ledger.RENT)
		ledger.record(day, -19, Ledger.WAGES)
		all_movements -= 83
		var settlement: Dictionary = account.settle_day(ledger, day, TERMS)
		assert_false(settlement.is_empty(), "day %d settles" % day)
		assert_true(int(settlement["advance"]) > 0,
			"forced loss needs a bank advance on day %d" % day)
		for movement: Dictionary in settlement["movements"]:
			all_movements += int(movement["amount"])
		assert_true(ledger.cash >= 0, "bank covers day %d" % day)
		assert_eq(ledger.cash, all_movements, "every movement balances on day %d" % day)
		assert_eq(ledger.day_totals(day).get(Ledger.RENT, 0), -64)
		assert_eq(ledger.day_totals(day).get(Ledger.WAGES, 0), -19)
	assert_true(account.principal > 0)
	assert_eq(account.last_settled_day, 10)
