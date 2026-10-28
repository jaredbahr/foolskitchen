extends TestCase
## FK-099 (#187): visible daytime deliveries through the back door (or the
## street door), crates that become stock only when staff put them away, the
## close-of-day safety net, job priority and guests kept off the back door.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const DOOR: Vector2i = Vector2i(13, 6)
const DROP: Vector2i = Vector2i(12, 6)

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _stock: Stock


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_stock = Stock.new()
	_stock.add(&"cheese", 8, 1)
	_stock.add(&"bread", 10, 1)
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, _stock)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash), LAYOUT)
	_editor.set_owner_level(5)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null
	_stock = null


func _can_spend(_amount: int) -> bool:
	return true


func _record_cash(_amount: int, _category: StringName) -> void:
	pass


func _back_door() -> void:
	var edge: Vector3i = SimGrid.edge_between(DROP, DOOR)
	assert_true(_editor.apply_segments({edge: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]),
		_editor.last_check.why)


## Opens with no guests coming, so only the delivery happens.
func _open_quiet() -> void:
	assert_true(_sim.world.clock.start_service())
	_sim.spawner.min_gap = 1000000
	_sim.spawner.max_gap = 1000000
	_sim.spawner.reset()


func _lines(cheese: int, bread: int) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if cheese > 0:
		lines.append({"id": &"cheese", "qty": cheese})
	if bread > 0:
		lines.append({"id": &"bread", "qty": bread})
	return lines


func _courier() -> CourierAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is CourierAgent:
			return agent as CourierAgent
	return null


func _run_until(condition: Callable, limit: int = 3000) -> int:
	for tick: int in limit:
		if condition.call():
			return tick
		_sim.advance()
	return -1


func _dropped() -> bool:
	return not _sim.dock.crates().is_empty() and _sim.dock.crates().all(
		func(crate: Dictionary) -> bool: return int(crate["state"]) != DeliveryDock.CrateState.ON_THE_WAY)


func _idle() -> bool:
	return _sim.dock.is_idle()


# --- Pathing ---------------------------------------------------------------------

func test_a_delivery_comes_from_off_the_lot_through_the_back_door() -> void:
	_back_door()
	_open_quiet()
	var route: Dictionary = WallRules.delivery_route(_sim.world.grid, Vector2i(1, 2))
	assert_eq(route["door"], DOOR)
	assert_eq(route["drop"], DROP)
	assert_eq(route["out"], Vector2i(1, 0))
	# The grid ends at the shop's east wall here (no lot bought), so the path
	# runs OFF_LOT_CELLS straight on beyond it.
	assert_false(_sim.world.grid.in_bounds(DOOR + Vector2i.RIGHT))
	var approach: Array[Vector2i] = []
	for x: int in range(DOOR.x + WallRules.OFF_LOT_CELLS, DOOR.x, -1):
		approach.append(Vector2i(x, 6))
	assert_eq(route["approach"], approach, "up the back door's path, far to near, from out of sight")
	assert_eq(WallRules.lot_cells_of(_sim.world.grid, approach), 0)
	assert_true(_sim.dock.arrive(_lines(4, 6)))
	assert_eq(_stock.count(&"cheese"), 8, "nothing is stock on arrival")
	var courier: CourierAgent = _courier()
	assert_not_null(courier, "a delivery person walks in")
	assert_eq(courier.route.front(), DOOR + Vector2i(WallRules.OFF_LOT_CELLS, 0), "from well beyond the lot")
	assert_eq(courier.route.back(), DOOR, "she stops in the doorway")
	assert_eq(courier.drop_cell(), DROP, "and sets the crates down just inside")
	assert_false(_sim.world.grid.in_bounds(courier.cell), "starts beyond the lot")
	var seen: Dictionary[Vector2i, bool] = {}
	var crates: Array[Dictionary] = []
	for tick: int in 600:
		seen[courier.cell] = true
		if crates.is_empty() and _dropped():
			crates = _sim.dock.crates()
		if _sim.dock.couriers().is_empty():
			break
		_sim.advance()
	assert_true(_sim.dock.couriers().is_empty(), "and leaves again")
	assert_false(_sim.world.agents.has(courier), "gone from the world")
	for cell: Vector2i in seen:
		assert_true(cell == DOOR or (cell.y == DOOR.y and cell.x > DOOR.x),
			"only the approach and the door: %s" % cell)
	assert_true(seen.has(DOOR))
	assert_eq(crates.size(), 2, "one crate per storage kind: fridge and dry")
	assert_eq(crates[0]["kind"], StorageSpace.FRIDGE)
	assert_eq(crates[1]["kind"], StorageSpace.DRY)
	for crate: Dictionary in crates:
		if int(crate["state"]) == DeliveryDock.CrateState.WAITING:
			assert_eq(crate["cell"], DROP, "set down on the receiving cell")
	assert_true(_stock.count(&"cheese") == 8 or _stock.count(&"bread") == 10, "not all stock yet")


