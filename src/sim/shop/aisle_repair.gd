class_name AisleRepair
extends RefCounted
## Older shops whose staff can't reach the kitchen (#320). Nobody walks
## through a seat (#306/#314), so on the original starter layout, whose middle
## row is all tables and seats, servers had no way to the pass. On load, a shop
## saved before this repair existed (shop snapshot version 9 or older) moves
## only the blocking tables and chairs until everyone can walk, as people do,
## to everything they could reach by walking across seats: the door, the pass,
## the stations, the seats and the toilets. Each item keeps its look (variant
## and colour) and its place in the placement order. The search is fixed (no
## RNG): fewest moves first, then the shortest moves. When no repair is
## found the shop is left exactly as it was.

const NOTE: String = "We moved a few tables so your staff can reach the kitchen."
## How far (cells, each axis) a table or chair may move from where it stood.
const RADIUS: int = 6
## The most items one repair moves before it gives up.
const MAX_MOVES: int = 6
## The original starter layout's three tables, as saves before #320 hold
## them: [origin, quarter turns] in placement order. The repair turns the west
## one where it stands (the shortest fix: one aisle by the pass, every seat
## kept), and data/layouts/tier1_original.tres now holds that, so a save from
## before the shop section, which loads the template itself, gets it too.
const ORIGINAL_TABLES: Array[Array] = [[Vector2i(2, 6), 0], [Vector2i(6, 6), 0], [Vector2i(10, 6), 0]]


## Repairs `layout` in place: changed placements are replaced with copies, so
## a shared template is never touched. Returns how many items moved (0 when the
## shop was fine, or no repair could be found).
static func repair(layout: ShopLayout, content: ContentDB) -> int:
	if layout == null or content == null:
		return 0
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(layout, content, errors, true)
	var grid: SimGrid = world.grid
	var items: Array[PlacedItem] = grid.items()
	if not errors.is_empty() or items.size() != layout.placements.size():
		return 0
	var accepted: Dictionary[String, bool] = cut_off(grid, false)
	if _score(grid, accepted) == 0:
		return 0
	var start: SimGrid = _copy(grid)
	if start == null:
		return 0
	var spawns: Dictionary[Vector2i, bool] = {}
	for role: StringName in layout.staff_spawns:
		spawns[layout.staff_spawns[role]] = true
	if not _search(grid, start, accepted, spawns):
		return 0
	var count: int = 0
	# A shallow duplicate (LeaseUpgrade.layout_for) shares its template's array.
	layout.placements = layout.placements.duplicate()
	for index: int in items.size():
		var placed: PlacedItem = items[index]
		var old: ShopPlacement = layout.placements[index]
		if placed.origin == old.origin and placed.quarter_turns == old.quarter_turns:
			continue
		var copy: ShopPlacement = old.duplicate() as ShopPlacement
		copy.origin = placed.origin
		copy.quarter_turns = placed.quarter_turns
		layout.placements[index] = copy
		count += 1
	if count > 0:
		layout.aisle_moved = count
	return count


## Things nobody can reach from the street: items (as ShopEditor._unreachable
## names them), street-door cells and toilets. `seats_stop` walks as people do.
static func cut_off(grid: SimGrid, seats_stop: bool) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	var reach: Dictionary[Vector2i, bool] = WallRules.reachable(grid, seats_stop)
	var identity: Dictionary[int, int] = {}
	for placed: PlacedItem in grid.items():
		identity[placed.id] = placed.id
	for id: int in ShopEditor._unreachable_in(grid, identity, reach):
		out["item:%d" % id] = true
	for cell: Vector2i in WallRules.door_cells(grid):
		if not reach.has(cell):
			out["door:%d:%d" % [cell.x, cell.y]] = true
	for placed: PlacedItem in grid.items():
		if RoomRules.is_toilet(placed) and not ShopEditor._any_reachable(reach, placed.work_cells):
			out["toilet:%d" % placed.id] = true
	return out


## How many things real people can't reach that walking across seats could.
## `accepted` is what was already cut off that way when the shop loaded.
static func _score(grid: SimGrid, accepted: Dictionary[String, bool]) -> int:
	var count: int = 0
	for key: String in cut_off(grid, true):
		if not accepted.has(key):
			count += 1
	return count


