class_name RestaurantCat
extends RefCounted
## The restaurant cat (#119): one shop pet that wanders the guest rooms, naps
## in sunny spots and makes waiting guests a little more patient.
##
## It is not a person. It is not in SimWorld.agents, so it never joins the
## movement coordinator, reserves a cell, holds a seat or blocks anyone: people
## and the cat may share a cell. It walks only on floor a guest could stand on
## (Dining room and Restroom cells, no furniture, no kitchen, no back door),
## through the same wall edges people use. All its choices come from one named
## RNG stream (GameState.rng(&"cat")), so a run replays exactly. Only the
## adoption and the name are saved; where it stands is not.

enum State {
	## Curled up asleep (the `nap` clip).
	NAPPING,
	## Standing still, looking about (the `idle` clip).
	STANDING,
	## Walking one step at a time (the `walk` clip).
	WALKING,
	## Being petted by a waiting guest: still and facing them (`idle`).
	PETTED,
}

const SAVE_VERSION: int = 1
const FALLBACK_SEED: int = 119
const _DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

var tuning: CatTuning
var adopted: bool = false
var cat_name: String = ""
## The cell the cat is in, or the one a step is heading for.
var cell: Vector2i = SimGrid.NO_CELL
## Where the current step began (equals `cell` when standing).
var from_cell: Vector2i = SimGrid.NO_CELL
var state: State = State.NAPPING
## Direction of the last step, or towards a guest being petted.
var heading: Vector2i = Vector2i(0, 1)
## Ticks into the current step and how many it takes (smooth drawing only).
var step_done: int = 0
var step_total: int = 1
## Whom the cat let pet it today, in order (for tests and the debug overlay).
var petted_by: Array[int] = []

var _rng: RandomNumberGenerator
var _bed: Vector2i = SimGrid.NO_CELL
var _path: Array[Vector2i] = []
var _timer: int = 0
var _on_arrival: State = State.STANDING
var _resume: State = State.STANDING
var _nap_cache_version: int = -1
var _nap_cache_grid: WeakRef = null
var _nap_cache: Array[Vector2i] = []
var _nap_is_sunny: bool = false


func _init(config: CatTuning = null, random: RandomNumberGenerator = null) -> void:
	tuning = config if config != null else CatTuning.new()
	cat_name = tuning.default_name
	if random == null:
		random = RandomNumberGenerator.new()
		random.seed = FALLBACK_SEED
	_rng = random


## The game session passes GameState.rng(&"cat"), so the stream is seeded per
## run and saved with it.
func use_rng(random: RandomNumberGenerator) -> void:
	if random != null:
		_rng = random


# --- Adoption and saving ------------------------------------------------------

## True while the morning offer should show (never twice: it is one-time).
func offered(owner_level: int, phase: int) -> bool:
	return not adopted and tuning.is_valid() and owner_level >= tuning.unlock_level \
		and phase == SimClock.Phase.MORNING


## One plain sentence for why adopting is not possible now, or "" if it is.
func refusal(owner_level: int, phase: int, cash: int) -> String:
	if not tuning.is_valid():
		return "Cats are not available"
	if adopted:
		return "You already have a cat"
	if owner_level < tuning.unlock_level:
		return "Unlocks at owner level %d" % tuning.unlock_level
	if phase != SimClock.Phase.MORNING:
		return "Adopt a cat in the morning"
	if cash < tuning.adoption_price:
		return "Not enough cash to adopt a cat"
	return ""


## Marks the cat adopted; the caller has already charged the price. Idempotent.
func adopt(grid: SimGrid) -> bool:
	if adopted:
		return false
	adopted = true
	begin_day(grid)
	return true


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "adopted": adopted, "name": cat_name}


## Validates fully before changing anything; false leaves the cat as it was.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if row.size() != 3 or not row.get("version") is int and not row.get("version") is float \
			or float(row.get("version", -1)) != float(SAVE_VERSION) or not row.get("adopted") is bool \
			or not row.get("name") is String:
		return false
	var saved_name: String = String(row["name"]).strip_edges()
	if saved_name.is_empty() or saved_name.length() > tuning.max_name_length:
		return false
	adopted = bool(row["adopted"])
	cat_name = saved_name
	clear_position()
	return true