func test_without_a_back_door_the_delivery_uses_the_street_door() -> void:
	_open_quiet()
	var grid: SimGrid = _sim.world.grid
	var entry: Vector2i = grid.entries()[0]
	var route: Dictionary = WallRules.delivery_route(grid, Vector2i(1, 2))
	assert_eq(route["door"], entry)
	assert_eq(route["drop"], entry + Vector2i.UP, "set down just inside the street door")
	assert_eq(route["out"], Vector2i.DOWN)
	assert_true((route["approach"] as Array).is_empty(), "appears at the street entry, as guests do")
	assert_true(_sim.dock.arrive(_lines(4, 0)))
	assert_eq(_courier().route, [entry] as Array[Vector2i], "she stands in the street door")
	assert_eq(_courier().drop_cell(), entry + Vector2i.UP)
	assert_true(_run_until(_dropped) >= 0)
	assert_eq(_sim.dock.crates()[0]["cell"], entry + Vector2i.UP)


func test_a_back_door_path_stops_at_the_shop() -> void:
	# A wing bought beside the path: the path stops before it.
	var grid: SimGrid = _sim.world.grid
	grid.grow_to(Rect2i(Vector2i.ZERO, Vector2i(18, 12)))
	var open: Array[Vector2i] = WallRules.back_door_approach(grid, DOOR, Vector2i.RIGHT)
	assert_eq(open.size(), 4 + WallRules.OFF_LOT_CELLS, "across the open lot to its edge, then on out of sight")
	assert_eq(WallRules.lot_cells_of(grid, open), 4)
	assert_eq(open.back(), Vector2i(14, 6))
	assert_true(grid.set_terrain(Vector2i(16, 6), SimGrid.Terrain.WALL))
	assert_eq(WallRules.back_door_approach(grid, DOOR, Vector2i.RIGHT),
		[Vector2i(15, 6), Vector2i(14, 6)] as Array[Vector2i])


func test_a_back_door_that_cannot_reach_storage_is_not_used() -> void:
	_back_door()
	# Wall the receiving cell off from the rest of the shop.
	assert_true(_sim.world.grid.set_segments({
		SimGrid.edge_between(DROP, Vector2i(11, 6)): SimGrid.Segment.WALL,
		SimGrid.edge_between(DROP, Vector2i(12, 5)): SimGrid.Segment.WALL,
		SimGrid.edge_between(DROP, Vector2i(12, 7)): SimGrid.Segment.WALL,
	} as Dictionary[Vector3i, int]))
	var route: Dictionary = WallRules.delivery_route(_sim.world.grid, Vector2i(1, 2))
	assert_eq(route["door"], _sim.world.grid.entries()[0], "the street door instead")


