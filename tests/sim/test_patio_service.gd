extends TestCase
## Outdoor eligibility shares the real dining/waiting reservation and service paths.

const TABLE: ItemDef = preload("res://data/items/table_2.tres")
const OUTDOOR_TABLE: ItemDef = preload("res://data/items/patio_table_2.tres")
const BENCH: ItemDef = preload("res://data/items/waiting_bench.tres")
const OUTDOOR_BENCH: ItemDef = preload("res://data/items/patio_waiting_bench.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _completed: Dictionary[StringName, int] = {}


func after_each() -> void:
	_completed.clear()


func test_sun_and_cloud_seat_singles_and_parties_on_real_outdoor_tables() -> void:
	for kind: int in [WeatherState.Kind.SUNNY, WeatherState.Kind.CLOUDY]:
		var sim: RestaurantSim = _plain(kind)
		var table: PlacedItem = sim.world.grid.place_def(OUTDOOR_TABLE, Vector2i(2, 8))
		assert_not_null(table)
		var guest: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(2431))
		var state: int = guest.rng.state
		assert_true(guest._try_seat(sim.world))
		assert_eq(guest.table_item_id, table.id)
		assert_true(table.seat_cells.has(guest.seat_cell))
		assert_eq(guest.rng.state, state, "seating never draws weather or guest randomness")
		sim.world.remove_agent(guest)
		var party: Party = sim.add_party(Vector2i(6, 6), [_rng(2432), _rng(2433)])
		assert_true(sim.world.reset_agent_position(PartySeating.members(party, sim.world)[1], sim.world.grid.entries()[1]),
			"the isolated MORNING seating fixture admits each body at a distinct real entry")
		assert_true(PartySeating.try_seat(party, sim.world))
		var members: Array[CustomerAgent] = PartySeating.members(party, sim.world)
		assert_eq(members.size(), 2)
		assert_ne(members[0].seat_cell, members[1].seat_cell)
		for member: CustomerAgent in members:
			assert_eq(member.table_item_id, table.id)
			assert_eq(table.reserved_by(member.seat_cell), member.id)


func test_rain_skips_outdoor_regular_favourite_and_party_seats_but_keeps_indoor_seating() -> void:
	var sim: RestaurantSim = _plain(WeatherState.Kind.RAIN)
	var outside: PlacedItem = sim.world.grid.place_def(OUTDOOR_TABLE, Vector2i(2, 8))
	var inside: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(2, 2))
	assert_not_null(outside)
	assert_not_null(inside)
	var guest: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(2434))
	guest.regular_profile = RegularProfile.new()
	guest.regular_profile.favourite_seat = outside.seat_cells[0]
	assert_true(guest._try_seat(sim.world))
	assert_eq(guest.table_item_id, inside.id, "an outdoor favourite cannot reopen a rainy patio")
	sim.world.remove_agent(guest)
	var party: Party = sim.add_party(Vector2i(6, 6), [_rng(2435), _rng(2436)])
	assert_true(sim.world.reset_agent_position(PartySeating.members(party, sim.world)[1], sim.world.grid.entries()[1]),
		"the isolated MORNING seating fixture admits each body at a distinct real entry")
	assert_true(PartySeating.try_seat(party, sim.world))
	for member: CustomerAgent in PartySeating.members(party, sim.world):
		assert_eq(member.table_item_id, inside.id)
	for seat: Vector2i in outside.seat_cells:
		assert_eq(outside.reserved_by(seat), -1)
	assert_eq(DiningSeats.usable_cells(sim.world.grid, outside, SimGrid.NO_CELL, WeatherState.Kind.RAIN).size(), 0)
	assert_eq(DiningSeats.usable_cells(sim.world.grid, outside).size(), 2,
		"ordinary build path warnings still describe physical access in any weather")


