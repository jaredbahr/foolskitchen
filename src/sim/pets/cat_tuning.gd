class_name CatTuning
extends Resource
## The restaurant cat (#119), in data (data/balance/cat.tres). Prices and the
## charm come from here; nothing about the cat is hard-coded in the sim.

## Shop (owner) level from which the one-time adoption offer appears.
@export var unlock_level: int = 4
## One-time adoption price, charged in the morning.
@export var adoption_price: int = 40
## Cat food, charged with the other closing costs every day while adopted.
@export var daily_food_cost: int = 2
## The name a new cat has.
@export var default_name: String = "Biscuit"
## Longest name a saved game may hold.
@export var max_name_length: int = 24

## Charm: waiting guests this close to the cat (grid cells, Chebyshev) are more
## patient, by this share of their patience budget.
@export var charm_radius: int = 2
@export_range(0.0, 1.0, 0.01) var charm_patience_bonus: float = 0.10
## A waiting guest this close may pet the cat, once per visit.
@export var pet_radius: int = 1
## Ticks the cat stays still while being petted (10 ticks a second).
@export var pet_pause_ticks: int = 20

## Walking: ticks per straight step (a diagonal step takes about 1.4 times as long).
@export var step_ticks: int = 8
## How far (in steps) a stroll or a nap trip may go from where the cat stands.
@export var wander_range: int = 9
## Share of decisions that head for a nap spot rather than a stroll.
@export_range(0.0, 1.0, 0.01) var nap_chance: float = 0.45
## Ticks of sitting still after a stroll, and of a nap (min, max).
@export var idle_ticks_min: int = 30
@export var idle_ticks_max: int = 90
@export var nap_ticks_min: int = 400
@export var nap_ticks_max: int = 900
## Ticks the cat sleeps at its bed spot at the start of every day.
@export var morning_nap_ticks: int = 300


func is_valid() -> bool:
	for value: float in [charm_patience_bonus]:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	return unlock_level >= 1 and adoption_price >= 0 and adoption_price <= 100000 \
		and daily_food_cost >= 0 and daily_food_cost <= 100000 \
		and not default_name.strip_edges().is_empty() and default_name.length() <= max_name_length \
		and max_name_length >= 1 and charm_radius >= 0 and pet_radius >= 0 and pet_pause_ticks >= 0 \
		and step_ticks >= 1 and wander_range >= 1 and idle_ticks_min >= 1 \
		and idle_ticks_max >= idle_ticks_min and nap_ticks_min >= 1 and nap_ticks_max >= nap_ticks_min \
		and morning_nap_ticks >= 0


## The share of each waiting tick handed back to a guest in charm range, so a
## +10% patience budget lasts exactly 10% longer (b / (1 + b)).
func refund_per_tick() -> float:
	return charm_patience_bonus / (1.0 + charm_patience_bonus)