func test_no_route_at_all_means_the_goods_come_at_once() -> void:
	_open_quiet()
	for entry: Vector2i in _sim.world.grid.entries():
		_sim.world.grid.set_terrain(entry, SimGrid.Terrain.OUTSIDE)
	assert_false(_sim.dock.arrive(_lines(4, 0)), "the caller stocks it instead")
	assert_true(_sim.dock.is_idle())
	assert_null(_courier())


func test_only_a_service_delivery_is_visible() -> void:
	assert_eq(_sim.world.clock.phase, SimClock.Phase.MORNING)
	assert_false(_sim.dock.arrive(_lines(4, 0)), "morning orders arrive at once (Jared)")
	assert_true(_sim.dock.is_idle())


# --- Carrying --------------------------------------------------------------------

func test_crates_become_stock_only_when_put_away() -> void:
	_back_door()
	_open_quiet()
	var stored: Array[Dictionary] = []
	_sim.dock.stored.connect(func(lines: Array[Dictionary]) -> void: stored.append_array(lines))
	assert_true(_sim.dock.arrive(_lines(4, 6)))
	assert_true(_run_until(_dropped) >= 0)
	assert_eq(_sim.dock.pending_by_id(), {&"cheese": 4, &"bread": 6} as Dictionary[StringName, int])
	var tasks: Array[SimTask] = []
	for crate: Dictionary in _sim.dock.crates():
		_sim.advance()
		var task: SimTask = _sim.dock.task_for_crate(int(crate["id"]))
		assert_not_null(task, "each crate is one job")
		assert_eq(task.kind, DeliveryDock.TASK_KIND)
		assert_eq(StaffJobPriorities.job_for_task(task.kind), &"cleaning")
		tasks.append(task)
	var fridge: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"fridge")[0]
	assert_eq(tasks[0].payload["item"], fridge.id, "the fridge crate goes to the fridge")
	assert_eq(tasks[1].payload["item"], fridge.id, "no shelf yet: dry goods go in by the built-in pantry")
	assert_eq(tasks[0].steps[DeliveryDock.STEP_CARRY].kind, TaskStep.Kind.GO_TO_CELL,
		"never reserves the fridge a cook needs")
	assert_true(fridge.work_cells.has(tasks[0].steps[DeliveryDock.STEP_CARRY].cell))
	var carried: bool = false
	for tick: int in 3000:
		if _sim.dock.is_idle():
			break
		_sim.advance()
		for crate: Dictionary in _sim.dock.crates():
			if int(crate["state"]) == DeliveryDock.CrateState.CARRIED:
				carried = true
				var carrier: SimAgent = _sim.world.agent(int(crate["carrier_id"]))
				assert_eq(carrier.role, &"server", "the server carries (no cleaner on the team)")
				assert_eq(crate["cell"], carrier.cell, "the crate goes with them")
		# Stock and what still waits always add up to everything delivered.
		var waiting: Dictionary[StringName, int] = _sim.dock.pending_by_id()
		assert_eq(_stock.count(&"cheese") + int(waiting.get(&"cheese", 0)), 12)
		assert_eq(_stock.count(&"bread") + int(waiting.get(&"bread", 0)), 16)
	assert_true(carried)
	assert_true(_run_until(_idle) >= 0)
	assert_eq(_stock.count(&"cheese"), 12, "put away: now it is stock")
	assert_eq(_stock.count(&"bread"), 16)
	assert_eq(stored.size(), 2)
	assert_true(_sim.dock.pending_by_id().is_empty())
	# Stock once the crate goes in; filling the shelves finishes the job.
	assert_true(_run_until(func() -> bool: return tasks.all(
		func(task: SimTask) -> bool: return task.state == SimTask.State.DONE),
		DeliveryDock.PUT_AWAY_TICKS * 2) >= 0)


