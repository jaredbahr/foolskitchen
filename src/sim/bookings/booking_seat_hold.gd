class_name BookingSeatHold
extends RefCounted
## A soft joined-group exclusion. It blocks new seating searches without
## acquiring cells or disturbing diners already holding seats.

var state: GroupBooking
var kitchen: Kitchen


func _init(model: GroupBooking = null, dining_kitchen: Kitchen = null) -> void:
	state = model
	kitchen = dining_kitchen


## Returns the current held group for the booked party, rebuilding the choice
## if a closed-morning layout edit changed the derived joined topology.
func group_for_booking(world: SimWorld, booking_id: int) -> int:
	if world == null or state == null or not state.has_active_booking() \
			or int(state.booking.get("booking_id", 0)) != booking_id:
		return 0
	_sync(world)
	return int(state.booking.get("held_group_id", 0))


func blocks_group(world: SimWorld, group_id: int, arriving_booking_id: int = 0) -> bool:
	if world == null or group_id <= 0 or state == null or not state.has_active_booking():
		return false
	_sync(world)
	return int(state.booking.get("held_group_id", 0)) == group_id \
		and arriving_booking_id != int(state.booking.get("booking_id", 0))


## Runs immediately before the next simulation tick so a walk-in cannot claim
## the selected group on the first tick whose displayed minute reaches the hold.
func prepare_next_tick(world: SimWorld) -> void:
	if world == null or state == null or not state.has_active_booking() \
			or world.clock.phase != SimClock.Phase.OPEN:
		return
	var next_minute: int = world.clock.display_close_minute
	var next_tick: int = world.clock.phase_tick + 1
	if next_tick < world.clock.open_ticks:
		next_minute = world.clock.display_open_minute + floori(
			float(next_tick) / float(maxi(world.clock.open_ticks, 1)) \
			* float(world.clock.display_close_minute - world.clock.display_open_minute))
	_sync_at_minute(world, next_minute)


## Read-only: normal hold/seat selection establishes the group. A retry never
## redraws it or moves the absolute slot + grace deadline.
func pauses_queue_patience(world: SimWorld, booking_id: int) -> bool:
	var group_id: int = _active_held_group(world, booking_id)
	if group_id == 0 or world.clock.phase != SimClock.Phase.OPEN:
		return false
	var minute: int = world.clock.display_minutes()
	var slot: int = int(state.booking["slot_minute"])
	if minute < slot or minute >= slot + state.tuning.reserved_queue_grace_minutes:
		return false
	if kitchen != null and kitchen.is_dining_group_dirty(group_id):
		return true
	for member: Variant in state.booking["held_group_members"]:
		var table: PlacedItem = world.grid.item(int(member))
		for seat: Vector2i in table.seat_cells:
			if table.reserved_by(seat) != -1:
				return true
	return false


## Reserved bussing outranks other enabled work, never disabled jobs. Inspect
## the current hold each claim so settled/reselected groups cannot stay urgent.
func prioritizes_bussing(world: SimWorld, table_item_id: int) -> bool:
	if state == null or kitchen == null or not kitchen.is_table_dirty(table_item_id):
		return false
	var booking_id: int = int(state.booking.get("booking_id", 0))
	var group_id: int = _active_held_group(world, booking_id)
	if group_id == 0:
		return false
	if _seated_booking_owns_group(world, booking_id, group_id):
		return false
	for member: Variant in state.booking["held_group_members"]:
		if int(member) == table_item_id:
			return true
	return false


## Joined departures dirty every original member. Cleaning those members while
## prior diners still hold seats delays their food and must be repeated later.
## Keep these OPEN jobs queued until the promised group is physically vacated.
func defers_bussing(world: SimWorld, table_item_id: int) -> bool:
	if state == null:
		return false
	var booking_id: int = int(state.booking.get("booking_id", 0))
	var group_id: int = _active_held_group(world, booking_id)
	if group_id == 0 or not state.booking["held_group_members"].has(table_item_id) \
			or _seated_booking_owns_group(world, booking_id, group_id):
		return false
	for member: Variant in state.booking["held_group_members"]:
		var table: PlacedItem = world.grid.item(int(member))
		for seat: Vector2i in table.seat_cells:
			var diner: CustomerAgent = world.agent(table.reserved_by(seat)) as CustomerAgent
			if diner != null and (diner.party == null or not diner.party.booking_owned \
					or diner.party.booking_id != booking_id):
				return true
	return false


func _seated_booking_owns_group(world: SimWorld, booking_id: int, group_id: int) -> bool:
	# The promise is fulfilled once this booking owns its joined group. Later
	# departures still post ordinary bus jobs, but those must not outrank the
	# remaining party members' food while their occupied table cannot be bused.
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest != null and guest.party != null and guest.party.booking_owned \
				and guest.party.booking_id == booking_id and guest.party.seated \
				and guest.party.table_item_id == group_id:
			return true
	return false


