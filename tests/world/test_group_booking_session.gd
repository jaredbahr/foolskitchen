extends TestCase
## Explicit occupied-table boundary fixture with real diners, meals, release,
## dirty-table work, booked seating, payment and Main settlement.

const SOAK: Script = preload("res://tools/booking_soak_core.gd")
const SLOT_MINUTE: int = 15 * 60 + 30
var _main: Node
var _paid_members: Dictionary[int, bool] = {}
var _bus_completed: Dictionary[int, bool] = {}
var _tables: Array[int] = []
var _old_providers: Dictionary


func before_each() -> void:
	_old_providers = SaveSystem._providers.duplicate()
	_paid_members.clear()
	_bus_completed.clear()
	_tables.clear()


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_walkins_eating_before_hold_and_at_slot_drain_through_real_bussing_then_booking_settles() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var prepared: Dictionary = SOAK.prepare(tree, 316, SLOT_MINUTE)
	assert_false(prepared.has("error"), String(prepared.get("error", "")))
	if prepared.has("error"):
		return
	_main = prepared["main"]
	var booking: GroupBooking = prepared["booking"]
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	# Targeted boundary staging only: a later accepted slot, unrelated arrivals
	# delayed, and long eating durations released at slot+5. The 24-case soak
	# does none of this. Extra supplies are actually bought through the cart.
	_tables.assign(prepared["fixture"]["table_ids"])
	_buy_twelve_meal_supplies()
	sim.spawner._remaining = 100000
	sim.customer_paid.connect(_on_paid)
	sim.world.board.task_completed.connect(_on_task_completed)
	assert_true(Clock.sim.start_service())
	var randoms: Array[RandomNumberGenerator] = []
	for index: int in 6:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 31600 + index
		randoms.append(random)
	var walkins: Party = sim.add_party(sim.world.grid.entries()[0], randoms)
	assert_not_null(walkins)
	if walkins == null:
		return
	var diners: Array[CustomerAgent] = PartySeating.members(walkins, sim.world)
	for diner: CustomerAgent in diners:
		diner.eat_ticks = 100000
	_advance_to(SLOT_MINUTE - 90)
	_assert_eating_at_real_seats(diners, sim)
	assert_eq(int(booking.booking["held_group_id"]), 0, "walk-ins acquired the group before the hold")
	_advance_to(SLOT_MINUTE - 75)
	_assert_eating_at_real_seats(diners, sim)
	assert_eq(int(booking.booking["held_group_id"]), _tables[0], "the 75-minute hold never evicts existing diners")
	_advance_to(SLOT_MINUTE)
	_assert_eating_at_real_seats(diners, sim)
	_advance_to(SLOT_MINUTE + 5)
	var booked: Party = null
	for customer: CustomerAgent in sim.customers():
		if customer.party != null and customer.party.booking_id == int(booking.booking["booking_id"]):
			booked = customer.party
			break
	assert_not_null(booked)
	if booked == null:
		return
	assert_false(booked.seated)
	assert_true(booked.queue_started, "all booked bodies have entered their ordinary shared queue")
	assert_eq(booked.queue_wait, 0, "waiting on actual occupied held seats did not spend patience")
	assert_true(sim.world.booking_hold.pauses_queue_patience(sim.world, booked.booking_id))
	var before_tick: int = booked.last_queue_tick
	PartySeating.advance_queue(booked, sim.world, sim, false)
	PartySeating.advance_queue(booked, sim.world, sim, false)
	assert_eq(booked.last_queue_tick, before_tick, "member/recovery callbacks share one queue tick")
	assert_eq(booked.queue_wait, 0)
	for diner: CustomerAgent in diners:
		# Explicit boundary fixture: finish the meal next tick, then let its
		# ordinary PAYING/departure/seat release create the real dirty tasks.
		diner.eat_ticks = diner._eating + 1
	var saw_dirty: bool = false
	var saw_bus_work: bool = false
	var saw_booked_seating: bool = false
	for _tick: int in 4000:
		if not booking.has_active_booking():
			break
		_main.call("run_ticks", 1)
		saw_dirty = saw_dirty or sim.kitchen.is_dining_group_dirty(_tables[0])
		for agent: SimAgent in sim.world.agents:
			var worker: StaffAgent = agent as StaffAgent
			if worker != null and worker.task != null and worker.task.kind == &"bus_table" \
					and _tables.has(worker.task.first_item_id()) and worker.step_index < worker.task.steps.size() \
					and worker.task.steps[worker.step_index].kind == TaskStep.Kind.WORK \
					and worker._step_started and worker.work_left > 0.0:
				saw_bus_work = true
		if booked.seated:
			saw_booked_seating = true
			assert_eq(booked.booked_table_ids, _tables)
	assert_true(saw_dirty, "departing walk-ins actually dirtied the joined physical tables")
	assert_true(saw_bus_work, "reserved cleanup used actual server work steps")
	assert_eq(_bus_completed.size(), 3, "each original physical member was bused")
	assert_true(saw_booked_seating)
	assert_eq(_paid_members.size(), 6, "all six booked guests actually paid")
	assert_eq(String(booking.booking["status"]), String(GroupBooking.STATUS_SETTLED))
	assert_false(bool(sim.booking_review_results.get(booked.booking_id, {}).get("no_seat", true)))
	assert_eq(Economy.ledger.day_totals(2).get(Ledger.BOOKING_DEPOSIT, 0), -30)
	assert_eq(Economy.ledger.day_totals(2).get(Ledger.BOOKING_REFUND, 0), 0)


func _advance_to(minute: int) -> void:
	var target_tick: int = ceili(float(minute - Clock.sim.display_open_minute) \
		/ float(Clock.sim.display_close_minute - Clock.sim.display_open_minute) * Clock.sim.open_ticks)
	assert_true(target_tick >= Clock.sim.phase_tick)
	_main.call("run_ticks", target_tick - Clock.sim.phase_tick)
	assert_eq(Clock.sim.display_minutes(), minute)


func _assert_eating_at_real_seats(diners: Array[CustomerAgent], sim: RestaurantSim) -> void:
	for diner: CustomerAgent in diners:
		assert_eq(diner.state, CustomerAgent.State.EATING)
		assert_eq(diner.cell, diner.seat_cell)
		assert_eq(sim.world.grid.item(diner.table_item_id).reserved_by(diner.seat_cell), diner.id)
		assert_false(diner.paid)


func _buy_twelve_meal_supplies() -> void:
	var ingredients: Dictionary[StringName, bool] = {}
	for recipe: RecipeDef in (_main.get("menu_settings") as MenuSettings).enabled_recipes():
		for ingredient: IngredientDef in recipe.ingredients:
			ingredients[ingredient.id] = true
	for id: StringName in ingredients:
		var missing: int = maxi(0, 12 - Economy.stock.count(id))
		if missing > 0:
			assert_true(_main.call("stock_cart_set", id, missing))
	if not (_main.get("stock_cart") as Dictionary).is_empty():
		assert_true(_main.call("stock_place_order"))


func _on_paid(customer: CustomerAgent, _order: Order, _amount: int) -> void:
	if customer.party != null and customer.party.booking_owned:
		_paid_members[customer.id] = true


func _on_task_completed(task: SimTask) -> void:
	if task.kind == &"bus_table" and _tables.has(task.first_item_id()):
		_bus_completed[task.first_item_id()] = true
