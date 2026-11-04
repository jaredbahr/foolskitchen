extends TestCase
## Real customer order, authored coffee ingredients/work and Kitchen READY.
## Only the opposing empty staff's ordinary route is a controlled test actor.

const WATCHDOG: int = 512
var _content: ContentDB
var _sim: RestaurantSim
var _guest: CustomerAgent
var _server: StaffAgent
var _empty: EmptyWalker
var _previous: Dictionary = {}

class EmptyWalker extends StaffAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.from_ascii(PackedStringArray([
		"#.#.#.#####", "E.........#", "########..#", "########..#", "###########"])))
	_sim.rng.seed = 8403
	_sim.spawner = CustomerSpawner.new(_sim.rng)
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.menu = [_content.recipe(&"coffee")] as Array[RecipeDef]
	var beans: IngredientDef = _content.ingredient(&"coffee_beans")
	_sim.stock.add(beans.id, 4, 1, 4 * beans.unit_cost)
	assert_not_null(_sim.world.grid.place_def(_content.item(&"coffee_machine"), Vector2i(1, 0), 2))
	var table: PlacedItem = _sim.world.grid.place_def(_content.item(&"round_table"), Vector2i(8, 2), 0)
	assert_not_null(table)
	assert_not_null(_sim.world.grid.place_def(_content.item(&"chair"), Vector2i(8, 1), 2))
	assert_true(table.seat_cells.has(Vector2i(8, 1)))
	_empty = EmptyWalker.new(&"cook", 3)
	_empty.cell = Vector2i(3, 0)
	_sim.world.add_agent(_empty)
	_server = StaffAgent.new(&"server", 3)
	_server.cell = Vector2i(5, 0)
	_sim.world.add_agent(_server)
	assert_true(_empty.id < _server.id)
	assert_true(_empty.movement_admitted and _server.movement_admitted)
	_sim.kitchen = Kitchen.new(_sim, _content, _sim.stock)
	_sim.start_day()
	assert_true(_sim.world.clock.start_service())
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 8404
	_guest = _sim.add_visitor(Vector2i(0, 1), random, null, RecipeDef.COFFEE)
	_guest.food_patience = 5000
	_guest.queue_patience = 5000
	assert_true(_guest.movement_admitted)


func after_each() -> void:
	if _sim != null and _sim.kitchen != null:
		_sim.kitchen.tidy_overnight()
	_guest = null
	_server = null
	_empty = null
	_sim = null
	_content = null


func test_actual_ready_pour_wins_head_on_against_lower_id_empty_staff_and_stops_carrying_after_serve() -> void:
	assert_true(_until_ingredients_taken(), "real order preparation reaches the authored recipe work")
	assert_eq(_guest.order.state, Order.State.COOKING)
	assert_false(_server.carries_food(), "ingredients/recipe work is not a drink in hand")
	assert_eq(_sim.world.movement.priority(_sim.world, _server), 2)
	assert_true(_until_ready(), "the real Kitchen callback makes this drink READY")
	_assert_real_ready()
	assert_true(_server.carries_food(), "a real prepared cup is nonempty hands")
	assert_eq(_sim.world.movement.priority(_sim.world, _server), 3)
	assert_eq(_sim.world.movement.priority(_sim.world, _empty), 2)
	_assert_passive_queries()
	assert_eq(_server.cell, Vector2i(1, 1), "the carry begins at its real coffee work cell")
	assert_true(_empty.set_destination(_sim.world.grid, Vector2i(2, 1)))
	var head_on: bool = false
	var empty_cleared: bool = false
	var carrier_retreat: bool = false
	var first_retreat: StringName = &""
	assert_almost_eq(_server.move_speed, _empty.move_speed, 0.000001)
	for tick: int in range(WATCHDOG):
		_advance()
		if _empty.cell == Vector2i(3, 1) and _server.cell == Vector2i(2, 1):
			head_on = true
		if head_on and _empty.cell == Vector2i(3, 0):
			empty_cleared = true
			if first_retreat.is_empty():
				first_retreat = &"empty"
		if head_on and _server.cell == Vector2i(1, 1):
			carrier_retreat = true
			if first_retreat.is_empty():
				first_retreat = &"carrier"
		if _guest.order.state == Order.State.DELIVERED:
			break
	assert_true(head_on, "the actual carrier and lower-ID empty worker meet on reciprocal cells")
	assert_true(empty_cleared, "empty hands yield into the real free pocket")
	assert_eq(first_retreat, &"empty", "the first reciprocal resolution gives way to the actual prepared cup")
	assert_false(carrier_retreat, "the ready cup keeps right of way instead of retreating for empty hands")
	assert_eq(_guest.order.state, Order.State.DELIVERED, "the real serving callback hands over this cup")
	assert_false(_server.carries_food(), "a served cup no longer grants movement priority")
	assert_eq(_sim.world.movement.priority(_sim.world, _server), 2)


