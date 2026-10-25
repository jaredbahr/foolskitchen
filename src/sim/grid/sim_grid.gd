class_name SimGrid
extends RefCounted
## The shop layout as a 0.5 m grid: terrain (floor, wall, outside), placed
## items, and pathfinding between cells. Pure logic, no nodes (docs/TECH.md 2.3).
##
## Paths: 8-directional, no corner cutting, agents do not block each other.
## A cell is walkable when its terrain is FLOOR or ENTRY and no solid item
## covers it. find_path() returns the cells from start to goal inclusive, or
## an empty array when there is no path.

## What a cell is before any furniture goes on it.
enum Terrain { OUTSIDE, FLOOR, WALL, ENTRY }

## Result of a placement check.
enum PlaceResult { OK, OUT_OF_BOUNDS, NOT_FLOOR, OVERLAPS, INVALID_LAYER }

## Emitted after cells change walkability (place/remove/terrain edits).
## Agents whose path crosses one of these cells must re-plan.
signal cells_changed(cells: Array[Vector2i])

## Emitted after an item is removed. Agents heading to its work or seat cells
## (which lie outside its footprint, so cells_changed doesn't cover them) must
## drop or re-plan their task.
signal item_removed(item: PlacedItem)

const NO_CELL := Vector2i(-1, -1)

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
	_astar.region = Rect2i(Vector2i.ZERO, _size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()


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
		out.append(neighbour)
	return out


## Checks whether an item could go at origin with the given rotation.
## Items need FLOOR under every footprint cell and no item in the same layer.
func can_place(footprint: Vector2i, origin: Vector2i, quarter_turns: int,
		layer: ItemDef.PlacementLayer = ItemDef.PlacementLayer.NORMAL) -> PlaceResult:
	if layer != ItemDef.PlacementLayer.NORMAL and layer != ItemDef.PlacementLayer.FLOOR_DECOR:
		return PlaceResult.INVALID_LAYER
	var cover: Dictionary[Vector2i, int] = _coverage(layer)
	for cell in _footprint_cells(footprint, origin, quarter_turns):
		if not in_bounds(cell):
			return PlaceResult.OUT_OF_BOUNDS
		if terrain(cell) != Terrain.FLOOR:
			return PlaceResult.NOT_FLOOR
		if cover.has(cell):
			return PlaceResult.OVERLAPS
	return PlaceResult.OK


## Definition-aware checking must agree with place_def, including floor decor.
func can_place_def(definition: ItemDef, origin: Vector2i, quarter_turns: int = 0) -> PlaceResult:
	if definition == null or not definition.placement_layer_valid():
		return PlaceResult.INVALID_LAYER
	return can_place(definition.footprint, origin, quarter_turns, definition.placement_layer)


## Places an item. Work and seat cells are given relative to the unrotated
## footprint (see GridMath.rotate_cell). Returns the PlacedItem, or null if
## can_place() is not OK. `def` is stored as-is for callers (an ItemDef).
func place(footprint: Vector2i, origin: Vector2i, quarter_turns: int, solid: bool,
		work_cells: Array[Vector2i] = [], seat_cells: Array[Vector2i] = [],
		def: Resource = null) -> PlacedItem:
	var definition: ItemDef = def as ItemDef
	var layer: ItemDef.PlacementLayer = definition.placement_layer if definition != null else ItemDef.PlacementLayer.NORMAL
	if definition != null and not definition.placement_layer_valid():
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
			or not definition.placement_layer_valid() or definition.placement_layer != placed.placement_layer:
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
	if placed.origin == origin and placed.quarter_turns == turns:
		return true
	var changed: Array[Vector2i] = placed.cells.duplicate()
	for cell: Vector2i in placed.cells:
		cover.erase(cell)
	placed.origin = origin
	placed.quarter_turns = turns
	placed.cells = new_cells
	placed.work_cells.clear()
	placed.seat_cells.clear()
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
		return _astar.get_id_path(start, goal)
	for exit in _walkable_rings(start, ESCAPE_CANDIDATES):
		var rest: Array[Vector2i] = []
		if exit == goal:
			rest.append(exit)
		else:
			rest = _astar.get_id_path(exit, goal)
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
	if id != 0 and _items[id].solid:
		blocked = true
	_astar.set_point_solid(cell, blocked)
