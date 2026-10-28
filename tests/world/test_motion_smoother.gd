extends TestCase
## Smooth motion (MotionSmoother, ShopView.interpolation_alpha): people are
## drawn between their last two sim ticks, never across a jump, frozen while
## paused, and the sim is never touched.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _view: ShopView
var _sim: RestaurantSim
var _clock_world: SimWorld
var _clock_driver: Callable
var _clock_sim: SimClock
var _speed: int
var _accumulator: float


func before_each() -> void:
	_clock_world = Clock.attached_world
	_clock_driver = Clock.tick_driver
	_clock_sim = Clock.sim
	_speed = Clock.speed
	_accumulator = Clock._accumulator


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()
	Clock.attach_world(_clock_world, _clock_driver)
	Clock.sim = _clock_sim
	Clock.set_speed(_speed)
	Clock._accumulator = _accumulator
	_sim = null


static func _frame(at: Vector3, facing: Vector3 = Vector3.ZERO, moving: bool = false) -> AgentPresentationController.Frame:
	var frame: AgentPresentationController.Frame = AgentPresentationController.Frame.new()
	frame.floor_position = at
	frame.facing_direction = facing
	frame.moving = moving
	return frame


func test_draws_between_the_last_two_ticks() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 10, _frame(Vector3(1.0, 0.0, 1.0), Vector3.RIGHT, true))
	motion.observe(1, 11, _frame(Vector3(1.125, 0.0, 1.0), Vector3.RIGHT, true))
	for alpha: float in [0.0, 0.25, 0.5, 0.75]:
		var frame: AgentPresentationController.Frame = _frame(Vector3(1.125, 0.0, 1.0), Vector3.RIGHT, true)
		motion.blend(1, alpha, frame)
		assert_almost_eq(frame.floor_position.x, 1.0 + 0.125 * alpha, 0.00001, "alpha %s" % alpha)
		assert_eq(frame.display_offset, Vector3.ZERO)
	var newest: AgentPresentationController.Frame = _frame(Vector3(1.125, 0.0, 1.0), Vector3.RIGHT, true)
	motion.blend(1, 1.0, newest)
	assert_eq(newest.floor_position, Vector3(1.125, 0.0, 1.0), "alpha 1 is the newest tick, unchanged")


func test_the_same_tick_again_refreshes_without_moving_on() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 0, _frame(Vector3.ZERO))
	motion.observe(1, 1, _frame(Vector3(0.1, 0.0, 0.0)))
	motion.observe(1, 1, _frame(Vector3(0.1, 0.0, 0.0)))
	var frame: AgentPresentationController.Frame = _frame(Vector3(0.1, 0.0, 0.0))
	motion.blend(1, 0.5, frame)
	assert_almost_eq(frame.floor_position.x, 0.05, 0.00001, "still between tick 0 and 1")


func test_a_newcomer_or_a_jump_is_drawn_where_it_is() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 5, _frame(Vector3(2.0, 0.0, 2.0)))
	var spawned: AgentPresentationController.Frame = _frame(Vector3(2.0, 0.0, 2.0))
	motion.blend(1, 0.3, spawned)
	assert_eq(spawned.floor_position, Vector3(2.0, 0.0, 2.0), "spawned: nothing to come from")
	motion.observe(1, 6, _frame(Vector3(2.0 + MotionSmoother.SNAP_DISTANCE + 0.5, 0.0, 2.0)))
	var jumped: AgentPresentationController.Frame = _frame(Vector3(2.0 + MotionSmoother.SNAP_DISTANCE + 0.5, 0.0, 2.0))
	motion.blend(1, 0.3, jumped)
	assert_almost_eq(jumped.floor_position.x, 2.0 + MotionSmoother.SNAP_DISTANCE + 0.5, 0.00001,
		"a teleport is not slid across")
	# Shown again after the restroom: no slide from where they went in.
	var hidden: AgentPresentationController.Frame = _frame(Vector3(3.6, 0.0, 2.0))
	hidden.hidden = true
	motion.observe(1, 7, hidden)
	var shown: AgentPresentationController.Frame = _frame(Vector3(3.7, 0.0, 2.0))
	motion.observe(1, 8, shown)
	motion.blend(1, 0.0, shown)
	assert_almost_eq(shown.floor_position.x, 3.7, 0.00001)
	# A world tick that went backwards (another world, a reload) starts afresh.
	motion.observe(1, 2, _frame(Vector3.ZERO))
	var reset: AgentPresentationController.Frame = _frame(Vector3.ZERO)
	motion.blend(1, 0.5, reset)
	assert_eq(reset.floor_position, Vector3.ZERO)
	motion.retain({} as Dictionary[int, bool])
	assert_false(motion.has_track(1), "gone people are forgotten")


