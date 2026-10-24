class_name Kitchen
extends RefCounted
## Turns tickets into cook/deliver/bus tasks. Owns dirty-table holds, never its parent.

signal plates_changed(clean: int, total: int, dirty: int, in_use: int)

const WASH_RETRY_TICKS: int = 30

var stock: Stock
var dirty_tables: Dictionary[int, bool] = {}
var plate_cycle_enabled: bool:
	get:
		return _plate_cycle_enabled
var plates: PlateLedger:
	get:
		return _plates
var clean_plates: int:
	get:
		return _plates.clean
var dirty_plates: int:
	get:
		return _plates.dirty
var in_use_plates: int:
	get:
		return _plates.in_use

var _restaurant: WeakRef
var _content: ContentDB
var _tasks: Dictionary[int, SimTask] = {}
var _bus_tasks: Dictionary[int, int] = {}
var _plates: PlateLedger = PlateLedger.new(EconomyTuning.new().starting_plates)
var _wash_task: int = 0
var _wash_blocked: bool = false
var _wash_retry_tick: int = 0
var _plate_cycle_enabled: bool = false
## Retain bypass decisions until morning, including after a cook task completes.
var _plate_bypassed_orders: Dictionary[int, bool] = {}
var _tidying: bool = false


## Uses explicitly supplied stock; a new restaurant never invents ingredients.
func _init(restaurant: RestaurantSim, content: ContentDB, ingredients: Stock) -> void:
	_restaurant = weakref(restaurant)
	_content = content
	stock = ingredients
	_plate_cycle_enabled = _station(restaurant.world, &"sink", ItemDef.Category.STATION) != null
	restaurant.orders.order_placed.connect(_on_order_placed)
	restaurant.orders.order_ready.connect(_on_order_ready)
	restaurant.orders.order_cancelled.connect(_on_order_cancelled)
	restaurant.world.board.task_completed.connect(_on_task_completed)
	restaurant.world.board.task_failed.connect(_on_task_failed)
	restaurant.world.grid.cells_changed.connect(_on_cells_changed)


## Only initial/validated morning setup changes the durable stock total.
func configure_plates(total: int) -> bool:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if total < 0 or sim == null or sim.world.clock.phase != SimClock.Phase.MORNING \
			or not _tasks.is_empty() or _plates.in_use != 0 or _plates.dirty != 0:
		return false
	_plates = PlateLedger.new(total)
	_notify_plates()
	return true


## Observes cook claims after the world's tick, before RestaurantSim.advance returns.
## Only active kitchen tasks are visited; historical orders are never polled.
func advance() -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	for task: SimTask in _tasks.values():
		if task.kind != &"cook" or task.state != SimTask.State.CLAIMED:
			continue
		var order: Order = sim.orders.get_order(int(task.payload["order_id"]))
		if order != null and order.state == Order.State.PLACED:
			sim.orders.set_state(order, Order.State.COOKING)
	_ensure_wash_task()


## Dirty tables cannot accept new guests until a real bussing task finishes.
func is_table_dirty(table_item_id: int) -> bool:
	return dirty_tables.has(table_item_id)


## Reports whether closing cleanup has returned every table to service.
func is_clean() -> bool:
	return dirty_tables.is_empty() and (not _plate_cycle_enabled or (_plates.dirty == 0 and _plates.in_use == 0))


## Called before a seated guest releases its reservation, including forced removal.
func mark_table_dirty(table_item_id: int, order_id: int = 0) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	if order_id > 0:
		_plates.return_to_table(order_id, table_item_id)
	if sim.world.grid.item(table_item_id) == null:
		if _plates.recover_table(table_item_id) > 0:
			_notify_plates()
			_ensure_wash_task()
		return
	dirty_tables[table_item_id] = true
	if _bus_tasks.has(table_item_id):
		return
	var task: SimTask = SimTask.new(&"bus_table", &"server", "Clear table #%d" % table_item_id)
	task.priority = 1
	task.payload = {"kitchen": true, "table_item_id": table_item_id}
	task.steps.append(TaskStep.go_to_item(table_item_id, "walking to dirty table", true))
	task.steps.append(TaskStep.work(40, "bussing table"))
	_post(task, sim)
	if task.state == SimTask.State.OPEN or task.state == SimTask.State.CLAIMED:
		_bus_tasks[table_item_id] = task.id


