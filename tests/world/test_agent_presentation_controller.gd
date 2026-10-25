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
	var seen_type: StringName = &""
	var seen_pose: Array[bool] = []
	var seen_seat: float = 0.0
	var seen_speed: float = -1.0

	func set_look(value: StringName, id: int = 0, kind: StringName = &"regular") -> bool:
		seen_role = value
		seen_id = id
		seen_type = kind
		return PersonPresentation.model_for(value, id, kind) != &""

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


func test_customer_type_reaches_person_view_without_rng_or_sim_mutation() -> void:
	var kind: CustomerType = preload("res://data/customers/types.tres").find_type(&"student")
	var guest: CustomerAgent = _restaurant.add_customer(Vector2i(2, 2), RandomNumberGenerator.new(), kind)
	var before: int = guest.rng.state
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world)
	assert_eq(frame.customer_type, &"student")
	var view: SpyPerson = SpyPerson.new()
	assert_true(AgentPresentationController.apply(frame, view, 0.0))
	assert_eq(view.seen_type, &"student")
	assert_eq(view.seen_id, guest.id)
	assert_eq(guest.rng.state, before)
	assert_eq(_world.now, 0)
	view.free()


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


func test_every_guest_state_uses_only_idle_walk_or_verified_seated_sit() -> void:
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _seated_customer(table)
	var seated_states: Array[int] = [CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD,
		CustomerAgent.State.EATING, CustomerAgent.State.PAYING]
	for state: int in range(CustomerAgent.State.LEFT + 1):
		guest.state = state as CustomerAgent.State
		guest.cell = guest.seat_cell
		guest.clear_path()
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world)
		var seated: bool = seated_states.has(state)
		assert_eq(frame.seated, seated, "only the four occupied-seat states may sit")
		assert_eq(frame.clip, &"sit" if seated else &"idle")
		assert_almost_eq(frame.seat_height, 0.27 if seated else 0.0)
		# A reservation and target lifecycle state do not prove physical arrival.
		guest.cell = Vector2i(0, 3)
		guest.path = [guest.cell, guest.seat_cell]
		guest.path_index = 1
		frame = AgentPresentationController.frame_for(guest, _world)
		assert_eq(frame.clip, &"walk")
		assert_false(frame.seated)
		assert_almost_eq(frame.seat_height, 0.0)
		guest.clear_path()
		frame = AgentPresentationController.frame_for(guest, _world)
		assert_eq(frame.clip, &"idle", "a stationary queue or stale target never selects another clip")
		assert_false(frame.seated)
		assert_almost_eq(frame.seat_height, 0.0)


func test_seated_pose_rejects_nonseat_wrong_claimant_and_unfinished_path() -> void:
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _seated_customer(table)
	var seat: Vector2i = guest.seat_cell
	# A work cell can be reserved and reached, but is not an authored seat.
	table.release(seat, guest.id)
	guest.seat_cell = Vector2i(0, 3)
	guest.cell = guest.seat_cell
	table.work_cells.append(guest.seat_cell)
	assert_true(table.reserve(guest.seat_cell, guest.id))
	assert_eq(AgentPresentationController.frame_for(guest, _world).clip, &"idle")
	table.release(guest.seat_cell, guest.id)
	guest.seat_cell = seat
	guest.cell = seat
	assert_true(table.reserve(seat, guest.id + 1))
	assert_eq(AgentPresentationController.frame_for(guest, _world).clip, &"idle")
	table.release(seat, guest.id + 1)
	assert_true(table.reserve(seat, guest.id))
	guest.path = [seat, Vector2i(0, 3)]
	guest.path_index = 1
	assert_eq(AgentPresentationController.frame_for(guest, _world).clip, &"walk")
	guest.clear_path()
	assert_eq(AgentPresentationController.frame_for(guest, _world).clip, &"sit")


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


