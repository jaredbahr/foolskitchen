class_name WallRules
extends RefCounted
## Where wall segments may stand (FK-070), and every refusal sentence the
## player sees for them. Read-only queries over a SimGrid; no mutation.
##
## Edges come in two kinds, both computed from terrain each time, never stored:
## - interior: FLOOR on both sides. Wall, doorway or window.
## - outer face: FLOOR on one side, a shell WALL cell on the other with the
##   street/outside (or the grid border) beyond it. Window only; "removing"
##   it restores the solid shell. Its side is the direction from the floor
##   into the wall. At least one face per side stays solid.
## Because this is derived from terrain, an expansion that turns shell cells
## into floor turns their faces' windows into interior windows automatically.

const NOT_INSIDE: String = "Walls must stand inside the shop"
const DOOR_FIXED: String = "The street door stays as it is"
const OUTER_WINDOW_ONLY: String = "Only windows fit in an outside wall"
const THROUGH_FURNITURE: String = "A wall can't cut through furniture"
const BLOCKS_ACCESS: String = "That would block a seat or work spot"
const KEEP_SOLID_SIDE: String = "Keep some solid wall on every side"
const NOTHING_HERE: String = "There is no wall here"
const CUT_DOOR: String = "That would cut off the door"
const CUT_SINK: String = "That would cut off the sink"
const CUT_STATION: String = "That would cut off a kitchen station"
const CUT_SEAT: String = "That would cut off a seat"
const CUT_PERSON: String = "That would shut someone in"


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
		return "" if kind == SimGrid.Segment.WINDOW else OUTER_WINDOW_ONLY
	return NOT_INSIDE


## Whole-shop checks after a proposed change has been applied to `grid`.
static func layout_problem(grid: SimGrid) -> String:
	for placed: PlacedItem in grid.items():
		if item_walled_off(grid, placed):
			return BLOCKS_ACCESS
	var faces: Dictionary[Vector2i, int] = {}
	var windows: Dictionary[Vector2i, int] = {}
	for y: int in range(grid.size.y):
		for x: int in range(grid.size.x):
			for edge: Vector3i in [Vector3i(x, y, SimGrid.EDGE_WEST), Vector3i(x, y, SimGrid.EDGE_NORTH)]:
				var side: Vector2i = outer_side(grid, edge)
				if side == Vector2i.ZERO:
					continue
				faces[side] = faces.get(side, 0) + 1
				if grid.segment(edge) == SimGrid.Segment.WINDOW:
					windows[side] = windows.get(side, 0) + 1
	for side: Vector2i in windows:
		if windows[side] >= faces[side]:
			return KEEP_SOLID_SIDE
	return ""


## A wall or window between an item and one of its authored work/seat cells.
static func item_walled_off(grid: SimGrid, placed: PlacedItem) -> bool:
	var definition: ItemDef = placed.def as ItemDef
	if definition == null or not grid.has_segments():
		return false
	var access: Array[Vector2i] = []
	for authored: Vector2i in definition.work_cells + definition.seat_cells:
		access.append(placed.origin + GridMath.rotate_cell(authored, definition.footprint, placed.quarter_turns))
	return grid.access_walled_off(placed.cells, access)


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


## The first thing a change would newly cut off from the street, or "".
## `after` has the same items in the same order as `before` (an edit preview).
## Something already unreachable before the change never blocks it.
static func cut_off_problem(before: SimGrid, after: SimGrid, people: Array[Vector2i]) -> String:
	var was: Dictionary[Vector2i, bool] = reachable(before)
	var now: Dictionary[Vector2i, bool] = reachable(after)
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