func test_dry_crates_go_to_a_storage_shelf_and_frozen_ones_to_the_freezer() -> void:
	assert_true(_editor.buy(&"storage_shelf", Vector2i(12, 1), 2), _editor.last_check.why)
	assert_true(_editor.buy(&"freezer", Vector2i(11, 9), 0), _editor.last_check.why)
	_back_door()
	_open_quiet()
	var lines: Array[Dictionary] = _lines(0, 6)
	lines.append({"id": &"frozen_fries", "qty": 10})
	assert_true(_sim.dock.arrive(lines))
	assert_true(_run_until(_dropped) >= 0)
	_sim.advance()
	var targets: Array[StringName] = []
	for crate: Dictionary in _sim.dock.crates():
		var task: SimTask = _sim.dock.task_for_crate(int(crate["id"]))
		targets.append((_sim.world.grid.item(int(task.payload["item"])).def as ItemDef).id)
	assert_eq(targets, [&"freezer", &"storage_shelf"] as Array[StringName], "by storage kind")
	assert_true(_run_until(_idle) >= 0)
	assert_eq(_stock.count(&"frozen_fries"), 10)


func test_a_dropped_crate_goes_down_where_the_carrier_stood() -> void:
	_back_door()
	_open_quiet()
	assert_true(_sim.dock.arrive(_lines(4, 0)))
	assert_true(_run_until(func() -> bool: return _sim.dock.crates().any(
		func(crate: Dictionary) -> bool: return int(crate["state"]) == DeliveryDock.CrateState.CARRIED)) >= 0)
	for tick: int in 6:
		_sim.advance()
	var crate: Dictionary = _sim.dock.crates()[0]
	var task: SimTask = _sim.dock.task_for_crate(int(crate["id"]))
	var carrier: SimAgent = _sim.world.agent(int(crate["carrier_id"]))
	var spot: Vector2i = carrier.cell
	_sim.world.board.drop(task, &"test")
	crate = _sim.dock.crates()[0]
	assert_eq(int(crate["state"]), DeliveryDock.CrateState.WAITING)
	assert_eq(crate["cell"], spot, "set down, not lost")
	assert_eq(task.steps[0].cell, spot, "picked up again from there")
	assert_false(bool(task.payload["carrying"]))
	assert_true(_run_until(_idle) >= 0)
	assert_eq(_stock.count(&"cheese"), 12, "still arrives in full")


func test_storage_sold_while_a_crate_is_carried_over_keeps_the_goods() -> void:
	_back_door()
	_open_quiet()
	assert_true(_sim.dock.arrive(_lines(4, 0)))
	assert_true(_run_until(func() -> bool: return _sim.dock.crates().any(
		func(crate: Dictionary) -> bool: return int(crate["state"]) == DeliveryDock.CrateState.CARRIED)) >= 0)
	var fridge: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"fridge")[0]
	assert_true(_sim.world.grid.remove(fridge.id))
	for tick: int in 400:
		_sim.advance()
	var crates: Array[Dictionary] = _sim.dock.crates()
	assert_eq(crates.size(), 1, "set down, not lost")
	assert_eq(int(crates[0]["state"]), DeliveryDock.CrateState.WAITING)
	assert_eq(_stock.count(&"cheese"), 8)
	_sim.dock.store_all()
	assert_eq(_stock.count(&"cheese"), 12)


func test_she_sets_the_crates_down_at_the_bottom_of_her_bend() -> void:
	_back_door()
	_open_quiet()
	assert_true(_sim.dock.arrive(_lines(4, 6)))
	var courier: CourierAgent = _courier()
	assert_true(_run_until(func() -> bool: return courier.unloading()) >= 0)
	assert_true(courier.carrying, "still in her hands as she starts to bend")
	assert_false(courier.dropped)
	for tick: int in CourierAgent.DROP_TICK:
		_sim.advance()
	assert_false(courier.carrying, "on the floor at the bend's lowest point")
	var states: Array[int] = []
	for crate: Dictionary in _sim.dock.crates():
		states.append(int(crate["state"]))
	assert_eq(states, [DeliveryDock.CrateState.WAITING, DeliveryDock.CrateState.ON_THE_WAY] as Array[int],
		"the one in her hands first")
	for tick: int in CourierAgent.UNLOAD_TICKS - CourierAgent.DROP_TICK:
		_sim.advance()
	assert_false(_dropped(), "not while she stands over the stack")
	_sim.advance()
	assert_eq(courier.state, CourierAgent.State.LEAVING)
	assert_true(_dropped(), "the rest once she has stepped away, clear of the stack")
	assert_eq(courier.cell, DOOR, "set down from the doorway, not from among them")


