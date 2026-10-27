class_name SimGrid
extends RefCounted
## The shop layout as a 0.5 m grid: terrain (floor, wall, outside), placed
## items, and pathfinding between cells. Pure logic, no nodes (docs/TECH.md 2.3).
##
## Paths: 8-directional, no corner cutting, agents do not block each other.
## A cell is walkable when its terrain is FLOOR or ENTRY and no whole-item or
## explicit cell blocking covers it. find_path() includes start and goal, or
## an empty array when there is no path.
##
## Wall segments (FK-070) live on cell EDGES, not cells. An edge key is
## Vector3i(x, y, axis): EDGE_WEST is the grid line on the west side of cell
## (x, y) (between x-1 and x), EDGE_NORTH the line on its north side. Keys are
## grid-line positions, independent of whether the line is inside the room or
## on the outer shell, so they survive terrain changes such as a floor
## expansion: a window on an outer face becomes an interior window when the
## wall cell behind it turns into floor.

## What a cell is before any furniture goes on it.
enum Terrain { OUTSIDE, FLOOR, WALL, ENTRY }

## Result of a placement check.
enum PlaceResult { OK, OUT_OF_BOUNDS, NOT_FLOOR, OVERLAPS, INVALID_LAYER, INVALID_CELLS, WALL_IN_WAY }

## What stands on a cell edge. WALL and WINDOW block movement across the edge;
## DOORWAY is open. Any segment blocks diagonal steps past its end posts.
enum Segment { NONE, WALL, DOORWAY, WINDOW }

## Emitted after cells change walkability (place/remove/terrain edits).
## Agents whose path crosses one of these cells must re-plan.
signal cells_changed(cells: Array[Vector2i])

## Emitted after an item is removed. Agents heading to its work or seat cells
## (which lie outside its footprint, so cells_changed doesn't cover them) must
## drop or re-plan their task.
signal item_removed(item: PlacedItem)

const NO_CELL := Vector2i(-1, -1)
const NO_EDGE := Vector3i(-1, -1, -1)
const EDGE_WEST: int = 0
const EDGE_NORTH: int = 1

## How many nearby open cells a buried agent tries before giving up.
const ESCAPE_CANDIDATES: int = 16

const _DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

## Grid size in cells. Read-only.
var size: Vector2i:
	get:
		return _size

var _size: Vector2i = Vector2i.ZERO

var _terrain: PackedByteArray = PackedByteArray()
var _astar := AStarGrid2D.new()
## Segment kind per edge key (Segment values, NONE never stored).
var _segments: Dictionary[Vector3i, int] = {}
## Path-relevant edges (both cells inside the walkable shell). Shared by
## reference with _edge_astar, so they are cleared, never reassigned.
var _edge_blocking: Dictionary[Vector3i, bool] = {}
var _edge_occupied: Dictionary[Vector3i, bool] = {}
var _edge_astar: EdgeAStar = EdgeAStar.new(_edge_blocking, _edge_occupied)
var _items: Dictionary[int, PlacedItem] = {}
## cell -> id of the item covering it (solid or not).
var _cover: Dictionary[Vector2i, int] = {}
## One passive floor furnishing per cell, independent of ordinary coverage.
var _floor_cover: Dictionary[Vector2i, int] = {}
var _next_id: int = 1
var _entries: Array[Vector2i] = []
## Derived dining links. These are rebuilt from definitions, never saved.
var _dining_tables: Dictionary[Vector2i, int] = {}
var _dining_furnishings: Dictionary[Vector2i, int] = {}


## A new grid is all FLOOR (handy for tests); from_ascii() sets real terrain.
func _init(grid_size: Vector2i = Vector2i(1, 1)) -> void:
	_size = Vector2i(maxi(grid_size.x, 1), maxi(grid_size.y, 1))
	_terrain.resize(_size.x * _size.y)
	_terrain.fill(Terrain.FLOOR)
	for astar: AStarGrid2D in [_astar, _edge_astar]:
		astar.region = Rect2i(Vector2i.ZERO, _size)
		astar.cell_size = Vector2.ONE
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		astar.update()


