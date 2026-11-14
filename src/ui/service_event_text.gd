class_name ServiceEventText
extends RefCounted
## Every player-facing preview of a service event choice (#495), in one place
## (code rule 11). A preview names each effect in plain words, cheapest first.

const NOTHING: String = "Nothing happens"
const OWNER_JOBS: Dictionary = {
	&"kitchen": "you cover the kitchen",
	&"floor": "you cover the floor",
	&"help": "you pitch in",
}


## The cash a stock purchase costs: list price times units, at a discount,
## never below $1 for a real purchase.
static func stock_cost(units: int, unit_cost: int, percent: int) -> int:
	if units <= 0 or unit_cost <= 0:
		return 0
	return maxi(1, roundi(float(units * unit_cost) * float(percent) / 100.0))


## "-$10, guests more patient today". `names` fills {staff} and {ingredient};
## `unit_cost` prices a stock purchase.
static func preview(choice: ServiceEventChoice, names: Dictionary = {}, unit_cost: int = 0) -> String:
	if choice == null:
		return ""
	var parts: PackedStringArray = []
	var ingredient: String = String(names.get("ingredient", "stock"))
	var staff: String = String(names.get("staff", "they"))
	if choice.cash != 0:
		parts.append(signed_money(choice.cash))
	if choice.stock_units > 0:
		parts.append("buy %d %s for %s" % [choice.stock_units, ingredient,
			Fmt.money(stock_cost(choice.stock_units, unit_cost, choice.stock_price_percent))])
	elif choice.stock_units < 0:
		parts.append("uses %d %s" % [-choice.stock_units, ingredient])
	if choice.review_stars > 0:
		parts.append("a %d-star review" % choice.review_stars)
	if choice.guest_patience_seconds > 0:
		parts.append("guests here wait %d s longer" % choice.guest_patience_seconds)
	elif choice.guest_patience_seconds < 0:
		parts.append("guests here lose %d s of patience" % -choice.guest_patience_seconds)
	if choice.day_patience_percent > 0:
		parts.append("guests more patient today")
	elif choice.day_patience_percent < 0:
		parts.append("guests less patient today")
	if choice.day_arrivals_percent > 0:
		parts.append("more walk-ins today")
	elif choice.day_arrivals_percent < 0:
		parts.append("fewer walk-ins today")
	if choice.tomorrow_arrivals_percent > 0:
		parts.append("more guests tomorrow")
	elif choice.tomorrow_arrivals_percent < 0:
		parts.append("fewer guests tomorrow")
	if choice.staff_mood > 0:
		parts.append("%s cheers up" % staff)
	elif choice.staff_mood < 0:
		parts.append("%s sulks" % staff)
	if OWNER_JOBS.has(choice.owner_mode):
		parts.append(OWNER_JOBS[choice.owner_mode])
	if choice.clean_spots:
		parts.append("the floor gets cleaned")
	if choice.risk_percent > 0:
		parts.append(_risk_words(choice))
	if parts.is_empty():
		return NOTHING
	var text: String = ", ".join(parts)
	return text.left(1).to_upper() + text.substr(1)


static func signed_money(amount: int) -> String:
	return ("+" if amount > 0 else "") + Fmt.money(amount)


static func _risk_words(choice: ServiceEventChoice) -> String:
	if choice.risk_stock_lost_percent > 0:
		return "might be a bad batch"
	if choice.review_stars > 0 and choice.risk_review_stars > 0:
		return "could go either way"
	if choice.risk_review_stars > 0 and choice.risk_review_stars <= 2:
		return "risk of a bad review"
	if choice.risk_review_stars >= 4:
		return "might earn a good review"
	return "a small risk"
