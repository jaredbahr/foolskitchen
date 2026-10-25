extends TestCase
## Atomic dining projections and real guest seating use synthetic definitions.

class FakeMeals extends RefCounted:
	var _sim: WeakRef
	var _due: Dictionary[int, int] = {}

	func _init(sim: RestaurantSim) -> void:
		_sim = weakref(sim)
		sim.orders.order_placed.connect(_on_order_placed)


	func _on_order_placed(order: Order) -> void:
		var sim: RestaurantSim = _sim.get_ref() as RestaurantSim
		_due[order.id] = sim.world.now + 10
		sim.orders.set_state(order, Order.State.COOKING)


	func advance() -> void:
		var sim: RestaurantSim = _sim.get_ref() as RestaurantSim
		for order_id: int in _due.keys():
			var order: Order = sim.orders.get_order(order_id)
			if order == null or order.state == Order.State.CANCELLED:
				_due.erase(order_id)
			elif sim.world.now >= _due[order_id]:
				sim.orders.set_state(order, Order.State.READY)
				sim.orders.set_state(order, Order.State.DELIVERED)
				_due.erase(order_id)

var _observed_grid: SimGrid
var _watched_cells: Array[Vector2i] = []
var _events: Array[Dictionary] = []


func after_each() -> void:
	_observed_grid = null
	_watched_cells.clear()
	_events.clear()


func test_live_table_owns_two_independently_reserved_bench_seats() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i(2, 1)), Vector2i(3, 3))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
		[Vector2i.ZERO, Vector2i.RIGHT]), Vector2i(3, 4))
	assert_eq(table.seat_cells, [Vector2i(3, 4), Vector2i(4, 4)] as Array[Vector2i])
	assert_eq(bench.seat_cells, table.seat_cells, "generic furnishing cells are still authored")
	assert_true(table.reserve(Vector2i(3, 4), 11))
	assert_true(table.reserve(Vector2i(4, 4), 22))
	assert_false(table.reserve(Vector2i(3, 4), 22))
	assert_eq(table.reserved_by(Vector2i(3, 4)), 11)
	assert_eq(table.reserved_by(Vector2i(4, 4)), 22)
	for cell: Vector2i in table.seat_cells:
		assert_eq(grid.dining_table_id(cell), table.id)
		assert_eq(grid.dining_furnishing_id(cell), bench.id)
		assert_eq(bench.reserved_by(cell), -1, "physical table owns customer bookings")


func test_counter_stools_have_distinct_furnishing_lookups() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var counter: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i(2, 1)), Vector2i(3, 3))
	var first: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(3, 4))
	var second: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(4, 4))
	assert_eq(counter.seat_cells, [first.origin, second.origin] as Array[Vector2i])
	assert_eq(grid.dining_furnishing_id(first.origin), first.id)
	assert_eq(grid.dining_furnishing_id(second.origin), second.id)
	assert_eq(grid.dining_table_id(first.origin), counter.id)
	assert_eq(grid.dining_table_id(second.origin), counter.id)


func test_builtin_identity_and_reservation_survive_unrelated_mutation() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var definition: ItemDef = _definition(ItemDef.Category.TABLE, Vector2i(2, 2),
		[Vector2i(-1, 1), Vector2i(2, 1)])
	var table: PlacedItem = grid.place_def(definition, Vector2i(3, 3), 1)
	var original: Array[Vector2i] = table.seat_cells.duplicate()
	assert_true(table.reserve(original[0], 17))
	var decor: PlacedItem = grid.place_def(_definition(ItemDef.Category.DECOR), Vector2i.ZERO)
	assert_true(grid.remove(decor.id))
	assert_eq(table.seat_cells, original)
	assert_eq(table.reserved_by(original[0]), 17)
	assert_eq(definition.seat_cells, [Vector2i(-1, 1), Vector2i(2, 1)] as Array[Vector2i])
	for cell: Vector2i in original:
		assert_eq(grid.dining_table_id(cell), table.id)
		assert_eq(grid.dining_furnishing_id(cell), table.id)


func test_moving_unoccupied_bench_releases_only_lost_links_and_retains_other_bookings() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i(3, 1)), Vector2i(2, 2))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
		[Vector2i.ZERO, Vector2i.RIGHT]), Vector2i(2, 3))
	var stool: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(4, 3))
	assert_true(table.reserve(stool.origin, 81))
	assert_true(grid.relocate_def(bench.id, Vector2i(2, 4), 0))
	assert_eq(table.seat_cells, [stool.origin] as Array[Vector2i])
	assert_eq(table.reserved_by(stool.origin), 81)
	assert_eq(grid.dining_table_id(Vector2i(2, 3)), 0)
	assert_eq(grid.dining_furnishing_id(Vector2i(3, 3)), 0)
	assert_eq(bench.seat_cells, [Vector2i(2, 4), Vector2i(3, 4)] as Array[Vector2i])


