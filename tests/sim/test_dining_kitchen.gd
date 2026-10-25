extends TestCase
## Real kitchen acceptance for catalogue seating. The 4000-tick ceiling and
## short eating/long patience fixture match test_kitchen.gd, not balance probes.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const MAX_SERVICE_TICKS: int = 4000
const STARTING_STOCK: int = 100
const PLATE_TOTAL: int = 2
const SURFACE_ORIGIN: Vector2i = Vector2i(2, 6)

var _content: ContentDB
var _sim: RestaurantSim
var _surface: PlacedItem
var _furnishings: Array[PlacedItem] = []
var _paid: Dictionary[int, int] = {}
var _left: Dictionary[int, StringName] = {}
var _ready: Dictionary[int, bool] = {}
var _delivered: Dictionary[int, bool] = {}
var _cooking: Dictionary[int, bool] = {}
var _eating: Dictionary[int, bool] = {}
var _assigned: Dictionary[int, Vector2i] = {}
var _completed: Dictionary[StringName, int] = {}
var _bus_posted: Dictionary[int, bool] = {}
var _visited: Dictionary[int, bool] = {}
var _saw_dirty: bool = false
var _saw_bus_work: bool = false
var _saw_cook_pass: bool = false
var _saw_server_pass: bool = false
var _peak_bookings: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_paid.clear()
	_left.clear()
	_ready.clear()
	_delivered.clear()
	_cooking.clear()
	_eating.clear()
	_assigned.clear()
	_completed.clear()
	_bus_posted.clear()
	_visited.clear()
	_furnishings.clear()
	_saw_dirty = false
	_saw_bus_work = false
	_saw_cook_pass = false
	_saw_server_pass = false
	_peak_bookings = 0


func after_each() -> void:
	_furnishings.clear()
	_surface = null
	_sim = null
	_content = null


func test_two_bench_guests_use_real_cook_delivery_payment_and_bussing() -> void:
	_create_service(&"cloth_table", [&"cushioned_bench"], 290121)
	assert_eq(_furnishings.size(), 1)
	assert_eq(_furnishings[0].seat_cells.size(), 2)
	_run_and_assert_service()
	for cell: Vector2i in _surface.seat_cells:
		assert_eq(_sim.world.grid.dining_furnishing_id(cell), _furnishings[0].id)


func test_bar_counter_and_both_stool_shapes_complete_real_kitchen_service() -> void:
	_create_service(&"bar_counter", [&"bar_stool", &"square_bar_stool"], 290122)
	assert_eq(_furnishings.size(), 2)
	_run_and_assert_service()
	assert_eq(_sim.world.grid.dining_furnishing_id(_surface.seat_cells[0]), _furnishings[0].id)
	assert_eq(_sim.world.grid.dining_furnishing_id(_surface.seat_cells[1]), _furnishings[1].id)


func _create_service(surface_id: StringName, seats: Array[StringName], seed: int) -> void:
	# Keep the authored stations, pass, sink, spawns and street. Only replace
	# dining furniture, so no fake meal/task callback can satisfy this fixture.
	var layout: ShopLayout = ShopLayout.new()
	layout.id = &"catalogue_dining_kitchen"
	layout.display_name = "Catalogue seating kitchen fixture"
	layout.rows = LAYOUT.rows.duplicate()
	layout.staff_spawns = LAYOUT.staff_spawns.duplicate()
	for placed: ShopPlacement in LAYOUT.placements:
		if _content.item(placed.item_id).category != ItemDef.Category.TABLE:
			layout.placements.append(placed.duplicate(true) as ShopPlacement)
	layout.placements.append(_placement(surface_id, SURFACE_ORIGIN))
	for index: int in range(seats.size()):
		layout.placements.append(_placement(seats[index], SURFACE_ORIGIN + Vector2i(index, 1)))
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, STARTING_STOCK, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(layout, _content, seed, errors, stock)
	assert_eq(errors, [] as Array[String])
	assert_not_null(_sim.kitchen)
	assert_true(_sim.kitchen.stock == stock)
	assert_true(_sim.kitchen.plate_cycle_enabled, "the real reachable sink enables plate accounting")
	assert_true(_sim.kitchen.configure_plates(PLATE_TOTAL))
	assert_eq(_sim.carry_capacity, 1, "seat acceptance does not depend on a tray upgrade")
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	_surface = _item(surface_id)
	assert_not_null(_surface)
	assert_eq(_surface.seat_cells.size(), 2)
	assert_true((_surface.def as ItemDef).seat_cells.is_empty(), "all dining seats come from placed furnishings")
	for id: StringName in seats:
		_furnishings.append(_item(id))
	_sim.customer_paid.connect(_on_paid)
	_sim.customer_left.connect(_on_left)
	_sim.orders.order_ready.connect(_on_ready)
	_sim.orders.order_delivered.connect(_on_delivered)
	_sim.world.board.task_posted.connect(_on_task_posted)
	_sim.world.board.task_completed.connect(_on_task_completed)


