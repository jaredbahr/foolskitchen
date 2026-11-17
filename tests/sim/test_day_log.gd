extends TestCase

var _clock: SimClock
var _log: DayLog


func before_each() -> void:
	_clock = SimClock.new()
	_clock.open_ticks = 120
	_clock.display_open_minute = 12 * 60
	_clock.display_close_minute = 13 * 60
	_clock.start_service()
	_log = DayLog.new()
	_log.clock = _clock


func test_repeat_window_spans_intervening_events_but_stays_within_five_minutes() -> void:
	_add(0, DayLog.Kind.GUEST_LEFT, "waited too long")
	_add(2, DayLog.Kind.STOCK_LOW, "Low stock: Tomato (1 left)")
	_add(5, DayLog.Kind.GUEST_LEFT, "waited too long")
	_add(10, DayLog.Kind.GUEST_LEFT, "waited too long")
	assert_eq(_log.newest_first(), [
		"12:05  3 guests left: waited too long",
		"12:01  Low stock: Tomato (1 left)",
	] as Array[String])
	_add(11, DayLog.Kind.GUEST_LEFT, "waited too long")
	_add(12, DayLog.Kind.GUEST_LEFT, "no table available")
	assert_eq(_log.newest_first().slice(0, 3), [
		"12:06  A guest left: no table available",
		"12:05  A guest left: waited too long",
		"12:05  3 guests left: waited too long",
	] as Array[String], "the repeat window is measured from the group's first occurrence")


func test_last_orders_uses_the_hud_time_but_does_not_freeze_repeat_window() -> void:
	_clock.phase = SimClock.Phase.LAST_ORDERS
	_add(120, DayLog.Kind.GUEST_LEFT, "shop closed")
	_add(131, DayLog.Kind.GUEST_LEFT, "shop closed")
	assert_eq(_log.newest_first(), [
		"13:00  A guest left: shop closed",
		"13:00  A guest left: shop closed",
	] as Array[String])


func test_cap_removes_oldest_rows_and_clear_restarts_fresh() -> void:
	for index: int in 203:
		_log.add(index, DayLog.Kind.SERVICE_EVENT, "Service note %d" % index)
	var lines: Array[String] = _log.newest_first()
	assert_eq(lines.size(), 200)
	assert_true(lines[0].ends_with("Service note 202"))
	assert_true(lines[199].ends_with("Service note 3"))
	lines.clear()
	assert_eq(_log.newest_first().size(), 200, "the returned view cannot change the live log")
	_log.clear()
	_add(0, DayLog.Kind.INSPECTOR, "The health inspector arrived")
	assert_eq(_log.newest_first(), ["12:00  The health inspector arrived"] as Array[String])


func _add(tick: int, kind: DayLog.Kind, text: String) -> void:
	_clock.phase_tick = tick
	_log.add(tick, kind, text)
