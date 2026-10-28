class_name DeliveryDock
extends RefCounted
## Visible daytime deliveries (FK-099, #187). A delivery due during service
## arrives with a delivery person (CourierAgent) who walks in from off the lot
## through the back door (the street door when there is none, or none that
## reaches storage; WallRules.delivery_route; from the back door's path, or
## appearing at the street entry as guests do), sets one crate per storage kind
## down on the receiving cell and leaves. Each crate becomes one `put_away`
## task: walk to it, pick it up, carry it to storage of its kind and put it
## away. Goods count as stock only once put away. The cleaner does it while one
## is on the team (job Cleaning), otherwise servers (job Serving; see
## StaffJobPriorities.ROLE_TASK_JOBS); cooks and the owner never carry.
##
## Never loses goods: the goods were paid when ordered, their storage space
## was reserved then (StorageSpace counts what is waiting here as on order, and
## Build refuses to sell storage it needs), and anything not yet put away is
## stored at once by store_all(), which RestaurantSim calls at closing and
## every morning (so nothing is in transit at the morning save, rule 9). A
## crate with no reachable storage of its kind goes to any reachable storage
## (the starter shop's pantry is built in, behind the kitchen); with none it
## waits for closing. Failed carries retry up to MAX_TRIES, then wait for a
## layout change.
##
## Morning orders still arrive at once (Jared) and never come here; no orders
## means no delivery person, no task and no change at all. Pure: no nodes, no
## random draws.

## Goods were stocked (carried in, or stored at closing): [{id, qty}].
signal stored(lines: Array[Dictionary])

enum CrateState { ON_THE_WAY, WAITING, CARRIED }

const TASK_KIND: StringName = &"put_away"
const PICK_UP_TICKS: int = 8
const PUT_AWAY_TICKS: int = 20
## Failed carries per crate before it waits for a layout change.
const MAX_TRIES: int = 3
## Kinds in crate order: fridge, freezer, dry.
const KINDS: Array[int] = [StorageSpace.FRIDGE, StorageSpace.FREEZER, StorageSpace.DRY]


class Crate extends RefCounted:
	var id: int = 0
	var kind: int = StorageSpace.DRY
	## [{id: StringName, qty: int}]
	var lines: Array[Dictionary] = []
	var cell: Vector2i = SimGrid.NO_CELL
	var state: int = CrateState.ON_THE_WAY
	var courier_id: int = 0
	var carrier_id: int = -1
	var task: SimTask = null
	var tries: int = 0
	## Grid version of the last give-up; a layout change retries.
	var gave_up_version: int = -1
	## Place in the stack on its cell (the view spreads them out).
	var slot: int = 0


## Ingredient stock the goods go into (the session's shared stock).
var stock: Stock
var _world_ref: WeakRef
var _kinds: Dictionary[StringName, int] = {}
var _crates: Array[Crate] = []
var _couriers: Array[CourierAgent] = []
var _next_crate: int = 1


func _init(world: SimWorld, ingredients: Stock, kinds: Dictionary[StringName, int] = {}) -> void:
	_world_ref = weakref(world) if world != null else null
	stock = ingredients
	_kinds = kinds.duplicate()
	if world != null:
		# Method callables and a weak world reference: no world/dock cycle.
		world.board.task_failed.connect(_on_task_failed)
		world.board.task_dropped.connect(_on_task_dropped)


## A delivery due now during service. False (nothing changes) when the shop
## is not open or no route reaches it; the caller then stocks the goods at once.
func arrive(lines: Array[Dictionary]) -> bool:
	var world: SimWorld = _world()
	if world == null or stock == null or lines.is_empty() \
			or world.clock.phase not in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		return false
	var route: Dictionary = WallRules.delivery_route(world.grid, _any_storage_cell(world))
	if route.is_empty():
		return false
	var by_kind: Dictionary[int, Array] = {}
	for line: Dictionary in lines:
		var id: StringName = StringName(line.get("id", &""))
		var qty: int = int(line.get("qty", 0))
		if id.is_empty() or qty <= 0:
			continue
		var kind: int = int(_kinds.get(id, StorageSpace.DRY))
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append({"id": id, "qty": qty})
	if by_kind.is_empty():
		return false
	var door: Vector2i = route["door"]
	var cells: Array[Vector2i] = []
	cells.assign(route["approach"])
	cells.append(door)
	if route["drop"] != door:
		cells.append(route["drop"])
	var courier: CourierAgent = CourierAgent.new(cells, by_kind.size())
	world.add_agent(courier)
	_couriers.append(courier)
	for kind: int in KINDS:
		if not by_kind.has(kind):
			continue
		var crate: Crate = Crate.new()
		crate.id = _next_crate
		_next_crate += 1
		crate.kind = kind
		crate.lines.assign(by_kind[kind])
		crate.cell = courier.drop_cell()
		crate.courier_id = courier.id
		_crates.append(crate)
	world.log_event("A delivery is on its way in")
	return true


