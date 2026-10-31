class_name MovementCoordinator
extends RefCounted
## Cell and swept-edge ownership, separate from task/station reservations.
## IDs and value maps only: no back reference to a world or its agents.

enum YieldAttempt { STARTED, IN_PROGRESS_PROTECTED, NO_POCKET }

var _occupied: Dictionary[Vector2i, int] = {}
var _next: Dictionary[Vector2i, int] = {}
var _edges: Dictionary[int, Dictionary] = {}
## Keep all crossed cells until the next tick: a later, faster actor must
## not catch an earlier actor inside this tick's continuous drawn interval.
var _swept: Dictionary[Vector2i, int] = {}
var _blocked: Dictionary[int, int] = {}
var _resume: Dictionary[int, Vector2i] = {}
## Return travel still suppresses productive work, but can yield again if blocked.
var _returning: Dictionary[int, bool] = {}
## A cooperative clearer waits briefly for the boxed actor to use its vacancy.
var _cooperative: Dictionary[int, Dictionary] = {}
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
	var returning: Array[int] = []
	returning.assign(_returning.keys())
	returning.sort()
	var cooperative: Array[Dictionary] = []
	var clearers: Array[int] = []
	clearers.assign(_cooperative.keys())
	clearers.sort()
	for id: int in clearers:
		var row: Dictionary = _cooperative[id].duplicate(true)
		row["id"] = id
		cooperative.append(row)
	return {"occupied": _occupied.duplicate(), "next": claims,
		"edges": edges, "pending": _pending.duplicate(), "stopping": stopping, "returning": returning, "cooperative": cooperative}


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
	_returning.erase(agent_id)
	_cooperative.erase(agent_id)
	for clearer: int in _cooperative.keys():
		if int(_cooperative[clearer]["blocked_id"]) == agent_id:
			_cooperative.erase(clearer)
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
		if _resume.has(agent.id) and agent is StaffAgent:
			var staff: StaffAgent = agent as StaffAgent
			if staff.task != null and (staff.task.state != SimTask.State.CLAIMED or staff.task.claimed_by != staff.id):
				# Withdrawal cancels return intent, not an edge already travelled.
				_resume.erase(agent.id)
				_returning.erase(agent.id)
				_cooperative.erase(agent.id)
				staff.let_go_if_withdrawn(world)
		if agent.move_progress == 0.0 and _edges.has(agent.id):
			_release_edge(agent.id)
		if _resume.has(agent.id) and agent.has_arrived() and not _stopping.has(agent.id):
			var goal: Vector2i = _resume[agent.id]
			if agent.cell == goal:
				if _idle_without_route(world, agent):
					if _cooperative_holding(world, agent):
						continue
					# Retire an idle service goal only at the pocket really reached.
					agent.set_destination(world.grid, agent.cell)
				# A sidestep is not arrival at the actor's productive station.
				_resume.erase(agent.id)
				_returning.erase(agent.id)
				_cooperative.erase(agent.id)
				continue
			if _cooperative_holding(world, agent):
				continue
			if not _returning.has(agent.id) and _idle_without_route(world, agent) \
					and agent.destination() != SimGrid.NO_CELL and goal != agent.destination():
				# A second completed idle pocket supersedes an earlier parking target.
				# Explicit journeys retain their real goal as the resume destination.
				agent.set_destination(world.grid, agent.cell)
				supersede_destination(agent.id)
				continue
			if not _returning.has(agent.id) and _can_queue_in_pocket(world, agent):
				# A door waiter can wait on the ordinary floor it actually reached.
				# Keep that vertex as the real goal so later yields cannot revive
				# the obsolete doorway return. Never cancel a partial/outbound edge.
				agent.set_destination(world.grid, agent.cell)
				continue
			var path: Array[Vector2i] = route(world, agent, agent.cell, goal, false)
			if not path.is_empty():
				# Keep work paused while allowing this returning actor to yield again.
				_returning[agent.id] = true
				agent.install_movement_route(path)
			elif not agent is CourierAgent:
				_resume.erase(agent.id)
				_returning.erase(agent.id)
				_cooperative.erase(agent.id)
				if agent is StaffAgent and (agent as StaffAgent).task != null:
					# WORK does not process needs_repath. Use the actor's existing
					# unreachable drop/cleanup instead of working in the pocket.
					(agent as StaffAgent)._drop(world, &"unreachable")
				else:
					agent.clear_path()
					agent.needs_repath = true


