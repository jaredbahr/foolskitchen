extends TestCase
## Seeded chances and real kitchen/task transitions, not sampled pass rates.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CLEAN: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")
const MESS: MessTuning = preload("res://data/balance/messes.tres")
var _sim: RestaurantSim
var _content: ContentDB
var _stream: RandomNumberGenerator


func after_each() -> void:
	if _sim != null:
		_sim.start_day()
	_sim = null
	_content = null


func test_seeded_spills_and_breakages_repeat_exactly() -> void:
	var a: MishapState = MishapState.new(MESS, _rng(127))
	var b: MishapState = MishapState.new(MESS, _rng(127))
	var hits: int = 0
	for index: int in range(1000):
		var spilled: bool = a.roll_spill(true, 5)
		assert_eq(spilled, b.roll_spill(true, 5))
		if spilled:
			hits += 1
			assert_eq(a.roll_breakage(), b.roll_breakage())
	assert_true(hits > 0)


func test_zero_chance_consumes_no_draws_even_with_clumsy_crowding() -> void:
	var tuning: MessTuning = MESS.duplicate() as MessTuning
	tuning.spill_chance_per_cell = 0.0
	tuning.broken_plate_chance = 0.0
	var random: RandomNumberGenerator = _rng(127)
	var before: int = random.state
	var state: MishapState = MishapState.new(tuning, random)
	for index: int in range(100):
		assert_false(state.roll_spill(true, 99))
		assert_false(state.roll_breakage())
	assert_eq(random.state, before)


func test_clumsy_and_pass_crowding_use_authored_caps() -> void:
	var state: MishapState = MishapState.new(MESS, _rng(1))
	assert_almost_eq(state.spill_chance(false, 0), MESS.spill_chance_per_cell)
	assert_almost_eq(state.spill_chance(true, 0), MESS.spill_chance_per_cell * MESS.clumsy_multiplier)
	assert_true(state.spill_chance(false, MESS.pass_crowding_threshold) > state.spill_chance(false, 0))
	assert_almost_eq(state.spill_chance(true, 100), MESS.maximum_spill_chance)
	assert_not_null(StaffRoster.CATALOGUE.find_trait(&"clumsy"))


func test_spilled_and_broken_plates_are_conserved_and_paid_replacements_arrive_overnight() -> void:
	var plates: PlateLedger = PlateLedger.new(2)
	assert_true(plates.take(1, 2))
	assert_true(plates.spill_order(1, false))
	assert_eq([plates.total, plates.clean, plates.dirty, plates.in_use], [2, 1, 1, 0])
	assert_true(plates.take(1, 2), "the same ticket can be cooked again")
	assert_true(plates.spill_order(1, true))
	assert_eq([plates.total, plates.clean, plates.dirty, plates.in_use], [1, 0, 1, 0])
	assert_false(plates.spill_order(1, true), "a repeated callback cannot lose another plate")
	assert_true(plates.break_untracked_plate())
	assert_eq([plates.total, plates.clean, plates.dirty, plates.in_use], [0, 0, 0, 0])
	assert_false(plates.take(1, 2), "a shop can run out of live plates for the day")
	assert_false(plates.break_untracked_plate())
	plates.tidy_overnight()
	assert_eq([plates.total, plates.clean, plates.dirty, plates.in_use], [2, 2, 0, 0])
	assert_not_null(PlateLedger.from_dict(plates.to_dict()), "existing morning section remains valid")
	plates.tidy_overnight()
	assert_eq(plates.total, 2, "replacement delivery never duplicates")
	assert_eq(plates.to_dict().size(), 2, "no new save fields")


func test_grease_threshold_is_per_station_and_degreasing_resets_rate() -> void:
	var state: MishapState = MishapState.new(MESS, _rng(1))
	for index: int in range(MESS.grease_threshold - 1):
		state.station_used(1)
	assert_false(state.is_greasy(1))
	assert_almost_eq(state.work_multiplier(1), 1.0)
	state.station_used(1)
	assert_true(state.is_greasy(1))
	assert_false(state.is_greasy(2))
	assert_almost_eq(state.work_multiplier(1), 0.9)
	assert_true(state.degrease(1))
	assert_almost_eq(state.work_multiplier(1), 1.0)
	assert_eq(state.degreases_today, 1)
	assert_false(state.degrease(1))


