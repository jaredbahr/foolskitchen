extends TestCase
## Staff favour the guests nearest to leaving (#307), inside the job tier the
## player chose. Real sims, real scoring and claiming.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 29015, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()


func after_each() -> void:
	_sim = null
	_content = null


func test_urgency_is_the_used_fraction_of_the_relevant_patience() -> void:
	var guest: CustomerAgent = _guest()
	assert_almost_eq(guest.urgency(), 0.0, 0.0001, "arriving guests are calm")
	guest.state = CustomerAgent.State.QUEUED
	guest.queue_patience = 200
	guest._queue_wait = 50
	assert_almost_eq(guest.urgency(), 0.25)
	guest.state = CustomerAgent.State.ORDERING
	guest.food_patience = 400
	guest._food_wait = 300
	assert_almost_eq(guest.urgency(), 0.75)
	guest.state = CustomerAgent.State.EATING
	assert_almost_eq(guest.urgency(), 0.0, 0.0001, "no patience is running while eating")


func test_nearly_gone_order_beats_a_slightly_nearer_calm_one() -> void:
	var server: StaffAgent = _lone_server()
	var calm: SimTask = _order_task(_guest(), 0.0, _table_item(0))
	var urgent: SimTask = _order_task(_guest(), 0.9, _table_item(1))
	# The calm order's table is a little nearer; with no urgency it would win.
	server.urgency_tuning = GuestUrgencyTuning.new()
	server.urgency_tuning.guest_weight = 0.0
	server.urgency_tuning.table_weight = 0.0
	server.cell = _cell_slightly_nearer(server, calm, urgent)
	var baseline_calm: float = server._score(_sim.world, calm)
	var baseline_urgent: float = server._score(_sim.world, urgent)
	assert_true(baseline_calm > baseline_urgent, "premise: the calm guest is nearer")
	assert_true(baseline_calm < baseline_urgent * 1.6, "premise: only slightly nearer")
	server.urgency_tuning = GuestUrgencyTuning.new()
	_sim.world.advance()
	assert_eq(server.task, urgent, "the guest about to leave is served first")
	assert_eq(calm.state, SimTask.State.OPEN)


func test_distance_still_counts_between_equally_calm_guests() -> void:
	var server: StaffAgent = _lone_server()
	var near: SimTask = _order_task(_guest(), 0.5, _table_item(0))
	var far: SimTask = _order_task(_guest(), 0.5, _table_item(1))
	server.cell = _cell_slightly_nearer(server, near, far)
	_sim.world.advance()
	assert_eq(server.task, near)
	assert_eq(far.state, SimTask.State.OPEN)


func test_a_waiting_far_guest_ages_up_and_is_not_starved() -> void:
	var server: StaffAgent = _lone_server()
	var near: SimTask = _order_task(_guest(), 0.0, _table_item(0))
	var far_guest: CustomerAgent = _guest()
	var far: SimTask = _order_task(far_guest, 0.0, _table_item(1))
	server.cell = _cell_slightly_nearer(server, near, far)
	# Same patience used: the nearer guest is served first (distance counts).
	assert_true(server._score(_sim.world, near) > server._score(_sim.world, far))
	# The far guest keeps waiting; urgency rises with the wait until they win.
	var served_far: bool = false
	for used: float in [0.1, 0.3, 0.5, 0.7, 0.9]:
		far_guest._food_wait = int(far_guest.food_patience * used)
		server.task = null
		if near.state == SimTask.State.CLAIMED:
			_sim.world.board.drop(near, &"test")
		if far.state == SimTask.State.CLAIMED:
			_sim.world.board.drop(far, &"test")
		server.cell = _cell_slightly_nearer_untuned(server, near, far)
		_sim.world.advance()
		if server.task == far:
			served_far = true
			break
	assert_true(served_far, "as the far guest's patience drains they overtake the nearer calm one")


func test_cook_takes_the_most_impatient_ticket_first() -> void:
	var cook: StaffAgent = _staff(&"cook")
	var calm: CustomerAgent = _guest()
	var urgent: CustomerAgent = _guest()
	var calm_order: Order = _place_order(calm, 0.0)
	var urgent_order: Order = _place_order(urgent, 0.85)
	assert_true(calm_order.id < urgent_order.id, "the calm ticket was posted first")
	_sim.world.clock.start_service()
	for tick: int in 6:
		_sim.advance()
		if cook.task != null and cook.task.kind == &"cook":
			break
	assert_not_null(cook.task)
	if cook.task != null:
		assert_eq(int(cook.task.payload["order_id"]), urgent_order.id)


func test_cook_keeps_posting_order_when_everyone_is_equally_calm() -> void:
	var cook: StaffAgent = _staff(&"cook")
	var first: Order = _place_order(_guest(), 0.2)
	_place_order(_guest(), 0.2)
	_sim.world.clock.start_service()
	for tick: int in 6:
		_sim.advance()
		if cook.task != null and cook.task.kind == &"cook":
			break
	assert_not_null(cook.task)
	if cook.task != null:
		assert_eq(int(cook.task.payload["order_id"]), first.id)


