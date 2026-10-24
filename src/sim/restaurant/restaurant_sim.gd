class_name RestaurantSim
extends RefCounted
## Owns one service's guests and tickets, independently of rendering or economy.

signal customer_arrived(customer: CustomerAgent)
signal customer_paid(customer: CustomerAgent, order: Order, amount: int)
signal customer_left(customer: CustomerAgent, reason: StringName)
## Emitted once service has closed and every guest's departure is recorded,
## so the day's numbers are final. Listen to this, not the clock, for reports.
signal service_closed(day: int)

var world: SimWorld
var orders: OrderBook = OrderBook.new()
## Ingredient stock the kitchen takes from. The game session points this at
## Economy.stock; tests can use their own.
var stock: Stock = Stock.new()
var menu: Array[RecipeDef] = []
var spawner: CustomerSpawner
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var served_today: int = 0
var lost_today: int = 0
var leave_reasons_today: Dictionary[StringName, int] = {}

var _departed: Dictionary[int, bool] = {}


## Builds the layout, its starting staff, and its tier-one menu.
static func create(layout: ShopLayout, content: ContentDB, seed: int, errors: Array[String]) -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = ShopBuilder.build(layout, content, errors)
	sim.rng.seed = seed
	sim.spawner = CustomerSpawner.new(sim.rng)
	for role: StringName in [&"cook", &"server"]:
		if not layout.staff_spawns.has(role):
			errors.append("%s: missing %s spawn" % [layout.id, role])
			continue
		var staff: StaffAgent = StaffAgent.new(role)
		staff.cell = layout.staff_spawns[role]
		sim.world.add_agent(staff)
	for recipe: RecipeDef in content.recipes():
		if recipe.unlock_tier == 1:
			sim.menu.append(recipe)
	sim.start_day()
	return sim


## Clears daily reports and redraws the first arrival; the caller opens the clock.
func start_day() -> void:
	served_today = 0
	lost_today = 0
	leave_reasons_today.clear()
	_departed.clear()
	orders.prune_finished()
	spawner.reset()


## One fixed world tick, arrivals, then departed-guest cleanup.
func advance() -> void:
	var was_closed: bool = world.clock.phase == SimClock.Phase.CLOSED
	world.advance()
	spawner.advance(self)
	for customer: CustomerAgent in customers():
		if world.clock.phase == SimClock.Phase.CLOSED:
			customer.leave_reason = &"closing"
		elif customer.state != CustomerAgent.State.LEFT:
			continue
		world.remove_agent(customer)
		record_departure(customer)
	if world.clock.phase == SimClock.Phase.LAST_ORDERS and customers().is_empty():
		world.clock.notify_restaurant_empty()
	if not was_closed and world.clock.phase == SimClock.Phase.CLOSED:
		service_closed.emit(world.clock.day)


## Uses `random` for arrivals (the spawner and future guests). The game session
## passes GameState.rng(&"customers") so the stream is saved and seeded per run.
func use_rng(random: RandomNumberGenerator) -> void:
	rng = random
	spawner.rng = random


## Adds a guest using an independent random stream (also useful for scenarios).
func add_customer(entry: Vector2i, random: RandomNumberGenerator) -> CustomerAgent:
	var customer: CustomerAgent = CustomerAgent.new(self, random)
	customer.cell = entry
	world.add_agent(customer)
	world.log_event("Guest #%d arrived" % customer.id)
	customer_arrived.emit(customer)
	return customer


## Current guests in stable agent-id order.
func customers() -> Array[CustomerAgent]:
	var out: Array[CustomerAgent] = []
	for agent: SimAgent in world.agents:
		if agent is CustomerAgent:
			out.append(agent as CustomerAgent)
	return out


## Called once by a paying guest; listeners connect economy or reports here.
func pay(customer: CustomerAgent, order: Order) -> void:
	if customer.paid:
		return
	customer.paid = true
	served_today += 1
	customer_paid.emit(customer, order, order.price)


## Accounts for a departure once, including direct world removal and repeated cleanup.
func record_departure(customer: CustomerAgent) -> void:
	if customer.departure_recorded or _departed.has(customer.id):
		return
	_departed[customer.id] = true
	customer.departure_recorded = true
	if not customer.paid and customer.leave_reason == &"happy":
		customer.leave_reason = &"removed"
	var reason: StringName = customer.leave_reason
	leave_reasons_today[reason] = leave_reasons_today.get(reason, 0) + 1
	if not customer.paid:
		lost_today += 1
	world.log_event("Guest #%d left: %s" % [customer.id, reason])
	customer_left.emit(customer, reason)