func test_a_waiting_ticket_holds_outdoor_seats_but_never_indoor_ones() -> void:
	var sim: RestaurantSim = _plain(WeatherState.Kind.SUNNY)
	var outside: PlacedItem = sim.world.grid.place_def(OUTDOOR_TABLE, Vector2i(2, 8))
	var inside: PlacedItem = sim.world.grid.place_def(TABLE, Vector2i(2, 2))
	assert_not_null(outside)
	assert_not_null(inside)
	var ticket: Order = Order.new()
	sim.orders.place(ticket, 0)
	var guest: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(2441))
	assert_true(guest._try_seat(sim.world))
	assert_eq(guest.table_item_id, inside.id, "a ticket not yet at the stove keeps the earlier-placed patio closed")
	sim.world.remove_agent(guest)
	assert_true(sim.world.grid.remove(inside.id))
	var party: Party = sim.add_party(Vector2i(6, 6), [_rng(2442), _rng(2443)])
	assert_true(sim.world.reset_agent_position(PartySeating.members(party, sim.world)[1], sim.world.grid.entries()[1]))
	assert_false(PartySeating.try_seat(party, sim.world, null, sim.patio_keeping_up()))
	assert_true(PartySeating.try_seat(party, sim.world), "a caller without a kitchen leaves only weather to decide")
	for member: CustomerAgent in PartySeating.members(party, sim.world):
		sim.world.remove_agent(member)
	for state: Order.State in [Order.State.COOKING, Order.State.READY, Order.State.DELIVERED]:
		sim.orders.set_state(ticket, state)
		assert_eq(sim.patio_keeping_up(), state != Order.State.READY, "a plate waiting at the pass also holds the patio")
	assert_false(PatioRules.can_seat(sim.world.grid, outside.seat_cells[0], WeatherState.Kind.RAIN, true))
	assert_true(PatioRules.can_seat(sim.world.grid, Vector2i(2, 2), WeatherState.Kind.RAIN, false), "indoor seats never ask")
	var single: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(2444))
	assert_true(single._try_seat(sim.world))
	assert_eq(single.table_item_id, outside.id)


func test_outdoor_guests_are_more_patient_once_seated() -> void:
	var sim: RestaurantSim = _plain(WeatherState.Kind.SUNNY)
	var outside: PlacedItem = sim.world.grid.place_def(OUTDOOR_TABLE, Vector2i(2, 8))
	assert_not_null(outside)
	var guest: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(2445))
	var base: int = guest.food_patience
	assert_true(guest._try_seat(sim.world))
	assert_eq(guest.food_patience, base, "booking alone changes nothing")
	# This bare fixture has no menu, so the guest then leaves; patience is set first.
	guest.sit_down(sim.world, sim)
	assert_eq(guest.food_patience, roundi(base * sim.visit_tuning.patio_patience_multiplier))
	assert_true(sim.visit_tuning.patio_patience_multiplier > 1.0)
	var indoor: RestaurantSim = _plain(WeatherState.Kind.SUNNY)
	assert_not_null(indoor.world.grid.place_def(TABLE, Vector2i(2, 2)))
	var inside: CustomerAgent = indoor.add_customer(Vector2i(6, 6), _rng(2446))
	assert_true(inside._try_seat(indoor.world))
	inside.sit_down(indoor.world, indoor)
	assert_eq(inside.food_patience, base, "indoor seats keep their exact patience")


func test_waiting_bench_keeps_arrival_bonus_and_rain_uses_indoor_waiting() -> void:
	for kind: int in [WeatherState.Kind.SUNNY, WeatherState.Kind.CLOUDY, WeatherState.Kind.RAIN]:
		var sim: RestaurantSim = _plain(kind)
		var outside: PlacedItem = sim.world.grid.place_def(OUTDOOR_BENCH, Vector2i(8, 6))
		var inside: PlacedItem = sim.world.grid.place_def(BENCH, Vector2i(2, 2))
		assert_not_null(outside)
		assert_not_null(inside)
		var guest: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(2437))
		guest.move_speed = 1.0
		guest.queue_patience = 20
		var state: int = guest.rng.state
		guest.tick(sim.world)
		var expected: PlacedItem = inside if kind == WeatherState.Kind.RAIN else outside
		assert_eq(guest.waiting_item_id, expected.id, "nearest eligible bench keeps its existing priority")
		assert_eq(guest.queue_patience, 20, "walking does not earn comfortable-wait patience")
		for tick: int in 20:
			guest.tick(sim.world)
			if guest.is_waiting_seated(sim.world):
				break
		assert_true(guest.is_waiting_seated(sim.world))
		assert_eq(guest.queue_patience, 30)
		guest.tick(sim.world)
		assert_eq(guest.queue_patience, 30, "the existing one-time bonus never compounds")
		assert_eq(guest.rng.state, state)
		assert_null(guest.order)
		sim.world.remove_agent(guest)
		for seat: Vector2i in expected.seat_cells:
			assert_eq(expected.reserved_by(seat), -1)