## Builds a grid from rows of characters: '.' floor, '#' wall, ' ' or '~'
## outside, 'E' entry (a walkable street cell where customers appear and leave).
## Unknown characters count as outside. Rows may differ in length (short
## rows are padded with outside). No rows gives a 1x1 outside cell.
static func from_ascii(rows: PackedStringArray) -> SimGrid:
	if rows.is_empty():
		var empty := SimGrid.new(Vector2i(1, 1))
		empty.set_terrain(Vector2i.ZERO, Terrain.OUTSIDE)
		return empty
	var w := 0
	for row in rows:
		w = maxi(w, row.length())
	var grid := SimGrid.new(Vector2i(w, rows.size()))
	for y in rows.size():
		for x in w:
			var ch := rows[y][x] if x < rows[y].length() else " "
			var t: Terrain = Terrain.OUTSIDE
			match ch:
				".":
					t = Terrain.FLOOR
				"#":
					t = Terrain.WALL
				"E":
					t = Terrain.ENTRY
			grid.set_terrain(Vector2i(x, y), t)
	return grid


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func terrain(cell: Vector2i) -> Terrain:
	if not in_bounds(cell):
		return Terrain.OUTSIDE
	return _terrain[cell.y * size.x + cell.x] as Terrain


## Changes a cell's terrain. Returns false (and changes nothing) for
## out-of-bounds cells, or when an item covers the cell and t isn't FLOOR,
## since items may only stand on floor.
func set_terrain(cell: Vector2i, t: Terrain) -> bool:
	if not in_bounds(cell):
		return false
	if (_cover.has(cell) or _floor_cover.has(cell)) and t != Terrain.FLOOR:
		return false
	_terrain[cell.y * size.x + cell.x] = t
	if t == Terrain.ENTRY:
		if not _entries.has(cell):
			_entries.append(cell)
	else:
		_entries.erase(cell)
	_refresh_cell(cell)
	for edge: Vector3i in cell_edges(cell):
		_refresh_edge(edge)
	_refresh_dining_seats()
	cells_changed.emit([cell] as Array[Vector2i])
	return true


## Street cells where customers spawn and leave, in row-major order.
func entries() -> Array[Vector2i]:
	var out := _entries.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func is_walkable(cell: Vector2i) -> bool:
	return in_bounds(cell) and not _astar.is_point_solid(cell)


## Walkable adjacent cells in north/east/south/west then diagonal order.
## Diagonals obey the same no-corner-cutting rule as find_path().
func walkable_neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for direction: Vector2i in _DIRS:
		var neighbour: Vector2i = cell + direction
		if not is_walkable(neighbour):
			continue
		if direction.x != 0 and direction.y != 0:
			if not is_walkable(cell + Vector2i(direction.x, 0)) or not is_walkable(cell + Vector2i(0, direction.y)):
				continue
		if not _edge_occupied.is_empty() and not _edge_astar.step_open(cell, neighbour):
			continue
		out.append(neighbour)
	return out


## Checks whether an item could go at origin with the given rotation.
## Items need FLOOR under every footprint cell and no item in the same layer.
func can_place(footprint: Vector2i, origin: Vector2i, quarter_turns: int,
		layer: ItemDef.PlacementLayer = ItemDef.PlacementLayer.NORMAL) -> PlaceResult:
	if layer != ItemDef.PlacementLayer.NORMAL and layer != ItemDef.PlacementLayer.FLOOR_DECOR:
		return PlaceResult.INVALID_LAYER
	var cover: Dictionary[Vector2i, int] = _coverage(layer)
	var cells: Array[Vector2i] = _footprint_cells(footprint, origin, quarter_turns)
	for cell in cells:
		if not in_bounds(cell):
			return PlaceResult.OUT_OF_BOUNDS
		if terrain(cell) != Terrain.FLOOR:
			return PlaceResult.NOT_FLOOR
		if cover.has(cell):
			return PlaceResult.OVERLAPS
	if _segment_inside(cells):
		return PlaceResult.WALL_IN_WAY
	return PlaceResult.OK


## Definition-aware checking must agree with place_def, including floor decor.
func can_place_def(definition: ItemDef, origin: Vector2i, quarter_turns: int = 0) -> PlaceResult:
	if definition == null or not definition.placement_layer_valid():
		return PlaceResult.INVALID_LAYER
	if not definition.blocking_cells_valid():
		return PlaceResult.INVALID_CELLS
	var result: PlaceResult = can_place(definition.footprint, origin, quarter_turns, definition.placement_layer)
	if result == PlaceResult.OK and _access_walled_off(definition, origin, quarter_turns):
		return PlaceResult.WALL_IN_WAY
	return result


