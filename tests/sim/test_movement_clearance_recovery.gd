extends TestCase
## Solvable corner-clearance and stale outbound-pocket regressions.
## Fixtures use genuine bodies, public destinations and ordinary world ticks.

const WATCHDOG: int = 512


class Walker extends SimAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


class StaffWalker extends StaffAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


class DelayedStaffWalker extends StaffWalker:
	var release_tick: int = 0


	func tick(world: SimWorld) -> void:
		if world.now >= release_tick:
			step_move(world)


func test_free_diagonal_target_with_stationary_corner_holders_recovers_to_the_actual_goal() -> void:
	var fixture: Dictionary = _corner_fixture()
	var world: SimWorld = fixture["world"] as SimWorld
	var mover: Walker = fixture["mover"] as Walker
	for tick: int in WATCHDOG:
		if not _advance(world):
			return
		if _at(mover, Vector2i(1, 1)):
			break
	assert_true(_at(mover, Vector2i(1, 1)), "a solvable free-target clearance blockage must reach its actual goal")
	assert_eq(world.agent(mover.id), mover)
	assert_eq(world.agent((fixture["holder"] as Walker).id), fixture["holder"])
	assert_eq(world.agent((fixture["other"] as Walker).id), fixture["other"])


func test_public_corner_holder_move_proves_the_same_geometry_is_physically_solvable() -> void:
	var fixture: Dictionary = _corner_fixture()
	var world: SimWorld = fixture["world"] as SimWorld
	var mover: Walker = fixture["mover"] as Walker
	var holder: Walker = fixture["holder"] as Walker
	var pocket: Vector2i = Vector2i(0, 0)
	assert_true(holder.set_destination(world.grid, pocket))
	var physically_moving: bool = false
	for tick: int in WATCHDOG:
		if not _advance(world):
			return
		physically_moving = physically_moving or holder.move_progress > 0.0
		if _at(mover, Vector2i(1, 1)) and _at(holder, pocket):
			break
	assert_true(physically_moving, "the corner holder walks a real claimed edge instead of disappearing")
	assert_true(_at(holder, pocket))
	assert_true(_at(mover, Vector2i(1, 1)), "the opened cardinal route reaches the original target")
	assert_true(_at(fixture["other"] as Walker, Vector2i(2, 1)))


func test_taken_outbound_yield_pocket_recovers_without_losing_the_original_goals() -> void:
	var fixture: Dictionary = _outbound_fixture()
	var world: SimWorld = fixture["world"] as SimWorld
	var first: StaffWalker = fixture["first"] as StaffWalker
	var contender: DelayedStaffWalker = fixture["contender"] as DelayedStaffWalker
	var yielding: StaffWalker = fixture["yielding"] as StaffWalker
	var contender_moved: bool = false
	for tick: int in WATCHDOG:
		if not _advance(world):
			return
		contender_moved = contender_moved or contender.move_progress > 0.0
		assert_eq(yielding.destination(), Vector2i(0, 1), "temporary pockets must not replace the actual original goal")
		if _at(first, Vector2i(4, 1)) and _at(yielding, Vector2i(0, 1)) \
				and _at(contender, Vector2i(2, 0)):
			break
	assert_true(contender_moved, "the contender claims and walks normally after its scheduled departure")
	assert_true(_at(first, Vector2i(4, 1)))
	assert_true(_at(yielding, Vector2i(0, 1)), "outbound recovery must finish the original journey before the watchdog")
	assert_true(_at(contender, Vector2i(2, 0)))


func test_public_contender_move_proves_the_outbound_encounter_can_finish() -> void:
	var fixture: Dictionary = _outbound_fixture()
	var world: SimWorld = fixture["world"] as SimWorld
	var first: StaffWalker = fixture["first"] as StaffWalker
	var contender: DelayedStaffWalker = fixture["contender"] as DelayedStaffWalker
	var yielding: StaffWalker = fixture["yielding"] as StaffWalker
	var reached_pocket: bool = false
	var physically_moving: bool = false
	for tick: int in WATCHDOG:
		if not _advance(world):
			return
		physically_moving = physically_moving or contender.move_progress > 0.0
		assert_eq(yielding.destination(), Vector2i(0, 1))
		if not reached_pocket and _at(contender, Vector2i(2, 0)):
			reached_pocket = true
			assert_true(contender.set_destination(world.grid, Vector2i(3, 0)),
				"move the real pocket occupant away through the public destination API")
		if reached_pocket and _at(first, Vector2i(4, 1)) and _at(yielding, Vector2i(0, 1)) \
				and _at(contender, Vector2i(3, 0)):
			break
	assert_true(physically_moving)
	assert_true(reached_pocket, "the competing actor actually reaches the declared yield pocket")
	assert_true(_at(contender, Vector2i(3, 0)))
	assert_true(_at(first, Vector2i(4, 1)))
	assert_true(_at(yielding, Vector2i(0, 1)))


