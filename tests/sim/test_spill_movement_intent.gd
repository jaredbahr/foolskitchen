extends TestCase
## Precise merged Kitchen lifecycle: READY tickets, real pickup WORK, carrying,
## ordinary cooperative yield, then the public last-carried-meal spill path.

const CLEAN: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")
const MESSES: MessTuning = preload("res://data/balance/messes.tres")
var _sim: RestaurantSim
var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	if _sim != null:
		if _sim.kitchen != null:
			_sim.kitchen.tidy_overnight()
		if _sim.clean_tasks != null:
			_sim.clean_tasks.tidy_overnight()
		for agent: SimAgent in _sim.world.all_agents():
			_sim.world.remove_agent(agent)
	_sim = null
	_content = null


func test_last_carried_spill_at_yield_vertex_clears_old_return_and_permits_actual_new_work() -> void:
	var fixture: Dictionary = _ready_carrier()
	if fixture.is_empty():
		return
	var server: StaffAgent = fixture["server"] as StaffAgent
	var trip: SimTask = fixture["trip"] as SimTask
	var order: Order = fixture["orders"][0] as Order
	var random: RandomNumberGenerator = fixture["random"] as RandomNumberGenerator
	if not _reach_yield(server, false):
		return
	assert_false(_sim.world.movement.snapshot()["cooperative"].is_empty())
	var pocket: Vector2i = server.cell
	var rng_before: int = random.state
	assert_true(_sim.kitchen.spill_carried_meal(server))
	assert_eq(_sim.mishaps.spills_today, 1)
	assert_eq(order.state, Order.State.PLACED, "the same live ticket takes the real recook path")
	assert_eq(trip.state, SimTask.State.CANCELLED)
	assert_eq(int(trip.payload.get("carried_count", -1)), 0)
	assert_null(server.task, "upstream immediate withdrawal releases the old trip")
	assert_false(server.carries_food())
	assert_eq(_sim.world.movement.priority(_sim.world, server), 2)
	assert_eq(random.state, rng_before, "zero authored test chances cause no incidental draw")
	assert_false(_sim.world.movement.is_yielding(server.id), "withdrawal must erase obsolete delivery intent")
	assert_false(_sim.world.movement.snapshot()["returning"].has(server.id))
	assert_true(_sim.world.movement.snapshot()["cooperative"].is_empty())
	_advance()
	assert_eq(server.cell, pocket, "the next tick must not resume the old return route")
	assert_eq(server.move_progress, 0.0)
	assert_not_null(server.task, "released staff can select the actual newly posted spill cleanup")
	if server.task != null:
		assert_ne(server.task, trip)
		assert_eq(server.task.kind, &"clean_spot")


func test_spilling_one_of_two_real_carried_meals_keeps_the_other_trip_priority_and_yield() -> void:
	var fixture: Dictionary = _ready_carrier(2)
	if fixture.is_empty():
		return
	var server: StaffAgent = fixture["server"] as StaffAgent
	var trip: SimTask = fixture["trip"] as SimTask
	if not _reach_yield(server, false):
		return
	var before: Dictionary = _sim.world.movement.snapshot()
	assert_true(_sim.kitchen.spill_carried_meal(server))
	assert_eq(int(trip.payload.get("carried_count", 0)), 1)
	assert_eq(trip.state, SimTask.State.CLAIMED)
	assert_eq(server.task, trip)
	assert_true(server.carries_food(), "a remaining picked-up meal is still physically carried")
	assert_eq(_sim.world.movement.priority(_sim.world, server), 3)
	assert_true(_sim.world.movement.is_yielding(server.id))
	assert_eq(_sim.world.movement.snapshot(), before, "remaining food must retain its actual movement recovery")
	var ready: int = 0
	var recooking: int = 0
	for order: Order in fixture["orders"]:
		ready += 1 if order.state == Order.State.READY else 0
		recooking += 1 if order.state == Order.State.PLACED else 0
	assert_eq(ready, 1)
	assert_eq(recooking, 1)


func test_last_carried_spill_mid_yield_finishes_reserved_edge_before_selecting_new_work() -> void:
	var fixture: Dictionary = _ready_carrier()
	if fixture.is_empty():
		return
	var server: StaffAgent = fixture["server"] as StaffAgent
	if not _reach_yield(server, true):
		return
	var from: Vector2i = server.cell
	var to: Vector2i = server.next_cell()
	var fraction: float = server.move_progress
	assert_true(fraction > 0.0 and fraction < 1.0)
	assert_true(_sim.kitchen.spill_carried_meal(server))
	assert_null(server.task)
	assert_false(server.carries_food())
	assert_false(_sim.world.movement.is_yielding(server.id))
	assert_true(_sim.world.movement.is_stopping(server.id))
	assert_eq(server.cell, from)
	assert_eq(server.next_cell(), to)
	assert_eq(server.move_progress, fraction)
	assert_eq(_sim.world.movement.snapshot()["next"].get(to), server.id)
	for _tick: int in 8:
		_advance()
		if not _sim.world.movement.is_stopping(server.id):
			break
		assert_null(server.task, "a reserved edge finishes without selecting productive work")
	assert_false(_sim.world.movement.is_stopping(server.id))
	assert_eq(server.cell, to, "cancellation must finish the physical edge instead of teleporting")
	assert_eq(server.move_progress, 0.0)
	assert_null(server.task)
	_advance()
	assert_not_null(server.task)
	if server.task != null:
		assert_eq(server.task.kind, &"clean_spot")


