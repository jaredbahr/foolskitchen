class_name PartySeating
extends RefCounted
## Atomic party reservations and a shared, bounded table search. The ordinary
## singleton search stays in CustomerAgent and shares only read-only helpers.


static func members(party: Party, world: SimWorld) -> Array[CustomerAgent]:
	var result: Array[CustomerAgent] = []
	if party == null or world == null or not party.is_valid():
		return result
	for member_id: int in party.member_ids:
		var guest: CustomerAgent = world.agent(member_id) as CustomerAgent
		if guest == null or guest.state >= CustomerAgent.State.LEAVING:
			return []
		result.append(guest)
	return result


## Candidate paths are checked for every member before any hold is acquired.
## Standalone parties up to four retain their original assignment order.
static func try_seat(party: Party, world: SimWorld, kitchen: Kitchen = null) -> bool:
	if party == null or party.departing or party.seated or party.table_item_id != 0:
		return false
	var guests: Array[CustomerAgent] = members(party, world)
	if guests.is_empty():
		return false
	for guest: CustomerAgent in guests:
		if guest.state != CustomerAgent.State.ARRIVING and guest.state != CustomerAgent.State.QUEUED:
			return false
	var seen: Dictionary[int, bool] = {}
	for table: PlacedItem in world.grid.items():
		var definition: ItemDef = table.def as ItemDef
		if table.removed or (definition != null and definition.category != ItemDef.Category.TABLE):
			continue
		var group_id: int = table_group_id(table, world.grid)
		if seen.has(group_id):
			continue
		seen[group_id] = true
		if kitchen != null and kitchen.is_dining_group_dirty(table.id):
			continue
		if held_for_earlier_party(table, guests[0].id, world):
			continue
		var available: Array[Vector2i] = []
		for seat: Vector2i in table_group_seats(table, world.grid):
			var owner: PlacedItem = world.grid.item(world.grid.dining_owner_id(table.id, seat))
			if owner != null and owner.reserved_by(seat) == -1 and world.grid.is_walkable(seat) and not available.has(seat):
				available.append(seat)
		if available.size() < guests.size():
			continue
		var choices: Array[Array] = []
		for guest: CustomerAgent in guests:
			var reachable: Array[Vector2i] = []
			for seat: Vector2i in available:
				if world.grid.is_guest_reachable(guest.cell, seat):
					reachable.append(seat)
			choices.append(reachable)
		var seats: Array[Vector2i] = []
		var table_ids: Array[int] = table_group_members(table, world.grid)
		if not _match_candidate(choices, seats, table_ids.size() > 1):
			continue
		var agent_ids: Array[int] = []
		for guest: CustomerAgent in guests:
			agent_ids.append(guest.id)
		if not world.grid.reserve_dining_seats(table.id, seats, agent_ids):
			continue
		var routed: bool = true
		for index: int in guests.size():
			if not guests[index].set_destination(world.grid, seats[index]):
				routed = false
				break
		if not routed:
			for index: int in guests.size():
				var owner: PlacedItem = world.grid.item(world.grid.dining_owner_id(table.id, seats[index]))
				if owner != null:
					owner.release(seats[index], guests[index].id)
				guests[index].clear_path()
			continue
		party.table_item_id = group_id
		party.booked_table_ids = table_ids.duplicate()
		for index: int in guests.size():
			var guest: CustomerAgent = guests[index]
			guest.release_waiting_seat(world)
			guest.table_item_id = world.grid.dining_owner_id(table.id, seats[index])
			guest.booked_table_ids = table_ids.duplicate()
			guest.seat_cell = seats[index]
			guest._walk_wait = 0
			guest._ordering_block_logged = false
			guest.state = CustomerAgent.State.WALKING_TO_SEAT
		return true
	return false


## Untyped synthetic table fixtures keep their original standalone contract.
static func table_group_id(table: PlacedItem, grid: SimGrid) -> int:
	var group_id: int = grid.dining_group_id(table.id)
	return group_id if group_id != 0 else table.id


static func table_group_members(table: PlacedItem, grid: SimGrid) -> Array[int]:
	var ids: Array[int] = grid.dining_group_members(table.id)
	if ids.is_empty():
		ids.append(table.id)
	return ids


