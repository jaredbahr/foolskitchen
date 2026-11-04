extends TestCase
## A real dining seat can border a locally open pocket whose only door is
## that same reserved seat. Staff must choose a reachable service approach.

var _content: ContentDB
var _sim: RestaurantSim
var _table: PlacedItem


class QueryMovement extends MovementCoordinator:
	var queried_starts: Array[Vector2i] = []

	func route(world: SimWorld, agent: SimAgent, from: Vector2i, to: Vector2i,
			avoid_people: bool = true) -> Array[Vector2i]:
		queried_starts.append(from)
		return super.route(world, agent, from, to, avoid_people)


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_sim = null
	_table = null
	_content = null


func test_reserved_seat_pocket_is_skipped_and_actual_server_completes_the_order() -> void:
	_build()
	var server: StaffAgent = _server(Vector2i(1, 2))
	var guest: CustomerAgent = _guest()
	assert_true(_sim.world.grid.walkable_neighbours(guest.seat_cell).has(Vector2i(3, 1)))
	assert_true(_sim.world.movement.route(_sim.world, server, server.cell, Vector2i(3, 1), false).is_empty())
	var before: int = guest.rng.state
	var task: SimTask = _post(guest)
	assert_eq(guest.rng.state, before, "approach queries do not draw the guest stream")
	if task == null:
		return
	assert_eq(task.steps[0].cell, Vector2i(2, 2), "keep the reachable side instead of the north pocket")
	assert_eq(_table.reserved_by(guest.seat_cell), guest.id)
	assert_true(_sim.world.clock.start_service())
	for _tick: int in 128:
		_sim.world.advance()
		var cells: Dictionary = {}
		for agent: SimAgent in _sim.world.agents:
			assert_false(cells.has(agent.cell), "the order must complete without entering another person's cell")
			cells[agent.cell] = agent.id
		if guest.order != null:
			break
	assert_not_null(guest.order, "the real take-order MOVE and WORK callback must finish")
	assert_eq(guest.state, CustomerAgent.State.WAITING_FOOD)
	assert_eq(server.cell, Vector2i(2, 2))
	assert_eq(task.state, SimTask.State.DONE)


func test_existing_north_preference_is_preserved_when_the_same_worker_can_reach_it() -> void:
	_build(true)
	_server(Vector2i(1, 2))
	var guest: CustomerAgent = _guest()
	var task: SimTask = _post(guest)
	if task != null:
		assert_eq(task.steps[0].cell, Vector2i(3, 1), "do not reorder already legal approaches")


func test_owner_only_floor_and_help_can_order_but_rest_and_kitchen_use_public_entry_fallback() -> void:
	for mode: StringName in [&"rest", &"kitchen", &"floor", &"help"]:
		_build()
		# Only an eligible owner already inside the pocket can legitimately use
		# it; a resting/cooking owner's location must not make it serviceable.
		var owner: OwnerAgent = OwnerAgent.new(Vector2i(3, 1))
		_sim.world.add_agent(owner)
		assert_true(owner.assign_mode(mode))
		var task: SimTask = _post(_guest())
		if task != null:
			assert_eq(task.steps[0].cell, Vector2i(3, 1) if mode in [&"floor", &"help"] else Vector2i(2, 2))


func test_no_server_yet_uses_seat_free_entry_route_without_fabricating_an_actor() -> void:
	_build()
	var guest: CustomerAgent = _guest()
	var count: int = _sim.world.agents.size()
	var task: SimTask = _post(guest)
	if task != null:
		assert_eq(task.steps[0].cell, Vector2i(2, 2))
	assert_eq(_sim.world.agents.size(), count)
	assert_true(_sim.world.pending_agents().is_empty())


func test_actual_job_mapping_off_excludes_cross_role_priority_from_approach_queries() -> void:
	_build()
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner")
	cleaner.cell = Vector2i(3, 1)
	cleaner.priorities[&"server"] = 2 # Legacy role priority alone is insufficient.
	assert_true(cleaner.set_job_priorities(StaffJobPriorities.new(&"cleaner")))
	assert_eq(cleaner.job_priorities().priority(StaffJobPriorities.job_for_task(&"take_order", cleaner.role)),
		StaffJobPriorities.Level.OFF)
	_sim.world.add_agent(cleaner)
	var task: SimTask = _post(_guest())
	if task != null:
		assert_eq(task.steps[0].cell, Vector2i(2, 2))


