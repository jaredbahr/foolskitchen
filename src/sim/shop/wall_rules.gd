class_name WallRules
extends RefCounted
## Where wall segments may stand (FK-070), and every refusal sentence the
## player sees for them. Read-only queries over a SimGrid; no mutation.
##
## Edges come in two kinds, both computed from terrain each time, never stored:
## - interior: FLOOR on both sides. Wall, doorway or window.
## - outer face: FLOOR on one side, a shell WALL cell on the other with the
##   street/outside (or the grid border) beyond it. Window or back doorway; "removing"
##   it restores the solid shell. Its side is the direction from the floor
##   into the wall. Back doors exclude the street-facing side. At least one
##   face per side stays solid.
## Because this is derived from terrain, an expansion that turns shell cells
## into floor turns their faces' windows into interior windows automatically.

const NOT_INSIDE: String = "Walls must stand inside the shop"
const DOOR_FIXED: String = "The street door stays as it is"
const OUTER_WINDOW_ONLY: String = "Choose a window or a back door for an outside wall"
const BACK_OR_SIDE: String = "Back doors go on the back or side of the shop"
const THROUGH_FURNITURE: String = "A wall can't cut through furniture"
const BLOCKS_ACCESS: String = "That would block a work spot"
const KEEP_SOLID_SIDE: String = "Keep some solid wall on every side"
const NOTHING_HERE: String = "There is no wall here"
const CUT_DOOR: String = "That would cut off the door"
const CUT_SINK: String = "That would cut off the sink"
const CUT_STATION: String = "That would cut off a kitchen station"
const CUT_SEAT: String = "That would cut off a seat"
const CUT_PERSON: String = "That would shut someone in"
const ONE_BACK_DOOR: String = "The shop already has a back door: remove it first to move it"


static func is_interior(grid: SimGrid, edge: Vector3i) -> bool:
	if not grid.edge_in_bounds(edge):
		return false
	for cell: Vector2i in SimGrid.edge_cells(edge):
		if grid.terrain(cell) != SimGrid.Terrain.FLOOR:
			return false
	return true


## Direction from the floor cell into the shell wall cell, or ZERO when the
## edge is not an outer face.
static func outer_side(grid: SimGrid, edge: Vector3i) -> Vector2i:
	if not grid.edge_in_bounds(edge):
		return Vector2i.ZERO
	var cells: Array[Vector2i] = SimGrid.edge_cells(edge)
	for index: int in 2:
		var floor_cell: Vector2i = cells[index]
		var wall_cell: Vector2i = cells[1 - index]
		if grid.terrain(floor_cell) != SimGrid.Terrain.FLOOR or grid.terrain(wall_cell) != SimGrid.Terrain.WALL:
			continue
		var side: Vector2i = wall_cell - floor_cell
		var beyond: Vector2i = wall_cell + side
		var beyond_terrain: SimGrid.Terrain = grid.terrain(beyond)
		if not grid.in_bounds(beyond) or beyond_terrain == SimGrid.Terrain.OUTSIDE \
				or beyond_terrain == SimGrid.Terrain.ENTRY:
			return side
	return Vector2i.ZERO