## The staff tidy up after hours: every table is clean and no kitchen job
## carries over into the next morning. Called at the start of each day.
func tidy_overnight() -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	_tidying = true
	if sim != null:
		for task: SimTask in _tasks.values():
			sim.world.board.cancel(task, &"overnight_tidy")
	_tasks.clear()
	dirty_tables.clear()
	_bus_tasks.clear()
	_wash_task = 0
	_wash_blocked = false
	_wash_retry_tick = 0
	_plate_bypassed_orders.clear()
	_plates.tidy_overnight()
	_tidying = false
	_notify_plates()


## Retries failed bussing only at explicit maintenance boundaries, never a hot loop.
## Dirty flags remain until actual server work succeeds; removed tables are forgotten.
func retry_dirty_tables() -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	for table_id: int in dirty_tables.keys():
		if sim.world.grid.item(table_id) == null:
			dirty_tables.erase(table_id)
			_bus_tasks.erase(table_id)
		elif not _bus_tasks.has(table_id):
			mark_table_dirty(table_id)


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	var was_enabled: bool = _plate_cycle_enabled
	_plate_cycle_enabled = _station(sim.world, &"sink", ItemDef.Category.STATION) != null
	# Grid removal clears reservations before this signal. The ledger, rather
	# than a table flag or prunable order, remains the authority for every plate.
	var recovered: int = 0
	var state: Dictionary = _plates.state()
	var tables: Dictionary[int, bool] = {}
	for token: Dictionary in (state["orders"] as Dictionary).values():
		tables[int(token["table_id"])] = true
	for table_id: int in tables:
		if sim.world.grid.item(table_id) == null:
			recovered += _plates.recover_table(table_id)
	if recovered > 0 or was_enabled != _plate_cycle_enabled:
		_notify_plates()
	var washing: SimTask = sim.world.board.get_task(_wash_task)
	if washing != null and sim.world.grid.item(int(washing.payload["sink_id"])) == null:
		sim.world.board.cancel(washing, &"target_gone")
	_wash_blocked = false
	_wash_retry_tick = 0
	retry_dirty_tables()
	_ensure_wash_task()


func _on_order_placed(order: Order) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	var recipe: RecipeDef = _content.recipe(order.recipe_id)
	var fridge: PlacedItem = _station(sim.world, &"fridge", ItemDef.Category.STORAGE)
	var pass_item: PlacedItem = _pass(sim.world)
	if recipe == null or fridge == null or pass_item == null:
		_cancel(order, &"missing_station")
		return
	var task: SimTask = SimTask.new(&"cook", &"cook", "Cook %s" % recipe.display_name)
	task.timeout_ticks = maxi(600, recipe.total_ticks() * 2 + 300)
	task.payload = {"kitchen": true, "order_id": order.id, "pass_id": pass_item.id, "ingredients_taken": false,
		"station_ids": [] as Array[int]}
	task.steps.append(TaskStep.go_to_item(fridge.id, "fetching ingredients"))
	task.steps.append(TaskStep.work(20, "taking ingredients", _take_ingredients))
	var stations: Array[int] = []
	for step: RecipeStep in recipe.steps:
		var station: PlacedItem = _station(sim.world, step.station_type, ItemDef.Category.STATION)
		if station == null:
			_cancel(order, &"missing_station")
			return
		if not stations.has(station.id):
			stations.append(station.id)
		task.steps.append(TaskStep.go_to_item(station.id, "walking to %s" % step.station_type))
		task.steps.append(TaskStep.work(step.duration_ticks, String(step.station_type)))
	task.payload["station_ids"] = stations
	task.steps.append(TaskStep.go_to_work_cell(pass_item.id, 0, "plating at kitchen side"))
	task.steps.append(TaskStep.wait_until(_take_clean_plate, "a clean plate"))
	task.steps.append(TaskStep.work(10, "plating dish"))
	_post(task, sim)


