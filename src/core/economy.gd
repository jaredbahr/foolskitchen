extends Node
## Autoload adapter for the pure ledger and ingredient stock models.
## Money is always whole currency units. Automatic loans are settled at close;
## ordinary purchases never borrow against the next day's income.

const MAX_CURRENCY: int = 9223372036854775807
const LOAN_TERMS: LoanTuning = preload("res://data/balance/loans.tres")
## Ledger notes that mark the morning auto-order's lines and its premium.
const AUTO_LINE_PREFIX: String = "auto_reorder:"
const AUTO_PREMIUM_NOTE: String = "auto_reorder_premium"
## Ledger note of a cancelled order's refund (FK-087).
const ORDER_REFUND_NOTE: String = "order_refund"

var ledger: Ledger = Ledger.new()
var stock: Stock = Stock.new()
var loan: LoanAccount = LoanAccount.new()
## Legacy balance access. Assignments record their difference under OTHER.
var cash: int:
	get:
		return ledger.cash
	set(value):
		if value != ledger.cash:
			add_cash(value - ledger.cash, Ledger.OTHER)


func _ready() -> void:
	register_save_provider()


## Registers this autoload's save section. Idempotent; the game session also
## calls it, because some hosts (the test runner) never deliver _ready().
func register_save_provider() -> void:
	SaveSystem.register("economy", _capture_save, _restore_save)


## Starts a fresh game's books: no history, the given cash, empty stock.
func reset(starting_cash: int) -> void:
	ledger = Ledger.new()
	ledger.cash = starting_cash
	stock = Stock.new()
	loan = LoanAccount.new()
	EventBus.cash_changed.emit(cash, 0, Ledger.OTHER)


func _capture_save() -> Dictionary:
	return {"ledger": ledger.to_dict(), "stock": stock.to_dict(), "loan": loan.to_dict()}


func _restore_save(data: Dictionary) -> bool:
	var ledger_data: Variant = data.get("ledger", null)
	var stock_data: Variant = data.get("stock", null)
	if not ledger_data is Dictionary or not stock_data is Dictionary:
		return false
	var restored_loan: LoanAccount = LoanAccount.new()
	if data.has("loan"):
		restored_loan = LoanAccount.from_dict(data["loan"])
		if restored_loan == null:
			return false
	ledger = Ledger.from_dict(ledger_data)
	stock = Stock.from_dict(stock_data)
	loan = restored_loan
	EventBus.cash_changed.emit(cash, 0, Ledger.OTHER)
	return true


## Adds (or, with a negative amount, removes) cash and announces it. The
## optional note marks special lines, such as shop-edit undo and redo (FK-085).
func add_cash(amount: int, reason: StringName, note: String = "") -> void:
	ledger.record(Clock.day, amount, reason, note)
	EventBus.cash_changed.emit(cash, amount, reason)


## Ingredients and wages remain available while a bank loan is open.
func can_spend_without_loan(amount: int) -> bool:
	return amount >= 0 and cash >= amount


## Furniture over the authored limit waits for the loan to close.
## Main will wire this to build commands during UI integration.
func can_buy_discretionary(amount: int) -> bool:
	return can_spend_without_loan(amount) \
		and (loan.principal == 0 or amount <= LOAN_TERMS.large_purchase_limit)


## Every upgrade waits for the loan to close, including cheap ones. This is
## separate from the furniture price limit so tray-like upgrades cannot slip
## through a $50 threshold check.
func can_buy_upgrade(amount: int) -> bool:
	return loan.principal == 0 and can_spend_without_loan(amount)


## Main calls this once after wages and rent, before constructing the report.
## Every bank flow is recorded under its own ledger category. Once all entries
## are applied, emit their running balances in transaction order for the HUD;
## callbacks that read Economy.cash see the already-settled final balance.
## Optional pre-bonus profit changes only the repayment base, never actual cash.
func settle_loan_day(day: int, repayment_profit: Variant = null) -> Dictionary:
	var running_cash: int = cash
	var result: Dictionary = loan.settle_day(ledger, day, LOAN_TERMS, repayment_profit)
	for movement: Dictionary in result.get("movements", []):
		var amount: int = int(movement["amount"])
		var reason: StringName = movement["category"]
		running_cash += amount
		EventBus.cash_changed.emit(running_cash, amount, reason)
	return result


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


## Buys a planned morning auto-order atomically, or returns false without
## changes. Each line is recorded at list price; the order's premium (the
## planned cost above its list total) is one extra ingredients entry.
## Lines: [{id: StringName, qty: int, unit_cost: int}]. Never borrows.
func buy_auto_order(lines: Array[Dictionary], cost: int) -> bool:
	if not pay_order(lines, cost, true):
		return false
	receive(lines)
	return true


## Pays for an order without stocking it (FK-087: it arrives with a later
## delivery). Atomic: returns false without changes. A standing order (the
## auto-reorder) records its lines as auto-order lines plus the premium
## entry; a hand order records each line at list price under its ingredient.
## `cost` may exceed the list total only for a standing order. Never borrows.
@warning_ignore("integer_division")
func pay_order(lines: Array[Dictionary], cost: int, standing: bool) -> bool:
	var list_total: int = 0
	var added: Dictionary[StringName, int] = {}
	for line: Dictionary in lines:
		var id: StringName = line.get("id", &"")
		var qty: int = int(line.get("qty", 0))
		var unit_cost: int = int(line.get("unit_cost", -1))
		if id.is_empty() or qty <= 0 or unit_cost < 0:
			return false
		if unit_cost > 0 and qty > (MAX_CURRENCY - list_total) / unit_cost:
			return false
		if qty > Stock.MAX_QUANTITY - stock.count(id) - added.get(id, 0):
			return false
		added[id] = added.get(id, 0) + qty
		list_total += qty * unit_cost
	if lines.is_empty() or cost < list_total or (not standing and cost != list_total) \
			or not can_spend_without_loan(cost):
		return false
	for line: Dictionary in lines:
		var id: StringName = line["id"]
		var price: int = int(line["qty"]) * int(line["unit_cost"])
		ledger.record(Clock.day, -price, Ledger.INGREDIENTS, (AUTO_LINE_PREFIX + String(id)) if standing else String(id))
		EventBus.cash_changed.emit(cash, -price, Ledger.INGREDIENTS)
	if cost > list_total:
		ledger.record(Clock.day, list_total - cost, Ledger.INGREDIENTS, AUTO_PREMIUM_NOTE)
		EventBus.cash_changed.emit(cash, list_total - cost, Ledger.INGREDIENTS)
	return true


## A delivery arrives: its lines join the stock, dated today (shelf life
## counts from the delivery). Lines: [{id, qty}].
func receive(lines: Array[Dictionary]) -> void:
	for line: Dictionary in lines:
		stock.add(StringName(line.get("id", &"")), int(line.get("qty", 0)), Clock.day)


## A cancelled order's full refund, as one ingredients entry.
func refund_order(amount: int) -> void:
	if amount <= 0:
		return
	ledger.record(Clock.day, amount, Ledger.INGREDIENTS, ORDER_REFUND_NOTE)
	EventBus.cash_changed.emit(cash, amount, Ledger.INGREDIENTS)
