class_name EveningSchedule
extends RefCounted
## A shop's saved day and evening presets and the clock time to switch between them.

const VERSION: int = 1

var enabled: bool = false
var minute: int = 0
var day_preset: String = ""
var evening_preset: String = ""


static func allowed_minute(value: int, open_minute: int, close_minute: int,
		tuning: OpeningHoursTuning) -> bool:
	return tuning != null and tuning.step_minutes > 0 and value > open_minute \
		and value < close_minute and value % tuning.step_minutes == 0


## The first open tick whose displayed minute reaches the changeover.
## Use the same clock math when a test or tool shortens the service.
func changeover_tick(clock: SimClock, tuning: OpeningHoursTuning) -> int:
	if not enabled or not allowed_minute(minute, clock.display_open_minute,
			clock.display_close_minute, tuning):
		return 0
	var span: int = clock.display_close_minute - clock.display_open_minute
	var first_tick: int = ceili(float(minute - clock.display_open_minute) * clock.open_ticks / span)
	# The clock floors the displayed minute after its floating-point division.
	if clock.open_display_minutes_at(first_tick) < minute:
		first_tick += 1
	# The last tick transitions to LAST_ORDERS before work or arrivals.
	return first_tick if first_tick < clock.open_ticks else 0


func uses_preset(preset_name: String) -> bool:
	return enabled and (day_preset.nocasecmp_to(preset_name) == 0 \
		or evening_preset.nocasecmp_to(preset_name) == 0)


func to_save() -> Dictionary:
	if minute == 0:
		return {}
	return {
		"version": VERSION,
		"enabled": enabled,
		"minute": minute,
		"day_preset": day_preset,
		"evening_preset": evening_preset,
	}


## Called on a staging instance. Empty is the legacy unscheduled state.
func restore(data: Dictionary) -> bool:
	if data.is_empty():
		enabled = false
		minute = 0
		day_preset = ""
		evening_preset = ""
		return true
	if data.size() != 5 or data.get("version") != VERSION or not data.get("enabled") is bool \
			or not data.get("day_preset") is String or not data.get("evening_preset") is String:
		return false
	var saved_minute: Variant = data.get("minute")
	if not (saved_minute is int or saved_minute is float) or not is_finite(float(saved_minute)) \
			or float(saved_minute) != floorf(float(saved_minute)) or saved_minute <= 0 or saved_minute >= 1440:
		return false
	var saved_day: String = data["day_preset"]
	var saved_evening: String = data["evening_preset"]
	if MenuSettings.normalized_restaurant_name(saved_day).is_empty() \
			or MenuSettings.normalized_restaurant_name(saved_evening).is_empty():
		return false
	enabled = data["enabled"]
	minute = int(saved_minute)
	day_preset = saved_day
	evening_preset = saved_evening
	return true