func _take_ingredients(agent: SimAgent) -> bool:
	var staff: StaffAgent = agent as StaffAgent
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if staff == null or staff.task == null or sim == null:
		return false
	var task: SimTask = staff.task
	if bool(task.payload.get("ingredients_taken", false)):
		return true
	var order: Order = sim.orders.get_order(int(task.payload["order_id"]))
	if order == null or order.state == Order.State.CANCELLED:
		return false
	var recipe: RecipeDef = _content.recipe(order.recipe_id)
	var needs: Dictionary[StringName, int] = {}
	for ingredient: IngredientDef in recipe.ingredients:
		needs[ingredient.id] = needs.get(ingredient.id, 0) + 1
	if not stock.take_many(needs):
		_cancel(order, &"out_of_stock")
		return false
	task.payload["ingredients_taken"] = true
	return true


func _take_clean_plate(agent: SimAgent) -> bool:
	var staff: StaffAgent = agent as StaffAgent
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if staff == null or staff.task == null or sim == null:
		return false
	if staff.task.kind != &"cook" or staff.task.state != SimTask.State.CLAIMED or not _tasks.has(staff.task.id):
		return false
	var order: Order = sim.orders.get_order(int(staff.task.payload["order_id"]))
	if order == null or order.state == Order.State.CANCELLED or order.state == Order.State.DELIVERED:
		return false
	var pass_item: PlacedItem = sim.world.grid.item(int(staff.task.payload["pass_id"]))
	if sim.world.grid.item(order.table_item_id) == null or pass_item == null \
			or pass_item.work_cells.is_empty() or pass_item.work_cells[0] != staff.cell \
			or pass_item.reserved_by(staff.cell) != staff.id:
		_cancel(order, &"missing_station")
		return false
	# A legacy shop without a sink keeps its original unlimited service. Settle
	# this meal's decision only at the pass, and retain it across task replays
	# and a sink purchased after plating has begun.
	if bool(staff.task.payload.get("plate_bypassed", false)) or _plate_bypassed_orders.has(order.id) \
			or (not _plate_cycle_enabled and not _plates.has_order(order.id)):
		staff.task.payload["plate_bypassed"] = true
		staff.task.payload["waiting_for_plate"] = false
		_plate_bypassed_orders[order.id] = true
		return true
	var before: int = _plates.clean
	var accepted: bool = _plates.take(order.id, order.table_item_id)
	staff.task.payload["waiting_for_plate"] = not accepted
	if _plates.clean != before:
		_notify_plates()
	return accepted


func _on_order_ready(order: Order) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	var pass_item: PlacedItem = _pass(sim.world)
	if pass_item == null:
		_cancel(order, &"missing_station")
		return
	var route: Array[Vector2i] = sim.world.grid.find_path_to_any(pass_item.work_cells[1],
		sim.world.grid.walkable_neighbours(order.seat_cell))
	if route.is_empty():
		_cancel(order, &"unreachable")
		return
	var recipe: RecipeDef = _content.recipe(order.recipe_id)
	var task: SimTask = SimTask.new(&"deliver", &"server",
		"Deliver %s" % (recipe.display_name if recipe != null else "meal"))
	task.priority = 3
	task.payload = {"kitchen": true, "order_id": order.id, "order_ids": [order.id],
		"pass_id": pass_item.id}
	task.steps.append(TaskStep.go_to_work_cell(pass_item.id, 1, "collecting from dining side"))
	# GO_TO_CELL intentionally retains item holds. Explicit pickup releases this
	# pass side before the walk, without changing legacy StaffAgent behaviour.
	task.steps.append(TaskStep.work(1, "picking up plate", _release_pass))
	# The route is selected at pickup, when the other READY meals are known.
	# A single-plate task still follows the same pass/seat path and timing.
	_post(task, sim)


func _release_pass(agent: SimAgent) -> bool:
	var staff: StaffAgent = agent as StaffAgent
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if staff == null or staff.task == null or sim == null:
		return false
	var item: PlacedItem = sim.world.grid.item(int(staff.task.payload["pass_id"]))
	if item == null:
		return false
	item.release(item.work_cells[1], staff.id)
	if not bool(staff.task.payload.get("batch_prepared", false)):
		return _prepare_delivery(staff.task, sim, item.work_cells[1])
	return true


