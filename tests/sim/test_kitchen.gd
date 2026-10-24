extends TestCase
## Real kitchen/staff/customer integration. Runtime evidence comes from check.sh.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
var _content: ContentDB
var _sim: RestaurantSim
var _arrived: Dictionary[int, bool] = {}
var _paid: Dictionary[int, int] = {}
var _left: Dictionary[int, StringName] = {}


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 29015, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.customer_arrived.connect(_on_arrived)
	_sim.customer_paid.connect(_on_paid)
	_sim.customer_left.connect(_on_left)
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_no_arrivals()


func after_each() -> void:
	_sim = null
	_content = null


func test_real_staff_cook_pass_deliver_eat_pay_and_bus() -> void:
	var guest: CustomerAgent = _guest()
	var pass_item: PlacedItem = _item(&"pass_counter")
	var cook: StaffAgent = _staff(&"cook")
	var server: StaffAgent = _staff(&"server")
	var visited: Dictionary[int, bool] = {}
	var cook_side: bool = false
	var dining_side: bool = false
	var cooking: bool = false
	var ready: bool = false
	_sim.world.clock.start_service()
	for tick: int in range(4000):
		_sim.advance()
		if guest.order != null:
			cooking = cooking or guest.order.state == Order.State.COOKING
			ready = ready or guest.order.state == Order.State.READY
		if cook.task != null and cook.task.kind == &"cook":
			var task: SimTask = cook.task
			if cook.step_index > 0 and cook.step_index < task.steps.size() and task.steps[cook.step_index].kind == TaskStep.Kind.WORK:
				var previous: TaskStep = task.steps[cook.step_index - 1]
				if previous.kind == TaskStep.Kind.GO_TO_ITEM:
					visited[previous.item_id] = true
				if cook.step_index == task.steps.size() - 1:
					cook_side = cook_side or cook.cell == pass_item.work_cells[0]
		if server.task != null and server.task.kind == &"deliver":
			assert_eq(server.task.priority, 3)
			if server.step_index == 1:
				dining_side = dining_side or server.cell == pass_item.work_cells[1]
		if guest.state == CustomerAgent.State.LEFT and _sim.world.board.active_count() == 0:
			break
	assert_not_null(guest.order)
	if guest.order == null:
		return
	assert_true(cooking, "ticket becomes COOKING while real staff own it")
	assert_true(ready, "ticket reaches READY before delivery")
	assert_eq(guest.order.state, Order.State.DELIVERED)
	assert_true(cook_side, "cook plates on kitchen side")
	assert_true(dining_side, "server collects on dining side")
	for id: StringName in [&"fridge", &"prep_counter", &"stove"]:
		assert_true(visited.has(_item(id).id), "real work at %s" % id)
	assert_almost_eq(guest.order.quality, 0.6)
	assert_eq(_paid.get(guest.id, -1), 9)
	assert_eq(_left.get(guest.id, &""), &"happy")
	for ingredient: IngredientDef in _content.recipe(&"burger").ingredients:
		assert_eq(_sim.stock.count(ingredient.id), 99)
	_assert_drained()


func test_out_of_stock_cancels_ticket_and_guest_with_same_reason() -> void:
	# Removing just one required ingredient also proves take_many remains atomic.
	assert_true(_sim.stock.take(&"beef_patty", 100))
	var guest: CustomerAgent = _guest()
	_sim.world.clock.start_service()
	_run(3000)
	assert_not_null(guest.order)
	if guest.order == null:
		return
	assert_eq(guest.order.state, Order.State.CANCELLED)
	assert_eq(guest.order.cancellation_reason, &"out_of_stock")
	assert_eq(guest.leave_reason, &"out_of_stock")
	assert_eq(_left.get(guest.id, &""), &"out_of_stock")
	assert_eq(_sim.stock.count(&"bun"), 100)
	assert_eq(_sim.stock.count(&"lettuce"), 100)
	assert_eq(_sim.served_today, 0)
	assert_eq(_sim.lost_today, 1)
	_assert_drained()


func test_dirty_table_blocks_new_seat_until_real_server_busses_it() -> void:
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(_sim.world, &"table_2")
	var table: PlacedItem = tables[0]
	for index: int in range(1, tables.size()):
		_sim.world.grid.remove(tables[index].id)
	var first: CustomerAgent = _guest()
	_sim.world.clock.start_service()
	for tick: int in range(2500):
		_sim.advance()
		if first.paid:
			break
	assert_true(first.paid)
	assert_true(_sim.kitchen.is_table_dirty(table.id))
	var server: StaffAgent = _staff(&"server")
	server.priorities[&"server"] = 0
	server.priorities[&"any"] = 0
	var second: CustomerAgent = _guest()
	_run(20)
	assert_eq(second.state, CustomerAgent.State.QUEUED)
	assert_eq(second.table_item_id, 0)
	assert_true(_sim.kitchen.is_table_dirty(table.id))
	for seat: Vector2i in table.seat_cells:
		assert_eq(table.reserved_by(seat), -1)
	var bus: SimTask = _find_task(&"bus_table")
	assert_not_null(bus)
	if bus != null:
		assert_eq(bus.priority, 1)
	server.priorities[&"server"] = 2
	for tick: int in range(500):
		_sim.advance()
		if second.table_item_id != 0:
			break
	assert_false(_sim.kitchen.is_table_dirty(table.id))
	assert_eq(second.table_item_id, table.id)
	_run(3000)
	_assert_drained()


