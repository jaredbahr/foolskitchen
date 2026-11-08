class_name HaggleRules
extends RefCounted
## Pure timing scores and exact whole-currency manual-order quotes.

const MAX_VALUE: int = 9223372036854775807


static func discount_percent(result: float, max_discount: float) -> int:
	if not is_finite(result) or not is_finite(max_discount):
		return 0
	var limit: float = clampf(max_discount, 0.0, 1.0)
	var maximum: int = roundi(limit * 100.0)
	# A fractional authored cap (10.5%) permits at most 10 whole percent.
	# Compare fractions to avoid flooring a decimal 0.29 * 100 to 28.
	if float(maximum) / 100.0 > limit:
		maximum -= 1
	return clampi(roundi(clampf(result, 0.0, 1.0) * maximum), 0, maximum)


## Exactly one draw per round, once at start. The view never retains the RNG.
static func zone_centers(tuning: HaggleTuning, rng: RandomNumberGenerator) -> Array[float]:
	var out: Array[float] = []
	if tuning == null or not tuning.is_valid() or rng == null:
		return out
	for width: float in tuning.zone_widths:
		out.append(rng.randf_range(width * 0.5, 1.0 - width * 0.5))
	return out


static func score(marker: float, center: float, width: float) -> float:
	if not is_finite(marker) or not is_finite(center) or not is_finite(width) or width <= 0.0:
		return 0.0
	return clampf(1.0 - absf(marker - center) / (width * 0.5), 0.0, 1.0)


## Ceil the discounted whole order. Decomposition avoids total * percent
## overflowing: no one-unit order becomes free at the authored 10% maximum.
@warning_ignore("integer_division")
static func charge(list_total: int, percent: int) -> int:
	if list_total < 0 or percent < 0 or percent > 100:
		return -1
	var saved: int = (list_total / 100) * percent + ((list_total % 100) * percent) / 100
	return list_total - saved


## The difference of rounded cumulative prices allocates the one rounded
## charge without negative free lines or floats. Stable input order decides
## rounding ties. Failure returns {} without mutating source lines.
@warning_ignore("integer_division")
static func quote(lines: Array[Dictionary], percent: int) -> Dictionary:
	if lines.is_empty() or lines.size() > DeliveryBook.MAX_LINES or percent < 0 or percent > 100:
		return {}
	var lots: Array[Dictionary] = []
	var total: int = 0
	var previous_charge: int = 0
	for line: Dictionary in lines:
		var raw_id: Variant = line.get("id", null)
		var qty: int = PurchaseBasis.decode(line.get("qty", null))
		var unit_cost: int = PurchaseBasis.decode(line.get("unit_cost", null))
		if not (raw_id is String or raw_id is StringName) or String(raw_id).is_empty() \
				or qty <= 0 or unit_cost < 0:
			return {}
		if unit_cost > 0 and qty > (MAX_VALUE - total) / unit_cost:
			return {}
		total += qty * unit_cost
		var cumulative_charge: int = charge(total, percent)
		lots.append({"id": StringName(raw_id), "qty": qty,
			"total_cost": cumulative_charge - previous_charge})
		previous_charge = cumulative_charge
	return {"lines": lots, "list_total": total, "cost": previous_charge,
		"saved": total - previous_charge, "percent": percent}
