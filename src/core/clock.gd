extends Node
## Converts real frame time into fixed simulation ticks. Speed changes tick
## frequency, never tick length. Menu phases do not accumulate a backlog.

## Keep the public phase names available to existing Clock callers.
const Phase: Dictionary = SimClock.Phase

## Sim ticks per in-game second.
const TICKS_PER_SECOND: int = SimClock.TICKS_PER_SECOND
const MAX_TICKS_PER_FRAME: int = 40

## Allowed speed multipliers. 0 = paused.
const SPEEDS: Array[int] = [0, 1, 2, 4]

var sim: SimClock = SimClock.new():
	set(value):
		if value == null or value == sim:
			return
		if sim.phase_changed.is_connected(_on_phase_changed):
			sim.phase_changed.disconnect(_on_phase_changed)
		sim = value
		sim.phase_changed.connect(_on_phase_changed)
		_accumulator = 0.0

## Compatibility accessors for the original autoload's clock state.
var day: int:
	get:
		return sim.day
var phase: SimClock.Phase:
	get:
		return sim.phase
var tick: int:
	get:
		return sim.tick

var speed: int = 0
var _last_non_zero_speed: int = 1
var _accumulator: float = 0.0


func _init() -> void:
	sim.phase_changed.connect(_on_phase_changed)


func _ready() -> void:
	SaveSystem.register("clock", _capture_save, _restore_save)


func _capture_save() -> Dictionary:
	return sim.to_dict()


func _restore_save(data: Dictionary) -> bool:
	# Validate before SimClock.from_dict converts numbers and before replacing sim.
	var minimums: Dictionary[String, int] = {
		"day": 1, "phase": 0, "tick": 0, "phase_tick": 0,
		"open_ticks": 1, "last_orders_max_ticks": 1,
		"display_open_minute": 0, "display_close_minute": 0,
	}
	for key: String in minimums:
		if not data.has(key):
			continue
		var maximum: int = 9223372036854775807
		if key == "phase":
			maximum = SimClock.Phase.CLOSED
		elif key.begins_with("display_"):
			maximum = 24 * 60
		if not _valid_save_integer(data[key], minimums[key], maximum):
			return false
	var opening: int = int(data.get("display_open_minute", 11 * 60))
	var closing: int = int(data.get("display_close_minute", 21 * 60))
	if closing < opening:
		return false
	sim = SimClock.from_dict(data)
	return true


func _valid_save_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return value >= minimum and value <= maximum
	if not value is float:
		return false
	# JSON parses numbers as floats. Reject fractions/nonfinite values and the
	# rounded 2^63 boundary before any int conversion can overflow.
	var number: float = value
	return is_finite(number) and number >= minimum and number <= maximum and number < 9223372036854775808.0 and floorf(number) == number


## Sets the speed. Only values in SPEEDS are accepted; returns false otherwise.
func set_speed(value: int) -> bool:
	if not SPEEDS.has(value):
		return false
	speed = value
	if value > 0:
		_last_non_zero_speed = value
	return true


func _process(delta: float) -> void:
	if sim.phase != SimClock.Phase.OPEN and sim.phase != SimClock.Phase.LAST_ORDERS:
		_accumulator = 0.0
		return
	_accumulator += maxf(delta, 0.0) * speed * TICKS_PER_SECOND
	var ticks_this_frame: int = 0
	while _accumulator >= 1.0 and ticks_this_frame < MAX_TICKS_PER_FRAME:
		if sim.phase != SimClock.Phase.OPEN and sim.phase != SimClock.Phase.LAST_ORDERS:
			_accumulator = 0.0
			break
		sim.advance()
		EventBus.sim_ticked.emit(sim.tick)
		_accumulator -= 1.0
		ticks_this_frame += 1
	if ticks_this_frame == MAX_TICKS_PER_FRAME:
		# Discard overdue whole ticks; retain only the sub-tick fraction.
		_accumulator = fmod(_accumulator, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"speed_pause"):
		set_speed(_last_non_zero_speed if speed == 0 else 0)
	elif event.is_action_pressed(&"speed_1"):
		set_speed(1)
	elif event.is_action_pressed(&"speed_2"):
		set_speed(2)
	elif event.is_action_pressed(&"speed_4"):
		set_speed(4)


func _on_phase_changed(current_day: int, current_phase: SimClock.Phase) -> void:
	EventBus.day_phase_changed.emit(current_day, current_phase)