## Once per tick after the world: crates the delivery person set down become
## work, carried crates follow their carrier, and finished visits end.
func advance() -> void:
	var world: SimWorld = _world()
	if world == null:
		return
	for courier: CourierAgent in _couriers.duplicate():
		if courier.dropped:
			for crate: Crate in _crates:
				if crate.state == CrateState.ON_THE_WAY and crate.courier_id == courier.id:
					crate.cell = courier.drop_cell()
					crate.slot = _next_slot(crate.cell)
					crate.state = CrateState.WAITING
		if courier.state == CourierAgent.State.GONE:
			world.remove_agent(courier)
			_couriers.erase(courier)
	for crate: Crate in _crates:
		if crate.state == CrateState.CARRIED:
			var carrier: SimAgent = world.agent(crate.carrier_id)
			if carrier != null:
				crate.cell = carrier.cell
		elif crate.state == CrateState.WAITING and crate.task == null:
			if crate.tries >= MAX_TRIES and crate.gave_up_version == world.grid.version:
				continue
			if crate.tries >= MAX_TRIES:
				crate.tries = 0
			_post(world, crate)


## Stocks everything not yet put away, ends every visit and withdraws the
## carrying work. Returns what was stored. Closing and each morning call it.
func store_all() -> Array[Dictionary]:
	var world: SimWorld = _world()
	var lines: Array[Dictionary] = []
	for crate: Crate in _crates.duplicate():
		_crates.erase(crate)
		if crate.task != null and world != null:
			var task: SimTask = crate.task
			crate.task = null
			task.payload["carrying"] = false
			world.board.cancel(task, &"stored_at_closing")
		lines.append_array(crate.lines)
	for courier: CourierAgent in _couriers:
		if world != null and world.agents.has(courier):
			world.remove_agent(courier)
	_couriers.clear()
	if not lines.is_empty():
		_stock(lines)
		if world != null:
			world.log_event("Stored the delivery that was still waiting")
	return lines


## Units waiting to be put away by ingredient id (paid for, space reserved).
func pending_by_id() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for crate: Crate in _crates:
		for line: Dictionary in crate.lines:
			out[line["id"]] = int(out.get(line["id"], 0)) + int(line["qty"])
	return out


func is_idle() -> bool:
	return _crates.is_empty() and _couriers.is_empty()


## Detached view of the crates: {id, kind, cell, state, slot, carrier_id}.
func crates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crate: Crate in _crates:
		out.append({"id": crate.id, "kind": crate.kind, "cell": crate.cell, "state": crate.state,
			"slot": crate.slot, "carrier_id": crate.carrier_id})
	return out


## The put-away task of a crate, or null (tests and the overlay).
func task_for_crate(crate_id: int) -> SimTask:
	for crate: Crate in _crates:
		if crate.id == crate_id:
			return crate.task
	return null


func couriers() -> Array[CourierAgent]:
	return _couriers.duplicate()


func _post(world: SimWorld, crate: Crate) -> void:
	var target: Dictionary = _storage_for(world, crate)
	if target.is_empty():
		crate.tries = MAX_TRIES
		crate.gave_up_version = world.grid.version
		return
	var placed: PlacedItem = target["item"]
	var definition: ItemDef = placed.def as ItemDef
	var place: String = definition.display_name.to_lower() if definition != null else "storage"
	var task: SimTask = SimTask.new(TASK_KIND, &"any", "Put a delivery away")
	# As urgent as washing: a mid-day order is usually restocking something.
	task.priority = 1
	task.payload = {"crate": crate.id, "carrying": false, "item": placed.id}
	task.steps.append(TaskStep.go_to_cell(crate.cell, "walking to the delivery"))
	task.steps.append(TaskStep.work(PICK_UP_TICKS, "picking up a crate", _on_picked_up))
	# To the storage's work spot without reserving it: a cook fetching from the
	# same fridge never waits for a crate (agents don't block each other).
	task.steps.append(TaskStep.go_to_cell(target["cell"], "carrying it to the %s" % place))
	task.steps.append(TaskStep.work(PUT_AWAY_TICKS, "putting it away", _on_put_away))
	crate.task = task
	world.board.post(task, world.now)


