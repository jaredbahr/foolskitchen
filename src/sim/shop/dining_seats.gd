class_name DiningSeats
extends RefCounted
## Read-only dining-seat projection. Authored table seats keep priority; a
## standalone furnishing contributes all of its seats or none. Applying a plan
## and maintaining reservations belongs to the caller's atomic grid update.
## ItemDef.capacity describes jobs/storage and is not a dining-seat limit.

## A wall or window between a seat and its table (FK-070).
const WALLED_OFF: String = "A wall stands between this seat and its table"

class SeatLink extends RefCounted:
	var table_item_id: int = 0
	var furnishing_item_id: int = 0
	var cell: Vector2i = Vector2i.ZERO
	var built_in: bool = false

class Group extends RefCounted:
	var id: int = 0
	var member_ids: Array[int] = []
	var seat_cells: Array[Vector2i] = []
	var nominal_capacity: int = 0

	func is_joined() -> bool:
		return member_ids.size() > 1

	func copy() -> Group:
		var result: Group = Group.new()
		result.id = id
		result.member_ids.assign(member_ids)
		result.seat_cells.assign(seat_cells)
		result.nominal_capacity = nominal_capacity
		return result

class Plan extends RefCounted:
	## New arrays keyed by the physical table/counter's stable placement ID.
	var table_seats: Dictionary[int, Array] = {}
	var links: Array[SeatLink] = []
	var groups: Dictionary[int, Group] = {}
	var member_groups: Dictionary[int, int] = {}

	func group_for(table_id: int) -> Group:
		return groups.get(member_groups.get(table_id, 0), null)
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
	for seat: Vector2i in grid.dining_group_seats(table.id):
		if usable.has(seat) or not grid.is_walkable(seat):
			continue
		for entry: Vector2i in starts:
			if grid.is_walkable(entry) and grid.is_guest_reachable(entry, seat):
				usable.append(seat)
				break
	return usable


static func largest_usable_capacity(grid: SimGrid, from_cell: Vector2i = SimGrid.NO_CELL) -> int:
	var largest: int = 0
	var seen: Dictionary[int, bool] = {}
	for table: PlacedItem in grid.items():
		var group_id: int = grid.dining_group_id(table.id)
		if group_id == 0 or seen.has(group_id):
			continue
		seen[group_id] = true
		largest = maxi(largest, usable_cells(grid, table, from_cell).size())
	return largest


## Nominal joined capacity excludes internal seams; standalone authored blocked
## seats retain their established warning semantics.
static func nominal_capacity(grid: SimGrid, table: PlacedItem) -> int:
	var group: Group = grid.dining_group(table.id)
	return group.nominal_capacity if group != null else 0


## Always reconstructs from definitions, even when a previous plan has already
## been applied to PlacedItem.seat_cells. No grid/definition/reservation mutates.
static func derive(grid: SimGrid) -> Plan:
	var plan: Plan = Plan.new()
	if grid == null:
		plan.failures[0] = "The shop is unavailable"
		return plan
	_derive_members(grid, plan)
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
			if failure.is_empty() and _internal_seat(grid, plan, table.id, cell):
				failure = "Seats between joined tables are not usable"
			if failure.is_empty() and grid.access_walled_off(table.cells, [cell] as Array[Vector2i]):
				failure = WALLED_OFF
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
			if _internal_seat(grid, plan, table.id, cell):
				failure = "Seats between joined tables are not usable"
				break
			if grid.edge_blocked(cell, front):
				failure = WALLED_OFF
				break
			var link: SeatLink = _link(table.id, furnishing.id, cell, false)
			pending.append(link)
			local_claims[cell] = true
		if not failure.is_empty():
			_record_failure(plan, furnishing.id, failure)
			continue
		for link: SeatLink in pending:
			_append_link(plan, claimed, link)
	_finish_groups(grid, plan)
	return plan


static func _absolute_cell(item: PlacedItem, definition: ItemDef, authored: Vector2i) -> Vector2i:
	return item.origin + GridMath.rotate_cell(authored, definition.footprint, item.quarter_turns)


static func _cell_failure(grid: SimGrid, cell: Vector2i, claimed: Dictionary[Vector2i, bool]) -> String:
	if not grid.in_bounds(cell):
		return "A seat is outside the shop"
	# A back door's shell cell is walkable for staff only: never a seat.
	if not grid.is_walkable(cell) or grid.is_back_door(cell):
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