func test_actual_station_work_slows_ten_percent_until_the_degrease_completes() -> void:
	_make()
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], _rng(42))
	guest.food_patience = 6000
	assert_true(_sim.world.clock.start_service())
	var cook: StaffAgent = null
	for agent: SimAgent in _sim.world.agents:
		if agent.role == &"cook":
			cook = agent as StaffAgent
	for tick: int in range(2000):
		_sim.advance()
		if cook.task != null and cook.work_left > 10.0 and cook.step_index > 0 \
				and cook.task.steps[cook.step_index - 1].kind == TaskStep.Kind.GO_TO_ITEM \
				and cook.task.steps[cook.step_index].kind == TaskStep.Kind.WORK \
				and cook.task.steps[cook.step_index].work_rate.is_valid():
			break
	assert_not_null(cook.task)
	var station_id: int = cook.task.steps[cook.step_index - 1].item_id
	_grease(station_id)
	var before: float = cook.work_left
	_sim.advance()
	assert_almost_eq(before - cook.work_left, cook.work_speed(&"cook") * 0.9)
	var degrease: SimTask = _sim.clean_tasks.station_task_for(station_id)
	if degrease.state == SimTask.State.OPEN:
		_sim.world.board.claim(degrease, 999, _sim.world.now)
	_sim.world.board.complete(degrease)
	before = cook.work_left
	_sim.advance()
	assert_almost_eq(before - cook.work_left, cook.work_speed(&"cook"))


func test_spill_messes_ignore_random_dirt_cap_and_one_clean_clears_all_kinds() -> void:
	_make()
	var cell: Vector2i = Vector2i(4, 7)
	assert_true(_sim.cleanliness.add_spill(cell))
	assert_true(_sim.cleanliness.add_spill(cell, true))
	assert_eq(_sim.cleanliness.spot_count(), 1)
	assert_eq(_sim.cleanliness.floor_mess_kind(cell), CleanlinessState.MessKind.BROKEN_PLATE)
	_sim.clean_tasks.sync_spots()
	var task: SimTask = _sim.clean_tasks.task_for(cell)
	assert_eq(task.label, "Sweep up a broken plate")
	assert_true(_sim.world.board.claim(task, 10, _sim.world.now))
	_sim.world.board.complete(task)
	assert_false(_sim.cleanliness.has_spot(cell))
	assert_eq(_sim.cleanliness.sticky_spot_count(), 0)


func test_cleaner_gets_degrease_before_server_and_off_blocks_server_fallback() -> void:
	_make()
	var station: PlacedItem = _station()
	_grease(station.id)
	var task: SimTask = _sim.clean_tasks.station_task_for(station.id)
	assert_not_null(task)
	assert_eq(StaffJobPriorities.job_for_task(task.kind, &"server"), &"cleaning")
	assert_eq(task.priority, 0)
	var server: StaffAgent = _server()
	server.tick(_sim.world)
	assert_eq(server.task, task, "no cleaner: server can take low-priority cleaning")
	server.on_removed(_sim.world)
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner", 3)
	cleaner.cell = server.cell
	_sim.world.add_agent(cleaner)
	server.tick(_sim.world)
	assert_null(server.task, "dedicated cleaner keeps the server serving")
	cleaner.tick(_sim.world)
	assert_eq(cleaner.task, task)
	cleaner.on_removed(_sim.world)
	_sim.world.remove_agent(cleaner)
	var priorities: StaffJobPriorities = server.job_priorities()
	assert_true(priorities.set_priority(&"cleaning", StaffJobPriorities.Level.OFF))
	assert_true(server.set_job_priorities(priorities))
	server.tick(_sim.world)
	assert_null(server.task, "saved Off choice is respected")


func test_owner_degreasing_waits_for_eligible_server_even_when_owner_is_closer() -> void:
	_make()
	var station: PlacedItem = _station()
	_grease(station.id)
	var owner: OwnerAgent = _sim.owner_agent()
	owner.assign_mode(&"floor")
	owner.cell = station.work_cells[0]
	_server().cell = _sim.world.grid.entries()[0]
	owner.tick(_sim.world)
	assert_null(owner.task, "idle server comes before owner regardless of distance or actor tick order")
	var choices: StaffJobPriorities = _server().job_priorities()
	choices.set_priority(&"cleaning", StaffJobPriorities.Level.OFF)
	_server().set_job_priorities(choices)
	owner.tick(_sim.world)
	assert_eq(owner.task, _sim.clean_tasks.station_task_for(station.id), "Off server does not block owner help")


