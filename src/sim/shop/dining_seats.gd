class_name DiningSeats
extends RefCounted
## Read-only dining-seat projection. Authored table seats keep priority; a
## standalone furnishing contributes all of its seats or none. Applying a plan
## and maintaining reservations belongs to the caller's atomic grid update.
## ItemDef.capacity describes jobs/storage and is not a dining-seat limit.

class SeatLink extends RefCounted:
	var table_item_id: int = 0
	var furnishing_item_id: int = 0
	var cell: Vector2i = Vector2i.ZERO
	var built_in: bool = false

class Plan extends RefCounted:
	## New arrays keyed by the physical table/counter's stable placement ID.
	var table_seats: Dictionary[int, Array] = {}
	var links: Array[SeatLink] = []
	## Readable first failure per furnishing. ID 0 means the grid is unavailable.
	var failures: Dictionary[int, String] = {}

	func seats_for(table_item_id: int) -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		cells.assign(table_seats.get(table_item_id, []))
		return cells


	func failure_for(furnishing_item_id: int) -> String:
		return failures.get(furnishing_item_id, "")


## Actual dining capacity ignores temporary bookings and dirt, but requires a
## clear seat reachable from the street. Never substitute ItemDef.capacity.
static func usable_cells(grid: SimGrid, table: PlacedItem, from_cell: Vector2i = SimGrid.NO_CELL) -> Array[Vector2i]:
	var usable: Array[Vector2i] = []
	var definition: ItemDef = table.def as ItemDef
	if table.removed or definition != null and definition.category != ItemDef.Category.TABLE:
		return usable
	var starts: Array[Vector2i] = []
	if from_cell == SimGrid.NO_CELL:
		starts.assign(grid.entries())
	else:
		starts.append(from_cell)
	for seat: Vector2i in table.seat_cells:
		if usable.has(seat) or not grid.is_walkable(seat):
			continue
		for entry: Vector2i in starts:
			if grid.is_walkable(entry) and grid.is_reachable(entry, seat):
				usable.append(seat)
				break
	return usable


static func largest_usable_capacity(grid: SimGrid, from_cell: Vector2i = SimGrid.NO_CELL) -> int:
	var largest: int = 0
	for table: PlacedItem in grid.items():
		largest = maxi(largest, usable_cells(grid, table, from_cell).size())
	return largest


## Built-ins retain their authored nominal count even when the projection has
## removed blocked cells. Valid separate furnishings add their linked seats.
static func nominal_capacity(grid: SimGrid, table: PlacedItem) -> int:
	var definition: ItemDef = table.def as ItemDef
	if definition == null:
		return table.seat_cells.size()
	var count: int = definition.seat_cells.size()
	for seat: Vector2i in table.seat_cells:
		var furnishing_id: int = grid.dining_furnishing_id(seat)
		if furnishing_id > 0 and furnishing_id != table.id:
			count += 1
	return count


## Always reconstructs from definitions, even when a previous plan has already
## been applied to PlacedItem.seat_cells. No grid/definition/reservation mutates.
static func derive(grid: SimGrid) -> Plan:
	var plan: Plan = Plan.new()
	if grid == null:
		plan.failures[0] = "The shop is unavailable"
		return plan
	var claimed: Dictionary[Vector2i, bool] = {}
	var items: Array[PlacedItem] = grid.items()
	for table: PlacedItem in items:
		var definition: ItemDef = table.def as ItemDef
		if table.removed or definition == null or definition.category != ItemDef.Category.TABLE:
			continue
		var cells: Array[Vector2i] = []
		plan.table_seats[table.id] = cells
		for authored: Vector2i in definition.seat_cells:
			var cell: Vector2i = _absolute_cell(table, definition, authored)
			var failure: String = _cell_failure(grid, cell, claimed)
			if not failure.is_empty():
				_record_failure(plan, table.id, failure)
				continue
			_append_link(plan, claimed, _link(table.id, table.id, cell, true))
	for furnishing: PlacedItem in items:
		var definition: ItemDef = furnishing.def as ItemDef
		if furnishing.removed or definition == null or definition.category != ItemDef.Category.CHAIR:
			continue
		var pending: Array[SeatLink] = []
		var local_claims: Dictionary[Vector2i, bool] = {}
		var failure: String = "This seat has no seating position" if definition.seat_cells.is_empty() else ""
		for authored: Vector2i in definition.seat_cells:
			var cell: Vector2i = _absolute_cell(furnishing, definition, authored)
			failure = _cell_failure(grid, cell, claimed)
			if failure.is_empty() and local_claims.has(cell):
				failure = "There is already a seat here"
			if not failure.is_empty():
				break
			var front: Vector2i = _absolute_cell(furnishing, definition, authored + Vector2i.UP)
			var table: PlacedItem = grid.item_at(front)
			var surface: ItemDef = table.def as ItemDef if table != null else null
			if table == null or table.removed or surface == null \
					or surface.category != ItemDef.Category.TABLE or not plan.table_seats.has(table.id):
				failure = "Place every seat facing a table or counter"
				break
			var link: SeatLink = _link(table.id, furnishing.id, cell, false)
			pending.append(link)
			local_claims[cell] = true
		if not failure.is_empty():
			_record_failure(plan, furnishing.id, failure)
			continue
		for link: SeatLink in pending:
			_append_link(plan, claimed, link)
	return plan


static func _absolute_cell(item: PlacedItem, definition: ItemDef, authored: Vector2i) -> Vector2i:
	return item.origin + GridMath.rotate_cell(authored, definition.footprint, item.quarter_turns)


static func _cell_failure(grid: SimGrid, cell: Vector2i, claimed: Dictionary[Vector2i, bool]) -> String:
	if not grid.in_bounds(cell):
		return "A seat is outside the shop"
	if not grid.is_walkable(cell):
		return "Keep every seat on a clear floor tile"
	if claimed.has(cell):
		return "There is already a seat here"
	return ""


static func _record_failure(plan: Plan, item_id: int, reason: String) -> void:
	if not plan.failures.has(item_id):
		plan.failures[item_id] = reason


static func _append_link(plan: Plan, claimed: Dictionary[Vector2i, bool], link: SeatLink) -> void:
	var cells: Array = plan.table_seats[link.table_item_id]
	cells.append(link.cell)
	claimed[link.cell] = true
	plan.links.append(link)


static func _link(table_id: int, furnishing_id: int, cell: Vector2i, built_in: bool) -> SeatLink:
	var link: SeatLink = SeatLink.new()
	link.table_item_id = table_id
	link.furnishing_item_id = furnishing_id
	link.cell = cell
	link.built_in = built_in
	return link
