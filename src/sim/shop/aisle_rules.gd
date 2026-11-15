class_name AisleRules
extends RefCounted
## Aisle pinches (#389): a walkway people actually use that narrows to one
## cell, where two people cannot pass and must squeeze head-on. Build mode
## warns about them (never refuses, like all furniture, DESIGN 4.3).
##
## "Used" walkways are the routes the shop's work needs, traced the way the
## sim plans them (octile steps, a seat ends a walk but is never an aisle).
## Each kind of trip is one Family, a shortest-route tree from its starts:
## - the street door to every seat (guests) and to the pass;
## - the pass's dining side to every seat and to the restroom;
## - the pass's kitchen side to every kitchen station and store;
## - the restroom to every seat (guests going there and back, #391);
## - the sink to every seat (clearing tables, #391);
## - where deliveries are put down to every store (#391).
## A cell on one of these routes is a pinch when both of its sides across one
## axis are closed (a wall, an item, a seat, or a wall segment between them),
## or when it is open on all four sides and both of its corners across one
## diagonal are closed (#391): between two things standing corner to corner
## there is only that one cell to step through.
## Cells no route crosses are never flagged; a one-cell lane to a single seat
## is, since the guest and the server both walk it.
##
## Cost (#391). survey() does all of it for one layout. Build mode hovers a
## proposal over every cell, so resurvey() reuses the live layout's survey:
## a family whose starts and ends are the same, and whose traced routes the
## proposal does not come within a cell of, keeps its routes; only the others
## are traced again. The trees use a bucket queue over cell indexes instead of
## a binary heap over dictionaries, and share one table of legal steps.

const WARNING: String = "Tight squeeze: people can't pass each other here"
## For a squeeze the edit did not make: it only sends people through a gap
## the shop already had (#391).
const REROUTE_WARNING: String = "Tight squeeze: people now have to pass through here"

## Fixed-point step costs (10 per straight step, 14 per diagonal) keep the
## route tree's ties deterministic.
const _STRAIGHT: int = 10
const _DIAGONAL: int = 14
## One bucket per cost in a window wider than the dearest step, so each
## bucket only ever holds entries of one cost.
const _BUCKETS: int = 15
const _SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
## Corner pairs across each diagonal: NW with SE, NE with SW.
const _CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1)]
const _AROUND: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1),
	Vector2i(-1, 0), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]


## One kind of trip: where it starts, where it ends and who walks it, with
## the routes traced for it.
class Family extends RefCounted:
	var sources: Array[Vector2i] = []
	var targets: Array[Vector2i] = []
	var guest: bool = false
	## Route cells, ends left out (the door, the pass, the seat or station
	## itself, and a seat's own doorstep).
	var cells: Dictionary[Vector2i, bool] = {}
	## Every cell the traced routes stand on or end at. A proposal that stays
	## more than one cell away from all of them cannot change these routes.
	var footing: Dictionary[Vector2i, bool] = {}
	## The route cells that are pinches.
	var pinches: Array[Vector2i] = []


## The legal steps of one layout, worked out once per cell and shared by
## every tree: neighbour cell indexes in the grid's own neighbour order.
class Net extends RefCounted:
	var origin: Vector2i = Vector2i.ZERO
	var width: int = 0
	var height: int = 0
	var seats: Dictionary[Vector2i, bool] = {}
	var staff: Array[PackedInt32Array] = []
	var guest: Array[PackedInt32Array] = []
	var staff_known: PackedByteArray = PackedByteArray()
	var guest_known: PackedByteArray = PackedByteArray()


## Everything the pinch pass knows about one layout.
class Survey extends RefCounted:
	var families: Array[Family] = []
	var route_cells: Dictionary[Vector2i, bool] = {}
	var pinches: Array[Vector2i] = []
	var net: Net = null
	## How many families were traced for this survey (the rest were reused).
	var traced: int = 0


