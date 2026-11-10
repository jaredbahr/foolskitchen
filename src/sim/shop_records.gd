class_name ShopRecords
extends RefCounted
## Lifetime observations only. Main records one finalized close and owns saving.

const VERSION: int = 1
const MAX_COUNT: int = 9007199254740991
const MAX_MONEY: int = 9223372036854775807
const MIN_MONEY: int = -MAX_MONEY - 1
const BEST_IDS: Array[StringName] = [&"guests", &"profit", &"dishes", &"reputation", &"streak"]
## Existing service failures, not administrative closing/removal or sampled reviews.
const ANGRY_REASONS: Array[StringName] = [
	&"out_of_stock", &"kitchen_failed", &"no_menu", &"waited_too_long",
	&"too_expensive", &"no_table", &"no_clean_plates", &"no_way_through",
]

var _last_day: int = 0
var _guests: int = 0
var _revenue: int = 0
var _dishes: Dictionary[StringName, int] = {}
var _bests: Dictionary[StringName, Dictionary] = {}
var _streak: int = 0


## Duplicate/stale closes are ignored, including a report rebuilt after purchases.
## A gap starts a new streak; an empty service with no unhappy departure is clean.
func record(report: DayReport) -> Array[StringName]:
	var beaten: Array[StringName] = []
	if report == null or not _whole(report.day, 1) or report.day <= _last_day \
			or not _whole(report.customers_served, 0) \
			or not is_finite(report.reputation_after) or report.reputation_after < 0.0 \
			or report.reputation_after > 5.0 or _guests > MAX_COUNT - report.customers_served:
		return beaten
	var revenue: int = 0
	for category: StringName in [Ledger.SALE, Ledger.TIP]:
		var amount: Variant = report.income.get(category, 0)
		if not _whole(amount, 0, MAX_MONEY) or revenue > MAX_MONEY - int(amount):
			return beaten
		revenue += int(amount)
	if _revenue > MAX_MONEY - revenue:
		return beaten
	var today: int = 0
	var dishes: Dictionary[StringName, int] = _dishes.duplicate()
	for raw: Variant in report.dishes_sold:
		var count: Variant = report.dishes_sold[raw]
		if not _dish_id(raw) or not _whole(count, 0) or today > MAX_COUNT - int(count):
			return beaten
		var id: StringName = StringName(raw)
		if dishes.get(id, 0) > MAX_COUNT - int(count):
			return beaten
		today += int(count)
		if int(count) > 0:
			dishes[id] = dishes.get(id, 0) + int(count)
	if _dish_total(dishes) < 0:
		return beaten
	var angry: bool = false
	for reason: StringName in ANGRY_REASONS:
		var count: Variant = report.leave_reasons.get(reason, 0)
		if not _whole(count, 0):
			return beaten
		angry = angry or int(count) > 0
	_streak = 0 if angry else (_streak + 1 if _last_day == report.day - 1 else 1)
	_guests += report.customers_served
	_revenue += revenue
	_dishes = dishes
	_last_day = report.day
	var first_day: bool = _bests.is_empty()
	_beat(&"guests", report.customers_served, report.day, beaten)
	if report.operating_profit_recorded():
		_beat(&"profit", report.operating_profit(), report.day, beaten)
	_beat(&"dishes", today, report.day, beaten)
	# Hundredths, so a value that went through a save compares equal to the
	# same reputation recomputed after loading.
	_beat(&"reputation", snappedf(report.reputation_after, 0.01), report.day, beaten)
	_beat(&"streak", _streak, report.day, beaten)
	# The first recorded day sets every record; it is not news to the player.
	if first_day:
		beaten.clear()
	return beaten


func _beat(id: StringName, value: Variant, day: int, beaten: Array[StringName]) -> void:
	if not _bests.has(id) or value > _bests[id]["value"]:
		_bests[id] = {"value": value, "day": day}
		beaten.append(id)


func snapshot() -> Dictionary:
	return {"last_day": _last_day, "guests": _guests, "revenue": _revenue,
		"dishes": _dishes.duplicate(), "bests": _bests.duplicate(true), "streak": _streak}


## Counts are bounded to exact JSON integers; signed currency uses decimal strings.
func capture() -> Dictionary:
	var data: Dictionary = snapshot()
	data["version"] = VERSION
	data["revenue"] = str(_revenue)
	if _bests.has(&"profit"):
		data["bests"][&"profit"]["value"] = str(_bests[&"profit"]["value"])
	return data


