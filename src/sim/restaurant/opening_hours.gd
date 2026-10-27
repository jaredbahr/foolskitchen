class_name OpeningHours
extends RefCounted
## The shop's opening hours live on its SimClock (display minutes and service
## length), so they join the existing morning save through the clock section;
## there is no separate save point (FK-083). Pure helpers, no nodes.


## Whether a pair of times is a permitted setting.
static func allowed(open_minute: int, close_minute: int, tuning: OpeningHoursTuning) -> bool:
	if tuning == null or tuning.step_minutes <= 0:
		return false
	var length: int = close_minute - open_minute
	return open_minute >= tuning.earliest_open_minute and close_minute <= tuning.latest_close_minute \
		and length >= tuning.min_open_minutes and length <= tuning.max_open_minutes \
		and open_minute % tuning.step_minutes == 0 and close_minute % tuning.step_minutes == 0


## The service ticks for a day of these hours.
static func open_ticks(open_minute: int, close_minute: int, tuning: OpeningHoursTuning) -> int:
	return (close_minute - open_minute) * tuning.ticks_per_minute


## Morning only: sets the clock's hours. Refuses anything outside the limits.
static func apply(clock: SimClock, open_minute: int, close_minute: int, tuning: OpeningHoursTuning) -> bool:
	if clock == null or clock.phase != SimClock.Phase.MORNING or not allowed(open_minute, close_minute, tuning):
		return false
	clock.display_open_minute = open_minute
	clock.display_close_minute = close_minute
	clock.open_ticks = open_ticks(open_minute, close_minute, tuning)
	return true


## A loaded clock is accepted only with permitted hours. (The service length in
## ticks is the clock's own saved setting; tests and tools shorten it.)
static func clock_valid(clock: SimClock, tuning: OpeningHoursTuning) -> bool:
	return clock != null and allowed(clock.display_open_minute, clock.display_close_minute, tuning)


## Staff are paid by the hour: the factor against the default day. Exactly 1.0
## for the default hours, so default wages are unchanged.
static func wage_factor(clock: SimClock, tuning: OpeningHoursTuning) -> float:
	if clock == null or tuning == null:
		return 1.0
	var length: int = clock.display_close_minute - clock.display_open_minute
	var default_length: int = tuning.default_close_minute - tuning.default_open_minute
	if length == default_length or default_length <= 0 or length <= 0:
		return 1.0
	return float(length) / float(default_length)


## A wage for today's hours, rounded to whole dollars.
static func wage_for_day(daily_wage: int, clock: SimClock, tuning: OpeningHoursTuning) -> int:
	var factor: float = wage_factor(clock, tuning)
	return daily_wage if factor == 1.0 else roundi(float(daily_wage) * factor)