func test_rain_without_an_indoor_bench_keeps_the_door_queue_and_rng() -> void:
	var sim: RestaurantSim = _plain(WeatherState.Kind.RAIN)
	var bench: PlacedItem = sim.world.grid.place_def(OUTDOOR_BENCH, Vector2i(8, 6))
	assert_not_null(bench)
	var guest: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(2438))
	guest.queue_patience = 3
	var state: int = guest.rng.state
	guest.tick(sim.world)
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	assert_eq(guest.waiting_item_id, 0)
	for tick: int in 3:
		guest.tick(sim.world)
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	assert_eq(guest.leave_reason, &"no_table")
	assert_eq(guest.queue_patience, 3)
	assert_false(guest.waited_seated)
	assert_eq(guest.rng.state, state)


func test_rainy_party_capacity_clamps_after_retaining_every_private_seed() -> void:
	for kind: int in [WeatherState.Kind.SUNNY, WeatherState.Kind.RAIN]:
		var sim: RestaurantSim = _plain(kind)
		assert_not_null(sim.world.grid.place_def(TABLE, Vector2i(2, 2)))
		assert_not_null(sim.world.grid.place_def(_four_seat_outdoor_table(), Vector2i(9, 8)))
		var catalogue: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
		var family: CustomerType = CustomerType.new()
		family.id = &"patio_family"
		family.display_name = "Patio family"
		family.party_size_min = 4
		family.party_size_max = 4
		family.weight_at_one_star = 1.0
		family.weight_at_five_stars = 1.0
		catalogue.types = [family]
		assert_true(sim.configure_customer_types(catalogue, 4))
		assert_true(sim.world.clock.start_service())
		var oracle: RandomNumberGenerator = _rng(1)
		oracle.state = sim.rng.state
		oracle.randi_range(0, 1)
		var seeds: Array[int] = []
		for index: int in 4:
			seeds.append(oracle.randi())
		var gap: int = oracle.randi_range(90, 90)
		sim.spawner._remaining = 1
		sim.spawner.advance(sim)
		var expected: int = 2 if kind == WeatherState.Kind.RAIN else 4
		assert_eq(sim.customers().size(), expected)
		assert_eq(sim.spawner._remaining, gap * expected)
		assert_eq(sim.rng.state, oracle.state, "rain never shifts the arrival stream's private-seed draw count")
		for index: int in expected:
			assert_eq(sim.customers()[index].rng.seed, seeds[index])


func test_next_rainy_morning_excludes_patio_from_restroom_capacity() -> void:
	var sim: RestaurantSim = _plain(WeatherState.Kind.SUNNY)
	assert_not_null(sim.world.grid.place_def(TABLE, Vector2i(2, 2)))
	assert_not_null(sim.world.grid.place_def(_four_seat_outdoor_table(), Vector2i(9, 8)))
	sim.restroom_tuning = sim.restroom_tuning.duplicate() as RestroomTuning
	sim.restroom_tuning.seat_threshold = 3
	assert_eq(sim.seat_count(), 6)
	assert_true(sim.restrooms_expected())
	var version: int = sim.world.grid.version
	sim.world.weather.kind = WeatherState.Kind.RAIN
	sim.start_day()
	assert_eq(sim.world.grid.version, version, "weather never edits terrain or paths")
	assert_eq(sim.seat_count(), 2)
	assert_false(sim.restrooms_expected())
	sim.world.weather.kind = WeatherState.Kind.CLOUDY
	sim.start_day()
	assert_eq(sim.seat_count(), 6)


func test_patio_access_and_room_rules_require_the_original_street_route() -> void:
	var sim: RestaurantSim = _plain(WeatherState.Kind.SUNNY)
	var table: PlacedItem = sim.world.grid.place_def(OUTDOOR_TABLE, Vector2i(2, 8))
	var bench: PlacedItem = sim.world.grid.place_def(OUTDOOR_BENCH, Vector2i(8, 6))
	assert_not_null(table)
	assert_not_null(bench)
	assert_eq(RoomRules.id_of(SimGrid.Room.PATIO), &"patio")
	assert_eq(RoomRules.kind_of(&"patio"), SimGrid.Room.PATIO)
	assert_eq(RoomRules.label(SimGrid.Room.PATIO), "Patio")
	assert_eq(RoomRules.violations(sim.world.grid, {}), {})
	var route: Array[Vector2i] = sim.world.grid.find_path(Vector2i(8, 3), table.seat_cells[0])
	assert_false(route.is_empty())
	assert_true(route.has(Vector2i(6, 6)) or route.has(Vector2i(7, 6)))
	assert_eq(WaitingBench.placement_problem(sim.world.grid, bench, RoomRules.guest_reachable(sim.world.grid)), "")
	# Closing the only street opening disconnects staff from the patio. Guests
	# cannot use a hypothetical staff-only room as an alternative route.
	assert_true(sim.world.grid.set_terrain(Vector2i(6, 5), SimGrid.Terrain.WALL))
	assert_true(sim.world.grid.set_terrain(Vector2i(7, 5), SimGrid.Terrain.WALL))
	assert_true(sim.world.grid.find_path(Vector2i(8, 3), table.seat_cells[0]).is_empty())
	assert_eq(sim.world.grid.entries(), [Vector2i(6, 6), Vector2i(7, 6)] as Array[Vector2i],
		"buying and closing the patio never adds an arrival or exit")