func test_the_top_crate_is_lifted_first_so_none_is_left_in_mid_air() -> void:
	_back_door()
	_open_quiet()
	var lines: Array[Dictionary] = _lines(4, 6)
	lines.append({"id": &"frozen_fries", "qty": 4})
	assert_true(_sim.dock.arrive(lines))
	assert_true(_run_until(_dropped) >= 0)
	var slots: Array[int] = []
	for crate: Dictionary in _sim.dock.crates():
		slots.append(int(crate["slot"]))
	slots.sort()
	assert_eq(slots, [0, 1, 2] as Array[int], "one stack, three high")
	var lifted: int = 0
	for tick: int in 3000:
		if _sim.dock.is_idle():
			break
		var before: int = 0
		for crate: Dictionary in _sim.dock.crates():
			if int(crate["state"]) == DeliveryDock.CrateState.WAITING:
				before += 1
		_sim.advance()
		var layers: Dictionary[Vector2i, Array] = {}
		var waiting: int = 0
		for crate: Dictionary in _sim.dock.crates():
			if int(crate["state"]) != DeliveryDock.CrateState.WAITING:
				continue
			waiting += 1
			if not layers.has(crate["cell"]):
				layers[crate["cell"]] = []
			layers[crate["cell"]].append(int(crate["slot"]))
		for cell: Vector2i in layers:
			var found: Array = layers[cell]
			found.sort()
			assert_eq(found, range(found.size()), "tick %d: every crate rests on the floor or another" % tick)
		if waiting < before:
			lifted += 1
			for crate: Dictionary in _sim.dock.crates():
				if int(crate["state"]) == DeliveryDock.CrateState.CARRIED:
					var task: SimTask = _sim.dock.task_for_crate(int(crate["id"]))
					if task != null and task.payload.has("layer"):
						assert_eq(int(task.payload["layer"]), waiting, "the top one was lifted")
	assert_true(lifted >= 2)
	assert_true(_sim.dock.is_idle())


# --- Safety nets -------------------------------------------------------------------

func test_anything_not_put_away_by_closing_is_stored() -> void:
	_back_door()
	_open_quiet()
	assert_true(_sim.dock.arrive(_lines(4, 6)))
	assert_true(_run_until(_dropped) >= 0)
	_sim.advance()
	assert_eq(_sim.dock.crates().size(), 2, "closing comes before anyone has put them away")
	assert_eq(_stock.count(&"cheese"), 8)
	assert_false(_sim.dock.couriers().is_empty(), "the delivery person is still here")
	var task: SimTask = _sim.dock.task_for_crate(int(_sim.dock.crates()[0]["id"]))
	assert_not_null(task)
	# Last orders with nobody inside closes at once.
	_sim.world.clock.phase = SimClock.Phase.LAST_ORDERS
	var closed: Array[int] = []
	_sim.service_closed.connect(func(day: int) -> void: closed.append(day))
	assert_true(_run_until(func() -> bool: return _sim.world.clock.phase == SimClock.Phase.CLOSED, 50) >= 0)
	assert_eq(closed.size(), 1)
	assert_true(_sim.dock.is_idle(), "stored at closing, before the day's books")
	assert_null(_courier())
	assert_eq(_stock.count(&"cheese"), 12, "never lost")
	assert_eq(_stock.count(&"bread"), 16)
	assert_eq(task.state, SimTask.State.CANCELLED, "the carrying job is withdrawn")
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent:
			assert_false(AgentPresentationController.frame_for(agent, _sim.world).crate_count > 0,
				"nobody is left holding a crate")


