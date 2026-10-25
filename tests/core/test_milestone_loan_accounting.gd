extends TestCase
## Autoload forwarding and cash signals only; no Main, save provider or files.

var _old_ledger: Ledger
var _old_loan: LoanAccount
var _events: Array[Dictionary] = []


func before_each() -> void:
	_old_ledger = Economy.ledger
	_old_loan = Economy.loan
	EventBus.cash_changed.connect(_on_cash_changed)


func after_each() -> void:
	EventBus.cash_changed.disconnect(_on_cash_changed)
	Economy.ledger = _old_ledger
	Economy.loan = _old_loan


func test_adapter_forwards_pre_bonus_profit_and_announces_actual_cash_in_order() -> void:
	var day: int = Clock.day
	for fixture: Dictionary in [{"bonus": 3, "repayment": 13, "cash": 0},
			{"bonus": 500, "repayment": 15, "cash": 495}]:
		_events.clear()
		_set_books(day)
		var profit: int = Economy.ledger.day_profit(day)
		var bonus: int = int(fixture["bonus"])
		Economy.add_cash(bonus, Ledger.MILESTONE_BONUS)
		var result: Dictionary = Economy.settle_loan_day(day, profit)
		assert_false(result.is_empty())
		if result.is_empty():
			continue
		var repayment: int = int(fixture["repayment"])
		var cash: int = int(fixture["cash"])
		assert_eq(result["operating_profit"], 30)
		assert_eq(result["repayment"], repayment)
		assert_eq(Economy.cash, cash)
		assert_eq(Economy.loan.principal, 1000 - repayment)
		assert_eq(_events, [
			{"balance": 60 + bonus, "amount": bonus, "reason": Ledger.MILESTONE_BONUS, "actual_cash": 60 + bonus},
			{"balance": 10 + bonus, "amount": -50, "reason": Ledger.LOAN_INTEREST, "actual_cash": cash},
			{"balance": cash, "amount": -repayment, "reason": Ledger.LOAN_REPAYMENT, "actual_cash": cash},
		] as Array[Dictionary])
		var books: Dictionary = Economy.ledger.to_dict()
		assert_true(Economy.settle_loan_day(day, profit).is_empty())
		assert_eq(Economy.ledger.to_dict(), books)
		assert_eq(_events.size(), 3, "a repeated close emits no additional cash movements")


func test_adapter_rejects_malformed_profit_without_cash_events_or_mutation() -> void:
	var day: int = Clock.day
	_set_books(day)
	var books: Dictionary = Economy.ledger.to_dict()
	var account: Dictionary = Economy.loan.to_dict()
	assert_true(Economy.settle_loan_day(day, 30.0).is_empty(), "the adapter must not coerce a float into a valid override")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.loan.to_dict(), account)
	assert_true(_events.is_empty())
	assert_false(Economy.settle_loan_day(day, 30).is_empty(), "the valid retry still owns the same closing day")
	assert_eq(_events.size(), 2)


func _set_books(day: int) -> void:
	Economy.ledger = Ledger.new()
	Economy.ledger.cash = 30
	Economy.ledger.record(day, 30, Ledger.SALE)
	Economy.loan = LoanAccount.new()
	Economy.loan.principal = 1000
	Economy.loan.has_borrowed = true


func _on_cash_changed(balance: int, amount: int, reason: StringName) -> void:
	_events.append({"balance": balance, "amount": amount, "reason": reason, "actual_cash": Economy.cash})
