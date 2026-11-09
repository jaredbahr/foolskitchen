class_name AisleRules
extends RefCounted
## Aisle pinches (#389): a walkway people actually use that narrows to one
## cell, where two people cannot pass and must squeeze head-on. Build mode
## warns about them (never refuses, like all furniture, DESIGN 4.3).
##
## "Used" walkways are the routes the shop's work needs, traced the way the
## sim plans them (octile steps, a seat ends a walk but is never an aisle):
## the street door to every seat and to the pass, the pass's dining side to
## every seat, and the pass's kitchen side to every kitchen station. A cell on
## one of these routes is a pinch when both of its sides across one axis are
## closed (a wall, an item, a seat, or a wall segment between them). Dead ends
## and corners no route crosses are never flagged.

const WARNING: String = "Tight squeeze: people can't pass each other here"

## Fixed-point step costs (10 per straight step, 14 per diagonal) keep the
## route tree's ties deterministic.
const _STRAIGHT: int = 10
const _DIAGONAL: int = 14
const _SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## The cells of every used route, endpoints (the door, the pass and the
## seat or station itself) left out.
static func route_cells(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	if grid == null:
		return out
	var seats: Dictionary[Vector2i, bool] = _seats(grid)
	var dining: Array[Vector2i] = []
	var stations: Array[Vector2i] = []
	var pass_dining: Array[Vector2i] = []
	var pass_kitchen: Array[Vector2i] = []
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or placed.removed:
			continue
		match definition.category:
			ItemDef.Category.TABLE, ItemDef.Category.CHAIR:
				for cell: Vector2i in placed.seat_cells:
					if not dining.has(cell):
						dining.append(cell)
			ItemDef.Category.STATION, ItemDef.Category.STORAGE:
				stations.append_array(placed.work_cells)
			ItemDef.Category.PASS:
				if placed.work_cells.size() >= 2:
					pass_kitchen.append(placed.work_cells[0])
					pass_dining.append(placed.work_cells[1])
	var door: Array[Vector2i] = grid.entries()
	_add_routes(grid, door, dining, seats, true, out)
	_add_routes(grid, door, pass_dining, seats, false, out)
	_add_routes(grid, pass_dining, dining, seats, false, out)
	_add_routes(grid, pass_kitchen, stations, seats, false, out)
	return out


## Pinch cells on the used routes, sorted (row, then column).
static func pinches(grid: SimGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid == null:
		return out
	var seats: Dictionary[Vector2i, bool] = _seats(grid)
	for cell: Vector2i in route_cells(grid):
		if is_pinch(grid, cell, seats):
			out.append(cell)
	out.sort_custom(_before)
	return out


## Pinches `after` has that `before` did not: what an edit newly squeezes.
## Older layouts never gain a warning for a squeeze they already had.
static func new_pinches(before: SimGrid, after: SimGrid) -> Array[Vector2i]:
	return new_pinches_from(pinches(before), after)


## new_pinches() with the pinches of the layout before already known.
static func new_pinches_from(had: Array[Vector2i], after: SimGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in pinches(after):
		if not had.has(cell):
			out.append(cell)
	return out


## A floor cell whose two sides across one axis are both closed. Doorways
## and back doors are narrow on purpose and never count.
static func is_pinch(grid: SimGrid, cell: Vector2i, seats: Dictionary[Vector2i, bool]) -> bool:
	if grid.terrain(cell) != SimGrid.Terrain.FLOOR or grid.is_back_door(cell) or seats.has(cell):
		return false
	var closed: Array[bool] = []
	for side: Vector2i in _SIDES:
		var next: Vector2i = cell + side
		closed.append(not grid.is_walkable(next) or seats.has(next) or not grid.step_open(cell, next))
	return (closed[0] and closed[1]) or (closed[2] and closed[3])


static func _seats(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for placed: PlacedItem in grid.items():
		if placed.removed:
			continue
		for cell: Vector2i in placed.seat_cells:
			out[cell] = true
	return out


## One shortest-route tree from all `sources` at once, then each target's
## route traced back into `out`. A seat target is stepped onto at the end.
static func _add_routes(grid: SimGrid, sources: Array[Vector2i], targets: Array[Vector2i],
		seats: Dictionary[Vector2i, bool], guest: bool, out: Dictionary[Vector2i, bool]) -> void:
	if sources.is_empty() or targets.is_empty():
		return
	var tree: Dictionary = _tree(grid, sources, seats, guest)
	var costs: Dictionary = tree["costs"]
	var previous: Dictionary = tree["previous"]
	for target: Vector2i in targets:
		var last: Vector2i = target
		if not costs.has(target):
			last = _approach(grid, target, costs, seats, guest)
			if last == SimGrid.NO_CELL:
				continue
		elif sources.has(target):
			continue
		if sources.has(last):
			continue
		# A seat's own doorstep is where its guest sits down, not a walkway
		# (a corner seat's one-cell approach is fine), so tracing starts
		# one step back from it.
		var cell: Vector2i = previous.get(last, SimGrid.NO_CELL)
		while cell != SimGrid.NO_CELL and not sources.has(cell):
			out[cell] = true
			cell = previous.get(cell, SimGrid.NO_CELL)


## The reached neighbour a route steps onto `target` from (a seat, which the
## tree never enters), or NO_CELL.
static func _approach(grid: SimGrid, target: Vector2i, costs: Dictionary,
		seats: Dictionary[Vector2i, bool], guest: bool) -> Vector2i:
	if not grid.is_walkable(target):
		return SimGrid.NO_CELL
	var best: Vector2i = SimGrid.NO_CELL
	var best_cost: int = 0
	var open: Dictionary[Vector2i, bool] = seats.duplicate()
	open.erase(target)
	for next: Vector2i in grid.walkable_neighbours(target):
		if not costs.has(next) or not grid.actor_step(next, target, open, guest) \
				or (guest and not grid.is_guest_walkable(target)):
			continue
		var cost: int = int(costs[next]) + _step_cost(next, target)
		if best == SimGrid.NO_CELL or cost < best_cost:
			best = next
			best_cost = cost
	return best


## Dijkstra over walkable cells (seats never entered) with a small binary heap.
static func _tree(grid: SimGrid, sources: Array[Vector2i], seats: Dictionary[Vector2i, bool],
		guest: bool) -> Dictionary:
	var costs: Dictionary[Vector2i, int] = {}
	var previous: Dictionary[Vector2i, Vector2i] = {}
	var heap_cost: Array[int] = []
	var heap_order: Array[int] = []
	var heap_cell: Array[Vector2i] = []
	var order: int = 0
	for source: Vector2i in sources:
		if grid.is_walkable(source) and not costs.has(source):
			costs[source] = 0
			_push(heap_cost, heap_order, heap_cell, 0, order, source)
			order += 1
	var done: Dictionary[Vector2i, bool] = {}
	while not heap_cell.is_empty():
		var top: Array = _pop(heap_cost, heap_order, heap_cell)
		var current: Vector2i = top[1]
		if done.has(current) or int(top[0]) > costs[current]:
			continue
		done[current] = true
		for next: Vector2i in grid.walkable_neighbours(current):
			if done.has(next) or not grid.actor_step(current, next, seats, guest) \
					or (guest and not grid.is_guest_walkable(next)):
				continue
			var cost: int = costs[current] + _step_cost(current, next)
			if costs.has(next) and costs[next] <= cost:
				continue
			costs[next] = cost
			previous[next] = current
			_push(heap_cost, heap_order, heap_cell, cost, order, next)
			order += 1
	return {"costs": costs, "previous": previous}


static func _step_cost(a: Vector2i, b: Vector2i) -> int:
	return _STRAIGHT if a.x == b.x or a.y == b.y else _DIAGONAL


static func _less(heap_cost: Array[int], heap_order: Array[int], a: int, b: int) -> bool:
	return heap_cost[a] < heap_cost[b] or (heap_cost[a] == heap_cost[b] and heap_order[a] < heap_order[b])


static func _swap(heap_cost: Array[int], heap_order: Array[int], heap_cell: Array[Vector2i], a: int, b: int) -> void:
	var cost: int = heap_cost[a]
	heap_cost[a] = heap_cost[b]
	heap_cost[b] = cost
	var rank: int = heap_order[a]
	heap_order[a] = heap_order[b]
	heap_order[b] = rank
	var cell: Vector2i = heap_cell[a]
	heap_cell[a] = heap_cell[b]
	heap_cell[b] = cell


static func _push(heap_cost: Array[int], heap_order: Array[int], heap_cell: Array[Vector2i],
		cost: int, rank: int, cell: Vector2i) -> void:
	heap_cost.append(cost)
	heap_order.append(rank)
	heap_cell.append(cell)
	var index: int = heap_cell.size() - 1
	while index > 0:
		var parent: int = (index - 1) >> 1
		if not _less(heap_cost, heap_order, index, parent):
			break
		_swap(heap_cost, heap_order, heap_cell, index, parent)
		index = parent


## [cost, cell] of the cheapest entry, removed from the heap.
static func _pop(heap_cost: Array[int], heap_order: Array[int], heap_cell: Array[Vector2i]) -> Array:
	var top: Array = [heap_cost[0], heap_cell[0]]
	var last: int = heap_cell.size() - 1
	_swap(heap_cost, heap_order, heap_cell, 0, last)
	heap_cost.pop_back()
	heap_order.pop_back()
	heap_cell.pop_back()
	var index: int = 0
	while true:
		var left: int = index * 2 + 1
		var right: int = left + 1
		var smallest: int = index
		if left < heap_cell.size() and _less(heap_cost, heap_order, left, smallest):
			smallest = left
		if right < heap_cell.size() and _less(heap_cost, heap_order, right, smallest):
			smallest = right
		if smallest == index:
			break
		_swap(heap_cost, heap_order, heap_cell, index, smallest)
		index = smallest
	return top


static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