## Floor cells that form the street door: the threshold next to street entry
## cells and any door item. Segments never touch them.
static func door_cells(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for entry: Vector2i in grid.entries():
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if grid.terrain(entry + step) == SimGrid.Terrain.FLOOR:
				cells[entry + step] = true
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition != null and definition.category == ItemDef.Category.DOOR:
			for cell: Vector2i in placed.cells:
				cells[cell] = true
	return cells


## A delivery entrance must face away from the street frontage. Derived from
## entry terrain, so rotated layouts and floor expansions keep their identity.
## Assumption: the street side is the side the ENTRY cells sit on, found by
## stepping from an entry against `side` onto FLOOR (the street door's
## threshold). It holds while every entry is a street cell directly outside the
## shell on one side; a layout with entries on two sides would refuse back
## doors on both, and one whose entries do not touch floor would allow a door
## on the street side. Revisit if layouts gain such entries.
static func back_door_side(grid: SimGrid, edge: Vector3i) -> Vector2i:
	var side: Vector2i = outer_side(grid, edge)
	if side == Vector2i.ZERO:
		return Vector2i.ZERO
	for entry: Vector2i in grid.entries():
		if grid.terrain(entry - side) == SimGrid.Terrain.FLOOR:
			return Vector2i.ZERO
	return side


## Receiving cell inside a reachable back door, or the existing street entry.
## No RNG, new customer spawn points or stock mutation. A target lets carrying
## choose an entrance from which its storage can actually be reached.
static func delivery_cell(grid: SimGrid, target: Vector2i = SimGrid.NO_CELL) -> Vector2i:
	var reach: Dictionary[Vector2i, bool] = reachable(grid)
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) != SimGrid.Segment.DOORWAY:
			continue
		var side: Vector2i = back_door_side(grid, edge)
		if side == Vector2i.ZERO:
			continue
		for cell: Vector2i in SimGrid.edge_cells(edge):
			if grid.terrain(cell) == SimGrid.Terrain.FLOOR and reach.has(cell) \
					and (target == SimGrid.NO_CELL or not grid.find_path(cell, target).is_empty()):
				return cell
	for entry: Vector2i in grid.entries():
		if grid.is_walkable(entry) and (target == SimGrid.NO_CELL or not grid.find_path(entry, target).is_empty()):
			return entry
	return SimGrid.NO_CELL


## Off-lot cells a delivery walks up a back door's path (the view paves them).
const APPROACH_CELLS: int = 4


## How a visible delivery comes in (FK-099, #187): {door, drop, out, approach}.
## `door` is where the delivery person steps onto the grid (the back door's
## shell cell, or the street entry when there is no usable back door), `drop`
## the receiving cell inside where the crates go down (the cell delivery_cell
## picks; for the street, the floor cell inside the street door), `out` the
## direction from `door` away from the shop and `approach` the outside cells
## walked to reach the door, far to near: a back door's path
## (back_door_approach); none at the street, where people appear at the entry
## as guests do. Empty when no route reaches `target`.
static func delivery_route(grid: SimGrid, target: Vector2i = SimGrid.NO_CELL) -> Dictionary:
	var cell: Vector2i = delivery_cell(grid, target)
	if cell == SimGrid.NO_CELL:
		return {}
	var none: Array[Vector2i] = []
	if grid.entries().has(cell):
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var inside: Vector2i = cell + step
			if grid.terrain(inside) == SimGrid.Terrain.FLOOR and grid.is_walkable(inside) \
					and grid.step_open(cell, inside) \
					and (target == SimGrid.NO_CELL or not grid.find_path(inside, target).is_empty()):
				return {"door": cell, "drop": inside, "out": -step, "approach": none}
		return {"door": cell, "drop": cell, "out": Vector2i.ZERO, "approach": none}
	for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var door: Vector2i = cell + step
		if grid.is_back_door(door) and grid.step_open(cell, door) \
				and back_door_side(grid, SimGrid.edge_between(cell, door)) == step:
			return {"door": door, "drop": cell, "out": step, "approach": back_door_approach(grid, door, step)}
	return {}


## The path outside a back door (shell cell `door`, facing `side`), far to
## near: up to APPROACH_CELLS cells straight out, stopping before anything but
## open ground (unbought lot or beyond the grid), so it never crosses a wing
## of the shop or the street.
static func back_door_approach(grid: SimGrid, door: Vector2i, side: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for step: int in range(1, APPROACH_CELLS + 1):
		var cell: Vector2i = door + side * step
		if grid.in_bounds(cell) and grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			break
		cells.push_front(cell)
	return cells


## Back doors on the grid (FK-099): DOORWAY segments on an outer back or side
## face. D25 allows one per shop; older saves with more keep them all.
static func back_door_count(grid: SimGrid) -> int:
	var count: int = 0
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) == SimGrid.Segment.DOORWAY and back_door_side(grid, edge) != Vector2i.ZERO:
			count += 1
	return count


