class_name InspectorAgent
extends SimAgent
## The health inspector (#302): a person who walks in like a guest, walks the
## dining room and the restroom for about a minute with a clipboard, then leaves.
##
## It is a real person on the guest layer: it reserves cells through the
## movement coordinator like any guest (at guest priority, so staff go first),
## but it is not a CustomerAgent: it takes no table, orders nothing, pays
## nothing, never counts as served or lost and leaves no review. It draws no
## random numbers: the stops are picked from the grid in a fixed way. It never
## stands for long (a look at each stop, then on) and a hard cap sends it out,
## so it cannot block anybody for good.

enum State { WALKING, LOOKING, LEAVING, LEFT }

## Ticks without moving on the way out before trying the other door, and
## before giving up (and being taken out of the shop like a stuck guest).
const LEAVE_REROUTE_TICKS: int = 300
const LEAVE_GIVE_UP_TICKS: int = 600

var state: State = State.WALKING
## The walk is over: the sim records the grade (once).
var checked: bool = false
var recorded: bool = false
## How many stops they have reached and looked at. With none there is nothing
## to grade. `facts` is the shop as the sim read it at the last of them.
var looked: int = 0
var facts: Dictionary = {}
var tuning: InspectionTuning
var stops: Array[Vector2i] = []
var stop_index: int = 0
## The world tick the visit began on (-1 until its first tick).
var started_tick: int = -1

var _look_left: int = 0
var _skipped: int = 0
var _exit_unreachable: int = 0
var _stop_since: int = 0
var _leave_idle: int = 0
var _leave_cell: Vector2i = SimGrid.NO_CELL
var _avoid_entry: Vector2i = SimGrid.NO_CELL


func _init(config: InspectionTuning = null) -> void:
	tuning = config if config != null else InspectionTuning.new()
	role = &"inspector"
	display_name = "Health inspector"


func uses_guest_layer() -> bool:
	return true


## The street door it gave up on after being blocked there (NO_CELL if none).
func avoided_entry() -> Vector2i:
	return _avoid_entry


