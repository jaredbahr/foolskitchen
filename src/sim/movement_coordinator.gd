class_name MovementCoordinator
extends RefCounted
## Cell and swept-edge ownership, separate from task/station reservations.
## IDs and value maps only: no back reference to a world or its agents.

enum YieldAttempt { STARTED, IN_PROGRESS_PROTECTED, NO_POCKET }

const CARRYING_PRIORITY: int = 3
## _escape outcomes: mid-step (retry next tick), nothing could change, acted.
const ESCAPE_SKIPPED: int = 0
const ESCAPE_FUTILE: int = 1
const ESCAPE_ACTED: int = 2
## Acted by starting a squeeze: in a one-cell corridor the next swap is due as
## soon as this one is done, not a whole retry later.
const ESCAPE_SQUEEZED: int = 3
const SQUEEZE_RETRY_TICKS: int = 8
## Handed along a leaving line to a head that is mid-step: looked at again next
## tick (the head is only settled for a tick at a time), but it counts as one
## of the tick's searched tries, so a long line cannot search every tick.
const ESCAPE_WAITING: int = 4
## The same two people never swap again within this many ticks.
const SQUEEZE_PAIR_COOLDOWN_TICKS: int = 40
## Futile escapes searched in one tick before the rest wait for the next.
const MAX_ESCAPE_TRIES_PER_TICK: int = 3
## How far an escape is handed along a line of leavers to reach its head.
const MAX_LINE_HAND_ON: int = 8
## Liveness key for a leaving guest: any real exit counts as its goal.
const EXIT_GOAL: Vector2i = Vector2i(-1000001, -1000001)

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
## Liveness backstop (#306): per person with a route, their real goal, the
## closest they have come to it and since when they have not got closer.
var _stall: Dictionary[int, Dictionary] = {}
## A stuck person given right of way wins arbitration until this tick.
var _right_of_way: Dictionary[int, int] = {}
## The one person whose held way keeps others out of its step: whoever has
## waited longest among the escapes whose right of way still lasts.
var _way_holder: int = -1
## Since when the holder has been waiting (its live stall is now minus this).
var _way_since: int = 0
## Arrivals held on the street by "let them out first": id -> first held tick.
var _held_since: Dictionary[int, int] = {}
## A squeeze-past: both partners cross one shared edge in lockstep.
var _squeezes: Dictionary[int, Dictionary] = {}
## When each pair (lower id, higher id) last started a squeeze.
var _pair_swapped: Dictionary[Vector2i, int] = {}
## Escape routes searched during one liveness pass: id -> route. Only kept
## while the pass runs; a pass that acts ends at once, so nothing it changes
## is ever read back stale.
var _route_memo: Dictionary[int, Array] = {}
var _memo_on: bool = false
## Diagnostics only (the liveness soak reads them): how often each escape ran.
var escape_counts: Dictionary[StringName, int] = {}
## Pairs whose squeeze finished during the current tick (for observers).
var _squeezed: Dictionary[int, int] = {}
## Door lane cache (#305), valid for one grid version.
var _lane: Dictionary[Vector2i, bool] = {}
var _lane_grid: SimGrid = null
var _lane_version: int = -1
var _work: Dictionary[Vector2i, bool] = {}
var _work_grid: SimGrid = null
var _work_version: int = -1


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
	var squeezes: Array[Array] = []
	var squeezers: Array[int] = []
	squeezers.assign(_squeezes.keys())
	squeezers.sort()
	for id: int in squeezers:
		var partner: int = int(_squeezes[id]["partner"])
		if id < partner:
			squeezes.append([id, partner])
	var finished: Array[int] = []
	finished.assign(_squeezed.keys())
	finished.sort()
	for id: int in finished:
		if id < _squeezed[id]:
			squeezes.append([id, _squeezed[id]])
	return {"occupied": _occupied.duplicate(), "next": claims,
		"edges": edges, "pending": _pending.duplicate(), "stopping": stopping, "returning": returning,
		"cooperative": cooperative, "squeezes": squeezes}


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
	if cause == "admission" and agent is CustomerAgent and _someone_leaving_by_the_door(world):
		# Let them out first: while the door is jammed (someone on the way out
		# has been stuck in the door lane for the escape limit), a guest
		# arriving from the street waits outside instead of adding to it, but
		# never longer than door_hold_max_ticks: waiting arrivals do not tick,
		# so an unbounded hold could keep them on the street until closing.
		var since: int = int(_held_since.get(agent.id, world.now))
		_held_since[agent.id] = since
		if world.now - since < world.movement_tuning.door_hold_max_ticks:
			return false
	if can_enter(world, agent, requested):
		_held_since.erase(agent.id)
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
	_held_since.erase(agent_id)
	_resume.erase(agent_id)
	_returning.erase(agent_id)
	_cooperative.erase(agent_id)
	for clearer: int in _cooperative.keys():
		if int(_cooperative[clearer]["blocked_id"]) == agent_id:
			_cooperative.erase(clearer)
	_stopping.erase(agent_id)
	_after_stop.erase(agent_id)
	_stall.erase(agent_id)
	_right_of_way.erase(agent_id)
	if _way_holder == agent_id:
		_way_holder = -1
	_end_squeeze(agent_id)
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
	_squeezed.clear()
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
	_watch_liveness(world)


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


func priority(world: SimWorld, agent: SimAgent) -> int:
	if agent is StaffAgent:
		return CARRYING_PRIORITY if (agent as StaffAgent).carries_food() else 2
	if agent is CourierAgent:
		return 2
	# Door flow (#305): a guest still arriving or queueing yields the front
	# door lane to anybody on the way out (and to every other guest).
	if agent is CustomerAgent and (agent as CustomerAgent).state <= CustomerAgent.State.QUEUED \
			and in_door_lane(world, agent.cell):
		return 0
	return 1


