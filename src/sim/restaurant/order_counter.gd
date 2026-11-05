class_name OrderCounter
extends RefCounted
## The café order counter (#293). Guests who came for a drink or a coffee queue
## in front of it, order and pay at its till, then take a free table or leave
## with a takeaway. It reuses the bar counter's cell projection: the first seat
## cell is the guest's ORDER cell, the other seat cells are PICKUP cells (a
## takeaway is handed across from the staff side), and the work cell is the
## staff side where a server stands. Nothing here draws a random number or
## keeps state: a shop without a counter never reaches this code.

const STATION: StringName = &"order_counter"
## How many cells of floor the line runs along behind the order cell. A short
## queue keeps one clear cell between guests (LINE_SPACING), so it reads as
## people waiting rather than a crowd; once it outgrows those places everyone
## packs close, one per cell.
const LINE_LENGTH: int = 6
const LINE_SPACING: int = 2
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func is_counter(item: PlacedItem) -> bool:
	return item != null and not item.removed and item.def is ItemDef \
		and (item.def as ItemDef).station_type == STATION


## Placed order counters, in the grid's id order.
static func counters(grid: SimGrid) -> Array[PlacedItem]:
	var found: Array[PlacedItem] = []
	for item: PlacedItem in grid.items():
		if is_counter(item):
			found.append(item)
	return found


static func exists(grid: SimGrid) -> bool:
	for item: PlacedItem in grid.items():
		if is_counter(item):
			return true
	return false


## Where a guest stands to order, or NO_CELL.
static func order_cell(item: PlacedItem) -> Vector2i:
	return item.seat_cells[0] if is_counter(item) and not item.seat_cells.is_empty() else SimGrid.NO_CELL


## Where a takeaway guest waits for the drink to be handed across.
static func pickup_cells(item: PlacedItem) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if is_counter(item):
		cells.assign(item.seat_cells.slice(1))
	return cells


## The direction pointing away from the counter at a guest-side cell, or ZERO.
static func outward(item: PlacedItem, cell: Vector2i) -> Vector2i:
	for direction: Vector2i in DIRECTIONS:
		if item.cells.has(cell - direction):
			return direction
	return Vector2i.ZERO


## A cell a queueing guest may stand on: clear floor in the dining room, never
## a seat, a staff work cell or the front door lane.
static func standable(world: SimWorld, cell: Vector2i) -> bool:
	if not world.grid.in_bounds(cell) or world.grid.terrain(cell) != SimGrid.Terrain.FLOOR \
			or world.grid.room(cell) != SimGrid.Room.DINING or not world.grid.is_guest_walkable(cell) \
			or not world.movement.standing_cell(world, cell) or world.movement.in_door_lane(world, cell):
		return false
	for item: PlacedItem in world.grid.items():
		if item.work_cells.has(cell):
			return false
	return true


## The line behind the order cell, nearest first: straight out from the counter
## while the floor is clear, then bending along the wall (towards the street door
## first) when it ends, a guest every `spacing` cells. It stops at a dead end or
## a cell that cannot hold a guest; guests beyond it use the door-side wait.
static func line_cells(world: SimWorld, item: PlacedItem, spacing: int = LINE_SPACING) -> Array[Vector2i]:
	# Cached per layout: every queued guest asks every tick.
	var key: String = "%d:%d:%d" % [world.grid.version, item.id, spacing]
	var cache: Dictionary = world.grid.get_meta(&"order_counter_lines", {})
	if cache.get(&"key_prefix", "") != str(world.grid.version):
		cache = {&"key_prefix": str(world.grid.version)}
	if cache.has(key):
		return (cache[key] as Array[Vector2i]).duplicate()
	var computed: Array[Vector2i] = _compute_line(world, item, spacing)
	cache[key] = computed
	world.grid.set_meta(&"order_counter_lines", cache)
	return computed.duplicate()


