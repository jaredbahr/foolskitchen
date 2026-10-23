class_name SimWorld
extends RefCounted
## One restaurant's simulation: clock, grid, task board and agents, advanced
## one fixed tick at a time. No nodes, so it runs headless in tests and in the
## background for other sites. The world view only reads it.

const LOG_LIMIT: int = 200

## World ticks since creation (advances every tick, unlike clock.tick which
## only counts while open).
var now: int = 0
var clock: SimClock
var grid: SimGrid
var board: TaskBoard = TaskBoard.new()
## Agents in id order.
var agents: Array[SimAgent] = []
## Recent human-readable events (newest last), for the debug overlay.
var event_log: PackedStringArray = []

var _next_agent_id: int = 1


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
	agent.id = _next_agent_id
	_next_agent_id += 1
	agent.last_progress_tick = now
	agents.append(agent)
	return agent


func remove_agent(agent: SimAgent) -> void:
	agents.erase(agent)


func agent(agent_id: int) -> SimAgent:
	for a in agents:
		if a.id == agent_id:
			return a
	return null


## Runs one tick: the clock, then every agent in id order.
func advance() -> void:
	now += 1
	clock.advance()
	for a: SimAgent in agents.duplicate():
		a.tick(self)


func log_event(text: String) -> void:
	event_log.append("[%d] %s" % [now, text])
	if event_log.size() > LOG_LIMIT:
		event_log = event_log.slice(event_log.size() - LOG_LIMIT)


func _on_task_failed(t: SimTask, reason: StringName) -> void:
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