func test_delivery_urgency_reads_every_guest_in_the_trip() -> void:
	var calm: CustomerAgent = _guest()
	var urgent: CustomerAgent = _guest()
	var calm_order: Order = _place_order(calm, 0.0)
	var urgent_order: Order = _place_order(urgent, 0.6)
	var task: SimTask = SimTask.new(&"deliver", &"server", "Deliver 2 meals")
	task.payload = {"order_id": calm_order.id, "order_ids": [calm_order.id, urgent_order.id]}
	assert_almost_eq(GuestUrgency.of_task(_sim.world, task), 0.6)


func test_staff_panel_job_tiers_still_beat_urgency() -> void:
	var server: StaffAgent = _lone_server()
	var priorities: StaffJobPriorities = StaffJobPriorities.new(&"server")
	priorities.set_priority(&"serving", StaffJobPriorities.Level.NORMAL)
	priorities.set_priority(&"cleaning", StaffJobPriorities.Level.HIGH)
	assert_true(server.set_job_priorities(priorities))
	var order: SimTask = _order_task(_guest(), 1.0, _table_item(0))
	var mop: SimTask = SimTask.new(&"clean_spot", &"cleaner", "Mop")
	mop.steps.append(TaskStep.go_to_cell(Vector2i(1, 1)))
	mop.steps.append(TaskStep.work(5))
	server.priorities[&"cleaner"] = 2
	server.skills[&"cleaner"] = 3
	_sim.world.board.post(mop, _sim.world.now)
	_sim.world.advance()
	assert_eq(server.task, mop, "the player's higher Cleaning tier wins over the most urgent order")
	assert_eq(order.state, SimTask.State.OPEN)


func test_dirty_table_task_is_nudged_by_a_waiting_party() -> void:
	var server: StaffAgent = _lone_server()
	var bus: SimTask = SimTask.new(&"bus_table", &"server", "Clear table")
	bus.priority = 1
	bus.steps.append(TaskStep.go_to_item(_table_item(0).id, "to table", true))
	_sim.world.board.post(bus, _sim.world.now)
	var base: float = server._score(_sim.world, bus)
	var waiting: CustomerAgent = _guest()
	waiting.state = CustomerAgent.State.QUEUED
	waiting.queue_patience = 100
	waiting._queue_wait = 90
	assert_almost_eq(GuestUrgency.waiting_for_table(_sim.world), 0.9)
	# _try_claim applies the blend; the raw score is unchanged.
	assert_almost_eq(server._score(_sim.world, bus), base)
	_sim.world.advance()
	assert_eq(server.task, bus)


func test_scoring_is_deterministic_and_consumes_no_random_draws() -> void:
	var guest: CustomerAgent = _guest()
	var task: SimTask = _order_task(guest, 0.7, _table_item(0))
	var rng_state: int = guest.rng.state
	var first: float = GuestUrgency.of_task(_sim.world, task)
	var second: float = GuestUrgency.of_task(_sim.world, task)
	assert_eq(first, second)
	assert_eq(guest.rng.state, rng_state)


func test_inspect_line_names_the_staff_member_coming_to_this_guest() -> void:
	var server: StaffAgent = _lone_server()
	server.display_name = "Sam"
	var guest: CustomerAgent = _guest()
	var other: CustomerAgent = _guest()
	_order_task(guest, 0.3, _table_item(0))
	assert_eq(GuestUrgency.staff_line(_sim.world, guest), "", "nobody has claimed it yet")
	_sim.world.advance()
	assert_eq(GuestUrgency.staff_line(_sim.world, guest), "Sam is coming to take my order")
	assert_eq(GuestUrgency.staff_line(_sim.world, other), "")


func test_longest_waiting_guest_gets_a_freed_table() -> void:
	# Arrival ids are queue order: when the only table frees, the guest who has
	# waited longest takes it, not the nearer or later one.
	var tables: Array[PlacedItem] = []
	for item: PlacedItem in _sim.world.grid.items():
		if (item.def as ItemDef).category == ItemDef.Category.TABLE:
			tables.append(item)
	assert_true(tables.size() >= 1)
	var seat_count: int = 0
	var occupants: Array[CustomerAgent] = []
	for table: PlacedItem in tables:
		for seat: Vector2i in table.seat_cells:
			var occupant: CustomerAgent = _guest()
			table.reserve(seat, occupant.id)
			occupants.append(occupant)
			seat_count += 1
	var early: CustomerAgent = _guest()
	var late: CustomerAgent = _guest()
	early.state = CustomerAgent.State.QUEUED
	late.state = CustomerAgent.State.QUEUED
	early._queue_wait = 150
	late._queue_wait = 10
	assert_false(early._try_seat(_sim.world), "premise: the room is full")
	var freed: PlacedItem = tables[0]
	var freed_seat: Vector2i = freed.seat_cells[0]
	freed.release(freed_seat, occupants[0].id)
	# Only one seat is free, so exactly one of them can sit.
	var early_seated: bool = early._try_seat(_sim.world)
	var late_seated: bool = late._try_seat(_sim.world)
	assert_true(early_seated, "the guest who arrived and waited first sits")
	assert_false(late_seated, "the later guest keeps waiting")