func test_a_delivery_still_on_its_way_is_stored_before_the_morning() -> void:
	_back_door()
	_open_quiet()
	assert_true(_sim.dock.arrive(_lines(4, 0)))
	_sim.advance()
	assert_not_null(_courier(), "still walking in")
	_sim.start_day()
	assert_true(_sim.dock.is_idle(), "nothing in transit at the morning save (rule 9)")
	assert_null(_courier())
	assert_eq(_stock.count(&"cheese"), 12)


func test_a_crate_with_no_storage_waits_for_closing() -> void:
	_back_door()
	_open_quiet()
	var fridge: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"fridge")[0]
	assert_true(_sim.world.grid.remove(fridge.id))
	assert_true(_sim.dock.arrive(_lines(4, 0)))
	assert_true(_run_until(_dropped) >= 0)
	for tick: int in 200:
		_sim.advance()
	assert_eq(_sim.dock.crates().size(), 1)
	assert_null(_sim.dock.task_for_crate(int(_sim.dock.crates()[0]["id"])), "no storage, no job")
	assert_eq(_sim.dock.store_all(), _lines(4, 0))
	assert_eq(_stock.count(&"cheese"), 12)


# --- Job priority -----------------------------------------------------------------

func test_the_cleaner_puts_deliveries_away_and_cooks_and_the_owner_never_do() -> void:
	_back_door()
	_open_quiet()
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner")
	assert_true(cleaner.set_job_priorities(StaffJobPriorities.new(&"cleaner")))
	cleaner.cell = Vector2i(8, 8)
	_sim.world.add_agent(cleaner)
	assert_true(_sim.dock.arrive(_lines(4, 6)))
	var carriers: Dictionary[StringName, bool] = {}
	for tick: int in 3000:
		if _sim.dock.is_idle():
			break
		_sim.advance()
		for crate: Dictionary in _sim.dock.crates():
			if int(crate["state"]) == DeliveryDock.CrateState.CARRIED:
				carriers[_sim.world.agent(int(crate["carrier_id"])).role] = true
	assert_true(_sim.dock.is_idle())
	assert_eq(carriers.keys(), [&"cleaner"] as Array[StringName], "the cleaner's job while one is on the team")
	assert_eq(_stock.count(&"cheese"), 12)


func test_servers_put_deliveries_away_as_serving_and_the_cleaner_as_cleaning() -> void:
	assert_eq(StaffJobPriorities.job_for_task(DeliveryDock.TASK_KIND, &"server"), &"serving",
		"front-of-house work, at the server's Serving level")
	assert_eq(StaffJobPriorities.job_for_task(DeliveryDock.TASK_KIND, &"cleaner"), &"cleaning")
	assert_eq(StaffJobPriorities.job_for_task(DeliveryDock.TASK_KIND, &"cook"), &"cleaning")
	assert_eq(_staff(&"cook").job_priorities().priority(&"cleaning"), StaffJobPriorities.Level.OFF, "never a cook's")
	assert_eq(_staff(&"server").job_priorities().priority(&"serving"), StaffJobPriorities.Level.NORMAL)
	var owner: OwnerAgent = _sim.owner_agent()
	assert_true(_sim.assign_owner(&"floor"))
	_back_door()
	_open_quiet()
	assert_true(_sim.dock.arrive(_lines(4, 6)))
	var carriers: Dictionary[StringName, bool] = {}
	for tick: int in 3000:
		if _sim.dock.is_idle():
			break
		_sim.advance()
		for crate: Dictionary in _sim.dock.crates():
			if int(crate["state"]) == DeliveryDock.CrateState.CARRIED:
				carriers[_sim.world.agent(int(crate["carrier_id"])).role] = true
	assert_true(_sim.dock.is_idle())
	assert_eq(carriers.keys(), [&"server"] as Array[StringName], "not the cook, not the owner on the floor")
	assert_not_null(owner)


