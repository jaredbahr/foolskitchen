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
## The site whose day is being played (FK-087). Every ledger entry Economy
## records is stamped with it. Not saved: main.gd sets it from its SiteBook in
## _wire_session(), which runs after a new game, a load and (later) a site
## switch, before that site's morning. Change it only via set_active_site().
var active_site: StringName = Ledger.HOME_SITE
## What purchases can spend: the cash in career; in a Creative game (FK-141)
## a budget no price reaches, because building, stock and upgrades are free.
const CREATIVE_BUDGET: int = 1000000000
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
	SaveSystem.register("economy", _capture_books, _restore_books)
	SaveSystem.register("pantry", _capture_pantry, _restore_pantry)


## Starts a fresh game's books: no history, the given cash, empty stock.
func reset(starting_cash: int) -> void:
	ledger = Ledger.new()
	ledger.cash = starting_cash
	stock = Stock.new()
	loan = LoanAccount.new()
	active_site = Ledger.HOME_SITE
	EventBus.cash_changed.emit(cash, 0, Ledger.OTHER)


## Makes `site` the one new ledger entries belong to. Returns false, changing
## nothing, for an id SiteBook would refuse.
func set_active_site(site: StringName) -> bool:
	if not Ledger.is_valid_site(site):
		return false
	active_site = site
	return true


## The whole money state (books and pantry) as one snapshot. Tests use it to
## save and put back everything Economy owns; saves use the two sections below.
func _capture_save() -> Dictionary:
	var data: Dictionary = _capture_books()
	data.merge(_capture_pantry())
	return data


## Restores a whole snapshot from _capture_save(). Nothing changes on a refusal.
func _restore_save(data: Dictionary) -> bool:
	var parsed: Dictionary = _parse_books(data)
	var restored_stock: Stock = _parse_stock(data)
	if parsed.is_empty() or restored_stock == null:
		return false
	_install_books(parsed)
	stock = restored_stock
	EventBus.cash_changed.emit(cash, 0, Ledger.OTHER)
	return true


## The shared "economy" save section: the ledger (cash) and the loan. These
## belong to the owner and stay put when sites switch (FK-087).
func _capture_books() -> Dictionary:
	return {"ledger": ledger.to_dict(), "loan": loan.to_dict()}


func _restore_books(data: Dictionary) -> bool:
	var parsed: Dictionary = _parse_books(data)
	if parsed.is_empty():
		return false
	_install_books(parsed)
	EventBus.cash_changed.emit(cash, 0, Ledger.OTHER)
	return true


## The per-site "pantry" section: the kitchen's stock on hand. Restoring fills
## the existing Stock in place, so the kitchen's reference stays valid even
## when SaveSystem.restore_sections rolls a refused site switch back.
func _capture_pantry() -> Dictionary:
	return {"stock": stock.to_dict()}


func _restore_pantry(data: Dictionary) -> bool:
	var restored_stock: Stock = _parse_stock(data)
	if restored_stock == null:
		return false
	stock.replace_with(restored_stock)
	return true


## Returns {"ledger", "loan"} models, or {} when the data is not valid books.
func _parse_books(data: Dictionary) -> Dictionary:
	var ledger_data: Variant = data.get("ledger", null)
	if not ledger_data is Dictionary:
		return {}
	var restored_loan: LoanAccount = LoanAccount.new()
	if data.has("loan"):
		restored_loan = LoanAccount.from_dict(data["loan"])
		if restored_loan == null:
			return {}
	var restored_ledger: Ledger = Ledger.from_dict(ledger_data)
	if restored_ledger == null:
		return {}
	return {"ledger": restored_ledger, "loan": restored_loan}


func _install_books(parsed: Dictionary) -> void:
	ledger = parsed["ledger"]
	loan = parsed["loan"]


func _parse_stock(data: Dictionary) -> Stock:
	var stock_data: Variant = data.get("stock", null)
	if not stock_data is Dictionary:
		return null
	return Stock.from_dict(stock_data)


## Adds (or, with a negative amount, removes) cash and announces it. The
## optional note marks special lines, such as shop-edit undo and redo (FK-085).
func add_cash(amount: int, reason: StringName, note: String = "") -> void:
	if GameMode.is_creative():
		return
	ledger.record(Clock.day, amount, reason, note, active_site)
	EventBus.cash_changed.emit(cash, amount, reason)


## Like add_cash, but booked to another site's books (FK-087): an inactive
## site's away income, rent or lapsed booking refund at the active site's
## close, so the active site's per-site readers leave it out. Returns false
## and moves nothing for an invalid site id.
func add_cash_for_site(amount: int, reason: StringName, note: String, site: StringName) -> bool:
	if not Ledger.is_valid_site(site):
		return false
	if GameMode.is_creative():
		return true
	ledger.record(Clock.day, amount, reason, note, site)
	EventBus.cash_changed.emit(cash, amount, reason)
	return true


## Money is off in a Creative game (FK-141): nothing costs anything, no
## money moves and no loan opens. Every money path below reads this.
func is_free() -> bool:
	return GameMode.is_creative()


## The cash a purchase may spend (see CREATIVE_BUDGET). Planning and refusal
## text read this instead of cash, so a Creative game never says "can't afford".
func spendable() -> int:
	return CREATIVE_BUDGET if is_free() else cash


## Ingredients and wages remain available while a bank loan is open.
func can_spend_without_loan(amount: int) -> bool:
	return amount >= 0 and (is_free() or cash >= amount)


