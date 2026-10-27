extends RefCounted
## Frozen singleton oracle from exact main 1f9804e5afa71ca5ef9675782dc8e83577bed412.
## Only party integration boundaries are frozen; real kitchen, staff, reviews,
## paths and clocks are shared. Do not refresh these methods from feature code.

class MainSpawner extends CustomerSpawner:
	func _init(random: RandomNumberGenerator) -> void:
		super(random)

	func advance(sim: RestaurantSim) -> void:
		if sim.world.clock.phase != SimClock.Phase.OPEN:
			return
		if _remaining < 0:
			reset()
		_remaining -= 1
		if _remaining > 0:
			return
		var entries: Array[Vector2i] = sim.world.grid.entries()
		if not entries.is_empty():
			var kind: CustomerType = null
			if sim.customer_types != null:
				kind = CustomerTypePicker.choose(sim.customer_types, sim.customer_level,
					sim.review_book.average(), rng)
			if sim.customer_types == null or kind != null:
				var entry: Vector2i = entries[rng.randi_range(0, entries.size() - 1)]
				var customer_rng: RandomNumberGenerator = RandomNumberGenerator.new()
				customer_rng.seed = rng.randi()
				sim.add_customer(entry, customer_rng, kind)
		_remaining = _gap()

class MainCustomer extends CustomerAgent:
	func _init(restaurant: RestaurantSim, random: RandomNumberGenerator) -> void:
		super(restaurant, random)

	func tick(world: SimWorld) -> void:
		var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
		if sim == null:
			state = State.LEFT
			return
		# RestaurantSim removes remaining guests on this same CLOSED tick.
		if world.clock.phase == SimClock.Phase.CLOSED:
			return
		if state >= State.WALKING_TO_SEAT and state <= State.PAYING:
			var table: PlacedItem = world.grid.item(table_item_id)
			if table == null or not table.seat_cells.has(seat_cell) \
					or table.reserved_by(seat_cell) != id or not world.grid.is_walkable(seat_cell):
				if state == State.WALKING_TO_SEAT:
					_requeue(world, sim)
				else:
					_leave(world, sim, &"no_table")
		if state == State.ORDERING or state == State.WAITING_FOOD:
			# Terminal kitchen results win over the patience deadline on the same tick.
			if order != null and order.state == Order.State.CANCELLED:
				_leave(world, sim, player_reason(order.cancellation_reason))
			elif order != null and order.state == Order.State.DELIVERED:
				state = State.EATING
				_eating = 0
			else:
				_food_wait += 1
				if _food_wait >= food_patience:
					_leave(world, sim, &"waited_too_long")
		match state:
			State.ARRIVING:
				if not _try_seat(world):
					state = State.QUEUED
					_queue_inside(world)
			State.QUEUED:
				if _queue_wait >= queue_patience:
					_leave(world, sim, &"no_table")
				elif not _try_seat(world):
					_queue_inside(world)
					_queue_wait += 1
					if _queue_wait >= queue_patience:
						_leave(world, sim, &"no_table")
			State.WALKING_TO_SEAT:
				_walk_wait += 1
				if _walk_wait >= SEAT_WALK_LIMIT:
					_requeue(world, sim)
				else:
					_walk_to_seat(world, sim)
			State.ORDERING:
				if _task == null or _task.state == SimTask.State.CANCELLED:
					_post_order_task(world, sim)
			State.WAITING_FOOD:
				pass
			State.EATING:
				_eating += 1
				if _eating >= eat_ticks:
					state = State.PAYING
			State.PAYING:
				sim.pay(self, order)
				_leave(world, sim, &"happy")
			State.LEAVING:
				_walk_to_exit(world)


	## Friendly status text suitable for the guest inspector.

	func on_removed(world: SimWorld) -> void:
		var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
		_cancel_work(world, sim)
		_release_seat(world)
		state = State.LEFT
		if sim != null:
			sim.record_departure(self)

	func _try_seat(world: SimWorld) -> bool:
		var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
		for table: PlacedItem in world.grid.items():
			# Definition-backed dining belongs to a physical table/counter. A chair
			# contributes its valid cells there rather than serving meals on its own.
			# Untyped synthetic grid fixtures retain their established seat contract.
			var definition: ItemDef = table.def as ItemDef
			if definition != null and definition.category != ItemDef.Category.TABLE:
				continue
			if sim != null and sim.kitchen != null and sim.kitchen.is_table_dirty(table.id):
				continue
			for seat: Vector2i in table.seat_cells:
				if table.reserved_by(seat) != -1 or not world.grid.is_walkable(seat):
					continue
				if not world.grid.is_reachable(cell, seat) or not table.reserve(seat, id):
					continue
				if not set_destination(world.grid, seat):
					table.release(seat, id)
					continue
				table_item_id = table.id
				seat_cell = seat
				_walk_wait = 0
				_ordering_block_logged = false
				state = State.WALKING_TO_SEAT
				return true
		return false

	func _walk_to_seat(world: SimWorld, sim: RestaurantSim) -> void:
		if needs_repath or path.is_empty():
			if not set_destination(world.grid, seat_cell):
				_requeue(world, sim)
				return
		var result: MoveResult = step_move(world)
		if result == MoveResult.BLOCKED:
			if not set_destination(world.grid, seat_cell):
				_requeue(world, sim)
		elif result == MoveResult.ARRIVED and cell == seat_cell:
			state = State.ORDERING
			_post_order_task(world, sim)

	func _requeue(world: SimWorld, sim: RestaurantSim) -> void:
		_release_seat(world, false)
		table_item_id = 0
		seat_cell = SimGrid.NO_CELL
		clear_path()
		# Failed walks consume the same bounded search budget, so repeated recovery
		# cannot keep a guest alive forever even if its movement speed is zero.
		_queue_wait += _walk_wait
		_walk_wait = 0
		state = State.QUEUED
		if _queue_wait >= queue_patience:
			_leave(world, sim, &"no_table")

	func _leave(world: SimWorld, sim: RestaurantSim, reason: StringName) -> void:
		if state >= State.LEAVING:
			return
		leave_reason = reason
		_cancel_work(world, sim)
		_release_seat(world)
		clear_path()
		state = State.LEAVING