static func table_group_seats(table: PlacedItem, grid: SimGrid) -> Array[Vector2i]:
	if grid.dining_group_id(table.id) == 0:
		return table.seat_cells.duplicate()
	return grid.dining_group_seats(table.id)


## A forced topology edit before arrival invalidates the complete booking.
static func booking_valid(party: Party, world: SimWorld) -> bool:
	if party == null or party.table_item_id == 0:
		return false
	var leader: PlacedItem = world.grid.item(party.table_item_id)
	if leader == null or table_group_id(leader, world.grid) != party.table_item_id \
			or table_group_members(leader, world.grid) != party.booked_table_ids:
		return false
	var guests: Array[CustomerAgent] = members(party, world)
	if guests.is_empty():
		return false
	for guest: CustomerAgent in guests:
		var owner: PlacedItem = world.grid.item(guest.table_item_id)
		if owner == null or world.grid.dining_owner_id(leader.id, guest.seat_cell) != owner.id \
				or owner.reserved_by(guest.seat_cell) != guest.id \
				or not owner.seat_cells.has(guest.seat_cell) or not world.grid.is_walkable(guest.seat_cell):
			return false
	return true


## A waiting party keeps priority at every table that could fit it once the
## current diners leave. Smaller/unreachable tables remain available to backfill.
## IDs are arrival order; reading paths and holds consumes no random draws.
static func held_for_earlier_party(table: PlacedItem, arrival_id: int, world: SimWorld) -> bool:
	var seen: Array[Party] = []
	for agent: SimAgent in world.agents:
		if agent.id >= arrival_id:
			break
		var guest: CustomerAgent = agent as CustomerAgent
		if guest == null or guest.state > CustomerAgent.State.QUEUED or guest.party == null:
			continue
		var earlier: Party = guest.party
		if earlier.size() <= 1 or earlier.departing or earlier.seated or earlier.table_item_id != 0 \
				or seen.has(earlier):
			continue
		seen.append(earlier)
		var waiting: Array[CustomerAgent] = members(earlier, world)
		if waiting.is_empty():
			continue
		var choices: Array[Array] = []
		for member: CustomerAgent in waiting:
			var reachable: Array[Vector2i] = []
			for seat: Vector2i in table_group_seats(table, world.grid):
				if world.grid.is_walkable(seat) and world.grid.is_guest_reachable(member.cell, seat) \
						and not reachable.has(seat):
					reachable.append(seat)
			choices.append(reachable)
		var seats: Array[Vector2i] = []
		if _match_candidate(choices, seats, table_group_members(table, world.grid).size() > 1):
			return true
	return false


static func _match_candidate(choices: Array[Array], seats: Array[Vector2i], joined: bool) -> bool:
	if not joined and choices.size() <= 4:
		return _match(choices, 0, seats)
	var owners: Dictionary[Vector2i, int] = {}
	for index: int in choices.size():
		var visited: Dictionary[Vector2i, bool] = {}
		if not _augment(choices, index, visited, owners):
			return false
	seats.resize(choices.size())
	for seat: Vector2i in owners:
		seats[owners[seat]] = seat
	return true


## At most six guest nodes; each augmentation visits every seat at most once.
static func _augment(choices: Array[Array], index: int, visited: Dictionary[Vector2i, bool],
		owners: Dictionary[Vector2i, int]) -> bool:
	for seat: Vector2i in choices[index]:
		if visited.has(seat):
			continue
		visited[seat] = true
		if not owners.has(seat) or _augment(choices, owners[seat], visited, owners):
			owners[seat] = index
			return true
	return false


static func _match(choices: Array[Array], index: int, seats: Array[Vector2i]) -> bool:
	if index == choices.size():
		return true
	for seat: Vector2i in choices[index]:
		if seats.has(seat):
			continue
		seats.append(seat)
		if _match(choices, index + 1, seats):
			return true
		seats.pop_back()
	return false