func test_zero_seated_offset_preserves_legacy_projection_and_table_facing() -> void:
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _seated_customer(table)
	var original: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31)
	var explicit_zero: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.0)
	assert_true(original.seated)
	assert_eq(original.floor_position, GridMath.cell_to_world(guest.seat_cell))
	assert_eq(original.display_offset, Vector3.ZERO)
	assert_eq(original.facing_direction, Vector3(0.75, 0.0, -0.25), "built-in table facing remains diagonal")
	assert_eq(explicit_zero.floor_position, original.floor_position)
	assert_eq(explicit_zero.display_offset, original.display_offset)
	assert_eq(explicit_zero.facing_direction, original.facing_direction)
	assert_eq(explicit_zero.clip, original.clip)
	assert_eq(explicit_zero.seat_height, original.seat_height)
	var legacy: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(_world.agents, _world)
	var empty_options: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(_world.agents, _world, {}, {}, {})
	assert_eq(_drawn(legacy[guest.id]), original.floor_position)
	assert_eq(_drawn(empty_options[guest.id]), _drawn(legacy[guest.id]))
	# This is an API fixture distance, not an authored content-tuning value.
	var shifted: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125)
	var expected_offset: Vector3 = Vector3(3.0, 0.0, -1.0).normalized() * 0.125
	assert_true(shifted.display_offset.is_equal_approx(expected_offset))
	assert_eq(shifted.floor_position, original.floor_position)
	assert_eq(shifted.facing_direction, original.facing_direction)
	var view: SpyPerson = SpyPerson.new()
	assert_true(AgentPresentationController.apply(shifted, view, 0.0))
	assert_true(view.position.is_equal_approx(original.floor_position + expected_offset))
	assert_eq(view.seen_pose, [false, true, false, false])
	assert_almost_eq(view.seen_seat, 0.31)
	view.free()


func test_authored_seated_facing_offsets_follow_all_four_rotations_in_world_metres() -> void:
	var guest: CustomerAgent = _seated_customer(_table())
	var directions: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	var heights: Dictionary[int, float] = {guest.id: 0.31}
	var offsets: Dictionary[int, float] = {guest.id: 0.125}
	for turns: int in range(4):
		var facing: Vector3 = directions[turns] * 3.0 + Vector3.UP * 7.0
		var facings: Dictionary[int, Vector3] = {guest.id: facing}
		var single: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125, facing)
		var batch: AgentPresentationController.Frame = AgentPresentationController.frames_for(_world.agents, _world, heights, facings, offsets)[guest.id]
		for frame: AgentPresentationController.Frame in [single, batch]:
			assert_true(frame.seated)
			assert_eq(frame.floor_position, GridMath.cell_to_world(guest.seat_cell))
			assert_eq(frame.facing_direction, directions[turns] * 3.0, "authored chair front wins over the table diagonal")
			assert_true(frame.display_offset.is_equal_approx(directions[turns] * 0.125))
			assert_almost_eq(frame.display_offset.length(), 0.125, 0.000001, "offset is metres, independent of facing magnitude or art scale")
			assert_eq(frame.display_offset.y, 0.0)
			assert_almost_eq(frame.seat_height, 0.31)
		var view: SpyPerson = SpyPerson.new()
		assert_true(AgentPresentationController.apply(batch, view, 0.0))
		assert_true((-view.basis.z).normalized().dot(directions[turns]) > 0.9999)
		assert_true(view.position.is_equal_approx(GridMath.cell_to_world(guest.seat_cell) + directions[turns] * 0.125))
		view.free()


func test_seated_offsets_ignore_invalid_distances_and_unverified_seated_states() -> void:
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _seated_customer(table)
	for state: CustomerAgent.State in [CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD,
		CustomerAgent.State.EATING, CustomerAgent.State.PAYING]:
		guest.state = state
		var seated: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125, Vector3.FORWARD)
		assert_true(seated.seated)
		assert_eq(seated.display_offset, Vector3.FORWARD * 0.125)
		assert_eq(seated.clip, &"sit")
	# A finite 64-bit parameter can still overflow the native Vector3 real_t.
	for distance: float in [-0.01, NAN, INF, -INF, 1.0e100]:
		var invalid: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, distance, Vector3.FORWARD)
		assert_true(invalid.seated)
		assert_eq(invalid.display_offset, Vector3.ZERO, "invalid offsets never create a non-finite or backward position")
		assert_eq(invalid.clip, &"sit")
	for state: CustomerAgent.State in [CustomerAgent.State.ARRIVING, CustomerAgent.State.QUEUED,
		CustomerAgent.State.WALKING_TO_SEAT, CustomerAgent.State.LEAVING, CustomerAgent.State.LEFT]:
		guest.state = state
		var standing: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125, Vector3.FORWARD)
		assert_false(standing.seated)
		assert_eq(standing.display_offset, Vector3.ZERO)
	guest.state = CustomerAgent.State.WAITING_FOOD
	guest.path = [guest.cell, guest.cell + Vector2i.UP]
	guest.path_index = 1
	guest.move_progress = 0.5
	var walking: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125, Vector3.FORWARD)
	assert_true(walking.moving)
	assert_false(walking.seated)
	assert_eq(walking.display_offset, Vector3.ZERO)
	guest.clear_path()
	table.release(guest.seat_cell, guest.id)
	var unreserved: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125, Vector3.FORWARD)
	assert_false(unreserved.seated)
	assert_eq(unreserved.display_offset, Vector3.ZERO)
	var other: SimAgent = _world.add_agent(SimAgent.new())
	assert_true(table.reserve(guest.seat_cell, other.id))
	var wrong_claimant: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125, Vector3.FORWARD)
	assert_false(wrong_claimant.seated)
	assert_eq(wrong_claimant.display_offset, Vector3.ZERO)
	var worker: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	worker.cell = guest.cell
	assert_eq(AgentPresentationController.frame_for(worker, _world, 0.31, 0.125, Vector3.FORWARD).display_offset, Vector3.ZERO)


