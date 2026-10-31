class_name MovementCoordinator
extends RefCounted
## Cell and swept-edge ownership, separate from task/station reservations.
## IDs and value maps only: no back reference to a world or its agents.

var _occupied: Dictionary[Vector2i, int] = {}
var _next: Dictionary[Vector2i, int] = {}
var _edges: Dictionary[int, Dictionary] = {}
## Keep all crossed cells until the next tick: a later, faster actor must
## not catch an earlier actor inside this tick's continuous drawn interval.
var _swept: Dictionary[Vector2i, int] = {}
var _blocked: Dictionary[int, int] = {}
var _resume: Dictionary[int, Vector2i] = {}
var _pending: Array[int] = []
var _stopping: Dictionary[int, bool] = {}
var _after_stop: Dictionary[int, Vector2i] = {}
var _seat_releases: Array[Dictionary] = []


func snapshot() -> Dictionary:
	var edges: Array[Dictionary] = []
	var ids: Array[int] = []
	ids.assign(_edges.keys())
	ids.sort()
	for id: int in ids:
		edges.append(_edges[id].duplicate(true))
	var claims: Dictionary[Vector2i, int] = _swept.duplicate()
	claims.merge(_next, true)
	var stopping: Array[int] = []
	stopping.assign(_stopping.keys())
	stopping.sort()
	return {"occupied": _occupied.duplicate(), "next": claims,
		"edges": edges, "pending": _pending.duplicate(), "stopping": stopping}


func set_pending(ids: Array[int]) -> void:
	_pending = ids.duplicate()


func pending_snapshot(ids: Array[int]) -> Dictionary:
	var result: Dictionary = snapshot()
	result["pending"] = ids.duplicate()
	return result


func register_agent(world: SimWorld, agent: SimAgent, cause: String = "admission") -> bool:
	if agent.movement_admitted:
		return world.agents.has(agent) and _occupied.get(agent.cell, -1) == agent.id
	var requested: Vector2i = agent.cell
	if can_enter(world, agent, requested):
		_occupied[requested] = agent.id
		agent.movement_admitted = true
		agent.reset_movement_trace(world.now, cause)
		return true
	if agent is StaffAgent:
		for cell: Vector2i in _nearby(world, agent, requested, world.movement_tuning.admission_search_radius):
			if can_enter(world, agent, cell):
				agent.cell = cell
				_occupied[cell] = agent.id
				agent.movement_admitted = true
				agent.reset_movement_trace(world.now, cause)
				return true
	return false


func unregister_agent(agent_id: int) -> void:
	_release_edge(agent_id)
	for cell: Vector2i in _occupied.keys():
		if _occupied[cell] == agent_id:
			_occupied.erase(cell)
	_blocked.erase(agent_id)
	_resume.erase(agent_id)
	_stopping.erase(agent_id)
	_after_stop.erase(agent_id)
	for cell: Vector2i in _swept.keys():
		if _swept[cell] == agent_id:
			_swept.erase(cell)


func reset_agent(world: SimWorld, agent: SimAgent, requested: Vector2i) -> bool:
	if agent.movement_admitted and world.clock.phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		return false
	if world.agents.has(agent) or world.pending_agents().has(agent):
		return world.reset_agent_position(agent, requested)
	release_actor_seats(world, agent.id)
	unregister_agent(agent.id)
	agent.movement_admitted = false
	agent.clear_path()
	agent.cell = requested
	return register_agent(world, agent, "reset")


func begin_tick(world: SimWorld) -> void:
	_swept.clear()
	_release_vacated_seats(world)
	# External scenario/reset callers can change cells directly. Reconcile their
	# admission before they tick, rather than retaining stale reservations.
	for agent: SimAgent in world.agents.duplicate():
		if _occupied.get(agent.cell, -1) != agent.id:
			var old: Vector2i = SimGrid.NO_CELL
			for cell: Vector2i in _occupied:
				if _occupied[cell] == agent.id:
					old = cell
					break
			if world.clock.phase in [SimClock.Phase.MORNING, SimClock.Phase.CLOSED] \
					and can_enter(world, agent, agent.cell):
				world.reset_agent_position(agent, agent.cell)
			elif old != SimGrid.NO_CELL:
				# Reject an external conflicting teleport; an existing actor is
				# never hidden in admission to conceal a duplicate active cell.
				agent.cell = old
				agent.clear_path()
	for agent: SimAgent in world.agents:
		if agent.move_progress == 0.0 and _edges.has(agent.id):
			_release_edge(agent.id)
		if _resume.has(agent.id) and agent.has_arrived() and not _stopping.has(agent.id):
			var goal: Vector2i = _resume[agent.id]
			var path: Array[Vector2i] = route(world, agent, agent.cell, goal, false)
			if not path.is_empty():
				_resume.erase(agent.id)
				agent.install_movement_route(path)
			elif not agent is CourierAgent:
				# A removed/blocked original target must return to the task's
				# ordinary unreachable recovery, never strand an actor in yield.
				_resume.erase(agent.id)
				agent.clear_path()
				agent.needs_repath = true


