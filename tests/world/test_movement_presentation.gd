extends TestCase
## Pure presentation regressions. Native pixel acceptance remains a separate gate.

class QuickWalker extends SimAgent:
	func _init() -> void:
		role = &"server"
		move_speed = 1.15

	func movement_multiplier() -> float:
		return 1.15

	func tick(world: SimWorld) -> void:
		step_move(world)


func test_actual_quick_turn_uses_each_crossed_centre_and_never_cuts_the_solid_corner() -> void:
	var world: SimWorld = _world()
	var solid: ItemDef = ItemDef.new()
	solid.id = &"corner_fixture"
	solid.category = ItemDef.Category.TABLE
	solid.footprint = Vector2i.ONE
	solid.solid = true
	assert_not_null(world.grid.place_def(solid, Vector2i(1, 2)))
	var walker: QuickWalker = QuickWalker.new()
	walker.cell = Vector2i(1, 1)
	world.add_agent(walker)
	walker.install_movement_route([Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)])
	walker.move_progress = 0.25
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(walker.id, world.now, AgentPresentationController.frame_for(walker, world))
	world.advance()
	var trace: Dictionary = walker.movement_trace()
	var points: Array[Vector3] = []
	points.assign(trace["points"])
	var times: Array[float] = []
	times.assign(trace["times"])
	assert_true(points.size() >= 3, "the production move crosses a centre and continues on the next edge")
	assert_eq(points[0], Vector3(0.875, 0.0, 0.75))
	assert_eq(points[1], GridMath.cell_to_world(Vector2i(2, 1)))
	assert_almost_eq(times[1], 0.75 / 1.15, 0.000001, "actual Quick budget sets the turning time")
	assert_eq(times[0], 0.0)
	assert_eq(times[-1], 1.0)
	var before: Dictionary = {"trace": walker.movement_trace(), "cell": walker.cell,
		"path": walker.path.duplicate(), "progress": walker.move_progress,
		"clock": world.clock.to_dict(), "now": world.now, "events": world.event_log.duplicate()}
	motion.observe(walker.id, world.now, AgentPresentationController.frame_for(walker, world))
	var corner: Rect2 = Rect2(Vector2(0.5, 1.0), Vector2(0.5, 0.5))
	var radius: float = AgentPresentationController.MIN_STANDING_DISTANCE * 0.5
	assert_true(_distance_to_rect(points[0].lerp(points[-1], 0.5), corner) < radius,
		"a straight endpoint blend would clip this same solid corner")
	for index: int in range(41):
		var alpha: float = float(index) / 40.0
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(walker, world)
		motion.blend(walker.id, alpha, frame)
		var point: Vector3 = frame.floor_position + frame.display_offset
		assert_true(_distance_to_rect(point, corner) >= radius - 0.00001,
			"sample %d keeps the drawn footprint out of the solid corner" % index)
		if alpha < times[1]:
			assert_almost_eq(point.z, points[0].z, 0.00001)
		else:
			assert_almost_eq(point.x, points[1].x, 0.00001)
	assert_eq(walker.movement_trace(), before["trace"])
	assert_eq(walker.cell, before["cell"])
	assert_eq(walker.path, before["path"])
	assert_eq(walker.move_progress, before["progress"])
	assert_eq(world.clock.to_dict(), before["clock"])
	assert_eq(world.now, before["now"])
	assert_eq(world.event_log, before["events"])


func test_skipped_render_ticks_use_the_latest_route_and_its_times_not_an_endpoint_chord() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	var initial: AgentPresentationController.Frame = _trace_frame(1,
		[Vector3.ZERO, Vector3.ZERO], [0.0, 1.0])
	motion.observe(1, 1, initial)
	var points: Array[Vector3] = [Vector3(2.25, 0.0, 2.25), Vector3(2.75, 0.0, 2.25),
		Vector3(2.75, 0.0, 2.75)]
	var frame: AgentPresentationController.Frame = _trace_frame(4, points, [0.0, 0.25, 1.0])
	motion.observe(1, 4, frame)
	# Mutating the detached caller frame cannot redirect an observed route.
	(frame.movement_trace["points"] as Array)[1] = Vector3(-100.0, 0.0, -100.0)
	for alpha: float in [0.0, 0.125, 0.25, 0.625, 1.0]:
		var drawn: AgentPresentationController.Frame = _trace_frame(4, points, [0.0, 0.25, 1.0])
		motion.blend(1, alpha, drawn)
		var expected: Vector3 = points[0].lerp(points[1], alpha / 0.25) if alpha <= 0.25 \
			else points[1].lerp(points[2], (alpha - 0.25) / 0.75)
		assert_true(drawn.floor_position.is_equal_approx(expected))
		if alpha > 0.25 and alpha < 1.0:
			assert_true(drawn.facing_direction.normalized().is_equal_approx(Vector3.BACK))


