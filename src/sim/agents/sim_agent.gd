class_name SimAgent
extends RefCounted
## Anything that walks the grid: staff, the owner, customers. Holds a grid
## cell, a path and a fractional progress toward the next cell, which the
## world view interpolates. Subclasses decide what to do in tick().

enum MoveResult { ARRIVED, MOVING, BLOCKED }

## How far (m) each person bows sideways at the middle of a squeeze-past.
const SQUEEZE_BOW: float = 0.14

## Assigned by SimWorld.add_agent (never reused).
var id: int = 0
## &"cook", &"server", &"owner", &"customer", ...
var role: StringName = &""
var display_name: String = ""
var cell: Vector2i = Vector2i.ZERO
## Cells per tick at work speed 1 (0.25 = 2.5 cells/s = 1.25 m/s at 1x).
var move_speed: float = 0.25
## Path being walked; path[path_index] is the next cell to enter.
var path: Array[Vector2i] = []
var path_index: int = 0
## 0..1 progress from `cell` toward path[path_index]. For the world view.
var move_progress: float = 0.0
## Set by SimWorld when the remaining path crosses a changed cell.
var needs_repath: bool = false
## Last world tick this agent moved a cell or did a unit of work.
var last_progress_tick: int = 0
## Pending requests live outside SimWorld.agents until physically admitted.
var movement_admitted: bool = false
## During a squeeze-past (#306) the two people bow to opposite sides of their
## shared edge (+1 / -1), so the swap is drawn as passing, never overlapping.
var squeeze_side: float = 0.0
var _movement_world: WeakRef
var _trace_tick: int = -1
var _trace_points: Array[Vector3] = []
var _trace_times: Array[float] = []
var _trace_discontinuous: bool = true
var _trace_cause: String = "admission"

var _goal: Vector2i = SimGrid.NO_CELL


## True for a person who keeps to the guest layer: never through the kitchen
## or storage (guests, the health inspector). Staff path everywhere.
func uses_guest_layer() -> bool:
	return false


## Runs one sim tick. Subclasses override.
func tick(_world: SimWorld) -> void:
	pass


## Player-facing "what am I doing and why", for the click readout.
func why() -> String:
	return "Idle"


## Plans a path to `goal`. False if unreachable (path cleared). If the new
## path heads into the same next cell, progress toward it is kept, so a
## re-plan never snaps the agent backwards.
func set_destination(grid: SimGrid, goal: Vector2i) -> bool:
	var old_next := next_cell()
	var was_moving: bool = move_progress > 0.0
	var previous_goal: Vector2i = _goal
	_goal = goal
	needs_repath = false
	var world: SimWorld = movement_world()
	if world != null and world.grid == grid and movement_admitted and not was_moving and goal != previous_goal:
		world.movement.supersede_destination(id)
	path = world.movement.route(world, self, cell, goal, false) \
		if world != null and world.grid == grid else plan_path(grid, cell, goal)
	var found: bool = not path.is_empty()
	path_index = 1
	if was_moving and world != null and movement_admitted:
		world.movement.stop_motion(id, goal if found else SimGrid.NO_CELL)
		path = [cell, old_next]
		path_index = 1
		return found
	if path.size() < 2 or path[1] != old_next:
		move_progress = 0.0
	return found


func bind_movement(world: SimWorld) -> void:
	_movement_world = weakref(world)


func movement_world() -> SimWorld:
	return _movement_world.get_ref() as SimWorld if _movement_world != null else null


func destination() -> Vector2i:
	return _goal


func install_movement_route(cells: Array[Vector2i]) -> void:
	var was_moving: bool = move_progress > 0.0
	var world: SimWorld = movement_world()
	if was_moving and world != null and movement_admitted:
		set_destination(world.grid, cells.back() if not cells.is_empty() else SimGrid.NO_CELL)
		return
	path = cells.duplicate()
	path_index = 1
	move_progress = 0.0
	needs_repath = false


func movement_position() -> Vector3:
	var start: Vector3 = GridMath.cell_to_world(cell)
	var end: Vector3 = GridMath.cell_to_world(next_cell())
	var progress: float = clampf(move_progress, 0.0, 1.0)
	var position: Vector3 = start.lerp(end, progress)
	if squeeze_side != 0.0 and end != start:
		var side: Vector3 = (end - start).normalized().cross(Vector3.UP)
		position += side * SQUEEZE_BOW * squeeze_side * sin(PI * progress)
	return position


func reset_movement_trace(tick: int, cause: String = "reset") -> void:
	_trace_tick = tick
	_trace_points = [movement_position(), movement_position()]
	_trace_times = [0.0, 1.0]
	_trace_discontinuous = true
	_trace_cause = cause


func begin_movement_trace(tick: int) -> void:
	var reset_this_tick: bool = _trace_tick == tick and _trace_discontinuous
	_trace_tick = tick
	_trace_points = [movement_position()]
	_trace_times = [0.0]
	_trace_discontinuous = reset_this_tick
	if not reset_this_tick:
		_trace_cause = ""


func movement_trace_point(time: float) -> void:
	_trace_points.append(movement_position())
	_trace_times.append(clampf(time, 0.0, 1.0))


func end_movement_trace() -> void:
	if _trace_times.is_empty() or _trace_times.back() < 1.0:
		movement_trace_point(1.0)