func test_low_level_move_refuses_reserved_linked_furnishing_before_any_change() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i(2, 1)), Vector2i(3, 3))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
		[Vector2i.ZERO, Vector2i.RIGHT]), Vector2i(3, 4))
	assert_true(table.reserve(Vector2i(4, 4), 21))
	_observed_grid = grid
	_watched_cells = table.seat_cells.duplicate()
	grid.cells_changed.connect(_on_cells_changed)
	assert_false(grid.relocate_def(bench.id, Vector2i(3, 5), 0))
	assert_false(grid.relocate_def(bench.id, bench.origin, 1))
	assert_eq(bench.origin, Vector2i(3, 4))
	assert_eq(bench.quarter_turns, 0)
	assert_eq(table.seat_cells, _watched_cells)
	assert_eq(table.reserved_by(Vector2i(4, 4)), 21)
	assert_eq(grid.dining_furnishing_id(Vector2i(4, 4)), bench.id)
	assert_true(_events.is_empty(), "refused low-level moves emit nothing")


func test_rotation_relinks_unoccupied_chair_to_new_surface_without_disturbing_other_hold() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var first: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i.ONE,
		[Vector2i.LEFT]), Vector2i(4, 3))
	var second: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), Vector2i(5, 4))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(4, 4))
	assert_true(first.reserve(Vector2i(3, 3), 77))
	assert_eq(grid.dining_table_id(chair.origin), first.id)
	assert_true(grid.relocate_def(chair.id, chair.origin, 1))
	assert_eq(first.seat_cells, [Vector2i(3, 3)] as Array[Vector2i])
	assert_eq(first.reserved_by(Vector2i(3, 3)), 77)
	assert_eq(second.seat_cells, [chair.origin] as Array[Vector2i])
	assert_eq(grid.dining_table_id(chair.origin), second.id)
	assert_eq(grid.dining_furnishing_id(chair.origin), chair.id)
	assert_true(second.reserve(chair.origin, 88))
	assert_false(grid.relocate_def(chair.id, chair.origin, 0))
	assert_eq(chair.quarter_turns, 1)
	assert_eq(second.reserved_by(chair.origin), 88)


func test_raw_furnishing_removal_releases_its_table_bookings_but_retains_work_hold() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var definition: ItemDef = _definition(ItemDef.Category.TABLE, Vector2i(2, 1))
	definition.work_cells = [Vector2i.LEFT]
	var table: PlacedItem = grid.place_def(definition, Vector2i(3, 3))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
		[Vector2i.ZERO, Vector2i.RIGHT]), Vector2i(3, 4))
	assert_true(table.reserve(Vector2i(3, 4), 11))
	assert_true(table.reserve(Vector2i(4, 4), 22))
	assert_true(table.reserve(Vector2i(2, 3), 77))
	assert_true(grid.remove(bench.id))
	assert_true(table.seat_cells.is_empty())
	for cell: Vector2i in [Vector2i(3, 4), Vector2i(4, 4)]:
		assert_eq(table.reserved_by(cell), -1)
		assert_eq(grid.dining_table_id(cell), 0)
		assert_eq(grid.dining_furnishing_id(cell), 0)
	assert_eq(table.reserved_by(Vector2i(2, 3)), 77)


func test_terrain_mutation_prunes_blocked_builtin_seat_before_existing_signal() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i.ONE,
		[Vector2i.DOWN]), Vector2i(3, 3))
	var seat: Vector2i = Vector2i(3, 4)
	assert_true(table.reserve(seat, 19))
	_observed_grid = grid
	_watched_cells = [seat]
	grid.cells_changed.connect(_on_cells_changed)
	assert_true(grid.set_terrain(seat, SimGrid.Terrain.WALL))
	assert_true(table.seat_cells.is_empty())
	assert_eq(table.reserved_by(seat), -1)
	assert_eq(grid.dining_table_id(seat), 0)
	assert_eq(_events.size(), 1)
	assert_true(_events[0]["coherent"])
	assert_true(grid.set_terrain(seat, SimGrid.Terrain.FLOOR))
	assert_eq(table.seat_cells, [seat] as Array[Vector2i])
	assert_eq(table.reserved_by(seat), -1, "restoring floor never restores an expired booking")
	assert_eq(grid.dining_table_id(seat), table.id)
	assert_eq(_events.size(), 2)
	assert_true(_events[1]["coherent"])


