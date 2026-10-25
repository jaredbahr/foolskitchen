class_name AgentPresentationController
extends RefCounted
## Read-only bridge from existing sim state to PersonView. No agents are retained.
## ShopView supplies nodes later; this helper owns no scene or sim lifecycle.

const NOMINAL_CHAIR_SEAT_HEIGHT: float = 0.27
const MIN_STANDING_DISTANCE: float = 0.45
const DISPLAY_NUDGE_STEP: float = MIN_STANDING_DISTANCE + 0.00001
const MOOD_CLEARANCE: float = 0.15

class Frame extends RefCounted:
	var id: int = 0
	var role: StringName = &""
	var customer_type: StringName = &"regular"
	var look_supported: bool = false
	var floor_position: Vector3 = Vector3.ZERO
	var display_offset: Vector3 = Vector3.ZERO
	var separation_blocked: bool = false
	var facing_direction: Vector3 = Vector3.ZERO
	var moving: bool = false
	var seated: bool = false
	var carrying: bool = false
	var working: bool = false
	var seat_height: float = 0.0
	var show_tray: bool = false
	var mood_visible: bool = false
	var mood_band: int = -1
	var clip: StringName = &"idle"
	# Local to PersonView, so parented attachments inherit its facing and nudge.
	var anchors_ready: bool = false
	var head_anchor: Vector3 = Vector3.ZERO
	var mood_anchor: Vector3 = Vector3.ZERO
	var tray_anchor: Vector3 = Vector3.ZERO


## Reuses the sim's next_cell/progress projection; never advances or re-paths.
static func frame_for(agent: SimAgent, world: SimWorld, chair_seat_height: float = NOMINAL_CHAIR_SEAT_HEIGHT,
		seated_forward_offset: float = 0.0, seated_facing: Vector3 = Vector3.ZERO) -> Frame:
	var frame: Frame = Frame.new()
	frame.id = agent.id
	frame.role = agent.role
	if agent is CustomerAgent:
		frame.customer_type = (agent as CustomerAgent).customer_type_id
	frame.look_supported = PersonPresentation.model_for(agent.role, agent.id, frame.customer_type) != &""
	var start: Vector3 = GridMath.cell_to_world(agent.cell)
	var end: Vector3 = GridMath.cell_to_world(agent.next_cell())
	frame.floor_position = start.lerp(end, clampf(agent.move_progress, 0.0, 1.0))
	frame.facing_direction = end - start
	frame.moving = frame.facing_direction.length_squared() > 0.000001
	if agent is CustomerAgent:
		var customer: CustomerAgent = agent as CustomerAgent
		frame.mood_visible = CustomerAgent.MOOD_WAITING_STATES.has(int(customer.state))
		frame.mood_band = customer.mood_band()
		frame.seated = _is_seated(customer, world)
		if frame.seated:
			frame.seat_height = maxf(chair_seat_height, 0.0) if is_finite(chair_seat_height) else 0.0
			frame.facing_direction = _item_center(world.grid.item(customer.table_item_id)) - start
			var authored: Vector3 = Vector3(seated_facing.x, 0.0, seated_facing.z)
			if authored.is_finite() and authored.length_squared() > 0.000001:
				frame.facing_direction = authored
			if is_finite(seated_forward_offset) and seated_forward_offset >= 0.0:
				var forward: Vector3 = Vector3(frame.facing_direction.x, 0.0, frame.facing_direction.z).normalized()
				frame.display_offset = forward * seated_forward_offset
	if agent is StaffAgent:
		var staff: StaffAgent = agent as StaffAgent
		var task: SimTask = _active_task(staff, world)
		if task != null:
			var count: int = int(task.payload.get("carried_count", 0)) if task.kind == &"deliver" else 0
			frame.carrying = count > 0
			frame.show_tray = count > 1
			frame.working = not frame.moving and staff.step_index >= 0 \
				and staff.step_index < task.steps.size() \
				and task.steps[staff.step_index].kind == TaskStep.Kind.WORK \
				and staff._step_started and staff.work_left > 0.0 and staff._waiting_for.is_empty()
			var held: PlacedItem = world.grid.item(staff._held_item_id)
			if frame.working and held != null and staff._held_cell == staff.cell \
					and held.reserved_by(staff._held_cell) == staff.id:
				frame.facing_direction = _item_center(held) - start
	frame.clip = PersonPresentation.clip_for_state(frame.moving, frame.seated, frame.carrying, frame.working)
	return frame