func _run_and_assert_service() -> void:
	var guests: Array[CustomerAgent] = []
	for index: int in range(2):
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 1210 + index
		var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
		guest.eat_ticks = 3
		guest.food_patience = 5000
		guests.append(guest)
	assert_true(_sim.world.clock.start_service())
	var drained: bool = false
	for tick: int in range(MAX_SERVICE_TICKS):
		_sim.advance()
		_observe_service(guests)
		if _sim.customers().is_empty() and _sim.kitchen.is_clean() \
				and _sim.world.board.active_count() == 0 and _workers_idle():
			drained = true
			break
	assert_true(drained, "both real meals and same-day cleanup finish within the existing kitchen budget")
	assert_eq(_sim.world.clock.day, 1, "no next-morning tidy can satisfy bussing or washing")
	assert_eq(_sim.served_today, 2)
	assert_eq(_sim.lost_today, 0)
	assert_eq(_paid.size(), 2)
	assert_eq(_left.size(), 2)
	assert_eq(_assigned.size(), 2)
	assert_eq(_peak_bookings, 2, "both furnishing seats are independently reserved")
	assert_true(_assigned.get(guests[0].id) != _assigned.get(guests[1].id))
	for guest: CustomerAgent in guests:
		assert_not_null(guest.order)
		if guest.order == null:
			continue
		assert_true(_cooking.has(guest.order.id), "a real cook claimed each ticket")
		assert_true(_ready.has(guest.order.id))
		assert_true(_delivered.has(guest.order.id))
		assert_true(_eating.has(guest.id))
		assert_eq(guest.order.state, Order.State.DELIVERED)
		assert_eq(guest.order.table_item_id, _surface.id)
		assert_true(_surface.seat_cells.has(guest.order.seat_cell))
		assert_eq(_paid.get(guest.id, -1), _content.recipe(&"burger").standard_price)
		assert_eq(_left.get(guest.id, &""), &"happy")
	assert_true(_saw_cook_pass, "the real cook plated on the kitchen side")
	assert_true(_saw_server_pass, "the real server collected on the dining side")
	assert_true(_saw_dirty)
	assert_true(_saw_bus_work, "the server actually worked while holding a physical table seat")
	assert_true(_bus_posted.size() > 0)
	assert_true(int(_completed.get(&"cook", 0)) >= 2)
	assert_true(int(_completed.get(&"deliver", 0)) >= 2)
	assert_true(int(_completed.get(&"bus_table", 0)) > 0)
	assert_true(int(_completed.get(&"wash", 0)) > 0, "the real sink restored the plate stock")
	for id: StringName in [&"fridge", &"prep_counter", &"stove"]:
		assert_true(_visited.has(_item(id).id), "real kitchen work used %s" % id)
	for ingredient: IngredientDef in _content.recipe(&"burger").ingredients:
		assert_eq(_sim.stock.count(ingredient.id), STARTING_STOCK - 2, "exactly two meals consumed ingredients")
	assert_true(_sim.customers().is_empty())
	assert_true(_sim.kitchen.dirty_tables.is_empty())
	assert_eq(_sim.world.board.active_count(), 0)
	assert_eq(_sim.kitchen.clean_plates, PLATE_TOTAL)
	assert_eq(_sim.kitchen.dirty_plates, 0)
	assert_eq(_sim.kitchen.in_use_plates, 0)
	assert_true(_sim.world.grid.free_seat_cell(_surface) != SimGrid.NO_CELL, "bussing returned seats to service")
	for placed: PlacedItem in _sim.world.grid.items():
		for cell: Vector2i in placed.work_cells + placed.seat_cells:
			assert_eq(placed.reserved_by(cell), -1, "station and seating reservations are released")