func test_existing_notifications_observe_coherent_projection_once_per_mutation() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	_observed_grid = grid
	_watched_cells = [Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]
	grid.cells_changed.connect(_on_cells_changed)
	grid.item_removed.connect(_on_item_removed)
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i(2, 1)), Vector2i(3, 3))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
		[Vector2i.ZERO, Vector2i.RIGHT]), Vector2i(3, 4))
	assert_true(grid.relocate_def(bench.id, Vector2i(3, 5), 0))
	assert_true(grid.remove(bench.id))
	assert_eq(_events.size(), 5, "four existing cells signals plus the removal signal")
	assert_eq(_events[4]["kind"], "removed")
	for event: Dictionary in _events:
		assert_true(event["coherent"], "projection is complete before " + String(event["kind"]))
	assert_eq(_events[1]["tables"], [table.id, table.id, 0, 0] as Array[int])
	assert_eq(_events[2]["tables"], [0, 0, 0, 0] as Array[int])
	assert_eq(_events[3]["tables"], _events[4]["tables"])


func test_layout_seating_rebuild_is_placement_order_independent_without_duplicate_links() -> void:
	for chair_first: bool in [false, true]:
		var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
		var table: PlacedItem
		var bench: PlacedItem
		var table_def: ItemDef = _definition(ItemDef.Category.TABLE, Vector2i(2, 1))
		var bench_def: ItemDef = _definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
			[Vector2i.ZERO, Vector2i.RIGHT])
		if chair_first:
			bench = grid.place_def(bench_def, Vector2i(3, 4))
			table = grid.place_def(table_def, Vector2i(3, 3))
		else:
			table = grid.place_def(table_def, Vector2i(3, 3))
			bench = grid.place_def(bench_def, Vector2i(3, 4))
		for index: int in range(3):
			var decor: PlacedItem = grid.place_def(_definition(ItemDef.Category.DECOR), Vector2i(index, 0))
			assert_true(grid.remove(decor.id))
		assert_eq(table.seat_cells, [Vector2i(3, 4), Vector2i(4, 4)] as Array[Vector2i])
		assert_eq(DiningSeats.derive(grid).links.size(), 2)
		for cell: Vector2i in table.seat_cells:
			assert_eq(grid.dining_table_id(cell), table.id)
			assert_eq(grid.dining_furnishing_id(cell), bench.id)


func test_generic_grid_seats_and_reservations_are_not_reinterpreted() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var generic: PlacedItem = grid.place(Vector2i.ONE, Vector2i(2, 2), 0, true,
		[] as Array[Vector2i], [Vector2i.RIGHT] as Array[Vector2i])
	assert_true(generic.reserve(Vector2i(3, 2), 47))
	var decor: PlacedItem = grid.place_def(_definition(ItemDef.Category.DECOR), Vector2i.ZERO)
	assert_true(grid.remove(decor.id))
	assert_eq(generic.seat_cells, [Vector2i(3, 2)] as Array[Vector2i])
	assert_eq(generic.reserved_by(Vector2i(3, 2)), 47)
	assert_eq(grid.dining_table_id(Vector2i(3, 2)), 0)
	assert_eq(grid.dining_furnishing_id(Vector2i(3, 2)), 0)


func test_raw_seat_removal_makes_walking_customer_requeue_next_tick() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE), Vector2i(4, 3))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(4, 4))
	var sim: RestaurantSim = _restaurant(grid)
	var guest: CustomerAgent = _guest(sim, Vector2i(1, 4))
	sim.world.advance()
	assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT)
	assert_eq(guest.table_item_id, table.id)
	assert_eq(table.reserved_by(chair.origin), guest.id)
	assert_true(grid.remove(chair.id))
	sim.world.advance()
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(guest.table_item_id, 0)
	assert_eq(guest.seat_cell, SimGrid.NO_CELL)
	assert_eq(table.reserved_by(chair.origin), -1)


func test_real_customer_refuses_definition_backed_chair_without_surface() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(3, 4))
	var sim: RestaurantSim = _restaurant(grid)
	var guest: CustomerAgent = _guest(sim, Vector2i(1, 4))
	sim.world.advance()
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(guest.table_item_id, 0)
	assert_eq(chair.reserved_by(chair.origin), -1)
	assert_eq(chair.seat_cells, [chair.origin] as Array[Vector2i])


