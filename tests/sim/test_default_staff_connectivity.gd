extends TestCase
## Regression for the real starter shop's doorway being a forbidden seat.
## These are geometry/task tests, not a replacement for the throughput probe.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const MAX_ORDER_TICKS: int = 480

var _content: ContentDB
var _board: TaskBoard
var _server: StaffAgent
var _posted_orders: int = 0
var _order_drops: int = 0
var _completion_cells: Array[Vector2i] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_posted_orders = 0
	_order_drops = 0
	_completion_cells.clear()


func after_each() -> void:
	if _board != null:
		_board.task_posted.disconnect(_on_posted)
		_board.task_dropped.disconnect(_on_dropped)
		_board.task_completed.disconnect(_on_completed)
	_board = null
	_server = null


func test_default_staff_can_reach_every_work_cell_without_using_any_dining_seat() -> void:
	var sim: RestaurantSim = _restaurant(LAYOUT)
	var world: SimWorld = sim.world
	var server: StaffAgent = _staff(world, &"server")
	assert_not_null(server)
	if server == null:
		return
	assert_eq(world.grid.room(server.cell), SimGrid.Room.DINING)
	var seats: Array[Vector2i] = _seats(world)
	var work_cells_checked: int = 0
	var regular_staff_checked: int = 0
	for actor: SimAgent in world.agents:
		if not actor is StaffAgent or actor.role not in [&"cook", &"server"]:
			continue
		regular_staff_checked += 1
		var staff: StaffAgent = actor as StaffAgent
		for item: PlacedItem in world.grid.items():
			for cell: Vector2i in item.work_cells:
				# Ignore temporary people only: route() still forbids every seat.
				var outward: Array[Vector2i] = world.movement.route(world, staff, staff.cell, cell, false)
				var returning: Array[Vector2i] = world.movement.route(world, staff, cell, staff.cell, false)
				_assert_seat_free_route(world, outward, staff.cell, cell, seats)
				_assert_seat_free_route(world, returning, cell, staff.cell, seats)
				work_cells_checked += 1
	assert_eq(regular_staff_checked, 2)
	assert_true(work_cells_checked >= 12, "both real staff reach fridge/prep/stove/pass/sink work cells")
	assert_true(_has_two_cell_crossing(world), "two adjacent connected kitchen/dining crossings stay free of seats")
	for item: PlacedItem in world.grid.items():
		for seat: Vector2i in item.seat_cells:
			assert_eq(item.reserved_by(seat), -1, "the route proof never borrows a seat reservation")


func test_old_doorway_gap_is_detected_even_when_all_dining_seats_are_empty() -> void:
	# Recreate d7's faulty wall on a detached resource, preserving actual furniture.
	var blocked: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	blocked.placements = []
	for authored: ShopPlacement in LAYOUT.placements:
		var placement: ShopPlacement = authored.duplicate(true) as ShopPlacement
		if placement.item_id == &"pass_counter":
			placement.origin = Vector2i(5, 4)
		blocked.placements.append(placement)
	blocked.wall_segments = {}
	for x: int in range(1, blocked.rows[0].length() - 1):
		if x not in [5, 6, 7]:
			blocked.wall_segments[Vector3i(x, 5, SimGrid.EDGE_NORTH)] = &"wall"
	var sim: RestaurantSim = _restaurant(blocked)
	var server: StaffAgent = _staff(sim.world, &"server")
	assert_not_null(server)
	if server == null:
		return
	assert_false(_has_two_cell_crossing(sim.world))
	var kitchen_cells: int = 0
	for item: PlacedItem in sim.world.grid.items():
		for cell: Vector2i in item.work_cells:
			if sim.world.grid.room(cell) != SimGrid.Room.KITCHEN:
				continue
			kitchen_cells += 1
			assert_true(sim.world.movement.route(sim.world, server, server.cell, cell, false).is_empty(),
				"empty seats still cannot turn the historical bad gap into an aisle")
	assert_true(kitchen_cells >= 5)


