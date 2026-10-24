extends TestCase
## Real restaurant mode transitions and an explicitly isolated wash-retry fixture.
## No guest state, order outcome, task completion or wash result is installed.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _arrivals: int = 0
var _topology_changes: int = 0
var _wash_posts: Array[SimTask] = []
var _wash_failures: Array[int] = []
var _completed_bypassed: Array[int] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 1000, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 73076, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	_arrivals = 0
	_topology_changes = 0
	_wash_posts.clear()
	_wash_failures.clear()
	_completed_bypassed.clear()
	_sim.customer_arrived.connect(_on_arrived)
	_sim.world.grid.cells_changed.connect(_on_topology_changed)
	_sim.world.board.task_posted.connect(_on_posted)
	_sim.world.board.task_completed.connect(_on_completed)
	_sim.world.board.task_failed.connect(_on_failed)
	_sim.kitchen.plates_changed.connect(_on_plates_changed)


func after_each() -> void:
	_sim = null
	_content = null
	_wash_posts.clear()


func test_no_sink_real_service_exceeds_plate_quota_without_ledger_changes_or_washing() -> void:
	assert_true(_sim.kitchen.configure_plates(1))
	_remove_sink()
	assert_false(_sim.kitchen.plate_cycle_enabled)
	var ledger: PlateLedger = _sim.kitchen.plates
	var before: Dictionary = ledger.state()
	assert_true(_sim.world.clock.start_service())
	for visit: int in range(4):
		var guest: CustomerAgent = _guest()
		for tick: int in range(1200):
			_tick()
			assert_false(_sim.kitchen.plate_cycle_enabled)
			assert_eq(_sim.kitchen.plates, ledger, "legacy mode never replaces the ledger")
			_assert_counts(1, 0, 0)
			if guest.order != null:
				assert_false(ledger.has_order(guest.order.id))
			if guest.state == CustomerAgent.State.LEFT and _sim.world.board.active_count() == 0:
				break
		assert_true(guest.paid, "real legacy visit %d completed" % visit)
		assert_eq(guest.order.state, Order.State.DELIVERED)
		assert_eq(guest.leave_reason, &"happy")
		assert_eq(ledger.state(), before)
		_assert_idle()
	assert_true(_sim.served_today > ledger.total)
	assert_eq(_sim.served_today, 4)
	assert_eq(_sim.lost_today, 0)
	assert_eq(_completed_bypassed.size(), 4)
	assert_eq(_wash_posts.size(), 0)
	assert_eq(_sim.stock.count(&"bun"), 996)
	assert_eq(_sim.world.clock.phase, SimClock.Phase.OPEN)


func test_real_sink_addition_before_plating_enables_plate_consumption() -> void:
	assert_true(_sim.kitchen.configure_plates(1))
	var removed: PlacedItem = _remove_sink()
	var ledger: PlateLedger = _sim.kitchen.plates
	var guest: CustomerAgent = _guest()
	assert_true(_sim.world.clock.start_service())
	var cooking: SimTask = _cook_before_plating(guest)
	assert_not_null(cooking)
	if cooking == null:
		return
	assert_false(bool(cooking.payload.get("plate_bypassed", false)))
	assert_false(_sim.kitchen.plate_cycle_enabled)
	assert_not_null(_add_sink(removed))
	assert_true(_sim.kitchen.plate_cycle_enabled)
	assert_eq(_sim.kitchen.plates, ledger)
	_assert_counts(1, 0, 0)
	for tick: int in range(800):
		_tick()
		if guest.order != null and guest.order.state == Order.State.READY:
			break
	assert_not_null(guest.order)
	if guest.order == null:
		return
	assert_eq(guest.order.state, Order.State.READY)
	assert_true(ledger.has_order(guest.order.id))
	assert_false(bool(cooking.payload.get("plate_bypassed", false)))
	_assert_counts(0, 0, 1)
	_drain_guest(guest)
	assert_true(guest.paid)
	assert_eq(_completed_bypassed.size(), 0)
	assert_true(_wash_posts.size() > 0)
	assert_eq(_sim.stock.count(&"bun"), 999)
	_assert_counts(1, 0, 0)
	_assert_idle()


