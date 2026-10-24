class_name CustomerAgent
extends SimAgent
## One guest's bounded visit. The parent is weak so owning guests cannot form a cycle.

enum State { ARRIVING, QUEUED, WALKING_TO_SEAT, ORDERING, WAITING_FOOD,
	EATING, PAYING, LEAVING, LEFT }

enum MoodBand { HAPPY, WAITING, IMPATIENT, ABOUT_TO_LEAVE }

const MOOD_HAPPY_THRESHOLD: float = 0.6
const MOOD_WAITING_THRESHOLD: float = 0.35
const MOOD_IMPATIENT_THRESHOLD: float = 0.15
const MOOD_WAITING_STATES: Array[int] = [State.QUEUED, State.ORDERING, State.WAITING_FOOD]
const MOOD_LABELS: Array[String] = ["content", "waiting patiently", "getting impatient", "about to leave"]

## A seat walk must recover well before the food-wait timeout.
const SEAT_WALK_LIMIT: int = 200

var state: State = State.ARRIVING
var queue_patience: int = 300
var food_patience: int = 1200
var eat_ticks: int = 300
var table_item_id: int = 0
var seat_cell: Vector2i = SimGrid.NO_CELL
var order: Order = null
var leave_reason: StringName = &"happy"
var paid: bool = false
## The floor seen on arrival, before this guest can add their own door spot.
var arrival_dirt_fraction: float = 0.0
## Survives morning report resets so stale removal callbacks cannot count twice.
var departure_recorded: bool = false
var rng: RandomNumberGenerator

var _restaurant: WeakRef
var _task: SimTask = null
var _queue_wait: int = 0
var _food_wait: int = 0
var _walk_wait: int = 0
var _eating: int = 0
var _exit_unreachable: int = 0
var _ordering_block_logged: bool = false


## Receives a private random stream; never retains its owning restaurant strongly.
func _init(restaurant: RestaurantSim, random: RandomNumberGenerator) -> void:
	role = &"customer"
	_restaurant = weakref(restaurant)
	rng = random


## Reasons a guest can give for leaving that the player should see as-is.
## Any other kitchen failure (an internal reason such as a dropped task or a
## missing station) becomes &"kitchen_failed"; the raw reason is in the log.
const PLAYER_REASONS: Array[StringName] = [
	&"out_of_stock", &"waited_too_long", &"closing", &"no_table", &"too_expensive", &"no_clean_plates",
]


## Maps an order's cancellation reason to the reason a guest gives the player.
static func player_reason(raw: StringName) -> StringName:
	return raw if PLAYER_REASONS.has(raw) else &"kitchen_failed"


## Advances movement and the visit state, including all timeout backstops.
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
		if table == null or table.reserved_by(seat_cell) != id or not world.grid.is_walkable(seat_cell):
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
func why() -> String:
	match state:
		State.ARRIVING:
			return "Arriving: looking for a table"
		State.QUEUED:
			return _waiting_why("Waiting by the door for a free table")
		State.WALKING_TO_SEAT:
			return "Walking to my seat"
		State.ORDERING:
			return _waiting_why("Waiting for a server to take my order")
		State.WAITING_FOOD:
			return _waiting_why("Waiting for food (%s), %ds of patience left" % [order.recipe_id,
				ceili(float(maxi(0, food_patience - _food_wait)) / SimClock.TICKS_PER_SECOND)])
		State.EATING:
			return "Enjoying my meal"
		State.PAYING:
			return "Paying for my meal"
		State.LEAVING, State.LEFT:
			return "Leaving: %s" % String(leave_reason).replace("_", " ")
	return "Visiting the restaurant"


## A read-only fraction of the patience relevant to this exact state.
## Walking has its own recovery limit, but is not a mood waiting state.
func mood() -> float:
	match state:
		State.QUEUED:
			return _patience_fraction(_queue_wait, queue_patience)
		State.ORDERING, State.WAITING_FOOD:
			return _patience_fraction(_food_wait, food_patience)
	return 1.0


func mood_band() -> int:
	var value: float = mood()
	if value >= MOOD_HAPPY_THRESHOLD:
		return MoodBand.HAPPY
	if value >= MOOD_WAITING_THRESHOLD:
		return MoodBand.WAITING
	if value >= MOOD_IMPATIENT_THRESHOLD:
		return MoodBand.IMPATIENT
	return MoodBand.ABOUT_TO_LEAVE


## Detached review inputs from this visit's actual waits and charged price.
## The caller supplies the recipe's unchanged standard price and the dirt
## fraction retained from arrival, so later mopping cannot rewrite this visit.
func review_visit(standard_price: int, dirt_fraction: float = 0.0) -> ReviewVisit:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = paid
	visit.closing = leave_reason == &"closing"
	visit.queue_wait_fraction = float(maxi(0, _queue_wait)) / float(maxi(1, queue_patience))
	visit.food_wait_fraction = float(maxi(0, _food_wait)) / float(maxi(1, food_patience))
	if order != null and standard_price > 0:
		visit.price_ratio = float(order.price) / float(standard_price)
	visit.dirt_fraction = dirt_fraction
	return visit


func _waiting_why(text: String) -> String:
	return "%s (%s)" % [text, MOOD_LABELS[mood_band()]]


static func _patience_fraction(waited: int, budget: int) -> float:
	if budget <= 0:
		return 0.0
	# Clamp before subtraction so even extreme counters cannot overflow.
	var elapsed: int = clampi(waited, 0, budget)
	return float(budget - elapsed) / float(budget)


## Removal always releases the seat and withdraws unfinished work and tickets.
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
		if not _ordering_block_logged:
			world.log_event("Guest #%d cannot order: no walkable neighbour at seat %s" % [id, seat_cell])
			_ordering_block_logged = true
		return
	_task = SimTask.new(&"take_order", &"server", "Take guest #%d's order" % id)
	_task.priority = 2
	_task.payload["customer_id"] = id
	_task.steps.append(TaskStep.go_to_cell(target, "walking to guest"))
	_task.steps.append(TaskStep.work(30, "taking order", _take_order))
	world.board.post(_task, world.now)


func _take_order(server: SimAgent) -> bool:
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
	var price: int = sim.price_of(recipe)
	var chance: float = sim.price_walkout_chance(recipe)
	# Standard/cheaper prices preserve the existing guest stream exactly.
	if chance > 0.0 and rng.randf() < chance:
		_leave(sim.world, sim, &"too_expensive")
		return true
	order = Order.new()
	order.customer_id = id
	order.table_item_id = table_item_id
	order.seat_cell = seat_cell
	order.recipe_id = recipe.id
	order.price = price
	# Apply once, after the ticket replay guard, while food patience still matters.
	if server is StaffAgent:
		food_patience = roundi(food_patience * (server as StaffAgent).food_patience_multiplier)
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
		sim.orders.set_state(order, Order.State.CANCELLED, leave_reason if leave_reason != &"happy" else &"customer_left")


func _release_seat(world: SimWorld, dirty: bool = true) -> void:
	var table: PlacedItem = world.grid.item(table_item_id)
	if table != null and table.reserved_by(seat_cell) == id:
		var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
		if dirty and cell == seat_cell and sim != null and sim.kitchen != null:
			sim.kitchen.mark_table_dirty(table.id, order.id if order != null else 0)
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