## ONE_BACK_DOOR when an edit (`before` -> `after`) adds a back door to a shop
## that already has one (D25), else "". Only adding is refused, so an older
## save with two keeps both and every other edit still works.
static func back_door_problem(before: SimGrid, after: SimGrid) -> String:
	var now: int = back_door_count(after)
	return ONE_BACK_DOOR if now > 1 and now > back_door_count(before) else ""


## Why `kind` cannot stand on `edge` (geometry only), or "" when it can.
static func edge_problem(grid: SimGrid, edge: Vector3i, kind: SimGrid.Segment) -> String:
	if not grid.edge_in_bounds(edge):
		return NOT_INSIDE
	var doors: Dictionary[Vector2i, bool] = door_cells(grid)
	for cell: Vector2i in SimGrid.edge_cells(edge):
		if doors.has(cell):
			return DOOR_FIXED
	if kind == SimGrid.Segment.NONE:
		return "" if grid.segment(edge) != SimGrid.Segment.NONE else NOTHING_HERE
	if is_interior(grid, edge):
		var cells: Array[Vector2i] = SimGrid.edge_cells(edge)
		for layer: ItemDef.PlacementLayer in [ItemDef.PlacementLayer.NORMAL, ItemDef.PlacementLayer.FLOOR_DECOR]:
			var first: PlacedItem = grid.item_on_layer(cells[0], layer)
			if first != null and first == grid.item_on_layer(cells[1], layer):
				return THROUGH_FURNITURE
		return ""
	if outer_side(grid, edge) != Vector2i.ZERO:
		if kind == SimGrid.Segment.DOORWAY:
			return "" if back_door_side(grid, edge) != Vector2i.ZERO else BACK_OR_SIDE
		return "" if kind == SimGrid.Segment.WINDOW else OUTER_WINDOW_ONLY
	return NOT_INSIDE


## Whole-shop checks after a proposed change has been applied to `grid`.
static func layout_problem(grid: SimGrid) -> String:
	for placed: PlacedItem in grid.items():
		if item_walled_off(grid, placed):
			return BLOCKS_ACCESS
	var faces: Dictionary[Vector2i, int] = {}
	var windows: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in grid.cells():
		for edge: Vector3i in [Vector3i(cell.x, cell.y, SimGrid.EDGE_WEST), Vector3i(cell.x, cell.y, SimGrid.EDGE_NORTH)]:
			var side: Vector2i = outer_side(grid, edge)
			if side == Vector2i.ZERO:
				continue
			faces[side] = faces.get(side, 0) + 1
			if grid.segment(edge) in [SimGrid.Segment.WINDOW, SimGrid.Segment.DOORWAY]:
				windows[side] = windows.get(side, 0) + 1
	for side: Vector2i in windows:
		if windows[side] >= faces[side]:
			return KEEP_SOLID_SIDE
	return ""


## A wall or window between an item and one of its authored work cells.
## Seats are not refused here: a table's built-in seat across a wall is simply
## dropped (DiningSeats.WALLED_OFF), and a chair's link to its table is checked
## by EditCheck.validate_dining, so tables can stand flush against a wall.
static func item_walled_off(grid: SimGrid, placed: PlacedItem) -> bool:
	var definition: ItemDef = placed.def as ItemDef
	if definition == null or not grid.has_segments():
		return false
	return grid.access_walled_off(placed.cells, work_cells(placed))


## An item's work cells on the grid.
static func work_cells(placed: PlacedItem) -> Array[Vector2i]:
	var access: Array[Vector2i] = []
	var definition: ItemDef = placed.def as ItemDef
	if definition == null:
		return access
	for authored: Vector2i in definition.work_cells:
		access.append(placed.origin + GridMath.rotate_cell(authored, definition.footprint, placed.quarter_turns))
	return access


## BLOCKS_ACCESS when closing a back door (on `before`, gone on `after`) would
## wall up the work cell an item uses in its opening, else "".
static func closed_door_problem(before: SimGrid, after: SimGrid) -> String:
	for placed: PlacedItem in after.items():
		for cell: Vector2i in work_cells(placed):
			if before.is_back_door(cell) and not after.is_back_door(cell):
				return BLOCKS_ACCESS
	return ""