func priority(_world: SimWorld, agent: SimAgent) -> int:
	if agent is StaffAgent:
		return 3 if (agent as StaffAgent).carries_food() else 2
	return 2 if agent is CourierAgent else 1


func _before(world: SimWorld, first: SimAgent, second: SimAgent) -> bool:
	var a: int = priority(world, first)
	var b: int = priority(world, second)
	return a > b or (a == b and first.id < second.id)


func can_enter(world: SimWorld, agent: SimAgent, cell: Vector2i) -> bool:
	return _legal_cell(world, agent, cell) and _occupied.get(cell, agent.id) == agent.id \
		and _next.get(cell, agent.id) == agent.id and _swept.get(cell, agent.id) == agent.id


func _legal_cell(world: SimWorld, agent: SimAgent, cell: Vector2i) -> bool:
	if agent is CourierAgent:
		var courier: CourierAgent = agent as CourierAgent
		if courier.route.has(cell):
			if not world.grid.in_bounds(cell) or world.grid.terrain(cell) == SimGrid.Terrain.OUTSIDE:
				return true
			if not world.grid.is_walkable(cell):
				return false
			# A real walkable indoor route cell still has the same seat and
			# bench ownership rules as every other person's cell below.
		else:
			# The planned alley is outside the shop. One-cell-wide pavement
			# beside it supplies a real yielding pocket, never an indoor shortcut.
			if world.grid.in_bounds(cell) and world.grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
				return false
			for route_cell: Vector2i in courier.route:
				if absi(route_cell.x - cell.x) + absi(route_cell.y - cell.y) <= 1:
					return true
			return false
	elif not world.grid.is_walkable(cell):
		return false
	if agent is CustomerAgent and not world.grid.is_guest_walkable(cell):
		return false
	var seat: bool = false
	var own: bool = false
	for item: PlacedItem in world.grid.items():
		if not item.seat_cells.has(cell):
			continue
		seat = true
		var holder: int = item.reserved_by(cell)
		if holder != -1 and holder != agent.id:
			return false
		own = own or holder == agent.id
	return not seat or own


## No person may use an unassigned dining/bench seat as an aisle.
func standing_cell(world: SimWorld, cell: Vector2i) -> bool:
	for item: PlacedItem in world.grid.items():
		if item.seat_cells.has(cell):
			return false
	return world.grid.is_walkable(cell)


func route(world: SimWorld, agent: SimAgent, from: Vector2i, to: Vector2i,
		avoid_people: bool = true) -> Array[Vector2i]:
	if agent is CourierAgent:
		return _courier_route(world, agent, from, to)
	var blocked: Dictionary[Vector2i, bool] = {}
	for item: PlacedItem in world.grid.items():
		for cell: Vector2i in item.seat_cells:
			if cell != from and not _legal_cell(world, agent, cell):
				blocked[cell] = true
	if avoid_people:
		for cell: Vector2i in _occupied:
			if _occupied[cell] != agent.id and cell != to:
				blocked[cell] = true
		for cell: Vector2i in _next:
			if _next[cell] != agent.id and cell != to:
				blocked[cell] = true
		for cell: Vector2i in _swept:
			if _swept[cell] != agent.id and cell != to:
				blocked[cell] = true
	return world.grid.find_path_avoiding(from, to, blocked, agent is CustomerAgent)