## Places an item. Work and seat cells are given relative to the unrotated
## footprint (see GridMath.rotate_cell). Returns the PlacedItem, or null if
## can_place() is not OK. An optional ItemDef also supplies explicit blocking
## cells, validated against both its authored and these actual placement values.
func place(footprint: Vector2i, origin: Vector2i, quarter_turns: int, solid: bool,
		work_cells: Array[Vector2i] = [], seat_cells: Array[Vector2i] = [],
		def: Resource = null) -> PlacedItem:
	var definition: ItemDef = def as ItemDef
	var layer: ItemDef.PlacementLayer = definition.placement_layer if definition != null else ItemDef.PlacementLayer.NORMAL
	if definition != null and (not definition.placement_layer_valid() or not definition.blocking_cells_valid() \
			or not definition.blocking_cells_fit(footprint, work_cells, seat_cells)):
		return null
	if layer == ItemDef.PlacementLayer.FLOOR_DECOR and (solid or not work_cells.is_empty() or not seat_cells.is_empty()):
		return null
	if can_place(footprint, origin, quarter_turns, layer) != PlaceResult.OK:
		return null
	var item := PlacedItem.new()
	item.id = _next_id
	_next_id += 1
	item.def = def
	item.placement_layer = layer
	item.origin = origin
	item.quarter_turns = posmod(quarter_turns, 4)
	item.solid = solid
	item.cells = _footprint_cells(footprint, origin, quarter_turns)
	if definition != null:
		for cell: Vector2i in definition.blocking_cells:
			item.blocking_cells.append(origin + GridMath.rotate_cell(cell, footprint, quarter_turns))
	for c in work_cells:
		item.work_cells.append(origin + GridMath.rotate_cell(c, footprint, quarter_turns))
	for c in seat_cells:
		item.seat_cells.append(origin + GridMath.rotate_cell(c, footprint, quarter_turns))
	_items[item.id] = item
	var cover: Dictionary[Vector2i, int] = _coverage(layer)
	for cell in item.cells:
		cover[cell] = item.id
		_refresh_cell(cell)
	_refresh_dining_seats()
	cells_changed.emit(item.cells.duplicate())
	return item


## Places an item from its content definition (footprint, solidity, work and
## seat cells come from the def). Returns null if it doesn't fit.
func place_def(def: ItemDef, origin: Vector2i, quarter_turns: int = 0) -> PlacedItem:
	if can_place_def(def, origin, quarter_turns) != PlaceResult.OK:
		return null
	return place(def.footprint, origin, quarter_turns, def.solid, def.work_cells, def.seat_cells, def)


## Moves/rotates an existing definition-backed item without replacing its id or
## object. Reservations refuse the move; the editor can explain "try next morning".
## Validation is read-only. Observers see the completed update once, never a
## temporary removal, and retain references to the same PlacedItem.
func relocate_def(item_id: int, origin: Vector2i, quarter_turns: int) -> bool:
	var placed: PlacedItem = item(item_id)
	if placed == null:
		return false
	var definition: ItemDef = placed.def as ItemDef
	if definition == null or definition.footprint.x < 1 or definition.footprint.y < 1 \
			or not definition.placement_layer_valid() or not definition.blocking_cells_valid() \
			or definition.placement_layer != placed.placement_layer:
		return false
	for cell: Vector2i in placed.work_cells + placed.seat_cells:
		if placed.reserved_by(cell) != -1:
			return false
	if definition.category == ItemDef.Category.CHAIR and _dining_furnishing_reserved(item_id):
		return false
	var turns: int = posmod(quarter_turns, 4)
	var new_cells: Array[Vector2i] = _footprint_cells(definition.footprint, origin, turns)
	var cover: Dictionary[Vector2i, int] = _coverage(placed.placement_layer)
	for cell: Vector2i in new_cells:
		if not in_bounds(cell) or terrain(cell) != Terrain.FLOOR:
			return false
		var covering: int = cover.get(cell, 0)
		if covering != 0 and covering != item_id:
			return false
	if _segment_inside(new_cells) or _access_walled_off(definition, origin, turns):
		return false
	if placed.origin == origin and placed.quarter_turns == turns:
		return true
	var changed: Array[Vector2i] = placed.cells.duplicate()
	for cell: Vector2i in placed.cells:
		cover.erase(cell)
	placed.origin = origin
	placed.quarter_turns = turns
	placed.cells = new_cells
	placed.blocking_cells.clear()
	placed.work_cells.clear()
	placed.seat_cells.clear()
	for cell: Vector2i in definition.blocking_cells:
		placed.blocking_cells.append(origin + GridMath.rotate_cell(cell, definition.footprint, turns))
	for cell: Vector2i in definition.work_cells:
		placed.work_cells.append(origin + GridMath.rotate_cell(cell, definition.footprint, turns))
	for cell: Vector2i in definition.seat_cells:
		placed.seat_cells.append(origin + GridMath.rotate_cell(cell, definition.footprint, turns))
	for cell: Vector2i in new_cells:
		cover[cell] = item_id
		if not changed.has(cell):
			changed.append(cell)
	for cell: Vector2i in changed:
		_refresh_cell(cell)
	_refresh_dining_seats()
	cells_changed.emit(changed)
	return true