func test_dropped_cook_task_restarts_without_taking_ingredients_twice() -> void:
	var guest: CustomerAgent = _guest()
	var cook: StaffAgent = _staff(&"cook")
	var replayed: SimTask
	_sim.world.clock.start_service()
	for tick: int in range(1000):
		_sim.advance()
		if cook.task != null and cook.task.kind == &"cook" and cook.task.payload.get("ingredients_taken", false):
			replayed = cook.task
			break
	assert_not_null(replayed)
	if replayed == null:
		return
	_sim.world.board.drop(replayed, &"test_retry")
	_run(3000)
	assert_eq(replayed.drops, 1)
	assert_eq(replayed.state, SimTask.State.DONE)
	assert_not_null(guest.order)
	if guest.order != null:
		assert_eq(guest.order.state, Order.State.DELIVERED)
	for ingredient: IngredientDef in _content.recipe(&"burger").ingredients:
		assert_eq(_sim.stock.count(ingredient.id), 99, "retry does not consume %s twice" % ingredient.id)
	_assert_drained()


func test_rotated_pass_keeps_explicit_kitchen_and_dining_work_cells() -> void:
	var original: PlacedItem = _item(&"pass_counter")
	var definition: ItemDef = original.def as ItemDef
	_sim.world.grid.remove(original.id)
	var rotated: PlacedItem = _sim.world.grid.place_def(definition, Vector2i(8, 5), 1)
	assert_not_null(rotated)
	if rotated == null:
		return
	var guest: CustomerAgent = _guest()
	_sim.world.clock.start_service()
	var cook_side: bool = false
	var dining_side: bool = false
	for tick: int in range(3000):
		_sim.advance()
		for role: StringName in [&"cook", &"server"]:
			var staff: StaffAgent = _staff(role)
			if staff.task == null:
				continue
			if role == &"cook" and staff.task.kind == &"cook" and staff.step_index == staff.task.steps.size() - 1:
				cook_side = cook_side or staff.cell == rotated.work_cells[0]
			if role == &"server" and staff.task.kind == &"deliver" and staff.step_index == 1:
				dining_side = dining_side or staff.cell == rotated.work_cells[1]
		if guest.state == CustomerAgent.State.LEFT and _sim.world.board.active_count() == 0:
			break
	assert_true(cook_side)
	assert_true(dining_side)
	assert_not_null(guest.order)
	if guest.order != null:
		assert_eq(guest.order.state, Order.State.DELIVERED)
	_assert_drained()


func test_quality_combines_skill_and_station_bonus_and_clamps() -> void:
	var cook: StaffAgent = _staff(&"cook")
	cook.skills[&"cook"] = 5
	for id: StringName in [&"prep_counter", &"stove"]:
		var item: PlacedItem = _item(id)
		var definition: ItemDef = item.def.duplicate() as ItemDef
		definition.quality_bonus = 0.2
		item.def = definition
	var guest: CustomerAgent = _guest()
	_sim.world.clock.start_service()
	_run(3000)
	assert_not_null(guest.order)
	if guest.order != null:
		assert_eq(guest.order.state, Order.State.DELIVERED)
		assert_almost_eq(guest.order.quality, 1.0)
	_assert_drained()


func test_quality_uses_low_cook_skill_and_each_station_bonus_once() -> void:
	var cook: StaffAgent = _staff(&"cook")
	cook.skills[&"cook"] = 1
	for id: StringName in [&"prep_counter", &"stove"]:
		var item: PlacedItem = _item(id)
		var definition: ItemDef = item.def.duplicate() as ItemDef
		definition.quality_bonus = 0.05 if id == &"prep_counter" else 0.1
		item.def = definition
	var guest: CustomerAgent = _guest()
	_sim.world.clock.start_service()
	_run(3000)
	assert_not_null(guest.order)
	if guest.order != null:
		assert_eq(guest.order.state, Order.State.DELIVERED)
		assert_almost_eq(guest.order.quality, 0.6 * 0.8 + 0.05 + 0.1)
	_assert_drained()