func test_several_ticks_in_one_frame_keep_one_tick_back_on_the_line() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 0, _frame(Vector3.ZERO))
	motion.observe(1, 2, _frame(Vector3(0.2, 0.0, 0.0)))
	var frame: AgentPresentationController.Frame = _frame(Vector3(0.2, 0.0, 0.0))
	motion.blend(1, 0.0, frame)
	assert_almost_eq(frame.floor_position.x, 0.1, 0.00001, "the pose at tick 1")


func test_facing_turns_and_a_stop_keeps_walking_into_place() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 0, _frame(Vector3.ZERO, Vector3.RIGHT, true))
	var stopped: AgentPresentationController.Frame = _frame(Vector3(0.125, 0.0, 0.0), Vector3.BACK, false)
	motion.observe(1, 1, stopped)
	motion.blend(1, 0.5, stopped)
	assert_true(stopped.moving, "walks the last bit instead of gliding in the idle pose")
	assert_eq(stopped.clip, &"walk")
	var yaw: float = atan2(-stopped.facing_direction.x, -stopped.facing_direction.z)
	assert_almost_eq(absf(angle_difference(yaw, lerp_angle(atan2(-1.0, 0.0), atan2(0.0, -1.0), 0.5))), 0.0, 0.0001,
		"half way round")


func test_sitting_down_walks_into_the_seat_then_sits() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	var seat: Vector3 = Vector3(1.0, 0.0, 1.0)
	motion.observe(1, 0, _frame(seat - Vector3(0.125, 0.0, 0.0), Vector3.RIGHT, true))
	var seated: AgentPresentationController.Frame = _frame(seat, Vector3.BACK)
	seated.seated = true
	seated.seat_height = 0.27
	seated.display_offset = Vector3(0.0, 0.0, 0.1)
	motion.observe(1, 1, seated)
	motion.blend(1, 0.5, seated)
	assert_false(seated.seated, "stands until the tick they sit")
	assert_eq(seated.seat_height, 0.0)
	assert_true(seated.moving)
	assert_almost_eq(seated.floor_position.x, seat.x - 0.0625, 0.00001, "towards the seat cell")
	assert_almost_eq(seated.floor_position.z, seat.z, 0.00001, "not the seated offset yet")
	var settled: AgentPresentationController.Frame = _frame(seat, Vector3.BACK)
	settled.seated = true
	settled.display_offset = Vector3(0.0, 0.0, 0.1)
	motion.observe(1, 2, settled)
	motion.blend(1, 0.5, settled)
	assert_true(settled.seated, "then seated, in place")
	assert_almost_eq(settled.floor_position.z, seat.z + 0.1, 0.00001)


func _view_with_clock() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, content, 1, errors, Stock.new())
	assert_eq(errors, [] as Array[String])
	_view = VIEW.instantiate() as ShopView
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_view)
	_view.set_process(false)
	_view.show_world(_sim.world)
	Clock.attach_world(_sim.world, _sim.advance)
	assert_true(_sim.world.clock.start_service())
	Clock.set_speed(1)


func _walker() -> SimAgent:
	for agent: SimAgent in _sim.world.agents:
		if not agent.has_arrived():
			return agent
	return null


