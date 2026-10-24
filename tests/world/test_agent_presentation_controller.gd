extends TestCase
## Source-authored regressions. They do not import Kenney models or render pixels.

var _world: SimWorld
var _restaurant: RestaurantSim

class PredicateCounter extends RefCounted:
	var calls: int = 0

	func check(_agent: SimAgent) -> bool:
		calls += 1
		return true

class SpyPerson extends PersonView:
	var seen_role: StringName = &""
	var seen_id: int = 0
	var seen_pose: Array[bool] = []
	var seen_seat: float = 0.0
	var seen_speed: float = -1.0

	func set_look(value: StringName, id: int = 0) -> bool:
		seen_role = value
		seen_id = id
		return PersonPresentation.model_for(value, id) != &""

	func set_pose(moving: bool, seated: bool, carrying: bool, working: bool, seat_height: float = 0.0) -> bool:
		seen_pose = [moving, seated, carrying, working]
		seen_seat = seat_height
		return true

	func set_playback_speed(value: float) -> void:
		seen_speed = value

	func head_anchor_position() -> Vector3:
		return Vector3(0.0, 0.8 + seen_seat, 0.0)

	func carry_anchor_position() -> Vector3:
		return Vector3(0.0, 0.4 + seen_seat, -0.2)


func before_each() -> void:
	_world = SimWorld.new(SimGrid.from_ascii([
		".......", ".......", ".......", ".......", ".......", ".......", ".......",
	]))
	_restaurant = RestaurantSim.new()
	_restaurant.world = _world


func after_each() -> void:
	_restaurant = null
	_world = null


func test_interpolation_and_facing_read_existing_path_without_advancing() -> void:
	var agent: SimAgent = _world.add_agent(SimAgent.new())
	agent.cell = Vector2i(1, 1)
	agent.path = [agent.cell, Vector2i(2, 1)]
	agent.path_index = 1
	agent.move_progress = 0.25
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(agent, _world)
	assert_eq(frame.floor_position, Vector3(0.875, 0.0, 0.75))
	assert_eq(frame.facing_direction, Vector3(0.5, 0.0, 0.0))
	assert_true(frame.moving)
	assert_eq(frame.clip, &"walk")
	assert_eq(agent.cell, Vector2i(1, 1))
	assert_almost_eq(agent.move_progress, 0.25)
	agent.move_progress = -2.0
	assert_eq(AgentPresentationController.frame_for(agent, _world).floor_position, GridMath.cell_to_world(agent.cell))
	agent.move_progress = 2.0
	assert_eq(AgentPresentationController.frame_for(agent, _world).floor_position, GridMath.cell_to_world(Vector2i(2, 1)))
	assert_almost_eq(agent.move_progress, 2.0)


func test_reserved_guest_only_sits_after_actual_seat_arrival() -> void:
	var table: PlacedItem = _table()
	var customer: CustomerAgent = _customer()
	customer.table_item_id = table.id
	customer.seat_cell = table.seat_cells[0]
	assert_true(table.reserve(customer.seat_cell, customer.id))
	customer.cell = Vector2i(0, 3)
	customer.path = [customer.cell, customer.seat_cell]
	customer.path_index = 1
	customer.state = CustomerAgent.State.WALKING_TO_SEAT
	assert_false(AgentPresentationController.frame_for(customer, _world).seated)
	# An early target-state projection is also insufficient while still walking.
	customer.state = CustomerAgent.State.ORDERING
	assert_false(AgentPresentationController.frame_for(customer, _world).seated)
	customer.cell = customer.seat_cell
	customer.clear_path()
	for state: CustomerAgent.State in [CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD,
			CustomerAgent.State.EATING, CustomerAgent.State.PAYING]:
		customer.state = state
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(customer, _world, 0.31)
		assert_true(frame.seated)
		assert_eq(frame.clip, &"sit")
		assert_almost_eq(frame.seat_height, 0.31)
		assert_true(frame.facing_direction.x > 0.0)
		assert_eq(frame.floor_position, GridMath.cell_to_world(customer.seat_cell))
		assert_eq(frame.mood_visible, CustomerAgent.MOOD_WAITING_STATES.has(int(state)))


func test_departure_and_lost_or_removed_seat_never_leave_a_sitting_guest() -> void:
	var table: PlacedItem = _table()
	var customer: CustomerAgent = _seated_customer(table)
	customer.state = CustomerAgent.State.LEAVING
	assert_false(AgentPresentationController.frame_for(customer, _world).seated)
	customer.state = CustomerAgent.State.WAITING_FOOD
	table.release(customer.seat_cell, customer.id)
	assert_false(AgentPresentationController.frame_for(customer, _world).seated)
	assert_true(table.reserve(customer.seat_cell, customer.id))
	_world.grid.remove(table.id)
	assert_false(AgentPresentationController.frame_for(customer, _world).seated)


