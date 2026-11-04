extends TestCase
## Existing APIs only: real take-order walks bind to the worker who starts them.

const TABLE: ItemDef = preload("res://data/items/table_2.tres")
const BURGER: RecipeDef = preload("res://data/recipes/burger.tres")

var _sim: RestaurantSim
var _table: PlacedItem


func after_each() -> void:
	if _sim != null and _sim.world != null:
		for actor: SimAgent in _sim.world.all_agents():
			_sim.world.remove_agent(actor)
	_table = null
	_sim = null


func test_real_order_walk_keeps_posted_anchor_but_uses_nearby_service_side() -> void:
	_build()
	var server: StaffAgent = _server(Vector2i(5, 2))
	var guest: CustomerAgent = _guest_at_north_seat()
	assert_true(_sim.world.clock.start_service())
	assert_true(_advance_checked())
	var task: SimTask = _order_task()
	assert_not_null(task)
	if task == null:
		return
	assert_eq(task.steps[0].cell, Vector2i(3, 1), "the existing legal north anchor is still posted")
	var random_before: int = guest.rng.state
	assert_true(_first_go_started(server, task))
	assert_eq(guest.rng.state, random_before, "choosing a physical service approach consumes no guest RNG")
	assert_eq(server.destination(), Vector2i(4, 2), "the actual claimant walks one clear cell to the guest's right instead of detouring north")
	assert_eq(task.steps[0].cell, Vector2i(3, 1), "the posted anchor is not mutated by actual route selection")
	assert_true(_until_order(guest, task, server))
	assert_eq(server.cell, Vector2i(4, 2), "real taking-order WORK completes at the chosen adjacent service cell")
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(task.drops, 0)


func test_later_claimant_uses_own_position_when_post_time_worker_is_busy() -> void:
	_build()
	var busy: StaffAgent = _server(Vector2i(3, 1))
	var work: SimTask = SimTask.new(&"busy_service", &"server", "Existing real work")
	work.priority = 3
	work.steps.append(TaskStep.go_to_cell(Vector2i(3, 1)))
	work.steps.append(TaskStep.work(40))
	_sim.world.board.post(work, _sim.world.now)
	var guest: CustomerAgent = _guest_at_north_seat()
	assert_true(_sim.world.clock.start_service())
	for tick: int in 3:
		if not _advance_checked():
			return
	assert_eq(busy.task, work)
	assert_eq(work.state, SimTask.State.CLAIMED)
	assert_eq(busy.step_index, 1)
	assert_true(busy.work_left > 0.0)
	var task: SimTask = _order_task()
	assert_not_null(task)
	if task == null:
		return
	assert_eq(task.steps[0].cell, Vector2i(3, 1), "the worker at the anchor was already busy when this order was posted")
	var claimant: StaffAgent = _server(Vector2i(5, 2))
	assert_true(_first_go_started(claimant, task))
	assert_eq(task.claimed_by, claimant.id)
	assert_eq(claimant.destination(), Vector2i(4, 2), "late arrival and actual claim cannot inherit the busy worker's preferred origin")
	assert_eq(task.steps[0].cell, Vector2i(3, 1))
	assert_true(_until_order(guest, task, claimant))
	assert_eq(claimant.cell, Vector2i(4, 2))
	assert_eq(work.state, SimTask.State.CLAIMED, "the nearby service side finishes before the unrelated WORK40 ends")
	assert_eq(busy.cell, Vector2i(3, 1), "the busy worker keeps its actual productive cell")
	assert_true(busy.work_left > 0.0)
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(task.drops, 0)


func test_fixed_point_role_job_keeps_exact_destination() -> void:
	_build()
	var server: StaffAgent = _server(Vector2i(5, 2))
	var task: SimTask = SimTask.new(&"fixed_point", &"server", "Fixed-point work")
	task.steps.append(TaskStep.go_to_cell(Vector2i(3, 1)))
	task.steps.append(TaskStep.work(1))
	_sim.world.board.post(task, _sim.world.now)
	assert_true(_sim.world.clock.start_service())
	assert_true(_first_go_started(server, task))
	assert_eq(server.destination(), Vector2i(3, 1), "ordinary GO_TO_CELL keeps its exact authored point")
	for tick: int in task.timeout_ticks:
		if task.state == SimTask.State.DONE:
			break
		if not _advance_checked():
			return
	assert_eq(server.cell, Vector2i(3, 1))
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(task.drops, 0)


