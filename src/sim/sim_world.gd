class_name SimWorld
extends RefCounted
## One restaurant's simulation: clock, grid, task board and agents, advanced
## one fixed tick at a time. No nodes, so it runs headless in tests and in the
## background for other sites. The world view only reads it.

const LOG_LIMIT: int = 200
const MOVEMENT_TUNING: MovementTuning = preload("res://data/balance/movement.tres")

## World ticks since creation (advances every tick, unlike clock.tick which
## only counts while open).
var now: int = 0
var clock: SimClock
var grid: SimGrid
## Daily forecast; selection belongs to the existing game morning boundary.
var weather: WeatherState = WeatherState.new()
var board: TaskBoard = TaskBoard.new()
## Agents in id order.
var agents: Array[SimAgent] = []
var movement: MovementCoordinator = MovementCoordinator.new()
## The restaurant owns Kitchen; traffic only holds a weak read-only query seam.
var _kitchen: WeakRef
var movement_tuning: MovementTuning = MOVEMENT_TUNING.duplicate(true) as MovementTuning
var _pending_agents: Array[SimAgent] = []
## Recent human-readable events (newest last), for the debug overlay.
var event_log: PackedStringArray = []

var _next_agent_id: int = 1
var _open_cache: Array[SimTask] = []


func _init(world_grid: SimGrid, world_clock: SimClock = null) -> void:
	grid = world_grid
	clock = world_clock if world_clock != null else SimClock.new()
	grid.cells_changed.connect(_on_cells_changed)
	grid.item_removed.connect(_on_item_removed)
	# Method callables, not lambdas: a lambda using `self` would keep the world
	# alive through its own board (a reference cycle that leaks).
	board.task_failed.connect(_on_task_failed)


## Adds an agent, assigns its id and returns it.
func add_agent(agent: SimAgent) -> SimAgent:
	if agents.has(agent) or _pending_agents.has(agent):
		return agent
	agent.id = _next_agent_id
	_next_agent_id += 1
	agent.last_progress_tick = now
	agent.bind_movement(self)
	var earlier_waiting: bool = false
	for pending: SimAgent in _pending_agents:
		if pending.cell == agent.cell:
			earlier_waiting = true
			break
	if not earlier_waiting and movement.register_agent(self, agent):
		agents.append(agent)
	else:
		_pending_agents.append(agent)
	_sync_pending_movement()
	return agent


## Removes an agent; it gives back its task and reserved cells first.
func remove_agent(agent: SimAgent) -> void:
	agent.on_removed(self)
	movement.release_actor_seats(self, agent.id)
	agents.erase(agent)
	_pending_agents.erase(agent)
	movement.unregister_agent(agent.id)
	agent.movement_admitted = false
	agent.clear_path()
	_sync_pending_movement()


func pending_agents() -> Array[SimAgent]:
	return _pending_agents.duplicate()


func pending_agent(agent_id: int) -> SimAgent:
	for agent: SimAgent in _pending_agents:
		if agent.id == agent_id:
			return agent
	return null


func all_agents() -> Array[SimAgent]:
	var result: Array[SimAgent] = agents.duplicate()
	result.append_array(_pending_agents)
	result.sort_custom(_agent_id_before)
	return result


func _agent_id_before(first: SimAgent, second: SimAgent) -> bool:
	return first.id < second.id


func reset_agent_position(agent: SimAgent, requested: Vector2i) -> bool:
	if agents.has(agent) and clock.phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		return false
	agents.erase(agent)
	_pending_agents.erase(agent)
	var admitted: bool = movement.reset_agent(self, agent, requested)
	if admitted:
		agents.append(agent)
		agents.sort_custom(_agent_id_before)
	else:
		_pending_agents.append(agent)
		_pending_agents.sort_custom(_agent_id_before)
	_sync_pending_movement()
	return admitted


func _sync_pending_movement() -> void:
	var ids: Array[int] = []
	for agent: SimAgent in _pending_agents:
		ids.append(agent.id)
	movement.set_pending(ids)


