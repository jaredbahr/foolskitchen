extends TestCase
## Guest lifecycle, deterministic arrivals and three complete days of imperfect service.

const LAYOUT: String = "res://data/layouts/tier1_hole_in_the_wall.tres"

class FakeKitchen extends RefCounted:
	## A bounded test double, never used by the game.
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	var mixed: bool = false
	var abandoned: int = 0
	var _sim: WeakRef
	var _due: Dictionary[int, int] = {}

	func _init(sim: RestaurantSim, varied: bool = false) -> void:
		_sim = weakref(sim)
		mixed = varied
		random.seed = 98765
		sim.orders.order_placed.connect(_on_order_placed)

	func _on_order_placed(order: Order) -> void:
		var sim: RestaurantSim = _sim.get_ref() as RestaurantSim
		if mixed and random.randi_range(0, 3) == 0:
			abandoned += 1
			return
		_due[order.id] = sim.world.now + (random.randi_range(10, 250) if mixed else 10)
		sim.orders.set_state(order, Order.State.COOKING)

	## Delivers due tickets in id order, ignoring guests who already cancelled.
	func advance() -> void:
		var sim: RestaurantSim = _sim.get_ref() as RestaurantSim
		var ids: Array[int] = []
		ids.assign(_due.keys())
		ids.sort()
		for id: int in ids:
			var order: Order = sim.orders.get_order(id)
			if order == null or order.state == Order.State.CANCELLED:
				_due.erase(id)
			elif sim.world.now >= _due[id]:
				sim.orders.set_state(order, Order.State.READY)
				sim.orders.set_state(order, Order.State.DELIVERED)
				_due.erase(id)

var _content: ContentDB
var _sim: RestaurantSim
var _log: PackedStringArray = []
var _arrived: Dictionary[int, bool] = {}
var _paid: Dictionary[int, int] = {}
var _left: Dictionary[int, StringName] = {}
var _ready: int = 0
var _delivered: int = 0
var _cancelled: int = 0


## Loads real content once per test and starts from a closed morning.
func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_sim = _create(123)


## Drops local ownership; method signal connections do not retain the receiver.
func after_each() -> void:
	_sim = null
	_content = null


## The order book assigns stable ids and keeps both terminal states immutable.
func test_order_book_terminal_states_and_signal_idempotence() -> void:
	var book: OrderBook = OrderBook.new()
	book.order_ready.connect(_on_ready)
	book.order_delivered.connect(_on_delivered)
	book.order_cancelled.connect(_on_cancelled)
	var first: Order = Order.new()
	var second: Order = Order.new()
	assert_eq(book.place(first, 12), 1)
	assert_eq(book.place(first, 50), 1)
	assert_eq(first.placed_tick, 12)
	assert_eq(book.place(second, 13), 2)
	assert_eq(book.orders_in_state(Order.State.PLACED), [first, second] as Array[Order])
	book.set_state(first, Order.State.READY)
	book.set_state(first, Order.State.READY)
	book.set_state(first, Order.State.DELIVERED)
	book.set_state(first, Order.State.CANCELLED)
	book.set_state(second, Order.State.CANCELLED)
	book.set_state(second, Order.State.READY)
	assert_eq(first.state, Order.State.DELIVERED)
	assert_eq(second.state, Order.State.CANCELLED)
	assert_eq(_ready, 1)
	assert_eq(_delivered, 1)
	assert_eq(_cancelled, 1)
	assert_eq(book.get_order(2), second)


## A server takes the guest's order and the real recipe price reaches payment.
func test_single_guest_seats_orders_eats_pays_and_leaves() -> void:
	_no_arrivals()
	var kitchen: FakeKitchen = FakeKitchen.new(_sim)
	var guest: CustomerAgent = _guest()
	guest.eat_ticks = 3
	var visited: Dictionary[int, bool] = {guest.state: true}
	_sim.world.clock.start_service()
	for tick: int in 2000:
		_sim.advance()
		kitchen.advance()
		visited[guest.state] = true
		if guest.state == CustomerAgent.State.LEFT:
			break
	for state: int in [CustomerAgent.State.ARRIVING, CustomerAgent.State.WALKING_TO_SEAT,
		CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD, CustomerAgent.State.EATING,
		CustomerAgent.State.PAYING, CustomerAgent.State.LEAVING, CustomerAgent.State.LEFT]:
		assert_true(visited.has(state), "visited state %d" % state)
	assert_not_null(guest.order)
	assert_eq(_paid.get(guest.id, -1), _content.recipe(guest.order.recipe_id).standard_price)
	assert_eq(_left.get(guest.id, &""), &"happy")
	guest.on_removed(_sim.world)
	_sim.record_departure(guest)
	assert_eq(_sim.served_today, 1)
	assert_eq(_sim.lost_today, 0)
	assert_eq(_sim.leave_reasons_today, {&"happy": 1})
	assert_eq(_left.size(), 1)
	_assert_drained()


