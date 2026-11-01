class_name DemandState
extends RefCounted
## Persistent progress only. Menu, rating and vibe remain session facts.

const VERSION: int = 1
const MAX_EXACT_INTEGER: int = 9007199254740991

var renown: float = 0.0
var day: int = 1
var last_decay_day: int = 1
var last_award_day: int = 0
var last_service_day: int = 0
var last_service_factor: float = 0.0


func begin_morning(value: int, tuning: DemandTuning) -> bool:
	if tuning == null or not tuning.is_valid() or value < day or value < 1 \
			or value > MAX_EXACT_INTEGER or value < last_decay_day \
			or value < last_award_day or not _number(renown, 0.0):
		return false
	if last_decay_day < value:
		var decayed: float = renown * pow(1.0 - tuning.renown_daily_decay, value - last_decay_day)
		if not _number(decayed, 0.0):
			return false
		renown = decayed
		last_decay_day = value
	day = value
	return true


## Daily counters are already idempotent complete departures, not order payments.
func award_close(value: int, happy_count: int, service_factor: float,
		tuning: DemandTuning) -> bool:
	if tuning == null or not tuning.is_valid() or value != day \
			or happy_count < 0 or happy_count > MAX_EXACT_INTEGER \
			or not _number(service_factor, 0.0) or service_factor <= 0.0 \
			or service_factor > tuning.total_cap:
		return false
	if last_award_day == value:
		# The original completed service owns its snapshot; later calls are no-ops.
		return true
	var awarded: float = renown + float(happy_count) * tuning.renown_per_happy_guest
	if not _number(awarded, 0.0):
		return false
	renown = awarded
	last_award_day = value
	last_service_day = value
	last_service_factor = service_factor
	return true


## Loading a legacy morning never decays unrecorded earlier days.
static func legacy_for_day(value: int) -> DemandState:
	if value < 1 or value > MAX_EXACT_INTEGER:
		return null
	var result: DemandState = DemandState.new()
	result.day = value
	result.last_decay_day = value
	return result


func to_dict() -> Dictionary:
	return {"version": VERSION, "day": day, "renown": renown,
		"last_decay_day": last_decay_day, "last_award_day": last_award_day,
		"last_service_day": last_service_day, "last_service_factor": last_service_factor}


## Decode atomically; callers stage this object until the whole save is valid.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if not _whole(row.get("version"), VERSION, VERSION) \
			or not _whole(row.get("day"), 1, MAX_EXACT_INTEGER) \
			or not _whole(row.get("last_decay_day"), 0, MAX_EXACT_INTEGER) \
			or not _whole(row.get("last_award_day"), 0, MAX_EXACT_INTEGER) \
			or not _whole(row.get("last_service_day"), 0, MAX_EXACT_INTEGER) \
			or not _number(row.get("renown"), 0.0) \
			or not _number(row.get("last_service_factor"), 0.0):
		return false
	var decoded_day: int = int(row["day"])
	var decay: int = int(row["last_decay_day"])
	var award: int = int(row["last_award_day"])
	var service_day: int = int(row["last_service_day"])
	var factor: float = float(row["last_service_factor"])
	if decay != decoded_day or award > decoded_day or service_day != award \
			or (service_day == 0 and factor != 0.0) or (service_day > 0 and factor <= 0.0):
		return false
	day = decoded_day
	renown = float(row["renown"])
	last_decay_day = decay
	last_award_day = award
	last_service_day = service_day
	last_service_factor = factor
	return true


static func _whole(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and floor(number) == number


static func _number(value: Variant, low: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
		and is_finite(float(value)) and float(value) >= low and float(value) <= MAX_EXACT_INTEGER