## Decode entirely into a detached candidate before installing any field.
func restore(data: Dictionary) -> bool:
	var candidate: Dictionary = _decode(data)
	if candidate.is_empty():
		return false
	_last_day = candidate["last_day"]
	_guests = candidate["guests"]
	_revenue = candidate["revenue"]
	_dishes = candidate["dishes"]
	_bests = candidate["bests"]
	_streak = candidate["streak"]
	return true


func valid_before(morning_day: int) -> bool:
	return morning_day > 0 and _last_day < morning_day


static func _decode(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return ShopRecords.new().snapshot()
	if not _whole(data.get("version"), VERSION, VERSION) \
			or not _whole(data.get("last_day"), 0) or not _whole(data.get("guests"), 0) \
			or not _whole(data.get("streak"), 0) or not data.get("dishes") is Dictionary \
			or not data.get("bests") is Dictionary:
		return {}
	var revenue: Variant = _money(data.get("revenue"))
	if revenue == null or int(revenue) < 0:
		return {}
	var last_day: int = int(data["last_day"])
	var streak: int = int(data["streak"])
	if streak > last_day:
		return {}
	var dishes: Dictionary[StringName, int] = {}
	for raw: Variant in data["dishes"]:
		if not _dish_id(raw) or not _whole(data["dishes"][raw], 1):
			return {}
		dishes[StringName(raw)] = int(data["dishes"][raw])
	var dish_total: int = _dish_total(dishes)
	if dish_total < 0:
		return {}
	var bests: Dictionary[StringName, Dictionary] = {}
	for raw: Variant in data["bests"]:
		if not (raw is String or raw is StringName) or not BEST_IDS.has(StringName(raw)):
			return {}
		var id: StringName = StringName(raw)
		var row: Variant = data["bests"][raw]
		if not row is Dictionary or not _whole(row.get("day"), 1, last_day):
			return {}
		var value: Variant = row.get("value")
		if id == &"profit":
			value = _money(value)
			if value == null:
				return {}
		elif id == &"reputation":
			if not (value is int or value is float) or not is_finite(float(value)) \
					or float(value) < 0.0 or float(value) > 5.0:
				return {}
			value = float(value)
		elif not _whole(value, 0):
			return {}
		else:
			value = int(value)
		bests[id] = {"value": value, "day": int(row["day"])}
	if last_day == 0:
		if int(data["guests"]) != 0 or int(revenue) != 0 or streak != 0 \
				or not dishes.is_empty() or not bests.is_empty():
			return {}
	else:
		for id: StringName in [&"guests", &"dishes", &"reputation", &"streak"]:
			if not bests.has(id):
				return {}
		if bests[&"guests"]["value"] > int(data["guests"]) \
				or bests[&"dishes"]["value"] > dish_total \
				or bests[&"streak"]["value"] < streak \
				or bests[&"streak"]["value"] > bests[&"streak"]["day"]:
			return {}
	return {"last_day": last_day, "guests": int(data["guests"]), "revenue": int(revenue),
		"dishes": dishes, "bests": bests, "streak": streak}


static func _dish_total(dishes: Dictionary) -> int:
	var total: int = 0
	for count: int in dishes.values():
		if total > MAX_COUNT - count:
			return -1
		total += count
	return total


static func _dish_id(value: Variant) -> bool:
	if not (value is String or value is StringName):
		return false
	var text: String = String(value)
	if text.is_empty() or text.length() > 80:
		return false
	for index: int in text.length():
		if text.unicode_at(index) < 32 or text.unicode_at(index) == 127:
			return false
	return true


static func _whole(value: Variant, minimum: int, maximum: int = MAX_COUNT) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	return value is float and is_finite(value) and absf(value) <= MAX_COUNT \
		and value >= minimum and value <= maximum and floorf(value) == value


static func _money(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		return int(value) if _whole(value, -MAX_COUNT) else null
	if not value is String:
		return null
	var negative: bool = value.begins_with("-")
	var digits: String = value.substr(1) if negative else value
	if digits.is_empty() or digits.length() > 19 or (digits.length() > 1 and digits.begins_with("0")) \
			or (negative and digits == "0"):
		return null
	for index: int in digits.length():
		if digits.unicode_at(index) < 48 or digits.unicode_at(index) > 57:
			return null
	var bound: String = "9223372036854775808" if negative else str(MAX_MONEY)
	if digits.length() == 19 and digits > bound:
		return null
	if negative and digits == "9223372036854775808":
		return MIN_MONEY
	return -int(digits) if negative else int(digits)
