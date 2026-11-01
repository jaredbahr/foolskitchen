class_name PatioArea
extends RefCounted
## Purchased pavement beside the authored street door. It never becomes part
## of the indoor footprint, moves the shell, or creates another guest entry.

const OUTSIDE_AREA: String = "Choose pavement beside the street door"
const INVALID_CELLS: String = "Invalid patio cells"
const HAS_FURNITURE: String = "Clear the furniture and its seats off that patio first"

var area: Rect2i = Rect2i()
var cell_price: int = 0
var _base: SimGrid
var _outward: Vector2i = Vector2i.DOWN
var _approaches: Dictionary[int, bool] = {}


static func from_layout(layout: ShopLayout) -> PatioArea:
	var patio: PatioArea = PatioArea.new()
	if layout == null:
		return patio
	patio._base = SimGrid.from_ascii(layout.rows)
	patio.cell_price = maxi(0, layout.patio_cell_price)
	var building: Rect2i = ShopFootprint.from_layout(layout).building
	if layout.patio_depth <= 0 or not building.has_area() or patio._base.entries().is_empty():
		return patio
	patio._outward = WallRules.street_side(patio._base)
	var depth: int = layout.patio_depth
	match patio._outward:
		Vector2i.DOWN:
			patio.area = Rect2i(building.position.x, building.end.y, building.size.x, depth)
		Vector2i.UP:
			patio.area = Rect2i(building.position.x, building.position.y - depth, building.size.x, depth)
		Vector2i.RIGHT:
			patio.area = Rect2i(building.end.x, building.position.y, depth, building.size.y)
		Vector2i.LEFT:
			patio.area = Rect2i(building.position.x - depth, building.position.y, depth, building.size.y)
	for entry: Vector2i in patio._base.entries():
		patio._approaches[patio._along(entry)] = true
	return patio


func _along(cell: Vector2i) -> int:
	return cell.x if _outward.y != 0 else cell.y


func can_hold(cell: Vector2i) -> bool:
	return area.has_point(cell) and not _approaches.has(_along(cell)) \
		and _base != null and _base.terrain(cell) == SimGrid.Terrain.OUTSIDE


## All purchasable cells, row-major; the door's public approach stays clear.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if can_hold(cell):
				out.append(cell)
	return out


func problem(bought: Array[Vector2i]) -> String:
	var seen: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in bought:
		if not can_hold(cell):
			return OUTSIDE_AREA
		if seen.has(cell):
			return INVALID_CELLS
		seen[cell] = true
	return ""


## Pure strict snapshot decoder. Version policy belongs to ShopEditor.
func decode(value: Variant, errors: Array[String]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not value is Array or (value as Array).size() > area.get_area():
		errors.append(INVALID_CELLS)
		return out
	for entry: Variant in value:
		if not entry is Array or (entry as Array).size() != 2:
			errors.append(INVALID_CELLS)
			return []
		var row: Array = entry
		for part: Variant in row:
			if not (part is int or part is float) or not is_finite(float(part)) \
					or absf(float(part)) > 100000.0 or floorf(float(part)) != float(part):
				errors.append(INVALID_CELLS)
				return []
		out.append(Vector2i(int(row[0]), int(row[1])))
	var why: String = problem(out)
	if not why.is_empty():
		errors.append(why)
		return []
	return ShopFootprint.sorted(ShopFootprint.to_set(out))


## Replaces patio ownership in one notification. Validate before growing or
## touching terrain, including authored access cells hidden by blocked seats.
## An empty purchase never grows a fresh shop's grid.
func apply(grid: SimGrid, bought: Array[Vector2i]) -> bool:
	if grid == null or not problem(bought).is_empty():
		return false
	var desired: Dictionary[Vector2i, bool] = ShopFootprint.to_set(bought)
	var changes: Dictionary[Vector2i, int] = {}
	var rooms: Dictionary[Vector2i, int] = {}
	var removed: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in grid.rooms():
		if grid.is_outdoor_floor(cell) and not desired.has(cell):
			changes[cell] = SimGrid.Terrain.OUTSIDE
			removed[cell] = true
	var grown: Rect2i = grid.bounds
	for cell: Vector2i in bought:
		if grid.is_outdoor_floor(cell):
			continue
		if grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			return false
		changes[cell] = SimGrid.Terrain.FLOOR
		rooms[cell] = SimGrid.Room.PATIO
		grown = grown.merge(Rect2i(cell, Vector2i.ONE))
	if changes.is_empty():
		return true
	for placed: PlacedItem in grid.items():
		var scope: Array[Vector2i] = placed.cells.duplicate()
		var definition: ItemDef = placed.def as ItemDef
		if definition == null:
			scope.append_array(placed.work_cells)
			scope.append_array(placed.seat_cells)
		else:
			for authored: Vector2i in definition.work_cells + definition.seat_cells:
				scope.append(placed.origin + GridMath.rotate_cell(authored, definition.footprint, placed.quarter_turns))
		for cell: Vector2i in scope:
			if removed.has(cell):
				return false
	var blocked: bool = grid.is_blocking_signals()
	grid.set_block_signals(true)
	grid.grow_to(grown)
	# All refusal conditions were checked above; neither call runs observers.
	var applied: bool = grid.set_terrains(changes)
	if applied:
		applied = grid.set_rooms(rooms)
	grid.set_block_signals(blocked)
	if applied:
		grid.cells_changed.emit(ShopFootprint.sorted(_as_set(changes)))
	return applied


static func _as_set(changes: Dictionary[Vector2i, int]) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in changes:
		out[cell] = true
	return out
