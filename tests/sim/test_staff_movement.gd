extends TestCase
## Isolated movement cadence, with real admission and complete world ticks.
## FK-124 intentionally replaces mid-edge snapping and buried long jumps;
## valid neutral/Quick timings and the exact legacy movement body stay held.

const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")


## These drivers exercise inherited movement without claiming restaurant work.
## Production occupancy, tick boundaries, stopping and traces remain enabled.
class MotionStaff extends StaffAgent:
	var last_move: SimAgent.MoveResult = SimAgent.MoveResult.ARRIVED

	func tick(world: SimWorld) -> void:
		last_move = step_move(world)


class MotionOwner extends OwnerAgent:
	var last_move: SimAgent.MoveResult = SimAgent.MoveResult.ARRIVED

	func tick(world: SimWorld) -> void:
		last_move = step_move(world)


func test_quick_arrives_thirteen_to_fifteen_percent_sooner_on_long_straight_path() -> void:
	var rows: PackedStringArray = [".".repeat(101)]
	var steady_world: SimWorld = _world(rows)
	var quick_world: SimWorld = _world(rows)
	var steady: MotionStaff = _staff(&"steady")
	var quick: MotionStaff = _staff(&"quick")
	_admit(steady_world, steady)
	_admit(quick_world, quick)
	for agent: MotionStaff in [steady, quick]:
		var world: SimWorld = steady_world if agent == steady else quick_world
		assert_true(agent.set_destination(world.grid, Vector2i(100, 0)))
		assert_eq(agent.path.size(), 101)
	var steady_ticks: int = _arrival_ticks(steady_world, steady)
	var quick_ticks: int = _arrival_ticks(quick_world, quick)
	assert_eq(steady_ticks, 400, "the old four ticks per straight cell stay exact")
	assert_eq(quick_ticks, 348)
	_assert_gain(steady_ticks, quick_ticks)
	assert_eq(quick.cell, Vector2i(100, 0))
	assert_almost_eq(quick.move_progress, 0.0)


func test_quick_arrives_thirteen_to_fifteen_percent_sooner_on_long_diagonal_path() -> void:
	var rows: PackedStringArray = []
	for row: int in range(101):
		rows.append(".".repeat(101))
	var steady_world: SimWorld = _world(rows)
	var quick_world: SimWorld = _world(rows)
	var steady: MotionStaff = _staff(&"steady")
	var quick: MotionStaff = _staff(&"quick")
	_admit(steady_world, steady)
	_admit(quick_world, quick)
	for agent: MotionStaff in [steady, quick]:
		var world: SimWorld = steady_world if agent == steady else quick_world
		assert_true(agent.set_destination(world.grid, Vector2i(100, 100)))
		assert_eq(agent.path.size(), 101)
		for index: int in range(1, agent.path.size()):
			assert_eq(agent.path[index] - agent.path[index - 1], Vector2i.ONE)
	var steady_ticks: int = _arrival_ticks(steady_world, steady)
	var quick_ticks: int = _arrival_ticks(quick_world, quick)
	assert_eq(steady_ticks, 600, "the old six ticks per diagonal cell stay exact")
	assert_eq(quick_ticks, 522)
	_assert_gain(steady_ticks, quick_ticks)
	assert_eq(quick.cell, Vector2i(100, 100))


func test_residual_tick_credit_converts_using_the_next_edges_cost_in_both_directions() -> void:
	var first_world: SimWorld = _world(PackedStringArray(["...", "..."]))
	var first: MotionStaff = _staff(&"quick")
	_admit(first_world, first)
	_route(first, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 1)])
	_move(first_world, first, 4)
	assert_eq(first.cell, Vector2i(1, 0))
	assert_eq(first.path_index, 2)
	assert_almost_eq(first.move_progress, 0.1, 0.000000001,
		"0.6 baseline ticks left after the straight edge become 0.6/6 of the diagonal")
	var second_world: SimWorld = _world(PackedStringArray(["...", "..."]))
	var second: MotionStaff = _staff(&"quick")
	_admit(second_world, second)
	_route(second, [Vector2i.ZERO, Vector2i(1, 1), Vector2i(2, 1)])
	_move(second_world, second, 6)
	assert_eq(second.cell, Vector2i(1, 1))
	assert_almost_eq(second.move_progress, 0.225, 0.000000001,
		"0.9 baseline ticks left after the diagonal become 0.9/4 of the straight edge")