## Forgets where the cat is (the next begin_day() puts it on its bed).
func clear_position() -> void:
	cell = SimGrid.NO_CELL
	from_cell = SimGrid.NO_CELL
	_bed = SimGrid.NO_CELL
	_path.clear()
	state = State.NAPPING
	step_done = 0
	step_total = 1
	_timer = 0


# --- The day -----------------------------------------------------------------

## The cell the cat sleeps on at the start of the day (NO_CELL before one is set).
func bed() -> Vector2i:
	return _bed


## Every morning the cat is asleep on its bed spot. Draws nothing from the RNG,
## so a game loaded in the morning replays the same day.
func begin_day(grid: SimGrid) -> void:
	petted_by.clear()
	if not adopted or grid == null:
		return
	clear_position()
	_bed = bed_spot(grid)
	if _bed == SimGrid.NO_CELL:
		return
	cell = _bed
	from_cell = _bed
	state = State.NAPPING
	_lie_along_wall(grid)
	_timer = tuning.morning_nap_ticks


## The layout changed (a build edit): a cat standing where furniture or a wall
## now is goes back to bed. The bed itself follows the new layout.
func layout_changed(grid: SimGrid) -> void:
	if not adopted or grid == null:
		return
	_nap_cache_version = -1
	_bed = bed_spot(grid)
	if cell == SimGrid.NO_CELL or not cell_ok(grid, cell):
		_path.clear()
		cell = _bed
		from_cell = _bed
		state = State.NAPPING
		if cell != SimGrid.NO_CELL:
			_lie_along_wall(grid)
		_timer = tuning.morning_nap_ticks
		step_done = 0
		step_total = 1


## One world tick while the shop is open. `guests` are the current visits.
func advance(grid: SimGrid, guests: Array[CustomerAgent]) -> void:
	if not adopted or grid == null:
		return
	if cell == SimGrid.NO_CELL or not cell_ok(grid, cell):
		layout_changed(grid)
		if cell == SimGrid.NO_CELL:
			return
	if state != State.PETTED and (state != State.WALKING or step_done >= step_total):
		if _try_petting(grid, guests):
			return
	match state:
		State.NAPPING, State.STANDING:
			_timer -= 1
			if _timer <= 0:
				_decide(grid)
		State.PETTED:
			_timer -= 1
			if _timer <= 0:
				state = _resume
				if state == State.WALKING and not _path.is_empty():
					_begin_step(grid)
				elif state == State.WALKING:
					_arrive(grid)
		State.WALKING:
			step_done += 1
			if step_done >= step_total:
				if _path.is_empty():
					_arrive(grid)
				else:
					_begin_step(grid)


# --- Charm ---------------------------------------------------------------------

## Is a guest standing here within charm range of the cat (so a little more patient)?
func charms(guest_cell: Vector2i) -> bool:
	return adopted and cell != SimGrid.NO_CELL and _chebyshev(guest_cell, cell) <= tuning.charm_radius


## Hands back one waiting tick now and then to a waiting guest in charm range.
## `carry` is the guest's fractional credit (kept on the guest); returns the new
## credit and whether one tick is refunded this time.
func relief(guest_cell: Vector2i, carry: float) -> Dictionary:
	if not charms(guest_cell):
		return {"carry": carry, "refund": 0}
	carry += tuning.refund_per_tick()
	if carry >= 1.0:
		return {"carry": carry - 1.0, "refund": 1}
	return {"carry": carry, "refund": 0}


func _try_petting(grid: SimGrid, guests: Array[CustomerAgent]) -> bool:
	for guest: CustomerAgent in guests:
		if guest.petted_cat or not guest.is_waiting_in_shop():
			continue
		if _chebyshev(guest.cell, cell) > tuning.pet_radius:
			continue
		guest.petted_cat = true
		petted_by.append(guest.id)
		var toward: Vector2i = guest.cell - cell
		if toward != Vector2i.ZERO:
			heading = Vector2i(signi(toward.x), signi(toward.y))
		_resume = State.WALKING if state == State.WALKING else State.STANDING
		state = State.PETTED
		_timer = maxi(1, tuning.pet_pause_ticks)
		return true
	return false