func test_middle_north_guest_gets_a_real_order_callback_from_a_physical_service_cell() -> void:
	var sim: RestaurantSim = _restaurant(LAYOUT)
	var world: SimWorld = sim.world
	_server = _staff(world, &"server")
	assert_not_null(_server)
	if _server == null:
		return
	assert_eq(world.grid.room(_server.cell), SimGrid.Room.DINING, "server starts on the dining side")
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	assert_eq(tables.size(), 3)
	if tables.size() != 3:
		return
	tables.sort_custom(_left_to_right)
	var table: PlacedItem = tables[1]
	var seat: Vector2i = table.seat_cells[0]
	for candidate: Vector2i in table.seat_cells:
		if candidate.y < seat.y:
			seat = candidate
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 263
	var guest: CustomerAgent = CustomerAgent.new(sim, random)
	guest.cell = world.grid.entries()[0]
	world.add_agent(guest)
	assert_eq(world.agent(guest.id), guest, "real guest is admitted at the actual street entry")
	assert_true(table.reserve(seat, guest.id))
	guest.table_item_id = table.id
	guest.booked_table_ids.append(table.id)
	guest.seat_cell = seat
	guest.state = CustomerAgent.State.WALKING_TO_SEAT
	assert_true(guest.set_destination(world.grid, seat))
	_board = world.board
	_board.task_posted.connect(_on_posted)
	_board.task_dropped.connect(_on_dropped)
	_board.task_completed.connect(_on_completed)
	assert_true(world.clock.start_service())
	for tick: int in MAX_ORDER_TICKS:
		var previous: Dictionary = MovementInvariants.capture(world)
		world.advance()
		var problem: String = MovementInvariants.problem(world, previous)
		assert_eq(problem, "", "actual walk, approach and callback preserve physical movement")
		if not problem.is_empty():
			return
		if guest.order != null:
			break
	assert_eq(guest.cell, seat, "the guest physically reaches its booked seat")
	assert_not_null(guest.order, "real task completes before the bounded watchdog, not an injected callback")
	assert_eq(guest.state, CustomerAgent.State.WAITING_FOOD)
	assert_eq(_posted_orders, 1, "the order task is not repeatedly replaced after unreachable drops")
	assert_eq(_order_drops, 0)
	assert_eq(_completion_cells.size(), 1)
	if _completion_cells.size() == 1:
		var physical: Vector2i = _completion_cells[0]
		assert_true(world.movement.standing_cell(world, physical))
		assert_true(world.grid.walkable_neighbours(seat).has(physical))
		assert_true(world.grid.step_open(seat, physical))
		assert_false(_seats(world).has(physical), "order callback never uses another dining seat")
		assert_eq(_server.cell, physical)
	assert_eq(table.reserved_by(seat), guest.id)


func _restaurant(layout: ShopLayout) -> RestaurantSim:
	var errors: Array[String] = []
	# Keep real staff/menu/task callbacks; cooking is outside this approach test.
	var sim: RestaurantSim = RestaurantSim.create(layout, _content, 263, errors, null, false)
	assert_eq(errors, [] as Array[String])
	return sim


func _staff(world: SimWorld, role: StringName) -> StaffAgent:
	for agent: SimAgent in world.agents:
		if agent is StaffAgent and agent.role == role:
			return agent as StaffAgent
	return null


func _seats(world: SimWorld) -> Array[Vector2i]:
	var seats: Array[Vector2i] = []
	for item: PlacedItem in world.grid.items():
		seats.append_array(item.seat_cells)
	return seats


func _assert_seat_free_route(world: SimWorld, path: Array[Vector2i], start: Vector2i,
		goal: Vector2i, seats: Array[Vector2i]) -> void:
	assert_false(path.is_empty(), "actual staff route from %s to %s exists" % [start, goal])
	if path.is_empty():
		return
	assert_eq(path[0], start)
	assert_eq(path[-1], goal)
	for index: int in path.size():
		assert_false(seats.has(path[index]), "a work route never traverses a seat")
		assert_true(world.grid.is_walkable(path[index]))
		if index > 0:
			var from: Vector2i = path[index - 1]
			var delta: Vector2i = path[index] - from
			assert_true(world.grid.walkable_neighbours(from).has(path[index]))
			if delta.x != 0 and delta.y != 0:
				assert_false(seats.has(from + Vector2i(delta.x, 0)), "diagonal clearance cannot borrow a seat")
				assert_false(seats.has(from + Vector2i(0, delta.y)), "diagonal clearance cannot borrow a seat")


func _has_two_cell_crossing(world: SimWorld) -> bool:
	var crossings: Array[int] = []
	for y: int in range(1, LAYOUT.rows.size()):
		crossings.clear()
		for x: int in LAYOUT.rows[0].length():
			var north: Vector2i = Vector2i(x, y - 1)
			var south: Vector2i = Vector2i(x, y)
			if world.grid.room(north) == SimGrid.Room.KITCHEN \
					and world.grid.room(south) == SimGrid.Room.DINING \
					and world.movement.standing_cell(world, north) \
					and world.movement.standing_cell(world, south) \
					and world.grid.step_open(north, south):
				crossings.append(x)
		for x: int in crossings:
			if crossings.has(x + 1) \
					and world.grid.step_open(Vector2i(x, y - 1), Vector2i(x + 1, y - 1)) \
					and world.grid.step_open(Vector2i(x, y), Vector2i(x + 1, y)):
				return true
	return false


func _left_to_right(a: PlacedItem, b: PlacedItem) -> bool:
	return a.origin.x < b.origin.x


func _on_posted(task: SimTask) -> void:
	if task.kind == &"take_order":
		_posted_orders += 1


func _on_dropped(task: SimTask, _agent_id: int, _reason: StringName) -> void:
	if task.kind == &"take_order":
		_order_drops += 1


func _on_completed(task: SimTask) -> void:
	if task.kind == &"take_order":
		assert_eq(task.claimed_by, _server.id, "the real serving employee completes the task")
		_completion_cells.append(_server.cell)