## The front door lane: the street entries, the floor cells beside them and the
## cells just inside those. Derived from the entries, whatever side the shop
## faces. Waiting guests stand clear of it. Cached per grid edit.
func in_door_lane(world: SimWorld, cell: Vector2i) -> bool:
	return door_lane(world).has(cell)


func door_lane(world: SimWorld) -> Dictionary[Vector2i, bool]:
	if _lane_grid != world.grid or _lane_version != world.grid.version:
		_lane_grid = world.grid
		_lane_version = world.grid.version
		_lane.clear()
		_lane.merge(lane_cells(world.grid))
	return _lane


## door_lane() for any grid, uncached (the editor checks previews with it).
static func lane_cells(grid: SimGrid) -> Dictionary[Vector2i, bool]:
	var lane: Dictionary[Vector2i, bool] = {}
	for entry: Vector2i in grid.entries():
		lane[entry] = true
		for neighbour: Vector2i in grid.walkable_neighbours(entry):
			if grid.terrain(neighbour) != SimGrid.Terrain.FLOOR:
				continue
			lane[neighbour] = true
			var delta: Vector2i = neighbour - entry
			if delta.x == 0 or delta.y == 0:
				var inside: Vector2i = neighbour + delta
				if grid.is_walkable(inside):
					lane[inside] = true
	return lane


func _before(world: SimWorld, first: SimAgent, second: SimAgent) -> bool:
	var a: int = priority(world, first)
	var b: int = priority(world, second)
	# Food in hand keeps its priority; otherwise a stuck person's granted
	# right of way (#306) wins until its retry.
	var first_way: bool = int(_right_of_way.get(first.id, -1)) >= world.now
	if first_way != (int(_right_of_way.get(second.id, -1)) >= world.now) \
			and a != CARRYING_PRIORITY and b != CARRYING_PRIORITY:
		return first_way
	return a > b or (a == b and first.id < second.id)


## A stuck person given right of way (#306) keeps the cells of the step it is
## waiting for, corners included: nobody else may slip in as soon as one
## empties. Whoever already stands in them may still move about to clear them.
## Only the most recently escaped person holds its way, so two held ways can
## never keep each other's holders out.
func _held_out(world: SimWorld, agent: SimAgent, next: Vector2i) -> bool:
	if _way_holder == -1 or _way_holder == agent.id:
		return false
	var holder: SimAgent = world.agent(_way_holder)
	if holder == null or holder.has_arrived() or not _holds_way(world, holder) \
			or not _before(world, holder, agent):
		return false
	var held: Array[Vector2i] = _step_cells(holder.cell, holder.next_cell())
	return not held.has(agent.cell) and _crosses(_step_cells(agent.cell, next), held)