## With six reserved seats the seventh guest waits inside, then gives up.
func test_seventh_guest_queues_and_leaves_with_no_table() -> void:
	_no_arrivals()
	for index: int in 6:
		var seated: CustomerAgent = _guest()
		seated.food_patience = 5000
	var seventh: CustomerAgent = _guest()
	seventh.queue_patience = 20
	_sim.advance()
	assert_eq(seventh.state, CustomerAgent.State.QUEUED)
	_run(15)
	assert_eq(_sim.world.grid.terrain(seventh.cell), SimGrid.Terrain.FLOOR)
	_run(200)
	assert_eq(seventh.state, CustomerAgent.State.LEFT)
	assert_eq(_left.get(seventh.id, &""), &"no_table")
	assert_eq(_sim.lost_today, 1)


## No kitchen means timeout, a cancelled ticket, and a reusable seat.
func test_missing_food_cancels_ticket_and_releases_seat() -> void:
	_no_arrivals()
	var guest: CustomerAgent = _guest()
	guest.food_patience = 250
	_run(1000)
	assert_not_null(guest.order, "server took the order before patience ran out")
	assert_eq(guest.order.state, Order.State.CANCELLED)
	assert_eq(_left.get(guest.id, &""), &"waited_too_long")
	assert_eq(_sim.world.grid.item(guest.table_item_id).reserved_by(guest.seat_cell), -1)
	assert_true(guest.why().contains("waited too long"))
	_assert_drained()


## Customers waiting for an unavailable server also time out and cancel tasks.
func test_patience_includes_order_taking() -> void:
	_no_arrivals()
	for agent: SimAgent in _sim.world.agents.duplicate():
		if agent.role == &"server":
			_sim.world.remove_agent(agent)
	var guest: CustomerAgent = _guest()
	guest.food_patience = 20
	_run(500)
	assert_eq(_left.get(guest.id, &""), &"waited_too_long")
	assert_true(guest.order == null)
	_assert_drained()


## Unreachable exits remove the guest after exactly the bounded safety interval.
func test_unreachable_exit_is_logged_and_does_not_hold_a_seat() -> void:
	_no_arrivals()
	var guest: CustomerAgent = _guest()
	guest.queue_patience = 1
	# No usable tables, and no street remains to walk back to.
	for item: PlacedItem in _sim.world.grid.items():
		for seat: Vector2i in item.seat_cells:
			item.reserve(seat, 999)
	for entry: Vector2i in _sim.world.grid.entries():
		_sim.world.grid.set_terrain(entry, SimGrid.Terrain.FLOOR)
	_run(101)
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	_sim.advance()
	assert_eq(guest.state, CustomerAgent.State.LEFT)
	assert_eq(_left.get(guest.id, &""), &"no_table")
	assert_true(String(" ").join(_sim.world.event_log).contains("exit unreachable for 100 ticks"))


## Direct world removal uses the same ticket, task and reservation cleanup.
func test_external_removal_cleans_up_customer_resources() -> void:
	_no_arrivals()
	var guest: CustomerAgent = _guest()
	for tick: int in 500:
		_sim.advance()
		if guest.order != null:
			break
	assert_not_null(guest.order)
	_sim.world.remove_agent(guest)
	_run(2)
	assert_eq(guest.order.state, Order.State.CANCELLED)
	assert_eq(_left.get(guest.id, &""), &"removed")
	assert_eq(_sim.lost_today, 1)
	assert_eq(_sim.served_today, 0)
	assert_eq(_sim.leave_reasons_today, {&"removed": 1})
	assert_eq(_arrived.size(), _paid.size() + _sim.lost_today)
	# Both the world hook and normal sweep can reach the accounting boundary.
	_sim.world.remove_agent(guest)
	_sim.record_departure(guest)
	assert_eq(_left.size(), 1)
	assert_eq(_sim.lost_today, 1)
	assert_eq(_sim.leave_reasons_today, {&"removed": 1})
	_assert_drained()