## Furniture over the authored limit waits for the loan to close.
## Main will wire this to build commands during UI integration.
func can_buy_discretionary(amount: int) -> bool:
	return can_spend_without_loan(amount) \
		and (is_free() or loan.principal == 0 or amount <= LOAN_TERMS.large_purchase_limit)


## Every upgrade waits for the loan to close, including cheap ones. This is
## separate from the furniture price limit so tray-like upgrades cannot slip
## through a $50 threshold check.
func can_buy_upgrade(amount: int) -> bool:
	return (is_free() or loan.principal == 0) and can_spend_without_loan(amount)


## Main calls this once after wages and rent, before constructing the report.
## Every bank flow is recorded under its own ledger category. Once all entries
## are applied, emit their running balances in transaction order for the HUD;
## callbacks that read Economy.cash see the already-settled final balance.
## Optional pre-bonus profit changes only the repayment base, never actual cash.
func settle_loan_day(day: int, repayment_profit: Variant = null) -> Dictionary:
	if is_free():
		return {}
	var running_cash: int = cash
	var result: Dictionary = loan.settle_day(ledger, day, LOAN_TERMS, repayment_profit, active_site)
	for movement: Dictionary in result.get("movements", []):
		var amount: int = int(movement["amount"])
		var reason: StringName = movement["category"]
		running_cash += amount
		EventBus.cash_changed.emit(running_cash, amount, reason)
	return result


## Posts voluntary principal repayment before notifying cash and loan observers.
func repay_loan_now(amount: int) -> int:
	if is_free():
		return 0
	var paid: int = loan.repay_now(ledger, amount, Clock.sim.day, active_site)
	if paid > 0:
		EventBus.cash_changed.emit(cash, -paid, Ledger.EARLY_LOAN_REPAYMENT)
	return paid


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
	stock.add(id, qty, Clock.day, price)
	if is_free():
		return true
	ledger.record(Clock.day, -price, Ledger.INGREDIENTS, String(id), active_site)
	EventBus.cash_changed.emit(cash, -price, Ledger.INGREDIENTS)
	return true


## Buys a planned morning auto-order atomically, or returns false without
## changes. Each line is recorded at list price; the order's premium (the
## planned cost above its list total) is one extra ingredients entry.
## Lines: [{id: StringName, qty: int, unit_cost: int}]. Never borrows.
func buy_auto_order(lines: Array[Dictionary], cost: int) -> bool:
	if not pay_order(lines, cost, true):
		return false
	receive(lines, cost)
	return true


## Narrow morning-only purchase path. Its exact discounted line costs are
## both the ledger debits and the received lot values; no refund is invented.
## The session owns the one-attempt/one-use offer. Ordinary orders keep their
## existing pay_order and premium validation unchanged.
func buy_haggled_order(lines: Array[Dictionary], percent: int) -> bool:
	if Clock.sim.phase != SimClock.Phase.MORNING:
		return false
	var quoted: Dictionary = HaggleRules.quote(lines, percent)
	if quoted.is_empty() or not can_spend_without_loan(int(quoted["cost"])):
		return false
	var added: Dictionary[StringName, int] = {}
	var lots: Array[Dictionary] = []
	lots.assign(quoted["lines"])
	for lot: Dictionary in lots:
		var id: StringName = lot["id"]
		var qty: int = int(lot["qty"])
		if qty > Stock.MAX_QUANTITY - stock.count(id) - added.get(id, 0):
			return false
		added[id] = added.get(id, 0) + qty
	if is_free():
		receive(lots)
		return true
	for lot: Dictionary in lots:
		ledger.record(Clock.day, -int(lot["total_cost"]), Ledger.INGREDIENTS, String(lot["id"]), active_site)
	receive(lots)
	EventBus.cash_changed.emit(cash, -int(quoted["cost"]), Ledger.INGREDIENTS)
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
	if is_free():
		return true
	for line: Dictionary in lines:
		var id: StringName = line["id"]
		var price: int = int(line["qty"]) * int(line["unit_cost"])
		ledger.record(Clock.day, -price, Ledger.INGREDIENTS,
			(AUTO_LINE_PREFIX + String(id)) if standing else String(id), active_site)
		EventBus.cash_changed.emit(cash, -price, Ledger.INGREDIENTS)
	if cost > list_total:
		ledger.record(Clock.day, list_total - cost, Ledger.INGREDIENTS, AUTO_PREMIUM_NOTE, active_site)
		EventBus.cash_changed.emit(cash, list_total - cost, Ledger.INGREDIENTS)
	return true


## A delivery arrives: its lines join the stock, dated today (shelf life
## counts from the delivery). Lines: [{id, qty}].
func receive(lines: Array[Dictionary], charged_total: int = -1) -> void:
	for line: Dictionary in PurchaseBasis.allocate(lines, charged_total):
		stock.add(StringName(line.get("id", &"")), int(line.get("qty", 0)), Clock.day,
			int(line.get("total_cost", -1)))


## A cancelled order's full refund, as one ingredients entry.
func refund_order(amount: int) -> void:
	if amount <= 0 or is_free():
		return
	ledger.record(Clock.day, amount, Ledger.INGREDIENTS, ORDER_REFUND_NOTE, active_site)
	EventBus.cash_changed.emit(cash, amount, Ledger.INGREDIENTS)
