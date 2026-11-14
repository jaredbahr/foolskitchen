class_name ServiceEventTuning
extends Resource
## How many service event cards a day brings and when (#495;
## data/balance/service_events.tres).

## Every open service day brings at least one card (when one can come up)...
@export var min_per_day: int = 1
## ...and at most this many.
@export var max_per_day: int = 2
## Chance (percent) that a day brings the second card.
@export_range(0, 100) var second_card_percent: int = 50
## No card in the first and last minutes of service.
@export var opening_margin_minutes: int = 45
@export var closing_margin_minutes: int = 60
## Minutes kept clear around a rush, a booked party or the critic's arrival.
@export var clear_minutes: int = 20
## Two cards on one day come at least this far apart.
@export var min_gap_minutes: int = 90
## Cards land on whole steps of the shop clock.
@export var step_minutes: int = 5


func is_valid() -> bool:
	return min_per_day >= 0 and max_per_day >= min_per_day and max_per_day <= 3 \
		and second_card_percent >= 0 and second_card_percent <= 100 \
		and opening_margin_minutes >= 0 and opening_margin_minutes <= 240 \
		and closing_margin_minutes >= 0 and closing_margin_minutes <= 240 \
		and clear_minutes >= 0 and clear_minutes <= 120 \
		and min_gap_minutes >= 0 and min_gap_minutes <= 360 \
		and step_minutes >= 1 and step_minutes <= 60