func _crosses(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for cell: Vector2i in a:
		if b.has(cell):
			return true
	return false


func _holds_way(world: SimWorld, agent: SimAgent) -> bool:
	return int(_right_of_way.get(agent.id, -1)) >= world.now and agent.move_progress == 0.0


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
	if agent.uses_guest_layer() and not world.grid.is_guest_walkable(cell):
		return false
	var seat: bool = false
	var own: bool = false
	for item: PlacedItem in world.grid.seat_items_at(cell):
		seat = true
		var holder: int = item.reserved_by(cell)
		if holder != -1 and holder != agent.id:
			return false
		own = own or holder == agent.id
	return not seat or own


## No person may use an unassigned dining/bench seat as an aisle.
func standing_cell(world: SimWorld, cell: Vector2i) -> bool:
	if not world.grid.seat_items_at(cell).is_empty():
		return false
	return world.grid.is_walkable(cell)


func route(world: SimWorld, agent: SimAgent, from: Vector2i, to: Vector2i,
		avoid_people: bool = true) -> Array[Vector2i]:
	if agent is CourierAgent:
		return _courier_route(world, agent, from, to)
	return world.grid.find_path_avoiding(from, to, _route_blocked(world, agent, from, to, avoid_people),
		agent.uses_guest_layer())


## Cells this actor may not route through: other people's seats and, when
## avoiding people, every cell another person holds (except the goal itself).
func _route_blocked(world: SimWorld, agent: SimAgent, from: Vector2i, to: Vector2i,
		avoid_people: bool) -> Dictionary[Vector2i, bool]:
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
	return blocked


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
		if agent.uses_guest_layer():
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
	var legal: bool = _edge_feasible(world, agent, next) and not _held_out(world, agent, next)
	# Arbitrate simultaneous intentions by physical carrying priority, before
	# a lower ID can claim a cell merely because its tick runs first. Someone
	# a held way keeps out cannot veto anybody either.
	if legal:
		for other: SimAgent in world.agents:
			if other == agent or other.has_arrived() or other.move_progress > 0.0:
				continue
			if other.next_cell() == next and _before(world, other, agent) \
					and _edge_feasible(world, other, next) and not _held_out(world, other, next):
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
			if actor is StaffAgent and actor.has_arrived() and not _stopping.has(actor.id) and not _resume.has(actor.id):
				for next: Vector2i in world.grid.walkable_neighbours(cell):
					# The whole edge must be open now, corners included: a seated
					# guest beside a diagonal would hold this step forever (#306).
					if standing_cell(world, next) and _edge_feasible(world, actor, next):
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
	if not agent.has_arrived() and agent.move_progress == 0.0 and not _edges.has(agent.id) \
			and int(_blocked.get(agent.id, 0)) >= world.movement_tuning.yield_after_ticks:
		# A stop whose edge never started has nothing to finish. Waiting for a
		# step that stays blocked (a seated guest on its diagonal corner) would
		# hold this person forever (#306): stand still and plan afresh instead.
		var pending_goal: Vector2i = _after_stop.get(agent.id, SimGrid.NO_CELL)
		_stopping.erase(agent.id)
		_after_stop.erase(agent.id)
		_blocked.erase(agent.id)
		agent.clear_path()
		if pending_goal != SimGrid.NO_CELL:
			agent.set_destination(world.grid, pending_goal)
		return true
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
			and not agent is CourierAgent \
			and not (_reciprocal_head_on_winner(world, agent, holder, next) \
				or (holder != null and _reciprocal_head_on_winner(world, holder, agent, agent.cell))):
		var alternate: Array[Vector2i] = route(world, agent, agent.cell, agent.destination(), true)
		if alternate.is_empty():
			alternate = _local_reconnection(world, agent, next)
		if not alternate.is_empty() and alternate.size() > 1 and alternate[1] != next:
			agent.install_movement_route(alternate)


## A distant body cut must not hide a legal local way around this blocker.
## Rejoin a strictly later original vertex; preserve its real goal and suffix.
func _local_reconnection(world: SimWorld, agent: SimAgent, blocked_next: Vector2i) -> Array[Vector2i]:
	if agent.move_progress != 0.0 or _edges.has(agent.id) or _stopping.has(agent.id) \
			or agent.has_arrived() or agent.path.back() != agent.destination():
		return []
	var original: Array[Vector2i] = agent.path.duplicate()
	for index: int in range(agent.path_index + 1, original.size()):
		var anchor: Vector2i = original[index]
		if GridMath.octile(agent.cell, anchor) > float(world.movement_tuning.yield_search_radius) \
				or not can_enter(world, agent, anchor):
			continue
		# The suffix may still meet people, but never stale geometry or seats.
		var valid_suffix: bool = _legal_cell(world, agent, anchor)
		for suffix_index: int in range(index + 1, original.size()):
			var from: Vector2i = original[suffix_index - 1]
			var to: Vector2i = original[suffix_index]
			var delta: Vector2i = to - from
			if maxi(absi(delta.x), absi(delta.y)) != 1 or not world.grid.step_open(from, to) \
					or (agent.uses_guest_layer() and not world.grid.guest_step_ok(from, to)):
				valid_suffix = false
				break
			for cell: Vector2i in _step_cells(from, to):
				if not _legal_cell(world, agent, cell):
					valid_suffix = false
			if not valid_suffix:
				break
		if not valid_suffix:
			continue
		var prefix: Array[Vector2i] = route(world, agent, agent.cell, anchor, true)
		if prefix.size() < 2 or prefix[1] == blocked_next:
			continue
		prefix.append_array(original.slice(index + 1))
		return prefix
	return []


## A reciprocal cardinal pair must not both detour at the same early deadline.
## Keep actual right of way while the other actor uses existing route/yield rules.
## This only queries legal physical intentions; no claims or movement change here.
func _reciprocal_head_on_winner(world: SimWorld, agent: SimAgent, holder: SimAgent,
		next: Vector2i) -> bool:
	if holder == null or holder == agent or not _before(world, agent, holder):
		return false
	if not agent.movement_admitted or not holder.movement_admitted \
			or agent.has_arrived() or holder.has_arrived() or agent.next_cell() != next \
			or holder.cell != next or holder.next_cell() != agent.cell:
		return false
	var delta: Vector2i = next - agent.cell
	if absi(delta.x) + absi(delta.y) != 1:
		return false
	if agent.move_progress != 0.0 or holder.move_progress != 0.0 \
			or _stopping.has(agent.id) or _stopping.has(holder.id) \
			or _edges.has(agent.id) or _edges.has(holder.id):
		return false
	if _occupied.get(agent.cell, -1) != agent.id or _occupied.get(holder.cell, -1) != holder.id:
		return false
	for mover: SimAgent in [agent, holder]:
		var multiplier: float = mover.movement_multiplier()
		if not is_finite(mover.move_speed) or mover.move_speed <= 0.0 \
				or not is_finite(multiplier) or multiplier <= 0.0:
			return false
		var target: Vector2i = holder.cell if mover == agent else agent.cell
		if not _legal_cell(world, mover, mover.cell) or not _legal_cell(world, mover, target) \
				or not world.grid.step_open(mover.cell, target):
			return false
		if mover.uses_guest_layer() and not world.grid.guest_step_ok(mover.cell, target):
			return false
		for point: Vector2i in [mover.cell, target]:
			var next_owner: int = _next.get(point, mover.id)
			var swept_owner: int = _swept.get(point, mover.id)
			if (next_owner != agent.id and next_owner != holder.id) \
					or (swept_owner != agent.id and swept_owner != holder.id):
				return false
	return true


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
		# Only a guest at their table (or inside a stall) is protected. One walking to or
		# from the restroom stands in an ordinary aisle and yields like anyone
		# else; protecting it let two such trips block each other forever.
		if guest.state >= CustomerAgent.State.ORDERING and guest.state <= CustomerAgent.State.PAYING \
				and (guest.cell == guest.seat_cell or guest.restroom == CustomerAgent.Restroom.INSIDE):
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
	# One flood fill answers which pockets route() could reach at all, so a
	# boxed actor does not run a full failed search for every nearby cell.
	# Pockets pass can_enter, so no other person holds them and the shared
	# blocked set (goal exemption aside) is the one route() would build.
	var reachable: Dictionary[Vector2i, bool] = {}
	var courier: bool = yielding is CourierAgent
	if not courier:
		reachable = world.grid.reachable_avoiding(yielding.cell,
			_route_blocked(world, yielding, yielding.cell, SimGrid.NO_CELL, true),
			yielding.uses_guest_layer())
		if reachable.size() <= 1:
			# Boxed in by people: no pocket other than its own cell is reachable.
			return YieldAttempt.NO_POCKET
	for cell: Vector2i in _nearby(world, yielding, yielding.cell, world.movement_tuning.yield_search_radius):
		if cell == winner.cell or cell == winner.next_cell() or not can_enter(world, yielding, cell):
			continue
		if parking and winner_route.has(cell):
			continue
		if not courier and not reachable.has(cell):
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


# --- Liveness backstop (#306) ------------------------------------------------
# The rules above resolve ordinary traffic. Some crowded shapes (a doorway full
# of leaving and arriving guests, a worker mopping the only free door cell, a
# line of waiting guests in a one-cell aisle) can still leave someone with a
# route making no physical progress at all. This watchdog guarantees service
# never stalls. In a total order (longest stall, then lowest ID), the stuck
# person gets right of way and whoever holds its next step clears it: to any
# free cell they can reach (no radius cap), or, when boxed in, by first
# clearing the stationary people between them and the nearest free cell. A
# boxed blocker's neighbours are also asked to make room. Past a longer
# limit the stuck person squeezes past a stationary guest (a visible swap over
# one ordinary step, never a teleport), and a guest who still cannot move
# gives up and leaves. Everything walks real claimed edges; no RNG is used.

func _watch_liveness(world: SimWorld) -> void:
	if world.clock.phase != SimClock.Phase.OPEN and world.clock.phase != SimClock.Phase.LAST_ORDERS:
		_stall.clear()
		_right_of_way.clear()
		_held_since.clear()
		_pair_swapped.clear()
		_way_holder = -1
		return
	for pair: Vector2i in _pair_swapped.keys():
		if world.now - _pair_swapped[pair] >= SQUEEZE_PAIR_COOLDOWN_TICKS:
			_pair_swapped.erase(pair)
	var tuning: MovementTuning = world.movement_tuning
	var due: Array[Array] = []
	for agent: SimAgent in world.agents:
		if (agent.has_arrived() and not _resume.has(agent.id) and not _leaving(agent)) \
				or not agent.movement_admitted:
			_stall.erase(agent.id)
			continue
		if _squeezes.has(agent.id):
			# Mid-swap: not due, but the stall keeps counting. Only getting
			# closer resets it; being swapped back a cell never does.
			continue
		# Progress means getting closer to where this person is really going,
		# so a crowd that only shuffles people back and forth (yield, return,
		# yield again) counts as stuck too, not just someone standing still.
		var goal: Vector2i = _real_goal(agent)
		var distance: float = GridMath.octile(agent.cell, goal)
		if _leaving(agent):
			# Either street cell is the way out; switching between them is not progress.
			goal = EXIT_GOAL
			for entry: Vector2i in world.grid.entries():
				distance = minf(distance, GridMath.octile(agent.cell, entry))
		var row: Dictionary = _stall.get(agent.id, {})
		if row.is_empty() or row["goal"] != goal or distance < float(row["best"]):
			_stall[agent.id] = {"goal": goal, "best": distance, "since": world.now,
				"next": world.now + tuning.escape_after_ticks}
			continue
		if world.now < int(row["next"]):
			continue
		due.append([world.now - int(row["since"]), agent])
	for id: int in _right_of_way.keys():
		if _right_of_way[id] < world.now:
			_right_of_way.erase(id)
	# Total order: longest stall first, then lowest ID. One escape per tick;
	# someone mid-step is skipped (and checked again next tick) so a person
	# who keeps shuffling can never starve a stuck one of its turn.
	due.sort_custom(_stalled_before)
	# An escape that could change nothing (nobody in the way can move and no
	# squeeze is allowed) does not use up the turn of the next person, but at
	# most MAX_ESCAPE_TRIES_PER_TICK are searched; the rest wait a tick.
	_route_memo.clear()
	_memo_on = true
	_escape_due(world, due)
	_memo_on = false
	_route_memo.clear()


func _escape_due(world: SimWorld, due: Array[Array]) -> void:
	var tuning: MovementTuning = world.movement_tuning
	var tries: int = 0
	for entry: Array in due:
		var agent: SimAgent = entry[1]
		if tries >= MAX_ESCAPE_TRIES_PER_TICK:
			break
		var outcome: int = _escape(world, agent, int(entry[0]))
		if _stall.has(agent.id):
			var retry: int = tuning.escape_retry_ticks
			if outcome == ESCAPE_SKIPPED or outcome == ESCAPE_WAITING:
				retry = 1
			elif outcome == ESCAPE_SQUEEZED:
				retry = SQUEEZE_RETRY_TICKS
			_stall[agent.id]["next"] = world.now + retry
		if outcome == ESCAPE_ACTED or outcome == ESCAPE_SQUEEZED:
			return
		if outcome == ESCAPE_FUTILE or outcome == ESCAPE_WAITING:
			tries += 1


func _stalled_before(a: Array, b: Array) -> bool:
	return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and (a[1] as SimAgent).id < (b[1] as SimAgent).id)


