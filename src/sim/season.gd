class_name Season
extends RefCounted
## A deterministic 112-day calendar. The season is derived from the saved day;
## it has no state, random stream or separate save section.

enum Kind { SPRING, SUMMER, AUTUMN, WINTER }
const DAYS_PER_SEASON: int = 28


static func kind_for_day(day: int) -> Kind:
	@warning_ignore("integer_division")
	return (((maxi(day, 1) - 1) / DAYS_PER_SEASON) % 4) as Kind


## The sole seasonal purchase-price calculation. Round each unit once before
## the existing whole-order auto premium or supplier haggle is applied.
static func purchase_unit_cost(id: StringName, base_cost: int, day: int,
		tuning: SeasonTuning) -> int:
	if base_cost <= 0:
		return 0
	if tuning == null:
		return base_cost
	var multiplier: float = tuning.multiplier_for(id, kind_for_day(day))
	if not is_finite(multiplier) or multiplier <= 0.0:
		return base_cost
	return maxi(0, roundi(float(base_cost) * multiplier))
