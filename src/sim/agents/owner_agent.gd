class_name OwnerAgent
extends StaffAgent
## An owner keeps their role while choosing which ordinary staff work to help.
## The session owns creation, selection, persistence and assignment commands.

const MODES: Array[StringName] = [&"kitchen", &"floor", &"help", &"rest"]
const HOME_ATTEMPTS: int = 3
const HOME_RETRY_TICKS: int = 10
const HOME_STALL_TICKS: int = 30

var _mode: StringName = &"rest"
var _home: Vector2i
var _home_grid: WeakRef = null
var _home_changed: bool = false
var _home_planned: bool = false
var _home_attempts: int = 0
var _home_retry_at: int = 0
var _home_stalled: int = 0
var _home_failure: String = ""


func _init(spawn_cell: Vector2i = Vector2i.ZERO) -> void:
	super(&"owner", 3)
	_home = spawn_cell
	cell = spawn_cell
	skills[&"cook"] = 3
	skills[&"server"] = 3
	_apply_priorities()


func current_mode() -> StringName:
	return _mode


func home_cell() -> Vector2i:
	return _home


## A repeated command preserves work, movement progress and recovery budgets.
## Newly disabled work is released by the next owner tick, never completed here.
func assign_mode(mode: StringName) -> bool:
	if not MODES.has(mode):
		return false
	if mode == _mode:
		return true
	if _mode == &"rest" and task == null:
		clear_path()
	_mode = mode
	_apply_priorities()
	_reset_home_recovery()
	return true


func tick(world: SimWorld) -> void:
	_bind_home_grid(world.grid)
	if _home_changed:
		if _mode == &"rest":
			_reset_home_recovery()
		_home_changed = false
	if task != null and int(priorities.get(task.role, 0)) == 0:
		if task.state == SimTask.State.CLAIMED and task.claimed_by == id:
			var reason: StringName = &"owner_rest" if _mode == &"rest" else &"owner_reassigned"
			world.log_event("Owner #%d gave back %s (%s)" % [id, task.label, reason])
			world.board.drop(task, reason)
		# StaffAgent notices the settled task and performs its own reservation,
		# step and path cleanup. Do not copy its private bookkeeping or on_done.
		super.tick(world)
		if _mode == &"rest":
			_walk_home(world)
		return
	if _mode == &"rest":
		_walk_home(world)
	else:
		super.tick(world)


func why() -> String:
	if task != null:
		if int(priorities.get(task.role, 0)) == 0:
			return "Changing to %s: giving back %s on the next tick" % [_mode, task.label]
		return super.why()
	if _mode != &"rest":
		match _mode:
			&"kitchen": return "Helping in the kitchen: looking for cooking work"
			&"floor": return "Helping on the floor: looking for service work"
		return "Helping where needed: looking for work"
	if _home_failure == "home spot blocked":
		return "Standing back: home spot is blocked; waiting for a shop change"
	if cell == _home and has_arrived():
		return "Standing back at home"
	if not _home_planned and _home_attempts >= HOME_ATTEMPTS:
		return "Standing back: cannot get home (%s); waiting for a shop change" % _home_failure
	if not _home_failure.is_empty() and not _home_planned:
		return "Standing back: home route blocked (%s); retrying soon" % _home_failure
	return "Standing back: walking home"


func on_removed(world: SimWorld) -> void:
	_disconnect_home_grid()
	super.on_removed(world)
	clear_path()
	_reset_home_recovery()


func _apply_priorities() -> void:
	# StaffAgent's initial owner/any priorities must not leak into any mode.
	priorities.clear()
	priorities[&"owner"] = 0
	priorities[&"any"] = 0
	priorities[&"cook"] = 3 if _mode == &"kitchen" else (1 if _mode == &"help" else 0)
	priorities[&"server"] = 3 if _mode == &"floor" else (1 if _mode == &"help" else 0)
	priorities[&"cleaner"] = 1 if _mode == &"floor" else 0


func _walk_home(world: SimWorld) -> void:
	if cell == _home:
		clear_path()
		_home_planned = false
		if world.grid.is_walkable(_home):
			_home_failure = ""
		else:
			_home_attempts = HOME_ATTEMPTS
			_home_failure = "home spot blocked"
		return
	if _home_planned and (needs_repath or has_arrived()):
		_home_planned = false
	if not _home_planned:
		if _home_attempts >= HOME_ATTEMPTS or world.now < _home_retry_at:
			return
		_home_attempts += 1
		if not set_destination(world.grid, _home):
			_wait_to_retry_home(world, "no route")
			return
		_home_planned = true
		_home_stalled = 0
		_home_failure = ""
	var previous_cell: Vector2i = cell
	var previous_progress: float = move_progress
	var result: MoveResult = step_move(world)
	if result == MoveResult.BLOCKED:
		_wait_to_retry_home(world, "blocked path")
	elif result == MoveResult.ARRIVED:
		clear_path()
		_home_planned = false
	elif cell != previous_cell or move_progress != previous_progress:
		_home_stalled = 0
	else:
		_home_stalled += 1
		if _home_stalled >= HOME_STALL_TICKS:
			_wait_to_retry_home(world, "no movement")


func _wait_to_retry_home(world: SimWorld, reason: String) -> void:
	clear_path()
	_home_planned = false
	_home_stalled = 0
	_home_retry_at = world.now + HOME_RETRY_TICKS
	_home_failure = reason


func _reset_home_recovery() -> void:
	_home_planned = false
	_home_attempts = 0
	_home_retry_at = 0
	_home_stalled = 0
	_home_failure = ""


## A weak grid reference avoids a grid -> callback -> owner -> grid cycle.
## Changed geometry grants a fresh bounded attempt budget, including after an
## unreachable route was exhausted and no remaining path could be marked.
func _bind_home_grid(grid: SimGrid) -> void:
	if _home_grid != null and _home_grid.get_ref() == grid:
		return
	_disconnect_home_grid()
	_home_grid = weakref(grid)
	grid.cells_changed.connect(_on_home_cells_changed)
	_home_changed = true


func _disconnect_home_grid() -> void:
	if _home_grid != null:
		var grid: SimGrid = _home_grid.get_ref() as SimGrid
		if grid != null and grid.cells_changed.is_connected(_on_home_cells_changed):
			grid.cells_changed.disconnect(_on_home_cells_changed)
	_home_grid = null


func _on_home_cells_changed(_cells: Array[Vector2i]) -> void:
	_home_changed = true
