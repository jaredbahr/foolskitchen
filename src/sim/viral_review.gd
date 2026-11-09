class_name ViralReview
extends RefCounted
## A close can trigger three future open services. Morning/report queries never
## consume a service or request randomness. Main owns the morning-only save.

const VERSION: int = 1
const MAX_EXACT_INTEGER: int = 9007199254740991

var tuning: ViralTuning
var last_close_day: int = 0
var last_trigger_day: int = 0
var days_left: int = 0
var dish: StringName = &""
## Preserve today's factor after its service consumes one future-use token.
var last_close_strength: int = 0


func _init(config: ViralTuning = null) -> void:
	tuning = config if config != null else ViralTuning.new()


## Called only for a completed open service. Happy share is of ALL guests,
## served + lost, not of reviews or payments (paid departures are always happy).
## Cooldown is the interval between trigger closes: day N can roll again at N+10.
func close_open_day(day: int, served: int, lost: int, happy: int,
		best_dish: StringName, random_provider: Callable) -> bool:
	if tuning == null or not tuning.is_valid() or day <= last_close_day \
			or day > MAX_EXACT_INTEGER or served < 0 or lost < 0 or happy < 0 \
			or served > MAX_EXACT_INTEGER - lost or happy > served \
			or String(best_dish).length() > 128:
		return false
	var strength: int = days_left if day > last_trigger_day else 0
	var remaining: int = maxi(0, days_left - (1 if strength > 0 else 0))
	var guests: int = served + lost
	var qualifies: bool = served >= tuning.min_served and guests > 0 \
		and float(happy) / float(guests) >= tuning.min_happy_share
	var eligible: bool = strength == 0 and (last_trigger_day == 0 \
		or day - last_trigger_day >= tuning.cooldown_days)
	var triggered: bool = false
	if qualifies and eligible:
		if not random_provider.is_valid():
			return false
		# The provider itself must stay lazy: nonqualifying days create no stream.
		var generator: RandomNumberGenerator = random_provider.call() as RandomNumberGenerator
		if generator == null:
			return false
		triggered = generator.randf() < tuning.viral_chance
	last_close_day = day
	last_close_strength = strength
	days_left = remaining
	if triggered:
		last_trigger_day = day
		days_left = tuning.boosted_open_days
		dish = best_dish
	return triggered


func factor(day: int) -> float:
	if tuning == null or not tuning.is_valid() or day < 1:
		return 1.0
	if day == last_close_day:
		return _factor_for_strength(last_close_strength)
	if day <= last_close_day or day <= last_trigger_day:
		return 1.0
	return _factor_for_strength(days_left)


func triggered_on(day: int) -> bool:
	return day > 0 and day == last_trigger_day


func cooldown_remaining(day: int) -> int:
	return maxi(0, tuning.cooldown_days - (day - last_trigger_day)) \
		if tuning != null and last_trigger_day > 0 else 0


func valid_before_morning(day: int) -> bool:
	return day >= 1 and day <= MAX_EXACT_INTEGER and last_close_day < day


func to_dict() -> Dictionary:
	return {"version": VERSION, "last_close_day": last_close_day,
		"last_trigger_day": last_trigger_day, "days_left": days_left,
		"dish": String(dish), "last_close_strength": last_close_strength}


## Atomic decode; Main stages this object until the whole save is accepted.
func from_dict(value: Variant) -> bool:
	if tuning == null or not tuning.is_valid() or not value is Dictionary:
		return false
	var row: Dictionary = value
	if not _whole(row.get("version"), VERSION, VERSION) \
			or not _whole(row.get("last_close_day"), 0, MAX_EXACT_INTEGER) \
			or not _whole(row.get("last_trigger_day"), 0, MAX_EXACT_INTEGER) \
			or not _whole(row.get("days_left"), 0, tuning.boosted_open_days) \
			or not _whole(row.get("last_close_strength"), 0, tuning.boosted_open_days) \
			or not row.get("dish") is String or String(row["dish"]).length() > 128:
		return false
	var closed: int = int(row["last_close_day"])
	var triggered: int = int(row["last_trigger_day"])
	var remaining: int = int(row["days_left"])
	var strength: int = int(row["last_close_strength"])
	if triggered > closed or (triggered == 0 and (remaining != 0 or strength != 0 \
			or not String(row["dish"]).is_empty())):
		return false
	if triggered > 0 and triggered == closed \
			and (remaining != tuning.boosted_open_days or strength != 0):
		return false
	if triggered < closed and (remaining > 0 or strength > 0) \
			and (strength < 1 or remaining != strength - 1):
		return false
	last_close_day = closed
	last_trigger_day = triggered
	days_left = remaining
	last_close_strength = strength
	dish = StringName(row["dish"])
	return true


func _factor_for_strength(strength: int) -> float:
	return 1.0 + (tuning.viral_multiplier - 1.0) * float(strength) \
		/ float(tuning.boosted_open_days)


static func _whole(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and floor(number) == number