func test_actual_internal_return_route_install_keeps_the_productive_yield_overlay() -> void:
	var fixture: Dictionary = _ready_carrier()
	if fixture.is_empty():
		return
	var server: StaffAgent = fixture["server"] as StaffAgent
	var trip: SimTask = fixture["trip"] as SimTask
	if not _reach_yield(server, false):
		return
	var returning: bool = false
	for _tick: int in 32:
		_advance()
		if _sim.world.movement.snapshot()["returning"].has(server.id):
			returning = true
			break
	assert_true(returning, "the coordinator must really install its ordinary return path")
	assert_true(_sim.world.movement.is_yielding(server.id))
	assert_eq(server.task, trip)
	assert_eq(trip.state, SimTask.State.CLAIMED)
	assert_true(server.carries_food())
	assert_eq(_sim.world.movement.priority(_sim.world, server), 3)


func _ready_carrier(meals: int = 1) -> Dictionary:
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["........", "........", ".#......",
		"........", ".#......", "........", "........", ".......E"])))
	var world: SimWorld = _sim.world
	assert_not_null(world.grid.place_def(_content.item(&"fridge"), Vector2i(5, 0), 2))
	assert_not_null(world.grid.place_def(_content.item(&"prep_counter"), Vector2i(5, 2)))
	assert_not_null(world.grid.place_def(_content.item(&"stove"), Vector2i(5, 4)))
	var pass_item: PlacedItem = world.grid.place_def(_content.item(&"pass_counter"), Vector2i(2, 2))
	var table: PlacedItem = world.grid.place_def(_content.item(&"table_2"), Vector2i(0, 5), 1)
	assert_not_null(pass_item)
	assert_not_null(table)
	var recipe: RecipeDef = _content.recipe(&"burger")
	_sim.menu = [recipe]
	_sim.carry_capacity = meals
	for ingredient: IngredientDef in recipe.ingredients:
		_sim.stock.add(ingredient.id, 20, 1)
	_sim.kitchen = Kitchen.new(_sim, _content, _sim.stock)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 263
	var clean: CleanlinessTuning = CLEAN.duplicate(true) as CleanlinessTuning
	clean.arrival_chance = 0.0
	clean.seat_departure_chance = 0.0
	assert_true(_sim.configure_cleanliness(CleanlinessState.new(world.grid, clean, random), clean))
	var messes: MessTuning = MESSES.duplicate(true) as MessTuning
	messes.spill_chance_per_cell = 0.0
	messes.broken_plate_chance = 0.0
	assert_true(_sim.configure_messes(messes, random))
	# Real admitted bodies make the lower-priority actor genuinely boxed. Only
	# normal coordinator fallback can move the food-carrying winner aside.
	var blocker: SimAgent = SimAgent.new()
	blocker.cell = Vector2i(0, 3)
	world.add_agent(blocker)
	var boxed: SimAgent = SimAgent.new()
	boxed.cell = Vector2i(1, 3)
	world.add_agent(boxed)
	var server: StaffAgent = StaffAgent.new(&"server")
	server.cell = pass_item.work_cells[1]
	world.add_agent(server)
	# Precise READY-ticket setup matches upstream Kitchen tests; all payload
	# carrying truth is generated by the actual GO_TO_ITEM/pickup WORK chain.
	var orders: Array[Order] = []
	for index: int in meals:
		var order: Order = Order.new()
		order.customer_id = 900 + index
		order.table_item_id = table.id
		order.seat_cell = Vector2i(0, 4) if index == 0 else Vector2i(0, 7)
		order.recipe_id = recipe.id
		order.price = recipe.standard_price
		_sim.orders.place(order, world.now)
		_sim.orders.set_state(order, Order.State.READY)
		orders.append(order)
	assert_true(world.clock.start_service())
	for _tick: int in 32:
		_advance()
		if server.carries_food():
			break
	assert_true(server.carries_food(), "a genuine claimed trip must finish pickup WORK")
	assert_not_null(server.task)
	if not server.carries_food() or server.task == null:
		return {}
	if server.task != null:
		assert_eq(server.task.kind, &"deliver")
		assert_eq(server.task.claimed_by, server.id)
		assert_true(server.step_index >= 2)
		assert_eq(int(server.task.payload.get("carried_count", 0)), meals)
	assert_eq(world.movement.priority(world, server), 3)
	return {"server": server, "trip": server.task, "orders": orders, "random": random,
		"pass_cell": pass_item.work_cells[1]}


func _reach_yield(server: StaffAgent, partial: bool) -> bool:
	var origin: Vector2i = server.cell
	for _tick: int in 96:
		_advance()
		if not _sim.world.movement.is_yielding(server.id):
			continue
		var reached: bool = server.move_progress > 0.0 if partial else (server.move_progress == 0.0 and server.cell != origin)
		if reached:
			return true
	fail("the actual boxed encounter did not reach the declared yield movement phase")
	return false


func _advance() -> void:
	var before: Dictionary = MovementInvariants.capture(_sim.world)
	_sim.world.advance()
	assert_eq(MovementInvariants.problem(_sim.world, before), "", "every physical edge and claim stays valid")