func test_owner_floor_can_degrease_but_rest_cannot_and_real_work_clears_grease() -> void:
	_make()
	var server: StaffAgent = _server()
	_sim.world.remove_agent(server)
	var station: PlacedItem = _station()
	_grease(station.id)
	var owner: OwnerAgent = _sim.owner_agent()
	owner.tick(_sim.world)
	assert_null(owner.task)
	assert_true(owner.assign_mode(&"floor"))
	owner.tick(_sim.world)
	assert_eq(owner.task, _sim.clean_tasks.station_task_for(station.id))
	for tick: int in range(400):
		_sim.advance()
		if not _sim.mishaps.is_greasy(station.id):
			break
	assert_false(_sim.mishaps.is_greasy(station.id))
	assert_eq(_sim.mishaps.degreases_today, 1)
	assert_eq(_sim.clean_tasks.active_task_count(), 0)


func test_overnight_withdraws_claimed_degrease_and_clears_every_day_local_counter() -> void:
	_make()
	_grease(_station().id)
	_sim.cleanliness.add_spill(Vector2i(4, 7), true)
	_sim.clean_tasks.sync_spots()
	_sim.mishaps.record_spill(true)
	_server().tick(_sim.world)
	assert_not_null(_server().task)
	_sim.start_day()
	assert_eq(_sim.mishaps.spills_today, 0)
	assert_eq(_sim.mishaps.broken_plates_today, 0)
	assert_eq(_sim.mishaps.grease_at(_station().id), 0)
	assert_eq(_sim.cleanliness.spot_count(), 0)
	assert_eq(_sim.clean_tasks.active_task_count(), 0)
	assert_null(_server().task)


func test_real_food_spill_recooks_same_ticket_and_charges_exactly_one_replacement() -> void:
	_make()
	var random: RandomNumberGenerator = _rng(42)
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
	guest.food_patience = 6000
	guest.eat_ticks = 3
	assert_true(_sim.world.clock.start_service())
	var server: StaffAgent = _server()
	for tick: int in range(2000):
		_sim.advance()
		if server.task != null and int(server.task.payload.get("carried_count", 0)) > 0:
			break
	assert_not_null(guest.order)
	var order: Order = guest.order
	assert_eq(order.state, Order.State.READY)
	var stock_before: int = _sim.stock.count(&"bun")
	var total: int = _sim.kitchen.plates.total
	_sim.mishaps.tuning.broken_plate_chance = 1.0
	assert_true(_sim.kitchen.spill_carried_meal(server))
	assert_eq(guest.order, order)
	assert_eq(order.state, Order.State.PLACED)
	assert_eq(_sim.mishaps.spills_today, 1)
	assert_eq(_sim.mishaps.broken_plates_today, 1)
	assert_eq(_sim.kitchen.plates.total, total - 1)
	assert_false(_sim.kitchen.spill_carried_meal(server))
	for tick: int in range(3000):
		_sim.advance()
		if guest.paid:
			break
	assert_true(guest.paid, "guest receives and pays for the recooked meal")
	assert_eq(order.state, Order.State.DELIVERED)
	assert_eq(_sim.stock.count(&"bun"), stock_before - 1, "recooking consumes real ingredients")
	assert_eq(_sim.kitchen.plates.total, _sim.kitchen.plates.clean + _sim.kitchen.plates.dirty + _sim.kitchen.plates.in_use)
	_sim.start_day()
	assert_eq(_sim.kitchen.plates.total, total)


func test_real_seeded_carry_spills_repeat_without_stationary_draws() -> void:
	var first: Array[int] = _real_spill_trace(127)
	_sim.start_day()
	_sim = null
	_content = null
	assert_eq(_real_spill_trace(127), first, "same real routes, spills and plate losses")
	assert_true(first[0] > 0)