## Only public NEW destinations replace recovery intent. This never releases
## the physical occupied/next/swept claims or a reserved partial edge.
func supersede_destination(id: int) -> void:
	_resume.erase(id)
	_returning.erase(id)
	_cooperative.erase(id)


func _can_queue_in_pocket(world: SimWorld, agent: SimAgent) -> bool:
	if not agent is CustomerAgent or agent.move_progress != 0.0:
		return false
	var guest: CustomerAgent = agent as CustomerAgent
	return guest.state in [CustomerAgent.State.ARRIVING, CustomerAgent.State.QUEUED] \
		and guest.waiting_item_id == 0 and world.grid.terrain(guest.cell) == SimGrid.Terrain.FLOOR \
		and world.grid.room(guest.cell) == SimGrid.Room.DINING and standing_cell(world, guest.cell)


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


## Physical cells swept by one adjacent edge, including diagonal corners.
## Shared by the read-only feasibility query and actual claim installation.
func _step_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [to_cell]
	var delta: Vector2i = to_cell - from_cell
	if delta.x != 0 and delta.y != 0:
		cells.append(from_cell + Vector2i(delta.x, 0))
		cells.append(from_cell + Vector2i(0, delta.y))
	return cells


## An impossible intention cannot veto somebody who can actually move.
## Query geometry/rights/claims only: no arbitration or state changes.
func _edge_feasible(world: SimWorld, agent: SimAgent, next: Vector2i) -> bool:
	if not agent.movement_admitted:
		return false
	var delta: Vector2i = next - agent.cell
	var legal: bool = maxi(absi(delta.x), absi(delta.y)) == 1
	if not agent is CourierAgent:
		legal = legal and world.grid.is_walkable(agent.cell) \
			and world.grid.step_open(agent.cell, next)
		if agent is CustomerAgent:
			legal = legal and world.grid.guest_step_ok(agent.cell, next)
	elif world.grid.is_walkable(agent.cell) and world.grid.is_walkable(next):
		legal = legal and world.grid.step_open(agent.cell, next)
	for cell: Vector2i in _step_cells(agent.cell, next):
		legal = legal and can_enter(world, agent, cell)
	return legal


func try_step(world: SimWorld, agent: SimAgent, next: Vector2i) -> bool:
	if not agent.movement_admitted:
		return false
	if _edges.has(agent.id):
		var existing: Dictionary = _edges[agent.id]
		if existing["from"] == agent.cell and existing["to"] == next:
			return true
		_release_edge(agent.id)
	var legal: bool = _edge_feasible(world, agent, next)
	# Arbitrate simultaneous intentions by physical carrying priority, before
	# a lower ID can claim a cell merely because its tick runs first.
	if legal:
		for other: SimAgent in world.agents:
			if other == agent or other.has_arrived() or other.move_progress > 0.0:
				continue
			if other.next_cell() == next and _before(world, other, agent) \
					and _edge_feasible(world, other, next):
				legal = false
				break
	if not legal:
		_wait(world, agent, next)
		return false
	for cell: Vector2i in _step_cells(agent.cell, next):
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
	_resume.erase(id)
	_returning.erase(id)
	_cooperative.erase(id)


