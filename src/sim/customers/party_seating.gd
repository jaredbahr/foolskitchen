class_name PartySeating
extends RefCounted
## Atomic party reservations and a shared, bounded table search. The ordinary
## singleton path stays in CustomerAgent and never calls this controller.


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
## Backtracking is bounded by the four-member contract and preserves authored
## seat order, including a case where a greedy first choice would strand one.
static func try_seat(party: Party, world: SimWorld, kitchen: Kitchen = null) -> bool:
	if party == null or party.departing or party.seated or party.table_item_id != 0:
		return false
	var guests: Array[CustomerAgent] = members(party, world)
	if guests.is_empty():
		return false
	for guest: CustomerAgent in guests:
		if guest.state != CustomerAgent.State.ARRIVING and guest.state != CustomerAgent.State.QUEUED:
			return false
	for table: PlacedItem in world.grid.items():
		var definition: ItemDef = table.def as ItemDef
		if table.removed or (definition != null and definition.category != ItemDef.Category.TABLE):
			continue
		if kitchen != null and kitchen.is_table_dirty(table.id):
			continue
		if held_for_earlier_party(table, guests[0].id, world):
			continue
		var available: Array[Vector2i] = []
		for seat: Vector2i in table.seat_cells:
			if table.reserved_by(seat) == -1 and world.grid.is_walkable(seat) and not available.has(seat):
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
		if not _match(choices, 0, seats):
			continue
		var held: int = 0
		for index: int in guests.size():
			if not table.reserve(seats[index], guests[index].id):
				break
			held += 1
		if held != guests.size():
			for index: int in held:
				table.release(seats[index], guests[index].id)
			continue
		var routed: bool = true
		for index: int in guests.size():
			if not guests[index].set_destination(world.grid, seats[index]):
				routed = false
				break
		if not routed:
			for index: int in guests.size():
				table.release(seats[index], guests[index].id)
				guests[index].clear_path()
			continue
		party.table_item_id = table.id
		for index: int in guests.size():
			var guest: CustomerAgent = guests[index]
			guest.release_waiting_seat(world)
			guest.table_item_id = table.id
			guest.seat_cell = seats[index]
			guest._walk_wait = 0
			guest._ordering_block_logged = false
			guest.state = CustomerAgent.State.WALKING_TO_SEAT
		return true
	return false


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
			for seat: Vector2i in table.seat_cells:
				if world.grid.is_walkable(seat) and world.grid.is_guest_reachable(member.cell, seat) \
						and not reachable.has(seat):
					reachable.append(seat)
			choices.append(reachable)
		var seats: Array[Vector2i] = []
		if _match(choices, 0, seats):
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
	for guest: CustomerAgent in guests:
		var table: PlacedItem = world.grid.item(party.table_item_id)
		if table == null or table.reserved_by(guest.seat_cell) != guest.id \
				or not table.seat_cells.has(guest.seat_cell) or not world.grid.is_walkable(guest.seat_cell):
			requeue(party, world, sim)
			return
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