func test_missing_stale_discontinuous_or_malformed_runtime_traces_snap_without_guessing() -> void:
	var points: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT * 0.5]
	var invalid: Array[Dictionary] = [{}, {"tick": 1, "points": points, "times": [0.0, 1.0], "discontinuous": false},
		{"tick": 2, "points": points, "times": [0.0, 1.0], "discontinuous": true},
		{"tick": 2, "points": points, "times": [0.0, NAN], "discontinuous": false},
		{"tick": 2, "points": points, "times": [0.5, 1.0], "discontinuous": false},
		{"tick": 2, "points": points, "times": [0.0, 0.0], "discontinuous": false},
		{"tick": 2, "points": [Vector3.ZERO, Vector3(99, 0, 0)], "times": [0.0, 1.0], "discontinuous": false}]
	for trace: Dictionary in invalid:
		var motion: MotionSmoother = MotionSmoother.new()
		motion.observe(1, 1, _trace_frame(1, [Vector3.ZERO, Vector3.ZERO], [0.0, 1.0]))
		var current: AgentPresentationController.Frame = _trace_frame(2, points, [0.0, 1.0])
		current.movement_trace = trace.duplicate(true)
		motion.observe(1, 2, current)
		motion.blend(1, 0.25, current)
		assert_eq(current.floor_position, points[-1], "invalid runtime trace must not become legacy interpolation")
		assert_false(motion.blending(1))


func test_trace_terminal_hold_is_idle_and_new_tick_refresh_does_not_restart_the_route() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 0, _trace_frame(0, [Vector3.ZERO, Vector3.ZERO], [0.0, 1.0]))
	var points: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT * 0.5, Vector3.RIGHT * 0.5]
	motion.observe(1, 1, _trace_frame(1, points, [0.0, 0.5, 1.0]))
	motion.observe(1, 1, _trace_frame(1, points, [0.0, 0.5, 1.0]))
	var moving: AgentPresentationController.Frame = _trace_frame(1, points, [0.0, 0.5, 1.0])
	motion.blend(1, 0.25, moving)
	assert_true(moving.moving)
	assert_eq(moving.clip, &"walk")
	assert_eq(moving.floor_position, Vector3.RIGHT * 0.25)
	var held: AgentPresentationController.Frame = _trace_frame(1, points, [0.0, 0.5, 1.0])
	motion.blend(1, 0.75, held)
	assert_false(held.moving)
	assert_eq(held.clip, &"idle")
	assert_eq(held.floor_position, points[-1])
	motion.settle(1)
	assert_false(motion.blending(1))


func test_hidden_transitions_snap_even_when_rendering_skips_ticks_or_repeats_a_tick() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	var hidden: AgentPresentationController.Frame = _trace_frame(0, [Vector3.ZERO, Vector3.ZERO], [0.0, 1.0])
	hidden.hidden = true
	motion.observe(1, 0, hidden)
	var points: Array[Vector3] = [Vector3.RIGHT * 0.5, Vector3.RIGHT]
	var shown: AgentPresentationController.Frame = _trace_frame(3, points, [0.0, 1.0])
	motion.observe(1, 3, shown)
	motion.blend(1, 0.25, shown)
	assert_eq(shown.floor_position, points[-1], "a person shown again does not replay an unseen walk")
	assert_false(motion.blending(1))
	hidden = _trace_frame(3, points, [0.0, 1.0])
	hidden.hidden = true
	motion.observe(1, 3, hidden)
	shown = _trace_frame(3, points, [0.0, 1.0])
	motion.observe(1, 3, shown)
	motion.blend(1, 0.25, shown)
	assert_eq(shown.floor_position, points[-1])
	assert_false(motion.blending(1))


