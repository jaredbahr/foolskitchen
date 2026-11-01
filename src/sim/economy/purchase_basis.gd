class_name PurchaseBasis
extends RefCounted
## Whole-unit purchase values. Missing historical prices remain unavailable.

const MAX_VALUE: int = 9223372036854775807


## A zero-cost purchase is recorded; an unknown purchase is not zero-cost.
static func zero() -> Dictionary:
	return {"cost": 0, "recorded": true}


## Cost-only overflow never prevents a physical stock movement or purchase.
static func combine(target: Dictionary, source: Dictionary) -> void:
	var cost: int = int(source.get("cost", 0))
	if cost < 0 or cost > MAX_VALUE - int(target["cost"]):
		target["cost"] = 0
		target["recorded"] = false
		return
	target["cost"] = int(target["cost"]) + cost
	target["recorded"] = bool(target["recorded"]) and bool(source.get("recorded", false))


## Decimal strings preserve int64 values through JSON. Numeric legacy values
## are accepted only within JSON's exact integer range; malformed values fail.
static func decode(value: Variant) -> int:
	if value is int:
		return value if value >= 0 else -1
	if value is float:
		var number: float = value
		return int(number) if is_finite(number) and number >= 0.0 \
			and number <= 9007199254740991.0 and floorf(number) == number else -1
	if not value is String:
		return -1
	var digits: String = value
	if digits.is_empty() or digits.length() > 19:
		return -1
	for index: int in range(digits.length()):
		if digits.unicode_at(index) < 48 or digits.unicode_at(index) > 57:
			return -1
	if digits.length() == 19 and digits > str(MAX_VALUE):
		return -1
	return int(digits)


## The exact charged premium is shared equally across order lines, with the
## first remainder lines receiving one more unit. Each lot then shares its
## total among units using Stock's FIFO quotient/remainder convention. This
## deterministic allocation conserves cash, including zero-price lines.
@warning_ignore("integer_division")
static func allocate(lines: Array[Dictionary], charged_total: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list_total: int = 0
	var valid: bool = true
	for line: Dictionary in lines:
		var copied: Dictionary = {"id": StringName(line.get("id", &"")), "qty": int(line.get("qty", 0))}
		var qty: int = int(copied["qty"])
		var unit_cost: int = decode(line.get("unit_cost", null))
		var cost: int = decode(line.get("total_cost", null))
		if charged_total >= 0 or not line.has("total_cost"):
			cost = -1
			if qty > 0 and unit_cost >= 0 and (unit_cost == 0 or qty <= MAX_VALUE / unit_cost):
				cost = qty * unit_cost
		if cost >= 0:
			copied["total_cost"] = cost
		if cost < 0 or cost > MAX_VALUE - list_total:
			valid = false
		else:
			list_total += cost
		out.append(copied)
	if charged_total < 0:
		return out
	if out.is_empty() or not valid or charged_total < list_total:
		for line: Dictionary in out:
			line.erase("total_cost")
		return out
	var premium: int = charged_total - list_total
	var share: int = premium / out.size()
	var remainder: int = premium % out.size()
	for index: int in range(out.size()):
		out[index]["total_cost"] = int(out[index]["total_cost"]) + share + (1 if index < remainder else 0)
	return out
