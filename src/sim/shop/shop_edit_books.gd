class_name ShopEditBooks
extends RefCounted
## Pure callable boundary: inject Economy.can_spend_without_loan/add_cash or
## fake methods. The record callback receives a signed amount and category.
## The affordability callback must be read-only.
## Both callbacks must remain valid for an edit; recording applies exactly once.

var _can_spend: Callable
var _record: Callable


func _init(can_spend: Callable = Callable(), record: Callable = Callable()) -> void:
	_can_spend = can_spend
	_record = record


func is_ready() -> bool:
	return _can_spend.is_valid() and _record.is_valid()


func can_spend_without_loan(amount: int) -> bool:
	if amount < 0 or not is_ready():
		return false
	var answer: Variant = _can_spend.call(amount)
	return answer is bool and answer


func add_cash(amount: int, category: StringName) -> void:
	_record.call(amount, category)
