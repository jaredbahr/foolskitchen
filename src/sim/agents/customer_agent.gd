class_name CustomerAgent
extends SimAgent
## One guest's bounded visit. The parent is weak so owning guests cannot form a cycle.

enum State { ARRIVING, QUEUED, WALKING_TO_SEAT, ORDERING, WAITING_FOOD,
	EATING, PAYING, LEAVING, LEFT }

var state: State = State.ARRIVING
var queue_patience: int = 300
var food_patience: int = 1200
var eat_ticks: int = 300
var table_item_id: int = 0
var seat_cell: Vector2i = SimGrid.NO_CELL
var order: Order = null
var leave_reason: StringName = &"happy"
var paid: bool = false
var rng: RandomNumberGenerator

var _restaurant: WeakRef
var _task: SimTask = null
var _queue_wait: int = 0
var _food_wait: int = 0
var _walk_wait: int = 0
var _eating: int = 0
var _exit_unreachable: int = 0


## Receives a private random stream; never retains its owning restaurant strongly.
func _init(restaurant: RestaurantSim, random: RandomNumberGenerator) -> void:
	role = &"customer"
	_restaurant = weakref(restaurant)
	rng = random


## Advances movement and the visit state, including all timeout backstops.
func tick(world: SimWorld) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		state = State.LEFT
		return
	if state >= State.WALKING_TO_SEAT and state <= State.PAYING:
		var table: PlacedItem = world.grid.item(table_item_id)
		if table == null or table.reserved_by(seat_cell) != id or not world.grid.is_walkable(seat_cell):
			_leave(world, sim, &"no_table")
	if state == State.ORDERING or state == State.WAITING_FOOD:
		# Delivery wins over the deadline on the same tick.
		if order != null and order.state == Order.State.DELIVERED:
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
			if not _try_seat(world):
				_queue_inside(world)
				_queue_wait += 1
				if _queue_wait >= queue_patience:
					_leave(world, sim, &"no_table")
		State.WALKING_TO_SEAT:
			_walk_wait += 1
			if _walk_wait >= food_patience:
				_leave(world, sim, &"waited_too_long")
			elif _move(world, seat_cell):
				state = State.ORDERING
				_post_order_task(world, sim)
		State.ORDERING:
			if _task == null or _task.state == SimTask.State.CANCELLED:
				_post_order_task(world, sim)
		State.WAITING_FOOD:
			if order.state == Order.State.CANCELLED:
				_leave(world, sim, &"order_cancelled")
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
func why() -> String:
	match state:
		State.ARRIVING:
			return "Arriving: looking for a table"
		State.QUEUED:
			return "Waiting by the door for a free table"
		State.WALKING_TO_SEAT:
			return "Walking to my seat"
		State.ORDERING:
			return "Waiting for a server to take my order"
		State.WAITING_FOOD:
			return "Waiting for food (%s), %ds of patience left" % [order.recipe_id,
				ceili(float(maxi(0, food_patience - _food_wait)) / SimClock.TICKS_PER_SECOND)]
		State.EATING:
			return "Enjoying my meal"
		State.PAYING:
			return "Paying for my meal"
		State.LEAVING, State.LEFT:
			return "Leaving: %s" % String(leave_reason).replace("_", " ")
	return "Visiting the restaurant"


## Removal always releases the seat and withdraws unfinished work and tickets.
func on_removed(world: SimWorld) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	_cancel_work(world, sim)
	_release_seat(world)
	state = State.LEFT


func _try_seat(world: SimWorld) -> bool:
	for table: PlacedItem in world.grid.items():
		var seat: Vector2i = world.grid.free_seat_cell(table)
		if seat == SimGrid.NO_CELL:
			continue
		if not table.reserve(seat, id):
			continue
		table_item_id = table.id
		seat_cell = seat
		state = State.WALKING_TO_SEAT
		set_destination(world.grid, seat)
		return true
	return false


func _queue_inside(world: SimWorld) -> void:
	if world.grid.terrain(cell) == SimGrid.Terrain.FLOOR:
		return
	for neighbour: Vector2i in world.grid.walkable_neighbours(cell):
		if world.grid.terrain(neighbour) == SimGrid.Terrain.FLOOR:
			_move(world, neighbour)
			return


func _move(world: SimWorld, destination: Vector2i) -> bool:
	if needs_repath or path.is_empty():
		if not set_destination(world.grid, destination):
			return false
	var result: MoveResult = step_move(world)
	if result == MoveResult.BLOCKED:
		set_destination(world.grid, destination)
	return result == MoveResult.ARRIVED and cell == destination


func _post_order_task(world: SimWorld, sim: RestaurantSim) -> void:
	if sim.menu.is_empty():
		_leave(world, sim, &"no_menu")
		return
	var neighbours: Array[Vector2i] = world.grid.walkable_neighbours(seat_cell)
	# Closest to the seat; fixed neighbour order breaks distance ties.
	var target: Vector2i = SimGrid.NO_CELL
	var distance: float = INF
	for neighbour: Vector2i in neighbours:
		var candidate: float = GridMath.octile(seat_cell, neighbour)
		if candidate < distance:
			distance = candidate
			target = neighbour
	if target == SimGrid.NO_CELL:
		return
	_task = SimTask.new(&"take_order", &"server", "Take guest #%d's order" % id)
	_task.priority = 2
	_task.payload["customer_id"] = id
	_task.steps.append(TaskStep.go_to_cell(target, "walking to guest"))
	_task.steps.append(TaskStep.work(30, "taking order", _take_order))
	world.board.post(_task, world.now)


func _take_order(_server: SimAgent) -> bool:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return false
	# A dropped task can replay its callback; a ticket is only placed once.
	if order != null:
		return order.state != Order.State.CANCELLED
	if state != State.ORDERING:
		return false
	if sim.menu.is_empty():
		return false
	var recipe: RecipeDef = sim.menu[rng.randi_range(0, sim.menu.size() - 1)]
	order = Order.new()
	order.customer_id = id
	order.table_item_id = table_item_id
	order.seat_cell = seat_cell
	order.recipe_id = recipe.id
	order.price = recipe.standard_price
	state = State.WAITING_FOOD
	sim.orders.place(order, sim.world.now)
	return true


func _leave(world: SimWorld, sim: RestaurantSim, reason: StringName) -> void:
	if state >= State.LEAVING:
		return
	leave_reason = reason
	_cancel_work(world, sim)
	_release_seat(world)
	clear_path()
	state = State.LEAVING


func _cancel_work(world: SimWorld, sim: RestaurantSim) -> void:
	if _task != null:
		world.board.cancel(_task, &"customer_left")
		_task = null
	if sim != null and order != null:
		sim.orders.set_state(order, Order.State.CANCELLED)


func _release_seat(world: SimWorld) -> void:
	var table: PlacedItem = world.grid.item(table_item_id)
	if table != null:
		table.release(seat_cell, id)


func _walk_to_exit(world: SimWorld) -> void:
	if needs_repath or path.is_empty():
		var route: Array[Vector2i] = world.grid.find_path_to_any(cell, world.grid.entries())
		if route.is_empty():
			_exit_unreachable += 1
			if _exit_unreachable >= 100:
				world.log_event("Guest #%d removed: exit unreachable for 100 ticks" % id)
				state = State.LEFT
			return
		set_destination(world.grid, route.back())
		_exit_unreachable = 0
	match step_move(world):
		MoveResult.ARRIVED:
			state = State.LEFT
		MoveResult.BLOCKED:
			clear_path()
