class_name EditCheck
extends RefCounted
## One read-only proposal check. Warnings describe the resulting shop and do
## not change ok. Existing item ids are positive; 0 denotes a proposed new buy.

var ok: bool = false
var why: String = ""
## Capacity of the valid proposed table component; -1 for other proposals.
var dining_capacity: int = -1
var dining_joined: bool = false
var unreachable: Array[int] = []
## Partial capacity is still a permitted placement, with a readable warning.
var seat_warnings: Dictionary[int, String] = {}
## Enabled dishes the proposal would take off sale (FK-100), in menu order.
var menu_losses: Array[RecipeDef] = []
var menu_warning: String = ""
## Wall edits (FK-070): what a valid change would charge and refund.
var cost: int = 0
var refund: int = 0
## Segments a valid wall change would actually alter (edge -> new segment).
var changes: Dictionary[Vector3i, int] = {}
## Floor edits (FK-080): the cells a valid change would buy or remove. Wall
## segments it would take down (they no longer fit) are in `changes` as NONE.
var floor_cells: Array[Vector2i] = []
var floor_adding: bool = true
## Room painting (FK-101): the cells a valid change would repaint (cell -> Room).
var rooms: Dictionary[Vector2i, int] = {}
## Floor types (D25): the cells a valid change would relay or recolour.
var finishes: Dictionary[Vector2i, FloorFinishes.Finish] = {}
## Wall finishes (D26): the faces a valid change would refinish or recolour.
var wall_finishes: Dictionary[Vector3i, FloorFinishes.Finish] = {}
## Wall and floor edits (D26): finished faces and hung wall decor (anchors)
## the changed shop would no longer have. They come down with the edit, and
## their refund (half the price) is part of `refund`.
var lost_finishes: Array[Vector3i] = []
var lost_decor: Array[Vector3i] = []
## Floor edits (D25/D26): the part of `refund` that is half the floor-type
## price of the cells that stop being floor (their looks come up with them).
var floor_finish_refund: int = 0


func _init(allowed: bool = false, reason: String = "") -> void:
	ok = allowed
	why = reason


## Seating validity is separate from path warnings. Legacy loose chairs can
## stay in a saved shop, but new/moved chairs must work and existing valid
## furnishings cannot lose their table through another item's edit.
static func validate_dining(live: SimGrid, preview: SimGrid, ids: Dictionary[int, int],
		proposed_id: int, exclude_id: int) -> EditCheck:
	var occupied: String = occupied_dining_problem(live, preview, ids)
	if not occupied.is_empty():
		return EditCheck.new(false, occupied)
	var plan: DiningSeats.Plan = DiningSeats.derive(preview)
	var future: Dictionary[int, bool] = _linked_furnishings(plan, ids)
	var failures: Dictionary[int, String] = {}
	for preview_id: int in plan.failures:
		failures[ids.get(preview_id, preview_id)] = plan.failure_for(preview_id)
	var proposed: PlacedItem = preview.item(proposed_id)
	if proposed != null and (proposed.def as ItemDef).category == ItemDef.Category.CHAIR:
		var live_id: int = ids[proposed_id]
		if not future.has(live_id):
			return EditCheck.new(false, failures.get(live_id, "Place every seat facing a table or counter"))
	var identity: Dictionary[int, int] = {}
	var before: Dictionary[int, bool] = _linked_furnishings(DiningSeats.derive(live), identity)
	for furnishing_id: int in before:
		if furnishing_id != exclude_id and not future.has(furnishing_id):
			return EditCheck.new(false, failures.get(furnishing_id, "Keep existing seats facing a table or counter"))
	var previous_owners: Dictionary[Vector2i, Array] = _built_in_owners(live, identity)
	var next_owners: Dictionary[Vector2i, Array] = _built_in_owners(preview, ids)
	for cell: Vector2i in next_owners:
		var owners: Array = next_owners[cell]
		if owners.size() > 1 and owners != previous_owners.get(cell, []):
			return EditCheck.new(false, "Seats cannot share the same floor tile")
	return EditCheck.new(true)


## DiningSeats stages whole furnishings, so any non-built-in link proves all
## authored seats of that furnishing are valid. Compare remapped live IDs.
static func _linked_furnishings(plan: DiningSeats.Plan, ids: Dictionary[int, int]) -> Dictionary[int, bool]:
	var furnishings: Dictionary[int, bool] = {}
	for link: DiningSeats.SeatLink in plan.links:
		if not link.built_in:
			furnishings[ids.get(link.furnishing_item_id, link.furnishing_item_id)] = true
	return furnishings


## Only walkable authored built-ins participate in duplicate ownership checks.
## Blocked built-ins stay warnings; path connectivity is not queried here.
static func _built_in_owners(grid: SimGrid, ids: Dictionary[int, int]) -> Dictionary[Vector2i, Array]:
	var owners: Dictionary[Vector2i, Array] = {}
	for table: PlacedItem in grid.items():
		var definition: ItemDef = table.def as ItemDef
		if definition == null or definition.category != ItemDef.Category.TABLE:
			continue
		for authored: Vector2i in definition.seat_cells:
			var cell: Vector2i = table.origin + GridMath.rotate_cell(authored, definition.footprint, table.quarter_turns)
			if not grid.is_walkable(cell):
				continue
			if not owners.has(cell):
				var empty: Array[int] = []
				owners[cell] = empty
			var table_ids: Array = owners[cell]
			table_ids.append(ids.get(table.id, table.id))
	for cell: Vector2i in owners:
		(owners[cell] as Array).sort()
	return owners


## Geometry cannot change an occupied component, including its unheld members.
## Compare physical identities through the preview mapping, never preview IDs.
static func occupied_dining_problem(live: SimGrid, preview: SimGrid, ids: Dictionary[int, int]) -> String:
	var future_ids: Dictionary[int, int] = {}
	for preview_id: int in ids:
		future_ids[ids[preview_id]] = preview_id
	var seen: Dictionary[int, bool] = {}
	for table: PlacedItem in live.items():
		var group_id: int = live.dining_group_id(table.id)
		if group_id == 0 or seen.has(group_id):
			continue
		seen[group_id] = true
		if not live.dining_group_has_reservations(table.id):
			continue
		var members: Array[int] = live.dining_group_members(table.id)
		for member_id: int in members:
			var before: PlacedItem = live.item(member_id)
			var after: PlacedItem = preview.item(future_ids.get(member_id, -1))
			# A standalone sale retains its original targeted-work cancellation.
			# A surviving singleton still compares its pose and future membership.
			if after == null and members.size() == 1:
				continue
			if after == null or before.origin != after.origin or before.quarter_turns != after.quarter_turns:
				return "This joined table is in use; try next morning"
			var future_members: Array[int] = []
			for future_id: int in preview.dining_group_members(after.id):
				future_members.append(ids.get(future_id, 0))
			if future_members.size() != members.size():
				return "This joined table is in use; try next morning"
			for original: int in members:
				if not future_members.has(original):
					return "This joined table is in use; try next morning"
			for cell: Vector2i in before.work_cells + before.seat_cells:
				if before.reserved_by(cell) == -1:
					continue
				if before.seat_cells.has(cell):
					if not after.seat_cells.has(cell) or preview.dining_owner_id(after.id, cell) != after.id \
							or not preview.is_walkable(cell):
						return "This joined table is in use; try next morning"
				elif not after.work_cells.has(cell):
					return "This joined table is in use; try next morning"
	return ""
