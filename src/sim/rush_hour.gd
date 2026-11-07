class_name RushHour
extends RefCounted
## Morning-planned busy period, driven by a separate lazy named RNG (#325).

const SAVE_VERSION: int = 1
const MAX_DAY: int = 9007199254740991

var tuning: RushTuning
var last_rush_day: int = 0
## Marked on every completed morning roll, including no-event days.
var rolled_day: int = 0
var occasion: String = ""
var start_minute: int = -1
var duration_minutes: int = 0
var cohort_arrivals: int = 0
var cohort_lost_no_seat: int = 0
var cohort_lost_patience: int = 0


func _init(config: RushTuning = null) -> void:
	tuning = config if config != null else RushTuning.new()


func has_event() -> bool:
	return not occasion.is_empty() and start_minute >= 0 and duration_minutes > 0


func can_roll(day: int, level: int, open_minute: int, close_minute: int) -> bool:
	return tuning != null and tuning.is_valid() and day >= 1 and level >= tuning.unlock_level \
		and (last_rush_day == 0 or day - last_rush_day >= tuning.min_gap_days) \
		and latest_start(open_minute, close_minute, tuning) >= earliest_start(open_minute, tuning)


## Idempotent for a morning. Even no-event days are stamped, so loading cannot
## draw twice; inaccessible levels/hours never ask for the named RNG provider.
func plan_day(day: int, level: int, open_minute: int, close_minute: int,
		random_provider: Callable) -> void:
	if day < 1 or rolled_day == day or tuning == null or not tuning.is_valid():
		return
	rolled_day = day
	_clear_event()
	if not can_roll(day, level, open_minute, close_minute) or not random_provider.is_valid():
		return
	var random: RandomNumberGenerator = random_provider.call() as RandomNumberGenerator
	if random == null or random.randf() >= tuning.daily_chance:
		return
	var max_duration: int = mini(tuning.max_duration_minutes,
		close_minute - tuning.last_orders_margin_minutes - earliest_start(open_minute, tuning))
	# Draw a duration, then a legal start inside the configured service margins.
	var duration: int = random.randi_range(tuning.min_duration_minutes, maxi(tuning.min_duration_minutes, max_duration))
	var first: int = earliest_start(open_minute, tuning)
	var last: int = close_minute - tuning.last_orders_margin_minutes - duration
	if last < first:
		return
	start_minute = random.randi_range(first, last)
	duration_minutes = duration
	occasion = tuning.occasions[random.randi_range(0, tuning.occasions.size() - 1)]


static func earliest_start(open_minute: int, config: RushTuning) -> int:
	return open_minute + (config.opening_margin_minutes if config != null else 30)


static func latest_start(open_minute: int, close_minute: int, config: RushTuning) -> int:
	if config == null or not config.is_valid():
		return -1
	return close_minute - config.last_orders_margin_minutes - config.min_duration_minutes


func is_active_minute(minute: int) -> bool:
	return has_event() and minute >= start_minute and minute < start_minute + duration_minutes


## Smoothly ramps from 1.0 to peak and back over the event's edges.
func multiplier_at(minute: int) -> float:
	if not is_active_minute(minute) or tuning == null or not tuning.is_valid():
		return 1.0
	var elapsed: float = float(minute - start_minute)
	var remaining: float = float(start_minute + duration_minutes - minute)
	var ramp: float = clampf(minf(elapsed / tuning.ramp_minutes,
		remaining / tuning.ramp_minutes), 0.0, 1.0)
	return lerpf(1.0, tuning.peak_multiplier, ramp)


## Keep a morning plan inside edited hours without drawing again. If no legal
## slot remains, remove today's notice/event and preserve the prior cooldown.
func fit_to_hours(open_minute: int, close_minute: int) -> void:
	if not has_event() or tuning == null or not tuning.is_valid():
		return
	var first: int = earliest_start(open_minute, tuning)
	var latest_duration: int = close_minute - tuning.last_orders_margin_minutes - first
	if latest_duration < tuning.min_duration_minutes:
		_clear_event()
		return
	duration_minutes = mini(duration_minutes, latest_duration)
	var last: int = close_minute - tuning.last_orders_margin_minutes - duration_minutes
	start_minute = clampi(start_minute, first, last)


func mark_started(day: int, minute: int) -> void:
	if day == rolled_day and is_active_minute(minute):
		last_rush_day = day


func begin_day(day: int) -> void:
	cohort_arrivals = 0
	cohort_lost_no_seat = 0
	cohort_lost_patience = 0
	if rolled_day != day:
		_clear_event()


