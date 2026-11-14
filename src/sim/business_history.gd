class_name BusinessHistory
extends RefCounted
## Detached closing summaries. Main owns when these join the morning save.

const MAX_DAYS: int = 30
const SAVE_VERSION: int = 1
const MAX_EXACT_INTEGER: int = 9007199254740991
const MAX_MONEY: int = 9223372036854775807
const MIN_MONEY: int = -MAX_MONEY - 1

var _days: Array[Dictionary] = []


## Repeated evening views replace today's row; stale reports cannot alter past days.
func record(report: DayReport) -> void:
	if report == null:
		return
	var recorded: bool = report.operating_profit_recorded()
	var good_reviews: int = 0
	for card: Dictionary in report.review_cards:
		if int(card.get("stars", 0)) >= 4:
			good_reviews += 1
	var row: Dictionary = _clean_row({
		"day": report.day,
		"served": report.customers_served,
		"lost": report.customers_lost,
		"dish_profit": report.operating_profit() if recorded else 0,
		"dish_profit_recorded": recorded,
		"cash_change": report.profit(),
		"reputation": report.reputation_after,
		"weekly_profit": report.purchase_basis_operating_profit(),
		"good_reviews": good_reviews,
		"no_table": int(report.leave_reasons.get(&"no_table", 0)),
		"dishes_sold": report.dishes_sold,
	})
	if row.is_empty():
		return
	if not _days.is_empty():
		var last_day: int = int(_days.back()["day"])
		if int(row["day"]) < last_day:
			return
		if int(row["day"]) == last_day:
			_days[_days.size() - 1] = row
			return
	_days.append(row)
	if _days.size() > MAX_DAYS:
		_days.pop_front()


func summaries() -> Array[Dictionary]:
	return recent(MAX_DAYS)


func recent(limit: int = 7) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = mini(maxi(limit, 0), _days.size())
	for index: int in range(_days.size() - count, _days.size()):
		result.append(_days[index].duplicate(true))
	return result


## Signed money stays exact through JSON; the recorded flag distinguishes unknown.
func capture() -> Dictionary:
	var days: Array[Dictionary] = summaries()
	for row: Dictionary in days:
		row["dish_profit"] = str(row["dish_profit"])
		row["cash_change"] = str(row["cash_change"])
		if row.has("weekly_profit"):
			row["weekly_profit"] = str(row["weekly_profit"])
	return {"version": SAVE_VERSION, "days": days}


## Validate every supplied row, even one older than the retained thirty.
## Keep the candidate detached and bounded; install only after all rows pass.
func restore(data: Dictionary) -> bool:
	if data.is_empty():
		_days.clear()
		return true
	if not _whole(data.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not data.get("days") is Array:
		return false
	var values: Array = data["days"]
	var candidate: Array[Dictionary] = []
	var previous_day: int = 0
	for value: Variant in values:
		if not value is Dictionary:
			return false
		var row: Dictionary = _clean_row(value)
		if row.is_empty() or int(row["day"]) <= previous_day:
			return false
		previous_day = int(row["day"])
		candidate.append(row)
		if candidate.size() > MAX_DAYS:
			candidate.pop_front()
	_days = candidate
	return true


## Main checks this against the saved morning after the whole load validates.
func valid_before(morning_day: int) -> bool:
	if not _whole(morning_day, 1):
		return false
	return _days.is_empty() or int(_days.back()["day"]) < morning_day


static func _clean_row(value: Dictionary) -> Dictionary:
	if not _whole(value.get("day"), 1) or not _whole(value.get("served"), 0) \
			or not _whole(value.get("lost"), 0) \
			or not value.get("dish_profit_recorded") is bool:
		return {}
	var dish: Variant = _money(value.get("dish_profit"))
	var cash: Variant = _money(value.get("cash_change"))
	var reputation: Variant = value.get("reputation")
	if dish == null or cash == null or not (reputation is int or reputation is float):
		return {}
	var stars: float = float(reputation)
	if not is_finite(stars) or stars < 0.0 or stars > 5.0:
		return {}
	var recorded: bool = value["dish_profit_recorded"]
	var row: Dictionary = {"day": int(value["day"]), "served": int(value["served"]),
		"lost": int(value["lost"]), "dish_profit": int(dish) if recorded else 0,
		"dish_profit_recorded": recorded, "cash_change": int(cash), "reputation": stars}
	# Existing history rows have none of these measurements. Leave them absent
	# so an old save does not become a week of zero sales or zero walkouts.
	if value.has("weekly_profit") or value.has("good_reviews") or value.has("no_table") or value.has("dishes_sold"):
		var weekly_profit: Variant = _money(value.get("weekly_profit"))
		if weekly_profit == null or not _whole(value.get("good_reviews"), 0) \
				or not _whole(value.get("no_table"), 0, row["lost"]) or not value.get("dishes_sold") is Dictionary:
			return {}
		var dishes: Dictionary[String, int] = {}
		for key: Variant in value["dishes_sold"]:
			if not (key is String or key is StringName) or str(key).is_empty() \
					or not _whole(value["dishes_sold"][key], 0):
				return {}
			dishes[str(key)] = int(value["dishes_sold"][key])
		row["weekly_profit"] = int(weekly_profit)
		row["good_reviews"] = int(value["good_reviews"])
		row["no_table"] = int(value["no_table"])
		row["dishes_sold"] = dishes
	return row


static func _whole(value: Variant, minimum: int, maximum: int = MAX_EXACT_INTEGER) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if not value is float:
		return false
	var number: float = value
	return is_finite(number) and number >= minimum and number <= maximum \
		and floorf(number) == number


## Null marks invalid input, since every signed int64 value is valid money.
static func _money(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_finite(number) and number >= -MAX_EXACT_INTEGER \
				and number <= MAX_EXACT_INTEGER and floorf(number) == number:
			return int(number)
		return null
	if not value is String:
		return null
	var text: String = value
	var negative: bool = text.begins_with("-")
	var digits: String = text.substr(1) if negative else text
	if digits.is_empty() or digits.length() > 19 \
			or (digits.length() > 1 and digits.begins_with("0")) \
			or (negative and digits == "0"):
		return null
	for index: int in range(digits.length()):
		if digits.unicode_at(index) < 48 or digits.unicode_at(index) > 57:
			return null
	var bound: String = "9223372036854775808" if negative else str(MAX_MONEY)
	if digits.length() == 19 and digits > bound:
		return null
	if negative and digits == "9223372036854775808":
		return MIN_MONEY
	var amount: int = int(digits)
	return -amount if negative else amount