func test_traced_seat_arrival_walks_to_its_cell_before_using_the_authored_seat_offset() -> void:
	var seat: Vector3 = Vector3(1.25, 0.0, 1.25)
	var start: Vector3 = seat - Vector3.RIGHT * 0.125
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 0, _trace_frame(0, [start, start], [0.0, 1.0]))
	var seated: AgentPresentationController.Frame = _trace_frame(1, [start, seat], [0.0, 1.0])
	seated.seated = true
	seated.seat_height = 0.27
	seated.display_offset = Vector3.BACK * 0.04
	motion.observe(1, 1, seated)
	motion.blend(1, 0.5, seated)
	assert_false(seated.seated)
	assert_eq(seated.seat_height, 0.0)
	assert_true(seated.moving)
	assert_eq(seated.floor_position, start.lerp(seat, 0.5))
	assert_eq(seated.display_offset, Vector3.ZERO)
	var final: AgentPresentationController.Frame = _trace_frame(1, [start, seat], [0.0, 1.0])
	final.seated = true
	final.display_offset = Vector3.BACK * 0.04
	motion.blend(1, 1.0, final)
	assert_true(final.seated)
	assert_eq(final.floor_position, seat)
	assert_eq(final.display_offset, Vector3.BACK * 0.04)


func test_skipped_render_ticks_stand_through_the_walk_and_sit_only_on_actual_arrival() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 0, _trace_frame(0, [Vector3.ZERO, Vector3.ZERO], [0.0, 1.0]))
	var points: Array[Vector3] = [Vector3(1.25, 0.0, 0.75), Vector3(1.75, 0.0, 0.75),
		Vector3(1.75, 0.0, 1.25), Vector3(1.75, 0.0, 1.25)]
	var times: Array[float] = [0.0, 0.4, 0.8, 1.0]
	var latest: AgentPresentationController.Frame = _trace_frame(3, points, times)
	latest.seated = true
	latest.seat_height = 0.27
	latest.display_offset = Vector3.BACK * 0.04
	motion.observe(1, 3, latest)
	for alpha: float in [0.0, 0.25, 0.6, 0.8, 0.9]:
		var frame: AgentPresentationController.Frame = _trace_frame(3, points, times)
		frame.seated = true
		frame.seat_height = 0.27
		frame.display_offset = Vector3.BACK * 0.04
		motion.blend(1, alpha, frame)
		if alpha < 0.8:
			assert_false(frame.seated, "a final seated pose cannot slide along the unseen walk")
			assert_eq(frame.seat_height, 0.0)
			assert_eq(frame.display_offset, Vector3.ZERO)
			assert_true(frame.moving)
			assert_eq(frame.clip, &"walk")
		else:
			assert_true(frame.seated, "the terminal hold starts after actual seat arrival")
			assert_eq(frame.seat_height, 0.27)
			assert_eq(frame.floor_position, points[-1])
			assert_true(frame.display_offset.distance_to(Vector3.BACK * 0.04) <= 0.000001,
				"the authored seat offset stays within one micrometre after Vector3 subtraction")
			assert_false(frame.moving)
			assert_eq(frame.clip, &"sit")


func test_active_trace_copies_are_detached_and_pending_requests_have_no_drawn_occupancy() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(["###", "#.#", "###"]))
	var active: SimAgent = SimAgent.new()
	active.cell = Vector2i(1, 1)
	world.add_agent(active)
	var pending: SimAgent = SimAgent.new()
	pending.cell = active.cell
	world.add_agent(pending)
	assert_true(active.movement_admitted)
	assert_false(pending.movement_admitted)
	assert_false(world.agents.has(pending))
	assert_true(world.pending_agents().has(pending))
	assert_true(AgentPresentationController.frame_for(pending, world).hidden)
	world.advance()
	var before: Dictionary = active.movement_trace()
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(active, world)
	assert_true(frame.movement_trace_expected)
	assert_eq(frame.sim_floor_position, GridMath.cell_to_world(active.cell))
	(frame.movement_trace["points"] as Array).clear()
	assert_eq(active.movement_trace(), before)
	assert_false(frame.moving, "a held route or idle cell does not animate a walk without actual movement")