func test_spilled_tray_primary_cannot_serve_recook_from_stale_route_or_cancel_other_meals() -> void:
	_make()
	_sim.carry_capacity = 2
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(_sim.world, &"table_2")
	var orders: Array[Order] = []
	for index: int in range(2):
		var order: Order = Order.new()
		order.recipe_id = &"burger"
		order.customer_id = 100 + index
		order.table_item_id = tables[index].id
		order.seat_cell = tables[index].seat_cells[0]
		_sim.orders.place(order, _sim.world.now)
		_sim.orders.set_state(order, Order.State.READY)
		orders.append(order)
	var task: SimTask = null
	for candidate: SimTask in _sim.world.board.open_tasks():
		if candidate.kind == &"deliver" and int(candidate.payload["order_id"]) == orders[0].id:
			task = candidate
	assert_not_null(task)
	var server: StaffAgent = _server()
	assert_true(_sim.world.board.claim(task, server.id, _sim.world.now))
	server.task = task
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	assert_true(_sim.kitchen._prepare_delivery(task, _sim, pass_item.work_cells[1]))
	assert_eq(task.payload["carried_count"], 2)
	var spilled_id: int = int(task.payload["order_ids"][0])
	task.payload["order_id"] = spilled_id
	var remaining_id: int = int(task.payload["order_ids"][1])
	var old_callback: Callable
	for step: TaskStep in task.steps:
		if step.on_done.is_valid() and step.on_done.get_bound_arguments() == [spilled_id]:
			old_callback = step.on_done
	assert_true(old_callback.is_valid())
	assert_true(_sim.kitchen.spill_carried_meal(server))
	assert_eq(task.payload["order_id"], remaining_id)
	var spilled: Order = _sim.orders.get_order(spilled_id)
	_sim.orders.set_state(spilled, Order.State.READY)
	server.cell = _sim.service_cells(spilled.table_item_id, spilled.seat_cell)[0]
	assert_true(old_callback.call(server))
	assert_eq(spilled.state, Order.State.READY, "old tray never picked up the recooked meal")
	assert_eq(task.payload["carried_count"], 1)
	_sim.orders.set_state(spilled, Order.State.CANCELLED, &"out_of_stock")
	assert_eq(task.state, SimTask.State.CLAIMED, "recook cancellation leaves remaining tray meal alive")
	assert_eq(server.task, task)
	assert_eq(_sim.orders.get_order(remaining_id).state, Order.State.READY)


func test_sticky_floor_has_three_plain_quotes_and_report_is_transient() -> void:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.sticky_floor = true
	var tuning: ReviewTuning = ReviewTuning.new()
	assert_eq(ReputationBook.cause_of(visit, tuning), &"sticky_floor")
	var quotes: ReviewQuotes = load("res://data/reviews/quotes.tres") as ReviewQuotes
	assert_true(quotes.is_valid())
	assert_eq(quotes.groups[&"sticky_floor"].size(), 3)
	var report: DayReport = DayReport.new()
	report.mishaps_text = MishapText.daily(1, 1, 2)
	assert_true(report.mishaps_text.begins_with("Mishaps: 1 spill, 1 broken plate; 2 stations degreased"))
	assert_false(report.to_dict().has("mishaps_text"), "no new saved report fields")
	assert_eq(report.to_dict().get("costs"), {})


func _real_spill_trace(_seed_value: int) -> Array[int]:
	_make()
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], _rng(42))
	guest.food_patience = 6000
	guest.eat_ticks = 3
	assert_true(_sim.world.clock.start_service())
	var server: StaffAgent = _server()
	for tick: int in range(2000):
		_sim.advance()
		if server.task != null and int(server.task.payload.get("carried_count", 0)) > 0:
			break
	var random: RandomNumberGenerator = _stream
	_sim.mishaps.tuning.spill_chance_per_cell = 1.0
	_sim.mishaps.tuning.maximum_spill_chance = 1.0
	_sim.mishaps.tuning.broken_plate_chance = 0.5
	var before: int = random.state
	for tick: int in range(10):
		_sim.kitchen.advance()
	assert_eq(random.state, before, "no cell entered: no spill roll")
	for tick: int in range(500):
		_sim.advance()
		if _sim.mishaps.spills_today > 0:
			break
	return [_sim.mishaps.spills_today, _sim.mishaps.broken_plates_today, _sim.kitchen.plates.total] as Array[int]


func _make() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 100, 1)
	_sim = RestaurantSim.create(LAYOUT, _content, 127, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	var clean: CleanlinessTuning = CLEAN.duplicate() as CleanlinessTuning
	clean.arrival_chance = 0.0
	clean.seat_departure_chance = 0.0
	var random: RandomNumberGenerator = _rng(127)
	_stream = random
	assert_true(_sim.configure_cleanliness(CleanlinessState.new(_sim.world.grid, clean, random), clean))
	var mess: MessTuning = MESS.duplicate() as MessTuning
	mess.spill_chance_per_cell = 0.0
	assert_true(_sim.configure_messes(mess, random))
	_sim.start_day()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _station() -> PlacedItem:
	return ShopBuilder.items_with_def(_sim.world, &"stove")[0]


func _server() -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent.role == &"server":
			return agent as StaffAgent
	return null


func _grease(station_id: int) -> void:
	for index: int in range(_sim.mishaps.tuning.grease_threshold):
		_sim.mishaps.station_used(station_id)
	_sim.clean_tasks.sync_stations()