# --- Where the cat may stand --------------------------------------------------

## True for floor the cat may stand on: a guest could stand there, in the
## Dining room or the Restroom, with no furniture on it.
func cell_ok(grid: SimGrid, candidate: Vector2i) -> bool:
	if not grid.in_bounds(candidate) or grid.terrain(candidate) != SimGrid.Terrain.FLOOR:
		return false
	if not grid.is_guest_walkable(candidate):
		return false
	var room: SimGrid.Room = grid.room(candidate)
	if room != SimGrid.Room.DINING and room != SimGrid.Room.RESTROOM:
		return false
	return grid.item_on_layer(candidate, ItemDef.PlacementLayer.NORMAL) == null


func _steps(grid: SimGrid, from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for neighbour: Vector2i in grid.guest_neighbours(from):
		if cell_ok(grid, neighbour):
			out.append(neighbour)
	return out


## The cell the cat sleeps on at the start of each day: the first nap spot in
## reading order, or the first free cell when no nap spot exists.
func bed_spot(grid: SimGrid) -> Vector2i:
	var spots: Array[Vector2i] = nap_spots(grid)
	if not spots.is_empty():
		return spots[0]
	for candidate: Vector2i in _floor_cells(grid):
		return candidate
	return SimGrid.NO_CELL


## Cells next to a window (a sunny spot); with no window in the shop, cells
## next to a wall. In reading order (row, then column). Cached per layout.
func nap_spots(grid: SimGrid) -> Array[Vector2i]:
	var cached: SimGrid = _nap_cache_grid.get_ref() as SimGrid if _nap_cache_grid != null else null
	if cached == grid and _nap_cache_version == grid.version:
		return _nap_cache
	var floor_cells: Array[Vector2i] = _floor_cells(grid)
	var windows: Dictionary[Vector2i, bool] = {}
	for window_cell: Vector2i in ExteriorSupport.window_cells(grid):
		windows[window_cell] = true
	var doors: Dictionary[Vector2i, bool] = WallRules.door_cells(grid)
	var sunny: Array[Vector2i] = []
	var walled: Array[Vector2i] = []
	for candidate: Vector2i in floor_cells:
		if doors.has(candidate):
			continue
		var beside_window: bool = false
		var beside_wall: bool = false
		for step: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var next: Vector2i = candidate + step
			var kind: SimGrid.Segment = grid.segment(SimGrid.edge_between(candidate, next))
			if windows.has(next) or kind == SimGrid.Segment.WINDOW:
				beside_window = true
			elif kind == SimGrid.Segment.WALL or kind == SimGrid.Segment.STALL_PARTITION \
					or grid.terrain(next) == SimGrid.Terrain.WALL:
				beside_wall = true
		if beside_window:
			sunny.append(candidate)
		elif beside_wall:
			walled.append(candidate)
	_nap_is_sunny = not sunny.is_empty()
	_nap_cache = sunny if _nap_is_sunny else walled
	_nap_cache_grid = weakref(grid)
	_nap_cache_version = grid.version
	return _nap_cache


## True when the nap spots are by a window (otherwise they are by a wall).
func naps_in_sun(grid: SimGrid) -> bool:
	nap_spots(grid)
	return _nap_is_sunny


func _floor_cells(grid: SimGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for candidate: Vector2i in grid.cells():
		if cell_ok(grid, candidate):
			out.append(candidate)
	out.sort_custom(_reading_order)
	return out


static func _reading_order(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


# --- Choosing and walking -----------------------------------------------------

func _decide(grid: SimGrid) -> void:
	var reach: Dictionary = _reach(grid)
	var order: Array[Vector2i] = reach["order"]
	var parents: Dictionary = reach["parent"]
	var napping: bool = _rng.randf() < tuning.nap_chance
	var target: Vector2i = SimGrid.NO_CELL
	if napping:
		var spots: Array[Vector2i] = []
		for spot: Vector2i in nap_spots(grid):
			if spot == cell or parents.has(spot):
				spots.append(spot)
		if not spots.is_empty():
			target = spots[_rng.randi_range(0, spots.size() - 1)]
	elif not order.is_empty():
		target = order[_rng.randi_range(0, order.size() - 1)]
	if target == SimGrid.NO_CELL:
		_settle(grid, State.STANDING)
		return
	_on_arrival = State.NAPPING if napping else State.STANDING
	if target == cell:
		_settle(grid, _on_arrival)
		return
	_path = _route(parents, target)
	state = State.WALKING
	_begin_step(grid)


## Breadth-first search over cells the cat may use, at most `wander_range`
## steps away, in a fixed neighbour order (deterministic).
func _reach(grid: SimGrid) -> Dictionary:
	var parent: Dictionary[Vector2i, Vector2i] = {}
	var depth: Dictionary[Vector2i, int] = {cell: 0}
	var order: Array[Vector2i] = []
	var queue: Array[Vector2i] = [cell]
	var head: int = 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		if depth[here] >= tuning.wander_range:
			continue
		for next: Vector2i in _steps(grid, here):
			if depth.has(next):
				continue
			depth[next] = depth[here] + 1
			parent[next] = here
			queue.append(next)
			order.append(next)
	return {"parent": parent, "order": order}


func _route(parent: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var step: Vector2i = target
	while parent.has(step):
		reversed.append(step)
		step = parent[step]
	reversed.reverse()
	return reversed


func _begin_step(grid: SimGrid) -> void:
	var next: Vector2i = _path[0]
	var delta: Vector2i = next - cell
	if not cell_ok(grid, next) or absi(delta.x) > 1 or absi(delta.y) > 1 \
			or not grid.guest_neighbours(cell).has(next):
		# The way is gone (an edit or a wall): stop where it stands.
		_path.clear()
		_settle(grid, State.STANDING)
		return
	_path.remove_at(0)
	from_cell = cell
	cell = next
	heading = Vector2i(signi(delta.x), signi(delta.y))
	var diagonal: bool = delta.x != 0 and delta.y != 0
	step_total = tuning.step_ticks if not diagonal else roundi(tuning.step_ticks * GridMath.DIAGONAL_COST)
	step_done = 0
	state = State.WALKING


func _arrive(grid: SimGrid) -> void:
	_path.clear()
	_settle(grid, _on_arrival)


## Stops where it stands: a nap or a stand, for a drawn number of ticks.
func _settle(grid: SimGrid, next_state: State) -> void:
	from_cell = cell
	step_done = 0
	step_total = 1
	state = next_state
	if next_state == State.NAPPING:
		_lie_along_wall(grid)
		_timer = _rng.randi_range(tuning.nap_ticks_min, tuning.nap_ticks_max)
	else:
		_timer = _rng.randi_range(tuning.idle_ticks_min, tuning.idle_ticks_max)


## A napping cat lies along the wall or window it sleeps by, not into it.
func _lie_along_wall(grid: SimGrid) -> void:
	for step: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var next: Vector2i = cell + step
		if grid.terrain(next) == SimGrid.Terrain.WALL \
				or grid.segment(SimGrid.edge_between(cell, next)) != SimGrid.Segment.NONE:
			# Keep to the side the cat already faces when the wall allows it.
			var along: Vector2i = Vector2i(-step.y, step.x)
			heading = along if heading.x * along.x + heading.y * along.y >= 0 else -along
			return


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# --- Drawing (read-only) --------------------------------------------------------

## Where the cat is drawn, on the floor: between its last two cells while it
## walks. `alpha` is the world clock's fraction of the way to the next tick
## (the picture runs one tick behind, like the people).
func floor_position(alpha: float = 1.0) -> Vector3:
	if cell == SimGrid.NO_CELL:
		return Vector3.ZERO
	var to_world: Vector3 = GridMath.cell_to_world(cell)
	if state != State.WALKING:
		return to_world
	var progress: float = clampf((float(step_done) - 1.0 + clampf(alpha, 0.0, 1.0)) / float(maxi(step_total, 1)), 0.0, 1.0)
	return GridMath.cell_to_world(from_cell).lerp(to_world, progress)


## Yaw about the vertical axis so the cat faces its heading (the model faces -Z).
func yaw() -> float:
	return atan2(-float(heading.x), -float(heading.y))
