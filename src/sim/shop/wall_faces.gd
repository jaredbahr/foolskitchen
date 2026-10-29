class_name WallFaces
extends RefCounted
## Wall faces (D26): one 0.5 m wide side of a wall, seen from the floor cell
## in front of it. A face key is Vector3i(x, y, dir): the floor cell (x, y)
## and the direction from it into the wall (DIRS index: 0 north, 1 east,
## 2 south, 3 west). Faces are derived from the grid on every query, never
## stored: the room side of a solid shell wall cell, and either side of an
## interior wall segment. Windows, doorways (the back door too), the street
## door and shell cells cut by a window or door have no face. Wall finishes
## and wall decor live on faces; both are looks only.
##
## A window slot uses the same key for an outside window: the floor cell
## inside and the direction from it into the window (WallRules.outer_side).
## A slot is never a face, so window signs and wall decor share one map.

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const NO_FACE: Vector3i = Vector3i(-1000000, -1000000, -1)

enum Kind { NONE, SHELL, INTERIOR }

## Refusals, one sentence each (rule 11).
const NOT_INSIDE: String = "Wall decor hangs on a wall inside the shop"
const NO_WALL: String = "There is no wall here"
const WINDOW: String = "This wall has a window"
const DOORWAY: String = "This is a doorway"
const CUT_SHELL: String = "This part of the wall has a window or door in it"
const STREET_DOOR: String = "This is the street door"
const TOO_NARROW: String = "Not enough wall here"
const CORNER: String = "A wall is in the way"
const WINDOW_ONLY: String = "This sign hangs in a window"
const OUTSIDE_WINDOW_ONLY: String = "This sign hangs in a window on an outside wall"


static func make(cell: Vector2i, dir: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, posmod(dir, 4))


static func cell(face: Vector3i) -> Vector2i:
	return Vector2i(face.x, face.y)


## The direction from the face's floor cell into its wall.
static func step(face: Vector3i) -> Vector2i:
	return DIRS[posmod(face.z, 4)]


## The grid edge the face lies on.
static func edge(face: Vector3i) -> Vector3i:
	return SimGrid.edge_between(cell(face), cell(face) + step(face))


## Along the wall to the right, seen from the room (a wide item's next face).
static func along(face: Vector3i) -> Vector2i:
	return DIRS[posmod(face.z + 1, 4)]


static func kind(grid: SimGrid, face: Vector3i) -> Kind:
	return Kind.NONE if not problem(grid, face).is_empty() else (
		Kind.INTERIOR if grid.segment(edge(face)) == SimGrid.Segment.WALL else Kind.SHELL)


static func is_face(grid: SimGrid, face: Vector3i) -> bool:
	return grid != null and face.z >= 0 and face.z < 4 and problem(grid, face).is_empty()


## Why `face` is not a wall face ("" when it is).
static func problem(grid: SimGrid, face: Vector3i) -> String:
	if grid == null or face.z < 0 or face.z > 3:
		return NO_WALL
	var here: Vector2i = cell(face)
	if grid.terrain(here) != SimGrid.Terrain.FLOOR:
		return NOT_INSIDE
	var there: Vector2i = here + step(face)
	match grid.segment(edge(face)):
		SimGrid.Segment.WALL:
			return "" if grid.terrain(there) == SimGrid.Terrain.FLOOR else NO_WALL
		SimGrid.Segment.WINDOW:
			return WINDOW
		SimGrid.Segment.DOORWAY:
			return DOORWAY
	match grid.terrain(there):
		SimGrid.Terrain.WALL:
			return CUT_SHELL if shell_cut(grid, there) else ""
		SimGrid.Terrain.ENTRY:
			return STREET_DOOR
	return NO_WALL


## A shell cell holding a window or back door on any side: its box is cut
## or hidden, so none of its sides is a plain wall.
static func shell_cut(grid: SimGrid, wall_cell: Vector2i) -> bool:
	for side: Vector3i in SimGrid.cell_edges(wall_cell):
		if grid.segment(side) != SimGrid.Segment.NONE:
			return true
	return false


## Why `slot` is not an outside window an item can hang in ("" when it is):
## a window segment between a floor cell and the shell, the street beyond.
static func window_problem(grid: SimGrid, slot: Vector3i) -> String:
	if grid == null or slot.z < 0 or slot.z > 3:
		return WINDOW_ONLY
	if grid.terrain(cell(slot)) != SimGrid.Terrain.FLOOR or grid.segment(edge(slot)) != SimGrid.Segment.WINDOW:
		return WINDOW_ONLY
	if WallRules.outer_side(grid, edge(slot)) != step(slot):
		return OUTSIDE_WINDOW_ONLY
	return ""


static func is_window(grid: SimGrid, slot: Vector3i) -> bool:
	return window_problem(grid, slot).is_empty()