func _corner_fixture() -> Dictionary:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["...", "#.."])))
	var mover: Walker = _walker(world, Vector2i(2, 0), Vector2i(1, 1))
	var holder: Walker = _walker(world, Vector2i(1, 0), Vector2i(1, 0))
	var other: Walker = _walker(world, Vector2i(2, 1), Vector2i(2, 1))
	assert_eq(mover.next_cell(), Vector2i(1, 1))
	assert_true(world.movement.can_enter(world, mover, Vector2i(1, 1)), "the diagonal destination itself is free")
	assert_false(world.movement.can_enter(world, mover, holder.cell))
	assert_false(world.movement.can_enter(world, mover, other.cell))
	assert_true(holder.has_arrived() and other.has_arrived(), "both corner occupants are idle ordinary actors")
	assert_eq(world.movement.priority(world, mover), world.movement.priority(world, holder))
	assert_true(mover.id < holder.id and mover.id < other.id)
	assert_true(world.movement.can_enter(world, holder, Vector2i(0, 0)), "the holder has a genuine free yielding pocket")
	assert_true(world.grid.step_open(holder.cell, Vector2i(0, 0)))
	assert_true(world.clock.start_service())
	return {"world": world, "mover": mover, "holder": holder, "other": other}


func _outbound_fixture() -> Dictionary:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["##..#", ".....", "##.##"])))
	var first: StaffWalker = StaffWalker.new(&"server", 3)
	first.cell = Vector2i(1, 1)
	world.add_agent(first)
	assert_true(first.set_destination(world.grid, Vector2i(4, 1)))
	var contender: DelayedStaffWalker = DelayedStaffWalker.new(&"server", 3)
	contender.cell = Vector2i(3, 0)
	contender.release_tick = world.movement_tuning.yield_after_ticks
	world.add_agent(contender)
	assert_true(contender.set_destination(world.grid, Vector2i(2, 0)))
	var yielding: StaffWalker = StaffWalker.new(&"server", 3)
	yielding.cell = Vector2i(2, 1)
	world.add_agent(yielding)
	assert_true(yielding.set_destination(world.grid, Vector2i(0, 1)))
	assert_true(first.id < contender.id and contender.id < yielding.id)
	assert_eq(world.movement.priority(world, first), world.movement.priority(world, contender))
	assert_eq(world.movement.priority(world, contender), world.movement.priority(world, yielding))
	assert_true(world.grid.step_open(yielding.cell, Vector2i(2, 0)))
	assert_true(world.movement.can_enter(world, yielding, Vector2i(2, 0)), "ordinary first pocket is initially free")
	assert_true(world.movement.can_enter(world, yielding, Vector2i(2, 2)), "a different legal pocket remains available")
	assert_true(world.clock.start_service())
	return {"world": world, "first": first, "contender": contender, "yielding": yielding}


func _walker(world: SimWorld, at: Vector2i, goal: Vector2i) -> Walker:
	var walker: Walker = Walker.new()
	walker.cell = at
	world.add_agent(walker)
	assert_true(walker.set_destination(world.grid, goal))
	return walker


func _advance(world: SimWorld) -> bool:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	var problem: String = MovementInvariants.problem(world, before)
	assert_eq(problem, "", "every real edge and body remains safe")
	assert_eq(world.agents.size(), 3, "recovery never hides or removes an active person")
	assert_true(world.pending_agents().is_empty())
	return problem.is_empty()


func _at(actor: SimAgent, cell: Vector2i) -> bool:
	return actor.cell == cell and actor.move_progress == 0.0 and actor.has_arrived()
