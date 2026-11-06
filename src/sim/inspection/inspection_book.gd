class_name InspectionBook
extends RefCounted
## The health inspector's schedule and the grade it left (#302).
##
## Each morning `plan_day` decides whether an inspector comes today. It draws
## only from the named "inspector" stream, and only on a day a visit is possible
## (owner level high enough, a week since the last one), so a shop that cannot
## be inspected never creates the stream and keeps its other streams exactly as
## they were. The draw is remembered (`planned_day`) so loading the same morning
## does not draw twice. The grade, the day and the plan are saved with the shop.

const SAVE_VERSION: int = 1
const MAX_DAY: int = 9007199254740991
const MAX_TICK: int = 100000000

var tuning: InspectionTuning
## "A", "B" or "C", or &"" before the first inspection.
var last_grade: StringName = &""
var last_day: int = 0
## The day a draw was made for, and the open tick the inspector arrives at
## (-1: no visit that day).
var planned_day: int = 0
var planned_tick: int = -1
## The day the inspector already walked in (not saved: a day is not resumed).
var arrived_day: int = 0
## Today's result ({points, grade, findings}), for the evening report.
var last_result: Dictionary = {}


func _init(config: InspectionTuning = null) -> void:
	tuning = config if config != null else InspectionTuning.new()


## True when an inspection could happen on `day` at owner level `level`.
func can_visit(day: int, level: int) -> bool:
	return tuning.is_valid() and level >= tuning.unlock_level \
		and (last_day == 0 or day - last_day >= tuning.min_gap_days)


## Decides today's visit. `stream` returns the named stream and is called only
## when a visit is possible. Idempotent for a day already planned.
func plan_day(day: int, level: int, open_ticks: int, stream: Callable) -> void:
	if planned_day == day:
		return
	planned_day = day
	planned_tick = -1
	last_result = {}
	if not can_visit(day, level) or open_ticks < 1:
		return
	var random: RandomNumberGenerator = stream.call() as RandomNumberGenerator
	if random == null or random.randf() >= tuning.daily_chance:
		return
	var first: int = floori(float(open_ticks) * tuning.arrival_from)
	var last: int = maxi(first, floori(float(open_ticks) * tuning.arrival_to))
	planned_tick = random.randi_range(first, last)


## True on the open tick the inspector should walk in (once per day). The plan
## is re-clamped to today's open window, so hours edited in the morning (a
## shorter day) cannot leave a planned visit past closing.
func arriving(day: int, service_tick: int, open_ticks: int) -> bool:
	if planned_day != day or planned_tick < 0 or arrived_day == day:
		return false
	var latest: int = maxi(0, floori(float(open_ticks) * tuning.arrival_to))
	return service_tick >= mini(planned_tick, latest)


func mark_arrived(day: int) -> void:
	arrived_day = day


## Remembers the inspection `result` ({points, grade, findings}) for `day`.
func record(day: int, result: Dictionary) -> void:
	last_grade = StringName(result.get("grade", &""))
	last_day = day
	last_result = result.duplicate(true)


## The arrival factor on `day`: the last grade's, for exactly `effect_days`
## days after the visit; 1.0 before and after.
func arrival_factor(day: int) -> float:
	if last_day <= 0 or last_grade == &"":
		return 1.0
	var since: int = day - last_day
	if since < 1 or since > tuning.effect_days:
		return 1.0
	return tuning.factor_for(last_grade)


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "last_grade": String(last_grade), "last_day": last_day,
		"planned_day": planned_day, "planned_tick": planned_tick}


## Validates fully before changing anything; false leaves the book as it was.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if row.size() != 5 or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("last_day"), 0, MAX_DAY) \
			or not _whole(row.get("planned_day"), 0, MAX_DAY) \
			or not _whole(row.get("planned_tick"), -1, MAX_TICK) \
			or not row.get("last_grade") is String:
		return false
	var grade: String = row["last_grade"]
	if not ["", "A", "B", "C"].has(grade) or (grade == "") != (int(row["last_day"]) == 0):
		return false
	last_grade = StringName(grade)
	last_day = int(row["last_day"])
	planned_day = int(row["planned_day"])
	planned_tick = int(row["planned_tick"])
	arrived_day = 0
	last_result = {}
	return true


static func _whole(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and floorf(number) == number