## Caller may supply actual per-person chair heights after resolving prop nodes.
## Order-independent nudges always start from fresh sim positions, never last frame.
static func frames_for(agents: Array[SimAgent], world: SimWorld, chair_heights: Dictionary[int, float] = {},
		seat_facings: Dictionary[int, Vector3] = {}, seat_offsets: Dictionary[int, float] = {}) -> Dictionary[int, Frame]:
	var frames: Dictionary[int, Frame] = {}
	var ids: Array[int] = []
	for agent: SimAgent in agents:
		frames[agent.id] = frame_for(agent, world, chair_heights.get(agent.id, NOMINAL_CHAIR_SEAT_HEIGHT),
			seat_offsets.get(agent.id, 0.0), seat_facings.get(agent.id, Vector3.ZERO))
		ids.append(agent.id)
	ids.sort()
	# Final authored seated positions are immutable blockers, including higher IDs.
	var occupied: Array[Vector3] = []
	for id: int in ids:
		if frames[id].seated:
			occupied.append(frames[id].floor_position + frames[id].display_offset)
	for id: int in ids:
		var frame: Frame = frames[id]
		if frame.moving or frame.seated:
			continue
		var drawn: Vector3 = _separated_position(frame.floor_position, occupied, world.grid)
		frame.display_offset = drawn - frame.floor_position
		frame.separation_blocked = not _has_clearance(drawn, occupied) \
			or not _floor_safe(frame.floor_position, drawn, world.grid)
		occupied.append(drawn)
	return frames


## Greedy, stable ID order: later people avoid final positions, not raw positions.
## The 2N+1 ring budget fits N blockers in unobstructed space. Actual floor
## geometry can make separation infeasible; keep the origin and report it.
## Do not clamp the result afterwards: that would recreate seat intersections.
static func _separated_position(origin: Vector3, occupied: Array[Vector3], grid: SimGrid) -> Vector3:
	if _has_clearance(origin, occupied) and _floor_safe(origin, origin, grid):
		return origin
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD,
		Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized(),
		Vector3(-1, 0, -1).normalized(), Vector3(1, 0, -1).normalized()]
	for ring: int in range(1, 2 * occupied.size() + 2):
		for direction: Vector3 in directions:
			var candidate: Vector3 = origin + direction * DISPLAY_NUDGE_STEP * float(ring)
			if _has_clearance(candidate, occupied) and _floor_safe(origin, candidate, grid):
				return candidate
	return origin


## Conservative swept footprint, not pathfinding: reject any wall, solid item,
## outside cell or room edge touched between the real and drawn floor points.
## Half the separation distance is the display footprint, not a model scale.
static func _floor_safe(origin: Vector3, candidate: Vector3, grid: SimGrid) -> bool:
	var radius: float = MIN_STANDING_DISTANCE * 0.5
	var low: Vector2i = GridMath.world_to_cell(Vector3(minf(origin.x, candidate.x) - radius,
		0.0, minf(origin.z, candidate.z) - radius))
	var high: Vector2i = GridMath.world_to_cell(Vector3(maxf(origin.x, candidate.x) + radius,
		0.0, maxf(origin.z, candidate.z) + radius))
	if not grid.in_bounds(low) or not grid.in_bounds(high):
		return false
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			if not grid.is_walkable(Vector2i(x, y)):
				return false
	return true


static func _has_clearance(candidate: Vector3, occupied: Array[Vector3]) -> bool:
	for point: Vector3 in occupied:
		var difference: Vector3 = candidate - point
		difference.y = 0.0
		if difference.length_squared() < MIN_STANDING_DISTANCE * MIN_STANDING_DISTANCE:
			return false
	return true


## False asks the caller to retain an explicit unsupported-role fallback.
## It does not choose a substitute model (notably for the unapproved Cleaner).
static func apply(frame: Frame, view: PersonView, playback_speed: float) -> bool:
	view.position = frame.floor_position + frame.display_offset
	view.face_direction(frame.facing_direction)
	view.set_playback_speed(playback_speed)
	frame.anchors_ready = false
	if not frame.look_supported:
		view.set_look(frame.role, frame.id, frame.customer_type)
		return false
	if not view.set_look(frame.role, frame.id, frame.customer_type):
		return false
	if not view.set_pose(frame.moving, frame.seated, frame.carrying, frame.working, frame.seat_height):
		return false
	frame.head_anchor = view.head_anchor_position()
	frame.mood_anchor = frame.head_anchor + Vector3.UP * MOOD_CLEARANCE
	frame.tray_anchor = view.carry_anchor_position()
	frame.anchors_ready = true
	return true


static func _is_seated(customer: CustomerAgent, world: SimWorld) -> bool:
	if world == null or not customer.has_arrived() or customer.cell != customer.seat_cell:
		return false
	if not [CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD,
			CustomerAgent.State.EATING, CustomerAgent.State.PAYING].has(customer.state):
		return false
	var table: PlacedItem = world.grid.item(customer.table_item_id)
	return table != null and not table.removed and table.seat_cells.has(customer.seat_cell) \
		and table.reserved_by(customer.seat_cell) == customer.id and world.grid.is_walkable(customer.seat_cell)


static func _active_task(staff: StaffAgent, world: SimWorld) -> SimTask:
	var task: SimTask = staff.task
	if world == null or task == null or task.state != SimTask.State.CLAIMED \
			or task.claimed_by != staff.id or world.board.get_task(task.id) != task:
		return null
	# Mode changes disable a task immediately; sim cleanup still owns release.
	if staff is OwnerAgent and int(staff.priorities.get(task.role, 0)) == 0:
		return null
	return task


static func _item_center(item: PlacedItem) -> Vector3:
	var center: Vector3 = Vector3.ZERO
	for cell: Vector2i in item.cells:
		center += GridMath.cell_to_world(cell)
	return center / float(item.cells.size()) if not item.cells.is_empty() else GridMath.cell_to_world(item.origin)