func test_every_residual_edge_checks_walkability_and_blocking_does_not_bank_credit() -> void:
	var world: SimWorld = _world(PackedStringArray(["...", "..."]))
	var quick: MotionStaff = _staff(&"quick")
	_admit(world, quick)
	_route(quick, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 1)])
	_move(world, quick, 3)
	# The planned terminal edge becomes blocked; the current edge stays legal.
	var blocker: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(2, 1), 0, true)
	assert_not_null(blocker)
	assert_eq(_step(world, quick), SimAgent.MoveResult.BLOCKED)
	assert_eq(quick.cell, Vector2i(1, 0), "the walkable edge completes; the blocked edge is never entered")
	assert_eq(quick.path_index, 2)
	assert_almost_eq(quick.move_progress, 0.0)
	for wait: int in range(12):
		assert_eq(_step(world, quick), SimAgent.MoveResult.BLOCKED)
		assert_almost_eq(quick.move_progress, 0.0)
	world.grid.remove(blocker.id)
	assert_eq(_step(world, quick), SimAgent.MoveResult.MOVING)
	assert_almost_eq(quick.move_progress, 1.15 / 6.0, 0.000000001,
		"unblocking receives one new tick, not saved credit from the blocked period")


func test_arrival_idle_clear_and_changed_next_repath_cannot_store_extra_movement() -> void:
	var world: SimWorld = _world(PackedStringArray(["....", "....", "...."]))
	var quick: MotionStaff = _staff(&"quick")
	_admit(world, quick)
	assert_true(quick.set_destination(world.grid, Vector2i(1, 0)))
	assert_eq(_arrival_ticks(world, quick), 4)
	for idle: int in range(12):
		assert_eq(_step(world, quick), SimAgent.MoveResult.ARRIVED)
	assert_almost_eq(quick.move_progress, 0.0)
	assert_true(quick.set_destination(world.grid, Vector2i(3, 0)))
	_move(world, quick, 1)
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001)
	assert_true(quick.repath(world.grid))
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001, "the same next cell keeps actual drawn progress")
	# FK-124: a changed intent cannot snap backwards from a reserved edge.
	# This target gives a straight fresh edge after reaching its current vertex.
	assert_true(quick.set_destination(world.grid, Vector2i(2, 2)))
	assert_eq(quick.cell, Vector2i(1, 0))
	assert_eq(quick.next_cell(), Vector2i(2, 0))
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001)
	_finish_stop(world, quick)
	assert_eq(quick.cell, Vector2i(2, 0))
	assert_almost_eq(quick.move_progress, 0.0)
	_move(world, quick, 1)
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001, "the new straight edge gets one fresh tick")
	quick.clear_path()
	assert_eq(quick.next_cell(), Vector2i(2, 1))
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001, "clear retains its already reserved physical edge")
	_finish_stop(world, quick)
	assert_eq(quick.cell, Vector2i(2, 1))
	assert_true(quick.has_arrived())
	assert_almost_eq(quick.move_progress, 0.0)
	for idle: int in range(12):
		assert_eq(_step(world, quick), SimAgent.MoveResult.ARRIVED)
	assert_true(quick.set_destination(world.grid, Vector2i(2, 2)))
	_move(world, quick, 1)
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001,
		"clear discards unused budget after the vertex; idle time never banks credit")


func test_quick_rejects_a_long_jump_through_solid_furniture_and_walks_an_adjacent_detour() -> void:
	var world: SimWorld = _world(PackedStringArray([".....", "....."]))
	var quick: MotionStaff = _staff(&"quick")
	_admit(world, quick)
	assert_not_null(world.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, true))
	# The former buried0→3 escape is user-forbidden geometry in FK-124.
	_route(quick, [Vector2i.ZERO, Vector2i(3, 0), Vector2i(4, 1)])
	_move(world, quick, 3)
	assert_eq(quick.cell, Vector2i.ZERO, "a non-adjacent edge cannot jump across furniture")
	assert_almost_eq(quick.move_progress, 0.0)
	quick.clear_path()
	assert_true(quick.set_destination(world.grid, Vector2i(4, 1)))
	for index: int in range(1, quick.path.size()):
		assert_true(world.grid.walkable_neighbours(quick.path[index - 1]).has(quick.path[index]),
			"every planned detour edge is adjacent and clears the solid corner")
		assert_ne(quick.path[index], Vector2i(1, 0))
	assert_true(_arrival_ticks(world, quick) <= 1000)
	assert_eq(quick.cell, Vector2i(4, 1))