## Every outside window slot of the shop, sorted.
static func windows(grid: SimGrid) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if grid == null:
		return out
	for edge_key: Vector3i in grid.segment_edges():
		var side: Vector2i = WallRules.outer_side(grid, edge_key)
		if side == Vector2i.ZERO or grid.segment(edge_key) != SimGrid.Segment.WINDOW:
			continue
		for here: Vector2i in SimGrid.edge_cells(edge_key):
			if grid.terrain(here) == SimGrid.Terrain.FLOOR:
				out.append(make(here, DIRS.find(side)))
	sort(out)
	return out


## Every wall face of the shop, sorted.
static func all(grid: SimGrid) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if grid == null:
		return out
	for here: Vector2i in grid.cells():
		if grid.terrain(here) != SimGrid.Terrain.FLOOR:
			continue
		for dir: int in 4:
			var face: Vector3i = make(here, dir)
			if is_face(grid, face):
				out.append(face)
	sort(out)
	return out


## The wall faces of these floor cells, sorted.
static func of_cells(grid: SimGrid, cells: Array[Vector2i]) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for here: Vector2i in cells:
		for dir: int in 4:
			var face: Vector3i = make(here, dir)
			if is_face(grid, face):
				out.append(face)
	sort(out)
	return out


## Every wall face of the room `face` looks into (FloorFinishes.room_cells:
## it stops at any wall segment and at room edges), sorted.
static func room_faces(grid: SimGrid, face: Vector3i) -> Array[Vector3i]:
	if not is_face(grid, face):
		return []
	return of_cells(grid, FloorFinishes.room_cells(grid, cell(face)))


## The faces joined to `start` along the wall: the same wall on to the next
## floor cell (no segment between the cells), and round an inside corner
## within one cell. `keep(face)` must hold for every face taken. Sorted.
static func flood(grid: SimGrid, start: Vector3i, keep: Callable) -> Array[Vector3i]:
	if not is_face(grid, start):
		return []
	var area: Array[Vector3i] = [start]
	var seen: Dictionary[Vector3i, bool] = {start: true}
	var index: int = 0
	while index < area.size():
		var face: Vector3i = area[index]
		index += 1
		for next: Vector3i in _neighbours(grid, face):
			if seen.has(next) or not is_face(grid, next) or not bool(keep.call(next)):
				continue
			seen[next] = true
			area.append(next)
	sort(area)
	return area


static func _neighbours(grid: SimGrid, face: Vector3i) -> Array[Vector3i]:
	var here: Vector2i = cell(face)
	var out: Array[Vector3i] = [make(here, face.z + 1), make(here, face.z + 3)]
	for side: Vector2i in [along(face), -along(face)]:
		var next: Vector2i = here + side
		if grid.terrain(next) == SimGrid.Terrain.FLOOR and grid.segment(SimGrid.edge_between(here, next)) == SimGrid.Segment.NONE:
			out.append(make(next, face.z))
	return out


## The `width` faces a wide item covers from `anchor` to its right.
static func span(anchor: Vector3i, width: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for index: int in range(maxi(width, 1)):
		out.append(make(cell(anchor) + along(anchor) * index, anchor.z))
	return out


## Why `width` faces from `anchor` are not one straight run of wall ("" when
## they are): every face solid, and no segment between their floor cells.
static func span_problem(grid: SimGrid, anchor: Vector3i, width: int) -> String:
	var faces: Array[Vector3i] = span(anchor, width)
	for index: int in range(faces.size()):
		var why: String = problem(grid, faces[index])
		if not why.is_empty():
			return why if index == 0 or why != NOT_INSIDE and why != NO_WALL else TOO_NARROW
		if index > 0 and grid.segment(SimGrid.edge_between(cell(faces[index - 1]), cell(faces[index]))) != SimGrid.Segment.NONE:
			return CORNER
	return ""


## The face whose (width-face) span is centred nearest to `along_offset`
## (metres from the hovered face's centre, to its right): a wide item hangs
## on the hovered face and the neighbour on the pointer's side.
static func anchor_for(hovered: Vector3i, width: int, along_offset: float) -> Vector3i:
	var shift: int = 0
	if width > 1:
		# Spans starting 0..width-1 faces to the left keep the hovered face.
		var best: float = INF
		for back: int in range(width):
			var centre: float = (float(width - 1) * 0.5 - float(back)) * GridMath.CELL_SIZE
			var distance: float = absf(centre - along_offset)
			if distance < best - 0.0001:
				best = distance
				shift = back
	return make(cell(hovered) - along(hovered) * shift, hovered.z)


static func sort(faces: Array[Vector3i]) -> void:
	faces.sort_custom(before)


## Row-major by floor cell, then direction.
static func before(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.x != b.x:
		return a.x < b.x
	return a.z < b.z
