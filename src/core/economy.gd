extends Node
## Autoload adapter for the pure ledger and ingredient stock models.
## Money is always whole currency units; purchases cannot borrow in Phase 1.

const MAX_CURRENCY: int = 9223372036854775807

var ledger: Ledger = Ledger.new()
var stock: Stock = Stock.new()
## Legacy balance access. Assignments record their difference under OTHER.
var cash: int:
	get:
		return ledger.cash
	set(value):
		if value != ledger.cash:
			add_cash(value - ledger.cash, Ledger.OTHER)


## Adds (or, with a negative amount, removes) cash and announces it.
func add_cash(amount: int, reason: StringName) -> void:
	ledger.record(Clock.day, amount, reason)
	EventBus.cash_changed.emit(cash, amount, reason)


## Central Phase 1 policy. Loan behavior will replace this rule in Phase 3.
func can_spend_without_loan(amount: int) -> bool:
	return amount >= 0 and cash >= amount


## Buys one ingredient batch atomically, or returns false without changes.
@warning_ignore("integer_division")
func buy_ingredient(id: StringName, qty: int, unit_cost: int) -> bool:
	if id.is_empty() or qty <= 0 or unit_cost < 0:
		return false
	if unit_cost > 0 and qty > MAX_CURRENCY / unit_cost:
		return false
	if qty > Stock.MAX_QUANTITY - stock.count(id):
		return false
	var price: int = qty * unit_cost
	if not can_spend_without_loan(price):
		return false
	stock.add(id, qty, Clock.day)
	ledger.record(Clock.day, -price, Ledger.INGREDIENTS, String(id))
	EventBus.cash_changed.emit(cash, -price, Ledger.INGREDIENTS)
	return true