func record_arrivals(day: int, minute: int, count: int) -> bool:
	if day != rolled_day or not is_active_minute(minute) or count <= 0:
		return false
	cohort_arrivals += count
	return true


func record_lost(reason: StringName) -> void:
	if reason == &"no_table":
		cohort_lost_no_seat += 1
	elif reason == &"waited_too_long":
		cohort_lost_patience += 1


func report_lines() -> Array[String]:
	if not has_event():
		return []
	var end_minute: int = start_minute + duration_minutes
	var line: String = "%s brought %d guests between %s and %s; %d left without a seat and %d left after waiting." % [
		occasion, cohort_arrivals, _clock_text(start_minute), _clock_text(end_minute),
		cohort_lost_no_seat, cohort_lost_patience]
	return [line]


func morning_notice() -> String:
	if not has_event():
		return ""
	return "%s: expect a rush around %s." % [occasion, _clock_text(start_minute)]


static func _clock_text(minute: int) -> String:
	var hour: int = minute / 60
	var part: String = "am" if hour < 12 else "pm"
	var shown_hour: int = hour % 12
	if shown_hour == 0:
		shown_hour = 12
	return "%d:%02d %s" % [shown_hour, minute % 60, part]


func to_dict() -> Dictionary:
	var result: Dictionary = {"version": SAVE_VERSION, "last_rush_day": last_rush_day,
		"rolled_day": rolled_day, "occasion": occasion, "start_minute": start_minute,
		"duration_minutes": duration_minutes}
	if has_event():
		result["cohort_arrivals"] = cohort_arrivals
		result["cohort_lost_no_seat"] = cohort_lost_no_seat
		result["cohort_lost_patience"] = cohort_lost_patience
	return result


## Strict atomic restore; absence is handled by Main for legacy saves.
func from_dict(value: Variant, open_minute: int = -1, close_minute: int = -1) -> bool:
	if not value is Dictionary or tuning == null or not tuning.is_valid():
		return false
	var row: Dictionary = value
	var event_fields: Array[String] = ["cohort_arrivals", "cohort_lost_no_seat", "cohort_lost_patience"]
	var has_counters: bool = event_fields.all(func(key: String) -> bool: return row.has(key))
	if (row.size() != 6 and row.size() != 9) or (row.size() == 9) != has_counters \
			or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("last_rush_day"), 0, MAX_DAY) \
			or not _whole(row.get("rolled_day"), 0, MAX_DAY) \
			or not row.get("occasion") is String \
			or not _whole(row.get("start_minute"), -1, 1439) \
			or not _whole(row.get("duration_minutes"), 0, 240):
		return false
	if has_counters:
		for key: String in event_fields:
			if not _whole(row.get(key), 0, MAX_DAY):
				return false
	var restored_occasion: String = row["occasion"]
	var restored_start: int = int(row["start_minute"])
	var restored_duration: int = int(row["duration_minutes"])
	var empty_event: bool = restored_occasion.is_empty() and restored_start == -1 and restored_duration == 0
	var valid_event: bool = not restored_occasion.is_empty() and restored_start >= 0 \
			and restored_duration >= tuning.min_duration_minutes \
			and restored_duration <= tuning.max_duration_minutes \
			and restored_start + restored_duration <= 1440 and restored_occasion in tuning.occasions
	if not empty_event and not valid_event:
		return false
	if empty_event and has_counters:
		return false
	if valid_event and open_minute >= 0 and (close_minute <= open_minute \
			or restored_start < earliest_start(open_minute, tuning) \
			or restored_start + restored_duration > close_minute - tuning.last_orders_margin_minutes):
		return false
	var arrivals: int = int(row.get("cohort_arrivals", 0))
	var no_seat: int = int(row.get("cohort_lost_no_seat", 0))
	var patience: int = int(row.get("cohort_lost_patience", 0))
	if not valid_event and (arrivals != 0 or no_seat != 0 or patience != 0) \
			or no_seat + patience > arrivals \
			or int(row["last_rush_day"]) > int(row["rolled_day"]) \
			or (valid_event and int(row["rolled_day"]) < 1):
		return false
	last_rush_day = int(row["last_rush_day"])
	rolled_day = int(row["rolled_day"])
	occasion = restored_occasion
	start_minute = restored_start
	duration_minutes = restored_duration
	cohort_arrivals = arrivals
	cohort_lost_no_seat = no_seat
	cohort_lost_patience = patience
	return true


func _clear_event() -> void:
	occasion = ""
	start_minute = -1
	duration_minutes = 0
	cohort_arrivals = 0
	cohort_lost_no_seat = 0
	cohort_lost_patience = 0


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