## Components use geometry, never placement order. Physical links keep their
## legacy built-in/furnishing priority; the joined union gets geometric order.
static func _derive_members(grid: SimGrid, plan: Plan) -> void:
	var tables: Array[PlacedItem] = []
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if placed.removed or (definition != null and definition.category != ItemDef.Category.TABLE):
			continue
		if definition == null and placed.seat_cells.is_empty():
			continue
		tables.append(placed)
	tables.sort_custom(_table_before)
	var seen: Dictionary[int, bool] = {}
	for table: PlacedItem in tables:
		if seen.has(table.id):
			continue
		var members: Array[PlacedItem] = [table]
		seen[table.id] = true
		var cursor: int = 0
		while cursor < members.size():
			var current: PlacedItem = members[cursor]
			cursor += 1
			for candidate: PlacedItem in tables:
				if not seen.has(candidate.id) and _joinable(grid, current, candidate):
					seen[candidate.id] = true
					members.append(candidate)
		members.sort_custom(_table_before)
		var group: Group = Group.new()
		group.id = members[0].id
		for member: PlacedItem in members:
			group.member_ids.append(member.id)
			plan.member_groups[member.id] = group.id
		plan.groups[group.id] = group


static func _table_before(a: PlacedItem, b: PlacedItem) -> bool:
	if a.origin.y != b.origin.y:
		return a.origin.y < b.origin.y
	if a.origin.x != b.origin.x:
		return a.origin.x < b.origin.x
	var ad: ItemDef = a.def as ItemDef
	var bd: ItemDef = b.def as ItemDef
	var aid: String = String(ad.id) if ad != null else ""
	var bid: String = String(bd.id) if bd != null else ""
	if aid != bid:
		return aid < bid
	if a.quarter_turns != b.quarter_turns:
		return a.quarter_turns < b.quarter_turns
	return a.id < b.id


static func _room_of(grid: SimGrid, table: PlacedItem) -> int:
	var definition: ItemDef = table.def as ItemDef
	if definition == null or definition.serve_across or table.cells.is_empty():
		return -1
	var room: int = grid.room(table.cells[0])
	for cell: Vector2i in table.cells:
		if grid.room(cell) != room:
			return -1
	return room


static func _joinable(grid: SimGrid, a: PlacedItem, b: PlacedItem) -> bool:
	var room: int = _room_of(grid, a)
	if room < 0 or _room_of(grid, b) != room:
		return false
	var ad: ItemDef = a.def as ItemDef
	var bd: ItemDef = b.def as ItemDef
	var ar: Rect2i = Rect2i(a.origin, GridMath.rotated_footprint(ad.footprint, a.quarter_turns))
	var br: Rect2i = Rect2i(b.origin, GridMath.rotated_footprint(bd.footprint, b.quarter_turns))
	var pairs: Array[Vector2i] = []
	var across: Vector2i = Vector2i.ZERO
	if ar.position.y == br.position.y and ar.size.y == br.size.y and (ar.end.x == br.position.x or br.end.x == ar.position.x):
		var left: Rect2i = ar if ar.end.x == br.position.x else br
		for y: int in range(left.position.y, left.end.y):
			pairs.append(Vector2i(left.end.x - 1, y))
		across = Vector2i.RIGHT
	elif ar.position.x == br.position.x and ar.size.x == br.size.x and (ar.end.y == br.position.y or br.end.y == ar.position.y):
		var top: Rect2i = ar if ar.end.y == br.position.y else br
		for x: int in range(top.position.x, top.end.x):
			pairs.append(Vector2i(x, top.end.y - 1))
		across = Vector2i.DOWN
	else:
		return false
	for cell: Vector2i in pairs:
		if grid.edge_blocked(cell, cell + across):
			return false
	return true


static func _internal_seat(grid: SimGrid, plan: Plan, table_id: int, seat: Vector2i) -> bool:
	var group: Group = plan.group_for(table_id)
	if group == null or not group.is_joined():
		return false
	for member_id: int in group.member_ids:
		if grid.item(member_id).cells.has(seat):
			return true
	return false


static func _finish_groups(grid: SimGrid, plan: Plan) -> void:
	for group: Group in plan.groups.values():
		for member_id: int in group.member_ids:
			var table: PlacedItem = grid.item(member_id)
			var definition: ItemDef = table.def as ItemDef
			var seats: Array[Vector2i] = plan.seats_for(member_id) if definition != null else table.seat_cells
			for seat: Vector2i in seats:
				if not group.seat_cells.has(seat):
					group.seat_cells.append(seat)
			if definition == null:
				group.nominal_capacity += seats.size()
			else:
				for authored: Vector2i in definition.seat_cells:
					if not _internal_seat(grid, plan, member_id, _absolute_cell(table, definition, authored)):
						group.nominal_capacity += 1
		for link: SeatLink in plan.links:
			if not link.built_in and group.member_ids.has(link.table_item_id):
				group.nominal_capacity += 1
		if group.is_joined():
			group.seat_cells.sort_custom(_cell_before)


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