class MainRestaurant extends RestaurantSim:
	func add_customer(entry: Vector2i, random: RandomNumberGenerator, kind: CustomerType = null) -> CustomerAgent:
		if kind != null and not kind.is_valid():
			return null
		var customer: CustomerAgent = MainCustomer.new(self, random)
		if kind != null:
			customer.configure_type(kind)
		customer.cell = entry
		# Only a real service arrival can dirty the floor or consume its stream.
		if cleanliness != null and world.clock.phase == SimClock.Phase.OPEN:
			customer.arrival_dirt_fraction = cleanliness.dirt_fraction()
			var patience_scale: float = cleanliness.patience_multiplier()
			customer.queue_patience = maxi(1, roundi(float(customer.queue_patience) * patience_scale))
			customer.food_patience = maxi(1, roundi(float(customer.food_patience) * patience_scale))
			var spot: Vector2i = cleanliness.try_spawn_on_arrival(entry)
			if spot != SimGrid.NO_CELL and clean_tasks != null:
				clean_tasks.sync_spots()
		if world.clock.phase == SimClock.Phase.OPEN:
			customer.queue_patience = _vibe_patience(customer.queue_patience, _vibe_result.patience_multiplier)
			customer.food_patience = _vibe_patience(customer.food_patience, _vibe_result.patience_multiplier)
			customer.vibe_review_bonus = _vibe_result.raw_review_bonus
			if _vibe_result.score > 0.0 and not _vibe_result.active_theme.is_empty():
				customer.vibe_theme_label = _vibe_result.theme_label
		world.add_agent(customer)
		world.log_event("Guest #%d arrived" % customer.id)
		customer_arrived.emit(customer)
		return customer


	## Current guests in stable agent-id order.