## Cells reachable on foot from any street entry.
static func reachable(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for entry: Vector2i in grid.entries():
		if grid.is_walkable(entry) and not seen.has(entry):
			seen[entry] = true
			frontier.append(entry)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for neighbour: Vector2i in grid.walkable_neighbours(cell):
				if not seen.has(neighbour):
					seen[neighbour] = true
					next.append(neighbour)
		frontier = next
	return seen


## The first thing a change would cut off from the street, or "".
## `after` has the same items in the same order as `before` (an edit preview).
## Two passes. Walls only (furniture ignored): a wall edit may never seal a
## target in, even when furniture happens to block it today, because that
## furniture can be moved or sold later and the seal would remain. Then with
## furniture: a change may not newly cut off something reachable right now;
## things furniture already blocks stay furniture warnings.
## `people_only` (undo/redo, FK-085) checks only the people: a restored layout
## was already accepted, unusable seats or stations included.
static func cut_off_problem(before: SimGrid, after: SimGrid, people: Array[Vector2i],
		people_only: bool = false) -> String:
	var problem: String = _cut_off(after, reachable(walls_only(before)), reachable(walls_only(after)), people, people_only)
	if problem.is_empty():
		problem = _cut_off(after, reachable(before), reachable(after), people, people_only)
	return problem


## Terrain and segments of `grid`, with no furniture.
static func walls_only(grid: SimGrid) -> SimGrid:
	var copy: SimGrid = grid.terrain_copy()
	var segments: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in grid.segment_edges():
		segments[edge] = grid.segment(edge)
	copy.set_segments(segments)
	return copy


static func _cut_off(after: SimGrid, was: Dictionary[Vector2i, bool], now: Dictionary[Vector2i, bool],
		people: Array[Vector2i], people_only: bool = false) -> String:
	if people_only:
		for cell: Vector2i in people:
			if _lost([cell] as Array[Vector2i], was, now):
				return CUT_PERSON
		return ""
	var door: Array[Vector2i] = []
	door.assign(door_cells(after).keys())
	if _lost(door, was, now):
		return CUT_DOOR
	var groups: Array[Array] = [[], [], []]
	for placed: PlacedItem in after.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null:
			continue
		match definition.category:
			ItemDef.Category.STATION, ItemDef.Category.STORAGE:
				groups[0 if definition.station_type == &"sink" else 1].append(placed.work_cells)
			ItemDef.Category.PASS:
				for index: int in range(mini(2, placed.work_cells.size())):
					groups[1].append([placed.work_cells[index]] as Array[Vector2i])
			ItemDef.Category.TABLE:
				for seat: Vector2i in placed.seat_cells:
					groups[2].append([seat] as Array[Vector2i])
	# When nothing that was reachable stays reachable, the street door itself
	# has been boxed in, so name the door rather than the first station.
	var lost: Array[String] = []
	var kept: bool = false
	var reasons: Array[String] = [CUT_SINK, CUT_STATION, CUT_SEAT]
	for index: int in groups.size():
		for cells: Array in groups[index]:
			var typed: Array[Vector2i] = []
			typed.assign(cells)
			if _lost(typed, was, now):
				lost.append(reasons[index])
			elif _any(typed, now):
				kept = true
	if not lost.is_empty():
		return lost[0] if kept else CUT_DOOR
	for cell: Vector2i in people:
		if _lost([cell] as Array[Vector2i], was, now):
			return CUT_PERSON
	return ""


static func _any(cells: Array[Vector2i], reach: Dictionary[Vector2i, bool]) -> bool:
	for cell: Vector2i in cells:
		if reach.has(cell):
			return true
	return false


## Some of these cells was reachable before and none of them is now.
static func _lost(cells: Array[Vector2i], was: Dictionary[Vector2i, bool], now: Dictionary[Vector2i, bool]) -> bool:
	var before: bool = false
	for cell: Vector2i in cells:
		if now.has(cell):
			return false
		if was.has(cell):
			before = true
	return before