func test_real_patio_meals_cross_the_street_door_pay_and_bus_without_overnight_cleanup() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	var kept: Array[ShopPlacement] = []
	for placement: ShopPlacement in layout.placements:
		if content.item(placement.item_id).category != ItemDef.Category.TABLE:
			kept.append(placement)
	layout.placements = kept
	layout.patio_cells = PatioArea.from_layout(layout).cells()
	var placement: ShopPlacement = ShopPlacement.new()
	placement.item_id = OUTDOOR_TABLE.id
	placement.origin = _street(-4, 1)
	layout.placements.append(placement)
	var sim: RestaurantSim = _stocked(layout, content, 2439)
	var entries: Array[Vector2i] = sim.world.grid.entries()
	assert_eq(entries, [_street(0, 0), _street(1, 0)] as Array[Vector2i])
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(sim.world, OUTDOOR_TABLE.id)
	assert_eq(tables.size(), 1)
	if tables.size() != 1:
		return
	var table: PlacedItem = tables[0]
	assert_true(sim.kitchen.plate_cycle_enabled)
	assert_true(sim.kitchen.configure_plates(2))
	sim.menu = [content.recipe(&"burger")]
	sim.world.board.task_completed.connect(_on_task_completed)
	assert_true(sim.world.clock.start_service())
	var guests: Array[CustomerAgent] = []
	for index: int in 2:
		var guest: CustomerAgent = sim.add_customer(entries[0], _rng(2440 + index))
		guest.food_patience = 5000
		guest.eat_ticks = 3
		guests.append(guest)
	var crossed_door: bool = false
	var bus_work_on_patio: bool = false
	var conserved: bool = true
	var drained: bool = false
	for tick: int in 4000:
		sim.advance()
		var plates: PlateLedger = sim.kitchen.plates
		conserved = conserved and plates.clean + plates.dirty + plates.in_use == 2
		for agent: SimAgent in sim.world.agents:
			var staff: StaffAgent = agent as StaffAgent
			if staff == null or staff.task == null:
				continue
			if staff.task.kind == &"deliver" and entries.has(staff.cell):
				crossed_door = true
			if staff.task.kind == &"bus_table" and staff._step_started and staff.work_left > 0.0 \
					and sim.world.grid.is_outdoor_floor(staff.cell):
				bus_work_on_patio = true
		if sim.customers().is_empty() and sim.kitchen.is_clean() and sim.world.board.active_count() == 0:
			drained = true
			break
	assert_true(drained, "two real meals and same-day cleanup finish in the existing kitchen test budget")
	assert_eq(sim.world.clock.day, 1, "next-morning tidy cannot satisfy bussing")
	assert_eq(sim.served_today, 2)
	assert_eq(sim.lost_today, 0)
	assert_true(crossed_door, "the actual delivery worker crossed an original street entry")
	assert_true(bus_work_on_patio, "a worker physically bussed the outdoor table")
	assert_true(conserved)
	assert_eq(_completed.get(&"cook", 0), 2)
	assert_eq(_completed.get(&"deliver", 0), 2)
	assert_true(_completed.get(&"bus_table", 0) > 0)
	assert_true(_completed.get(&"wash", 0) > 0)
	assert_eq(sim.kitchen.plates.clean, 2)
	assert_eq(sim.kitchen.plates.dirty, 0)
	assert_eq(sim.kitchen.plates.in_use, 0)
	for guest: CustomerAgent in guests:
		assert_true(guest.paid)
		assert_eq(guest.leave_reason, &"happy")
		assert_not_null(guest.order)
		if guest.order != null:
			assert_eq(guest.order.state, Order.State.DELIVERED)
			assert_eq(guest.order.table_item_id, table.id)
			assert_true(table.seat_cells.has(guest.order.seat_cell))
	for ingredient: IngredientDef in content.recipe(&"burger").ingredients:
		assert_eq(sim.stock.count(ingredient.id), 98)
	for seat: Vector2i in table.seat_cells:
		assert_eq(table.reserved_by(seat), -1)


