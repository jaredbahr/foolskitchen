extends TestCase
## Gameplay cases advance the real restaurant. The isolated wash fixtures
## seed only the public ledger and are explicitly not full-service evidence.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _arrivals: int = 0
var _drops: Dictionary[int, Array] = {}
var _task_failures: Dictionary[int, StringName] = {}
var _work_callbacks: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_new_restaurant()
	_work_callbacks = 0


func after_each() -> void:
	_sim = null
	_content = null


func test_real_two_plate_service_day_conserves_every_tick_and_finishes_cleanup() -> void:
	assert_true(_sim.kitchen.configure_plates(2))
	_sim.spawner.min_gap = 160
	_sim.spawner.max_gap = 250
	_sim.start_day()
	assert_true(_sim.world.clock.start_service())
	var saw_dirty: bool = false
	var saw_real_washing: bool = false
	var peak_in_use: int = 0
	for tick: int in range(6000):
		_tick()
		saw_dirty = saw_dirty or _sim.kitchen.dirty_plates > 0
		peak_in_use = maxi(peak_in_use, _sim.kitchen.in_use_plates)
		var server: StaffAgent = _staff(&"server")
		if server.task != null and server.task.kind == &"wash":
			saw_real_washing = true
		if _sim.world.clock.phase == SimClock.Phase.CLOSED and _sim.kitchen.is_clean() \
				and _sim.world.board.active_count() == 0:
			break
	assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED)
	assert_true(_arrivals > 0)
	assert_true(_sim.served_today > 0, "real guests were cooked for, served and paid")
	assert_eq(_sim.served_today + _sim.lost_today, _arrivals)
	assert_true(saw_dirty, "returned plates reached the dirty stock through bussing")
	assert_true(saw_real_washing, "a real server claimed sink work")
	assert_true(peak_in_use > 0 and peak_in_use <= 2)
	_assert_counts(2, 0, 0)
	_assert_cleanup()


func test_real_missing_sink_exhaustion_waits_at_pass_then_restored_sink_serves_order() -> void:
	var removed_sink: PlacedItem = _exhaust_one_plate_without_sink()
	var guest: CustomerAgent = _guest()
	var waiting: SimTask = _wait_for_plate(guest)
	assert_not_null(waiting)
	if waiting == null:
		return
	var cook: StaffAgent = _staff(&"cook")
	var pass_item: PlacedItem = _item(&"pass_counter")
	assert_false(waiting.defer_to_higher_priority, "ordinary cook selection is unchanged")
	assert_eq(cook.cell, pass_item.work_cells[0])
	assert_eq(pass_item.reserved_by(cook.cell), cook.id)
	assert_eq(waiting.steps[cook.step_index].kind, TaskStep.Kind.WAIT_UNTIL)
	var observation_ticks: int = StaffAgent.STUCK_TICKS * 2 + 5
	assert_true(waiting.timeout_ticks - (_sim.world.now - waiting.claimed_tick) > observation_ticks)
	for tick: int in range(observation_ticks):
		_tick()
		assert_eq(cook.task, waiting)
		assert_eq(waiting.drops, 0, "resource waits do not enter the stuck recovery path")
		assert_true(cook.why().contains("Waiting for a clean plate"))
		_assert_counts(0, 1, 0)
	var replacement: PlacedItem = _restore_sink(removed_sink)
	assert_not_null(replacement)
	if replacement == null:
		return
	var saw_washing: bool = false
	for tick: int in range(1500):
		_tick()
		var server: StaffAgent = _staff(&"server")
		if server.task != null and server.task.kind == &"wash":
			saw_washing = true
			assert_eq(server.task.payload["sink_id"], replacement.id)
		if guest.state == CustomerAgent.State.LEFT and _sim.kitchen.is_clean() \
				and _sim.world.board.active_count() == 0:
			break
	assert_true(saw_washing, "restoration resumes real server washing")
	assert_true(guest.paid)
	assert_eq(guest.leave_reason, &"happy")
	assert_eq(guest.order.state, Order.State.DELIVERED)
	assert_eq(waiting.state, SimTask.State.DONE)
	assert_eq(waiting.drops, 0)
	assert_eq(_sim.stock.count(&"bun"), 998, "each of the two real meals consumed ingredients once")
	_assert_counts(1, 0, 0)
	_assert_cleanup()