func test_sink_added_after_real_bypass_cannot_take_a_plate_on_cook_replay_or_completion() -> void:
	assert_true(_sim.kitchen.configure_plates(1))
	var removed: PlacedItem = _remove_sink()
	var ledger: PlateLedger = _sim.kitchen.plates
	var before: Dictionary = ledger.state()
	var guest: CustomerAgent = _guest()
	assert_true(_sim.world.clock.start_service())
	var bypassed: SimTask = _bypassed_cook(guest)
	assert_not_null(bypassed)
	if bypassed == null:
		return
	assert_false(bool(bypassed.payload.get("waiting_for_plate", true)))
	assert_not_null(_add_sink(removed))
	assert_true(_sim.kitchen.plate_cycle_enabled)
	assert_eq(_sim.kitchen.plates, ledger)
	_sim.world.board.drop(bypassed, &"test_bypass_replay")
	for tick: int in range(1500):
		_tick()
		assert_eq(_sim.kitchen.plates, ledger)
		_assert_counts(1, 0, 0)
		if guest.order != null:
			assert_false(ledger.has_order(guest.order.id))
		if guest.state == CustomerAgent.State.LEFT and _sim.world.board.active_count() == 0:
			break
	assert_true(guest.paid)
	assert_eq(guest.order.state, Order.State.DELIVERED)
	assert_eq(bypassed.state, SimTask.State.DONE)
	assert_eq(bypassed.drops, 1)
	assert_true(bool(bypassed.payload.get("plate_bypassed", false)))
	assert_false(bool(bypassed.payload.get("waiting_for_plate", true)))
	assert_eq(_completed_bypassed, [guest.order.id] as Array[int])
	assert_eq(_wash_posts.size(), 0)
	assert_eq(_sim.stock.count(&"bun"), 999, "replaying a bypassed cook does not take ingredients twice")
	assert_eq(ledger.state(), before)
	_assert_idle()


func test_sink_added_after_real_bypass_cancellation_never_allocates_or_resets_stock() -> void:
	assert_true(_sim.kitchen.configure_plates(1))
	var removed: PlacedItem = _remove_sink()
	var ledger: PlateLedger = _sim.kitchen.plates
	var before: Dictionary = ledger.state()
	var guest: CustomerAgent = _guest()
	assert_true(_sim.world.clock.start_service())
	var bypassed: SimTask = _bypassed_cook(guest)
	assert_not_null(bypassed)
	if bypassed == null:
		return
	var cook: StaffAgent = _staff(&"cook")
	var old_wait: TaskStep = bypassed.steps[bypassed.steps.size() - 2]
	assert_not_null(_add_sink(removed))
	assert_true(_sim.kitchen.plate_cycle_enabled)
	# Let the real cook finish first: the bypass decision must survive after
	# its task leaves Kitchen's active map and delivery becomes the live work.
	for tick: int in range(300):
		_tick()
		_assert_counts(1, 0, 0)
		if guest.order.state == Order.State.READY:
			break
	assert_eq(guest.order.state, Order.State.READY)
	assert_eq(bypassed.state, SimTask.State.DONE)
	_sim.orders.set_state(guest.order, Order.State.CANCELLED, &"test_cancel_bypass")
	_sim.orders.set_state(guest.order, Order.State.CANCELLED, &"test_cancel_bypass")
	assert_false(bool(old_wait.on_done.call(cook)))
	assert_eq(_sim.kitchen.plates, ledger)
	_assert_counts(1, 0, 0)
	_drain_guest(guest)
	assert_false(bool(old_wait.on_done.call(cook)))
	assert_false(guest.paid)
	assert_eq(guest.order.state, Order.State.CANCELLED)
	assert_eq(bypassed.state, SimTask.State.DONE)
	assert_true(bool(bypassed.payload.get("plate_bypassed", false)))
	assert_false(ledger.has_order(guest.order.id))
	assert_eq(_sim.kitchen.plates, ledger)
	assert_eq(ledger.state(), before, "cancellation of a bypassed meal does not retire a ledger token")
	assert_eq(_wash_posts.size(), 0)
	assert_eq(_sim.stock.count(&"bun"), 999)
	_assert_counts(1, 0, 0)
	_assert_idle()


func test_present_unreachable_sink_keeps_real_cook_in_plate_cycle_mode() -> void:
	assert_true(_sim.kitchen.configure_plates(0))
	var sink: PlacedItem = _item(&"sink")
	assert_true(_sim.world.grid.set_terrain(sink.work_cells[0], SimGrid.Terrain.WALL))
	assert_true(_sim.kitchen.plate_cycle_enabled, "presence, rather than reachability, enables the cycle")
	var guest: CustomerAgent = _guest()
	assert_true(_sim.world.clock.start_service())
	var waiting: SimTask = null
	var cook: StaffAgent = _staff(&"cook")
	for tick: int in range(1000):
		_tick()
		if cook.task != null and cook.task.kind == &"cook" and cook.why().contains("Waiting for a clean plate"):
			waiting = cook.task
			break
	assert_not_null(waiting)
	if waiting == null:
		return
	for tick: int in range(StaffAgent.STUCK_TICKS * 2 + 1):
		_tick()
		assert_true(_sim.kitchen.plate_cycle_enabled)
		assert_eq(waiting.state, SimTask.State.CLAIMED)
		assert_eq(waiting.drops, 0)
		assert_false(bool(waiting.payload.get("plate_bypassed", false)))
		assert_true(bool(waiting.payload.get("waiting_for_plate", false)))
		_assert_counts(0, 0, 0)
	_sim.orders.set_state(guest.order, Order.State.CANCELLED, &"test_end_wait")
	_drain_guest(guest)
	assert_false(guest.paid)
	assert_eq(_wash_posts.size(), 0)
	_assert_idle()


