class_name MovementInvariants
extends RefCounted
## Independent observed-history oracle. Reconstruct edges from timed physical
## points; never copy a planner's occupancy map as the expected answer.

const EPSILON: float = 0.000001

## Which items project a seat on each cell, rebuilt from the grid's own items
## whenever the grid or its version changes. Ids only, so no object is kept.
static var _seat_grid_id: int = 0
static var _seat_version: int = -1
static var _seat_ids: Dictionary[Vector2i, Array] = {}


static func _seat_item_ids(grid: SimGrid, cell: Vector2i) -> Array:
	if grid.get_instance_id() != _seat_grid_id or grid.version != _seat_version:
		_seat_ids.clear()
		for item: PlacedItem in grid.items():
			for seat: Vector2i in item.seat_cells:
				if not _seat_ids.has(seat):
					_seat_ids[seat] = []
				if not (_seat_ids[seat] as Array).has(item.id):
					(_seat_ids[seat] as Array).append(item.id)
		_seat_grid_id = grid.get_instance_id()
		_seat_version = grid.version
	return _seat_ids.get(cell, [])


static func capture(world: SimWorld) -> Dictionary:
	var active: Dictionary[int, Dictionary] = {}
	var pending: Dictionary[int, Dictionary] = {}
	for agent: SimAgent in world.agents:
		active[agent.id] = _actor_before(agent)
	for agent: SimAgent in world.pending_agents():
		pending[agent.id] = _actor_before(agent)
	var seats: Dictionary[Vector2i, int] = {}
	for item: PlacedItem in world.grid.items():
		for seat: Vector2i in item.seat_cells:
			var holder: int = item.reserved_by(seat)
			if holder >= 0:
				seats[seat] = holder if not seats.has(seat) or seats[seat] == holder else -2
	return {"tick": world.now, "phase": world.clock.phase, "day": world.clock.day,
		"active": active, "pending": pending, "seats": seats}


static func _actor_before(agent: SimAgent) -> Dictionary:
	return {"cell": agent.cell, "next": agent.next_cell(), "progress": agent.move_progress,
		"position": GridMath.cell_to_world(agent.cell).lerp(GridMath.cell_to_world(agent.next_cell()),
			agent.move_progress)}