func test_real_plate_wait_uses_existing_timeout_drop_limit_and_readable_guest_reason() -> void:
	_exhaust_one_plate_without_sink()
	var guest: CustomerAgent = _guest()
	# Test-only patience keeps the guest present long enough to observe all three
	# ordinary cook timeouts. Production patience and task limits are untouched.
	guest.food_patience = 10000
	var waiting: SimTask = _wait_for_plate(guest)
	assert_not_null(waiting)
	if waiting == null:
		return
	for tick: int in range(2400):
		_tick()
		if waiting.state == SimTask.State.CANCELLED and guest.state == CustomerAgent.State.LEFT:
			break
	assert_eq(waiting.state, SimTask.State.CANCELLED)
	assert_eq(waiting.drops, TaskBoard.MAX_DROPS)
	assert_eq(_drops.get(waiting.id, []), [&"timeout", &"timeout", &"timeout"] as Array[StringName])
	assert_eq(_task_failures.get(waiting.id, &""), &"dropped_too_often")
	assert_eq(guest.order.state, Order.State.CANCELLED)
	assert_eq(guest.order.cancellation_reason, &"no_clean_plates")
	assert_eq(guest.leave_reason, &"no_clean_plates")
	assert_true(guest.why().contains("no clean plates"))
	assert_false(guest.why().contains("no_clean_plates"))
	assert_false(guest.paid)
	assert_eq(_sim.served_today, 1)
	assert_eq(_sim.lost_today, 1)
	_assert_counts(0, 1, 0)


func test_real_ready_and_carrying_cancellations_recover_exactly_one_plate() -> void:
	_cancel_at_delivery_stage(false)
	_cancel_at_delivery_stage(true)


func test_real_wait_target_removal_and_stale_predicates_never_allocate_a_plate() -> void:
	for remove_pass: bool in [false, true]:
		_new_restaurant()
		var removed_sink: PlacedItem = _exhaust_one_plate_without_sink()
		var guest: CustomerAgent = _guest()
		var waiting: SimTask = _wait_for_plate(guest)
		assert_not_null(waiting)
		if waiting == null:
			continue
		var cook: StaffAgent = _staff(&"cook")
		var stale_step: TaskStep = waiting.steps[cook.step_index]
		var target_id: int = _item(&"pass_counter").id if remove_pass else guest.table_item_id
		assert_true(_sim.world.grid.remove(target_id))
		_tick()
		assert_eq(waiting.state, SimTask.State.CANCELLED)
		assert_eq(guest.order.state, Order.State.CANCELLED)
		assert_false(_sim.kitchen.plates.has_order(guest.order.id))
		assert_not_null(_restore_sink(removed_sink))
		for tick: int in range(600):
			_tick()
			if _sim.kitchen.is_clean() and _sim.world.board.active_count() == 0 \
					and _sim.customers().is_empty():
				break
		_assert_counts(1, 0, 0)
		# Retain and invoke the old predicate only after normal cancellation and
		# real washing have made a clean plate available. It cannot revive work.
		assert_false(bool(stale_step.on_done.call(cook)))
		_assert_counts(1, 0, 0)
		assert_false(_sim.kitchen.plates.has_order(guest.order.id))
		_assert_cleanup()