## Fold only unclaimed READY deliveries into this trip. The claimed order
## always stays in the bundle; the remaining slots choose the closest meals
## from the pass, then all selected tables run in nearest-next path order.
func _prepare_delivery(task: SimTask, sim: RestaurantSim, pass_cell: Vector2i) -> bool:
	var primary: Order = sim.orders.get_order(int(task.payload["order_id"]))
	if primary == null or primary.state != Order.State.READY:
		return false
	var selected: Array[Order] = [primary]
	var available: Array[Order] = []
	for order: Order in sim.orders.orders_in_state(Order.State.READY):
		if order.id == primary.id:
			continue
		if _open_delivery_for(order.id) != null:
			available.append(order)
	while selected.size() < sim.carry_capacity and not available.is_empty():
		var next: Order = _nearest_order(sim, pass_cell, available)
		if next == null:
			break
		selected.append(next)
		available.erase(next)
	var route_from: Vector2i = pass_cell
	var route_order: Array[Order] = []
	var route_cells: Array[Vector2i] = []
	while not selected.is_empty():
		var next: Order = _nearest_order(sim, route_from, selected)
		if next == null:
			break
		var path: Array[Vector2i] = sim.world.grid.find_path_to_any(route_from,
			sim.world.grid.walkable_neighbours(next.seat_cell))
		route_from = path.back()
		route_order.append(next)
		route_cells.append(route_from)
		selected.erase(next)
	# Plan the complete reachable route before withdrawing any other task. If
	# the claimed meal lost its path since READY, the normal failed-task path
	# cancels that meal and recovers its plate. Unreachable extras keep their
	# original OPEN task and can fail or recover independently at their pickup.
	if not route_order.has(primary):
		return false
	var ids: Array[int] = []
	for index: int in range(route_order.size()):
		var order: Order = route_order[index]
		ids.append(order.id)
		if order.id != primary.id:
			var other: SimTask = _open_delivery_for(order.id)
			if other != null:
				_tasks.erase(other.id)
				sim.world.board.cancel(other, &"batched")
		task.steps.append(TaskStep.go_to_cell(route_cells[index], "carrying meal to guest"))
		task.steps.append(TaskStep.work(10, "serving meal", _serve_order.bind(order.id)))
	task.payload["order_ids"] = ids
	task.payload["carried_count"] = ids.size()
	task.payload["batch_prepared"] = true
	task.label = "Deliver %d meals" % ids.size() if ids.size() > 1 else task.label
	task.timeout_ticks = 600 * maxi(1, ids.size())
	return true


func _nearest_order(sim: RestaurantSim, from_cell: Vector2i, orders: Array[Order]) -> Order:
	var best: Order = null
	var best_length: int = 2147483647
	for order: Order in orders:
		var path: Array[Vector2i] = sim.world.grid.find_path_to_any(from_cell,
			sim.world.grid.walkable_neighbours(order.seat_cell))
		if not path.is_empty() and (path.size() < best_length or
				(path.size() == best_length and (best == null or order.id < best.id))):
			best = order
			best_length = path.size()
	return best


func _open_delivery_for(order_id: int) -> SimTask:
	for task: SimTask in _tasks.values():
		if task.kind == &"deliver" and task.state == SimTask.State.OPEN \
				and not bool(task.payload.get("batch_prepared", false)) \
				and int(task.payload.get("order_id", 0)) == order_id:
			# A dropped prepared trip is OPEN again, but it still covers every
			# READY order in order_ids. Absorbing its primary would strand the rest.
			return task
	return null


func _serve_order(agent: SimAgent, order_id: int) -> bool:
	var staff: StaffAgent = agent as StaffAgent
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if staff == null or staff.task == null or sim == null:
		return false
	var order: Order = sim.orders.get_order(order_id)
	if order == null or order.state != Order.State.READY:
		return true  # A departing guest only loses their own meal and plate.
	if sim.world.grid.item(order.table_item_id) == null \
			or not sim.world.grid.walkable_neighbours(order.seat_cell).has(staff.cell):
		_cancel(order, &"target_gone")
		return true
	sim.orders.set_state(order, Order.State.DELIVERED)
	staff.task.payload["carried_count"] = maxi(0, int(staff.task.payload.get("carried_count", 0)) - 1)
	return true