## Removes an item by id. Returns false if there is no such item.
func remove(item_id: int) -> bool:
	if not _items.has(item_id):
		return false
	var item: PlacedItem = _items[item_id]
	_items.erase(item_id)
	item.removed = true
	item.clear_reservations()
	var cover: Dictionary[Vector2i, int] = _coverage(item.placement_layer)
	for cell in item.cells:
		cover.erase(cell)
		_refresh_cell(cell)
	_refresh_dining_seats()
	cells_changed.emit(item.cells.duplicate())
	item_removed.emit(item)
	return true


func item(item_id: int) -> PlacedItem:
	return _items.get(item_id, null)


## Item covering a cell, or null.
func item_at(cell: Vector2i) -> PlacedItem:
	var normal: PlacedItem = item_on_layer(cell, ItemDef.PlacementLayer.NORMAL)
	return normal if normal != null else item_on_layer(cell, ItemDef.PlacementLayer.FLOOR_DECOR)


func item_on_layer(cell: Vector2i, layer: ItemDef.PlacementLayer) -> PlacedItem:
	if layer != ItemDef.PlacementLayer.NORMAL and layer != ItemDef.PlacementLayer.FLOOR_DECOR:
		return null
	return _items.get(_coverage(layer).get(cell, 0), null)


## A detached deterministic list for view/picking callers: normal, then floor.
func items_at(cell: Vector2i) -> Array[PlacedItem]:
	var result: Array[PlacedItem] = []
	for layer: ItemDef.PlacementLayer in [ItemDef.PlacementLayer.NORMAL, ItemDef.PlacementLayer.FLOOR_DECOR]:
		var placed: PlacedItem = item_on_layer(cell, layer)
		if placed != null:
			result.append(placed)
	return result


func _coverage(layer: ItemDef.PlacementLayer) -> Dictionary[Vector2i, int]:
	return _floor_cover if layer == ItemDef.PlacementLayer.FLOOR_DECOR else _cover


## Physical table/counter owning a valid dining seat, or 0 if none.
func dining_table_id(seat_cell: Vector2i) -> int:
	return _dining_tables.get(seat_cell, 0)


## Standalone seat furnishing, or the table itself for an authored built-in.
## Returns 0 when the cell is not part of a valid dining link.
func dining_furnishing_id(seat_cell: Vector2i) -> int:
	return _dining_furnishings.get(seat_cell, 0)


## All items, ordered by id (placement order), so iteration is deterministic.
func items() -> Array[PlacedItem]:
	var ids := _items.keys()
	ids.sort()
	var out: Array[PlacedItem] = []
	for id: int in ids:
		out.append(_items[id])
	return out


## Shortest path from start to goal, both inclusive. Empty if the goal is not
## walkable or unreachable. If the start is not walkable (furniture landed on
## an agent), the path begins at start and continues from the nearest walkable
## cell that can reach the goal, so an agent is never trapped; that first step
## may be longer than one cell when the agent was buried inside a large item.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not in_bounds(start) or not is_walkable(goal):
		return []
	if start == goal:
		return [start]
	if is_walkable(start):
		return _solve(start, goal)
	for exit in _walkable_rings(start, ESCAPE_CANDIDATES):
		# The escape jump itself may not cross a wall next to the buried cell.
		# Longer jumps (deeply buried) are not edge-checked: they already pass
		# through solid furniture, and walls are closed-phase edits only.
		if not step_open(start, exit):
			continue
		var rest: Array[Vector2i] = []
		if exit == goal:
			rest.append(exit)
		else:
			rest = _solve(exit, goal)
		if rest.is_empty():
			continue
		var path: Array[Vector2i] = [start]
		path.append_array(rest)
		return path
	return []