static func problem(world: SimWorld, before: Dictionary) -> String:
	if before.get("tick", -2) != world.now - 1:
		return "missing exact prior-tick observation"
	var occupied: Dictionary[Vector2i, int] = {}
	var active: Dictionary[int, SimAgent] = {}
	# A squeeze-past (#306) is the one declared exception: two partners swap
	# over one shared edge, each claiming the other's current cell, and a seat
	# booking on one of the two cells passes to the partner stepping onto it.
	var partners: Dictionary[int, int] = {}
	for pair: Array in world.movement.snapshot().get("squeezes", []):
		partners[int(pair[0])] = int(pair[1])
		partners[int(pair[1])] = int(pair[0])
	for agent: SimAgent in world.agents:
		if not agent.movement_admitted or active.has(agent.id):
			return "unadmitted or duplicate active person: %d" % agent.id
		active[agent.id] = agent
		if occupied.has(agent.cell):
			return "cell %s shared by %d and %d" % [agent.cell, occupied[agent.cell], agent.id]
		occupied[agent.cell] = agent.id
		if not is_finite(agent.move_progress) or agent.move_progress < 0.0 or agent.move_progress >= 1.0:
			return "invalid fractional progress: %d" % agent.id
		# Only the seat a leaving guest handed to its partner may be stood on
		# under the partner's booking; every other seat rule still applies.
		var handed_to: int = partners.get(agent.id, -1)
		var invalid: String = _cell_problem(world, agent, agent.cell, -1, handed_to)
		if not invalid.is_empty():
			return "current cell of %d: %s" % [agent.id, invalid]
		var from: Vector2i = agent.cell
		var first: int = agent.path_index
		if world.movement.is_squeezing(agent.id):
			# The swap edge itself is the declared exception; the route after it
			# is checked like anyone's.
			if first >= agent.path.size():
				return "squeeze of %d has no swap edge" % agent.id
			from = agent.path[first]
			first += 1
		for index: int in range(first, agent.path.size()):
			var to: Vector2i = agent.path[index]
			invalid = _edge_problem(world, agent, from, to)
			if not invalid.is_empty():
				return "future edge of %d: %s" % [agent.id, invalid]
			from = to
	var snapshot: Dictionary = world.movement.snapshot()
	if snapshot.occupied != occupied:
		return "occupancy snapshot does not describe every active person"
	var pending_ids: Array[int] = []
	for waiting: SimAgent in world.pending_agents():
		if active.has(waiting.id) or waiting.movement_admitted or world.agent(waiting.id) != null:
			return "pending person hidden in active population: %d" % waiting.id
		if world.pending_agent(waiting.id) != waiting or pending_ids.has(waiting.id):
			return "pending identity lost or repeated: %d" % waiting.id
		pending_ids.append(waiting.id)
	if snapshot.pending != pending_ids:
		return "pending snapshot does not match ordered admission queue"
	var claims: Dictionary = snapshot.next
	for destination: Vector2i in claims:
		var holder: int = claims[destination]
		if not active.has(holder):
			return "claim held by missing person: %d" % holder
		if occupied.has(destination) and occupied[destination] != holder \
				and partners.get(holder, -1) != occupied[destination]:
			return "claim conflicts with another current person at %s" % destination
	for agent: SimAgent in world.agents:
		if partners.has(agent.id):
			# The squeeze bows sideways off the grid line; check its ends only.
			var prior: Dictionary = before.active.get(agent.id, {})
			var partner_prior: Dictionary = before.active.get(partners[agent.id], {})
			if prior.is_empty() or partner_prior.is_empty() \
					or not agent.cell in [prior.cell, partner_prior.cell]:
				return "squeeze of %d does not swap with its partner" % agent.id
			continue
		var analysis: Dictionary = _actual_segments(world, agent, before)
		if not analysis.error.is_empty():
			return "actual trace of %d: %s" % [agent.id, analysis.error]
		var required: Dictionary = analysis.required
		if agent.move_progress > 0.0:
			for cell: Vector2i in _edge_cells(agent.cell, agent.next_cell()):
				required[cell] = true
		for cell: Vector2i in required:
			if occupied.get(cell, -1) != agent.id and claims.get(cell, -1) != agent.id:
				return "missing reconstructed current/next/swept claim for %d at %s" % [agent.id, cell]
	var edges: Array = snapshot.edges
	var expected_edges: Dictionary[int, Dictionary] = {}
	for agent: SimAgent in world.agents:
		if agent.move_progress > 0.0:
			expected_edges[agent.id] = {"id": agent.id, "from": agent.cell, "to": agent.next_cell()}
	var seen_edges: Dictionary[int, bool] = {}
	for index: int in edges.size():
		var edge: Dictionary = edges[index]
		if not edge.get("id") is int or seen_edges.has(edge.id) \
				or not expected_edges.has(edge.id) or edge != expected_edges[edge.id]:
			return "edge record does not match actual partial current-to-next movement"
		seen_edges[edge.id] = true
		for other_index: int in range(index + 1, edges.size()):
			var other: Dictionary = edges[other_index]
			if edge.id == other.id:
				continue
			if edge["from"] == other["to"] and edge["to"] == other["from"] \
					and partners.get(int(edge.id), -1) != int(other.id):
				return "opposite edge reservations"
			var delta: Vector2i = edge["to"] - edge["from"]
			var other_delta: Vector2i = other["to"] - other["from"]
			if delta.x != 0 and delta.y != 0 and other_delta.x != 0 and other_delta.y != 0 \
					and edge["from"] + edge["to"] == other["from"] + other["to"]:
				return "crossed diagonal reservations"
	if seen_edges.size() != expected_edges.size():
		return "actual partial movement is missing its exact edge record"
	var stopping: Array = snapshot.get("stopping", [])
	for id: int in stopping:
		if not active.has(id):
			return "stopping edge belongs to a missing person"
	for left: int in world.agents.size():
		for right: int in range(left + 1, world.agents.size()):
			if partners.get(world.agents[left].id, -1) == world.agents[right].id:
				continue
			if _traces_touch(world.agents[left].movement_trace(), world.agents[right].movement_trace()):
				return "timed movement crosses between %d and %d" % [world.agents[left].id, world.agents[right].id]
	return ""


static func _cell_problem(world: SimWorld, agent: SimAgent, cell: Vector2i, prior_owner: int = -1,
		handed_to: int = -1) -> String:
	if agent is CourierAgent:
		var courier: CourierAgent = agent as CourierAgent
		var on_route: bool = courier.route.has(cell)
		if world.grid.in_bounds(cell) and world.grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			if not on_route or not world.grid.is_walkable(cell):
				return "courier crosses indoor/solid geometry"
		elif not on_route:
			var pocket: bool = false
			for route_cell: Vector2i in courier.route:
				pocket = pocket or absi(route_cell.x - cell.x) + absi(route_cell.y - cell.y) == 1
			if not pocket:
				return "courier leaves route and adjacent outdoor pockets"
	elif not world.grid.is_walkable(cell):
		return "solid footprint or nonwalkable cell"
	if agent is CustomerAgent and not world.grid.is_guest_walkable(cell):
		return "guest enters staff-only room"
	var seat: bool = false
	var own: bool = false
	for item_id: int in _seat_item_ids(world.grid, cell):
		var item: PlacedItem = world.grid.item(item_id)
		seat = true
		var holder: int = item.reserved_by(cell)
		var handed: bool = handed_to >= 0 and holder == handed_to
		if holder >= 0 and holder != agent.id and prior_owner != agent.id and not handed:
			return "foreign furniture seat"
		own = own or holder == agent.id or handed
	if seat and not own and prior_owner != agent.id:
		return "unassigned furniture seat"
	return ""


