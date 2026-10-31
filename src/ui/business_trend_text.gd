class_name BusinessTrendText
extends RefCounted
## Plain wording and detached display rows for completed business days.

const HEADING: String = "This week"
const EMPTY: String = "Come back tomorrow to see your trend."
const UNAVAILABLE: String = "There isn't enough information to compare dish profit."
const PROFIT_TRACK: String = "Dish profit ($)"
const SERVED_TRACK: String = "Guests served"
const TODAY: String = "Today"
const DAY: String = "Day %d"
const GAP: String = "—"
const PERCENT_CHANGE: String = "%s is %s %.0f%% on %s."
const MONEY_CHANGE: String = "%s is %s %s than %s."
const FLAT: String = "%s is unchanged from %s."
const MAX_TOTAL: int = 9223372036854775807
const MIN_TOTAL: int = -MAX_TOTAL - 1


## Core supplies validated rows. This boundary also tolerates direct UI callers.
static func display_rows(rows: Array[Dictionary], today: int) -> Array[Dictionary]:
	var by_day: Dictionary[int, Dictionary] = {}
	for row: Dictionary in rows:
		var day: Variant = row.get("day")
		var served: Variant = row.get("served")
		if not day is int or day < 1 or day > today or not served is int or served < 0:
			continue
		var recorded: bool = row.get("dish_profit_recorded") is bool \
			and bool(row["dish_profit_recorded"]) and row.get("dish_profit") is int
		by_day[day] = {"day": day, "served": served,
			"dish_profit": int(row["dish_profit"]) if recorded else 0,
			"dish_profit_recorded": recorded}
	var days: Array[int] = []
	days.assign(by_day.keys())
	days.sort()
	var result: Array[Dictionary] = []
	for index: int in range(maxi(0, days.size() - 14), days.size()):
		result.append(by_day[days[index]].duplicate(true))
	return result


static func summary(rows: Array[Dictionary], today: int) -> String:
	var clean: Array[Dictionary] = display_rows(rows, today)
	if clean.size() < 2:
		return EMPTY
	var count: int = mini(7, clean.size() / 2)
	var start: int = clean.size() - count * 2
	var previous: Variant = _total(clean, start, count)
	var recent: Variant = _total(clean, start + count, count)
	if previous == null or recent == null:
		return UNAVAILABLE
	var old: int = previous
	var current: int = recent
	var difference: Variant = _difference(current, old)
	if difference == null:
		return UNAVAILABLE
	var delta: int = difference
	var full_weeks: bool = clean.size() == 14 and int(clean[-1]["day"]) == today
	for index: int in range(1, clean.size()):
		full_weeks = full_weeks and int(clean[index]["day"]) == int(clean[index - 1]["day"]) + 1
	var subject: String = "Dish profit" if full_weeks else (
		"Dish profit on the last recorded day" if count == 1 \
		else "Dish profit over the last %d recorded days" % count)
	var comparison: String = "last week" if full_weeks else (
		"the previous recorded day" if count == 1 else "the previous %d recorded days" % count)
	if delta == 0:
		return FLAT % [subject, comparison]
	if old > 0 and current > 0:
		var percent: float = roundf(absf(float(delta)) / float(old) * 100.0)
		if percent >= 1.0:
			return PERCENT_CHANGE % [subject, "up" if delta > 0 else "down", percent, comparison]
	return MONEY_CHANGE % [subject, Fmt.money(delta).trim_prefix("-"),
		"higher" if delta > 0 else "lower", comparison]


static func day_label(day: int) -> String:
	return DAY % day


static func profit_label(value: int) -> String:
	var magnitude: float = absf(float(value))
	var sign_text: String = "-" if value < 0 else ""
	if magnitude >= 1000000000.0:
		return "%s$%.1fB" % [sign_text, magnitude / 1000000000.0]
	if magnitude >= 1000000.0:
		return "%s$%.1fM" % [sign_text, magnitude / 1000000.0]
	if magnitude >= 10000.0:
		return "%s$%.1fk" % [sign_text, magnitude / 1000.0]
	return Fmt.money(value)


static func served_label(value: int) -> String:
	if value >= 1000000000:
		return "%.1fB" % (float(value) / 1000000000.0)
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 10000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)


static func _total(rows: Array[Dictionary], start: int, count: int) -> Variant:
	var total: int = 0
	for index: int in range(start, start + count):
		if not bool(rows[index]["dish_profit_recorded"]):
			return null
		var value: int = rows[index]["dish_profit"]
		if (value > 0 and total > MAX_TOTAL - value) or (value < 0 and total < MIN_TOTAL - value):
			return null
		total += value
	return total


static func _difference(current: int, previous: int) -> Variant:
	if (previous < 0 and current > MAX_TOTAL + previous) \
			or (previous > 0 and current < MIN_TOTAL + previous):
		return null
	return current - previous