static func _compute_line(world: SimWorld, item: PlacedItem, spacing: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var front: Vector2i = order_cell(item)
	var away: Vector2i = outward(item, front)
	if front == SimGrid.NO_CELL or away == Vector2i.ZERO:
		return cells
	var cursor: Vector2i = front
	var heading: Vector2i = away
	var path: Array[Vector2i] = []
	while path.size() < LINE_LENGTH:
		var next: Vector2i = cursor + heading
		if not standable(world, next) or path.has(next):
			heading = _turn(world, cursor, heading, path)
			if heading == Vector2i.ZERO:
				break
			next = cursor + heading
		path.append(next)
		cursor = next
	for index: int in range(0, path.size(), spacing):
		cells.append(path[index])
	# A queue must never wall off a one-cell aisle to a seat, a work cell or the pass.
	while not cells.is_empty() and _cuts_off(world, cells):
		cells.pop_back()
	return cells


## True when standing guests on `cells` would leave some seat or work cell that
## the street can reach today unreachable.
static func _cuts_off(world: SimWorld, cells: Array[Vector2i]) -> bool:
	var blocked: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		blocked[cell] = true
	for entry: Vector2i in world.grid.entries():
		var open: Dictionary[Vector2i, bool] = world.grid.reachable_avoiding(entry, {})
		if open.is_empty():
			continue
		var after: Dictionary[Vector2i, bool] = world.grid.reachable_avoiding(entry, blocked)
		for item: PlacedItem in world.grid.items():
			for target: Vector2i in item.seat_cells + item.work_cells:
				if open.has(target) and not after.has(target) and not blocked.has(target):
					return true
	return false


## The cells the queue stands on right now: spaced out while it is short, packed
## close once more guests are waiting than the spaced line holds.
static func queue_cells(world: SimWorld, item: PlacedItem, waiting: int) -> Array[Vector2i]:
	var spaced: Array[Vector2i] = line_cells(world, item)
	return spaced if waiting <= spaced.size() else line_cells(world, item, 1)


## A side step for a line that ran out: the clear side nearest the street door,
## never back on itself. ZERO when both sides are blocked.
static func _turn(world: SimWorld, cursor: Vector2i, heading: Vector2i, used: Array[Vector2i]) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_distance: float = INF
	for side: Vector2i in [Vector2i(heading.y, heading.x), Vector2i(-heading.y, -heading.x)]:
		var cell: Vector2i = cursor + side
		if not standable(world, cell) or used.has(cell):
			continue
		var distance: float = INF
		for entry: Vector2i in world.grid.entries():
			distance = minf(distance, GridMath.octile(entry, cell))
		if distance < best_distance:
			best_distance = distance
			best = side
	return best


## The counter the queue forms behind: the first usable one (a clear staff side,
## the order cell walkable), cached for the tick. Null when none.
static func line_counter(sim: RestaurantSim) -> PlacedItem:
	var cached: Array = sim.world.get_meta(&"order_counter_first", [])
	if cached.size() == 2 and cached[0] == sim.world.now and cached[1] is PlacedItem \
			and not (cached[1] as PlacedItem).removed:
		return cached[1] as PlacedItem
	var found: PlacedItem = null
	for item: PlacedItem in counters(sim.world.grid):
		if usable(sim, item, SimGrid.NO_CELL):
			found = item
			break
	sim.world.set_meta(&"order_counter_first", [sim.world.now, found])
	return found


## A counter guests can use now: a server can stand behind its order cell and
## the guest can walk to that cell from `from_cell`.
static func usable(sim: RestaurantSim, item: PlacedItem, from_cell: Vector2i) -> bool:
	var front: Vector2i = order_cell(item)
	if front == SimGrid.NO_CELL or not sim.world.grid.is_walkable(front) \
			or sim.across_cell(item.id, front) == SimGrid.NO_CELL:
		return false
	return from_cell == SimGrid.NO_CELL or sim.world.grid.is_guest_reachable(from_cell, front)


## Counters usable from `from_cell`, in id order.
static func usable_counters(sim: RestaurantSim, from_cell: Vector2i) -> Array[PlacedItem]:
	var found: Array[PlacedItem] = []
	for item: PlacedItem in counters(sim.world.grid):
		if usable(sim, item, from_cell):
			found.append(item)
	return found


## The first pickup cell on `item` that is free, walkable, reachable by the
## guest and has a clear staff cell behind it; NO_CELL when there is none.
## With `ignore_holds` a cell another guest holds still counts (is there a spot at all?).
static func free_pickup(sim: RestaurantSim, item: PlacedItem, guest: CustomerAgent,
		ignore_holds: bool = false) -> Vector2i:
	for cell: Vector2i in pickup_cells(item):
		if (ignore_holds or item.reserved_by(cell) == -1) and sim.world.grid.is_walkable(cell) \
				and sim.across_cell(item.id, cell) != SimGrid.NO_CELL \
				and sim.world.grid.is_guest_reachable(guest.cell, cell):
			return cell
	return SimGrid.NO_CELL