func test_real_shared_table_bussing_washing_and_removal_preserve_active_diners_plate() -> void:
	assert_true(_sim.kitchen.configure_plates(2))
	var removed_sink: PlacedItem = _remove_sink()
	var first: CustomerAgent = _guest(5000)
	var second: CustomerAgent = _guest(5000)
	assert_true(_sim.world.clock.start_service())
	for tick: int in range(1600):
		_tick()
		if first.state == CustomerAgent.State.EATING and second.state == CustomerAgent.State.EATING:
			break
	assert_eq(first.state, CustomerAgent.State.EATING)
	assert_eq(second.state, CustomerAgent.State.EATING)
	assert_not_null(first.order)
	assert_not_null(second.order)
	if first.order == null or second.order == null:
		return
	assert_eq(first.table_item_id, second.table_item_id)
	assert_ne(first.seat_cell, second.seat_cell)
	var table_id: int = first.table_item_id
	_assert_counts(0, 0, 2)
	_sim.world.remove_agent(first)
	_sim.world.remove_agent(first)
	assert_eq(_sim.lost_today, 1, "repeated forced removal records one departure")
	assert_true(_sim.kitchen.is_table_dirty(table_id))
	_assert_counts(0, 0, 2)
	for tick: int in range(500):
		_tick()
		if _sim.kitchen.dirty_plates == 1:
			break
	_assert_counts(0, 1, 1)
	assert_false(_sim.kitchen.is_table_dirty(table_id))
	assert_eq(second.state, CustomerAgent.State.EATING)
	assert_true(_sim.kitchen.plates.has_order(second.order.id))
	assert_false(_sim.kitchen.plates.state()["orders"][second.order.id]["returned"])
	assert_not_null(_restore_sink(removed_sink))
	for tick: int in range(500):
		_tick()
		if _sim.kitchen.clean_plates == 1:
			break
	_assert_counts(1, 0, 1)
	assert_eq(second.state, CustomerAgent.State.EATING, "washing did not take the active diner's plate")
	assert_true(_sim.kitchen.plates.has_order(second.order.id))
	_sim.world.remove_agent(second)
	assert_true(_sim.kitchen.is_table_dirty(table_id))
	_assert_counts(1, 0, 1)
	assert_true(_sim.world.grid.remove(table_id), "external removal recovers the returned token immediately")
	_assert_counts(1, 1, 0)
	assert_false(_sim.world.grid.remove(table_id))
	_assert_counts(1, 1, 0)
	for tick: int in range(500):
		_tick()
		if _sim.kitchen.is_clean() and _sim.world.board.active_count() == 0:
			break
	_assert_counts(2, 0, 0)
	_assert_cleanup()


## Isolated washing contract, not a gameplay service: no synthetic customer or
## cook result is installed, and only public ledger take/recover seed dirty stock.
func test_isolated_wash_drop_replays_completed_steps_once_and_batches_at_most_four() -> void:
	_seed_isolated_dirty_stock(6)
	var washing: SimTask = _find_task(&"wash")
	assert_not_null(washing)
	if washing == null:
		return
	assert_eq(washing.role, &"server")
	assert_eq(washing.priority, 0)
	assert_true(washing.defer_to_higher_priority, "real sink work yields at claim time")
	assert_eq(washing.steps.size(), 5, "one walk followed by at most four plates")
	for index: int in range(1, washing.steps.size()):
		assert_eq(washing.steps[index].kind, TaskStep.Kind.WORK)
		assert_eq(washing.steps[index].ticks, 15)
	_wait_for_first_washed_plate(washing)
	_assert_counts(1, 5, 0)
	_sim.world.board.drop(washing, &"test_restart")
	for tick: int in range(600):
		_tick()
		if washing.state == SimTask.State.DONE:
			break
	assert_eq(washing.state, SimTask.State.DONE)
	assert_eq(washing.drops, 1)
	assert_eq(washing.payload["washed_steps"], [1, 2, 3, 4] as Array[int])
	_assert_counts(4, 2, 0)
	var next_batch: SimTask = _find_task(&"wash")
	assert_not_null(next_batch)
	if next_batch == null:
		return
	assert_ne(next_batch.id, washing.id)
	assert_eq(next_batch.steps.size(), 3, "the next task contains just the remaining two plates")
	for tick: int in range(400):
		_tick()
		if _sim.kitchen.is_clean() and _sim.world.board.active_count() == 0:
			break
	_assert_counts(6, 0, 0)
	_assert_cleanup()


## Isolated public-ledger fixture: cancellation and retry accounting only.
func test_isolated_wash_cancellation_preserves_dirty_stock_until_real_topology_repair() -> void:
	_seed_isolated_dirty_stock(3)
	var washing: SimTask = _find_task(&"wash")
	assert_not_null(washing)
	if washing == null:
		return
	_wait_for_first_washed_plate(washing)
	_assert_counts(1, 2, 0)
	_sim.world.board.cancel(washing, &"test_sink_failure")
	_run(80)
	assert_eq(washing.state, SimTask.State.CANCELLED)
	assert_null(_find_task(&"wash"), "a failed job does not hot-loop a replacement")
	_assert_counts(1, 2, 0)
	var removed_sink: PlacedItem = _remove_sink()
	assert_null(_find_task(&"wash"), "without a sink the plates remain dirty")
	var replacement: PlacedItem = _restore_sink(removed_sink)
	assert_not_null(replacement)
	var retry: SimTask = _find_task(&"wash")
	assert_not_null(retry)
	if replacement == null or retry == null:
		return
	assert_ne(retry.id, washing.id)
	assert_eq(retry.payload["sink_id"], replacement.id)
	_assert_counts(1, 2, 0)
	for tick: int in range(500):
		_tick()
		if _sim.kitchen.is_clean() and _sim.world.board.active_count() == 0:
			break
	_assert_counts(3, 0, 0)
	_assert_cleanup()