func test_servers_carry_only_while_no_guest_is_waiting_on_them() -> void:
	_back_door()
	_open_quiet()
	var server: StaffAgent = _staff(&"server")
	assert_true(_sim.dock.arrive(_lines(4, 0)))
	assert_true(_run_until(_dropped) >= 0)
	var put_away: SimTask = _sim.dock.task_for_crate(int(_sim.dock.crates()[0]["id"]))
	assert_eq(put_away.state, SimTask.State.OPEN)
	assert_null(server.task)
	# Guest work for servers, far off and less urgent: the crate would score higher.
	var guest: SimTask = SimTask.new(&"take_order", &"server", "Take an order")
	guest.steps.append(TaskStep.go_to_cell(Vector2i(1, 9), "walking"))
	_sim.world.board.post(guest, _sim.world.now)
	_sim.advance()
	assert_eq(server.task, guest, "service first: no crate while a guest waits")
	assert_eq(put_away.state, SimTask.State.OPEN)
	_sim.world.board.cancel(guest, &"test")
	for tick: int in 3:
		_sim.advance()
	assert_eq(server.task, put_away, "idle again: now the server carries it")


func test_closing_frees_whoever_was_carrying_at_once() -> void:
	_back_door()
	_open_quiet()
	assert_true(_sim.dock.arrive(_lines(4, 0)))
	assert_true(_run_until(func() -> bool: return _sim.dock.crates().any(
		func(crate: Dictionary) -> bool: return int(crate["state"]) == DeliveryDock.CrateState.CARRIED)) >= 0)
	var carrier: StaffAgent = _sim.world.agent(int(_sim.dock.crates()[0]["carrier_id"])) as StaffAgent
	assert_not_null(carrier.task)
	_sim.world.clock.phase = SimClock.Phase.LAST_ORDERS
	assert_true(_run_until(func() -> bool: return _sim.world.clock.phase == SimClock.Phase.CLOSED, 50) >= 0)
	assert_null(carrier.task, "let go on the closing tick, not the next one")


func _staff(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent and not agent is OwnerAgent and agent.role == role:
			return agent as StaffAgent
	return null


# --- Guests and no-op ---------------------------------------------------------------

func test_guests_never_use_the_back_door_while_deliveries_come_and_go() -> void:
	_back_door()
	assert_true(_sim.world.clock.start_service())
	var deliveries: int = 0
	var courier_at_door: bool = false
	for tick: int in 3000:
		if tick % 600 == 50:
			assert_true(_sim.dock.arrive(_lines(2, 2)))
			deliveries += 1
		_sim.advance()
		for agent: SimAgent in _sim.world.agents:
			if agent is CustomerAgent:
				assert_ne(agent.cell, DOOR, "tick %d: a guest in the back door" % tick)
				assert_ne(agent.next_cell(), DOOR, "tick %d: a guest heading through the back door" % tick)
			elif agent is CourierAgent and agent.cell == DOOR:
				courier_at_door = true
	assert_eq(deliveries, 5)
	assert_true(courier_at_door, "deliveries do use it")
	assert_true(_sim.served_today > 0, "with guests coming and going")


func test_no_orders_change_nothing() -> void:
	var errors: Array[String] = []
	var plain: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 1, errors, Stock.new())
	plain.dock = null
	var with_dock: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 1, errors, Stock.new())
	assert_eq(errors, [] as Array[String])
	var posted: Array[SimTask] = []
	with_dock.world.board.task_posted.connect(func(task: SimTask) -> void:
		if task.kind == DeliveryDock.TASK_KIND:
			posted.append(task))
	for sim: RestaurantSim in [plain, with_dock]:
		assert_true(sim.world.clock.start_service())
		for tick: int in 2500:
			sim.advance()
	assert_eq(with_dock.world.event_log, plain.world.event_log, "the same day, tick for tick")
	assert_eq(with_dock.served_today, plain.served_today)
	assert_eq(with_dock.world.agents.size(), plain.world.agents.size())
	assert_true(posted.is_empty())
	assert_true(with_dock.dock.is_idle())


