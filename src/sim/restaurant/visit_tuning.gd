class_name VisitTuning
extends Resource
## Who visits when (FK-083). Each visit kind (RecipeDef.FOOD, COFFEE, DRINKS)
## has a weight for every hour of the day. While more than one kind is on
## today's menu, an arriving guest draws a kind by these weights (times its
## customer type's preference), and the arrival rate follows their sum.
## A food-only menu between the default opening hours keeps the weight 1.0,
## so default play draws nothing extra and keeps its exact arrival gaps.

const HOURS: int = 24

## Kind -> 24 hourly weights (hour 0 is midnight to 1am).
@export var hourly_weights: Dictionary[StringName, PackedFloat32Array] = {}
## How long a drinks-only guest stays with their drink, in ticks (a meal is 300).
@export var drink_visit_ticks: int = 150
## The arrival rate never falls below this, so a quiet hour still sees guests.
@export var min_arrival_rate: float = 0.25


func is_valid() -> bool:
	if drink_visit_ticks < 1 or not is_finite(min_arrival_rate) or min_arrival_rate <= 0.0:
		return false
	for kind: StringName in RecipeDef.ORDER_TYPES:
		if not hourly_weights.has(kind) or hourly_weights[kind].size() != HOURS:
			return false
		for value: float in hourly_weights[kind]:
			if not is_finite(value) or value < 0.0:
				return false
	return hourly_weights.size() == RecipeDef.ORDER_TYPES.size()


## The weight of a visit kind at a minute of the day (0 when unknown).
func weight(kind: StringName, minute: int) -> float:
	var weights: PackedFloat32Array = hourly_weights.get(kind, PackedFloat32Array())
	if weights.size() != HOURS:
		return 0.0
	return weights[clampi(floori(float(minute) / 60.0), 0, HOURS - 1)]


## Guests per tick relative to today's default: the sum over the kinds on
## the menu. Exactly 1.0 for a food-only menu at a full-weight hour.
func arrival_rate(kinds: Array[StringName], minute: int) -> float:
	var total: float = 0.0
	for kind: StringName in kinds:
		total += weight(kind, minute)
	if total == 1.0:
		return 1.0
	return maxf(total, min_arrival_rate)