## Isolated dirty-stock setup, followed by actual server claims, movement and work.
func test_isolated_real_server_uses_reachable_second_sink_when_first_is_inaccessible() -> void:
	var first_sink: PlacedItem = _item(&"sink")
	assert_not_null(first_sink)
	if first_sink == null:
		return
	assert_true(_sim.world.grid.set_terrain(first_sink.work_cells[0], SimGrid.Terrain.WALL))
	var second_sink: PlacedItem = _sim.world.grid.place_def(_content.item(&"sink"), Vector2i(11, 1), 2)
	assert_not_null(second_sink)
	if second_sink == null:
		return
	assert_eq(ShopBuilder.items_with_def(_sim.world, &"sink")[0].id, first_sink.id)
	assert_false(_sim.world.grid.is_walkable(first_sink.work_cells[0]))
	var server: StaffAgent = _staff(&"server")
	assert_false(_sim.world.grid.find_path(server.cell, second_sink.work_cells[0]).is_empty())
	_seed_isolated_dirty_stock(2)
	var washing: SimTask = _find_task(&"wash")
	assert_not_null(washing)
	if washing == null:
		return
	assert_eq(washing.payload["sink_id"], second_sink.id)
	var saw_second_sink_work: bool = false
	for tick: int in range(500):
		_tick()
		if server.task == washing and server.step_index > 0 and server.cell == second_sink.work_cells[0]:
			saw_second_sink_work = true
			assert_eq(second_sink.reserved_by(server.cell), server.id)
		if _sim.kitchen.is_clean() and _sim.world.board.active_count() == 0:
			break
	assert_true(saw_second_sink_work, "the real server washed at the reachable second sink")
	assert_eq(washing.state, SimTask.State.DONE)
	assert_eq(washing.drops, 0)
	assert_eq(first_sink.reserved_by(first_sink.work_cells[0]), -1)
	_assert_counts(2, 0, 0)
	_assert_cleanup()


func test_staff_ready_wait_before_ten_work_units_preserves_actual_completion_tick() -> void:
	for skill: int in [1, 3, 5]:
		var without_wait: int = _completion_tick(false, skill)
		var with_wait: int = _completion_tick(true, skill)
		assert_true(without_wait > 0)
		assert_eq(with_wait, without_wait, "available plates add no tick at skill %d" % skill)


func test_staff_false_wait_consumes_claimed_timeout_without_stuck_drops_or_following_work() -> void:
	var task: SimTask = SimTask.new(&"test_wait", &"cook", "Wait for plate")
	task.timeout_ticks = 80
	task.steps.append(TaskStep.wait_until(_never_ready, "a clean plate"))
	task.steps.append(TaskStep.work(1, "must not run", _count_work))
	var world: SimWorld = _staff_world(task)
	var cook: StaffAgent = world.agents[0] as StaffAgent
	for tick: int in range(StaffAgent.STUCK_TICKS * 2 + 5):
		world.advance()
	assert_eq(task.state, SimTask.State.CLAIMED)
	assert_true(world.now - task.claimed_tick > StaffAgent.STUCK_TICKS * 2)
	assert_eq(task.drops, 0)
	assert_true(cook.why().contains("Waiting for a clean plate"))
	assert_eq(_work_callbacks, 0)
	for tick: int in range(300):
		world.advance()
		if task.state == SimTask.State.CANCELLED:
			break
	assert_eq(task.state, SimTask.State.CANCELLED)
	assert_eq(task.drops, TaskBoard.MAX_DROPS)
	assert_eq(_drops.get(task.id, []), [&"timeout", &"timeout", &"timeout"] as Array[StringName])
	assert_eq(_task_failures.get(task.id, &""), &"dropped_too_often")
	assert_eq(_work_callbacks, 0)
	assert_null(cook.task)