func try_step(world: SimWorld, agent: SimAgent, next: Vector2i) -> bool:
	if not agent.movement_admitted:
		return false
	if _edges.has(agent.id):
		var existing: Dictionary = _edges[agent.id]
		if existing["from"] == agent.cell and existing["to"] == next:
			return true
		_release_edge(agent.id)
	var delta: Vector2i = next - agent.cell
	var legal: bool = maxi(absi(delta.x), absi(delta.y)) == 1
	if not agent is CourierAgent:
		legal = legal and world.grid.is_walkable(agent.cell) \
			and world.grid.step_open(agent.cell, next)
		if agent is CustomerAgent:
			legal = legal and world.grid.guest_step_ok(agent.cell, next)
	elif world.grid.is_walkable(agent.cell) and world.grid.is_walkable(next):
		legal = legal and world.grid.step_open(agent.cell, next)
	var cells: Array[Vector2i] = [next]
	if delta.x != 0 and delta.y != 0:
		cells.append(agent.cell + Vector2i(delta.x, 0))
		cells.append(agent.cell + Vector2i(0, delta.y))
	for cell: Vector2i in cells:
		legal = legal and can_enter(world, agent, cell)
	# Arbitrate simultaneous intentions by physical carrying priority, before
	# a lower ID can claim a cell merely because its tick runs first.
	if legal:
		for other: SimAgent in world.agents:
			if other == agent or other.has_arrived() or other.move_progress > 0.0:
				continue
			if other.next_cell() == next and _before(world, other, agent):
				legal = false
				break
	if not legal:
		_wait(world, agent, next)
		return false
	for cell: Vector2i in cells:
		_next[cell] = agent.id
	_edges[agent.id] = {"id": agent.id, "from": agent.cell, "to": next}
	_blocked.erase(agent.id)
	return true


func complete_step(world: SimWorld, agent: SimAgent, from: Vector2i, to: Vector2i) -> void:
	if _occupied.get(from, -1) == agent.id:
		_occupied.erase(from)
	_occupied[to] = agent.id
	_swept[from] = agent.id
	_swept[to] = agent.id
	var delta: Vector2i = to - from
	if delta.x != 0 and delta.y != 0:
		_swept[from + Vector2i(delta.x, 0)] = agent.id
		_swept[from + Vector2i(0, delta.y)] = agent.id
	_release_edge(agent.id)
	_blocked.erase(agent.id)
	_release_vacated_seats(world)


## A released booking still physically holds its seat until the person has
## walked off it (or has been removed). Never turn it into a public aisle.
func defer_seat_release(world: SimWorld, item_id: int, cell: Vector2i, actor_id: int) -> void:
	var item: PlacedItem = world.grid.item(item_id)
	if item == null or item.reserved_by(cell) != actor_id:
		return
	var actor: SimAgent = world.agent(actor_id)
	if actor == null or (actor.cell != cell and not (actor.move_progress > 0.0 and actor.next_cell() == cell)):
		item.release(cell, actor_id)
		return
	for row: Dictionary in _seat_releases:
		if row["item"] == item_id and row["cell"] == cell and row["actor"] == actor_id:
			return
	_seat_releases.append({"item": item_id, "cell": cell, "actor": actor_id})


func release_actor_seats(world: SimWorld, actor_id: int) -> void:
	for row: Dictionary in _seat_releases.duplicate():
		if row["actor"] != actor_id:
			continue
		var item: PlacedItem = world.grid.item(row["item"])
		if item != null:
			item.release(row["cell"], actor_id)
		_seat_releases.erase(row)


func _release_vacated_seats(world: SimWorld) -> void:
	for row: Dictionary in _seat_releases.duplicate():
		var actor: SimAgent = world.agent(row["actor"])
		var cell: Vector2i = row["cell"]
		if actor != null and (actor.cell == cell or (actor.move_progress > 0.0 and actor.next_cell() == cell)):
			# An idle busser must step off the just-cleaned seat rather than
			# hold it indefinitely while waiting for another job.
			if actor.has_arrived() and not _stopping.has(actor.id) and not _resume.has(actor.id):
				for next: Vector2i in world.grid.walkable_neighbours(cell):
					if standing_cell(world, next) and can_enter(world, actor, next):
						actor.install_movement_route([cell, next] as Array[Vector2i])
						stop_motion(actor.id)
						break
			continue
		var item: PlacedItem = world.grid.item(row["item"])
		if item != null:
			item.release(cell, row["actor"])
		_seat_releases.erase(row)


func _release_edge(id: int) -> void:
	_edges.erase(id)
	for cell: Vector2i in _next.keys():
		if _next[cell] == id:
			_next.erase(cell)


func release_motion(id: int) -> void:
	_release_edge(id)


## Cancellation changes intent, not the physical position halfway along an
## already reserved edge. Finish that edge without running actor/task logic.
func stop_motion(id: int, next_goal: Vector2i = SimGrid.NO_CELL) -> void:
	_stopping[id] = true
	_resume.erase(id)
	if next_goal == SimGrid.NO_CELL:
		_after_stop.erase(id)
	else:
		_after_stop[id] = next_goal


