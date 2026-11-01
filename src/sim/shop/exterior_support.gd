class_name ExteriorSupport
extends RefCounted
## Street-facing supports. Old room/window keys stay untouched; new exterior
## bands occupy distinct z lanes while x/y always denotes the outside cell.

enum Band { BODY, CANOPY, HEADER, SILL, LIGHTS }
const MAX_KEY_DIRECTION: int = 19
const STREET_ONLY: String = "Choose the outside of the street front"
const SOLID_ONLY: String = "Choose a solid street-facing wall"
const OPENING_ONLY: String = "Hang this above a street door or window"
const DOOR_ONLY: String = "Hang this above the street door"
const WINDOW_ONLY: String = "Hang this below a street-facing window"
const TOO_NARROW: String = "Not enough street-facing wall here"
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func key_for(face: Vector3i, mount_band: int) -> Vector3i:
	return Vector3i(face.x, face.y, posmod(face.z, 4) + 4 * mount_band)


static func base_face(key: Vector3i) -> Vector3i:
	return key_for(key, Band.BODY)


@warning_ignore("integer_division")
static func band(key: Vector3i) -> int:
	return key.z / 4


static func shell_cell(key: Vector3i) -> Vector2i:
	return Vector2i(key.x, key.y) + DIRS[posmod(key.z, 4)]


static func is_exterior(grid: SimGrid, key: Vector3i) -> bool:
	if grid == null or key.z < 0 or key.z > MAX_KEY_DIRECTION or grid.entries().is_empty():
		return false
	var into: Vector2i = DIRS[posmod(key.z, 4)]
	if into != -WallRules.street_side(grid):
		return false
	var outside: Vector2i = Vector2i(key.x, key.y)
	if grid.terrain(outside) not in [SimGrid.Terrain.OUTSIDE, SimGrid.Terrain.ENTRY]:
		return false
	var shell: Vector2i = shell_cell(key)
	var doors: Array[Vector2i] = door_cells(grid)
	if doors.is_empty() or _axis_value(shell, into) != _axis_value(doors[0], into):
		return false
	if doors.has(shell):
		return true
	return grid.terrain(shell) == SimGrid.Terrain.WALL \
		and grid.terrain(shell + into) == SimGrid.Terrain.FLOOR


static func finish_problem(grid: SimGrid, key: Vector3i) -> String:
	if not is_exterior(grid, key) or band(key) != Band.BODY:
		return STREET_ONLY
	var shell: Vector2i = shell_cell(key)
	if grid.terrain(shell) != SimGrid.Terrain.WALL or WallFaces.shell_cut(grid, shell):
		return SOLID_ONLY
	return ""


static func span_problem(grid: SimGrid, key: Vector3i, width: int) -> String:
	if width < 1 or width > ItemDef.MAX_WALL_WIDTH or not is_exterior(grid, key):
		return STREET_ONLY
	var into: Vector2i = DIRS[posmod(key.z, 4)]
	var along: Vector2i = DIRS[posmod(key.z + 1, 4)]
	var windows: Array[Vector2i] = window_cells(grid)
	var doors: Array[Vector2i] = door_cells(grid)
	var has_window: bool = false
	var has_door: bool = false
	for index: int in width:
		var face: Vector3i = Vector3i(key.x + along.x * index, key.y + along.y * index, key.z)
		if not is_exterior(grid, face):
			return TOO_NARROW
		var shell: Vector2i = shell_cell(face)
		has_window = has_window or windows.has(shell)
		has_door = has_door or doors.has(shell)
		if band(key) == Band.BODY and not finish_problem(grid, base_face(face)).is_empty():
			return SOLID_ONLY
		# All supports share the same facade plane. Never turn a corner.
		if _axis_value(shell - shell_cell(key), into) != 0:
			return TOO_NARROW
	match band(key):
		Band.CANOPY:
			return "" if has_window or has_door else OPENING_ONLY
		Band.HEADER:
			return "" if has_door else DOOR_ONLY
		Band.SILL:
			return "" if has_window else WINDOW_ONLY
	return ""