## The cells of every used route, endpoints (the door, the pass and the
## seat or station itself) left out.
static func route_cells(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	return survey(grid).route_cells


## Pinch cells on the used routes, sorted (row, then column).
static func pinches(grid: SimGrid) -> Array[Vector2i]:
	return survey(grid).pinches


## Pinches `after` has that `before` did not: what an edit newly squeezes.
## Older layouts never gain a warning for a squeeze they already had.
static func new_pinches(before: SimGrid, after: SimGrid) -> Array[Vector2i]:
	return new_pinches_from(pinches(before), after)


## new_pinches() with the pinches of the layout before already known.
static func new_pinches_from(had: Array[Vector2i], after: SimGrid) -> Array[Vector2i]:
	return _added(had, pinches(after))


## The routes and pinches of one layout, every family traced.
static func survey(grid: SimGrid) -> Survey:
	var result: Survey = Survey.new()
	if grid == null:
		return result
	result.net = _net(grid, _seats(grid))
	result.families = _families(grid)
	for family: Family in result.families:
		_trace(grid, result.net, family)
		result.traced += 1
	_finish(result)
	return result


## survey(after), reusing `live` (the survey of the layout the edit starts
## from) wherever the edit cannot have changed it. `changed` lists every cell
## whose furniture differs between the two layouts (footprint, seat and work
## cells of what was added, moved or removed). `opened` says some cell became
## walkable or stopped being a seat: a new way through can shorten any route,
## so then everything is traced again.
static func resurvey(live: Survey, after: SimGrid, changed: Array[Vector2i], opened: bool) -> Survey:
	if live == null or live.net == null or after == null or opened \
			or live.net.origin != after.bounds.position or live.net.width != after.bounds.size.x \
			or live.net.height != after.bounds.size.y:
		return survey(after)
	var result: Survey = Survey.new()
	var seats: Dictionary[Vector2i, bool] = _seats(after)
	result.net = _patched(live.net, seats, changed)
	result.families = _families(after)
	if result.families.size() != live.families.size():
		return survey(after)
	var near: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in changed:
		for offset: Vector2i in _AROUND:
			near[cell + offset] = true
	for index: int in result.families.size():
		var family: Family = result.families[index]
		var known: Family = live.families[index]
		if family.guest == known.guest and family.sources == known.sources and family.targets == known.targets \
				and not _touches(known.footing, near):
			family.cells = known.cells
			family.footing = known.footing
			family.pinches = known.pinches
		else:
			_trace(after, result.net, family)
			result.traced += 1
	_finish(result)
	return result


## Pinches of `after` that `had` did not list.
static func added_pinches(had: Array[Vector2i], after: Survey) -> Array[Vector2i]:
	return _added(had, after.pinches)


## Of `cells` (new pinches after an edit), the ones the edit closed nothing
## beside: none of `changed` is one of the cells that make it a pinch. Those
## were one-cell gaps already; the edit only sends people through them.
static func rerouted(after: SimGrid, cells: Array[Vector2i], changed: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in cells:
		var beside: bool = false
		for other: Vector2i in changed:
			if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) == 1:
				beside = true
				break
		if not beside:
			out.append(cell)
	return out


## A floor cell whose two sides across one axis are both closed; or one open
## on all four sides whose two corners across one diagonal are closed (#391):
## two things standing corner to corner, with this cell the only one to step
## through between them (the corner rule forbids cutting past either).
## Doorways and back doors are narrow on purpose and never count.
static func is_pinch(grid: SimGrid, cell: Vector2i, seats: Dictionary[Vector2i, bool]) -> bool:
	if grid.terrain(cell) != SimGrid.Terrain.FLOOR or grid.is_back_door(cell) or seats.has(cell):
		return false
	var closed: Array[bool] = []
	for side: Vector2i in _SIDES:
		var next: Vector2i = cell + side
		closed.append(not grid.is_walkable(next) or seats.has(next) or not grid.step_open(cell, next))
	if (closed[0] and closed[1]) or (closed[2] and closed[3]):
		return true
	if closed[0] or closed[1] or closed[2] or closed[3]:
		return false
	var corners: Array[bool] = []
	for corner: Vector2i in _CORNERS:
		var next: Vector2i = cell + corner
		corners.append(not grid.is_walkable(next) or seats.has(next))
	return (corners[0] and corners[1]) or (corners[2] and corners[3])


static func _added(had: Array[Vector2i], now: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in now:
		if not had.has(cell):
			out.append(cell)
	return out


static func _touches(footing: Dictionary[Vector2i, bool], near: Dictionary[Vector2i, bool]) -> bool:
	if footing.size() < near.size():
		for cell: Vector2i in footing:
			if near.has(cell):
				return true
		return false
	for cell: Vector2i in near:
		if footing.has(cell):
			return true
	return false


static func _finish(result: Survey) -> void:
	for family: Family in result.families:
		result.route_cells.merge(family.cells)
		for cell: Vector2i in family.pinches:
			if not result.pinches.has(cell):
				result.pinches.append(cell)
	result.pinches.sort_custom(_before)


static func _seats(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for placed: PlacedItem in grid.items():
		if placed.removed:
			continue
		for cell: Vector2i in placed.seat_cells:
			out[cell] = true
	return out


## The kinds of trip this layout has, always in the same order (a family
## with no start or no end stays in the list, empty).
static func _families(grid: SimGrid) -> Array[Family]:
	var dining: Array[Vector2i] = []
	var stations: Array[Vector2i] = []
	var stores: Array[Vector2i] = []
	var sinks: Array[Vector2i] = []
	var restrooms: Array[Vector2i] = []
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
				if definition.category == ItemDef.Category.STORAGE:
					stores.append_array(placed.work_cells)
				elif definition.station_type == &"sink":
					sinks.append_array(placed.work_cells)
			ItemDef.Category.PASS:
				if placed.work_cells.size() >= 2:
					pass_kitchen.append(placed.work_cells[0])
					pass_dining.append(placed.work_cells[1])
			ItemDef.Category.RESTROOM:
				restrooms.append_array(placed.work_cells)
	var door: Array[Vector2i] = grid.entries()
	return [_family(door, dining, true), _family(door, pass_dining, false),
		_family(pass_dining, dining, false), _family(pass_kitchen, stations, false),
		_family(restrooms, dining, true), _family(pass_dining, restrooms, false),
		_family(sinks, dining, false), _family(_receiving(grid), stores, false)]


static func _family(sources: Array[Vector2i], targets: Array[Vector2i], guest: bool) -> Family:
	var family: Family = Family.new()
	family.sources = sources
	family.targets = targets
	family.guest = guest
	return family


## Where deliveries are put down: the floor cell inside each back door, or
## inside the street door when the shop has no back door (WallRules.
## delivery_route picks one of these; any of them may be the one in use).
static func _receiving(grid: SimGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) != SimGrid.Segment.DOORWAY:
			continue
		var ends: Array[Vector2i] = SimGrid.edge_cells(edge)
		for index: int in ends.size():
			var inside: Vector2i = ends[index]
			var door: Vector2i = ends[ends.size() - 1 - index]
			if grid.is_back_door(door) and grid.terrain(inside) == SimGrid.Terrain.FLOOR \
					and grid.is_walkable(inside) and not out.has(inside):
				out.append(inside)
	if not out.is_empty():
		return out
	for entry: Vector2i in grid.entries():
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var inside: Vector2i = entry + step
			if grid.terrain(inside) == SimGrid.Terrain.FLOOR and grid.is_walkable(inside) \
					and grid.step_open(entry, inside) and not out.has(inside):
				out.append(inside)
	return out


static func _net(grid: SimGrid, seats: Dictionary[Vector2i, bool]) -> Net:
	var net: Net = Net.new()
	net.origin = grid.bounds.position
	net.width = grid.bounds.size.x
	net.height = grid.bounds.size.y
	net.seats = seats
	var count: int = net.width * net.height
	net.staff.resize(count)
	net.guest.resize(count)
	net.staff_known.resize(count)
	net.guest_known.resize(count)
	return net


## `live` for a layout that differs only around `changed`: every cell further
## than one step from a changed cell keeps the steps already worked out.
static func _patched(live: Net, seats: Dictionary[Vector2i, bool], changed: Array[Vector2i]) -> Net:
	var net: Net = Net.new()
	net.origin = live.origin
	net.width = live.width
	net.height = live.height
	net.seats = seats
	net.staff = live.staff.duplicate()
	net.guest = live.guest.duplicate()
	net.staff_known = live.staff_known.duplicate()
	net.guest_known = live.guest_known.duplicate()
	for cell: Vector2i in changed:
		for offset: Vector2i in _AROUND:
			var index: int = _index(net, cell + offset)
			if index >= 0:
				net.staff_known[index] = 0
				net.guest_known[index] = 0
	return net


static func _index(net: Net, cell: Vector2i) -> int:
	var x: int = cell.x - net.origin.x
	var y: int = cell.y - net.origin.y
	if x < 0 or y < 0 or x >= net.width or y >= net.height:
		return -1
	return y * net.width + x


static func _cell(net: Net, index: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(net.origin.x + index % net.width, net.origin.y + index / net.width)


## The cells a person standing on `index` may step to (seats never entered).
static func _steps(grid: SimGrid, net: Net, index: int, guest: bool) -> PackedInt32Array:
	if guest:
		if net.guest_known[index] != 0:
			return net.guest[index]
	elif net.staff_known[index] != 0:
		return net.staff[index]
	var cell: Vector2i = _cell(net, index)
	var out: PackedInt32Array = PackedInt32Array()
	for next: Vector2i in grid.walkable_neighbours(cell):
		if not grid.actor_step(cell, next, net.seats, guest) or (guest and not grid.is_guest_walkable(next)):
			continue
		out.append(_index(net, next))
	if guest:
		net.guest[index] = out
		net.guest_known[index] = 1
	else:
		net.staff[index] = out
		net.staff_known[index] = 1
	return out


## One shortest-route tree from all of the family's starts at once, then each
## end's route traced back. A seat is stepped onto at the end.
static func _trace(grid: SimGrid, net: Net, family: Family) -> void:
	family.cells = {}
	family.footing = {}
	family.pinches = []
	if family.sources.is_empty() or family.targets.is_empty():
		return
	var count: int = net.width * net.height
	var costs: PackedInt32Array = PackedInt32Array()
	costs.resize(count)
	costs.fill(-1)
	var previous: PackedInt32Array = PackedInt32Array()
	previous.resize(count)
	previous.fill(-1)
	_tree(grid, net, family, costs, previous)
	var starts: Dictionary[int, bool] = {}
	for source: Vector2i in family.sources:
		var at: int = _index(net, source)
		if at >= 0:
			starts[at] = true
			family.footing[source] = true
	for target: Vector2i in family.targets:
		family.footing[target] = true
		var end: int = _index(net, target)
		var last: int = end
		if end < 0 or costs[end] < 0:
			last = _approach(grid, net, target, costs, family.guest)
			if last < 0:
				continue
		elif starts.has(end):
			continue
		family.footing[_cell(net, last)] = true
		if starts.has(last):
			continue
		# A seat's own doorstep is where its guest sits down, not a walkway
		# (a corner seat's one-cell approach is fine), so tracing starts
		# one step back from it.
		var at: int = previous[last]
		while at >= 0 and not starts.has(at):
			var cell: Vector2i = _cell(net, at)
			if not family.cells.has(cell):
				family.cells[cell] = true
				family.footing[cell] = true
				if is_pinch(grid, cell, net.seats):
					family.pinches.append(cell)
			at = previous[at]


## The reached neighbour a route steps onto `target` from (a seat, which the
## tree never enters), or -1.
static func _approach(grid: SimGrid, net: Net, target: Vector2i, costs: PackedInt32Array, guest: bool) -> int:
	if not grid.is_walkable(target):
		return -1
	var best: int = -1
	var best_cost: int = 0
	var open: Dictionary[Vector2i, bool] = net.seats.duplicate()
	open.erase(target)
	for next: Vector2i in grid.walkable_neighbours(target):
		var at: int = _index(net, next)
		if at < 0 or costs[at] < 0 or not grid.actor_step(next, target, open, guest) \
				or (guest and not grid.is_guest_walkable(target)):
			continue
		var cost: int = costs[at] + _step_cost(next, target)
		if best < 0 or cost < best_cost:
			best = at
			best_cost = cost
	return best


## Dijkstra over walkable cells (seats never entered). The queue is a ring of
## buckets, one per cost: entries of equal cost leave in the order they went
## in, exactly as the binary heap this replaces ordered them (cost, then
## push order), so the trees are the same ones, several times faster.
static func _tree(grid: SimGrid, net: Net, family: Family, costs: PackedInt32Array,
		previous: PackedInt32Array) -> void:
	var buckets: Array[PackedInt32Array] = []
	for _slot: int in _BUCKETS:
		buckets.append(PackedInt32Array())
	var waiting: int = 0
	for source: Vector2i in family.sources:
		var at: int = _index(net, source)
		if at >= 0 and grid.is_walkable(source) and costs[at] < 0:
			costs[at] = 0
			buckets[0].append(at)
			waiting += 1
	var done: PackedByteArray = PackedByteArray()
	done.resize(costs.size())
	var width: int = net.width
	var cost: int = 0
	while waiting > 0:
		var slot: int = cost % _BUCKETS
		var bucket: PackedInt32Array = buckets[slot]
		if bucket.is_empty():
			cost += 1
			continue
		# Nothing joins this bucket while it drains: every step costs at
		# least _STRAIGHT, which lands in another slot.
		buckets[slot] = PackedInt32Array()
		waiting -= bucket.size()
		for current: int in bucket:
			if done[current] != 0 or costs[current] != cost:
				continue
			done[current] = 1
			for next: int in _steps(grid, net, current, family.guest):
				if done[next] != 0:
					continue
				var delta: int = absi(next - current)
				var reached: int = cost + (_STRAIGHT if delta == 1 or delta == width else _DIAGONAL)
				if costs[next] >= 0 and costs[next] <= reached:
					continue
				costs[next] = reached
				previous[next] = current
				buckets[reached % _BUCKETS].append(next)
				waiting += 1
		cost += 1


static func _step_cost(a: Vector2i, b: Vector2i) -> int:
	return _STRAIGHT if a.x == b.x or a.y == b.y else _DIAGONAL


static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
