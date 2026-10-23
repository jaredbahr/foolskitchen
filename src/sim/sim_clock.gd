class_name SimClock
extends RefCounted
## Deterministic day clock. Each advance is one fixed simulation tick;
## morning and closed are menu phases and never consume simulation time.

enum Phase { MORNING, OPEN, LAST_ORDERS, CLOSED }

## Sim ticks per game second at 1x speed (Clock drives this many per real second).
const TICKS_PER_SECOND: int = 10

## Emitted after every transition, with the new day and phase.
signal phase_changed(day: int, phase: Phase)

var day: int = 1
var phase: Phase = Phase.MORNING
var tick: int = 0
var phase_tick: int = 0

## Configuration in fixed ticks and displayed minutes since midnight.
var open_ticks: int = 3600
var last_orders_max_ticks: int = 900
var display_open_minute: int = 11 * 60
var display_close_minute: int = 21 * 60


func start_service() -> bool:
	if phase != Phase.MORNING:
		return false
	_transition_to(Phase.OPEN)
	return true


func advance() -> void:
	if phase != Phase.OPEN and phase != Phase.LAST_ORDERS:
		return
	tick += 1
	phase_tick += 1
	if phase == Phase.OPEN and phase_tick >= open_ticks:
		_transition_to(Phase.LAST_ORDERS)
	elif phase == Phase.LAST_ORDERS and phase_tick >= last_orders_max_ticks:
		_transition_to(Phase.CLOSED)


func notify_restaurant_empty() -> void:
	if phase == Phase.LAST_ORDERS:
		_transition_to(Phase.CLOSED)


func next_day() -> bool:
	if phase != Phase.CLOSED:
		return false
	day += 1
	_transition_to(Phase.MORNING)
	return true


func display_minutes() -> int:
	match phase:
		Phase.OPEN:
			var progress: float = clampf(float(phase_tick) / float(maxi(open_ticks, 1)), 0.0, 1.0)
			return display_open_minute + floori(progress * (display_close_minute - display_open_minute))
		Phase.LAST_ORDERS, Phase.CLOSED:
			return display_close_minute
		_:
			return display_open_minute


## Includes configuration so loading a run preserves its day length.
func to_dict() -> Dictionary:
	return {
		"day": day,
		"phase": phase,
		"tick": tick,
		"phase_tick": phase_tick,
		"open_ticks": open_ticks,
		"last_orders_max_ticks": last_orders_max_ticks,
		"display_open_minute": display_open_minute,
		"display_close_minute": display_close_minute,
	}


## Restores clock data without emitting a transition or advancing time.
static func from_dict(d: Dictionary) -> SimClock:
	var clock: SimClock = SimClock.new()
	clock.day = int(d.get("day", clock.day))
	clock.phase = int(d.get("phase", clock.phase)) as Phase
	clock.tick = int(d.get("tick", clock.tick))
	clock.phase_tick = int(d.get("phase_tick", clock.phase_tick))
	clock.open_ticks = int(d.get("open_ticks", clock.open_ticks))
	clock.last_orders_max_ticks = int(d.get("last_orders_max_ticks", clock.last_orders_max_ticks))
	clock.display_open_minute = int(d.get("display_open_minute", clock.display_open_minute))
	clock.display_close_minute = int(d.get("display_close_minute", clock.display_close_minute))
	return clock


func _transition_to(value: Phase) -> void:
	phase = value
	phase_tick = 0
	phase_changed.emit(day, phase)