func test_removing_real_sink_preserves_held_token_and_dirty_stock_does_not_block_legacy_cleanup() -> void:
	assert_true(_sim.kitchen.configure_plates(1))
	var ledger: PlateLedger = _sim.kitchen.plates
	var guest: CustomerAgent = _guest(5000)
	assert_true(_sim.world.clock.start_service())
	for tick: int in range(1200):
		_tick()
		if guest.state == CustomerAgent.State.EATING:
			break
	assert_eq(guest.state, CustomerAgent.State.EATING)
	assert_not_null(guest.order)
	if guest.order == null:
		return
	_assert_counts(0, 0, 1)
	_remove_sink()
	assert_false(_sim.kitchen.plate_cycle_enabled)
	assert_eq(_sim.kitchen.plates, ledger)
	assert_true(ledger.has_order(guest.order.id))
	_assert_counts(0, 0, 1)
	assert_true(_sim.world.grid.remove(guest.table_item_id))
	assert_false(ledger.has_order(guest.order.id))
	_assert_counts(0, 1, 0)
	_drain_guest(guest)
	assert_false(guest.paid)
	assert_eq(guest.leave_reason, &"no_table")
	assert_eq(_sim.kitchen.plates, ledger)
	assert_eq(_wash_posts.size(), 0)
	_assert_counts(0, 1, 0)
	assert_true(_sim.kitchen.is_clean(), "legacy cleanup ignores retained plate buckets after tables are clear")
	_assert_idle()


## Explicitly isolated washing contract: dirty stock is seeded only through
## public take/recover. A real server performs every wash; there are no guests.
func test_isolated_terminal_wash_failure_retries_once_after_cooldown_in_same_open_day() -> void:
	assert_eq(Kitchen.WASH_RETRY_TICKS, 30)
	assert_true(_sim.kitchen.configure_plates(3))
	assert_true(_sim.world.clock.start_service())
	var day: int = _sim.world.clock.day
	var ledger: PlateLedger = _sim.kitchen.plates
	var table: PlacedItem = _item(&"table_2")
	for order_id: int in range(10000, 10003):
		assert_true(ledger.take(order_id, table.id))
		assert_true(ledger.recover_order(order_id))
	_sim.kitchen.advance()
	var original: SimTask = _find_wash()
	assert_not_null(original)
	if original == null:
		return
	_wait_for_first_washed_plate(original)
	_assert_counts(1, 2, 0)
	var failure_tick: int = _sim.world.now
	_sim.world.board.cancel(original, &"test_one_terminal_wash_failure")
	assert_eq(original.state, SimTask.State.CANCELLED)
	assert_eq(_wash_failures, [original.id] as Array[int])
	for elapsed: int in range(1, Kitchen.WASH_RETRY_TICKS):
		_tick()
		assert_eq(_sim.world.now, failure_tick + elapsed)
		assert_null(_find_wash(), "the retry waits for the complete cooldown")
		assert_eq(_wash_posts.size(), 1)
		_assert_counts(1, 2, 0)
	_tick()
	var retry: SimTask = _find_wash()
	assert_not_null(retry)
	if retry == null:
		return
	assert_eq(retry.posted_tick, failure_tick + Kitchen.WASH_RETRY_TICKS)
	assert_ne(retry.id, original.id)
	assert_eq(_wash_posts.size(), 2, "one normal advance posts at most one replacement")
	assert_eq(retry.steps.size(), 3, "only the two still-dirty plates enter the new task")
	assert_eq(retry.payload["washed_steps"], [] as Array[int])
	_assert_counts(1, 2, 0)
	_wait_for_first_washed_plate(retry)
	_assert_counts(2, 1, 0)
	_sim.world.board.drop(retry, &"test_retry_replay")
	for tick: int in range(500):
		_tick()
		assert_eq(_sim.kitchen.plates, ledger)
		assert_eq(_sim.world.clock.phase, SimClock.Phase.OPEN)
		assert_eq(_sim.world.clock.day, day)
		assert_eq(_topology_changes, 0)
		if _sim.kitchen.is_clean() and _sim.world.board.active_count() == 0:
			break
	assert_eq(original.payload["washed_steps"], [1] as Array[int])
	assert_eq(retry.payload["washed_steps"], [1, 2] as Array[int])
	assert_eq(retry.state, SimTask.State.DONE)
	assert_eq(retry.drops, 1)
	assert_eq(_wash_posts.size(), 2)
	assert_eq(_wash_failures, [original.id] as Array[int])
	assert_eq(_topology_changes, 0)
	assert_eq(_sim.world.clock.phase, SimClock.Phase.OPEN)
	assert_eq(_sim.world.clock.day, day)
	_assert_counts(3, 0, 0)
	_assert_idle()