func test_only_started_claimed_work_plays_station_animation_without_calling_waits() -> void:
	var worker: StaffAgent = _world.add_agent(StaffAgent.new(&"cook")) as StaffAgent
	var task: SimTask = _claimed_task(worker, &"cook", &"cook")
	task.steps = [TaskStep.work(10)]
	worker.work_left = 5.0
	worker._step_started = false
	assert_false(AgentPresentationController.frame_for(worker, _world).working)
	worker._step_started = true
	assert_eq(AgentPresentationController.frame_for(worker, _world).clip, &"interact-right")
	var counter: PredicateCounter = PredicateCounter.new()
	task.steps = [TaskStep.wait_until(counter.check, "Waiting for a plate")]
	assert_eq(AgentPresentationController.frame_for(worker, _world).clip, &"idle")
	assert_eq(counter.calls, 0)
	worker.step_index = task.steps.size()
	assert_false(AgentPresentationController.frame_for(worker, _world).working)
	worker.step_index = -1
	assert_false(AgentPresentationController.frame_for(worker, _world).working)
	worker.step_index = 0
	task.steps = [TaskStep.work(10)]
	_world.board.cancel(task)
	assert_false(AgentPresentationController.frame_for(worker, _world).working)
	assert_eq(counter.calls, 0)


func test_delivery_pose_uses_picked_up_count_and_preserves_tray_threshold() -> void:
	var worker: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	var task: SimTask = _claimed_task(worker, &"deliver", &"server")
	assert_false(AgentPresentationController.frame_for(worker, _world).carrying)
	task.payload["carried_count"] = 2
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(worker, _world)
	assert_true(frame.carrying)
	assert_true(frame.show_tray)
	assert_eq(frame.clip, &"holding-both")
	task.payload["carried_count"] = 1
	frame = AgentPresentationController.frame_for(worker, _world)
	assert_true(frame.carrying)
	assert_false(frame.show_tray)
	task.payload["carried_count"] = 0
	assert_false(AgentPresentationController.frame_for(worker, _world).carrying)
	task.payload["carried_count"] = 2
	task.claimed_by = worker.id + 1
	assert_false(AgentPresentationController.frame_for(worker, _world).carrying)
	task.claimed_by = worker.id
	_world.board.cancel(task)
	assert_false(AgentPresentationController.frame_for(worker, _world).carrying)


func test_work_facing_ignores_a_released_pass_bookkeeping_reference() -> void:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"pass"
	definition.category = ItemDef.Category.PASS
	definition.work_cells = [Vector2i(-1, 0)]
	var item: PlacedItem = _world.grid.place_def(definition, Vector2i(4, 1))
	var worker: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	worker.cell = item.work_cells[0]
	worker._held_item_id = item.id
	worker._held_cell = worker.cell
	assert_true(item.reserve(worker.cell, worker.id))
	var task: SimTask = _claimed_task(worker, &"deliver", &"server")
	task.steps = [TaskStep.work(10)]
	worker._step_started = true
	worker.work_left = 5.0
	assert_true(AgentPresentationController.frame_for(worker, _world).facing_direction.x > 0.0)
	item.release(worker.cell, worker.id)
	assert_eq(AgentPresentationController.frame_for(worker, _world).facing_direction, Vector3.ZERO)
	worker.cell = Vector2i(1, 3)
	# Delivery deliberately retains the old held-item fields after pass release.
	assert_eq(AgentPresentationController.frame_for(worker, _world).facing_direction, Vector3.ZERO)
	assert_eq(worker._held_item_id, item.id)


func test_owner_reassignment_suppresses_stale_task_but_rest_can_walk_home() -> void:
	var owner: OwnerAgent = _world.add_agent(OwnerAgent.new(Vector2i(1, 1))) as OwnerAgent
	assert_true(owner.assign_mode(&"floor"))
	var task: SimTask = _claimed_task(owner, &"deliver", &"server")
	task.payload["carried_count"] = 2
	assert_true(AgentPresentationController.frame_for(owner, _world).carrying)
	assert_true(owner.assign_mode(&"kitchen"))
	assert_false(AgentPresentationController.frame_for(owner, _world).carrying)
	assert_eq(owner.task, task)
	assert_eq(task.state, SimTask.State.CLAIMED)
	assert_eq(task.payload["carried_count"], 2)
	assert_true(owner.assign_mode(&"rest"))
	assert_false(AgentPresentationController.frame_for(owner, _world).carrying)
	owner.task = null
	owner.cell = Vector2i(2, 1)
	owner.path = [owner.cell, owner.home_cell()]
	owner.path_index = 1
	assert_eq(AgentPresentationController.frame_for(owner, _world).clip, &"walk")