func test_stationary_nudges_avoid_moving_people_and_interior_edge_walls() -> void:
	var world: SimWorld = _world()
	var first: SimAgent = SimAgent.new()
	first.cell = Vector2i(1, 1)
	world.add_agent(first)
	var second: SimAgent = SimAgent.new()
	second.cell = Vector2i(1, 2)
	world.add_agent(second)
	assert_true(first.movement_admitted and second.movement_admitted)
	# Explicit legacy overlap fixture: normal admission itself never overlaps.
	second.cell = first.cell
	var moving: SimAgent = SimAgent.new()
	moving.cell = Vector2i(2, 1)
	world.add_agent(moving)
	moving.install_movement_route([moving.cell, Vector2i(3, 1)])
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(
		[first, second, moving], world)
	for actor: SimAgent in [first, second]:
		assert_true(_drawn(frames[actor.id]).distance_to(_drawn(frames[moving.id])) \
			>= AgentPresentationController.MIN_STANDING_DISTANCE)
	assert_eq(frames[moving.id].display_offset, Vector3.ZERO)
	assert_true(world.grid.set_segment(SimGrid.edge_between(first.cell, Vector2i(2, 1)), SimGrid.Segment.WALL))
	frames = AgentPresentationController.frames_for([first, second], world)
	var drawn: Vector3 = _drawn(frames[second.id])
	assert_true(drawn.x <= GridMath.cell_to_world(first.cell).x,
		"a walkable cell across an interior edge wall cannot justify a rightward nudge")
	assert_false(frames[second.id].separation_blocked)
	assert_eq(first.cell, second.cell)


func test_postblend_offsets_cannot_sweep_through_another_person_to_a_free_endpoint() -> void:
	var world: SimWorld = _world()
	var first: AgentPresentationController.Frame = _plain_frame(Vector3(0.75, 0.0, 0.75))
	first.display_offset = Vector3.RIGHT * 1.2
	var blocker: AgentPresentationController.Frame = _plain_frame(Vector3(1.25, 0.0, 0.75))
	blocker.moving = true
	var frames: Dictionary[int, AgentPresentationController.Frame] = {1: first, 2: blocker}
	assert_true(_drawn(first).distance_to(_drawn(blocker)) > AgentPresentationController.MIN_STANDING_DISTANCE)
	AgentPresentationController.constrain_display_offsets(frames, world.grid)
	assert_eq(_drawn(first), first.sim_floor_position)
	assert_eq(first.display_offset, Vector3.ZERO)
	assert_true(first.separation_blocked)
	assert_eq(_drawn(blocker), blocker.sim_floor_position)


func test_postblend_reach_offset_cannot_cross_an_internal_wall_or_solid_footprint() -> void:
	var world: SimWorld = _world()
	var origin: Vector3 = GridMath.cell_to_world(Vector2i(1, 1))
	var frame: AgentPresentationController.Frame = _plain_frame(origin)
	frame.floor_position += Vector3.RIGHT * 0.5
	assert_true(world.grid.set_segment(SimGrid.edge_between(Vector2i(1, 1), Vector2i(2, 1)), SimGrid.Segment.WALL))
	var frames: Dictionary[int, AgentPresentationController.Frame] = {1: frame}
	AgentPresentationController.constrain_display_offsets(frames, world.grid)
	assert_eq(frame.floor_position, origin)
	assert_true(frame.separation_blocked)
	world = _world()
	var solid: ItemDef = ItemDef.new()
	solid.id = &"solid_fixture"
	solid.category = ItemDef.Category.TABLE
	solid.footprint = Vector2i.ONE
	solid.solid = true
	assert_not_null(world.grid.place_def(solid, Vector2i(2, 1)))
	frame = _plain_frame(origin)
	frame.display_offset = Vector3.RIGHT * 1.0
	frames = {1: frame}
	AgentPresentationController.constrain_display_offsets(frames, world.grid)
	assert_eq(_drawn(frame), origin)
	assert_true(frame.separation_blocked)


