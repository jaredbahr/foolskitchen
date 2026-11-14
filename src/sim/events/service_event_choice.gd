class_name ServiceEventChoice
extends Resource
## One answer on a service event card (#495). Every effect is small and uses a
## system the shop already has; a zero field does nothing. A "risk" outcome is
## decided by a seeded roll (ServiceEvents.risk_hit), never by global random.

## The button text.
@export var label: String = ""
## What happened, for the Today log and the evening report. Dry, short.
@export var result: String = ""
## Cash in or out, booked under Ledger.SERVICE_EVENT.
@export var cash: int = 0
## One review of this many stars joins the rolling window (0 = none).
@export_range(0, 5) var review_stars: int = 0
## Guests in the shop now get this much more (or less) patience, in seconds.
@export var guest_patience_seconds: int = 0
## Guests arriving later today are this much more patient (percent).
@export var day_patience_percent: int = 0
## Arrivals for the rest of today change by this percent.
@export var day_arrivals_percent: int = 0
## Tomorrow's arrivals change by this percent (it joins tomorrow's demand).
@export var tomorrow_arrivals_percent: int = 0
## Positive: buy this many of the event's ingredient at stock_price_percent of
## its list price. Negative: use this many of it from the shelves.
@export var stock_units: int = 0
@export_range(0, 100) var stock_price_percent: int = 100
## The event's staff member's mood changes by this much (kept between 1 and 3).
@export_range(-1, 1) var staff_mood: int = 0
## Every dirty spot on the floor is cleaned at once.
@export var clean_spots: bool = false
## Chance (percent) that the risk outcome below happens as well.
@export_range(0, 100) var risk_percent: int = 0
## Replaces `result` when the risk happens.
@export var risk_result: String = ""
@export_range(0, 5) var risk_review_stars: int = 0
@export var risk_cash: int = 0
## Share of the units just bought that turn out bad and are thrown away
## (below 100, so the crate always keeps something).
@export_range(0, 99) var risk_stock_lost_percent: int = 0


## The most cash this choice can take, besides a stock purchase: its cost
## plus a costly risk. The card's availability and the effect both use it.
func cash_needed() -> int:
	var worst: int = cash + (mini(0, risk_cash) if risk_percent > 0 else 0)
	return maxi(0, -worst)


## A choice that needs no cash and no stock: every card keeps one, so the
## player can always pick.
func is_free() -> bool:
	return cash_needed() == 0 and stock_units == 0


func errors(who: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if label.strip_edges().is_empty() or label.length() > 40:
		found.append("%s: a choice needs a label of 1-40 characters" % who)
	if result.strip_edges().is_empty() or result.length() > 160:
		found.append("%s: a choice needs a result of 1-160 characters" % who)
	if absi(cash) > 60 or absi(risk_cash) > 60:
		found.append("%s: cash must stay within $60" % who)
	if absi(guest_patience_seconds) > 60:
		found.append("%s: guest patience must stay within 60 s" % who)
	for percent: int in [day_patience_percent, day_arrivals_percent, tomorrow_arrivals_percent]:
		if absi(percent) > 20:
			found.append("%s: day and tomorrow nudges must stay within 20%%" % who)
	if absi(stock_units) > 30:
		found.append("%s: stock changes must stay within 30 units" % who)
	if risk_stock_lost_percent < 0 or risk_stock_lost_percent > 99:
		found.append("%s: a bad batch loses 0-99%% of the crate" % who)
	if risk_percent > 0 and risk_result.strip_edges().is_empty():
		found.append("%s: a risk needs its own result text" % who)
	if risk_percent == 0 and (risk_review_stars != 0 or risk_cash != 0 or risk_stock_lost_percent != 0):
		found.append("%s: risk effects need a risk chance" % who)
	if risk_stock_lost_percent > 0 and stock_units <= 0:
		found.append("%s: only bought stock can go bad" % who)
	return found
