class_name HygieneOverview
extends RefCounted
## Detached, read-only presentation of the existing day-local cleaning state.
## No tasks, RNG draws, layout edits or save data are created by this view.

const TITLE: String = "Hygiene"
const TOGGLE_TIP: String = "Show dirty tables, floor spots and restroom upkeep on the shop floor"
const TODAY_TIP: String = "Today's cleanliness is the worst floor-dirt rating reached today, as in the evening report"
const UNAVAILABLE: String = "Not recorded yet"

class Snapshot:
	extends RefCounted
	var dirty_tables: int = 0
	var floor_spots: int = 0
	var has_restroom: bool = false
	var toilets_needing_tidy: int = 0
	var restroom_spots: int = 0
	var today_label: String = UNAVAILABLE
	var problem_cells: Array[Vector2i] = []


static func capture(sim: RestaurantSim) -> Snapshot:
	var result: Snapshot = Snapshot.new()
	if sim == null or sim.world == null:
		return result
	var grid: SimGrid = sim.world.grid
	var cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) == SimGrid.Terrain.FLOOR and grid.room(cell) == SimGrid.Room.RESTROOM:
			result.has_restroom = true
			break
	if sim.kitchen != null:
		for id: int in sim.kitchen.dirty_tables:
			var table: PlacedItem = grid.item(id)
			if table == null or table.removed:
				continue
			result.dirty_tables += 1
			_add_cells(cells, table.cells, grid)
			_add_cells(cells, table.seat_cells, grid)
	if sim.cleanliness != null:
		var floor: Array[Vector2i] = sim.cleanliness.spots()
		result.floor_spots = floor.size()
		_add_cells(cells, floor, grid)
		var label: String = sim.cleanliness.worst_category_label()
		result.today_label = label if not label.is_empty() else UNAVAILABLE
		if result.has_restroom:
			var restroom: Array[Vector2i] = sim.cleanliness.restroom_spots()
			result.restroom_spots = restroom.size()
			_add_cells(cells, restroom, grid)
			for toilet: PlacedItem in grid.items():
				if not RoomRules.is_toilet(toilet) or toilet.removed:
					continue
				for spot: Vector2i in toilet.work_cells:
					if restroom.has(spot):
						result.toilets_needing_tidy += 1
						_add_cells(cells, toilet.cells, grid)
						break
	result.problem_cells.assign(cells.keys())
	result.problem_cells.sort_custom(_cell_before)
	return result


static func lines(snapshot: Snapshot) -> PackedStringArray:
	var result: PackedStringArray = ["Dirty tables: %d" % snapshot.dirty_tables,
		"Floor spots: %d" % snapshot.floor_spots]
	if snapshot.has_restroom:
		result.append("Restroom: %d toilet%s need%s a tidy · %d upkeep spot%s" % [
			snapshot.toilets_needing_tidy, "" if snapshot.toilets_needing_tidy == 1 else "s",
			"s" if snapshot.toilets_needing_tidy == 1 else "", snapshot.restroom_spots,
			"" if snapshot.restroom_spots == 1 else "s"])
	result.append("Today's cleanliness: %s" % snapshot.today_label)
	return result


static func _add_cells(target: Dictionary[Vector2i, bool], cells: Array[Vector2i], grid: SimGrid) -> void:
	for cell: Vector2i in cells:
		if grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			target[cell] = true


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