func test_display_nudges_are_stable_bounded_and_independent_of_input_order() -> void:
	var first: SimAgent = _world.add_agent(SimAgent.new())
	var second: SimAgent = _world.add_agent(SimAgent.new())
	first.cell = Vector2i(1, 1)
	second.cell = first.cell
	var forward: Array[SimAgent] = [first, second]
	var backward: Array[SimAgent] = [second, first]
	var a: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(forward, _world)
	var b: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(backward, _world)
	var again: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(forward, _world)
	assert_true(a[first.id].display_offset.length() > 0.0)
	assert_almost_eq((a[first.id].display_offset - a[second.id].display_offset).length(), 0.45)
	for id: int in [first.id, second.id]:
		assert_eq(a[id].display_offset, b[id].display_offset)
		assert_eq(a[id].display_offset, again[id].display_offset)
		assert_almost_eq(a[id].display_offset.y, 0.0)
		assert_true(a[id].display_offset.length() <= AgentPresentationController.MAX_DISPLAY_NUDGE + 0.00001)
	assert_eq(first.cell, second.cell)
	second.cell = Vector2i(2, 1)
	a = AgentPresentationController.frames_for(forward, _world)
	assert_eq(a[first.id].display_offset, Vector3.ZERO)
	assert_eq(a[second.id].display_offset, Vector3.ZERO)


func test_moving_and_seated_people_stay_anchored_and_dense_groups_remain_bounded() -> void:
	var table: PlacedItem = _table()
	var customer: CustomerAgent = _seated_customer(table)
	var walker: SimAgent = _world.add_agent(SimAgent.new())
	walker.cell = customer.cell
	walker.path = [walker.cell, Vector2i(0, 3)]
	walker.path_index = 1
	var standers: Array[SimAgent] = [customer, walker]
	for index: int in range(6):
		var agent: SimAgent = _world.add_agent(SimAgent.new())
		agent.cell = customer.cell
		standers.append(agent)
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(standers, _world)
	assert_eq(frames[customer.id].display_offset, Vector3.ZERO)
	assert_eq(frames[walker.id].display_offset, Vector3.ZERO)
	for frame: AgentPresentationController.Frame in frames.values():
		assert_true(frame.display_offset.length() <= AgentPresentationController.MAX_DISPLAY_NUDGE + 0.00001)


func test_sampling_preserves_paths_tasks_reservations_world_and_guest_rng() -> void:
	var table: PlacedItem = _table()
	var customer: CustomerAgent = _seated_customer(table)
	var worker: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	worker.cell = Vector2i(0, 1)
	worker.path = [worker.cell, Vector2i(1, 1)]
	worker.path_index = 1
	worker.move_progress = 0.5
	var task: SimTask = _claimed_task(worker, &"deliver", &"server")
	task.payload["carried_count"] = 2
	var before_path: Array[Vector2i] = worker.path.duplicate()
	var before_payload: Dictionary = task.payload.duplicate(true)
	var before_rng: int = customer.rng.state
	var before_log: PackedStringArray = _world.event_log.duplicate()
	var before_now: int = _world.now
	AgentPresentationController.frames_for(_world.agents, _world)
	assert_eq(worker.path, before_path)
	assert_eq(worker.path_index, 1)
	assert_almost_eq(worker.move_progress, 0.5)
	assert_eq(worker.task, task)
	assert_eq(task.payload, before_payload)
	assert_eq(task.state, SimTask.State.CLAIMED)
	assert_eq(task.claimed_by, worker.id)
	assert_eq(table.reserved_by(customer.seat_cell), customer.id)
	assert_eq(customer.rng.state, before_rng)
	assert_eq(_world.event_log, before_log)
	assert_eq(_world.now, before_now)