## Arrival countdowns do not run in morning, last orders, or closed phases.
func test_spawns_only_during_open_and_empty_last_orders_closes() -> void:
	_sim.spawner.min_gap = 1
	_sim.spawner.max_gap = 1
	_sim.start_day()
	_run(5)
	assert_eq(_arrived.size(), 0)
	_sim.world.clock.start_service()
	_run(3)
	assert_eq(_arrived.size(), 3)
	_sim.world.clock.open_ticks = _sim.world.clock.phase_tick + 1
	_sim.advance()
	assert_eq(_arrived.size(), 3)
	assert_eq(_sim.world.clock.phase, SimClock.Phase.LAST_ORDERS)
	for guest: CustomerAgent in _sim.customers():
		_sim.world.remove_agent(guest)
	_sim.advance()
	assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED)
	_run(5)
	assert_eq(_arrived.size(), 3)


## The normal 900-tick deadline flushes late guests and never leaks losses into tomorrow.
func test_default_closing_deadline_clears_remaining_guests_same_day() -> void:
	_no_arrivals()
	assert_eq(_sim.world.clock.last_orders_max_ticks, 900)
	_sim.world.clock.start_service()
	_run(_sim.world.clock.open_ticks - 1)
	var guest: CustomerAgent = _guest()
	_run(900)
	assert_eq(_sim.world.clock.phase, SimClock.Phase.LAST_ORDERS)
	assert_eq(_sim.customers().size(), 1)
	assert_not_null(guest.order)
	_sim.advance()
	assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED)
	assert_eq(guest.order.state, Order.State.CANCELLED)
	assert_eq(_left.get(guest.id, &""), &"closing")
	assert_eq(_sim.lost_today, 1)
	assert_eq(_sim.leave_reasons_today, {&"closing": 1})
	_assert_drained()
	assert_true(_sim.world.clock.next_day())
	_sim.start_day()
	assert_true(_sim.orders.get_order(guest.order.id) == null)
	assert_eq(_sim._departed.size(), 0)
	# A retained old guest cannot re-enter tomorrow's reports after daily pruning.
	guest.on_removed(_sim.world)
	_sim.record_departure(guest)
	_run(5)
	assert_eq(_sim.lost_today, 0)
	assert_eq(_sim.served_today, 0)
	assert_eq(_sim.leave_reasons_today.size(), 0)
	assert_eq(_left.size(), 1)
	_assert_drained()


## A paid guest caught walking out at closing is served once and never a loss.
func test_closing_preserves_paid_guest_accounting() -> void:
	_no_arrivals()
	var kitchen: FakeKitchen = FakeKitchen.new(_sim)
	var guest: CustomerAgent = _guest()
	guest.eat_ticks = 1
	_sim.world.clock.start_service()
	for tick: int in 1000:
		_sim.advance()
		kitchen.advance()
		if guest.paid:
			break
	assert_true(guest.paid)
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	_sim.world.clock.open_ticks = _sim.world.clock.phase_tick + 1
	guest.move_speed = 0.0
	_sim.advance()
	_run(899)
	assert_eq(_sim.world.clock.phase, SimClock.Phase.LAST_ORDERS)
	_sim.advance()
	assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED)
	assert_eq(_left.get(guest.id, &""), &"closing")
	assert_eq(_paid.size(), 1)
	assert_eq(_sim.served_today, 1)
	assert_eq(_sim.lost_today, 0)
	_assert_drained()


## An unreachable first seat is skipped even when the other seat is on the same table.
func test_walled_first_seat_uses_reachable_second_seat_on_same_table() -> void:
	_no_arrivals()
	var table: PlacedItem = _simple_seating()
	var grid: SimGrid = _sim.world.grid
	var trapped: Vector2i = table.seat_cells[0]
	for neighbour: Vector2i in grid.walkable_neighbours(trapped):
		grid.set_terrain(neighbour, SimGrid.Terrain.WALL)
	var guest: CustomerAgent = _guest()
	_sim.advance()
	assert_eq(guest.table_item_id, table.id)
	assert_eq(guest.seat_cell, table.seat_cells[1])
	assert_eq(table.reserved_by(trapped), -1)
	for tick: int in 100:
		_sim.advance()
		if guest.state == CustomerAgent.State.ORDERING:
			break
	assert_eq(guest.cell, table.seat_cells[1])
	assert_eq(guest.state, CustomerAgent.State.ORDERING)