func _guest(eat_ticks: int = 3) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7300 + _arrivals
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


func _remove_sink() -> PlacedItem:
	var sink: PlacedItem = _item(&"sink")
	if sink != null:
		assert_true(_sim.world.grid.remove(sink.id))
	return sink


func _add_sink(removed: PlacedItem) -> PlacedItem:
	if removed == null:
		fail("fixture requires the real removed sink's pose")
		return null
	return _sim.world.grid.place_def(_content.item(&"sink"), removed.origin, removed.quarter_turns)


func _cook_before_plating(guest: CustomerAgent) -> SimTask:
	for tick: int in range(1000):
		_tick()
		var cook: StaffAgent = _staff(&"cook")
		if guest.order != null and cook.task != null and cook.task.kind == &"cook" \
				and int(cook.task.payload["order_id"]) == guest.order.id \
				and bool(cook.task.payload.get("ingredients_taken", false)) \
				and cook.step_index < cook.task.steps.size() - 2:
			return cook.task
	fail("the real cook never reached the recipe before plating")
	return null


func _bypassed_cook(guest: CustomerAgent) -> SimTask:
	for tick: int in range(1000):
		_tick()
		var cook: StaffAgent = _staff(&"cook")
		if guest.order != null and cook.task != null and cook.task.kind == &"cook" \
				and int(cook.task.payload["order_id"]) == guest.order.id \
				and bool(cook.task.payload.get("plate_bypassed", false)) \
				and cook.step_index == cook.task.steps.size() - 1:
			return cook.task
	fail("the real cook never reached bypassed plating")
	return null


func _find_wash() -> SimTask:
	var tasks: Array[SimTask] = _sim.world.board.open_tasks()
	tasks.append_array(_sim.world.board.claimed_tasks())
	for task: SimTask in tasks:
		if task.kind == &"wash":
			return task
	return null


func _wait_for_first_washed_plate(washing: SimTask) -> void:
	for tick: int in range(300):
		_tick()
		var completed: Array = washing.payload["washed_steps"]
		if completed.size() == 1:
			return
	fail("the real server did not finish the first wash step")


func _drain_guest(guest: CustomerAgent) -> void:
	for tick: int in range(1400):
		_tick()
		if guest.state == CustomerAgent.State.LEFT and _sim.world.board.active_count() == 0:
			break
	assert_eq(guest.state, CustomerAgent.State.LEFT)


func _tick() -> void:
	_sim.advance()
	var ledger: PlateLedger = _sim.kitchen.plates
	assert_true(ledger.clean >= 0)
	assert_true(ledger.dirty >= 0)
	assert_true(ledger.in_use >= 0)
	assert_eq(ledger.clean + ledger.dirty + ledger.in_use, ledger.total)


func _assert_counts(clean: int, dirty: int, in_use: int) -> void:
	assert_eq(_sim.kitchen.clean_plates, clean)
	assert_eq(_sim.kitchen.dirty_plates, dirty)
	assert_eq(_sim.kitchen.in_use_plates, in_use)
	assert_eq(clean + dirty + in_use, _sim.kitchen.plates.total)


func _assert_idle() -> void:
	assert_eq(_sim.customers().size(), 0)
	assert_eq(_sim.world.board.active_count(), 0)
	assert_true(_sim.kitchen.is_clean())
	assert_eq(_sim.kitchen.dirty_tables.size(), 0)
	for item: PlacedItem in _sim.world.grid.items():
		for cell: Vector2i in item.work_cells + item.seat_cells:
			assert_eq(item.reserved_by(cell), -1)


func _on_arrived(_guest: CustomerAgent) -> void:
	_arrivals += 1


func _on_topology_changed(_cells: Array[Vector2i]) -> void:
	_topology_changes += 1


func _on_posted(task: SimTask) -> void:
	if task.kind == &"wash":
		_wash_posts.append(task)


func _on_completed(task: SimTask) -> void:
	if task.kind == &"cook" and bool(task.payload.get("plate_bypassed", false)):
		_completed_bypassed.append(int(task.payload["order_id"]))


func _on_failed(task: SimTask, _reason: StringName) -> void:
	if task.kind == &"wash":
		_wash_failures.append(task.id)


## The existing signal remains exactly four primitive plate counters.
func _on_plates_changed(clean: int, total: int, dirty: int, in_use: int) -> void:
	assert_eq(clean + dirty + in_use, total)