func test_apply_passes_real_pose_and_local_attachment_anchors_to_person_api() -> void:
	var table: PlacedItem = _table()
	var customer: CustomerAgent = _seated_customer(table)
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(customer, _world, 0.31)
	var view: SpyPerson = SpyPerson.new()
	assert_true(AgentPresentationController.apply(frame, view, 0.0))
	assert_eq(view.seen_role, &"customer")
	assert_eq(view.seen_id, customer.id)
	assert_eq(view.seen_pose, [false, true, false, false])
	assert_almost_eq(view.seen_seat, 0.31)
	assert_almost_eq(view.seen_speed, 0.0)
	assert_eq(view.position, frame.floor_position)
	assert_true(frame.anchors_ready)
	assert_eq(frame.head_anchor, Vector3(0.0, 1.11, 0.0))
	assert_eq(frame.mood_anchor, frame.head_anchor + Vector3.UP * AgentPresentationController.MOOD_CLEARANCE)
	assert_eq(frame.tray_anchor, Vector3(0.0, 0.71, -0.2))
	view.free()


func test_cleaner_returns_explicit_fallback_without_assigning_a_new_model() -> void:
	var cleaner: StaffAgent = _world.add_agent(StaffAgent.new(&"cleaner")) as StaffAgent
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(cleaner, _world)
	assert_false(frame.look_supported)
	var view: SpyPerson = SpyPerson.new()
	assert_false(AgentPresentationController.apply(frame, view, 1.0))
	assert_eq(view.seen_role, &"cleaner")
	assert_eq(view.seen_pose.size(), 0)
	assert_false(frame.anchors_ready)
	view.free()


func test_head_and_hand_anchors_include_rig_pose_seat_lift_and_shared_scale() -> void:
	var scene: PackedScene = preload("res://assets/people/person.tscn")
	var view: PersonView = scene.instantiate() as PersonView
	var pivot: Node3D = view.get_node("ModelPivot") as Node3D
	pivot.scale = Vector3.ONE * ArtScale.CHARACTER_SCALE
	pivot.position.y = 0.27
	var skeleton: Skeleton3D = Skeleton3D.new()
	pivot.add_child(skeleton)
	for bone: String in ["root", "head", "arm-left", "arm-right"]:
		skeleton.add_bone(bone)
	for index: int in range(1, 4):
		skeleton.set_bone_parent(index, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.34325, 0.0)))
	skeleton.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0.1, 0.28775, -0.01725)))
	skeleton.set_bone_rest(3, Transform3D(Basis.IDENTITY, Vector3(-0.1, 0.28775, -0.01725)))
	skeleton.reset_bone_poses()
	view._skeleton = skeleton
	view._model_name = PersonPresentation.OWNER_MODEL
	assert_almost_eq(view.head_anchor_position().y, 0.27 + 0.671325 * ArtScale.CHARACTER_SCALE)
	var hands: Vector3 = view.carry_anchor_position()
	assert_almost_eq(hands.x, 0.0)
	assert_almost_eq(hands.y, 0.27 + 0.28775 * ArtScale.CHARACTER_SCALE)
	assert_almost_eq(hands.z, 0.01725 * ArtScale.CHARACTER_SCALE)
	skeleton.set_bone_pose_position(1, Vector3(0.0, 0.20, 0.0))
	assert_almost_eq(view.head_anchor_position().y, 0.27 + (0.671325 - 0.14325) * ArtScale.CHARACTER_SCALE)
	# The hat's band begins above the male-b head mesh, in head-bone space.
	var band: MeshInstance3D = view.get_node("ChefHat/Band") as MeshInstance3D
	assert_true(0.34325 + band.position.y - (band.mesh as CylinderMesh).height * 0.5 >= 0.661325)
	view.free()


func _customer() -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	return _world.add_agent(CustomerAgent.new(_restaurant, random)) as CustomerAgent


func _table() -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"table_2"
	definition.category = ItemDef.Category.TABLE
	definition.footprint = Vector2i(2, 2)
	definition.seat_cells = [Vector2i(-1, 1), Vector2i(2, 1)]
	return _world.grid.place_def(definition, Vector2i(2, 2))


func _seated_customer(table: PlacedItem) -> CustomerAgent:
	var customer: CustomerAgent = _customer()
	customer.table_item_id = table.id
	customer.seat_cell = table.seat_cells[0]
	customer.cell = customer.seat_cell
	customer.state = CustomerAgent.State.WAITING_FOOD
	assert_true(table.reserve(customer.seat_cell, customer.id))
	return customer


func _claimed_task(worker: StaffAgent, kind: StringName, task_role: StringName) -> SimTask:
	var task: SimTask = SimTask.new(kind, task_role)
	_world.board.post(task, _world.now)
	assert_true(_world.board.claim(task, worker.id, _world.now))
	worker.task = task
	return task