func test_three_day_real_kitchen_customer_soak_accounts_and_drains() -> void:
	_sim.menu = _content.recipes()
	_sim.spawner.min_gap = 100
	_sim.spawner.max_gap = 180
	var total_served: int = 0
	var total_lost: int = 0
	var total_reasons: Dictionary[StringName, int] = {}
	for day: int in range(3):
		var arrivals_before_day: int = _arrived.size()
		_sim.start_day()
		assert_eq(_sim.served_today, 0)
		assert_eq(_sim.lost_today, 0)
		assert_true(_sim.world.clock.start_service())
		for tick: int in range(5000):
			_sim.advance()
			if _sim.world.clock.phase == SimClock.Phase.CLOSED:
				break
		assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED)
		assert_eq(_sim.customers().size(), 0, "closing removes guests on this tick")
		# Closing cancels service work immediately; only genuine bussing may remain.
		for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY]:
			assert_eq(_sim.orders.orders_in_state(state).size(), 0, "closing resolves tickets on this tick")
		var remaining: Array[SimTask] = _sim.world.board.open_tasks()
		remaining.append_array(_sim.world.board.claimed_tasks())
		for task: SimTask in remaining:
			assert_eq(task.kind, &"bus_table", "closing leaves no live cook/delivery/order-taking work")
		var closed_arrivals: int = _arrived.size()
		var closed_payments: int = _paid.size()
		var closed_departures: int = _left.size()
		var closed_served: int = _sim.served_today
		var closed_lost: int = _sim.lost_today
		var closed_reasons: Dictionary = _sim.leave_reasons_today.duplicate()
		# Real servers finish cleanup after the closing sweep; no fake completion.
		var cleanup_ticks: int = 0
		while cleanup_ticks < 1200 and _sim.world.board.active_count() > 0:
			_sim.advance()
			cleanup_ticks += 1
		_assert_drained()
		assert_eq(_arrived.size(), closed_arrivals)
		assert_eq(_paid.size(), closed_payments)
		assert_eq(_left.size(), closed_departures)
		assert_eq(_sim.served_today, closed_served)
		assert_eq(_sim.lost_today, closed_lost)
		assert_eq(_sim.leave_reasons_today, closed_reasons)
		total_served += _sim.served_today
		total_lost += _sim.lost_today
		for reason: StringName in _sim.leave_reasons_today:
			total_reasons[reason] = total_reasons.get(reason, 0) + _sim.leave_reasons_today[reason]
		assert_eq(_arrived.size(), _left.size())
		assert_eq(_arrived.size(), total_served + total_lost)
		assert_eq(_paid.size(), total_served)
		for id: int in _arrived:
			assert_true(_paid.has(id) or not String(_left.get(id, &"")).is_empty())
		print("KITCHEN_DAY day=%d arrivals=%d served=%d lost=%d cleanup_ticks=%d dirty=%d board=%d reasons=%s" % [day + 1, _arrived.size() - arrivals_before_day, _sim.served_today, _sim.lost_today, cleanup_ticks, _sim.kitchen.dirty_tables.size(), _sim.world.board.active_count(), _sim.leave_reasons_today])
		if day < 2:
			assert_true(_sim.world.clock.next_day())
	assert_true(total_served > 0, "real staff deliver meals during the soak")
	assert_true(total_lost > 0, "bounded guest failures are accounted too")
	print("KITCHEN_SOAK arrivals=%d served=%d lost=%d reasons=%s" % [_arrived.size(), total_served, total_lost, total_reasons])


func _no_arrivals() -> void:
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()


func _guest() -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
	guest.eat_ticks = 3
	guest.food_patience = 5000
	return guest


func _item(id: StringName) -> PlacedItem:
	return ShopBuilder.items_with_def(_sim.world, id)[0]


func _staff(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent and agent.role == role:
			return agent as StaffAgent
	return null


func _find_task(kind: StringName) -> SimTask:
	var tasks: Array[SimTask] = _sim.world.board.open_tasks()
	tasks.append_array(_sim.world.board.claimed_tasks())
	for task: SimTask in tasks:
		if task.kind == kind:
			return task
	return null


func _run(ticks: int) -> void:
	for tick: int in range(ticks):
		_sim.advance()


func _assert_drained() -> void:
	assert_eq(_sim.customers().size(), 0)
	assert_eq(_sim.world.board.active_count(), 0)
	assert_eq(_sim.kitchen.dirty_tables.size(), 0)
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY]:
		assert_eq(_sim.orders.orders_in_state(state).size(), 0, "no unfinished orders")
	for item: PlacedItem in _sim.world.grid.items():
		for cell: Vector2i in item.work_cells + item.seat_cells:
			assert_eq(item.reserved_by(cell), -1, "all station and seat reservations released")


func _on_arrived(guest: CustomerAgent) -> void:
	assert_false(_arrived.has(guest.id))
	_arrived[guest.id] = true


func _on_paid(guest: CustomerAgent, order: Order, amount: int) -> void:
	assert_false(_paid.has(guest.id), "one payment per guest")
	assert_eq(order.state, Order.State.DELIVERED)
	assert_eq(amount, order.price)
	_paid[guest.id] = amount


func _on_left(guest: CustomerAgent, reason: StringName) -> void:
	assert_false(_left.has(guest.id), "one departure per guest")
	assert_false(String(reason).is_empty())
	_left[guest.id] = reason
