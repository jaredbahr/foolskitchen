class_name ShopFootprint
extends RefCounted
## The building's floor plan (FK-080): the authored starting shell plus the
## floor cells the player bought on the lot. Only the bought cells are stored
## (ShopLayout.floor_cells, the `shop` save); the outer walls are derived from
## them on every change, so they always wrap the floor.
##
## Derivation, all in fixed grid coordinates (nothing is ever shifted):
## - Interior: the authored FLOOR cells and authored interior walls (the
##   kitchen divider). They never change, and interior walls never open:
##   only floor counts for joining and opening up (a doorway is the player's).
## - Bought cells become FLOOR.
## - An authored shell cell with floor on two opposite sides (north and south,
##   or west and east) opens into FLOOR. This repeats, so the inner corner of
##   an L opens too. The room simply grows: no wall is left on the old
##   outline (like a Sims floor extension); the player can build one with the
##   Walls tool. ShopEditor takes down windows and doorways left without a
##   continuing wall when the shell opens; supported wall runs stay intact.
## - A lot cell touching the floor (8 directions) becomes the new shell WALL;
##   any other lot cell is OUTSIDE, unless walls enclose it (a notch): then it
##   fills in as WALL, so no void is left inside the wall mass.
## - Cells outside the lot (the street, the sidewalk, the door) never change,
##   because the lot never grows towards the street.

const NO_LOT: String = "This shop has no room to grow"
const OUTSIDE_LOT: String = "That is outside your lot"
const NOT_JOINED: String = "New floor must join the shop"
const SPLITS: String = "The floor must stay in one piece"
const LEAVES_GAP: String = "That would leave a gap in the floor"
const ONLY_BOUGHT: String = "Only floor you added can be removed"
const ALREADY_BUILT: String = "That floor is already built"
const HAS_FURNITURE: String = "Clear the furniture off that floor first"
const FLOOR_CLOSED: String = "The floor can only be changed in the morning or after closing"

const _SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const _AROUND: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

## Where the building, walls included, may stand.
var lot: Rect2i
## The starting building, shell included (authored FLOOR and WALL cells).
var building: Rect2i
## Price of one bought floor cell.
var cell_price: int = 0

var _base: SimGrid
## Authored floor and interior walls: terrain that never changes.
var _interior: Dictionary[Vector2i, bool] = {}
## Authored FLOOR cells only: what new floor joins and what opens the shell.
var _floor: Dictionary[Vector2i, bool] = {}
## Authored shell cells that may open, row-major (not a divider's end).
var _shell: Array[Vector2i] = []


static func from_layout(layout: ShopLayout) -> ShopFootprint:
	var footprint: ShopFootprint = ShopFootprint.new()
	footprint._base = SimGrid.from_ascii(layout.rows if layout != null else PackedStringArray())
	var first: bool = true
	for cell: Vector2i in footprint._base.cells():
		var t: SimGrid.Terrain = footprint._base.terrain(cell)
		if t != SimGrid.Terrain.FLOOR and t != SimGrid.Terrain.WALL:
			continue
		footprint.building = Rect2i(cell, Vector2i.ONE) if first else footprint.building.merge(Rect2i(cell, Vector2i.ONE))
		first = false
		if t == SimGrid.Terrain.FLOOR:
			footprint._floor[cell] = true
		if t == SimGrid.Terrain.FLOOR or not footprint._touches_outside(cell):
			footprint._interior[cell] = true
		else:
			footprint._shell.append(cell)
	# A shell cell carrying on an interior wall (the divider's end) stays a wall.
	var kept: Array[Vector2i] = []
	for cell: Vector2i in footprint._shell:
		var carries: bool = false
		for side: Vector2i in _SIDES:
			var near: Vector2i = cell + side
			if footprint._interior.has(near) and not footprint._floor.has(near):
				carries = true
		if not carries:
			kept.append(cell)
	footprint._shell = kept
	footprint.lot = footprint.building
	if layout != null and not first:
		var west: int = maxi(layout.lot_west, 0)
		var north: int = maxi(layout.lot_north, 0)
		footprint.lot = Rect2i(footprint.building.position - Vector2i(west, north),
			footprint.building.size + Vector2i(west + maxi(layout.lot_east, 0), north))
		footprint.cell_price = maxi(layout.floor_cell_price, 0)
	return footprint


func has_lot() -> bool:
	return lot != building and building.size != Vector2i.ZERO


## A cell the player may buy: inside the lot (not on its edge, which is kept
## for the wall) and not part of the starting building.
func can_hold(cell: Vector2i) -> bool:
	return lot.grow(-1).has_point(cell) and not building.has_point(cell)


## Where new floor may go: the lot without its outer ring (kept for walls).
## Drawn as the lot outline in Build mode.
func floor_area() -> Rect2i:
	return lot.grow(-1)


## The grid area a built-out shop needs: the authored grid plus the lot.
func grid_bounds() -> Rect2i:
	return _base.bounds.merge(lot)


## Cells in `rect` inside the lot but outside the starting building, row-major.
func lot_cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if lot.has_point(cell) and not building.has_point(cell):
				out.append(cell)
	return out


