class_name ServiceEventText
extends RefCounted
## Every player-facing preview of a service event choice (#495), in one place
## (code rule 11). A preview names each effect in plain words, cheapest first.

const NOTHING: String = "Nothing happens"
## Why a choice is greyed out (the card shows it in place of the preview).
const NOT_ENOUGH_CASH: String = "Not enough cash"


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
		parts.append("buy %s x%d for %s" % [ingredient, choice.stock_units,
			Fmt.money(stock_cost(choice.stock_units, unit_cost, choice.stock_price_percent))])
	elif choice.stock_units < 0:
		parts.append("uses %s x%d" % [ingredient, -choice.stock_units])
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
	var later: String = "tomorrow" if choice.tomorrow_days <= 1 else "for %d days" % choice.tomorrow_days
	if choice.tomorrow_arrivals_percent > 0:
		parts.append("more guests %s" % later)
	elif choice.tomorrow_arrivals_percent < 0:
		parts.append("fewer guests %s" % later)
	if choice.staff_mood > 0:
		parts.append("%s cheers up" % staff)
	elif choice.staff_mood < 0:
		parts.append("%s sulks" % staff)
	if choice.clean_spots:
		parts.append("the floor gets cleaned")
	if choice.send_home:
		parts.append("%s goes home, still paid" % staff)
	if not choice.follow_up.is_empty():
		parts.append("more to come in a few days")
	if choice.risk_percent > 0 and choice.risk_cash != 0:
		# A gamble (#506): the other way it can go, in money.
		parts.append("or %s if it goes wrong" % signed_money(choice.cash + choice.risk_cash))
		if choice.risk_review_stars > 0:
			parts.append(_risk_words(choice))
	elif choice.risk_percent > 0:
		parts.append(_risk_words(choice))
	if parts.is_empty():
		return NOTHING
	var text: String = ", ".join(parts)
	return text.left(1).to_upper() + text.substr(1)


## "Not enough tomato" for an improvised dish the shelves can't cover.
static func not_enough_stock(ingredient: String) -> String:
	return "Not enough %s" % ingredient


## Why "Off you go" is greyed out: nobody else on the floor does their job.
static func nobody_covers(staff: String) -> String:
	return "Nobody can cover for %s" % (staff if not staff.is_empty() else "them")


## A greyed-out choice's preview: the reason first, then what it would do.
static func refused_preview(reason: String, preview_text: String) -> String:
	return "%s. %s" % [reason, preview_text] if not preview_text.is_empty() else reason


## The Today log line as yesterday's food blogger buzz brings more guests.
static func buzz_line(factor: float) -> String:
	return "Yesterday's food blogger post: more curious faces today (arrivals %s)." % DemandText.change_text(factor)


## The Today log line while a multi-day nudge (#506) brings guests in.
static func later_line(title: String, percent: int) -> String:
	return "%s: %s today (arrivals %s)." % [title, "a few more faces" if percent > 0 else "a quieter street",
		DemandText.change_text(1.0 + float(percent) / 100.0)]


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