# --- One back door (D25) ------------------------------------------------------------

func test_build_refuses_a_second_back_door_but_older_shops_keep_theirs() -> void:
	_back_door()
	var second: Vector3i = SimGrid.edge_between(Vector2i(12, 8), Vector2i(13, 8))
	var check: EditCheck = _editor.check_segments({second: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int])
	assert_false(check.ok)
	assert_eq(check.why, WallRules.ONE_BACK_DOOR)
	assert_eq(WallRules.back_door_count(_sim.world.grid), 1)
	# Moving it is a removal, then a new door.
	assert_true(_editor.apply_segments({SimGrid.edge_between(DROP, DOOR): SimGrid.Segment.NONE} as Dictionary[Vector3i, int]))
	assert_true(_editor.apply_segments({second: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	# An older save with two loads and keeps both; only adding is refused.
	assert_true(_sim.world.grid.set_segment(SimGrid.edge_between(DROP, DOOR), SimGrid.Segment.DOORWAY))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	var loaded: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	assert_eq(WallRules.back_door_count(loaded.world.grid), 2, "nothing lost from an older save")
	var editor: ShopEditor = ShopEditor.new(loaded, _content, ShopEditBooks.new(_can_spend, _record_cash), layout)
	assert_eq(WallRules.delivery_cell(loaded.world.grid, Vector2i(1, 2)), DROP, "deliveries use the first")
	var window: Vector3i = SimGrid.edge_between(Vector2i(12, 2), Vector2i(13, 2))
	assert_true(editor.apply_segments({window: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]),
		"other edits still work")
	var third: Vector3i = SimGrid.edge_between(Vector2i(12, 3), Vector2i(13, 3))
	assert_eq(editor.check_segments({third: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]).why,
		WallRules.ONE_BACK_DOOR)
	assert_true(editor.apply_segments({second: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]),
		"removing one is fine")
	assert_eq(WallRules.back_door_count(loaded.world.grid), 1)


func test_a_back_door_is_one_cell_wide() -> void:
	var wide: Dictionary[Vector3i, int] = {
		SimGrid.edge_between(DROP, DOOR): SimGrid.Segment.DOORWAY,
		SimGrid.edge_between(Vector2i(12, 7), Vector2i(13, 7)): SimGrid.Segment.DOORWAY,
	}
	var check: EditCheck = _editor.check_segments(wide)
	assert_false(check.ok)
	assert_eq(check.why, WallRules.BACK_DOOR_WIDTH, "not 'already has one' on a shop with none")
	_back_door()
	assert_eq(_editor.check_segments({SimGrid.edge_between(Vector2i(12, 7), Vector2i(13, 7)):
		SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]).why, WallRules.BACK_DOOR_WIDTH,
		"widening the one there is")


func test_selling_floor_cannot_bring_back_a_second_back_door() -> void:
	_back_door()
	var wing: Array[Vector2i] = []
	for y: int in range(5, 10):
		wing.append(Vector2i(14, y))
	assert_true(_editor.apply_floor(wing, true), _editor.last_check.why)
	assert_eq(WallRules.back_door_count(_sim.world.grid), 0, "now an interior doorway")
	var other: Vector3i = SimGrid.edge_between(Vector2i(12, 2), Vector2i(13, 2))
	assert_true(_editor.apply_segments({other: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]),
		_editor.last_check.why)
	assert_eq(_editor.check_floor(wing, false).why, WallRules.ONE_BACK_DOOR,
		"selling the wing would make the old doorway a second back door")
