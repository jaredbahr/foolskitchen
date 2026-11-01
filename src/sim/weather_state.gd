class_name WeatherState
extends RefCounted
## One chosen daily value. Selection uses an injected current named stream;
## neither this value nor SimWorld retains a random-number generator.

enum Kind { SUNNY, CLOUDY, RAIN }
const VERSION: int = 1
## Weather days use ordinary JSON numbers, so only exact integers are durable.
const MAX_SAVED_DAY: int = 9007199254740991

var kind: Kind = Kind.SUNNY
## Zero is a new, unchosen world. A saved morning always has a positive day.
var day: int = 0


func is_for_day(for_day: int) -> bool:
	return for_day > 0 and day == for_day


func needs_selection(for_day: int) -> bool:
	return for_day > 0 and day != for_day


## Exactly one random draw for a new morning; repeated setup is a pure no-op.
## Validation happens before the draw or any state mutation. At randf's
## inclusive upper endpoint, select the last positive bin, never a zero bin.
func ensure_today(for_day: int, rng: RandomNumberGenerator, tuning: WeatherTuning) -> bool:
	if for_day < 1 or for_day > MAX_SAVED_DAY or for_day < day:
		return false
	if is_for_day(for_day):
		return true
	if rng == null or tuning == null or not tuning.is_valid():
		return false
	var values: PackedFloat64Array = tuning.weights()
	var total: float = values[0] + values[1] + values[2]
	var sample: float = rng.randf() * total
	var cumulative: float = 0.0
	var selected: Kind = Kind.SUNNY
	for index: int in values.size():
		if values[index] <= 0.0:
			continue
		selected = index as Kind
		cumulative += values[index]
		if sample < cumulative:
			break
	kind = selected
	day = for_day
	return true


func copy() -> WeatherState:
	var result: WeatherState = WeatherState.new()
	result.kind = kind
	result.day = day
	return result


func to_dict() -> Dictionary:
	return {"version": VERSION, "day": day, "kind": int(kind)}


## A missing legacy section is explicitly selected Sunny for the SAVED day.
## This does not obtain a stream or consume a random draw.
static func legacy_sunny(saved_day: int) -> WeatherState:
	if saved_day < 1 or saved_day > MAX_SAVED_DAY:
		return null
	var result: WeatherState = WeatherState.new()
	result.day = saved_day
	return result


## Decode into a detached value. Main stages it, checks the saved Clock day,
## and installs it only after the entire morning load has succeeded.
static func from_dict(data: Dictionary, errors: Array[String] = []) -> WeatherState:
	if not _integer_in(data.get("version"), VERSION, VERSION):
		errors.append("Invalid weather version")
		return null
	if not _integer_in(data.get("day"), 1, MAX_SAVED_DAY):
		errors.append("Invalid weather day")
		return null
	if not _integer_in(data.get("kind"), Kind.SUNNY, Kind.RAIN):
		errors.append("Invalid weather kind")
		return null
	var result: WeatherState = WeatherState.new()
	result.day = int(data["day"])
	result.kind = int(data["kind"]) as Kind
	return result


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if value is float:
		var number: float = value
		return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum
	return false