func test_invalid_or_vertical_authored_facing_uses_the_unchanged_table_direction() -> void:
	var guest: CustomerAgent = _seated_customer(_table())
	var expected: Vector3 = Vector3(3.0, 0.0, -1.0).normalized() * 0.125
	for facing: Vector3 in [Vector3(NAN, 0.0, 1.0), Vector3(1.0, 0.0, INF), Vector3.UP, Vector3.ZERO]:
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world, 0.31, 0.125, facing)
		assert_true(frame.seated)
		assert_eq(frame.facing_direction, Vector3(0.75, 0.0, -0.25))
		assert_true(frame.display_offset.is_finite())
		assert_true(frame.display_offset.is_equal_approx(expected))


func test_final_shifted_seat_blocks_earlier_standers_without_drift_or_sim_mutation() -> void:
	var first: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	var second: SimAgent = _world.add_agent(SimAgent.new())
	first.cell = Vector2i(1, 2)
	second.cell = first.cell
	first.path = [first.cell]
	first.path_index = 1
	first.move_progress = 0.25
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _seated_customer(table)
	guest._queue_wait = 11
	guest._food_wait = 17
	assert_true(guest.id > first.id and guest.id > second.id, "the seated blocker is installed before earlier standing IDs")
	var task: SimTask = _claimed_task(first, &"deliver", &"server")
	task.payload["carried_count"] = 2
	var before_payload: Dictionary = task.payload.duplicate(true)
	var before_path: Array[Vector2i] = first.path.duplicate()
	var before_reservations: Dictionary = table._reservations.duplicate()
	var before_rng: int = guest.rng.state
	var before_clock: Dictionary = _world.clock.to_dict()
	var before_log: PackedStringArray = _world.event_log.duplicate()
	var heights: Dictionary[int, float] = {guest.id: 0.31}
	var facings: Dictionary[int, Vector3] = {guest.id: Vector3.FORWARD}
	var offsets: Dictionary[int, float] = {guest.id: 0.125}
	var before_heights: Dictionary = heights.duplicate()
	var before_facings: Dictionary = facings.duplicate()
	var before_offsets: Dictionary = offsets.duplicate()
	var anchor: Vector3 = GridMath.cell_to_world(guest.seat_cell) + Vector3.FORWARD * 0.125
	assert_true(GridMath.cell_to_world(first.cell).distance_to(GridMath.cell_to_world(guest.seat_cell)) >= AgentPresentationController.MIN_STANDING_DISTANCE)
	assert_true(GridMath.cell_to_world(first.cell).distance_to(anchor) < AgentPresentationController.MIN_STANDING_DISTANCE,
		"using the old seat position would miss this standing overlap")
	var ordered: Array[SimAgent] = [first, second, guest]
	var reversed: Array[SimAgent] = [guest, second, first]
	var a: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(ordered, _world, heights, facings, offsets)
	var b: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(reversed, _world, heights, facings, offsets)
	var repeated: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(ordered, _world, heights, facings, offsets)
	assert_true(_drawn(a[guest.id]).is_equal_approx(anchor))
	assert_eq(a[guest.id].display_offset, Vector3.FORWARD * 0.125, "generic separation never moves a seated guest off its authored anchor")
	assert_false(a[guest.id].separation_blocked)
	for actor: SimAgent in ordered:
		assert_eq(a[actor.id].floor_position, b[actor.id].floor_position)
		assert_eq(a[actor.id].display_offset, b[actor.id].display_offset)
		assert_eq(a[actor.id].display_offset, repeated[actor.id].display_offset)
		if actor == guest:
			continue
		assert_true(_drawn(a[actor.id]).distance_to(anchor) >= AgentPresentationController.MIN_STANDING_DISTANCE)
		assert_true(_world.grid.is_walkable(GridMath.world_to_cell(_drawn(a[actor.id]))))
		assert_false(a[actor.id].separation_blocked)
	assert_true(_drawn(a[first.id]).distance_to(_drawn(a[second.id])) >= AgentPresentationController.MIN_STANDING_DISTANCE)
	assert_eq(first.cell, Vector2i(1, 2))
	assert_eq(second.cell, first.cell)
	assert_eq(guest.cell, guest.seat_cell)
	assert_eq(guest.state, CustomerAgent.State.WAITING_FOOD)
	assert_eq(guest._queue_wait, 11)
	assert_eq(guest._food_wait, 17)
	assert_eq(first.path, before_path)
	assert_eq(first.path_index, 1)
	assert_eq(first.move_progress, 0.25)
	assert_eq(first.task, task)
	assert_eq(_world.board.get_task(task.id), task)
	assert_eq(task.state, SimTask.State.CLAIMED)
	assert_eq(task.claimed_by, first.id)
	assert_eq(task.payload, before_payload)
	assert_eq(table._reservations, before_reservations)
	assert_eq(guest.rng.state, before_rng)
	assert_eq(_world.clock.to_dict(), before_clock)
	assert_eq(_world.event_log, before_log)
	assert_eq(_world.now, 0)
	assert_eq(heights, before_heights)
	assert_eq(facings, before_facings)
	assert_eq(offsets, before_offsets)


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
	assert_true(a[second.id].display_offset.length() > 0.0)
	assert_almost_eq((a[first.id].display_offset - a[second.id].display_offset).length(), 0.45)
	for id: int in [first.id, second.id]:
		assert_eq(a[id].display_offset, b[id].display_offset)
		assert_eq(a[id].display_offset, again[id].display_offset)
		assert_almost_eq(a[id].display_offset.y, 0.0)
		# Vector3 position addition/subtraction rounds through 32-bit real_t.
		# At this 0.75 origin the one-step offset becomes 0.450010061.
		var nudge_length: float = a[id].display_offset.length()
		assert_true(nudge_length <= AgentPresentationController.DISPLAY_NUDGE_STEP + 0.000001,
			"agent %d nudge %.9f exceeds step %.9f plus 0.000001" %
			[id, nudge_length, AgentPresentationController.DISPLAY_NUDGE_STEP])
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
	var reverse: Array[SimAgent] = standers.duplicate()
	reverse.reverse()
	var repeated: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(reverse, _world)
	for first: SimAgent in standers:
		var frame: AgentPresentationController.Frame = frames[first.id]
		assert_eq(frame.display_offset, repeated[first.id].display_offset)
		assert_true(frame.display_offset.length() <= AgentPresentationController.DISPLAY_NUDGE_STEP * float(2 * standers.size() + 1))
		assert_almost_eq(frame.display_offset.y, 0.0)
		if first == walker:
			continue
		for second: SimAgent in standers:
			if first.id >= second.id or second == walker:
				continue
			assert_true(_drawn(frames[first.id]).distance_to(_drawn(frames[second.id])) >= 0.45)
	assert_eq(table.reserved_by(customer.seat_cell), customer.id)