func test_dropped_ready_pour_has_no_priority_until_its_real_reclaimed_recipe_replay_finishes() -> void:
	assert_true(_until_ready())
	_assert_real_ready()
	var task: SimTask = _server.task
	assert_true(_server.carries_food())
	_sim.world.board.drop(task, &"test_public_drop")
	assert_eq(task.state, SimTask.State.OPEN)
	assert_false(_server.carries_food(), "an OPEN task cannot retain carry priority")
	assert_eq(_sim.world.movement.priority(_sim.world, _server), 2)
	var reclaimed: bool = false
	for tick: int in range(WATCHDOG):
		_advance()
		if _server.task == task and task.state == SimTask.State.CLAIMED and _server.step_index == 0:
			reclaimed = true
			break
	assert_true(reclaimed, "the actual task is reclaimed through the normal board")
	assert_eq(_guest.order.state, Order.State.READY, "the prior ticket state alone is insufficient")
	assert_false(_server.carries_food(), "replayed pickup/recipe steps are not carrying")
	assert_true(_until_ready(), "the real replay reaches the ready callback again")
	assert_eq(_sim.stock.count(&"coffee_beans"), 3, "replay never takes the actual ingredients twice")
	assert_true(_server.carries_food())
	_sim.orders.set_state(_guest.order, Order.State.CANCELLED, &"target_gone")
	assert_false(_server.carries_food(), "a cancelled actual ticket/task loses carry priority")
	assert_eq(_sim.world.movement.priority(_sim.world, _server), 2)


func test_cancelled_before_ready_pour_never_gets_food_priority() -> void:
	assert_true(_until_ingredients_taken())
	assert_eq(_guest.order.state, Order.State.COOKING)
	assert_false(_server.carries_food())
	_sim.orders.set_state(_guest.order, Order.State.CANCELLED, &"target_gone")
	assert_false(_server.carries_food())
	assert_eq(_sim.world.movement.priority(_sim.world, _server), 2)
	_assert_passive_queries()


func _until_ingredients_taken() -> bool:
	for tick: int in range(2000):
		_advance()
		if _server.task != null and _server.task.kind == &"pour" and _guest.order != null \
				and _guest.order.state == Order.State.COOKING \
				and bool(_server.task.payload.get("ingredients_taken", false)):
			return true
	return false


func _until_ready() -> bool:
	for tick: int in range(2000):
		_advance()
		if _server.task != null and _server.task.kind == &"pour" and _guest.order != null \
				and _guest.order.state == Order.State.READY \
				and _server.step_index == _server.task.steps.size() - 2:
			return true
	return false


func _assert_real_ready() -> void:
	assert_eq(_guest.order.recipe_id, &"coffee")
	assert_eq(_guest.order.state, Order.State.READY)
	assert_true(_guest.order.ingredient_cost_recorded)
	assert_true(_guest.order.ingredient_cost > 0)
	assert_eq(_sim.stock.count(&"coffee_beans"), 3)
	assert_true(_server.task != null and _server.task.kind == &"pour")
	assert_eq(_server.task.state, SimTask.State.CLAIMED)
	assert_eq(_server.task.claimed_by, _server.id)
	assert_eq(_sim.world.board.get_task(_server.task.id), _server.task)
	assert_eq(int(_server.task.payload["order_id"]), _guest.order.id)
	assert_eq(_server.step_index, _server.task.steps.size() - 2)


func _assert_passive_queries() -> void:
	var now: int = _sim.world.now
	var shared: int = _sim.rng.state
	var private_state: int = _guest.rng.state
	var snapshots: Dictionary = _sim.world.movement.snapshot()
	for query: int in range(3):
		_server.carries_food()
		_sim.world.movement.priority(_sim.world, _server)
	assert_eq(_sim.world.now, now)
	assert_eq(_sim.rng.state, shared)
	assert_eq(_guest.rng.state, private_state)
	assert_eq(_sim.world.movement.snapshot(), snapshots)


func _advance() -> void:
	_previous = MovementInvariants.capture(_sim.world)
	_sim.advance()
	assert_eq(MovementInvariants.problem(_sim.world, _previous), "")