static func _edge_problem(world: SimWorld, agent: SimAgent, from: Vector2i, to: Vector2i,
		prior_seat: Vector2i = SimGrid.NO_CELL, prior_owner: int = -1) -> String:
	var delta: Vector2i = to - from
	if maxi(absi(delta.x), absi(delta.y)) != 1:
		return "missing intermediate grid centre"
	if not world.grid.step_open(from, to):
		return "crosses an interior wall edge"
	for cell: Vector2i in _edge_cells(from, to):
		var invalid: String = _cell_problem(world, agent, cell,
			prior_owner if cell == from and from == prior_seat else -1)
		if not invalid.is_empty():
			return invalid
	return ""


static func _edge_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [from, to]
	var delta: Vector2i = to - from
	if delta.x != 0 and delta.y != 0:
		cells.append(from + Vector2i(delta.x, 0))
		cells.append(from + Vector2i(0, delta.y))
	return cells


static func _actual_segments(world: SimWorld, agent: SimAgent, before: Dictionary) -> Dictionary:
	var trace: Dictionary = agent.movement_trace()
	var points: Array = trace.get("points", [])
	var times: Array = trace.get("times", [])
	if trace.get("tick", -1) != world.now or points.size() < 2 or points.size() != times.size() \
			or times[0] != 0.0 or times[-1] != 1.0:
		return _bad("stale or incomplete normalized movement trace")
	for index: int in points.size():
		if not points[index] is Vector3 or not (points[index] as Vector3).is_finite() \
				or not (times[index] is int or times[index] is float) or not is_finite(float(times[index])) \
				or times[index] < 0.0 or times[index] > 1.0:
			return _bad("invalid movement trace value")
		if index > 0 and (times[index] < times[index - 1] \
				or (times[index] == times[index - 1] and points[index] != points[index - 1])):
			return _bad("noncausal movement trace")
	var prior_active: Dictionary = before.active
	var prior_pending: Dictionary = before.pending
	var discontinuous: Variant = trace.get("discontinuous")
	var cause: Variant = trace.get("discontinuity_cause")
	if not discontinuous is bool or not (cause is String or cause is StringName):
		return _bad("missing explicit discontinuity cause")
	var cursor: Vector2i
	if discontinuous:
		if cause == "admission" and not prior_active.has(agent.id):
			cursor = GridMath.world_to_cell(points[0])
			if prior_pending.has(agent.id) and not agent is StaffAgent \
					and prior_pending[agent.id].cell != cursor:
				return _bad("pending admission moved its requested entry")
		elif cause == "reset" and before.phase in [SimClock.Phase.MORNING, SimClock.Phase.CLOSED] \
				and world.clock.phase in [SimClock.Phase.MORNING, SimClock.Phase.CLOSED]:
			cursor = GridMath.world_to_cell(points[0])
		else:
			return _bad("unjustified discontinuity for an active service person")
		if not (points[0] as Vector3).is_equal_approx(GridMath.cell_to_world(cursor)):
			return _bad("admission/reset does not begin at an actual cell centre")
	else:
		if cause != "" or not prior_active.has(agent.id):
			return _bad("normal trace has no actual prior active identity")
		if not (points[0] as Vector3).is_equal_approx(prior_active[agent.id].position):
			return _bad("trace erased the prior physical start")
		cursor = prior_active[agent.id].cell
	var required: Dictionary[Vector2i, bool] = {}
	var prior_seat: Vector2i = prior_active[agent.id].cell if prior_active.has(agent.id) else SimGrid.NO_CELL
	var prior_owner: int = before.seats.get(prior_seat, -1)
	var first_departure: bool = not discontinuous and prior_owner == agent.id
	for index: int in range(1, points.size()):
		var start: Vector3 = points[index - 1]
		var finish: Vector3 = points[index]
		if start.is_equal_approx(finish):
			## A near1 scalar fraction can already round to the next Vector3
			## centre. An actual completion record can then be duplicate points
			## before a turn. Advance only with prior partial-edge evidence and
			## subsequent motion/committed current cell, never for a plain hold.
			var rounded: Vector2i = GridMath.world_to_cell(finish)
			var later_motion: bool = false
			for later: int in range(index + 1, points.size()):
				later_motion = later_motion or not finish.is_equal_approx(points[later])
			if rounded != cursor and finish.is_equal_approx(GridMath.cell_to_world(rounded)) \
					and prior_active.has(agent.id) and prior_active[agent.id].cell == cursor \
					and prior_active[agent.id].next == rounded and prior_active[agent.id].progress > 0.0 \
					and (later_motion or agent.cell != cursor):
				var invalid: String = _edge_problem(world, agent, cursor, rounded,
					prior_seat if first_departure else SimGrid.NO_CELL, prior_owner)
				if not invalid.is_empty():
					return _bad(invalid)
				for cell: Vector2i in _edge_cells(cursor, rounded):
					required[cell] = true
				cursor = rounded
				first_departure = false
			continue
		var centre: Vector3 = GridMath.cell_to_world(cursor)
		var motion: Vector3 = finish - start
		if absf(motion.y) > EPSILON or (absf(motion.x) > EPSILON and absf(motion.z) > EPSILON \
				and absf(absf(motion.x) - absf(motion.z)) > EPSILON):
			return _bad("actual segment turns between grid centres")
		var direction: Vector2i = Vector2i(int(signf(motion.x)), int(signf(motion.z)))
		var target: Vector2i = cursor + direction
		var target_centre: Vector3 = GridMath.cell_to_world(target)
		var off_centre: Vector3 = start - centre
		if absf(off_centre.x * motion.z - off_centre.z * motion.x) > EPSILON \
				or off_centre.dot(motion) < -EPSILON:
			return _bad("actual segment reverses or turns before a grid centre")
		if start.distance_to(target_centre) + EPSILON < start.distance_to(finish):
			return _bad("actual segment omitted a crossed grid centre")
		## A completed departure may release its old seat during this tick. Only
		## its observed prior owner may have traversed that source; CURRENT and
		## FUTURE cells above always require their actual current reservation.
		var invalid: String = _edge_problem(world, agent, cursor, target,
			prior_seat if first_departure else SimGrid.NO_CELL, prior_owner)
		if not invalid.is_empty():
			return _bad(invalid)
		for cell: Vector2i in _edge_cells(cursor, target):
			required[cell] = true
		## Vector3 is lower precision than movement's float: a final fraction
		## just below1 can round to the centre without committing that cell.
		var continues: bool = false
		for later: int in range(index + 1, points.size()):
			continues = continues or not finish.is_equal_approx(points[later])
		if finish.is_equal_approx(target_centre) and (continues or agent.cell != cursor):
			cursor = target
			first_departure = false
	if cursor != agent.cell:
		return _bad("completed trace cells disagree with actual current cell")
	var endpoint: Vector3 = GridMath.cell_to_world(agent.cell).lerp(
		GridMath.cell_to_world(agent.next_cell()), agent.move_progress)
	if not (points[-1] as Vector3).is_equal_approx(endpoint):
		return _bad("trace endpoint disagrees with actual movement")
	return {"error": "", "required": required}