func test_steady_and_owner_match_the_old_movement_state_on_every_tick() -> void:
	# The unchanged reference below now compares valid adjacent mixed edges.
	# Each reference has its own grid/world, never blocking the actual actor.
	for actual: SimAgent in [_staff(&"steady"), MotionOwner.new()]:
		var rows: PackedStringArray = [".....", ".....", "....."]
		var world: SimWorld = _world(rows)
		var reference_world: SimWorld = _world(rows)
		var blocker: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(4, 2), 0, true)
		var reference_blocker: PlacedItem = reference_world.grid.place(Vector2i.ONE, Vector2i(4, 2), 0, true)
		var legacy: SimAgent = SimAgent.new()
		_admit(world, actual)
		_admit(reference_world, legacy)
		var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 1),
			Vector2i(3, 1), Vector2i(4, 1), Vector2i(4, 2)]
		_route(actual, cells)
		_route(legacy, cells)
		assert_eq(actual.movement_multiplier(), 1.0)
		for tick: int in range(24):
			var result: SimAgent.MoveResult = _step(world, actual)
			reference_world.now = world.now
			assert_eq(result, _legacy_step(legacy, reference_world))
			assert_eq(_snapshot(actual), _snapshot(legacy), "neutral movement stays identical on every tick")
		world.grid.remove(blocker.id)
		reference_world.grid.remove(reference_blocker.id)
		for tick: int in range(8):
			var result: SimAgent.MoveResult = _step(world, actual)
			reference_world.now = world.now
			assert_eq(result, _legacy_step(legacy, reference_world))
			assert_eq(_snapshot(actual), _snapshot(legacy))
		assert_true(actual.has_arrived())


func _world(rows: PackedStringArray) -> SimWorld:
	return SimWorld.new(SimGrid.from_ascii(rows))


func _admit(world: SimWorld, agent: SimAgent) -> void:
	assert_eq(agent.id, 0)
	agent.cell = Vector2i.ZERO
	world.add_agent(agent)
	assert_true(agent.movement_admitted)
	assert_eq(world.agents, [agent] as Array[SimAgent])
	assert_true(world.pending_agents().is_empty())


func _staff(trait_id: StringName) -> MotionStaff:
	var member: StaffMember = StaffMember.new()
	member.id = &"movement_fixture"
	member.display_name = "Walker"
	member.trait_id = trait_id
	var staff: MotionStaff = MotionStaff.new()
	staff.configure_member(member, CATALOGUE.find_trait(trait_id))
	return staff


func _route(agent: SimAgent, cells: Array[Vector2i]) -> void:
	assert_eq(agent.cell, cells[0], "fixture never teleports an admitted actor")
	agent.install_movement_route(cells)


func _step(world: SimWorld, agent: SimAgent) -> SimAgent.MoveResult:
	world.advance()
	if world.movement.is_stopping(agent.id):
		return SimAgent.MoveResult.MOVING
	if agent is MotionStaff:
		return (agent as MotionStaff).last_move
	if agent is MotionOwner:
		return (agent as MotionOwner).last_move
	fail("only an admitted movement test driver may advance the actual world")
	return SimAgent.MoveResult.BLOCKED


func _move(world: SimWorld, agent: SimAgent, ticks: int) -> void:
	for tick: int in range(ticks):
		_step(world, agent)


func _arrival_ticks(world: SimWorld, agent: SimAgent) -> int:
	for tick: int in range(1, 1001):
		if _step(world, agent) == SimAgent.MoveResult.ARRIVED:
			return tick
	fail("movement did not arrive within its bounded test path")
	return 1001


func _finish_stop(world: SimWorld, agent: SimAgent) -> void:
	for tick: int in range(16):
		if not world.movement.is_stopping(agent.id):
			return
		_step(world, agent)
	fail("reserved edge did not finish within its bounded isolated fixture")


func _assert_gain(steady_ticks: int, quick_ticks: int) -> void:
	var fewer: float = float(steady_ticks - quick_ticks) / float(steady_ticks)
	assert_true(fewer >= 0.13 and fewer <= 0.15, "actual arrival ticks must decrease by 13-15 percent")


func _snapshot(agent: SimAgent) -> Dictionary:
	return {"cell": agent.cell, "path": agent.path, "index": agent.path_index,
		"progress": agent.move_progress, "last_progress": agent.last_progress_tick, "repath": agent.needs_repath}


## Exact legacy state transition, used only to protect neutral behavior.
func _legacy_step(agent: SimAgent, world: SimWorld) -> SimAgent.MoveResult:
	if agent.has_arrived():
		return SimAgent.MoveResult.ARRIVED
	var next: Vector2i = agent.path[agent.path_index]
	if not world.grid.is_walkable(next):
		return SimAgent.MoveResult.BLOCKED
	var delta: Vector2i = next - agent.cell
	var length: float = GridMath.DIAGONAL_COST if delta.x != 0 and delta.y != 0 else 1.0
	length = maxf(length, float(maxi(absi(delta.x), absi(delta.y))))
	agent.move_progress += agent.move_speed / length
	agent.last_progress_tick = world.now
	if agent.move_progress >= 1.0:
		agent.move_progress = 0.0
		agent.cell = next
		agent.path_index += 1
		agent.last_progress_tick = world.now
	return SimAgent.MoveResult.ARRIVED if agent.has_arrived() else SimAgent.MoveResult.MOVING