## Cancellation changes intent, not the physical position halfway along an
## already reserved edge. Finish that edge without running actor/task logic.
func stop_motion(id: int, next_goal: Vector2i = SimGrid.NO_CELL) -> void:
	_stopping[id] = true
	_resume.erase(id)
	_returning.erase(id)
	_cooperative.erase(id)
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
	if holder == null:
		for corner: Vector2i in _step_cells(agent.cell, next):
			if corner == next:
				continue
			var corner_holder: SimAgent = world.agent(_occupied.get(corner, _next.get(corner, -1)))
			if corner_holder != null and corner_holder != agent:
				holder = corner_holder
				break
	if holder != null and holder.move_progress == 0.0:
		if waits >= world.movement_tuning.yield_after_ticks \
				and _idle_station_holder(world, agent, holder, next):
			if _yield(world, holder, agent) == YieldAttempt.STARTED:
				# No station lease requires a return to this cleared position.
				_resume[holder.id] = holder.path.back()
				return
		var yielding: SimAgent = holder if _before(world, agent, holder) else agent
		if waits >= world.movement_tuning.yield_after_ticks:
			var winner: SimAgent = agent if yielding == holder else holder
			if _yield(world, yielding, winner) == YieldAttempt.NO_POCKET:
				# A boxed lower-priority actor cannot clear itself. Only then
				# ask the normal winner to make a physical cooperative vacancy.
				var blocked_cell: Vector2i = yielding.cell
				var cleared_cell: Vector2i = winner.cell
				var idle_blocked: bool = _idle_without_route(world, yielding)
				var winner_route: Array[Vector2i] = [winner.cell]
				if idle_blocked:
					winner_route.append_array(winner.path.slice(winner.path_index))
				if _yield(world, winner, yielding) == YieldAttempt.STARTED:
					_cooperative[winner.id] = {"blocked_id": yielding.id, "blocked_cell": blocked_cell,
						"cleared_cell": cleared_cell, "arrival_tick": -1, "hold_until": -1}
					if idle_blocked:
						# Preserve the productive route before the clearer's retreat replaces it.
						_cooperative[winner.id]["winner_route"] = winner_route
	if waits % world.movement_tuning.repath_after_ticks == 0 \
			and (not _resume.has(agent.id) or _returning.has(agent.id)) \
			and not agent is CourierAgent:
		var alternate: Array[Vector2i] = route(world, agent, agent.cell, agent.destination(), true)
		if not alternate.is_empty() and alternate.size() > 1 and alternate[1] != next:
			agent.install_movement_route(alternate)


## An idle or unleased waiting employee can clear incoming leased work.
## Active workers, owners and ordinary route priority retain their policy.
func _idle_station_holder(world: SimWorld, agent: SimAgent, holder: SimAgent, next: Vector2i) -> bool:
	if not agent is StaffAgent or not holder is StaffAgent or holder is OwnerAgent:
		return false
	var worker: StaffAgent = agent as StaffAgent
	var idle: StaffAgent = holder as StaffAgent
	if idle.carries_food() or not idle.has_arrived() or _resume.has(idle.id) \
			or _stopping.has(idle.id) or _edges.has(idle.id):
		return false
	if idle.task != null:
		if idle.task.state != SimTask.State.CLAIMED or idle.task.claimed_by != idle.id \
				or world.board.get_task(idle.task.id) != idle.task or idle.step_index < 0 \
				or idle.step_index >= idle.task.steps.size():
			return false
		var pending: TaskStep = idle.task.steps[idle.step_index]
		if pending.kind != TaskStep.Kind.GO_TO_ITEM or idle._step_started \
				or idle._waiting_for.is_empty() or idle._held_item_id != 0 \
				or idle._held_cell != SimGrid.NO_CELL:
			return false
	if worker.task == null or worker.task.state != SimTask.State.CLAIMED \
			or worker.task.claimed_by != worker.id or worker.step_index < 0 \
			or world.board.get_task(worker.task.id) != worker.task \
			or worker.step_index >= worker.task.steps.size() \
			or worker.destination() != next or holder.cell != next:
		return false
	var step: TaskStep = worker.task.steps[worker.step_index]
	if step.kind != TaskStep.Kind.GO_TO_ITEM:
		return false
	var item: PlacedItem = world.grid.item(step.item_id)
	return item != null and item.work_cells.has(next) and item.reserved_by(next) == worker.id


func _idle_without_route(_world: SimWorld, agent: SimAgent) -> bool:
	if not agent is StaffAgent or agent is OwnerAgent or not agent.has_arrived() \
			or agent.move_progress != 0.0 or _stopping.has(agent.id) or _edges.has(agent.id):
		return false
	var staff: StaffAgent = agent as StaffAgent
	return staff.task == null and not staff.carries_food() and staff._held_item_id == 0 \
		and staff._held_cell == SimGrid.NO_CELL


