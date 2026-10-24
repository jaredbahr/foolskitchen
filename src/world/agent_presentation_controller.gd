class_name AgentPresentationController
extends RefCounted
## Read-only bridge from existing sim state to PersonView. No agents are retained.
## ShopView supplies nodes later; this helper owns no scene or sim lifecycle.

const NOMINAL_CHAIR_SEAT_HEIGHT: float = 0.27
const MIN_STANDING_DISTANCE: float = 0.45
const MAX_DISPLAY_NUDGE: float = MIN_STANDING_DISTANCE * 0.5
const MOOD_CLEARANCE: float = 0.10

class Frame extends RefCounted:
	var id: int = 0
	var role: StringName = &""
	var look_supported: bool = false
	var floor_position: Vector3 = Vector3.ZERO
	var display_offset: Vector3 = Vector3.ZERO
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
static func frame_for(agent: SimAgent, world: SimWorld, chair_seat_height: float = NOMINAL_CHAIR_SEAT_HEIGHT) -> Frame:
	var frame: Frame = Frame.new()
	frame.id = agent.id
	frame.role = agent.role
	frame.look_supported = PersonPresentation.model_for(agent.role, agent.id) != &""
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
static func frames_for(agents: Array[SimAgent], world: SimWorld, chair_heights: Dictionary[int, float] = {}) -> Dictionary[int, Frame]:
	var frames: Dictionary[int, Frame] = {}
	var ids: Array[int] = []
	for agent: SimAgent in agents:
		frames[agent.id] = frame_for(agent, world, chair_heights.get(agent.id, NOMINAL_CHAIR_SEAT_HEIGHT))
		ids.append(agent.id)
	ids.sort()
	for first_index: int in range(ids.size()):
		var first: Frame = frames[ids[first_index]]
		if first.moving or first.seated:
			continue
		for second_index: int in range(first_index + 1, ids.size()):
			var second: Frame = frames[ids[second_index]]
			if second.moving or second.seated:
				continue
			var difference: Vector3 = first.floor_position - second.floor_position
			var distance: float = difference.length()
			if distance >= MIN_STANDING_DISTANCE:
				continue
			var direction: Vector3 = difference / distance if distance > 0.000001 else _tie_direction(first.id, second.id)
			var push: Vector3 = direction * ((MIN_STANDING_DISTANCE - distance) * 0.5)
			first.display_offset += push
			second.display_offset -= push
	for id: int in ids:
		var frame: Frame = frames[id]
		frame.display_offset = frame.display_offset.limit_length(MAX_DISPLAY_NUDGE)
	return frames


## False asks the caller to retain an explicit unsupported-role fallback.
## It does not choose a substitute model (notably for the unapproved Cleaner).
static func apply(frame: Frame, view: PersonView, playback_speed: float) -> bool:
	view.position = frame.floor_position + frame.display_offset
	view.face_direction(frame.facing_direction)
	view.set_playback_speed(playback_speed)
	frame.anchors_ready = false
	if not frame.look_supported:
		view.set_look(frame.role, frame.id)
		return false
	if not view.set_look(frame.role, frame.id):
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


static func _tie_direction(first_id: int, second_id: int) -> Vector3:
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]
	return directions[posmod(posmod(first_id, 4) + posmod(second_id, 4), 4)]
