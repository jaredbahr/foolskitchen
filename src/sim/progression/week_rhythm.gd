class_name WeekRhythm
extends Resource
## A repeating schedule derived from the restaurant day without a random draw.

const DAYS_PER_WEEK: int = 7

@export_enum("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
var first_weekday: int = 0
@export var arrival_percent: PackedInt32Array


func is_valid() -> bool:
	if first_weekday < 0 or first_weekday >= DAYS_PER_WEEK or arrival_percent.size() != DAYS_PER_WEEK:
		return false
	var total: int = 0
	for percent: int in arrival_percent:
		if percent <= 0:
			return false
		total += percent
	return total == 100 * DAYS_PER_WEEK


func weekday_index(day: int) -> int:
	# Reduce the day first so even the largest saved day can include the offset.
	return (first_weekday + (maxi(1, day) - 1) % DAYS_PER_WEEK) % DAYS_PER_WEEK


func factor_for_day(day: int) -> float:
	return arrival_percent[weekday_index(day)] / 100.0