func test_wall_added_after_post_rejects_a_stale_service_side() -> void:
	_build()
	var server: StaffAgent = _server(Vector2i(5, 2))
	var guest: CustomerAgent = _guest_at_north_seat()
	assert_true(_sim.world.clock.start_service())
	assert_true(_advance_checked())
	var task: SimTask = _order_task()
	assert_not_null(task)
	if task == null:
		return
	assert_eq(task.steps[0].cell, Vector2i(3, 1))
	assert_true(_sim.world.grid.set_segment(Vector3i(4, 2, SimGrid.EDGE_WEST), SimGrid.Segment.WALL))
	assert_eq(_table.reserved_by(guest.seat_cell), guest.id, "the new side wall keeps the original valid dining hold")
	assert_eq(_sim.world.grid.dining_table_id(guest.seat_cell), _table.id)
	assert_false(_sim.world.grid.walkable_neighbours(guest.seat_cell).has(Vector2i(4, 2)))
	assert_true(_sim.world.grid.walkable_neighbours(guest.seat_cell).has(Vector2i(3, 1)))
	assert_false(_sim.world.movement.route(_sim.world, server, server.cell, Vector2i(4, 2), false).is_empty(),
		"the rejected side is still reachable by the worker, making contact geometry the discriminator")
	assert_true(_first_go_started(server, task))
	assert_eq(server.destination(), Vector2i(3, 1), "the actual walk must not serve through the newly added wall")
	assert_eq(task.steps[0].cell, Vector2i(3, 1))
	assert_true(_until_order(guest, task, server))
	assert_eq(server.cell, Vector2i(3, 1))
	assert_true(_sim.world.grid.walkable_neighbours(guest.seat_cell).has(server.cell), "actual order WORK is on a currently open service side")
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(task.drops, 0)


func _build() -> void:
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.from_ascii(PackedStringArray([
		"#######", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", "#..E..#"])))
	_table = _sim.world.grid.place_def(TABLE, Vector2i(3, 3), 1)
	assert_not_null(_table)
	_sim.menu = [BURGER] as Array[RecipeDef]
	for ingredient: IngredientDef in BURGER.ingredients:
		_sim.stock.add(ingredient.id, 20, 1)


func _server(cell: Vector2i) -> StaffAgent:
	var worker: StaffAgent = StaffAgent.new(&"server", 3)
	worker.cell = cell
	_sim.world.add_agent(worker)
	assert_true(worker.movement_admitted)
	return worker


func _guest_at_north_seat() -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 17
	var guest: CustomerAgent = _sim.add_customer(Vector2i(1, 3), random)
	var profile: RegularProfile = RegularProfile.new()
	profile.favourite_seat = Vector2i(3, 2)
	guest.regular_profile = profile
	assert_true(guest._try_seat(_sim.world))
	assert_eq(guest.seat_cell, Vector2i(3, 2))
	assert_true(_sim.world.reset_agent_position(guest, guest.seat_cell))
	return guest


func _order_task() -> SimTask:
	var tasks: Array[SimTask] = _sim.world.board.open_tasks()
	tasks.append_array(_sim.world.board.claimed_tasks())
	for task: SimTask in tasks:
		if task.kind == &"take_order":
			return task
	return null


func _first_go_started(worker: StaffAgent, task: SimTask) -> bool:
	for tick: int in 8:
		if worker.task == task and worker.destination() != SimGrid.NO_CELL:
			return true
		if not _advance_checked():
			return false
	fail("the real worker did not claim and start its existing first GO step")
	return false


func _until_order(guest: CustomerAgent, task: SimTask, worker: StaffAgent) -> bool:
	for tick: int in task.timeout_ticks:
		if guest.order != null:
			assert_eq(worker.move_progress, 0.0, "order WORK completes at a physical vertex")
			assert_true(worker.has_arrived(), "order WORK does not complete along a route")
			assert_eq(guest.state, CustomerAgent.State.WAITING_FOOD)
			return true
		if not _advance_checked():
			return false
	fail("the real take-order WORK callback did not place the guest's order within its unchanged task budget")
	return false


func _advance_checked() -> bool:
	var before: Dictionary = MovementInvariants.capture(_sim.world)
	_sim.world.advance()
	var problem: String = MovementInvariants.problem(_sim.world, before)
	assert_eq(problem, "", "all real people, seat rights, partial edges and timed traces remain valid")
	return problem.is_empty()
