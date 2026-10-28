class_name FloorFinishes
extends RefCounted
## The floor's look per cell (D25): a floor type (FloorStyleDef id), a main
## colour and an accent colour (SwatchDef ids). Looks only: owned by
## ShopEditor, never by SimGrid, so paths, seats and every sim rule ignore it.
##
## Only cells that differ from the shop default are stored. The default is the
## free wide planks in the shop's own floor colour (the legacy whole-shop floor
## paint, empty for the authored brown), so an older shop with no stored cells
## looks exactly as it always did, and new floor starts as the default.

## `cells` changed look (default cells too when the default changed).
signal changed(cells: Array[Vector2i])

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


## One cell's look. Values compare with same(); never mutate a shared one.
class Finish extends RefCounted:
	var style: StringName = &""
	var swatch: StringName = &""
	var accent: StringName = &""

	func _init(style_id: StringName = &"", swatch_id: StringName = &"", accent_id: StringName = &"") -> void:
		style = style_id
		swatch = swatch_id
		accent = accent_id

	func same(other: Finish) -> bool:
		return other != null and style == other.style and swatch == other.swatch and accent == other.accent

	## The same floor type with another main colour (a recolour).
	func recoloured(swatch_id: StringName) -> Finish:
		return Finish.new(style, swatch_id, accent)

	func _to_string() -> String:
		return "%s/%s/%s" % [style, swatch, accent]


var default_style: StringName = FloorStyleDef.DEFAULT_ID
## The shop's own floor colour (ShopEditor.floor_swatch_id); empty = authored brown.
var default_swatch: StringName = &""
## Bumped on every `changed`, so callers can cache derived areas against it.
var revision: int = 0
var _cells: Dictionary[Vector2i, Finish] = {}
## One shared default look, so reading a default cell allocates nothing.
var _default: Finish


func _init(style_id: StringName = FloorStyleDef.DEFAULT_ID, swatch_id: StringName = &"") -> void:
	default_style = style_id
	default_swatch = swatch_id
	_default = Finish.new(default_style, default_swatch, &"")


## The shared default look (never mutate it; it is replaced when the default
## colour changes).
func default_finish() -> Finish:
	return _default


## The cell's look: stored, else the default (any cell, floor or not).
func finish(cell: Vector2i) -> Finish:
	return _cells[cell] if _cells.has(cell) else default_finish()


func is_default(cell: Vector2i) -> bool:
	return not _cells.has(cell)


## Cells with a stored (non-default) look, row-major.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_cells.keys())
	out.sort_custom(_row_major)
	return out


func count() -> int:
	return _cells.size()


## The current look of each given cell (defaults included), for undo history.
func snapshot(cells_wanted: Array[Vector2i]) -> Dictionary[Vector2i, Finish]:
	var out: Dictionary[Vector2i, Finish] = {}
	for cell: Vector2i in cells_wanted:
		out[cell] = finish(cell)
	return out


## Applies looks (cell -> Finish); a default look clears the cell. One
## `changed` for the cells whose look really changed. Returns those cells.
func set_finishes(changes: Dictionary[Vector2i, Finish]) -> Array[Vector2i]:
	var touched: Array[Vector2i] = []
	var base: Finish = default_finish()
	for cell: Vector2i in changes:
		var next: Finish = changes[cell]
		if next == null or finish(cell).same(next):
			continue
		if next.same(base):
			_cells.erase(cell)
		else:
			_cells[cell] = Finish.new(next.style, next.swatch, next.accent)
		touched.append(cell)
	if not touched.is_empty():
		touched.sort_custom(_row_major)
		revision += 1
		changed.emit(touched)
	return touched


## Forgets the looks of `dropped` cells (floor that was taken away).
func drop(dropped: Array[Vector2i]) -> Array[Vector2i]:
	var touched: Array[Vector2i] = []
	for cell: Vector2i in dropped:
		if _cells.erase(cell):
			touched.append(cell)
	if not touched.is_empty():
		touched.sort_custom(_row_major)
		revision += 1
		changed.emit(touched)
	return touched


## A new shop colour for every default cell (the legacy whole-floor paint).
## Stored cells that now match the default stop being stored.
func set_default_swatch(swatch_id: StringName) -> void:
	if swatch_id == default_swatch:
		return
	default_swatch = swatch_id
	_default = Finish.new(default_style, default_swatch, &"")
	var base: Finish = default_finish()
	for cell: Vector2i in _cells.keys():
		if _cells[cell].same(base):
			_cells.erase(cell)
	revision += 1
	changed.emit([] as Array[Vector2i])


## Save rows [x, y, style, swatch, accent], row-major (shop snapshot v5).
func to_rows() -> Array[Array]:
	var rows: Array[Array] = []
	for cell: Vector2i in cells():
		var look: Finish = _cells[cell]
		rows.append([cell.x, cell.y, String(look.style), String(look.swatch), String(look.accent)])
	return rows


## Every floor cell of the room holding `cell`: orthogonal steps over floor of
## the same SimGrid.Room that cross no wall segment of any kind (a doorway or
## window ends the room too). Row-major; empty when `cell` is not floor.
static func room_cells(grid: SimGrid, cell: Vector2i) -> Array[Vector2i]:
	if grid == null or grid.terrain(cell) != SimGrid.Terrain.FLOOR:
		return []
	var room: int = grid.room(cell)
	return _flood(grid, cell, func(next: Vector2i) -> bool: return grid.room(next) == room)


## The connected area of `cell`'s look inside its room: orthogonal steps over
## floor with the same look and the same SimGrid.Room that cross no wall
## segment, so a paint click stops at room edges (an open pass into the
## kitchen too). Row-major; empty off the floor.
func area_cells(grid: SimGrid, cell: Vector2i) -> Array[Vector2i]:
	if grid == null or grid.terrain(cell) != SimGrid.Terrain.FLOOR:
		return []
	var look: Finish = finish(cell)
	var room: int = grid.room(cell)
	return _flood(grid, cell, func(next: Vector2i) -> bool: return grid.room(next) == room and finish(next).same(look))


static func _flood(grid: SimGrid, start: Vector2i, keep: Callable) -> Array[Vector2i]:
	var area: Array[Vector2i] = [start]
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var index: int = 0
	while index < area.size():
		var here: Vector2i = area[index]
		index += 1
		for step: Vector2i in STEPS:
			var next: Vector2i = here + step
			if seen.has(next) or grid.terrain(next) != SimGrid.Terrain.FLOOR:
				continue
			if grid.segment(SimGrid.edge_between(here, next)) != SimGrid.Segment.NONE or grid.edge_blocked(here, next):
				continue
			if not bool(keep.call(next)):
				continue
			seen[next] = true
			area.append(next)
	area.sort_custom(_row_major)
	return area


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