func _observe_service(guests: Array[CustomerAgent]) -> void:
	var plates: PlateLedger = _sim.kitchen.plates
	assert_eq(plates.clean + plates.dirty + plates.in_use, PLATE_TOTAL, "plate stock is conserved every tick")
	var bookings: int = 0
	for guest: CustomerAgent in guests:
		if guest.order != null and guest.order.state == Order.State.COOKING:
			_cooking[guest.order.id] = true
		if guest.state == CustomerAgent.State.EATING:
			_eating[guest.id] = true
		if guest.state >= CustomerAgent.State.WALKING_TO_SEAT and guest.state <= CustomerAgent.State.PAYING:
			bookings += 1
			_assigned[guest.id] = guest.seat_cell
			assert_eq(guest.table_item_id, _surface.id)
			assert_eq(_surface.reserved_by(guest.seat_cell), guest.id)
			assert_eq(_sim.world.grid.dining_table_id(guest.seat_cell), _surface.id)
	_peak_bookings = maxi(_peak_bookings, bookings)
	for table_id: int in _sim.kitchen.dirty_tables:
		assert_eq(table_id, _surface.id, "chairs never become separate dirty-table buckets")
	_saw_dirty = _saw_dirty or _sim.kitchen.is_table_dirty(_surface.id)
	var cook: StaffAgent = _staff(&"cook")
	var server: StaffAgent = _staff(&"server")
	var pass_item: PlacedItem = _item(&"pass_counter")
	if cook.task != null and cook.task.kind == &"cook" \
			and cook.step_index > 0 and cook.step_index < cook.task.steps.size() \
			and cook.task.steps[cook.step_index].kind == TaskStep.Kind.WORK:
		var previous: TaskStep = cook.task.steps[cook.step_index - 1]
		if previous.kind == TaskStep.Kind.GO_TO_ITEM:
			_visited[previous.item_id] = true
		if cook.step_index == cook.task.steps.size() - 1:
			_saw_cook_pass = _saw_cook_pass or cook.cell == pass_item.work_cells[0]
	if server.task != null and server.task.kind == &"deliver" and server.step_index == 1:
		_saw_server_pass = _saw_server_pass or server.cell == pass_item.work_cells[1]
	if server.task != null and server.task.kind == &"bus_table" \
			and server.step_index < server.task.steps.size() \
			and server.task.steps[server.step_index].kind == TaskStep.Kind.WORK \
			and server._step_started and server.work_left > 0.0:
		assert_eq(server._held_item_id, _surface.id)
		assert_eq(_surface.reserved_by(server.cell), server.id)
		_saw_bus_work = true


func _on_task_posted(task: SimTask) -> void:
	if task.kind != &"bus_table":
		return
	assert_eq(int(task.payload["table_item_id"]), _surface.id)
	assert_eq(task.steps[0].kind, TaskStep.Kind.GO_TO_ITEM)
	assert_eq(task.steps[0].item_id, _surface.id)
	assert_true(task.steps[0].use_seat)
	_bus_posted[task.id] = true


func _on_task_completed(task: SimTask) -> void:
	_completed[task.kind] = int(_completed.get(task.kind, 0)) + 1
	if task.kind == &"bus_table":
		assert_true(_bus_posted.has(task.id))
		assert_eq(int(task.payload["table_item_id"]), _surface.id)
		var worker: StaffAgent = _sim.world.agent(task.claimed_by) as StaffAgent
		assert_not_null(worker)
		if worker != null:
			assert_eq(worker.role, &"server")


func _on_ready(order: Order) -> void:
	assert_eq(order.table_item_id, _surface.id)
	_ready[order.id] = true


func _on_delivered(order: Order) -> void:
	assert_eq(order.table_item_id, _surface.id)
	_delivered[order.id] = true


func _on_paid(guest: CustomerAgent, order: Order, amount: int) -> void:
	assert_false(_paid.has(guest.id), "one real payment per guest")
	assert_eq(order.state, Order.State.DELIVERED)
	assert_eq(order.table_item_id, _surface.id)
	assert_eq(amount, order.price)
	_paid[guest.id] = amount


func _on_left(guest: CustomerAgent, reason: StringName) -> void:
	assert_false(_left.has(guest.id), "one departure per guest")
	_left[guest.id] = reason


func _workers_idle() -> bool:
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent and (agent as StaffAgent).task != null:
			return false
	return true


func _staff(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent and agent.role == role:
			return agent as StaffAgent
	fail("fixture requires staff role %s" % role)
	return null


func _item(id: StringName) -> PlacedItem:
	var items: Array[PlacedItem] = ShopBuilder.items_with_def(_sim.world, id)
	assert_false(items.is_empty(), "fixture requires %s" % id)
	return null if items.is_empty() else items[0]


func _placement(id: StringName, origin: Vector2i) -> ShopPlacement:
	var placement: ShopPlacement = ShopPlacement.new()
	placement.item_id = id
	placement.origin = origin
	return placement
