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
enum PlaceResult { OK, OUT_OF_BOUNDS, NOT_FLOOR, OVERLAPS }

## Emitted after cells change walkability (place/remove/terrain edits).
## Agents whose path crosses one of these cells must re-plan.
signal cells_changed(cells: Array[Vector2i])

var size: Vector2i = Vector2i.ZERO

var _terrain: PackedByteArray = PackedByteArray()
var _astar := AStarGrid2D.new()
var _items: Dictionary[int, PlacedItem] = {}
## cell -> id of the item covering it (solid or not).
var _cover: Dictionary[Vector2i, int] = {}
var _next_id: int = 1
var _entries: Array[Vector2i] = []


func _init(grid_size: Vector2i = Vector2i(1, 1)) -> void:
	size = Vector2i(maxi(grid_size.x, 1), maxi(grid_size.y, 1))
	_terrain.resize(size.x * size.y)
	_terrain.fill(Terrain.FLOOR)
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()


## Builds a grid from rows of characters: '.' floor, '#' wall, ' ' or '~'
## outside, 'E' entry (a walkable street cell where customers appear and leave).
## Unknown characters count as outside. Rows may differ in length.
static func from_ascii(rows: PackedStringArray) -> SimGrid:
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


## Changes a cell's terrain. Ignored for out-of-bounds cells.
func set_terrain(cell: Vector2i, t: Terrain) -> void:
	if not in_bounds(cell):
		return
	_terrain[cell.y * size.x + cell.x] = t
	if t == Terrain.ENTRY:
		if not _entries.has(cell):
			_entries.append(cell)
	else:
		_entries.erase(cell)
	_refresh_cell(cell)
	cells_changed.emit([cell] as Array[Vector2i])


## Street cells where customers spawn and leave, in row-major order.
func entries() -> Array[Vector2i]:
	var out := _entries.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func is_walkable(cell: Vector2i) -> bool:
	return in_bounds(cell) and not _astar.is_point_solid(cell)


## Checks whether an item could go at origin with the given rotation.
## Items need FLOOR under every footprint cell and no other item there.
func can_place(footprint: Vector2i, origin: Vector2i, quarter_turns: int) -> PlaceResult:
	for cell in _footprint_cells(footprint, origin, quarter_turns):
		if not in_bounds(cell):
			return PlaceResult.OUT_OF_BOUNDS
		if terrain(cell) != Terrain.FLOOR:
			return PlaceResult.NOT_FLOOR
		if _cover.has(cell):
			return PlaceResult.OVERLAPS
	return PlaceResult.OK


## Places an item. Work and seat cells are given relative to the unrotated
## footprint (see GridMath.rotate_cell). Returns the PlacedItem, or null if
## can_place() is not OK. `def` is stored as-is for callers (an ItemDef).
func place(footprint: Vector2i, origin: Vector2i, quarter_turns: int, solid: bool,
		work_cells: Array[Vector2i] = [], seat_cells: Array[Vector2i] = [],
		def: Resource = null) -> PlacedItem:
	if can_place(footprint, origin, quarter_turns) != PlaceResult.OK:
		return null
	var item := PlacedItem.new()
	item.id = _next_id
	_next_id += 1
	item.def = def
	item.origin = origin
	item.quarter_turns = posmod(quarter_turns, 4)
	item.solid = solid
	item.cells = _footprint_cells(footprint, origin, quarter_turns)
	for c in work_cells:
		item.work_cells.append(origin + GridMath.rotate_cell(c, footprint, quarter_turns))
	for c in seat_cells:
		item.seat_cells.append(origin + GridMath.rotate_cell(c, footprint, quarter_turns))
	_items[item.id] = item
	for cell in item.cells:
		_cover[cell] = item.id
		_refresh_cell(cell)
	cells_changed.emit(item.cells.duplicate())
	return item


## Removes an item by id. Returns false if there is no such item.
func remove(item_id: int) -> bool:
	if not _items.has(item_id):
		return false
	var item: PlacedItem = _items[item_id]
	_items.erase(item_id)
	for cell in item.cells:
		_cover.erase(cell)
		_refresh_cell(cell)
	cells_changed.emit(item.cells.duplicate())
	return true


func item(item_id: int) -> PlacedItem:
	return _items.get(item_id, null)


## Item covering a cell, or null.
func item_at(cell: Vector2i) -> PlacedItem:
	var id: int = _cover.get(cell, 0)
	return _items.get(id, null)


## All items, ordered by id (placement order), so iteration is deterministic.
func items() -> Array[PlacedItem]:
	var ids := _items.keys()
	ids.sort()
	var out: Array[PlacedItem] = []
	for id: int in ids:
		out.append(_items[id])
	return out


## Shortest path from start to goal, both inclusive. Empty if the goal is not
## walkable or unreachable. The start may be non-walkable (an agent standing
## where furniture just landed): it is let out to the nearest open neighbour.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not in_bounds(start) or not is_walkable(goal):
		return []
	if start == goal:
		return [start]
	var start_blocked := _astar.is_point_solid(start)
	if start_blocked:
		_astar.set_point_solid(start, false)
	var path: Array[Vector2i] = _astar.get_id_path(start, goal)
	if start_blocked:
		_astar.set_point_solid(start, true)
	return path


## Cheapest path from start to any of the goals (ties go to the earlier goal).
## Empty if none is reachable.
func find_path_to_any(start: Vector2i, goals: Array[Vector2i]) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_cost := INF
	for goal in goals:
		var path := find_path(start, goal)
		if path.is_empty():
			continue
		var cost := GridMath.path_cost(path)
		if cost < best_cost:
			best = path
			best_cost = cost
	return best


func is_reachable(start: Vector2i, goal: Vector2i) -> bool:
	return not find_path(start, goal).is_empty()


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