func test_staff_false_work_callback_still_cancels_instead_of_waiting() -> void:
	var task: SimTask = SimTask.new(&"test_work", &"cook", "Check stock")
	task.steps.append(TaskStep.work(1, "check ingredients", _never_ready))
	var world: SimWorld = _staff_world(task)
	for tick: int in range(10):
		world.advance()
		if task.state == SimTask.State.CANCELLED:
			break
	assert_eq(task.state, SimTask.State.CANCELLED)
	assert_eq(task.drops, 0)
	assert_eq(_task_failures.get(task.id, &""), &"step_failed")
	assert_null((world.agents[0] as StaffAgent).task)


func _new_restaurant() -> void:
	_arrivals = 0
	_drops.clear()
	_task_failures.clear()
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 1000, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 73073, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	_sim.customer_arrived.connect(_on_arrived)
	_sim.world.board.task_dropped.connect(_on_dropped)
	_sim.world.board.task_failed.connect(_on_failed)


func _guest(eat_ticks: int = 3) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 73 + _arrivals
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
	guest.eat_ticks = eat_ticks
	return guest


func _item(id: StringName) -> PlacedItem:
	var items: Array[PlacedItem] = ShopBuilder.items_with_def(_sim.world, id)
	assert_false(items.is_empty(), "fixture requires %s" % id)
	return null if items.is_empty() else items[0]


func _staff(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent and agent.role == role:
			return agent as StaffAgent
	fail("fixture requires staff role %s" % role)
	return null


func _find_task(kind: StringName) -> SimTask:
	var tasks: Array[SimTask] = _sim.world.board.open_tasks()
	tasks.append_array(_sim.world.board.claimed_tasks())
	for task: SimTask in tasks:
		if task.kind == kind:
			return task
	return null


func _remove_sink() -> PlacedItem:
	var sink: PlacedItem = _item(&"sink")
	assert_not_null(sink)
	if sink != null:
		assert_true(_sim.world.grid.remove(sink.id))
	return sink


func _restore_sink(removed: PlacedItem) -> PlacedItem:
	if removed == null:
		fail("the removed sink must retain its real layout pose")
		return null
	return _sim.world.grid.place_def(_content.item(&"sink"), removed.origin, removed.quarter_turns)


func _exhaust_one_plate_without_sink() -> PlacedItem:
	assert_true(_sim.kitchen.configure_plates(1))
	var removed: PlacedItem = _remove_sink()
	var first: CustomerAgent = _guest()
	assert_true(_sim.world.clock.start_service())
	for tick: int in range(1600):
		_tick()
		if first.paid and _sim.kitchen.dirty_plates == 1:
			break
	assert_true(first.paid, "the first real meal exhausted the single plate")
	_assert_counts(0, 1, 0)
	return removed


func _wait_for_plate(guest: CustomerAgent) -> SimTask:
	for tick: int in range(1000):
		_tick()
		var cook: StaffAgent = _staff(&"cook")
		if guest.order != null and cook.task != null and cook.task.kind == &"cook" \
				and int(cook.task.payload["order_id"]) == guest.order.id \
				and cook.why().contains("Waiting for a clean plate"):
			return cook.task
	fail("a real cook never reached the clean-plate wait")
	return null


func _cancel_at_delivery_stage(carrying: bool) -> void:
	_new_restaurant()
	assert_true(_sim.kitchen.configure_plates(2))
	_remove_sink()
	var guest: CustomerAgent = _guest()
	assert_true(_sim.world.clock.start_service())
	var observed: bool = false
	for tick: int in range(1200):
		_tick()
		if guest.order == null or guest.order.state != Order.State.READY:
			continue
		if not carrying:
			observed = true
			break
		var server: StaffAgent = _staff(&"server")
		if server.task != null and server.task.kind == &"deliver" and server.step_index == 2:
			var pass_item: PlacedItem = _item(&"pass_counter")
			assert_eq(pass_item.reserved_by(pass_item.work_cells[1]), -1)
			observed = true
			break
	assert_true(observed, "real delivery reached carrying=%s" % carrying)
	if not observed or guest.order == null:
		return
	_assert_counts(1, 0, 1)
	_sim.orders.set_state(guest.order, Order.State.CANCELLED, &"test_cancel")
	_sim.orders.set_state(guest.order, Order.State.CANCELLED, &"test_cancel")
	_assert_counts(1, 1, 0)
	assert_false(_sim.kitchen.plates.take(guest.order.id, guest.table_item_id))
	_run(500)
	assert_false(guest.paid)
	assert_eq(guest.order.state, Order.State.CANCELLED)
	assert_eq(guest.leave_reason, &"kitchen_failed")
	assert_eq(_sim.stock.count(&"bun"), 999)
	_assert_counts(1, 1, 0)


func _seed_isolated_dirty_stock(quantity: int) -> void:
	assert_true(_sim.kitchen.configure_plates(quantity))
	var table: PlacedItem = _item(&"table_2")
	for index: int in range(quantity):
		var order_id: int = 10000 + index
		assert_true(_sim.kitchen.plates.take(order_id, table.id))
		assert_true(_sim.kitchen.plates.recover_order(order_id))
	_assert_counts(0, quantity, 0)
	_sim.kitchen.advance()


func _wait_for_first_washed_plate(washing: SimTask) -> void:
	for tick: int in range(300):
		_tick()
		var completed: Array = washing.payload["washed_steps"]
		if completed.size() == 1:
			return
	fail("a real server did not finish the first wash step")


func _completion_tick(with_wait: bool, skill: int) -> int:
	var task: SimTask = SimTask.new(&"test_plating", &"cook", "Plate dish")
	if with_wait:
		task.steps.append(TaskStep.wait_until(_always_ready, "a clean plate"))
	task.steps.append(TaskStep.work(10, "plating dish"))
	var world: SimWorld = _staff_world(task, skill)
	for tick: int in range(40):
		world.advance()
		if task.state == SimTask.State.DONE:
			return world.now
	fail("the pure staff plating fixture did not complete")
	return -1


func _staff_world(task: SimTask, skill: int = 3) -> SimWorld:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([".....", ".....", "....."]))
	var world: SimWorld = SimWorld.new(grid)
	var cook: StaffAgent = StaffAgent.new(&"cook", skill)
	cook.cell = Vector2i(1, 1)
	world.add_agent(cook)
	world.board.task_dropped.connect(_on_dropped)
	world.board.task_failed.connect(_on_failed)
	world.board.post(task, world.now)
	return world


