class_name Kitchen
extends RefCounted
## Turns tickets into cook/deliver/bus tasks. Owns dirty-table holds, never its parent.

var stock: Stock
var dirty_tables: Dictionary[int, bool] = {}

var _restaurant: WeakRef
var _content: ContentDB
var _tasks: Dictionary[int, SimTask] = {}
var _bus_tasks: Dictionary[int, int] = {}


## Uses explicitly supplied stock; a new restaurant never invents ingredients.
func _init(restaurant: RestaurantSim, content: ContentDB, ingredients: Stock) -> void:
	_restaurant = weakref(restaurant)
	_content = content
	stock = ingredients
	restaurant.orders.order_placed.connect(_on_order_placed)
	restaurant.orders.order_ready.connect(_on_order_ready)
	restaurant.orders.order_cancelled.connect(_on_order_cancelled)
	restaurant.world.board.task_completed.connect(_on_task_completed)
	restaurant.world.board.task_failed.connect(_on_task_failed)
	restaurant.world.grid.cells_changed.connect(_on_cells_changed)


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


## Dirty tables cannot accept new guests until a real bussing task finishes.
func is_table_dirty(table_item_id: int) -> bool:
	return dirty_tables.has(table_item_id)


## Reports whether closing cleanup has returned every table to service.
func is_clean() -> bool:
	return dirty_tables.is_empty()


## Called before a seated guest releases its reservation, including forced removal.
func mark_table_dirty(table_item_id: int) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null or sim.world.grid.item(table_item_id) == null:
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
	retry_dirty_tables()


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
	task.payload = {"kitchen": true, "order_id": order.id, "ingredients_taken": false,
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
	var task: SimTask = SimTask.new(&"deliver", &"server", "Deliver %s" % order.recipe_id)
	task.priority = 3
	task.payload = {"kitchen": true, "order_id": order.id, "pass_id": pass_item.id}
	task.steps.append(TaskStep.go_to_work_cell(pass_item.id, 1, "collecting from dining side"))
	# GO_TO_CELL intentionally retains item holds. Explicit pickup releases this
	# pass side before the walk, without changing legacy StaffAgent behaviour.
	task.steps.append(TaskStep.work(1, "picking up plate", _release_pass))
	task.steps.append(TaskStep.go_to_cell(route.back(), "carrying meal to guest"))
	task.steps.append(TaskStep.work(10, "serving meal"))
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
	return true


func _on_order_cancelled(order: Order) -> void:
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	for task: SimTask in _tasks.values():
		if int(task.payload.get("order_id", 0)) == order.id:
			sim.world.board.cancel(task, order.cancellation_reason)


func _on_task_completed(task: SimTask) -> void:
	if not _tasks.has(task.id):
		return
	_tasks.erase(task.id)
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	if task.kind == &"bus_table":
		var table_id: int = int(task.payload["table_item_id"])
		dirty_tables.erase(table_id)
		_bus_tasks.erase(table_id)
		return
	var order: Order = sim.orders.get_order(int(task.payload["order_id"]))
	if order == null or order.state == Order.State.CANCELLED:
		return
	if task.kind == &"cook":
		var cook: StaffAgent = sim.world.agent(task.claimed_by) as StaffAgent
		var recipe: RecipeDef = _content.recipe(order.recipe_id)
		var skill: int = cook.skill_for(&"cook") if cook != null else 1
		var quality: float = recipe.base_quality * (0.7 + 0.1 * clampi(skill, 1, 5))
		for station_id: int in task.payload["station_ids"]:
			var station: PlacedItem = sim.world.grid.item(station_id)
			if station != null:
				quality += (station.def as ItemDef).quality_bonus
		order.quality = clampf(quality, 0.0, 1.0)
		sim.orders.set_state(order, Order.State.READY)
	elif task.kind == &"deliver":
		sim.orders.set_state(order, Order.State.DELIVERED)


func _on_task_failed(task: SimTask, reason: StringName) -> void:
	if not _tasks.has(task.id):
		return
	_tasks.erase(task.id)
	var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
	if sim == null:
		return
	if task.kind == &"bus_table":
		var table_id: int = int(task.payload["table_item_id"])
		_bus_tasks.erase(table_id)
		if sim.world.grid.item(table_id) == null:
			dirty_tables.erase(table_id)
		else:
			sim.world.log_event("Table #%d still dirty: %s" % [table_id, reason])
		return
	var order: Order = sim.orders.get_order(int(task.payload["order_id"]))
	if order != null and order.state != Order.State.CANCELLED:
		_cancel(order, reason)


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
