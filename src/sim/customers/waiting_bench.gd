class_name WaitingBench
extends RefCounted
## Waiting seats are separate from dining. Deterministic placement order and
## distance to the street door choose a free spot without consuming any RNG.

const TUNING: VisitTuning = preload("res://data/balance/visits.tres")
const DINING_ONLY: String = "Waiting benches belong in the dining room"
const REACHABLE: String = "Guests must be able to reach every waiting bench seat"
const DINING_OVERLAP: String = "Keep waiting seats separate from dining tables"
const FAR_FROM_DOOR: String = "Waiting benches work best near the door"


static func is_bench(item: PlacedItem) -> bool:
	return item != null and not item.removed and item.def is ItemDef \
		and (item.def as ItemDef).category == ItemDef.Category.WAITING


static func benches(grid: SimGrid) -> Array[PlacedItem]:
	var found: Array[PlacedItem] = []
	for item: PlacedItem in grid.items():
		if is_bench(item):
			found.append(item)
	return found


static func door_distance(grid: SimGrid, cells: Array[Vector2i]) -> float:
	var distance: float = INF
	for entry: Vector2i in grid.entries():
		for cell: Vector2i in cells:
			distance = minf(distance, GridMath.octile(entry, cell))
	return distance


static func placement_problem(grid: SimGrid, bench: PlacedItem,
		guests: Dictionary[Vector2i, bool]) -> String:
	for seat: Vector2i in bench.seat_cells:
		if grid.room(seat) != SimGrid.Room.DINING:
			return DINING_ONLY
		if grid.dining_table_id(seat) > 0:
			return DINING_OVERLAP
		if not guests.has(seat):
			return REACHABLE
	return ""


## The caller already tried to find a table. A reserved waiting spot remains
## valid until a table is found, the bench changes, or this guest departs.
static func advance(guest: CustomerAgent, world: SimWorld, sim: RestaurantSim) -> bool:
	var bench: PlacedItem = world.grid.item(guest.waiting_item_id)
	if not is_bench(bench) or not bench.seat_cells.has(guest.waiting_cell) \
			or bench.reserved_by(guest.waiting_cell) != guest.id \
			or not world.grid.is_guest_walkable(guest.waiting_cell) \
			or world.grid.room(guest.waiting_cell) != SimGrid.Room.DINING:
		if guest.waiting_item_id > 0:
			guest.clear_path()
		guest.release_waiting_seat(world)
		bench = null
	if bench == null:
		var choices: Array[PlacedItem] = benches(world.grid)
		choices.sort_custom(func(a: PlacedItem, b: PlacedItem) -> bool:
			var first: float = door_distance(world.grid, a.seat_cells)
			var second: float = door_distance(world.grid, b.seat_cells)
			return first < second or first == second and a.id < b.id)
		for candidate: PlacedItem in choices:
			for seat: Vector2i in candidate.seat_cells:
				if candidate.reserved_by(seat) != -1 or world.grid.room(seat) != SimGrid.Room.DINING \
						or world.grid.dining_table_id(seat) > 0 \
						or not world.grid.is_guest_walkable(seat) \
						or not world.grid.is_guest_reachable(guest.cell, seat):
					continue
				if not candidate.reserve(seat, guest.id):
					continue
				if not guest.set_destination(world.grid, seat):
					candidate.release(seat, guest.id)
					continue
				guest.waiting_item_id = candidate.id
				guest.waiting_cell = seat
				bench = candidate
				break
			if bench != null:
				break
	if bench == null:
		return false
	if guest.cell != guest.waiting_cell:
		if not guest._move(world, guest.waiting_cell) and (guest.path.is_empty() or guest.needs_repath):
			guest.release_waiting_seat(world)
			guest.clear_path()
			return false
	if guest.is_waiting_seated(world) and not guest.waited_seated:
		guest.waited_seated = true
		var tuning: VisitTuning = sim.visit_tuning if sim != null else TUNING
		var multiplier: float = tuning.waiting_bench_patience_multiplier if tuning != null and tuning.is_valid() else 1.0
		guest.queue_patience = CustomerAgent._type_patience(guest.queue_patience, multiplier)
	return true