func _always_ready(_agent: SimAgent) -> bool:
	return true


func _never_ready(_agent: SimAgent) -> bool:
	return false


func _count_work(_agent: SimAgent) -> bool:
	_work_callbacks += 1
	return true


func _tick() -> void:
	_sim.advance()
	_assert_conserved()


func _run(ticks: int) -> void:
	for tick: int in range(ticks):
		_tick()


func _assert_conserved() -> void:
	var plates: PlateLedger = _sim.kitchen.plates
	assert_true(plates.clean >= 0)
	assert_true(plates.dirty >= 0)
	assert_true(plates.in_use >= 0)
	assert_eq(plates.clean + plates.dirty + plates.in_use, plates.total, "every tick conserves plate stock")


func _assert_counts(clean: int, dirty: int, in_use: int) -> void:
	assert_eq(_sim.kitchen.clean_plates, clean)
	assert_eq(_sim.kitchen.dirty_plates, dirty)
	assert_eq(_sim.kitchen.in_use_plates, in_use)
	_assert_conserved()


func _assert_cleanup() -> void:
	assert_true(_sim.kitchen.is_clean())
	assert_eq(_sim.customers().size(), 0)
	assert_eq(_sim.world.board.active_count(), 0)
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY]:
		assert_eq(_sim.orders.orders_in_state(state).size(), 0)
	for item: PlacedItem in _sim.world.grid.items():
		for cell: Vector2i in item.work_cells + item.seat_cells:
			assert_eq(item.reserved_by(cell), -1)


func _on_arrived(_guest: CustomerAgent) -> void:
	_arrivals += 1


func _on_dropped(task: SimTask, _agent_id: int, reason: StringName) -> void:
	var reasons: Array[StringName] = []
	reasons.assign(_drops.get(task.id, []))
	reasons.append(reason)
	_drops[task.id] = reasons


func _on_failed(task: SimTask, reason: StringName) -> void:
	_task_failures[task.id] = reason