## The fixed street door's shell/gap cells (the starter entries lie one row
## beyond its floor threshold; embedded entries already occupy the shell row).
static func door_cells(grid: SimGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid == null:
		return out
	var outward: Vector2i = WallRules.street_side(grid)
	var into: Vector2i = -outward
	var entries: Array[Vector2i] = grid.entries()
	if entries.is_empty():
		return out
	var frontage: Array[Vector2i] = _dressed_cells(grid, entries, outward)
	var plane: int = _axis_value(frontage[0], outward) if not frontage.is_empty() else _axis_value(entries[0], outward)
	for entry: Vector2i in entries:
		var depth: int = _axis_value(entry, outward) - plane
		if depth < 0 or depth > 1:
			continue
		var shell: Vector2i = entry + into * depth
		if not out.has(shell):
			out.append(shell)
	return out


## Real player windows plus the unchanged two decorative frontage panes.
## Mirrors RoomDressing's bounded window selection without any scene dependency.
static func window_cells(grid: SimGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid == null or grid.entries().is_empty():
		return out
	var outward: Vector2i = WallRules.street_side(grid)
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) != SimGrid.Segment.WINDOW or WallRules.outer_side(grid, edge) != outward:
			continue
		for cell: Vector2i in SimGrid.edge_cells(edge):
			if grid.terrain(cell) == SimGrid.Terrain.WALL and not out.has(cell):
				out.append(cell)
	var selected: int = 0
	var attached: Dictionary[Vector2i, bool] = {}
	for entrance: Array[Vector2i] in _entrances(grid, outward):
		for cell: Vector2i in _dressed_cells(grid, entrance, outward):
			if attached.has(cell):
				continue
			attached[cell] = true
			if selected < 2:
				if not out.has(cell):
					out.append(cell)
				selected += 1
	return out


static func _entrances(grid: SimGrid, outward: Vector2i) -> Array[Array]:
	var out: Array[Array] = []
	var remaining: Dictionary[Vector2i, bool] = {}
	for entry: Vector2i in grid.entries():
		remaining[entry] = true
	var along: Vector2i = Vector2i(-outward.y, outward.x)
	for entry: Vector2i in grid.entries():
		if not remaining.has(entry):
			continue
		var run: Array[Vector2i] = [entry]
		remaining.erase(entry)
		for sign_value: int in [-1, 1]:
			var next: Vector2i = entry + along * sign_value
			while remaining.has(next):
				run.append(next)
				remaining.erase(next)
				next += along * sign_value
		out.append(run)
	return out


static func _dressed_cells(grid: SimGrid, entries: Array[Vector2i], outward: Vector2i) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for depth: int in [0, 1]:
		var plane: int = _axis_value(entries[0] - outward * depth, outward)
		for cell: Vector2i in grid.cells():
			if _axis_value(cell, outward) == plane and grid.terrain(cell) == SimGrid.Terrain.WALL \
					and grid.terrain(cell - outward) == SimGrid.Terrain.FLOOR \
					and grid.terrain(cell + outward) in [SimGrid.Terrain.OUTSIDE, SimGrid.Terrain.ENTRY]:
				candidates.append(cell)
		if not candidates.is_empty():
			break
	var out: Array[Vector2i] = []
	while not candidates.is_empty() and out.size() < 4:
		var best: int = 0
		for index: int in range(1, candidates.size()):
			if _entry_distance(candidates[index], entries) < _entry_distance(candidates[best], entries):
				best = index
		out.append(candidates[best])
		candidates.remove_at(best)
	return out


static func _entry_distance(cell: Vector2i, entries: Array[Vector2i]) -> int:
	var result: int = 1000000
	for entry: Vector2i in entries:
		result = mini(result, absi(cell.x - entry.x) + absi(cell.y - entry.y))
	return result


static func _axis_value(cell: Vector2i, axis: Vector2i) -> int:
	return cell.x * axis.x + cell.y * axis.y