## Failed paths return a seat immediately; stalled walks have their own 200-tick limit.
func test_seat_walk_requeues_after_failed_path_or_short_limit() -> void:
	_no_arrivals()
	_simple_seating()
	var guest: CustomerAgent = _guest()
	guest.queue_patience = 1000
	guest.move_speed = 0.0
	_sim.advance()
	var table: PlacedItem = _sim.world.grid.item(guest.table_item_id)
	var seat: Vector2i = guest.seat_cell
	_run(CustomerAgent.SEAT_WALK_LIMIT)
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(table.reserved_by(seat), -1)
	guest.move_speed = 0.25
	_sim.advance()
	table = _sim.world.grid.item(guest.table_item_id)
	seat = guest.seat_cell
	# Isolate its reserved goal without making the goal itself unwalkable.
	for neighbour: Vector2i in _sim.world.grid.walkable_neighbours(seat):
		if _sim.world.grid.item_at(neighbour) == null:
			_sim.world.grid.set_terrain(neighbour, SimGrid.Terrain.WALL)
	guest.needs_repath = true
	_sim.advance()
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(table.reserved_by(seat), -1)


## Impossible order taking is visible in the log once despite repeated retries.
func test_no_order_neighbour_logs_once() -> void:
	_no_arrivals()
	_simple_seating()
	var guest: CustomerAgent = _guest()
	for tick: int in 100:
		_sim.advance()
		if guest.state == CustomerAgent.State.ORDERING:
			break
	# Cancel the original task, then block every adjacent cell from server access.
	for task: SimTask in _sim.world.board.open_tasks():
		_sim.world.board.cancel(task)
	for task: SimTask in _sim.world.board.claimed_tasks():
		_sim.world.board.cancel(task)
	for neighbour: Vector2i in _sim.world.grid.walkable_neighbours(guest.seat_cell):
		_sim.world.grid.set_terrain(neighbour, SimGrid.Terrain.WALL)
	_run(20)
	var messages: int = 0
	for message: String in _sim.world.event_log:
		if message.contains("cannot order: no walkable neighbour"):
			messages += 1
	assert_eq(messages, 1)


## Morning pruning removes terminal tickets but preserves active tickets and id order.
func test_start_day_prunes_only_finished_orders() -> void:
	var delivered: Order = Order.new()
	var cancelled: Order = Order.new()
	var active: Order = Order.new()
	_sim.orders.place(delivered, 1)
	_sim.orders.place(cancelled, 2)
	_sim.orders.place(active, 3)
	_sim.orders.set_state(delivered, Order.State.DELIVERED)
	_sim.orders.set_state(cancelled, Order.State.CANCELLED)
	_sim.orders.set_state(active, Order.State.COOKING)
	_sim.start_day()
	assert_true(_sim.orders.get_order(delivered.id) == null)
	assert_true(_sim.orders.get_order(cancelled.id) == null)
	assert_eq(_sim.orders.get_order(active.id), active)
	assert_eq(_sim.orders.orders_in_state(Order.State.COOKING), [active] as Array[Order])
	var next: Order = Order.new()
	assert_eq(_sim.orders.place(next, 4), 4)


## Identical private streams reproduce arrivals, menu choices, payments and exits.
func test_same_seed_reproduces_event_log() -> void:
	var first: PackedStringArray = _service_log(4567)
	var second: PackedStringArray = _service_log(4567)
	assert_eq(first, second)
	assert_true(first.size() > 10)