func _on_order_cancelled(order: Order) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	if not _plate_bypassed_orders.has(order.id) and (_plate_cycle_enabled or _plates.has_order(order.id)):
		if _plates.recover_order(order.id):
			_notify_plates()
	for task: SimTask in _tasks.values():
		if task.kind == &"deliver" and task.payload.get("order_ids", []).has(order.id):
			if bool(task.payload.get("batch_prepared", false)):
				task.payload["carried_count"] = maxi(0, int(task.payload.get("carried_count", 0)) - 1)
			var remaining: bool = false
			for id: int in task.payload["order_ids"]:
				var meal: Order = sim.orders.get_order(id)
				remaining = remaining or (meal != null and meal.state == Order.State.READY)
			if not remaining:
				sim.world.board.cancel(task, order.cancellation_reason)
		elif int(task.payload.get("order_id", 0)) == order.id:
			sim.world.board.cancel(task, order.cancellation_reason)
	_ensure_wash_task()


func _on_task_completed(task: SimTask) -> void:
	if not _tasks.has(task.id):
		return
	_tasks.erase(task.id)
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	if task.kind == &"bus_table":
		var table_id: int = int(task.payload["table_item_id"])
		if _plates.collect_table(table_id) > 0:
			_notify_plates()
		_bus_tasks.erase(table_id)
		if _plates.returned_at_table(table_id) > 0:
			mark_table_dirty(table_id)
		else:
			dirty_tables.erase(table_id)
		_ensure_wash_task()
		return
	if task.kind == &"wash":
		_wash_task = 0
		return
	var order: Order = sim.orders.get_order(int(task.payload["order_id"]))
	if order == null or order.state == Order.State.CANCELLED:
		return
	if task.kind == &"cook":
		if not _plates.has_order(order.id) and not bool(task.payload.get("plate_bypassed", false)):
			_cancel(order, &"no_clean_plates")
			return
		var cook: StaffAgent = sim.world.agent(task.claimed_by) as StaffAgent
		var recipe: RecipeDef = _content.recipe(order.recipe_id)
		var skill: int = cook.skill_for(&"cook") if cook != null else 1
		var quality: float = recipe.base_quality * (0.7 + 0.1 * clampi(skill, 1, 5))
		if cook != null:
			quality += cook.cook_quality_bonus
		for station_id: int in task.payload["station_ids"]:
			var station: PlacedItem = sim.world.grid.item(station_id)
			if station != null:
				quality += (station.def as ItemDef).quality_bonus
		order.quality = clampf(quality, 0.0, 1.0)
		sim.orders.set_state(order, Order.State.READY)
	# Delivery settles each ticket at its own table through _serve_order.


func _on_task_failed(task: SimTask, reason: StringName) -> void:
	if not _tasks.has(task.id):
		return
	_tasks.erase(task.id)
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	if task.kind == &"wash":
		_wash_task = 0
		if _tidying or not _plate_cycle_enabled:
			_wash_blocked = false
			_wash_retry_tick = 0
			return
		# Only genuinely unreachable sinks wait for a layout change. A transient
		# task failure gets a short same-day cooldown, never an immediate repost.
		_wash_blocked = _wash_sink(sim.world) == null
		_wash_retry_tick = sim.world.now + WASH_RETRY_TICKS
		return
	if task.kind == &"bus_table":
		var table_id: int = int(task.payload["table_item_id"])
		_bus_tasks.erase(table_id)
		if sim.world.grid.item(table_id) == null:
			dirty_tables.erase(table_id)
		else:
			sim.world.log_event("Table #%d still dirty: %s" % [table_id, reason])
		return
	if task.kind == &"deliver":
		for id: int in task.payload.get("order_ids", []):
			var meal: Order = sim.orders.get_order(id)
			if meal != null and meal.state == Order.State.READY:
				_cancel(meal, reason)
		return
	var order: Order = sim.orders.get_order(int(task.payload["order_id"]))
	if order != null and order.state != Order.State.CANCELLED:
		var failure: StringName = &"no_clean_plates" if bool(task.payload.get("waiting_for_plate", false)) else reason
		_cancel(order, failure)