func _active_held_group(world: SimWorld, booking_id: int) -> int:
	if world == null or world.clock == null or state == null or state.tuning == null \
			or not state.tuning.is_valid() or not state.has_active_booking() or booking_id <= 0 \
			or int(state.booking.get("booking_id", 0)) != booking_id \
			or int(state.booking.get("service_day", 0)) != world.clock.day \
			or world.clock.phase not in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS] \
			or world.clock.display_minutes() < int(state.booking.get("slot_minute", 0)) - state.tuning.hold_before_minutes:
		return 0
	var group_id: int = int(state.booking.get("held_group_id", 0))
	return group_id if group_id > 0 and _valid_group(group_id,
		state.booking.get("held_group_members", []), world, int(state.booking.get("party_size", 0))) else 0


func _sync(world: SimWorld) -> void:
	_sync_at_minute(world, world.clock.display_minutes())


func _sync_at_minute(world: SimWorld, display_minute: int) -> void:
	var booking: Dictionary = state.booking
	if int(booking.get("service_day", 0)) != world.clock.day:
		return
	var hold_at: int = int(booking.get("slot_minute", 0)) - state.tuning.hold_before_minutes
	if display_minute < hold_at:
		return
	var group_id: int = int(booking.get("held_group_id", 0))
	if group_id > 0 and _valid_group(group_id, booking.get("held_group_members", []), world,
			int(booking.get("party_size", 0))):
		return
	if group_id > 0:
		state.clear_held_group(int(booking["booking_id"]), group_id)
	var candidate: Dictionary = _choose_group(world, int(booking.get("party_size", 0)))
	if not candidate.is_empty():
		state.mark_held_group(int(booking["booking_id"]), int(candidate["id"]), candidate["members"])


func _choose_group(world: SimWorld, party_size: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var seen: Dictionary[int, bool] = {}
	for table: PlacedItem in world.grid.items():
		var definition: ItemDef = table.def as ItemDef
		if table.removed or (definition != null and definition.category != ItemDef.Category.TABLE):
			continue
		var group_id: int = PartySeating.table_group_id(table, world.grid)
		if seen.has(group_id):
			continue
		seen[group_id] = true
		var members: Array[int] = PartySeating.table_group_members(table, world.grid)
		if members.size() < 2:
			continue
		var seats: Array[Vector2i] = _usable_seats(world, table)
		if seats.size() < party_size:
			continue
		var free_count: int = 0
		var occupied: bool = false
		for seat: Vector2i in seats:
			var owner: PlacedItem = world.grid.item(world.grid.dining_owner_id(table.id, seat))
			if owner == null:
				continue
			if owner.reserved_by(seat) == -1:
				free_count += 1
			else:
				occupied = true
		var clear_now: bool = free_count >= party_size and not occupied \
				and (kitchen == null or not kitchen.is_dining_group_dirty(group_id))
		var rank: int = 0 if clear_now else (2 if occupied else 1)
		candidates.append({"id": group_id, "members": members, "rank": rank})
	candidates.sort_custom(_candidate_before)
	return candidates[0] if not candidates.is_empty() else {}


func _candidate_before(left: Dictionary, right: Dictionary) -> bool:
	if int(left["rank"]) != int(right["rank"]):
		return int(left["rank"]) < int(right["rank"])
	return int(left["id"]) < int(right["id"])


func _valid_group(group_id: int, saved_members: Variant, world: SimWorld, party_size: int) -> bool:
	if not saved_members is Array or saved_members.size() < 2:
		return false
	var grid: SimGrid = world.grid
	var leader: PlacedItem = grid.item(group_id)
	if leader == null or PartySeating.table_group_id(leader, grid) != group_id:
		return false
	var live_members: Array[int] = PartySeating.table_group_members(leader, grid)
	if live_members.size() != saved_members.size():
		return false
	for index: int in live_members.size():
		if live_members[index] != int(saved_members[index]):
			return false
	return _usable_seats(world, leader).size() >= party_size


func _usable_seats(world: SimWorld, table: PlacedItem) -> Array[Vector2i]:
	var usable: Array[Vector2i] = []
	var entries: Array[Vector2i] = world.grid.entries()
	if entries.is_empty():
		return usable
	for seat: Vector2i in PartySeating.table_group_seats(table, world.grid):
		if not world.grid.is_walkable(seat) or not PatioRules.can_seat(
				world.grid, seat, world.weather.kind):
			continue
		if world.grid.is_guest_reachable(entries[0], seat):
			usable.append(seat)
	return usable
