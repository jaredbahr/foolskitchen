class_name EconomyTuning
extends Resource
## Money numbers for a property tier, kept as data so balancing never needs
## code changes (data/balance/*.tres). All amounts are whole currency units.

## Cash a new game starts with.
@export var starting_cash: int = 300
## Rent charged at the end of every day.
@export var daily_rent: int = 40
## Wage per staff role, charged at the end of every day.
@export var wages: Dictionary[StringName, int] = {&"cook": 30, &"server": 25}
## Each morning the fridge is topped up to this many units per ingredient,
## paid at the ingredient's unit cost (a Phase 1 stand-in for the market screen).
@export var morning_stock: Dictionary[StringName, int] = {}

## Ticks between guest arrivals while open (uniform in [min, max]).
@export var arrival_gap_min: int = 100
@export var arrival_gap_max: int = 260

## Over-standard prices may make a guest refuse the dish at order time.
@export_range(0.0, 10.0, 0.05) var price_sensitivity: float = 1.5
@export_range(0.0, 1.0, 0.01) var max_price_walkout: float = 0.9