static func _bad(message: String) -> Dictionary:
	return {"error": message, "required": {}}


static func _traces_touch(a: Dictionary, b: Dictionary) -> bool:
	## Discontinuity is never an actor or collision exclusion.
	var cuts: Array[float] = []
	for value: Variant in a.times + b.times:
		if not cuts.has(float(value)):
			cuts.append(float(value))
	cuts.sort()
	for index: int in range(1, cuts.size()):
		var first: float = cuts[index - 1]
		var last: float = cuts[index]
		if last <= first:
			continue
		var relative_start: Vector3 = _at(a, first) - _at(b, first)
		var relative_end: Vector3 = _at(a, last) - _at(b, last)
		var delta: Vector3 = relative_end - relative_start
		var fraction: float = 0.0 if delta.length_squared() == 0.0 \
			else clampf(-relative_start.dot(delta) / delta.length_squared(), 0.0, 1.0)
		if (relative_start + delta * fraction).length_squared() <= EPSILON * EPSILON:
			return true
	return false


static func _at(trace: Dictionary, time: float) -> Vector3:
	var points: Array = trace.points
	var times: Array = trace.times
	for index: int in range(1, times.size()):
		if time <= float(times[index]) and times[index] > times[index - 1]:
			var fraction: float = (time - float(times[index - 1])) / (float(times[index]) - float(times[index - 1]))
			return (points[index - 1] as Vector3).lerp(points[index], fraction)
	return points[-1]