## Where this person is actually headed: a sidestep's return goal, not its pocket.
func _real_goal(agent: SimAgent) -> Vector2i:
	if _resume.has(agent.id) and not agent is CourierAgent:
		return _resume[agent.id]
	return agent.cell if agent.path.is_empty() else agent.path.back()


## visited: the leavers this escape has already been handed through.
func _escape(world: SimWorld, stuck: SimAgent, stalled: int, visited: Dictionary[int, bool] = {}) -> int:
	if _mid_move(stuck):
		return ESCAPE_SKIPPED
	var tuning: MovementTuning = world.movement_tuning
	if stuck is CustomerAgent and stalled >= tuning.give_up_after_ticks \
			and (stuck as CustomerAgent).state < CustomerAgent.State.LEAVING:
		# Bounded: a guest never waits forever behind a crowd it cannot pass.
		(stuck as CustomerAgent).give_up_blocked(world)
		escape_counts[&"give_up"] = int(escape_counts.get(&"give_up", 0)) + 1
		if stuck.has_arrived() or world.agent(stuck.id) == null:
			return ESCAPE_ACTED
	var route_cells: Array[Vector2i] = _escape_route(world, stuck)
	if route_cells.size() < 2:
		return ESCAPE_FUTILE  # Static unreachability keeps its existing drop/exit handling.
	var step: Vector2i = route_cells[1]
	var blockers: Array[SimAgent] = []
	for cell: Vector2i in _step_cells(stuck.cell, step):
		var holder: SimAgent = _holder(world, cell)
		if holder != null and holder != stuck and not blockers.has(holder):
			blockers.append(holder)
	if _leaving(stuck) and not blockers.is_empty() and visited.size() < MAX_LINE_HAND_ON:
		# A line on the way out: clearing or swapping with the leaver ahead only
		# shuffles the line. Hand the escape, and this wait, to the one ahead,
		# until it reaches the head of the line and whoever really blocks it.
		# Each person is visited once, so two leavers facing each other never
		# bounce the escape back and forth.
		visited[stuck.id] = true
		var ahead: SimAgent = null
		for blocker: SimAgent in blockers:
			if not _leaving(blocker) or visited.has(blocker.id) or _may_squeeze(world, stuck, blocker):
				ahead = null
				break
			if ahead == null:
				ahead = blocker
		if ahead != null:
			if _mid_move(ahead):
				return ESCAPE_WAITING
			escape_counts[&"line_head"] = int(escape_counts.get(&"line_head", 0)) + 1
			return _escape(world, ahead, stalled, visited)
	var detour: bool = not stuck is CourierAgent and route_cells != stuck.path.slice(stuck.path_index - 1)
	# Right of way wins the step when someone else reaches for the same cell
	# at the same moment: in a busy corridor a free first step is exactly
	# what a stalled person keeps losing (#317). Even into someone else's held
	# way: there the two right-of-way holders meet by ordinary arbitration
	# (_before). Keeping it out (or letting the holder always win) left
	# leaving lines in edited shops stuck past 600 ticks (#318 review).
	_right_of_way[stuck.id] = world.now + tuning.escape_retry_ticks
	if blockers.is_empty():
		# Nobody stands in the shortest way: no held way and nobody is moved.
		# Only a stale detour is replaced; the turn passes on.
		if not detour:
			escape_counts[&"way"] = int(escape_counts.get(&"way", 0)) + 1
			return ESCAPE_FUTILE
		stuck.install_movement_route(route_cells)
		escape_counts[&"reroute"] = int(escape_counts.get(&"reroute", 0)) + 1
		return ESCAPE_ACTED
	# The held way stays with whoever has waited longest while theirs lasts,
	# so a newer escape in the same crowd cannot take it away (#317).
	var current: SimAgent = world.agent(_way_holder) if _way_holder != -1 else null
	if current == null or current == stuck or current.has_arrived() \
			or int(_right_of_way.get(current.id, -1)) < world.now or stalled >= world.now - _way_since:
		_way_holder = stuck.id
		_way_since = world.now - stalled
	escape_counts[&"escape"] = int(escape_counts.get(&"escape", 0)) + 1
	if detour:
		# Retake the shortest static route; right of way now wins its first step.
		stuck.install_movement_route(route_cells)
	if stalled >= tuning.squeeze_after_ticks:
		var swapped: int = _try_squeeze(world, stuck, route_cells, blockers)
		if swapped != ESCAPE_FUTILE:
			return swapped
		if stuck is StaffAgent and (stuck as StaffAgent).task == null and not (stuck as StaffAgent).carries_food():
			# An idle worker only parking or returning can simply stop here.
			supersede_destination(stuck.id)
			stuck.set_destination(world.grid, stuck.cell)
			escape_counts[&"stay"] = int(escape_counts.get(&"stay", 0)) + 1
			return ESCAPE_ACTED
	var avoid: Dictionary[Vector2i, bool] = {stuck.cell: true}
	for cell: Vector2i in route_cells:
		avoid[cell] = true
	var cleared: bool = false
	for blocker: SimAgent in blockers:
		if not _clearable(world, blocker, stuck) \
				or (stalled < tuning.squeeze_after_ticks and _busy_worker(blocker)):
			continue
		if _clear_to_pocket(world, blocker, avoid) or _push_through(world, blocker, stuck, avoid):
			cleared = true
			continue
		# Boxed in: open space around the blocker; a later retry uses it.
		var around: Dictionary[Vector2i, bool] = avoid.duplicate()
		around[blocker.cell] = true
		for cell: Vector2i in world.grid.walkable_neighbours(blocker.cell):
			var other: SimAgent = _holder(world, cell)
			if other != null and not blockers.has(other) and _clearable(world, other, stuck) \
					and not _busy_worker(other):
				cleared = _clear_to_pocket(world, other, around) or cleared
	if cleared:
		return ESCAPE_ACTED
	# Nobody in the way can go anywhere (a leaving guest meeting an arrival in
	# the doorway, with only the street behind it): waiting for the longer
	# limit cannot help, so squeeze now if allowed.
	if stalled < tuning.squeeze_after_ticks:
		var swapped: int = _try_squeeze(world, stuck, route_cells, blockers)
		if swapped != ESCAPE_FUTILE:
			return swapped
	# Futile for now: hand the held way and the turn to the next person.
	if _way_holder == stuck.id:
		_way_holder = -1
	return ESCAPE_FUTILE


