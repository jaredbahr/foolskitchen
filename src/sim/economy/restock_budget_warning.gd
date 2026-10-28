class_name RestockBudgetWarning
extends RefCounted
## Advisory only: never changes the purchase check or the order plan.
static func text(cash: int, purchase_cost: int, restock_estimate: int) -> String:
	if purchase_cost <= 0 or cash < purchase_cost or restock_estimate <= 0:
		return ""
	var left: int = cash - purchase_cost
	if left >= restock_estimate:
		return ""
	return "Leaves %s; allow about %s for restocking" % [Fmt.money(left), Fmt.money(restock_estimate)]