func _yield(world: SimWorld, yielding: SimAgent, winner: SimAgent, avoid_parking: Array[Vector2i] = []) -> YieldAttempt:
	var fresh_outbound: bool = _resume.has(yielding.id) and not _returning.has(yielding.id) \
			and int(_blocked.get(yielding.id, 0)) < world.movement_tuning.yield_after_ticks
	if fresh_outbound or _stopping.has(yielding.id) or _edges.has(yielding.id) \
			or yielding.move_progress > 0.0:
		return YieldAttempt.IN_PROGRESS_PROTECTED
	if yielding is CustomerAgent:
		var guest: CustomerAgent = yielding as CustomerAgent
		if guest.state >= CustomerAgent.State.ORDERING and guest.state <= CustomerAgent.State.PAYING:
			return YieldAttempt.IN_PROGRESS_PROTECTED
	var original: Vector2i = _resume.get(yielding.id, yielding.destination())
	if original == SimGrid.NO_CELL:
		original = yielding.cell
	var parking: bool = _idle_without_route(world, yielding)
	var winner_route: Array[Vector2i] = []
	if parking:
		winner_route.assign(winner.path.slice(winner.path_index))
		winner_route.append(winner.cell)
		winner_route.append_array(avoid_parking)
	for cell: Vector2i in _nearby(world, yielding, yielding.cell, world.movement_tuning.yield_search_radius):
		if cell == winner.cell or cell == winner.next_cell() or not can_enter(world, yielding, cell):
			continue
		if parking and winner_route.has(cell):
			continue
		var path: Array[Vector2i] = route(world, yielding, yielding.cell, cell, true)
		if path.size() < 2 or path.slice(1).has(winner.cell) or path.slice(1).has(winner.next_cell()):
			continue
		_resume[yielding.id] = cell if parking else original
		_returning.erase(yielding.id)
		_cooperative.erase(yielding.id)
		_blocked.erase(yielding.id)
		yielding.install_movement_route(path)
		return YieldAttempt.STARTED

	return YieldAttempt.NO_POCKET


## Called only after the clearer physically reaches its temporary pocket.
## Route changes alone are not evidence that the boxed actor has progressed.
func _cooperative_holding(world: SimWorld, agent: SimAgent) -> bool:
	if not _cooperative.has(agent.id):
		return false
	var row: Dictionary = _cooperative[agent.id]
	var blocked: SimAgent = world.agent(int(row["blocked_id"]))
	var progressed: bool = blocked == null
	if blocked != null:
		progressed = blocked.cell != row["blocked_cell"]
		if not progressed and blocked.move_progress > 0.0 and _edges.has(blocked.id):
			var edge: Dictionary = _edges[blocked.id]
			progressed = edge["from"] == row["blocked_cell"] and edge["to"] == blocked.next_cell() \
				and _next.get(blocked.next_cell(), -1) == blocked.id
	if progressed:
		_cooperative.erase(agent.id)
		return false
	if int(row["arrival_tick"]) < 0:
		# Movement completion sets last_progress_tick on the arrival tick;
		# begin_tick observes it one tick later without extending the deadline.
		row["arrival_tick"] = agent.last_progress_tick
		row["hold_until"] = agent.last_progress_tick + world.movement_tuning.yield_after_ticks
	if world.now >= int(row["hold_until"]):
		_cooperative.erase(agent.id)
		return false
	if blocked != null and row.has("winner_route") and _idle_without_route(world, blocked):
		# The clearer is physically in its pocket. Ask the ordinary idle loser
		# to use that real vacancy; a route alone never counts as progress.
		var winner_route: Array[Vector2i] = []
		winner_route.assign(row["winner_route"])
		_yield(world, blocked, agent, winner_route)
	return true


func advance_yield(world: SimWorld, agent: SimAgent) -> bool:
	if not _resume.has(agent.id):
		return false
	if agent is OwnerAgent:
		var owner: OwnerAgent = agent as OwnerAgent
		if owner.task != null and int(owner.priorities.get(owner.task.role, 0)) <= 0:
			# Let the ordinary owner tick settle the new mode exactly once,
			# including normal cleanup/stop-motion for any reserved partial edge.
			_resume.erase(agent.id)
			_returning.erase(agent.id)
			_cooperative.erase(agent.id)
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