## The stuck person's own static route to where it is really going (people
## ignored, seats and rooms respected). A courier keeps its planned alley.
func _escape_route(world: SimWorld, stuck: SimAgent) -> Array[Vector2i]:
	if not _memo_on:
		return _search_escape_route(world, stuck)
	if _route_memo.has(stuck.id):
		var known: Array[Vector2i] = []
		known.assign(_route_memo[stuck.id])
		return known
	var cells: Array[Vector2i] = _search_escape_route(world, stuck)
	_route_memo[stuck.id] = cells.duplicate()
	return cells


func _search_escape_route(world: SimWorld, stuck: SimAgent) -> Array[Vector2i]:
	if stuck is CourierAgent:
		return stuck.path.slice(stuck.path_index - 1)
	if _leaving(stuck):
		# Either street cell is a way out: take the nearer one.
		var best: Array[Vector2i] = []
		var best_cost: float = INF
		var entries: Array[Vector2i] = world.grid.entries()
		if stuck is InspectorAgent and entries.size() > 1:
			# Keep to the door the inspector chose after giving up on the other.
			entries.erase((stuck as InspectorAgent).avoided_entry())
		for entry: Vector2i in entries:
			var cells: Array[Vector2i] = route(world, stuck, stuck.cell, entry, false)
			var cost: float = _route_cost(cells)
			if cells.size() >= 2 and cost < best_cost:
				best = cells
				best_cost = cost
		if not best.is_empty():
			return best
	return route(world, stuck, stuck.cell, _real_goal(stuck), false)