func is_stopping(id: int) -> bool:
	return _stopping.has(id)


func advance_stop(world: SimWorld, agent: SimAgent) -> bool:
	if not _stopping.has(agent.id):
		return false
	if not agent.has_arrived():
		if agent is CourierAgent:
			(agent as CourierAgent)._walk(world)
		else:
			agent.step_move(world)
	if agent.has_arrived():
		_stopping.erase(agent.id)
		var goal: Vector2i = _after_stop.get(agent.id, SimGrid.NO_CELL)
		_after_stop.erase(agent.id)
		agent.clear_path()
		if goal != SimGrid.NO_CELL:
			agent.set_destination(world.grid, goal)
	return true


func _wait(world: SimWorld, agent: SimAgent, next: Vector2i) -> void:
	var waits: int = _blocked.get(agent.id, 0) + 1
	_blocked[agent.id] = waits
	if agent.move_progress > 0.0:
		return
	var holder: SimAgent = world.agent(_occupied.get(next, _next.get(next, -1)))
	if holder != null and holder.move_progress == 0.0:
		var yielding: SimAgent = holder if _before(world, agent, holder) else agent
		if waits >= world.movement_tuning.yield_after_ticks:
			_yield(world, yielding, agent if yielding == holder else holder)
	if waits % world.movement_tuning.repath_after_ticks == 0 and not _resume.has(agent.id) \
			and not agent is CourierAgent:
		var alternate: Array[Vector2i] = route(world, agent, agent.cell, agent.destination(), true)
		if not alternate.is_empty() and alternate.size() > 1 and alternate[1] != next:
			agent.install_movement_route(alternate)


func _yield(world: SimWorld, yielding: SimAgent, winner: SimAgent) -> void:
	if _resume.has(yielding.id) or _stopping.has(yielding.id) or yielding.move_progress > 0.0:
		return
	if yielding is CustomerAgent:
		var guest: CustomerAgent = yielding as CustomerAgent
		if guest.state >= CustomerAgent.State.ORDERING and guest.state <= CustomerAgent.State.PAYING:
			return
	var original: Vector2i = yielding.destination()
	if original == SimGrid.NO_CELL:
		original = yielding.cell
	for cell: Vector2i in _nearby(world, yielding, yielding.cell, world.movement_tuning.yield_search_radius):
		if cell == winner.cell or cell == winner.next_cell() or not can_enter(world, yielding, cell):
			continue
		var path: Array[Vector2i] = route(world, yielding, yielding.cell, cell, true)
		if path.size() < 2 or path.slice(1).has(winner.cell) or path.slice(1).has(winner.next_cell()):
			continue
		_resume[yielding.id] = original
		yielding.install_movement_route(path)
		return


func advance_yield(world: SimWorld, agent: SimAgent) -> bool:
	if not _resume.has(agent.id):
		return false
	if not agent.has_arrived():
		if agent is CourierAgent:
			(agent as CourierAgent)._walk(world)
		else:
			agent.step_move(world)
	return true


func is_yielding(id: int) -> bool:
	return _resume.has(id)


func _courier_route(world: SimWorld, agent: SimAgent, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [from]
	var previous: Dictionary[Vector2i, Vector2i] = {}
	var seen: Dictionary[Vector2i, bool] = {from: true}
	var index: int = 0
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		if current == to:
			var result: Array[Vector2i] = [current]
			while previous.has(current):
				current = previous[current]
				result.push_front(current)
			return result
		for delta: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = current + delta
			if seen.has(next) or not can_enter(world, agent, next):
				continue
			seen[next] = true
			previous[next] = current
			queue.append(next)
	return []


func _nearby(world: SimWorld, agent: SimAgent, start: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# Stable cardinal-first breadth-first order; never cross geometry to yield.
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var index: int = 0
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		var neighbours: Array[Vector2i] = world.grid.walkable_neighbours(current)
		if agent is CourierAgent:
			neighbours = [current + Vector2i.UP, current + Vector2i.RIGHT,
				current + Vector2i.DOWN, current + Vector2i.LEFT]
		for next: Vector2i in neighbours:
			if seen.has(next) or GridMath.octile(start, next) > float(radius) \
					or not _legal_cell(world, agent, next):
				continue
			seen[next] = true
			queue.append(next)
			result.append(next)
	return result
