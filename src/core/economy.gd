extends Node
## Money (stub for Phase 0). All amounts are whole currency units (int) so
## totals never drift from float rounding.

var cash: int = 0


## Adds (or, with a negative amount, removes) cash and announces it.
func add_cash(amount: int, reason: StringName) -> void:
	cash += amount
	EventBus.cash_changed.emit(cash, amount, reason)