func _route_cost(cells: Array[Vector2i]) -> float:
	var cost: float = 0.0
	for index: int in range(1, cells.size()):
		cost += GridMath.octile(cells[index - 1], cells[index])
	return cost


func _someone_leaving_by_the_door(world: SimWorld) -> bool:
	for other: SimAgent in world.agents:
		if not _leaving(other) or not in_door_lane(world, other.cell) or not _stall.has(other.id):
			continue
		# Jammed from the escape limit; from the give-up limit holding arrivals
		# back has not helped, so they come in and the backstop sorts it out.
		var stalled: int = world.now - int(_stall[other.id]["since"])
		if stalled >= world.movement_tuning.escape_after_ticks and stalled < world.movement_tuning.give_up_after_ticks:
			return true
	return false


## A guest or the health inspector on the way out: either street cell will do.
func _leaving(agent: SimAgent) -> bool:
	if agent is InspectorAgent:
		return (agent as InspectorAgent).state == InspectorAgent.State.LEAVING
	return agent is CustomerAgent and (agent as CustomerAgent).state == CustomerAgent.State.LEAVING


## Moving now: mid-edge, stopping or squeezing.
func _mid_move(agent: SimAgent) -> bool:
	return agent.move_progress > 0.0 or _edges.has(agent.id) or _stopping.has(agent.id) \
		or _squeezes.has(agent.id)


func _holder(world: SimWorld, cell: Vector2i) -> SimAgent:
	var id: int = _occupied.get(cell, _next.get(cell, _swept.get(cell, -1)))
	return world.agent(id) if id != -1 else null


## Physically settled (not mid-edge, stopping or squeezing) and not a courier.
func _clearable(world: SimWorld, agent: SimAgent, stuck: SimAgent) -> bool:
	return agent != stuck and world.agents.has(agent) and agent.movement_admitted \
		and not agent is CourierAgent and agent.move_progress == 0.0 \
		and not _edges.has(agent.id) and not _stopping.has(agent.id) and not _squeezes.has(agent.id)


## Mid-work or carrying food: finishing soon frees the cell anyway, so the
## backstop leaves them be until its squeeze limit.
func _busy_worker(agent: SimAgent) -> bool:
	if not agent is StaffAgent:
		return false
	var staff: StaffAgent = agent as StaffAgent
	if staff.carries_food():
		return true
	if staff.task == null or staff.step_index < 0 or staff.step_index >= staff.task.steps.size():
		return false
	return staff.task.steps[staff.step_index].kind == TaskStep.Kind.WORK and staff._step_started


## Unbounded search for the nearest free floor cell this person can walk to
## now, off the stuck person's route.
func _clear_to_pocket(world: SimWorld, agent: SimAgent, avoid: Dictionary[Vector2i, bool]) -> bool:
	var path: Array[Vector2i] = _pocket_path(world, agent, avoid)
	if path.size() < 2:
		return false
	_send_aside(world, agent, path)
	avoid[path.back()] = true
	escape_counts[&"pocket"] = int(escape_counts.get(&"pocket", 0)) + 1
	return true