func test_rejected_neighbor_offsets_are_rechecked_against_all_final_positions_in_either_order() -> void:
	var world: SimWorld = _world()
	assert_true(world.grid.set_segment(SimGrid.edge_between(Vector2i(2, 1), Vector2i(3, 1)), SimGrid.Segment.WALL))
	for reverse: bool in [false, true]:
		var first: AgentPresentationController.Frame = _plain_frame(Vector3(0.75, 0.0, 0.75))
		var second: AgentPresentationController.Frame = _plain_frame(Vector3(1.25, 0.0, 0.75))
		first.floor_position += Vector3.RIGHT * 0.06
		second.floor_position += Vector3.RIGHT * 0.06
		var frames: Dictionary[int, AgentPresentationController.Frame] = {}
		if reverse:
			frames[2] = second
			frames[1] = first
		else:
			frames[1] = first
			frames[2] = second
		assert_true(_drawn(first).distance_to(_drawn(second)) >= AgentPresentationController.MIN_STANDING_DISTANCE)
		assert_true(_drawn(first).distance_to(second.sim_floor_position) < AgentPresentationController.MIN_STANDING_DISTANCE,
			"the earlier candidate would overlap the neighbor's safe fallback")
		AgentPresentationController.constrain_display_offsets(frames, world.grid)
		assert_eq(_drawn(first), first.sim_floor_position)
		assert_eq(_drawn(second), second.sim_floor_position)
		assert_true(_drawn(first).distance_to(_drawn(second)) >= AgentPresentationController.MIN_STANDING_DISTANCE)
		assert_true(first.separation_blocked and second.separation_blocked)


func test_safe_authored_seat_and_reach_offsets_stay_anchored() -> void:
	var world: SimWorld = _world()
	var seated: AgentPresentationController.Frame = _plain_frame(Vector3(1.25, 0.0, 1.25))
	seated.seated = true
	seated.display_offset = Vector3(0.0, 0.0, 0.04)
	var reaching: AgentPresentationController.Frame = _plain_frame(Vector3(2.25, 0.0, 2.25))
	reaching.floor_position += Vector3(0.0, 0.0, 0.01)
	var frames: Dictionary[int, AgentPresentationController.Frame] = {1: seated, 2: reaching}
	AgentPresentationController.constrain_display_offsets(frames, world.grid)
	assert_eq(seated.display_offset, Vector3(0.0, 0.0, 0.04))
	assert_eq(reaching.floor_position, Vector3(2.25, 0.0, 2.26))
	assert_false(reaching.separation_blocked)
	seated.display_offset = Vector3.RIGHT * 0.5
	AgentPresentationController.constrain_display_offsets(frames, world.grid)
	assert_eq(seated.display_offset, Vector3.ZERO, "seated pose cannot be used to bypass the offset bound or its own cell")
	assert_true(seated.separation_blocked)


static func _world() -> SimWorld:
	return SimWorld.new(SimGrid.from_ascii(["......", "......", "......", "......", "......", "......"]))


static func _plain_frame(point: Vector3) -> AgentPresentationController.Frame:
	var frame: AgentPresentationController.Frame = AgentPresentationController.Frame.new()
	frame.floor_position = point
	frame.sim_floor_position = point
	return frame


static func _trace_frame(tick: int, points: Array[Vector3], times: Array[float]) -> AgentPresentationController.Frame:
	var frame: AgentPresentationController.Frame = _plain_frame(points[-1])
	frame.movement_trace_expected = true
	frame.movement_trace = {"tick": tick, "points": points.duplicate(), "times": times.duplicate(), "discontinuous": false}
	return frame


static func _drawn(frame: AgentPresentationController.Frame) -> Vector3:
	return frame.floor_position + frame.display_offset


static func _distance_to_rect(point: Vector3, rect: Rect2) -> float:
	var flat: Vector2 = Vector2(point.x, point.z)
	var closest: Vector2 = Vector2(clampf(flat.x, rect.position.x, rect.end.x),
		clampf(flat.y, rect.position.y, rect.end.y))
	return flat.distance_to(closest)