## Nearest walkable cell to `cell` by grid steps (the cell itself if it is
## walkable), searching outward in a fixed order so the answer is deterministic.
## NO_CELL if the grid has no walkable cell at all.
func nearest_walkable(cell: Vector2i) -> Vector2i:
	if not in_bounds(cell):
		return NO_CELL
	if is_walkable(cell):
		return cell
	var found := _walkable_rings(cell, 1)
	return NO_CELL if found.is_empty() else found[0]


## Cheapest path from start to any of the goals (ties go to the earlier goal).
## Empty if none is reachable. Goals whose straight-line lower bound can't
## beat the best path found so far are skipped without a search.
func find_path_to_any(start: Vector2i, goals: Array[Vector2i]) -> Array[Vector2i]:
	var order: Array[int] = []
	for i in goals.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := GridMath.octile(start, goals[a])
		var db := GridMath.octile(start, goals[b])
		return da < db or (da == db and a < b))
	var best: Array[Vector2i] = []
	var best_cost := INF
	var best_index := -1
	for i in order:
		if GridMath.octile(start, goals[i]) > best_cost:
			break
		var path := find_path(start, goals[i])
		if path.is_empty():
			continue
		var cost := GridMath.path_cost(path)
		if cost < best_cost or (cost == best_cost and i < best_index):
			best = path
			best_cost = cost
			best_index = i
	return best


## First work cell of an item that is walkable and not reserved, or NO_CELL.
func free_work_cell(it: PlacedItem) -> Vector2i:
	return _free_cell(it, it.work_cells)


## First seat cell of an item that is walkable and not reserved, or NO_CELL.
func free_seat_cell(it: PlacedItem) -> Vector2i:
	return _free_cell(it, it.seat_cells)


func is_reachable(start: Vector2i, goal: Vector2i) -> bool:
	return not find_path(start, goal).is_empty()