## Fewest moves first: one move that fixes everything (the shortest, earliest
## item on ties), else the move that fixes the most, repeated.
static func _search(grid: SimGrid, start: SimGrid, accepted: Dictionary[String, bool],
		spawns: Dictionary[Vector2i, bool]) -> bool:
	var moved: Dictionary[int, bool] = {}
	var score: int = _score(grid, accepted)
	var history: Array[Array] = []
	while score > 0 and moved.size() < MAX_MOVES:
		var best: Array = []
		var best_score: int = score
		var best_cost: int = 0
		for placed: PlacedItem in grid.items():
			if moved.has(placed.id) or not _movable(placed):
				continue
			var home: Vector2i = placed.origin
			var home_turns: int = placed.quarter_turns
			for candidate: Array in _candidates(grid, placed):
				var cost: int = candidate[2]
				# Nothing later in this item's list can beat a full fix found
				# at a shorter or equal cost.
				if best_score == 0 and cost >= best_cost:
					break
				if not _try(grid, start, placed, candidate[0], candidate[1], spawns):
					continue
				var now: int = _score(grid, accepted)
				grid.relocate_def(placed.id, home, home_turns)
				if now < best_score or (now == best_score and not best.is_empty() and cost < best_cost):
					best = [placed.id, candidate[0], candidate[1], home, home_turns]
					best_score = now
					best_cost = cost
		if best.is_empty():
			break
		grid.relocate_def(best[0], best[1], best[2])
		moved[best[0]] = true
		history.append(best)
		score = best_score
	if score == 0:
		return true
	for index: int in range(history.size() - 1, -1, -1):
		var step: Array = history[index]
		grid.relocate_def(step[0], step[3], step[4])
	return false


## Tables and chairs, the furniture people sit at.
static func _movable(placed: PlacedItem) -> bool:
	var definition: ItemDef = placed.def as ItemDef
	return definition != null and definition.category in [ItemDef.Category.TABLE, ItemDef.Category.CHAIR]


## [origin, quarter turns, cost] within RADIUS, cheapest first. The cost is
## the move's length in cells plus one for a turn; ties go north to south,
## west to east, then by turns, so the order never changes.
static func _candidates(grid: SimGrid, placed: PlacedItem) -> Array[Array]:
	var out: Array[Array] = []
	var area: Rect2i = grid.bounds
	for y: int in range(maxi(area.position.y, placed.origin.y - RADIUS), mini(area.end.y, placed.origin.y + RADIUS + 1)):
		for x: int in range(maxi(area.position.x, placed.origin.x - RADIUS), mini(area.end.x, placed.origin.x + RADIUS + 1)):
			for turns: int in 4:
				var origin: Vector2i = Vector2i(x, y)
				if origin == placed.origin and turns == placed.quarter_turns:
					continue
				var cost: int = absi(x - placed.origin.x) + absi(y - placed.origin.y) \
					+ (0 if turns == placed.quarter_turns else 1)
				out.append([origin, turns, cost])
	out.sort_custom(_cheaper)
	return out


static func _cheaper(a: Array, b: Array) -> bool:
	if a[2] != b[2]:
		return a[2] < b[2]
	var left: Vector2i = a[0]
	var right: Vector2i = b[0]
	if left.y != right.y:
		return left.y < right.y
	if left.x != right.x:
		return left.x < right.x
	return int(a[1]) < int(b[1])


## Moves `placed` when the editor would accept the move: it fits, stays in
## the room kind it stood in, keeps every chair at its table, adds no room
## problem, puts no seat in the doorway, loses no dining seat and covers no
## staff start. False (and the item where it was) otherwise.
static func _try(grid: SimGrid, start: SimGrid, placed: PlacedItem, origin: Vector2i, turns: int,
		spawns: Dictionary[Vector2i, bool]) -> bool:
	var home: Vector2i = placed.origin
	var home_turns: int = placed.quarter_turns
	var rooms: Dictionary[int, bool] = {}
	for cell: Vector2i in placed.cells + placed.seat_cells:
		rooms[grid.room(cell)] = true
	if not grid.relocate_def(placed.id, origin, turns):
		return false
	var ok: bool = true
	for cell: Vector2i in placed.cells + placed.seat_cells:
		if spawns.has(cell) and placed.cells.has(cell) or not rooms.has(grid.room(cell)):
			ok = false
			break
	if ok:
		ok = ShopEditor.seat_doorway_problem(grid, placed).is_empty() \
			and _seat_count(grid) >= _seat_count(start)
	if ok:
		var identity: Dictionary[int, int] = {}
		for item: PlacedItem in grid.items():
			identity[item.id] = item.id
		ok = EditCheck.validate_dining(start, grid, identity, placed.id, placed.id).ok \
			and RoomRules.problem(start, grid, identity).is_empty()
	if not ok:
		grid.relocate_def(placed.id, home, home_turns)
	return ok


## The dining seats of every table group: a repair never trades one away.
static func _seat_count(grid: SimGrid) -> int:
	var seats: Dictionary[Vector2i, bool] = {}
	for placed: PlacedItem in grid.items():
		if (placed.def as ItemDef).category == ItemDef.Category.TABLE:
			for cell: Vector2i in grid.dining_group_seats(placed.id):
				seats[cell] = true
	return seats.size()


## Terrain, walls, rooms and items of `grid`, with the same item ids (null
## when they can't be copied).
static func _copy(grid: SimGrid) -> SimGrid:
	var copy: SimGrid = WallRules.walls_only(grid)
	for placed: PlacedItem in grid.items():
		var item: PlacedItem = copy.place_def(placed.def as ItemDef, placed.origin, placed.quarter_turns, placed.variant_id)
		if item == null or item.id != placed.id:
			return null
	return copy
