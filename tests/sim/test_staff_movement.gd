extends TestCase
## Arrival-time regressions for the opt-in trait cadence. No balance sampling.

const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")


func test_quick_arrives_thirteen_to_fifteen_percent_sooner_on_long_straight_path() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray([".".repeat(101)])))
	var steady: StaffAgent = _staff(&"steady")
	var quick: StaffAgent = _staff(&"quick")
	for agent: StaffAgent in [steady, quick]:
		world.add_agent(agent)
		assert_true(agent.set_destination(world.grid, Vector2i(100, 0)))
		assert_eq(agent.path.size(), 101)
	var steady_ticks: int = _arrival_ticks(world, steady)
	var quick_ticks: int = _arrival_ticks(world, quick)
	assert_eq(steady_ticks, 400, "the old four ticks per straight cell stay exact")
	assert_eq(quick_ticks, 348)
	_assert_gain(steady_ticks, quick_ticks)
	assert_eq(quick.cell, Vector2i(100, 0))
	assert_almost_eq(quick.move_progress, 0.0)


func test_quick_arrives_thirteen_to_fifteen_percent_sooner_on_long_diagonal_path() -> void:
	var rows: PackedStringArray = []
	for row: int in range(101):
		rows.append(".".repeat(101))
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(rows))
	var steady: StaffAgent = _staff(&"steady")
	var quick: StaffAgent = _staff(&"quick")
	for agent: StaffAgent in [steady, quick]:
		world.add_agent(agent)
		assert_true(agent.set_destination(world.grid, Vector2i(100, 100)))
		assert_eq(agent.path.size(), 101)
		for index: int in range(1, agent.path.size()):
			assert_eq(agent.path[index] - agent.path[index - 1], Vector2i.ONE)
	var steady_ticks: int = _arrival_ticks(world, steady)
	var quick_ticks: int = _arrival_ticks(world, quick)
	assert_eq(steady_ticks, 600, "the old six ticks per diagonal cell stay exact")
	assert_eq(quick_ticks, 522)
	_assert_gain(steady_ticks, quick_ticks)
	assert_eq(quick.cell, Vector2i(100, 100))


func test_residual_tick_credit_converts_using_the_next_edges_cost_in_both_directions() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["...", "..."])))
	var quick: StaffAgent = _staff(&"quick")
	_route(quick, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 1)])
	_move(world, quick, 4)
	assert_eq(quick.cell, Vector2i(1, 0))
	assert_eq(quick.path_index, 2)
	assert_almost_eq(quick.move_progress, 0.1, 0.000000001,
		"0.6 baseline ticks left after the straight edge become 0.6/6 of the diagonal")
	_route(quick, [Vector2i.ZERO, Vector2i(1, 1), Vector2i(2, 1)])
	_move(world, quick, 6)
	assert_eq(quick.cell, Vector2i(1, 1))
	assert_almost_eq(quick.move_progress, 0.225, 0.000000001,
		"0.9 baseline ticks left after the diagonal become 0.9/4 of the straight edge")


func test_every_residual_edge_checks_walkability_and_blocking_does_not_bank_credit() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["...", "..."]))
	var blocker: PlacedItem = grid.place(Vector2i.ONE, Vector2i(2, 1), 0, true)
	assert_not_null(blocker)
	var world: SimWorld = SimWorld.new(grid)
	var quick: StaffAgent = _staff(&"quick")
	_route(quick, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 1)])
	_move(world, quick, 3)
	assert_eq(quick.step_move(world), SimAgent.MoveResult.BLOCKED)
	assert_eq(quick.cell, Vector2i(1, 0), "the walkable edge completes; the blocked edge is never entered")
	assert_eq(quick.path_index, 2)
	assert_almost_eq(quick.move_progress, 0.0)
	for wait: int in range(12):
		assert_eq(quick.step_move(world), SimAgent.MoveResult.BLOCKED)
		assert_almost_eq(quick.move_progress, 0.0)
	grid.remove(blocker.id)
	assert_eq(quick.step_move(world), SimAgent.MoveResult.MOVING)
	assert_almost_eq(quick.move_progress, 1.15 / 6.0, 0.000000001,
		"unblocking receives one new tick, not saved credit from the blocked period")