## Derived terrain (cell -> SimGrid.Terrain) of every cell in grid_bounds()
## for this set of bought cells. Cells must be valid (see problem()).
func terrain_for(bought: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, int]:
	var inside: Dictionary[Vector2i, bool] = _inside(bought)
	var result: Dictionary[Vector2i, int] = {}
	var area: Rect2i = grid_bounds()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if inside.has(cell) and not _interior.has(cell):
				result[cell] = SimGrid.Terrain.FLOOR
			elif lot.has_point(cell) and not building.has_point(cell):
				result[cell] = SimGrid.Terrain.WALL if _touches(cell, inside) else SimGrid.Terrain.OUTSIDE
			else:
				result[cell] = _base.terrain(cell)
	_fill_enclosed(result, area)
	return result


## A lot cell left OUTSIDE but cut off from the world beyond by walls (a notch
## between wall runs) joins the wall mass: it becomes WALL, never a void.
func _fill_enclosed(result: Dictionary[Vector2i, int], area: Rect2i) -> void:
	var around: Rect2i = area.grow(1)
	var open: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for y: int in range(around.position.y, around.end.y):
		for x: int in range(around.position.x, around.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if not area.has_point(cell):
				open[cell] = true
				frontier.append(cell)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for side: Vector2i in _SIDES:
				var near: Vector2i = cell + side
				if area.has_point(near) and not open.has(near) and result[near] == SimGrid.Terrain.OUTSIDE:
					open[near] = true
					next.append(near)
		frontier = next
	for cell: Vector2i in result:
		if result[cell] == SimGrid.Terrain.OUTSIDE and not open.has(cell) \
				and lot.has_point(cell) and not building.has_point(cell):
			result[cell] = SimGrid.Terrain.WALL


## Why this set of bought cells is not a valid floor plan, or "".
## `adding` picks the sentence for a floor that no longer joins up.
func problem(bought: Dictionary[Vector2i, bool], adding: bool = true) -> String:
	if not has_lot():
		return NO_LOT if not bought.is_empty() else ""
	for cell: Vector2i in bought:
		if not can_hold(cell):
			return OUTSIDE_LOT
	var inside: Dictionary[Vector2i, bool] = _inside(bought)
	# Joined: every bought cell is reachable from the starting room.
	var seen: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in _floor:
		seen[cell] = true
		frontier.append(cell)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for side: Vector2i in _SIDES:
				var near: Vector2i = cell + side
				if inside.has(near) and not seen.has(near):
					seen[near] = true
					next.append(near)
		frontier = next
	for cell: Vector2i in bought:
		if not seen.has(cell):
			return NOT_JOINED if adding else SPLITS
	# No gaps: every cell outside the floor connects to the world beyond.
	# Authored interior walls are neither floor nor gap.
	for cell: Vector2i in _interior:
		inside[cell] = true
	var area: Rect2i = grid_bounds().grow(1)
	var open: Dictionary[Vector2i, bool] = {}
	frontier.clear()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if (x == area.position.x or y == area.position.y or x == area.end.x - 1 or y == area.end.y - 1) \
					and not inside.has(cell):
				open[cell] = true
				frontier.append(cell)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for side: Vector2i in _SIDES:
				var near: Vector2i = cell + side
				if area.has_point(near) and not inside.has(near) and not open.has(near):
					open[near] = true
					next.append(near)
		frontier = next
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell: Vector2i = Vector2i(x, y)
			# Authored walls left standing (a divider's end) are walls, not gaps.
			if not inside.has(cell) and not open.has(cell) and not building.has_point(cell):
				return LEAVES_GAP
	return ""


## Sets a grid's terrain to this floor plan with one cells_changed. Grows the
## grid to the lot first when bought cells need it. False when set_terrains
## refuses (an item would be left off the floor); the grid may then be grown.
func apply(grid: SimGrid, bought: Dictionary[Vector2i, bool]) -> bool:
	if not bought.is_empty():
		grid.grow_to(grid_bounds())
	var all: Dictionary[Vector2i, int] = terrain_for(bought)
	var changes: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in all:
		if grid.in_bounds(cell) and grid.terrain(cell) != all[cell]:
			changes[cell] = all[cell]
	return grid.set_terrains(changes)


static func to_set(cells: Array[Vector2i]) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		out[cell] = true
	return out


static func sorted(cells: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(cells.keys())
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## Authored floor, bought and opened shell cells (not interior walls).
func _inside(bought: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
	var inside: Dictionary[Vector2i, bool] = _floor.duplicate()
	for cell: Vector2i in bought:
		inside[cell] = true
	if bought.is_empty():
		return inside
	var changed: bool = true
	while changed:
		changed = false
		for cell: Vector2i in _shell:
			if inside.has(cell):
				continue
			if (inside.has(cell + Vector2i.UP) and inside.has(cell + Vector2i.DOWN)) \
					or (inside.has(cell + Vector2i.LEFT) and inside.has(cell + Vector2i.RIGHT)):
				inside[cell] = true
				changed = true
	return inside


func _touches_outside(cell: Vector2i) -> bool:
	for step: Vector2i in _AROUND:
		var t: SimGrid.Terrain = _base.terrain(cell + step)
		if not _base.in_bounds(cell + step) or t == SimGrid.Terrain.OUTSIDE or t == SimGrid.Terrain.ENTRY:
			return true
	return false


static func _touches(cell: Vector2i, inside: Dictionary[Vector2i, bool]) -> bool:
	for step: Vector2i in _AROUND:
		if inside.has(cell + step):
			return true
	return false