func test_no_patio_service_keeps_every_tick_and_random_stream_identical_in_all_weather() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var services: Array[RestaurantSim] = []
	for kind: int in [WeatherState.Kind.SUNNY, WeatherState.Kind.CLOUDY, WeatherState.Kind.RAIN]:
		var sim: RestaurantSim = _stocked(LAYOUT, content, 2443)
		sim.world.weather.kind = kind as WeatherState.Kind
		sim.spawner.min_gap = 35
		sim.spawner.max_gap = 50
		sim.start_day()
		assert_true(sim.world.clock.start_service())
		services.append(sim)
	for tick: int in 600:
		for sim: RestaurantSim in services:
			sim.advance()
		var expected: Dictionary = _service_signature(services[0])
		for index: int in range(1, services.size()):
			assert_eq(_service_signature(services[index]), expected,
				"indoor-only service is identical at tick %d" % tick)
	assert_true(services[0].customers().size() > 0 or services[0].served_today + services[0].lost_today > 0,
		"the comparison exercised actual arrivals and service")


func _stocked(layout: ShopLayout, content: ContentDB, seed_value: int) -> RestaurantSim:
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, seed_value, errors, stock)
	assert_eq(errors, [] as Array[String])
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()
	return sim


func _service_signature(sim: RestaurantSim) -> Dictionary:
	var people: Array[Array] = []
	for agent: SimAgent in sim.world.agents:
		var row: Array = [agent.id, agent.role, agent.cell, agent.path.duplicate(), agent.needs_repath]
		var guest: CustomerAgent = agent as CustomerAgent
		if guest != null:
			row.append_array([guest.state, guest.table_item_id, guest.seat_cell, guest.waiting_item_id,
				guest.rng.seed, guest.rng.state, guest._queue_wait, guest._food_wait, guest.paid])
			if guest.order != null:
				row.append_array([guest.order.id, guest.order.state, guest.order.quality])
		var worker: StaffAgent = agent as StaffAgent
		if worker != null:
			row.append_array([worker.task.id if worker.task != null else 0, worker.step_index, worker.work_left])
		people.append(row)
	return {"clock": sim.world.clock.to_dict(), "arrival_rng": sim.rng.state,
		"remaining": sim.spawner._remaining, "people": people, "events": sim.world.event_log,
		"served": sim.served_today, "lost": sim.lost_today, "reasons": sim.leave_reasons_today.duplicate(),
		"stock": sim.stock.to_dict(), "dirty": sim.kitchen.dirty_tables.duplicate(),
		"plates": [sim.kitchen.plates.clean, sim.kitchen.plates.dirty, sim.kitchen.plates.in_use]}


func _on_task_completed(task: SimTask) -> void:
	_completed[task.kind] = _completed.get(task.kind, 0) + 1


func _plain(kind: int) -> RestaurantSim:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"##############", "#............#", "#............#", "#............#", "#............#",
		"######..######", "......EE......", "..............", "..............", "..............", ".............."
	]))
	var rooms: Dictionary[Vector2i, int] = {}
	for y: int in range(6, 11):
		for x: int in 14:
			var cell: Vector2i = Vector2i(x, y)
			if grid.terrain(cell) == SimGrid.Terrain.FLOOR:
				rooms[cell] = SimGrid.Room.PATIO
	assert_true(grid.set_rooms(rooms))
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(grid)
	grid.cells_changed.connect(sim._on_layout_changed)
	sim.world.weather.kind = kind as WeatherState.Kind
	sim.rng.seed = 243
	sim.spawner = CustomerSpawner.new(sim.rng)
	sim.spawner.min_gap = 90
	sim.spawner.max_gap = 90
	return sim


func _four_seat_outdoor_table() -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"outdoor_capacity_fixture"
	definition.category = ItemDef.Category.TABLE
	definition.outdoor_only = true
	definition.seat_cells = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	return definition


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _street(x: int, y: int) -> Vector2i:
	return SimGrid.from_ascii(LAYOUT.rows).entries()[0] + Vector2i(x, y)