func test_standers_avoid_seats_even_when_seated_id_is_later_and_nudges_create_new_neighbors() -> void:
	var first: StaffAgent = _world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	var second: SimAgent = _world.add_agent(SimAgent.new())
	first.cell = Vector2i(1, 2)
	second.cell = first.cell
	var table: PlacedItem = _table()
	var guest: CustomerAgent = _seated_customer(table)
	assert_eq(guest.cell, Vector2i(1, 3))
	var agents: Array[SimAgent] = [first, second, guest]
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(agents, _world)
	assert_eq(frames[guest.id].display_offset, Vector3.ZERO)
	assert_eq(_drawn(frames[guest.id]), GridMath.cell_to_world(guest.seat_cell))
	for agent: SimAgent in [first, second]:
		assert_true(_drawn(frames[agent.id]).distance_to(_drawn(frames[guest.id])) >= 0.45)
		assert_true(_world.grid.is_walkable(GridMath.world_to_cell(_drawn(frames[agent.id]))))
		assert_false(frames[agent.id].separation_blocked)
	assert_true(_drawn(frames[first.id]).distance_to(_drawn(frames[second.id])) >= 0.45)
	first.cell = guest.cell
	second.cell = guest.cell
	frames = AgentPresentationController.frames_for(agents, _world)
	assert_eq(frames[guest.id].display_offset, Vector3.ZERO)
	for agent: SimAgent in [first, second]:
		assert_true(_drawn(frames[agent.id]).distance_to(_drawn(frames[guest.id])) >= 0.45)
	assert_eq(first.cell, guest.cell, "separation changes no simulation cell")
	assert_eq(table.reserved_by(guest.seat_cell), guest.id)


