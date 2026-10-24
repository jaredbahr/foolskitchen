class_name DebugOverlay
extends Control
## Read-only diagnostics. The session owns input, refresh timing and rate samples.

const RATE_WINDOW_SECONDS: float = 1.0
const LOG_LINES: int = 15

## Measured values, exposed independently of label formatting.
var frames_per_second: float = 0.0
var ticks_per_second: float = 0.0

var _world: SimWorld
var _cleanliness: CleanlinessState
var _enabled: bool = false
var _rates: Label
var _tasks: Label
var _log: Label
var _window_time: float = -1.0
var _window_tick: int = 0
var _last_time: float = -1.0
var _last_tick: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _ready() -> void:
	visible = _enabled
	refresh()


## Rebinding also discards rate history, even if the same world is supplied.
func bind_world(value: SimWorld) -> void:
	if _world != value:
		_cleanliness = null
	_world = value
	frames_per_second = 0.0
	_reset_sampling()
	refresh()


## Main supplies the optional day-local floor state after binding the world.
func bind_cleanliness(value: CleanlinessState) -> void:
	_cleanliness = value
	refresh()


func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if value:
		refresh()


func is_enabled() -> bool:
	return _enabled


## Reads snapshots only; safe before _ready() and with an empty/unbound world.
func refresh() -> void:
	if not _bind_nodes():
		return
	_refresh_rates()
	if _world == null:
		_tasks.text = "No world attached"
		_log.text = "No events yet"
		return
	var tasks: Array[SimTask] = _world.board.open_tasks()
	tasks.append_array(_world.board.claimed_tasks())
	tasks.sort_custom(_task_id_before)
	var rows: PackedStringArray = []
	for task: SimTask in tasks:
		var state: String = "claimed" if task.state == SimTask.State.CLAIMED else "open"
		var claimant: String = "#%d" % task.claimed_by if task.state == SimTask.State.CLAIMED else "-"
		rows.append("#%d %s | %s | claimant %s | age %d ticks" % [
			task.id, task.label, state, claimant, _world.now - task.posted_tick])
	_tasks.text = "No active tasks" if rows.is_empty() else "\n".join(rows)
	var first: int = maxi(0, _world.event_log.size() - LOG_LINES)
	_log.text = "No events yet" if _world.event_log.is_empty() else "\n".join(_world.event_log.slice(first))


## Uses monotonic wall time and world ticks, not configured speed or clock.tick.
## A full window without world progress reports zero, including paused menus.
func sample_rates(real_time_seconds: float, fps: float) -> void:
	frames_per_second = maxf(0.0, fps) if is_finite(fps) else 0.0
	if _world == null or not is_finite(real_time_seconds) or real_time_seconds < 0.0:
		_reset_sampling()
	elif _window_time < 0.0 or real_time_seconds < _last_time or _world.now < _last_tick:
		_start_window(real_time_seconds, _world.now)
		ticks_per_second = 0.0
	else:
		var elapsed: float = real_time_seconds - _window_time
		if elapsed >= RATE_WINDOW_SECONDS:
			ticks_per_second = float(_world.now - _window_tick) / elapsed
			_start_window(real_time_seconds, _world.now)
		_last_time = real_time_seconds
		_last_tick = _world.now
	if _bind_nodes():
		_refresh_rates()


func _reset_sampling() -> void:
	ticks_per_second = 0.0
	_window_time = -1.0
	_window_tick = 0
	_last_time = -1.0
	_last_tick = 0


func _start_window(time: float, tick: int) -> void:
	_window_time = time
	_window_tick = tick
	_last_time = time
	_last_tick = tick


func _bind_nodes() -> bool:
	if _rates == null:
		_rates = get_node_or_null("Panel/Margin/Scroll/Content/Rates") as Label
		_tasks = get_node_or_null("Panel/Margin/Scroll/Content/Tasks") as Label
		_log = get_node_or_null("Panel/Margin/Scroll/Content/Log") as Label
	return _rates != null and _tasks != null and _log != null


func _refresh_rates() -> void:
	_rates.text = "FPS %.0f  |  Sim %.1f ticks/s" % [frames_per_second, ticks_per_second]
	if _world != null and _cleanliness != null:
		_rates.text += "  |  Floor spots %d" % _cleanliness.spot_count()


func _task_id_before(a: SimTask, b: SimTask) -> bool:
	return a.id < b.id