func _ensure_wash_task() -> void:
	if _tidying or not _plate_cycle_enabled or _wash_blocked or _wash_task != 0 or _plates.dirty <= 0:
		return
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null or sim.world.now < _wash_retry_tick:
		return
	var sink: PlacedItem = _wash_sink(sim.world)
	if sink == null:
		_wash_blocked = true
		return
	var count: int = mini(4, _plates.dirty)
	var task: SimTask = SimTask.new(&"wash", &"server", "Wash up to %d plates" % count)
	task.priority = 0
	task.defer_to_higher_priority = true
	task.payload = {"kitchen": true, "sink_id": sink.id, "washed_steps": [] as Array[int]}
	task.steps.append(TaskStep.go_to_item(sink.id, "walking to the sink"))
	for plate: int in range(count):
		task.steps.append(TaskStep.work(15, "washing a plate", _wash_one_plate))
	_wash_task = -1  # Guard synchronous task_posted observers until _post settles.
	_post(task, sim)
	if task.state == SimTask.State.OPEN or task.state == SimTask.State.CLAIMED:
		_wash_task = task.id
	elif _wash_task == -1:
		_wash_task = 0


## The first authored sink may be blocked. Prefer the first free, reachable
## work cell, retaining one busy reachable sink as a bounded-wait fallback.
func _wash_sink(world: SimWorld) -> PlacedItem:
	var busy: PlacedItem = null
	var entries: Array[Vector2i] = world.grid.entries()
	for item: PlacedItem in world.grid.items():
		var definition: ItemDef = item.def as ItemDef
		if definition == null or definition.category != ItemDef.Category.STATION or definition.station_type != &"sink":
			continue
		for cell: Vector2i in item.work_cells:
			if not world.grid.is_walkable(cell) or world.grid.find_path_to_any(cell, entries).is_empty():
				continue
			if item.reserved_by(cell) == -1:
				return item
			if busy == null:
				busy = item
	return busy


func _wash_one_plate(agent: SimAgent) -> bool:
	var staff: StaffAgent = agent as StaffAgent
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if staff == null or staff.task == null or sim == null:
		return false
	if staff.task.kind != &"wash" or staff.task.state != SimTask.State.CLAIMED or not _tasks.has(staff.task.id):
		return false
	if staff.step_index >= staff.task.steps.size() or staff.task.steps[staff.step_index].kind != TaskStep.Kind.WORK:
		return false
	var sink: PlacedItem = sim.world.grid.item(int(staff.task.payload["sink_id"]))
	if sink == null or not sink.work_cells.has(staff.cell) or sink.reserved_by(staff.cell) != staff.id:
		return false
	var completed: Array[int] = []
	completed.assign(staff.task.payload["washed_steps"])
	if completed.has(staff.step_index):
		return true
	completed.append(staff.step_index)
	staff.task.payload["washed_steps"] = completed
	if _plates.wash_one():
		_notify_plates()
	return true


func _notify_plates() -> void:
	plates_changed.emit(_plates.clean, _plates.total, _plates.dirty, _plates.in_use)


func _cancel(order: Order, reason: StringName) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim != null:
		sim.orders.set_state(order, Order.State.CANCELLED, reason)


func _post(task: SimTask, sim: RestaurantSim) -> void:
	var id: int = sim.world.board.post(task, sim.world.now)
	_tasks[id] = task
	# A task_posted observer can settle a task synchronously before post returns.
	if task.state == SimTask.State.CANCELLED:
		_on_task_failed(task, &"cancelled_during_post")
	elif task.state == SimTask.State.DONE:
		_on_task_completed(task)


func _station(world: SimWorld, station_type: StringName, category: ItemDef.Category) -> PlacedItem:
	for item: PlacedItem in world.grid.items():
		var definition: ItemDef = item.def as ItemDef
		if definition != null and definition.station_type == station_type and definition.category == category:
			return item
	return null


func _pass(world: SimWorld) -> PlacedItem:
	for item: PlacedItem in world.grid.items():
		var definition: ItemDef = item.def as ItemDef
		if definition != null and definition.category == ItemDef.Category.PASS and item.work_cells.size() >= 2:
			return item
	return null