func _guest() -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42 + _sim.world.agents.size()
	# Each guest stands on a free cell of their own, so none waits in the
	# pending-admission list (which receives no patience ticks).
	var spot: Vector2i = _free_spot()
	var guest: CustomerAgent = _sim.add_customer(spot, random)
	assert_true(guest.movement_admitted, "guest admitted at %s" % spot)
	guest.food_patience = 1000
	guest.queue_patience = 1000
	return guest


func _free_spot() -> Vector2i:
	var entry: Vector2i = _sim.world.grid.entries()[0]
	var best: Vector2i = SimGrid.NO_CELL
	var best_distance: int = 1 << 30
	for y: int in _sim.world.grid.size.y:
		for x: int in _sim.world.grid.size.x:
			var spot: Vector2i = Vector2i(x, y)
			var distance: int = absi(spot.x - entry.x) + absi(spot.y - entry.y)
			if distance < best_distance and _sim.world.grid.is_guest_walkable(spot) and not _cell_taken(spot):
				best = spot
				best_distance = distance
	assert_ne(best, SimGrid.NO_CELL)
	return best


func _cell_taken(spot: Vector2i) -> bool:
	for agent: SimAgent in _sim.world.all_agents():
		if agent.cell == spot:
			return true
	return false


func _table_item(index: int) -> PlacedItem:
	var tables: Array[PlacedItem] = []
	for item: PlacedItem in _sim.world.grid.items():
		if (item.def as ItemDef).category == ItemDef.Category.TABLE and not item.seat_cells.is_empty():
			tables.append(item)
	return tables[mini(index, tables.size() - 1)]


## An order-taking task for a guest already used `used` of their food patience.
func _order_task(guest: CustomerAgent, used: float, table: PlacedItem) -> SimTask:
	guest.state = CustomerAgent.State.ORDERING
	guest._food_wait = int(guest.food_patience * used)
	var task: SimTask = SimTask.new(&"take_order", &"server", "Take order")
	task.priority = 2
	task.payload["customer_id"] = guest.id
	task.steps.append(TaskStep.go_to_item(table.id, "walking to guest", true))
	task.steps.append(TaskStep.work(10, "taking order"))
	_sim.world.board.post(task, _sim.world.now)
	return task


func _place_order(guest: CustomerAgent, used: float) -> Order:
	var table: PlacedItem = _table_item(0)
	guest.table_item_id = table.id
	guest.seat_cell = table.seat_cells[0]
	guest.order = guest._new_order(_content.recipe(&"burger"), 10)
	guest.state = CustomerAgent.State.WAITING_FOOD
	guest._food_wait = int(guest.food_patience * used)
	_sim.orders.place(guest.order, _sim.world.now)
	return guest.order


## One idle server and nobody else, so claims are decided by score alone.
func _lone_server() -> StaffAgent:
	for agent: SimAgent in _sim.world.agents.duplicate():
		if agent is StaffAgent:
			_sim.world.remove_agent(agent)
	var server: StaffAgent = StaffAgent.new(&"server", 3)
	server.cell = _sim.staff_spawns.get(&"server", Vector2i(3, 3))
	_sim.world.add_agent(server)
	return server


func _cell_slightly_nearer_untuned(server: StaffAgent, first: SimTask, second: SimTask) -> Vector2i:
	var kept: GuestUrgencyTuning = server.urgency_tuning
	server.urgency_tuning = GuestUrgencyTuning.new()
	server.urgency_tuning.guest_weight = 0.0
	var spot: Vector2i = _cell_slightly_nearer(server, first, second)
	server.urgency_tuning = kept
	return spot


## A walkable cell where `first` scores 5-50% above `second` for this server
## when no urgency applies, so "slightly nearer" is measured, not assumed.
func _cell_slightly_nearer(server: StaffAgent, first: SimTask, second: SimTask) -> Vector2i:
	var kept: GuestUrgencyTuning = server.urgency_tuning
	for y: int in _sim.world.grid.size.y:
		for x: int in _sim.world.grid.size.x:
			var spot: Vector2i = Vector2i(x, y)
			if not _sim.world.grid.is_walkable(spot):
				continue
			server.cell = spot
			var a: float = server._score(_sim.world, first)
			var b: float = server._score(_sim.world, second)
			if b > 0.0 and a > b * 1.05 and a < b * 1.5:
				return spot
	fail("no cell where the first task is slightly nearer")
	return server.cell


func _staff(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent and agent.role == role:
			return agent as StaffAgent
	return null