## Guests (and the inspector) never walk through the kitchen or storage.
func plan_path(grid: SimGrid, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return grid.find_guest_path(from_cell, to_cell)


func why() -> String:
	match state:
		State.WALKING:
			return "Inspecting the shop"
		State.LOOKING:
			return "Checking things over"
	return "Heading out"


func tick(world: SimWorld) -> void:
	if started_tick < 0:
		started_tick = world.now
		_stop_since = world.now
		stops = choose_stops(world.grid, cell, tuning.dining_stops)
	if world.clock.phase == SimClock.Phase.CLOSED and state != State.LEFT:
		# The sim removes the inspector on this tick and grades what it saw.
		return
	var elapsed: int = world.now - started_tick
	if state == State.WALKING or state == State.LOOKING:
		if elapsed >= tuning.visit_ticks or stops.is_empty() or _skipped > stops.size() \
				or elapsed >= tuning.visit_cap_ticks:
			_begin_leaving()
	match state:
		State.WALKING:
			_walk_to_stop(world)
		State.LOOKING:
			last_progress_tick = world.now
			if cell != stops[stop_index] or move_progress > 0.0:
				# Stepped aside for someone (a yield): go back to the stop.
				state = State.WALKING
				_stop_since = world.now
				return
			_look_left -= 1
			if _look_left <= 0:
				_next_stop(world)
		State.LEAVING:
			_walk_to_exit(world)


func _reach_stop() -> void:
	state = State.LOOKING
	_look_left = tuning.look_ticks
	_skipped = 0
	looked += 1
	clear_path()


func _begin_leaving() -> void:
	checked = true
	state = State.LEAVING
	clear_path()
	_exit_unreachable = 0
	_leave_idle = 0
	_leave_cell = cell


func _next_stop(world: SimWorld) -> void:
	stop_index = (stop_index + 1) % maxi(1, stops.size())
	state = State.WALKING
	_stop_since = world.now
	clear_path()


func _walk_to_stop(world: SimWorld) -> void:
	var target: Vector2i = stops[stop_index]
	if cell == target and move_progress == 0.0:
		_reach_stop()
		return
	# A stop that cannot be reached or is taking far too long is given up.
	if world.now - _stop_since > 400:
		_skipped += 1
		_next_stop(world)
		return
	if needs_repath or path.is_empty() or destination() != target:
		if not set_destination(world.grid, target) or path.size() < 2:
			_skipped += 1
			_next_stop(world)
			return
	var result: MoveResult = step_move(world)
	if result == MoveResult.ARRIVED and cell == target:
		_reach_stop()
	elif result == MoveResult.BLOCKED:
		clear_path()


func _walk_to_exit(world: SimWorld) -> void:
	if move_progress == 0.0 and world.grid.entries().has(cell):
		state = State.LEFT
		return
	# Stuck behind people: after a while try the other door, then give up the
	# way a guest does (the sim removes them).
	if cell != _leave_cell or move_progress > 0.0:
		_leave_cell = cell
		_leave_idle = 0
	else:
		_leave_idle += 1
		if _leave_idle == LEAVE_REROUTE_TICKS:
			_avoid_entry = destination()
			clear_path()
		elif _leave_idle >= LEAVE_GIVE_UP_TICKS:
			world.log_event("Inspector removed: blocked on the way out")
			state = State.LEFT
			return
	if needs_repath or path.is_empty():
		var goals: Array[Vector2i] = []
		for entry: Vector2i in world.grid.entries():
			if entry != _avoid_entry:
				goals.append(entry)
		if goals.is_empty():
			goals = world.grid.entries()
		var route: Array[Vector2i] = world.grid.find_guest_path_to_any(cell, goals)
		if route.is_empty() or not set_destination(world.grid, route.back()):
			_exit_unreachable += 1
			if _exit_unreachable >= 100:
				world.log_event("Inspector removed: exit unreachable for 100 ticks")
				state = State.LEFT
			return
		_exit_unreachable = 0
	var result: MoveResult = step_move(world)
	if move_progress == 0.0 and world.grid.entries().has(cell):
		state = State.LEFT
		return
	match result:
		MoveResult.ARRIVED:
			if world.grid.entries().has(cell):
				state = State.LEFT
			else:
				clear_path()
		MoveResult.BLOCKED:
			clear_path()


## Dining room stops spread evenly over the room, then one in the restroom if
## there is one, ordered by a nearest-first walk from `from_cell`. Pure grid
## reading: the same shop always gives the same round.
static func choose_stops(grid: SimGrid, from_cell: Vector2i, dining_count: int) -> Array[Vector2i]:
	var entries: Array[Vector2i] = grid.entries()
	# Not in the doorway lane, and never on a work spot (a toilet's use spot,
	# a station): those are where somebody else needs to stand.
	var avoid: Dictionary[Vector2i, bool] = {}
	for door: Vector2i in ExteriorSupport.door_cells(grid):
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				avoid[door + Vector2i(dx, dy)] = true
	for item: PlacedItem in grid.items():
		if item.removed:
			continue
		for work: Vector2i in item.work_cells:
			avoid[work] = true
	# One flood fill from where they stand tells which cells a guest can reach.
	var reachable: Dictionary[Vector2i, bool] = grid.reachable_avoiding(from_cell, {}, true)
	var dining: Array[Vector2i] = []
	var restroom: Array[Vector2i] = []
	for spot: Vector2i in grid.cells():
		if grid.terrain(spot) != SimGrid.Terrain.FLOOR or not grid.is_guest_walkable(spot) \
				or not grid.seat_items_at(spot).is_empty() or entries.has(spot) \
				or avoid.has(spot) or not reachable.has(spot):
			continue
		match grid.room(spot):
			SimGrid.Room.DINING:
				dining.append(spot)
			SimGrid.Room.RESTROOM:
				restroom.append(spot)
	var chosen: Array[Vector2i] = []
	var wanted: int = mini(dining_count, dining.size())
	for index: int in wanted:
		chosen.append(dining[floori((float(index) + 0.5) * float(dining.size()) / float(wanted))])
	if not restroom.is_empty():
		chosen.append(restroom[restroom.size() / 2])
	var ordered: Array[Vector2i] = []
	var here: Vector2i = from_cell
	while not chosen.is_empty():
		var best: int = 0
		for index: int in range(1, chosen.size()):
			if GridMath.octile(here, chosen[index]) < GridMath.octile(here, chosen[best]):
				best = index
		here = chosen[best]
		ordered.append(here)
		chosen.remove_at(best)
	return ordered