func test_infeasible_room_spacing_is_reported_without_jumping_through_a_wall() -> void:
	_world = SimWorld.new(SimGrid.from_ascii(["#####", "#.#.#", "#####"]))
	var agents: Array[SimAgent] = []
	for index: int in range(2):
		var agent: SimAgent = _world.add_agent(SimAgent.new())
		agent.cell = Vector2i(1, 1)
		agents.append(agent)
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(agents, _world)
	assert_eq(frames[agents[0].id].display_offset, Vector3.ZERO)
	assert_eq(frames[agents[1].id].display_offset, Vector3.ZERO)
	assert_false(frames[agents[0].id].separation_blocked)
	assert_true(frames[agents[1].id].separation_blocked,
		"another floor cell beyond a wall cannot justify a display teleport")
	assert_eq(agents[0].cell, Vector2i(1, 1))
	assert_eq(agents[1].cell, Vector2i(1, 1))
	assert_eq(_world.now, 0)


func test_infeasible_nudges_do_not_cross_a_solid_table_or_room_edge() -> void:
	_world = SimWorld.new(SimGrid.from_ascii(["#####", "#...#", "#####"]))
	var definition: ItemDef = ItemDef.new()
	definition.id = &"solid_table_test"
	definition.category = ItemDef.Category.TABLE
	definition.footprint = Vector2i.ONE
	var table: PlacedItem = _world.grid.place_def(definition, Vector2i(2, 1))
	assert_not_null(table)
	assert_false(_world.grid.is_walkable(Vector2i(2, 1)))
	var agents: Array[SimAgent] = []
	for index: int in range(2):
		var agent: SimAgent = _world.add_agent(SimAgent.new())
		agent.cell = Vector2i(1, 1)
		agents.append(agent)
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(agents, _world)
	assert_eq(frames[agents[1].id].display_offset, Vector3.ZERO)
	assert_true(frames[agents[1].id].separation_blocked)
	assert_eq(_world.grid.item_at(Vector2i(2, 1)), table)
	assert_true(table._reservations.is_empty())
	assert_eq(_world.now, 0)


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
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var scene: PackedScene = preload("res://assets/people/person.tscn")
	var view: PersonView = scene.instantiate() as PersonView
	# Enter with an unsupported role so this synthetic rig loads no kit model.
	view.role = &"anchor_test_fixture"
	tree.root.add_child(view)
	assert_true(view.is_inside_tree())
	var pivot: Node3D = view.get_node("ModelPivot") as Node3D
	pivot.scale = Vector3.ONE * ArtScale.CHARACTER_SCALE
	pivot.position.y = 0.27
	var skeleton: Skeleton3D = Skeleton3D.new()
	pivot.add_child(skeleton)
	assert_true(skeleton.is_inside_tree(), "bone setters invalidate global pose caches only inside the tree")
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
	assert_almost_eq(skeleton.get_bone_global_pose(1).origin.y, 0.20)
	assert_almost_eq(view.head_anchor_position().y, 0.27 + (0.671325 - 0.14325) * ArtScale.CHARACTER_SCALE)
	# The hat's band begins above the male-b head mesh, in head-bone space.
	var band: MeshInstance3D = view.get_node("ChefHat/Band") as MeshInstance3D
	assert_true(0.34325 + band.position.y - (band.mesh as CylinderMesh).height * 0.5 >= 0.661325)
	view.free()


func _customer() -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	return _world.add_agent(CustomerAgent.new(_restaurant, random)) as CustomerAgent


func _drawn(frame: AgentPresentationController.Frame) -> Vector3:
	return frame.floor_position + frame.display_offset


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