## One breadth-first search over the steps this person can take right now
## (other people, other people's seats and diagonal corners respected, the
## same rules as route()). It stops at the first free floor cell that is off
## the stuck route and clear of the door lane and station work cells; failing
## that, the nearest free floor cell of any kind. Empty when boxed in.
func _pocket_path(world: SimWorld, agent: SimAgent, avoid: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var grid: SimGrid = world.grid
	if not grid.is_walkable(agent.cell):
		return []
	var blocked: Dictionary[Vector2i, bool] = _route_blocked(world, agent, agent.cell, SimGrid.NO_CELL, true)
	var guest: bool = agent.uses_guest_layer()
	var work: Dictionary[Vector2i, bool] = _work_cells(world)
	var previous: Dictionary[Vector2i, Vector2i] = {}
	var seen: Dictionary[Vector2i, bool] = {agent.cell: true}
	var queue: Array[Vector2i] = [agent.cell]
	var fallback: Vector2i = SimGrid.NO_CELL
	var found: Vector2i = SimGrid.NO_CELL
	var index: int = 0
	while index < queue.size() and found == SimGrid.NO_CELL:
		var current: Vector2i = queue[index]
		index += 1
		for next: Vector2i in grid.walkable_neighbours(current):
			if seen.has(next) or not grid.actor_step(current, next, blocked, guest):
				continue
			seen[next] = true
			previous[next] = current
			queue.append(next)
			if avoid.has(next) or not _pocket_cell(world, agent, next):
				continue
			if not work.has(next) and not in_door_lane(world, next):
				found = next
				break
			if fallback == SimGrid.NO_CELL:
				fallback = next
	if found == SimGrid.NO_CELL:
		found = fallback
	if found == SimGrid.NO_CELL:
		return []
	var path: Array[Vector2i] = [found]
	while previous.has(path[0]):
		path.push_front(previous[path[0]])
	return path


## Every station's work cells, cached per grid edit like the door lane.
func _work_cells(world: SimWorld) -> Dictionary[Vector2i, bool]:
	if _work_grid != world.grid or _work_version != world.grid.version:
		_work_grid = world.grid
		_work_version = world.grid.version
		_work.clear()
		for item: PlacedItem in world.grid.items():
			for cell: Vector2i in item.work_cells:
				_work[cell] = true
	return _work


func _pocket_cell(world: SimWorld, agent: SimAgent, cell: Vector2i) -> bool:
	return can_enter(world, agent, cell) and standing_cell(world, cell) \
		and world.grid.terrain(cell) == SimGrid.Terrain.FLOOR


## Nobody can step aside alone: find the nearest free floor cell this person
## could reach if the stationary people between were not there (unbounded
## search, never through the stuck person). Each of those people first clears
## to a pocket off both routes; this person then follows them out, waiting
## behind each one on ordinary claimed steps.
func _push_through(world: SimWorld, first: SimAgent, stuck: SimAgent,
		avoid: Dictionary[Vector2i, bool]) -> bool:
	var previous: Dictionary[Vector2i, Vector2i] = {}
	var queue: Array[Vector2i] = [first.cell]
	var seen: Dictionary[Vector2i, bool] = {first.cell: true, stuck.cell: true}
	var index: int = 0
	var found: Vector2i = SimGrid.NO_CELL
	while index < queue.size() and found == SimGrid.NO_CELL:
		var current: Vector2i = queue[index]
		index += 1
		for delta: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = current + delta
			if seen.has(next) or not _line_step(world, first, current, next):
				continue
			var holder: SimAgent = _holder(world, next)
			if holder != null and not _clearable(world, holder, stuck):
				continue
			seen[next] = true
			previous[next] = current
			if holder == null and not avoid.has(next) and _pocket_cell(world, first, next):
				found = next
				break
			queue.append(next)
	if found == SimGrid.NO_CELL:
		return false
	var line: Array[Vector2i] = [found]
	while previous.has(line[0]):
		line.push_front(previous[line[0]])
	var keep: Dictionary[Vector2i, bool] = avoid.duplicate()
	for cell: Vector2i in line:
		keep[cell] = true
	var moved: bool = false
	for cell: Vector2i in line.slice(1):
		var holder: SimAgent = _holder(world, cell)
		if holder == null:
			continue
		if not _clear_to_pocket(world, holder, keep):
			# Those already sent aside opened real space: that is an action, and
			# the next retry can push the rest of the line through.
			return moved
		moved = true
	_send_aside(world, first, line)
	avoid[found] = true
	escape_counts[&"line"] = int(escape_counts.get(&"line", 0)) + 1
	return true


func _line_step(world: SimWorld, mover: SimAgent, from: Vector2i, to: Vector2i) -> bool:
	if not world.grid.in_bounds(to) or not world.grid.step_open(from, to) or not _legal_cell(world, mover, to):
		return false
	return not mover.uses_guest_layer() or world.grid.guest_step_ok(from, to)


## An ordinary yield: real route, with return intent for anyone who has
## somewhere to be. Someone only standing about (an idle worker, a waiting
## guest) keeps the new spot rather than walking back into the same jam.
func _send_aside(world: SimWorld, agent: SimAgent, path: Array[Vector2i]) -> void:
	var original: Vector2i = _resume.get(agent.id, agent.destination())
	if original == SimGrid.NO_CELL:
		original = agent.cell
	var standing: bool = not _resume.has(agent.id) and agent.has_arrived() \
		and (agent is CustomerAgent or not agent is StaffAgent or (agent as StaffAgent).task == null)
	_resume[agent.id] = path.back() if standing or _idle_without_route(world, agent) else original
	_returning.erase(agent.id)
	_cooperative.erase(agent.id)
	_blocked.erase(agent.id)
	agent.install_movement_route(path)


## Last resort, after squeeze_after_ticks of no movement: swap places with a
## physically stationary person over one ordinary step. Only staff squeeze
## past guests, and a leaving guest past anyone but a courier. Returns
## ESCAPE_SQUEEZED when a swap starts (a corner swap too: in a doorway the
## way out turns, and the next swap is due just as soon; the pair cooldown
## keeps the same two from swapping back) and ESCAPE_FUTILE when none is allowed.
func _try_squeeze(world: SimWorld, stuck: SimAgent, route_cells: Array[Vector2i],
		blockers: Array[SimAgent]) -> int:
	if stuck is CourierAgent:
		return ESCAPE_FUTILE
	var step: Vector2i = route_cells[1]
	for partner: SimAgent in blockers:
		if not _clearable(world, partner, stuck) or not _may_squeeze(world, stuck, partner):
			continue
		if _pair_swapped.has(_pair(stuck, partner)):
			continue  # These two just swapped: never straight back.
		var through: Vector2i = partner.cell
		var delta: Vector2i = through - stuck.cell
		if absi(delta.x) + absi(delta.y) != 1:
			continue  # Squeezes are cardinal; a diagonal holder is cleared instead.
		var handover: bool = false
		if not _line_step(world, partner, through, stuck.cell):
			handover = _own_seat_handover_ok(world, stuck, partner, through)
			if not handover:
				continue
		if not _line_step(world, stuck, stuck.cell, through):
			continue
		var rest: Array[Vector2i] = [stuck.cell, through]
		if through == step:
			rest.append_array(route_cells.slice(2))
		else:
			# A corner holder: continue cardinally to the original next step.
			var onward: Array[Vector2i] = route(world, stuck, through, route_cells.back(), false)
			if onward.size() < 1:
				continue
			rest.append_array(onward.slice(1))
		if handover:
			_hand_over_seat(world, stuck, partner)
		_start_squeeze(world, stuck, partner, rest)
		_pair_swapped[_pair(stuck, partner)] = world.now
		return ESCAPE_SQUEEZED
	return ESCAPE_FUTILE


func _pair(a: SimAgent, b: SimAgent) -> Vector2i:
	return Vector2i(mini(a.id, b.id), maxi(a.id, b.id))


## A leaving guest still standing on its own seat (a stool beside the door)
## can only be passed by someone stepping onto that seat. Only the seat it
## really holds, and only geometry the partner could otherwise walk.
func _own_seat_handover_ok(world: SimWorld, stuck: SimAgent, partner: SimAgent, through: Vector2i) -> bool:
	if not stuck is CustomerAgent or (stuck as CustomerAgent).state != CustomerAgent.State.LEAVING:
		return false
	var items: Array[PlacedItem] = world.grid.seat_items_at(stuck.cell)
	if items.is_empty() or not world.grid.is_walkable(stuck.cell) or not world.grid.step_open(through, stuck.cell):
		return false
	# A seat can be projected by both its table and its furnishing: the stuck
	# guest holds at least one of them and nobody else holds any.
	var held: bool = false
	for item: PlacedItem in items:
		var holder: int = item.reserved_by(stuck.cell)
		if holder != stuck.id and holder != -1:
			return false
		held = held or holder == stuck.id
	if not held:
		return false
	if partner.uses_guest_layer():
		return world.grid.is_guest_walkable(stuck.cell) and world.grid.guest_step_ok(through, stuck.cell)
	return true


## The partner takes over the seat booking for as long as it physically stands
## there; the ordinary deferred release frees it once it walks off.
func _hand_over_seat(world: SimWorld, stuck: SimAgent, partner: SimAgent) -> void:
	for item: PlacedItem in world.grid.seat_items_at(stuck.cell):
		if item.reserved_by(stuck.cell) != stuck.id:
			continue
		item.release(stuck.cell, stuck.id)
		if item.reserve(stuck.cell, partner.id):
			_seat_releases.append({"item": item.id, "cell": stuck.cell, "actor": partner.id})


func _may_squeeze(world: SimWorld, stuck: SimAgent, partner: SimAgent) -> bool:
	if partner is CourierAgent:
		return false
	if stuck is StaffAgent:
		return partner is CustomerAgent or partner is InspectorAgent
	if not _leaving(stuck):
		return false
	if not _leaving(partner):
		return true
	# Two people on the way out swapping usually gets neither closer to the
	# street. Only a real head-on is allowed (the partner's own way out runs
	# through the stuck person's cell), so two leavers jammed against each
	# other (around a table, towards different doors) are never stuck.
	var theirs: Array[Vector2i] = _escape_route(world, partner)
	return theirs.size() >= 2 and theirs[1] == stuck.cell


func _start_squeeze(world: SimWorld, stuck: SimAgent, partner: SimAgent, stuck_path: Array[Vector2i]) -> void:
	var original: Vector2i = _resume.get(partner.id, partner.destination())
	if original == SimGrid.NO_CELL:
		original = partner.cell
	_resume[partner.id] = stuck.cell if _idle_without_route(world, partner) else original
	_returning.erase(partner.id)
	_cooperative.erase(partner.id)
	_blocked.erase(partner.id)
	_blocked.erase(stuck.id)
	partner.install_movement_route([partner.cell, stuck.cell] as Array[Vector2i])
	stuck.install_movement_route(stuck_path)
	_squeezes[stuck.id] = {"partner": partner.id, "tick": -1}
	_squeezes[partner.id] = {"partner": stuck.id, "tick": -1}
	# Opposite sides of the shared edge, so the view draws them passing.
	stuck.squeeze_side = 1.0
	partner.squeeze_side = -1.0
	for pair: Array in [[stuck, partner], [partner, stuck]]:
		var mover: SimAgent = pair[0]
		var other: SimAgent = pair[1]
		_edges[mover.id] = {"id": mover.id, "from": mover.cell, "to": other.cell}
		_next[other.cell] = mover.id
	escape_counts[&"squeeze"] = int(escape_counts.get(&"squeeze", 0)) + 1
	world.log_event("#%d squeezed past #%d" % [stuck.id, partner.id])


func is_squeezing(id: int) -> bool:
	return _squeezes.has(id)


## Both partners advance together at the slower person's ordinary step time.
func advance_squeeze(world: SimWorld, agent: SimAgent) -> bool:
	if not _squeezes.has(agent.id):
		agent.squeeze_side = 0.0
		# The partner of a swap that finished earlier this tick has already
		# moved this tick: it only holds, like the one that completed it.
		return _squeezed.has(agent.id)
	var row: Dictionary = _squeezes[agent.id]
	if int(row["tick"]) == world.now:
		return true
	var partner: SimAgent = world.agent(int(row["partner"]))
	if partner == null:
		_end_squeeze(agent.id)
		return false
	var rate: float = minf(_tick_rate(agent), _tick_rate(partner))
	row["tick"] = world.now
	_squeezes[partner.id]["tick"] = world.now
	if rate <= 0.0:
		return true
	var before: float = agent.move_progress
	agent.move_progress += rate
	partner.move_progress += rate
	agent.last_progress_tick = world.now
	partner.last_progress_tick = world.now
	if agent.move_progress < 1.0:
		return true
	var time: float = clampf((1.0 - before) / rate, 0.0, 1.0)
	var a_from: Vector2i = agent.cell
	var b_from: Vector2i = partner.cell
	for mover: SimAgent in [agent, partner]:
		mover.move_progress = 0.0
		mover.cell = b_from if mover == agent else a_from
		mover.path_index += 1
		mover.squeeze_side = 0.0
		mover.movement_trace_point(time)
	_squeezes.erase(agent.id)
	_squeezes.erase(partner.id)
	_squeezed[agent.id] = partner.id
	_squeezed[partner.id] = agent.id
	_release_edge(agent.id)
	_release_edge(partner.id)
	_occupied[agent.cell] = agent.id
	_occupied[partner.cell] = partner.id
	_swept[agent.cell] = agent.id
	_swept[partner.cell] = partner.id
	_release_vacated_seats(world)
	return true


## Edge fraction per tick at this person's ordinary walking speed (cardinal).
func _tick_rate(agent: SimAgent) -> float:
	var multiplier: float = agent.movement_multiplier()
	if not is_finite(multiplier) or multiplier <= 0.0 or not is_finite(agent.move_speed):
		return 0.0
	return maxf(agent.move_speed, 0.0) * multiplier


## A removed partner leaves the other on an ordinary claimed edge into a cell
## that is now empty; it finishes that edge normally.
func _end_squeeze(agent_id: int) -> void:
	if not _squeezes.has(agent_id):
		return
	var partner: int = int(_squeezes[agent_id]["partner"])
	_squeezes.erase(agent_id)
	_squeezes.erase(partner)
