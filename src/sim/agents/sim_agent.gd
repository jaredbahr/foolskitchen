class_name SimAgent
extends RefCounted
## Anything that walks the grid: staff, the owner, customers. Holds a grid
## cell, a path and a fractional progress toward the next cell, which the
## world view interpolates. Subclasses decide what to do in tick().

enum MoveResult { ARRIVED, MOVING, BLOCKED }

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

var _goal: Vector2i = Vector2i(-1, -1)


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
	_goal = goal
	needs_repath = false
	path = grid.find_path(cell, goal)
	path_index = 1
	if path.size() < 2 or path[1] != old_next:
		move_progress = 0.0
	return not path.is_empty()


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
		return MoveResult.ARRIVED
	var next := path[path_index]
	if not world.grid.is_walkable(next) or not world.grid.step_open(cell, next):
		return MoveResult.BLOCKED
	var d := next - cell
	var step_len := GridMath.DIAGONAL_COST if d.x != 0 and d.y != 0 else 1.0
	# A buried agent's exit step can be longer than one cell.
	step_len = maxf(step_len, float(maxi(absi(d.x), absi(d.y))))
	move_progress += move_speed / step_len
	last_progress_tick = world.now
	if move_progress >= 1.0:
		move_progress = 0.0
		cell = next
		path_index += 1
		last_progress_tick = world.now
	return MoveResult.ARRIVED if has_arrived() else MoveResult.MOVING


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
		return MoveResult.ARRIVED
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
		cell = next
		path_index += 1
		last_progress_tick = world.now
	return MoveResult.ARRIVED if has_arrived() else MoveResult.MOVING


## Called by SimWorld.remove_agent: give back anything held (tasks, cells).
func on_removed(_world: SimWorld) -> void:
	pass


## Stops walking.
func clear_path() -> void:
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