## The nearest reachable storage of the crate's kind (placement order breaks
## ties), else the nearest reachable storage of any kind: {item, cell} with
## the work cell walked to, or {} when none is reachable.
func _storage_for(world: SimWorld, crate: Crate) -> Dictionary:
	for same_kind: bool in [true, false]:
		var best: Dictionary = {}
		var best_cost: float = INF
		for placed: PlacedItem in world.grid.items():
			var definition: ItemDef = placed.def as ItemDef
			if definition == null or placed.removed or definition.storage_units <= 0:
				continue
			if same_kind and int(definition.storage_kind) != crate.kind:
				continue
			var goals: Array[Vector2i] = []
			for cell: Vector2i in placed.work_cells:
				if world.grid.is_walkable(cell):
					goals.append(cell)
			var path: Array[Vector2i] = world.grid.find_path_to_any(crate.cell, goals)
			if path.is_empty():
				continue
			var cost: float = GridMath.path_cost(path)
			if cost < best_cost:
				best = {"item": placed, "cell": path.back()}
				best_cost = cost
		if not best.is_empty():
			return best
	return {}


## A walkable work cell of some storage item, so the delivery route chosen can
## reach the stores, or NO_CELL when the shop has none.
func _any_storage_cell(world: SimWorld) -> Vector2i:
	for placed: PlacedItem in world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or placed.removed or definition.storage_units <= 0:
			continue
		for cell: Vector2i in placed.work_cells:
			if world.grid.is_walkable(cell):
				return cell
	return SimGrid.NO_CELL


func _next_slot(cell: Vector2i) -> int:
	var taken: Dictionary[int, bool] = {}
	for crate: Crate in _crates:
		if crate.state == CrateState.WAITING and crate.cell == cell:
			taken[crate.slot] = true
	var slot: int = 0
	while taken.has(slot):
		slot += 1
	return slot


func _crate_for_task(task: SimTask) -> Crate:
	if task == null or task.kind != TASK_KIND:
		return null
	var crate_id: int = int(task.payload.get("crate", 0))
	for crate: Crate in _crates:
		if crate.id == crate_id and crate.task == task:
			return crate
	return null


## Work step: the crate goes from the floor into the carrier's hands. Safe to
## run again after a dropped task (the crate is back on the floor by then).
func _on_picked_up(agent: SimAgent) -> bool:
	var staff: StaffAgent = agent as StaffAgent
	var crate: Crate = _crate_for_task(staff.task if staff != null else null)
	if crate == null or crate.state != CrateState.WAITING:
		return false
	crate.state = CrateState.CARRIED
	crate.carrier_id = agent.id
	crate.cell = agent.cell
	staff.task.payload["carrying"] = true
	return true


## Work step at the storage: the goods become stock.
func _on_put_away(agent: SimAgent) -> bool:
	var staff: StaffAgent = agent as StaffAgent
	var crate: Crate = _crate_for_task(staff.task if staff != null else null)
	if crate == null or crate.state != CrateState.CARRIED or crate.carrier_id != agent.id:
		return false
	# Storage sold while it was carried over: set it down, find another.
	var world: SimWorld = _world()
	var placed: PlacedItem = world.grid.item(int(staff.task.payload.get("item", 0))) if world != null else null
	if placed == null or placed.removed:
		return false
	_crates.erase(crate)
	crate.task = null
	staff.task.payload["carrying"] = false
	_stock(crate.lines)
	return true


## A carrier gave the crate back (timeout, stuck, let go): it goes down where
## they stood and the task starts again from there.
func _on_task_dropped(task: SimTask, agent_id: int, _reason: StringName) -> void:
	var crate: Crate = _crate_for_task(task)
	if crate == null:
		return
	_put_down(crate, agent_id)
	if not task.steps.is_empty() and task.steps[0].kind == TaskStep.Kind.GO_TO_CELL:
		task.steps[0].cell = crate.cell


func _on_task_failed(task: SimTask, _reason: StringName) -> void:
	var crate: Crate = _crate_for_task(task)
	if crate == null:
		return
	_put_down(crate, crate.carrier_id)
	crate.task = null
	crate.tries += 1
	var world: SimWorld = _world()
	if crate.tries >= MAX_TRIES and world != null:
		crate.gave_up_version = world.grid.version


func _put_down(crate: Crate, agent_id: int) -> void:
	if crate.task != null:
		crate.task.payload["carrying"] = false
	if crate.state != CrateState.CARRIED:
		return
	var world: SimWorld = _world()
	var carrier: SimAgent = world.agent(agent_id) if world != null else null
	if carrier != null and world.grid.is_walkable(carrier.cell):
		crate.cell = carrier.cell
	crate.carrier_id = -1
	crate.slot = _next_slot(crate.cell)
	crate.state = CrateState.WAITING


func _stock(lines: Array[Dictionary]) -> void:
	var world: SimWorld = _world()
	var day: int = world.clock.day if world != null else 1
	var merged: Array[Dictionary] = []
	for line: Dictionary in lines:
		stock.add(StringName(line["id"]), int(line["qty"]), day)
		merged.append({"id": StringName(line["id"]), "qty": int(line["qty"])})
	stored.emit(merged)


func _world() -> SimWorld:
	return _world_ref.get_ref() as SimWorld if _world_ref != null else null