## Walkable cells nearest to `cell` (excluding it), ring by ring in a fixed
## direction order, up to `limit` of them.
func _walkable_rings(cell: Vector2i, limit: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary[Vector2i, bool] = {cell: true}
	var frontier: Array[Vector2i] = [cell]
	while not frontier.is_empty() and out.size() < limit:
		var next: Array[Vector2i] = []
		for c in frontier:
			for d in _DIRS:
				var n := c + d
				if not in_bounds(n) or seen.has(n):
					continue
				seen[n] = true
				if is_walkable(n):
					out.append(n)
					if out.size() >= limit:
						return out
				else:
					next.append(n)
		frontier = next
	return out


func _free_cell(it: PlacedItem, cells: Array[Vector2i]) -> Vector2i:
	if it.removed:
		return NO_CELL
	for c in cells:
		if it.reserved_by(c) == -1 and is_walkable(c):
			return c
	return NO_CELL


## Finish this projection before publishing the existing mutation signals.
## Generic placements and standalone chairs keep their authored cell lists;
## only physical tables receive the derived seats and retain their bookings.
func _refresh_dining_seats() -> void:
	var plan: DiningSeats.Plan = DiningSeats.derive(self)
	for table_id: int in plan.table_seats:
		var table: PlacedItem = item(table_id)
		table.set_seat_cells(plan.seats_for(table_id))
	var tables: Dictionary[Vector2i, int] = {}
	var furnishings: Dictionary[Vector2i, int] = {}
	for link: DiningSeats.SeatLink in plan.links:
		tables[link.cell] = link.table_item_id
		furnishings[link.cell] = link.furnishing_item_id
	_dining_tables = tables
	_dining_furnishings = furnishings


func _dining_furnishing_reserved(furnishing_id: int) -> bool:
	for cell: Vector2i in _dining_furnishings:
		if _dining_furnishings[cell] != furnishing_id:
			continue
		var table: PlacedItem = item(_dining_tables[cell])
		if table != null and table.reserved_by(cell) != -1:
			return true
	return false


func _footprint_cells(footprint: Vector2i, origin: Vector2i, quarter_turns: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var f := GridMath.rotated_footprint(footprint, quarter_turns)
	for y in f.y:
		for x in f.x:
			out.append(origin + Vector2i(x, y))
	return out


func _refresh_cell(cell: Vector2i) -> void:
	var t := terrain(cell)
	var blocked := t == Terrain.WALL or t == Terrain.OUTSIDE
	var id: int = _cover.get(cell, 0)
	if id != 0 and (_items[id].solid or _items[id].blocking_cells.has(cell)):
		blocked = true
	_astar.set_point_solid(cell, blocked)
	_edge_astar.set_point_solid(cell, blocked)


## The plain engine search while no interior segment exists, so a shop without
## walls keeps exactly the paths (and tie-breaks) it had before FK-070.
func _solve(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if _edge_occupied.is_empty():
		return _astar.get_id_path(start, goal)
	var path: Array[Vector2i] = _edge_astar.get_id_path(start, goal)
	for index: int in range(1, path.size()):
		if not _edge_astar.step_open(path[index - 1], path[index]):
			return []
	return path


# --- Wall segments (FK-070) -------------------------------------------------

## Edge between two orthogonally adjacent cells, or NO_EDGE.
static func edge_between(a: Vector2i, b: Vector2i) -> Vector3i:
	var delta: Vector2i = b - a
	if delta == Vector2i(1, 0):
		return Vector3i(b.x, b.y, EDGE_WEST)
	if delta == Vector2i(-1, 0):
		return Vector3i(a.x, a.y, EDGE_WEST)
	if delta == Vector2i(0, 1):
		return Vector3i(b.x, b.y, EDGE_NORTH)
	if delta == Vector2i(0, -1):
		return Vector3i(a.x, a.y, EDGE_NORTH)
	return NO_EDGE


## The two cells an edge separates: [west or north cell, east or south cell].
static func edge_cells(edge: Vector3i) -> Array[Vector2i]:
	var cell: Vector2i = Vector2i(edge.x, edge.y)
	var before: Vector2i = cell - (Vector2i(1, 0) if edge.z == EDGE_WEST else Vector2i(0, 1))
	return [before, cell]


## Grid-line end points. Vertex (x, y) is the north-west corner of cell (x, y).
static func edge_vertices(edge: Vector3i) -> Array[Vector2i]:
	var start: Vector2i = Vector2i(edge.x, edge.y)
	return [start, start + (Vector2i(0, 1) if edge.z == EDGE_WEST else Vector2i(1, 0))]


## Edge joining two neighbouring grid vertices, or NO_EDGE.
static func edge_from_vertices(a: Vector2i, b: Vector2i) -> Vector3i:
	var low: Vector2i = a.min(b)
	var delta: Vector2i = (b - a).abs()
	if delta == Vector2i(0, 1):
		return Vector3i(low.x, low.y, EDGE_WEST)
	if delta == Vector2i(1, 0):
		return Vector3i(low.x, low.y, EDGE_NORTH)
	return NO_EDGE


## The (up to) four edges meeting at a grid vertex.
static func edges_at_vertex(vertex: Vector2i) -> Array[Vector3i]:
	return [Vector3i(vertex.x, vertex.y - 1, EDGE_WEST), Vector3i(vertex.x, vertex.y, EDGE_WEST),
		Vector3i(vertex.x - 1, vertex.y, EDGE_NORTH), Vector3i(vertex.x, vertex.y, EDGE_NORTH)]


## A cell's four sides: west, north, east, south.
static func cell_edges(cell: Vector2i) -> Array[Vector3i]:
	return [Vector3i(cell.x, cell.y, EDGE_WEST), Vector3i(cell.x, cell.y, EDGE_NORTH),
		Vector3i(cell.x + 1, cell.y, EDGE_WEST), Vector3i(cell.x, cell.y + 1, EDGE_NORTH)]


## An edge key is usable when it separates two in-bounds cells.
func edge_in_bounds(edge: Vector3i) -> bool:
	if edge.z != EDGE_WEST and edge.z != EDGE_NORTH:
		return false
	var cells: Array[Vector2i] = edge_cells(edge)
	return in_bounds(cells[0]) and in_bounds(cells[1])


## True unless a segment blocks this step (orthogonal across a wall/window, or
## diagonal past any segment's end). Non-adjacent steps are always open.
func step_open(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	return _edge_occupied.is_empty() or _edge_astar.step_open(from_cell, to_cell)


func segment(edge: Vector3i) -> Segment:
	return _segments.get(edge, Segment.NONE) as Segment


## Places, changes or (with NONE) removes a segment. Rules about where walls
## may stand belong to WallRules; this only refuses malformed edges. Emits
## cells_changed with both cells when the edge changes.
func set_segment(edge: Vector3i, kind: Segment) -> bool:
	if not edge_in_bounds(edge) or kind < Segment.NONE or kind > Segment.WINDOW:
		return false
	if segment(edge) == kind:
		return true
	if kind == Segment.NONE:
		_segments.erase(edge)
	else:
		_segments[edge] = kind
	_refresh_edge(edge)
	_refresh_dining_seats()
	cells_changed.emit(edge_cells(edge))
	return true


## Applies several segment changes (edge -> Segment) with one cells_changed
## and one dining refresh, so a dragged run rebuilds observers once. Nothing
## changes when any edge is malformed.
func set_segments(changes: Dictionary[Vector3i, int]) -> bool:
	for edge: Vector3i in changes:
		var kind: int = changes[edge]
		if not edge_in_bounds(edge) or kind < Segment.NONE or kind > Segment.WINDOW:
			return false
	var touched: Array[Vector2i] = []
	for edge: Vector3i in changes:
		if segment(edge) == changes[edge]:
			continue
		if changes[edge] == Segment.NONE:
			_segments.erase(edge)
		else:
			_segments[edge] = changes[edge]
		_refresh_edge(edge)
		for cell: Vector2i in edge_cells(edge):
			if not touched.has(cell):
				touched.append(cell)
	if touched.is_empty():
		return true
	_refresh_dining_seats()
	cells_changed.emit(touched)
	return true


## Every edge holding a segment, sorted (axis, then row, then column).
func segment_edges() -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	edges.assign(_segments.keys())
	edges.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.z < b.z or (a.z == b.z and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return edges


func has_segments() -> bool:
	return not _segments.is_empty()


## True when a wall or window stands between two orthogonally adjacent cells.
func edge_blocked(a: Vector2i, b: Vector2i) -> bool:
	var kind: Segment = segment(edge_between(a, b))
	return kind == Segment.WALL or kind == Segment.WINDOW


## Only edges with walkable-shell terrain on both sides take part in pathing,
## so outer-face windows leave paths untouched until the shell moves.
func _refresh_edge(edge: Vector3i) -> void:
	var kind: Segment = segment(edge)
	var inside: bool = false
	if kind != Segment.NONE and edge_in_bounds(edge):
		inside = true
		for cell: Vector2i in edge_cells(edge):
			var t: Terrain = terrain(cell)
			if t != Terrain.FLOOR and t != Terrain.ENTRY:
				inside = false
	if inside:
		_edge_occupied[edge] = true
		if kind == Segment.WALL or kind == Segment.WINDOW:
			_edge_blocking[edge] = true
		else:
			_edge_blocking.erase(edge)
	else:
		_edge_occupied.erase(edge)
		_edge_blocking.erase(edge)


## Any segment on an edge between two cells of one footprint.
func _segment_inside(cells: Array[Vector2i]) -> bool:
	if _segments.is_empty():
		return false
	for cell: Vector2i in cells:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if cells.has(cell + step) and _segments.has(edge_between(cell, cell + step)):
				return true
	return false


## A wall or window between an item and one of its own work cells.
func _access_walled_off(definition: ItemDef, origin: Vector2i, quarter_turns: int) -> bool:
	if _segments.is_empty() or definition == null:
		return false
	var cells: Array[Vector2i] = _footprint_cells(definition.footprint, origin, quarter_turns)
	var access: Array[Vector2i] = []
	# Work cells only: a table's seat across a wall is dropped by DiningSeats.
	for authored: Vector2i in definition.work_cells:
		access.append(origin + GridMath.rotate_cell(authored, definition.footprint, quarter_turns))
	return access_walled_off(cells, access)


## True when some access cell touches the footprint only across walls/windows.
func access_walled_off(cells: Array[Vector2i], access: Array[Vector2i]) -> bool:
	if _segments.is_empty():
		return false
	for spot: Vector2i in access:
		var touching: int = 0
		var blocked: int = 0
		for cell: Vector2i in cells:
			if edge_between(cell, spot) == NO_EDGE:
				continue
			touching += 1
			if edge_blocked(cell, spot):
				blocked += 1
		if touching > 0 and blocked == touching:
			return true
	return false