func movement_trace() -> Dictionary:
	return {"tick": _trace_tick, "points": _trace_points.duplicate(),
		"times": _trace_times.duplicate(), "discontinuous": _trace_discontinuous,
		"discontinuity_cause": _trace_cause}


## The route this agent would walk. Guests override it to stay out of
## staff-only rooms (FK-101); staff path everywhere.
func plan_path(grid: SimGrid, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return grid.find_path(from_cell, to_cell)


## Re-plans to the current goal (after the layout changed).
func repath(grid: SimGrid) -> bool:
	return set_destination(grid, _goal)


func has_arrived() -> bool:
	return path.is_empty() or path_index >= path.size()


## The cell being walked into, or the current cell when standing still.
func next_cell() -> Vector2i:
	return cell if has_arrived() else path[path_index]


## Advances along the path. BLOCKED when the next cell stopped being walkable
## (the caller should repath). The first step out of a blocked start cell is
## always allowed, so agents can leave furniture placed on them.
func step_move(world: SimWorld) -> MoveResult:
	var multiplier: float = movement_multiplier()
	if multiplier != 1.0:
		return _step_move_scaled(world, multiplier)
	if has_arrived():
		return MoveResult.MOVING if world.movement.is_stopping(id) else MoveResult.ARRIVED
	var next := path[path_index]
	if not world.grid.is_walkable(next) or not world.grid.step_open(cell, next):
		return MoveResult.BLOCKED
	if not world.movement.try_step(world, self, next):
		return MoveResult.MOVING
	var d := next - cell
	var step_len := GridMath.DIAGONAL_COST if d.x != 0 and d.y != 0 else 1.0
	# A buried agent's exit step can be longer than one cell.
	step_len = maxf(step_len, float(maxi(absi(d.x), absi(d.y))))
	var before: float = move_progress
	move_progress += move_speed / step_len
	last_progress_tick = world.now
	if move_progress >= 1.0:
		move_progress = 0.0
		var from: Vector2i = cell
		cell = next
		path_index += 1
		world.movement.complete_step(world, self, from, next)
		movement_trace_point((1.0 - before) * step_len / move_speed)
		last_progress_tick = world.now
	return MoveResult.ARRIVED if has_arrived() and not world.movement.is_stopping(id) else MoveResult.MOVING


## Neutral agents retain the original per-tick movement above, including its
## diagonal rounding. Staff override only this opt-in; the owner remains neutral.
func movement_multiplier() -> float:
	return 1.0


## Scale the EXISTING edge's quantized travel time, rather than geometric
## distance: a neutral 0.25 agent takes 4 straight / 6 diagonal ticks. Scaling
## raw distance only for Quick would inadvertently give an 18% diagonal gain.
## Budget is in baseline ticks and converts using each NEXT edge's own cost.
## Only current path progress survives; unused arrival/blocked credit is lost.
func _step_move_scaled(world: SimWorld, multiplier: float) -> MoveResult:
	if has_arrived():
		return MoveResult.MOVING if world.movement.is_stopping(id) else MoveResult.ARRIVED
	if not is_finite(multiplier) or multiplier <= 0.0 or not is_finite(move_speed) or move_speed <= 0.0:
		return MoveResult.MOVING
	var baseline_speed: float = move_speed / multiplier
	if not is_finite(baseline_speed) or baseline_speed <= 0.0:
		return MoveResult.MOVING
	var budget: float = multiplier
	while budget > 0.0 and not has_arrived():
		var next: Vector2i = path[path_index]
		if not world.grid.is_walkable(next) or not world.grid.step_open(cell, next):
			return MoveResult.BLOCKED
		if not world.movement.try_step(world, self, next):
			return MoveResult.MOVING
		var delta: Vector2i = next - cell
		var length: float = GridMath.DIAGONAL_COST if delta.x != 0 and delta.y != 0 else 1.0
		length = maxf(length, float(maxi(absi(delta.x), absi(delta.y))))
		var cost: float = float(maxi(1, ceili(length / baseline_speed)))
		var needed: float = (1.0 - move_progress) * cost
		if budget < needed:
			move_progress += budget / cost
			last_progress_tick = world.now
			return MoveResult.MOVING
		budget -= needed
		move_progress = 0.0
		var from: Vector2i = cell
		cell = next
		path_index += 1
		world.movement.complete_step(world, self, from, next)
		movement_trace_point((multiplier - budget) / multiplier)
		last_progress_tick = world.now
	return MoveResult.ARRIVED if has_arrived() and not world.movement.is_stopping(id) else MoveResult.MOVING


## Called by SimWorld.remove_agent: give back anything held (tasks, cells).
func on_removed(_world: SimWorld) -> void:
	pass


## Stops walking.
func clear_path() -> void:
	var world: SimWorld = movement_world()
	var was_moving: bool = move_progress > 0.0
	if world != null and was_moving and movement_admitted and not has_arrived():
		var current_next: Vector2i = next_cell()
		world.movement.stop_motion(id)
		path = [cell, current_next]
		path_index = 1
		needs_repath = false
		return
	if world != null:
		world.movement.release_motion(id)
	path = []
	path_index = 0
	move_progress = 0.0
	needs_repath = false


## True if any of `cells` lies on the part of the path not yet walked,
## including the cell being left: a wall edit beside it can close the next step.
func path_crosses(cells: Array[Vector2i]) -> bool:
	if not has_arrived() and cells.has(cell):
		return true
	for i in range(path_index, path.size()):
		if cells.has(path[i]):
			return true
	return false
