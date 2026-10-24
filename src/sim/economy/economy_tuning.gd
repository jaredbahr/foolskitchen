class_name EconomyTuning
extends Resource
## Money numbers for a property tier, kept as data so balancing never needs
## code changes (data/balance/*.tres). All amounts are whole currency units.

## Cash a new game starts with.
@export var starting_cash: int = 300
## Durable plates available to the new shop; overnight washing keeps this total.
@export var starting_plates: int = 12
## One-time morning tray upgrades: first two plates, then four.
@export var tray_prices: PackedInt32Array = PackedInt32Array([60, 150])
## Rent charged at the end of every day.
@export var daily_rent: int = 40
## Wage per staff role, charged at the end of every day.
@export var wages: Dictionary[StringName, int] = {&"cook": 30, &"server": 25, &"cleaner": 20}
## Skill 1..5 wage multipliers; skill 3 keeps the starting role wage.
@export var staff_wage_curve: PackedFloat32Array = PackedFloat32Array([0.7, 0.85, 1.0, 1.2, 1.4])
## Each morning the fridge is topped up to this many units per ingredient,
## paid at the ingredient's unit cost (a Phase 1 stand-in for the market screen).
@export var morning_stock: Dictionary[StringName, int] = {}

## Ticks between guest arrivals while open (uniform in [min, max]).
@export var arrival_gap_min: int = 100
@export var arrival_gap_max: int = 260

## Over-standard prices may make a guest refuse the dish at order time.
@export_range(0.0, 10.0, 0.05) var price_sensitivity: float = 1.5
@export_range(0.0, 1.0, 0.01) var max_price_walkout: float = 0.9


func staff_wage(role: StringName, skill: int) -> int:
	var base: int = maxi(0, wages.get(role, 0))
	var index: int = clampi(skill, 1, 5) - 1
	var multiplier: float = staff_wage_curve[index] if index < staff_wage_curve.size() else 1.0
	if not is_finite(multiplier) or multiplier < 0.0:
		multiplier = 1.0
	return clampi(roundi(base * multiplier), 0, 1000000)