func test_the_clock_fraction_draws_between_ticks_and_pause_freezes_it() -> void:
	_view_with_clock()
	assert_eq(_view.interpolation_alpha(), 1.0, "nothing driven by the clock yet: as it is")
	var walker: SimAgent = null
	for step: int in 400:
		Clock._process(0.1)
		_view._process(0.0)
		walker = _walker()
		if walker != null and walker.move_progress > 0.3:
			break
	assert_not_null(walker, "someone walks")
	Clock._process(0.05)
	assert_almost_eq(_view.interpolation_alpha(), Clock.tick_fraction(), 0.00001)
	assert_true(_view.interpolation_alpha() > 0.0 and _view.interpolation_alpha() < 1.0)
	var cell: Vector2i = walker.cell
	var progress: float = walker.move_progress
	var now: int = _sim.world.now
	_view._process(0.0)
	var drawn: Vector3 = _view.agent_nodes[walker.id].position
	var newest: Vector3 = AgentPresentationController.frame_for(walker, _sim.world).floor_position
	assert_true(drawn.distance_to(newest) > 0.001, "a little behind the newest tick")
	assert_true(drawn.distance_to(newest) < 0.2)
	assert_eq(walker.cell, cell, "the sim is never moved")
	assert_eq(walker.move_progress, progress)
	assert_eq(_sim.world.now, now)
	Clock.set_speed(0)
	for step: int in 5:
		Clock._process(0.1)
		_view._process(0.0)
	assert_eq(_sim.world.now, now, "paused")
	assert_true(_view.agent_nodes[walker.id].position.is_equal_approx(drawn), "frozen in place, no jump")
	Clock.set_speed(1)
	Clock._process(0.02)
	_view._process(0.0)
	var resumed: Vector3 = _view.agent_nodes[walker.id].position
	assert_true(resumed.distance_to(drawn) < 0.05, "picks up where it stopped")
	# A tick from outside the clock (tools, tests) draws the newest state.
	_sim.advance()
	_view._process(0.0)
	assert_eq(_view.interpolation_alpha(), 1.0)
	assert_true(_view.agent_nodes[walker.id].position.is_equal_approx(
		AgentPresentationController.frames_for(_sim.world.agents, _sim.world)[walker.id].floor_position
		+ AgentPresentationController.frames_for(_sim.world.agents, _sim.world)[walker.id].display_offset))


func test_a_slide_that_ends_this_tick_finishes_towards_its_own_spot() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	var spot: Vector3 = Vector3(2.0, 0.0, 1.2)
	var sliding: AgentPresentationController.Frame = _frame(Vector3(2.0, 0.0, 1.5))
	sliding.crate_slide = 0.1
	sliding.crate_spot = spot
	sliding.crate_layer = 1
	motion.observe(1, 0, sliding)
	# In the hands now: the newest frame has no spot or layer.
	var held: AgentPresentationController.Frame = _frame(Vector3(2.0, 0.0, 1.5))
	held.crate_count = 1
	held.carrying = true
	motion.observe(1, 1, held)
	motion.blend(1, 0.5, held)
	assert_almost_eq(held.crate_slide, 0.05, 0.00001)
	assert_eq(held.crate_spot, spot, "still towards the stack it came off, never the world origin")
	assert_eq(held.crate_layer, 1)


func test_settle_blends_from_what_is_drawn_now() -> void:
	var motion: MotionSmoother = MotionSmoother.new()
	motion.observe(1, 10, _frame(Vector3(1.0, 0.0, 1.0)))
	# Same tick, moved between ticks (the morning reset), drawn as it is.
	motion.observe(1, 10, _frame(Vector3(1.5, 0.0, 1.5)))
	motion.settle(1)
	var frame: AgentPresentationController.Frame = _frame(Vector3(1.5, 0.0, 1.5))
	motion.blend(1, 0.5, frame)
	assert_eq(frame.floor_position, Vector3(1.5, 0.0, 1.5), "no glide from where they were yesterday")


func test_opening_after_the_morning_reset_does_not_glide() -> void:
	_view_with_clock()
	var guard: int = 0
	while _sim.world.clock.phase != SimClock.Phase.CLOSED and guard < 400:
		Clock._process(4.0)
		_view._process(0.0)
		guard += 1
	assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED)
	var tick: int = _sim.world.now
	assert_true(_sim.world.clock.next_day())
	_sim.start_day()
	_view._process(0.0)
	for agent: SimAgent in _sim.world.agents:
		assert_false(_view.motion.blending(agent.id), "%s: the morning is drawn as it is, nothing to glide from" % agent.role)
	assert_true(_sim.world.clock.start_service())
	Clock._process(0.05)
	_view._process(0.0)
	assert_eq(_sim.world.now, tick, "no tick yet")
	assert_almost_eq(_view.interpolation_alpha(), 0.5, 0.0001, "between ticks")
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(
		_sim.world.agents, _sim.world)
	for agent: SimAgent in _sim.world.agents:
		var at: Vector3 = frames[agent.id].floor_position + frames[agent.id].display_offset
		assert_true(_view.agent_nodes[agent.id].position.is_equal_approx(at),
			"%s stands at its post, not on its way from last night" % agent.role)