func test_arrival_idle_clear_and_changed_next_repath_cannot_store_extra_movement() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["....", "....", "...."])))
	var quick: StaffAgent = _staff(&"quick")
	assert_true(quick.set_destination(world.grid, Vector2i(1, 0)))
	assert_eq(_arrival_ticks(world, quick), 4)
	for idle: int in range(12):
		assert_eq(quick.step_move(world), SimAgent.MoveResult.ARRIVED)
	assert_almost_eq(quick.move_progress, 0.0)
	assert_true(quick.set_destination(world.grid, Vector2i(3, 0)))
	_move(world, quick, 1)
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001)
	assert_true(quick.repath(world.grid))
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001, "the same next cell keeps actual drawn progress")
	assert_true(quick.set_destination(world.grid, Vector2i(1, 2)))
	assert_almost_eq(quick.move_progress, 0.0, 0.000000001, "a changed next cell resets progress")
	_move(world, quick, 1)
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001)
	quick.clear_path()
	assert_almost_eq(quick.move_progress, 0.0)
	assert_true(quick.set_destination(world.grid, Vector2i(1, 2)))
	_move(world, quick, 1)
	assert_almost_eq(quick.move_progress, 0.2875, 0.000000001, "clear_path also discards the partial path")


func test_quick_retains_the_legacy_buried_start_exit_length() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([".....", "....."]))
	assert_not_null(grid.place(Vector2i.ONE, Vector2i.ZERO, 0, true))
	var world: SimWorld = SimWorld.new(grid)
	var quick: StaffAgent = _staff(&"quick")
	_route(quick, [Vector2i.ZERO, Vector2i(3, 0), Vector2i(4, 1)])
	_move(world, quick, 11)
	assert_eq(quick.cell, Vector2i(3, 0))
	assert_almost_eq(quick.move_progress, 0.65 / 6.0, 0.000000001)


func test_steady_and_owner_match_the_old_movement_state_on_every_tick() -> void:
	# This reference is the pre-carry movement body, deliberately preserved below.
	# Check mixed edges, the long exit out of a buried start and a blocked target.
	for actual: SimAgent in [_staff(&"steady"), OwnerAgent.new()]:
		var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([".....", ".....", "....."]))
		grid.place(Vector2i.ONE, Vector2i.ZERO, 0, true)
		var blocker: PlacedItem = grid.place(Vector2i.ONE, Vector2i(4, 2), 0, true)
		var world: SimWorld = SimWorld.new(grid)
		var legacy: SimAgent = SimAgent.new()
		world.add_agent(actual)
		world.add_agent(legacy)
		var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, 0), Vector2i(4, 1), Vector2i(4, 2)]
		_route(actual, cells)
		_route(legacy, cells)
		assert_eq(actual.movement_multiplier(), 1.0)
		for tick: int in range(24):
			world.now += 1
			assert_eq(actual.step_move(world), _legacy_step(legacy, world))
			assert_eq(_snapshot(actual), _snapshot(legacy), "neutral movement stays identical on every tick")
		grid.remove(blocker.id)
		for tick: int in range(8):
			world.now += 1
			assert_eq(actual.step_move(world), _legacy_step(legacy, world))
			assert_eq(_snapshot(actual), _snapshot(legacy))
		assert_true(actual.has_arrived())


func _staff(trait_id: StringName) -> StaffAgent:
	var member: StaffMember = StaffMember.new()
	member.id = &"movement_fixture"
	member.display_name = "Walker"
	member.trait_id = trait_id
	var staff: StaffAgent = StaffAgent.new()
	staff.configure_member(member, CATALOGUE.find_trait(trait_id))
	return staff


func _route(agent: SimAgent, cells: Array[Vector2i]) -> void:
	agent.cell = cells[0]
	agent.path = cells.duplicate()
	agent.path_index = 1
	agent.move_progress = 0.0


func _move(world: SimWorld, agent: SimAgent, ticks: int) -> void:
	for tick: int in range(ticks):
		world.now += 1
		agent.step_move(world)


func _arrival_ticks(world: SimWorld, agent: SimAgent) -> int:
	for tick: int in range(1, 1001):
		world.now += 1
		if agent.step_move(world) == SimAgent.MoveResult.ARRIVED:
			return tick
	fail("movement did not arrive within its bounded test path")
	return 1001


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
