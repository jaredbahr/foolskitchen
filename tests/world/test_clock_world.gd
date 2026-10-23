extends TestCase
## The autoload drives either one clock or one complete world, never both.

var _sim: SimClock
var _world: SimWorld
var _speed: int
var _last_speed: int
var _accumulator: float


func before_each() -> void:
	_sim = Clock.sim
	_world = Clock.attached_world
	_speed = Clock.speed
	_last_speed = Clock._last_non_zero_speed
	_accumulator = Clock._accumulator
	Clock.attach_world(null)
	Clock.sim = SimClock.new()
	Clock.set_speed(1)


func after_each() -> void:
	Clock.attach_world(_world)
	Clock.sim = _sim
	Clock.set_speed(_speed)
	Clock._last_non_zero_speed = _last_speed
	Clock._accumulator = _accumulator


func test_standalone_mode_advances_clock() -> void:
	Clock.sim.start_service()
	Clock._process(0.1)
	assert_eq(Clock.sim.tick, 1)


func test_attached_mode_advances_world_once_and_detach_keeps_clock() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new())
	Clock.attach_world(world)
	assert_true(Clock.sim == world.clock)
	world.clock.start_service()
	Clock._process(0.2)
	assert_eq(world.now, 2)
	assert_eq(world.clock.tick, 2)
	Clock.attach_world(null)
	Clock._process(0.1)
	assert_eq(world.now, 2)
	assert_eq(Clock.sim.tick, 3)


func test_attached_world_respects_pause_and_speed() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new())
	Clock.attach_world(world)
	Clock._process(1.0)
	assert_eq(world.now, 0)
	world.clock.start_service()
	Clock.set_speed(0)
	Clock._process(1.0)
	assert_eq(world.now, 0)
	Clock.set_speed(4)
	Clock._process(0.1)
	assert_eq(world.now, 4)


func test_attached_world_keeps_driving_after_clock_replacement_and_restore() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new())
	Clock.attach_world(world)
	world.clock.start_service()
	Clock._process(0.1)
	var replacement: SimClock = SimClock.new()
	replacement.start_service()
	Clock.sim = replacement
	assert_true(world.clock == replacement)
	Clock._process(0.1)
	assert_eq(world.now, 2)
	assert_eq(replacement.tick, 1)
	var saved: Dictionary = replacement.to_dict()
	assert_true(Clock._restore_save(saved))
	assert_true(world.clock == Clock.sim)
	assert_true(world.clock != replacement)
	Clock._process(0.1)
	assert_eq(world.now, 3)
	assert_eq(world.clock.tick, 2)
	# The new clock retains the phase forwarding connection exactly once.
	assert_true(world.clock.phase_changed.is_connected(Callable(Clock, "_on_phase_changed")))
	assert_false(replacement.phase_changed.is_connected(Callable(Clock, "_on_phase_changed")))
