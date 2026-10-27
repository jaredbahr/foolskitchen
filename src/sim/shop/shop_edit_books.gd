class_name ShopEditBooks
extends RefCounted
## Pure callable boundary: inject Economy.can_spend_without_loan/add_cash or
## fake methods. The record callback receives a signed amount and category.
## The affordability and optional refusal-reason callbacks must be read-only.
## Both callbacks must remain valid for an edit; recording applies exactly once.

const CASH_REFUSAL: String = "Not enough cash; furniture cannot use a loan"

var _can_spend: Callable
var _record: Callable
var _refusal_reason: Callable


func _init(can_spend: Callable = Callable(), record: Callable = Callable(),
		refusal_reason: Callable = Callable()) -> void:
	_can_spend = can_spend
	_record = record
	_refusal_reason = refusal_reason


func is_ready() -> bool:
	return _can_spend.is_valid() and _record.is_valid()


func can_spend_without_loan(amount: int) -> bool:
	if amount < 0 or not is_ready():
		return false
	var answer: Variant = _can_spend.call(amount)
	return answer is bool and answer


## A note (for example ShopEditHistory.UNDO_NOTE) is passed only to record
## callbacks that take a third argument; two-argument fakes keep working.
func add_cash(amount: int, category: StringName, note: String = "") -> void:
	if not note.is_empty() and _record.get_argument_count() >= 3:
		_record.call(amount, category, note)
	else:
		_record.call(amount, category)


## Legacy cash-only callers keep their existing explanation.
func purchase_refusal_reason(amount: int) -> String:
	if _refusal_reason.is_valid():
		var answer: Variant = _refusal_reason.call(amount)
		if answer is String and not String(answer).strip_edges().is_empty():
			return answer
	return CASH_REFUSAL
