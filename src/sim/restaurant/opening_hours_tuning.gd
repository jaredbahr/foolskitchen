class_name OpeningHoursTuning
extends Resource
## Limits for the morning opening-hours setting (FK-083). Times are minutes
## since midnight on the shop clock. The default is the original 11:00-21:00.

@export var default_open_minute: int = 11 * 60
@export var default_close_minute: int = 21 * 60
@export var earliest_open_minute: int = 6 * 60
@export var latest_close_minute: int = 24 * 60
@export var min_open_minutes: int = 4 * 60
@export var max_open_minutes: int = 13 * 60
## The setting moves in these steps.
@export var step_minutes: int = 30
## Service ticks per shop minute (3,600 ticks for the default ten hours).
@export var ticks_per_minute: int = 6


func is_valid() -> bool:
	return step_minutes > 0 and ticks_per_minute > 0 and earliest_open_minute >= 0 \
		and latest_close_minute <= 24 * 60 and earliest_open_minute < latest_close_minute \
		and min_open_minutes > 0 and max_open_minutes >= min_open_minutes \
		and OpeningHours.allowed(default_open_minute, default_close_minute, self)