## One common queue budget uses the least patient member. The arrival's first
## search is free, just as for an individual guest; subsequent ticks count once.
static func advance_queue(party: Party, world: SimWorld, sim: RestaurantSim) -> void:
	if party == null or party.departing or party.seated or party.last_queue_tick == world.now:
		return
	party.last_queue_tick = world.now
	var guests: Array[CustomerAgent] = members(party, world)
	if guests.is_empty():
		leave_waiting(party, world, sim, &"no_table")
		return
	if party.queue_started and party.queue_wait >= _budget(guests):
		leave_waiting(party, world, sim, &"no_table")
		return
	if try_seat(party, world, sim.kitchen):
		return
	var already_waiting: bool = party.queue_started
	party.queue_started = true
	if already_waiting:
		party.queue_wait += 1
	for guest: CustomerAgent in guests:
		guest.state = CustomerAgent.State.QUEUED
		guest._queue_wait = party.queue_wait
		guest._queue_inside(world)
	if already_waiting and party.queue_wait >= _budget(guests):
		leave_waiting(party, world, sim, &"no_table")


## No member starts an order until all members have reached their held seats.
static func finish_seating(party: Party, world: SimWorld, sim: RestaurantSim) -> void:
	if party == null or party.seated or party.departing:
		return
	var guests: Array[CustomerAgent] = members(party, world)
	if guests.is_empty():
		leave_waiting(party, world, sim, &"no_table")
		return
	if not booking_valid(party, world):
		requeue(party, world, sim)
		return
	for guest: CustomerAgent in guests:
		if guest.cell != guest.seat_cell:
			return
	party.seated = true
	for guest: CustomerAgent in guests:
		guest.state = CustomerAgent.State.ORDERING
	for guest: CustomerAgent in guests:
		guest._post_order_task(world, sim)


## A failed walk releases the whole booking. Charge the longest concurrent
## walk once, rather than multiplying the wait by the number of members.
static func requeue(party: Party, world: SimWorld, sim: RestaurantSim) -> void:
	if party == null or party.seated or party.departing:
		return
	var guests: Array[CustomerAgent] = members(party, world)
	if guests.is_empty():
		leave_waiting(party, world, sim, &"no_table")
		return
	var walked: int = 0
	for guest: CustomerAgent in guests:
		walked = maxi(walked, guest._walk_wait)
	party.queue_wait += walked
	party.queue_started = true
	party.table_item_id = 0
	party.booked_table_ids.clear()
	party.last_queue_tick = world.now
	for guest: CustomerAgent in guests:
		guest._release_seat(world, false)
		guest.table_item_id = 0
		guest.seat_cell = SimGrid.NO_CELL
		guest.clear_path()
		guest._walk_wait = 0
		guest._queue_wait = party.queue_wait
		guest.state = CustomerAgent.State.QUEUED
	if party.queue_wait >= _budget(guests):
		leave_waiting(party, world, sim, &"no_table")


## Set the guard before invoking each guest's normal cleanup. Departure
## accounting still runs once per person through RestaurantSim, with reasons.
static func leave_waiting(party: Party, world: SimWorld, sim: RestaurantSim,
		reason: StringName = &"no_table") -> void:
	if party == null or party.seated or party.departing:
		return
	leave_together(party, world, sim, reason)


## A food timeout ends only visits still waiting for their food. Delivered
## tickets count as fed even before that member's next tick changes its state.
static func leave_together(party: Party, world: SimWorld, sim: RestaurantSim,
		reason: StringName) -> void:
	if party == null or party.departing:
		return
	party.departing = true
	for member_id: int in party.member_ids:
		var guest: CustomerAgent = world.agent(member_id) as CustomerAgent
		if guest == null or guest.paid:
			continue
		if reason == &"waited_too_long":
			if guest.state != CustomerAgent.State.ORDERING and guest.state != CustomerAgent.State.WAITING_FOOD:
				continue
			if guest.order != null and guest.order.state == Order.State.DELIVERED:
				continue
		guest._leave(world, sim, reason)


static func _budget(guests: Array[CustomerAgent]) -> int:
	var patience: int = guests[0].queue_patience
	for guest: CustomerAgent in guests:
		patience = mini(patience, guest.queue_patience)
	return patience