func test_lost_seat_cannot_remain_valid_because_its_cell_is_also_a_work_cell() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var definition: ItemDef = _definition(ItemDef.Category.TABLE)
	definition.work_cells = [Vector2i.DOWN]
	var table: PlacedItem = grid.place_def(definition, Vector2i(4, 3))
	var chair: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i.ONE,
		[Vector2i.ZERO]), Vector2i(4, 4))
	var sim: RestaurantSim = _restaurant(grid)
	var guest: CustomerAgent = _guest(sim, chair.origin)
	sim.world.advance()
	sim.world.advance()
	assert_eq(guest.state, CustomerAgent.State.ORDERING)
	assert_true(grid.remove(chair.id))
	assert_eq(table.reserved_by(chair.origin), guest.id, "projection does not discard a still-valid work hold")
	sim.world.advance()
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	assert_eq(guest.leave_reason, &"no_table")
	assert_eq(table.reserved_by(chair.origin), -1, "the guest releases its invalid dining hold")


func test_two_real_guests_order_and_pay_using_physical_table_with_bench() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	grid.set_terrain(Vector2i(0, 7), SimGrid.Terrain.ENTRY)
	var table: PlacedItem = grid.place_def(_definition(ItemDef.Category.TABLE, Vector2i(2, 1)), Vector2i(2, 2))
	var bench: PlacedItem = grid.place_def(_definition(ItemDef.Category.CHAIR, Vector2i(2, 1),
		[Vector2i.ZERO, Vector2i.RIGHT]), Vector2i(2, 3))
	var sim: RestaurantSim = _restaurant(grid)
	var server: StaffAgent = StaffAgent.new(&"server", 3)
	server.cell = Vector2i(1, 5)
	sim.world.add_agent(server)
	var first: CustomerAgent = _guest(sim, Vector2i(0, 7))
	var second: CustomerAgent = _guest(sim, Vector2i(0, 7))
	first.eat_ticks = 3
	second.eat_ticks = 3
	var meals: FakeMeals = FakeMeals.new(sim)
	for tick: int in range(400):
		sim.world.advance()
		meals.advance()
		if first.state == CustomerAgent.State.LEFT and second.state == CustomerAgent.State.LEFT:
			break
	assert_true(first.paid)
	assert_true(second.paid)
	assert_eq(sim.served_today, 2)
	assert_not_null(first.order)
	assert_not_null(second.order)
	if first.order != null and second.order != null:
		assert_eq(first.order.table_item_id, table.id)
		assert_eq(second.order.table_item_id, table.id)
		assert_true(first.order.seat_cell != second.order.seat_cell)
		assert_eq(first.order.state, Order.State.DELIVERED)
		assert_eq(second.order.state, Order.State.DELIVERED)
	for cell: Vector2i in table.seat_cells:
		assert_eq(table.reserved_by(cell), -1)
		assert_eq(bench.reserved_by(cell), -1)


func _definition(category: ItemDef.Category, footprint: Vector2i = Vector2i.ONE,
		seats: Array[Vector2i] = []) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"synthetic_dining_item"
	definition.category = category
	definition.footprint = footprint
	definition.solid = category == ItemDef.Category.TABLE
	definition.seat_cells = seats.duplicate()
	return definition


func _restaurant(grid: SimGrid) -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(grid)
	var dish: RecipeDef = RecipeDef.new()
	dish.id = &"synthetic_dish"
	dish.display_name = "Test meal"
	dish.standard_price = 10
	sim.menu = [dish]
	assert_true(sim.world.clock.start_service())
	return sim


func _guest(sim: RestaurantSim, cell: Vector2i) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 121
	var guest: CustomerAgent = CustomerAgent.new(sim, random)
	guest.cell = cell
	sim.world.add_agent(guest)
	return guest


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	_observe("cells")


func _on_item_removed(_item: PlacedItem) -> void:
	_observe("removed")


func _observe(kind: String) -> void:
	var plan: DiningSeats.Plan = DiningSeats.derive(_observed_grid)
	var coherent: bool = true
	for table_id: int in plan.table_seats:
		coherent = coherent and _observed_grid.item(table_id).seat_cells == plan.seats_for(table_id)
	var tables: Array[int] = []
	for cell: Vector2i in _watched_cells:
		var expected_table: int = 0
		var expected_furnishing: int = 0
		for link: DiningSeats.SeatLink in plan.links:
			if link.cell == cell:
				expected_table = link.table_item_id
				expected_furnishing = link.furnishing_item_id
		var actual_table: int = _observed_grid.dining_table_id(cell)
		coherent = coherent and actual_table == expected_table \
			and _observed_grid.dining_furnishing_id(cell) == expected_furnishing
		tables.append(actual_table)
	_events.append({"kind": kind, "coherent": coherent, "tables": tables})