func test_partial_worker_queries_from_reserved_vertex_but_planned_route_starts_from_current_cell() -> void:
	_build()
	var movement: QueryMovement = QueryMovement.new()
	_sim.world.movement = movement
	var server: StaffAgent = _server(Vector2i(1, 2))
	var guest: CustomerAgent = _guest()
	assert_true(server.set_destination(_sim.world.grid, Vector2i(2, 2)))
	assert_eq(server.move_progress, 0.0)
	movement.queried_starts.clear()
	var initial: SimTask = _post(guest)
	assert_false(movement.queried_starts.is_empty())
	for start: Vector2i in movement.queried_starts:
		assert_eq(start, Vector2i(1, 2), "an ungranted future path is not a physical starting point")
	if initial == null:
		return
	_sim.world.board.cancel(initial, &"fixture_requery")
	server.step_move(_sim.world)
	assert_true(server.move_progress > 0.0)
	assert_eq(movement.snapshot()["next"].get(Vector2i(2, 2)), server.id)
	movement.queried_starts.clear()
	var replacement: SimTask = _post(guest)
	assert_not_null(replacement)
	assert_false(movement.queried_starts.is_empty())
	for start: Vector2i in movement.queried_starts:
		assert_eq(start, Vector2i(2, 2), "a partial move must finish its actual reserved edge")


func test_existing_serve_across_counter_target_is_unchanged_without_an_active_server() -> void:
	_build()
	var grid: SimGrid = _sim.world.grid
	assert_true(grid.remove(_table.id))
	_table = grid.place_def(_content.item(&"bar_section"), Vector2i(3, 3))
	assert_not_null(grid.place_def(_content.item(&"bar_stool"), Vector2i(3, 4)))
	var guest: CustomerAgent = _guest(Vector2i(3, 4))
	var expected: Vector2i = _sim.across_cell(_table.id, guest.seat_cell)
	assert_eq(expected, Vector2i(3, 2))
	var task: SimTask = _post(guest)
	if task != null:
		assert_eq(task.steps[0].cell, expected)


func _build(open_north: bool = false) -> void:
	_sim = RestaurantSim.new()
	var rows: PackedStringArray = PackedStringArray(["#######", "#.....#" if open_north else "###.###",
		"#...#.#", "#.....#", "#.....#", "#.....#", "#..E..#"])
	_sim.world = SimWorld.new(SimGrid.from_ascii(rows))
	_table = _sim.world.grid.place_def(_content.item(&"table_2"), Vector2i(3, 3), 1)
	assert_not_null(_table)
	var recipe: RecipeDef = _content.recipe(&"burger")
	_sim.menu = [recipe]
	for ingredient: IngredientDef in recipe.ingredients:
		_sim.stock.add(ingredient.id, 20, 1)


func _server(cell: Vector2i) -> StaffAgent:
	var server: StaffAgent = StaffAgent.new(&"server")
	server.cell = cell
	_sim.world.add_agent(server)
	assert_true(_sim.world.agents.has(server))
	return server


func _guest(seat: Vector2i = Vector2i(3, 2)) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 17
	var guest: CustomerAgent = CustomerAgent.new(_sim, random)
	guest.cell = Vector2i(1, 3)
	_sim.world.add_agent(guest)
	guest.table_item_id = _table.id
	guest.seat_cell = seat
	assert_true(_table.reserve(seat, guest.id))
	assert_true(_sim.world.reset_agent_position(guest, seat))
	guest.state = CustomerAgent.State.ORDERING
	return guest


func _post(guest: CustomerAgent) -> SimTask:
	guest.call("_post_order_task", _sim.world, _sim)
	var task: SimTask = guest.get("_task") as SimTask
	assert_not_null(task)
	return task