## Three complete days include random delivery delays and intentionally missing food.
func test_three_day_imperfect_kitchen_soak() -> void:
	_sim.spawner.min_gap = 80
	_sim.spawner.max_gap = 160
	assert_eq(_sim.world.clock.last_orders_max_ticks, 900)
	var kitchen: FakeKitchen = FakeKitchen.new(_sim, true)
	var total_served: int = 0
	var total_lost: int = 0
	var reasons: Dictionary[StringName, int] = {}
	for day: int in 3:
		_sim.start_day()
		assert_eq(_sim.served_today, 0)
		assert_eq(_sim.lost_today, 0)
		assert_eq(_sim.leave_reasons_today.size(), 0)
		assert_true(_sim.world.clock.start_service())
		for tick: int in 4501:
			_sim.advance()
			kitchen.advance()
			if _sim.world.clock.phase == SimClock.Phase.CLOSED and _sim.customers().is_empty():
				break
		assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED, "day %d closed" % (day + 1))
		_run(2) # A server notices a just-cancelled task on its next tick.
		_assert_drained()
		total_served += _sim.served_today
		total_lost += _sim.lost_today
		for reason: StringName in _sim.leave_reasons_today:
			reasons[reason] = reasons.get(reason, 0) + _sim.leave_reasons_today[reason]
		assert_eq(_arrived.size(), _paid.size() + total_lost)
		assert_eq(_arrived.size(), _left.size())
		for id: int in _arrived:
			assert_true(_paid.has(id) or not String(_left.get(id, &"")).is_empty())
		if day < 2:
			assert_true(_sim.world.clock.next_day())
	assert_true(total_served > 0)
	assert_true(total_lost > 0)
	assert_true(kitchen.abandoned > 0)
	assert_true(reasons.get(&"waited_too_long", 0) > 0)
	assert_true(reasons.get(&"no_table", 0) > 0)
	assert_true(reasons.get(&"closing", 0) > 0)
	print("CUSTOMER_SOAK arrivals=%d served=%d lost=%d reasons=%s" % [
		_arrived.size(), total_served, total_lost, reasons])


func _create(seed: int) -> RestaurantSim:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(load(LAYOUT) as ShopLayout, _content, seed, errors, null, false)
	assert_eq(errors, [] as Array[String])
	sim.customer_arrived.connect(_on_arrived)
	sim.customer_paid.connect(_on_paid)
	sim.customer_left.connect(_on_left)
	return sim


func _no_arrivals() -> void:
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()


func _simple_seating() -> PlacedItem:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 5))
	grid.set_terrain(Vector2i(7, 4), SimGrid.Terrain.ENTRY)
	var table: PlacedItem = grid.place(Vector2i.ONE, Vector2i(1, 2), 0, true, [],
		[Vector2i(1, 0), Vector2i(4, 0)] as Array[Vector2i])
	_sim.world = SimWorld.new(grid)
	return table


func _guest() -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	return _sim.add_customer(_sim.world.grid.entries()[0], random)


func _run(ticks: int) -> void:
	for tick: int in ticks:
		_sim.advance()


func _assert_drained() -> void:
	assert_eq(_sim.customers().size(), 0)
	assert_eq(_sim.world.board.active_count(), 0)
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY]:
		assert_eq(_sim.orders.orders_in_state(state).size(), 0, "no unfinished tickets")
	for item: PlacedItem in _sim.world.grid.items():
		for seat: Vector2i in item.seat_cells:
			assert_eq(item.reserved_by(seat), -1, "seat %s released" % seat)


func _service_log(seed: int) -> PackedStringArray:
	_log.clear()
	_arrived.clear()
	_paid.clear()
	_left.clear()
	_sim = _create(seed)
	_sim.world.clock.open_ticks = 600
	_sim.world.clock.last_orders_max_ticks = 2500
	_sim.spawner.min_gap = 80
	_sim.spawner.max_gap = 100
	_sim.start_day()
	var kitchen: FakeKitchen = FakeKitchen.new(_sim, true)
	_sim.world.clock.start_service()
	for tick: int in 3200:
		_sim.advance()
		kitchen.advance()
	return _log.duplicate()


func _on_arrived(customer: CustomerAgent) -> void:
	_arrived[customer.id] = true
	_log.append("%d arrived %d" % [_sim.world.now, customer.id])


func _on_paid(customer: CustomerAgent, order: Order, amount: int) -> void:
	assert_false(_paid.has(customer.id), "only one payment")
	_paid[customer.id] = amount
	_log.append("%d paid %d %s %d" % [_sim.world.now, customer.id, order.recipe_id, amount])


func _on_left(customer: CustomerAgent, reason: StringName) -> void:
	assert_false(_left.has(customer.id), "only one departure")
	assert_false(String(reason).is_empty(), "every guest has a reason")
	_left[customer.id] = reason
	_log.append("%d left %d %s" % [_sim.world.now, customer.id, reason])


func _on_ready(_order: Order) -> void:
	_ready += 1


func _on_delivered(_order: Order) -> void:
	_delivered += 1


func _on_cancelled(_order: Order) -> void:
	_cancelled += 1