func _admit_waiting() -> void:
	for agent: SimAgent in _pending_agents.duplicate():
		if movement.register_agent(self, agent):
			_pending_agents.erase(agent)
			agents.append(agent)
	agents.sort_custom(_agent_id_before)
	_sync_pending_movement()


func agent(agent_id: int) -> SimAgent:
	for a in agents:
		if a.id == agent_id:
			return a
	return null


## Runs one tick: the clock, the board backstops, then every agent in id order.
func advance() -> void:
	now += 1
	clock.advance()
	movement.begin_tick(self)
	_admit_waiting()
	_heal_board()
	_open_cache = board.open_tasks()
	for a: SimAgent in agents:
		a.begin_movement_trace(now)
	for a: SimAgent in agents.duplicate():
		if movement.advance_squeeze(self, a) or movement.advance_stop(self, a) or movement.advance_yield(self, a):
			if a is StaffAgent:
				(a as StaffAgent).maintain_movement_pause(self)
			elif a is CustomerAgent:
				(a as CustomerAgent).maintain_movement_pause(self)
		else:
			a.tick(self)
	for a: SimAgent in agents:
		a.end_movement_trace()
	_open_cache = []


## Open tasks as of the start of this tick, built once per tick so idle
## agents don't each sort the board. Claimed-this-tick tasks are still in the
## list: check task.state before using one.
func open_tasks_this_tick() -> Array[SimTask]:
	return _open_cache if not _open_cache.is_empty() else board.open_tasks()


## The board heals itself instead of trusting every claimant:
## - a claimed task whose claimant is gone, or that is past its timeout plus a
##   grace tick, is dropped;
## - an open task aimed at an item that no longer exists fails at once.
func _heal_board() -> void:
	for t in board.claimed_tasks():
		var holder := agent(t.claimed_by)
		if holder == null:
			board.drop(t, &"claimant_gone")
		elif now - t.claimed_tick > t.timeout_ticks + 1:
			board.drop(t, &"timeout")
	for t in board.open_tasks():
		for s in t.steps:
			if s.kind == TaskStep.Kind.GO_TO_ITEM and grid.item(s.item_id) == null:
				board.cancel(t, &"target_gone")
				break


func log_event(text: String) -> void:
	event_log.append("[%d] %s" % [now, text])
	if event_log.size() > LOG_LIMIT:
		event_log = event_log.slice(event_log.size() - LOG_LIMIT)


func _on_task_failed(t: SimTask, reason: StringName) -> void:
	# A READY delivery folded into a tray trip is successful handoff, not a
	# failed job. Keep the board cancellation for its claimant/ownership cleanup.
	if t.kind == &"deliver" and reason == &"batched":
		return
	log_event("Task failed: %s (%s)" % [t.label, reason])


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	for a in agents:
		if a.path_crosses(cells):
			a.needs_repath = true


## Tasks aimed at a removed item can never finish: fail them now so their
## posters can react, instead of leaving them on the board forever.
func _on_item_removed(item: PlacedItem) -> void:
	var doomed: Array[SimTask] = board.open_tasks()
	doomed.append_array(board.claimed_tasks())
	for t in doomed:
		for s in t.steps:
			if s.kind == TaskStep.Kind.GO_TO_ITEM and s.item_id == item.id:
				board.cancel(t, &"target_gone")
				break


func bind_kitchen(kitchen: Kitchen) -> void:
	_kitchen = weakref(kitchen)


## Guest behind a ticket, or 0 when the ticket or kitchen is gone (#307).
func order_customer_id(order_id: int) -> int:
	var kitchen: Kitchen = _kitchen.get_ref() as Kitchen if _kitchen != null else null
	return 0 if kitchen == null else kitchen.order_customer_id(order_id)


func carries_prepared_drink(staff: StaffAgent) -> bool:
	var kitchen: Kitchen = _kitchen.get_ref() as Kitchen if _kitchen != null else null
	return kitchen != null and kitchen.carries_prepared_drink(staff)
