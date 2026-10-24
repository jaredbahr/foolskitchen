extends TestCase
## The board owns the walk/work lifecycle; cleaning settles only on completion.

const TUNING: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")


func test_posts_one_low_priority_walk_and_30_tick_work_task_per_spot() -> void:
	var world: SimWorld = _world()
	var dirt: CleanlinessState = _dirt(world)
	var controller: CleanTaskController = CleanTaskController.new(world, dirt, TUNING)
	var first: Vector2i = Vector2i(1, 1)
	var second: Vector2i = Vector2i(2, 1)
	assert_true(dirt.try_spawn_at_departed_seat(second))
	assert_true(dirt.try_spawn_at_departed_seat(first))
	controller.sync_spots()
	controller.sync_spots()
	assert_eq(controller.active_task_count(), 2)
	assert_eq(world.board.active_count(), 2)
	assert_eq(world.board.open_tasks()[0], controller.task_for(first), "sorted dirt cells post deterministically")
	for cell: Vector2i in [first, second] as Array[Vector2i]:
		var task: SimTask = controller.task_for(cell)
		assert_not_null(task)
		assert_eq(task.kind, &"clean_spot")
		assert_eq(task.role, &"cleaner")
		assert_eq(task.priority, 0)
		assert_true(task.defer_to_higher_priority)
		assert_eq(task.steps.size(), 2)
		assert_eq(task.steps[0].kind, TaskStep.Kind.GO_TO_CELL)
		assert_eq(task.steps[0].cell, cell)
		assert_eq(task.steps[1].kind, TaskStep.Kind.WORK)
		assert_eq(task.steps[1].ticks, 30)
	assert_eq(dirt.spot_count(), 2, "posting does not clean a spot")


func test_completion_clears_only_its_cell_and_preserves_daily_worst() -> void:
	var world: SimWorld = _world()
	var dirt: CleanlinessState = _dirt(world)
	var controller: CleanTaskController = CleanTaskController.new(world, dirt, TUNING)
	var first: Vector2i = Vector2i(1, 1)
	var second: Vector2i = Vector2i(2, 1)
	assert_true(dirt.try_spawn_at_departed_seat(first))
	assert_true(dirt.try_spawn_at_departed_seat(second))
	controller.sync_spots()
	var task: SimTask = controller.task_for(first)
	assert_true(world.board.claim(task, 7, world.now))
	world.board.complete(task)
	assert_false(dirt.has_spot(first))
	assert_true(dirt.has_spot(second))
	assert_eq(dirt.worst_today_count(), 2)
	assert_eq(controller.active_task_count(), 1)
	assert_eq(world.board.active_count(), 1)


func test_blocked_target_cancels_without_erasing_dirt_and_reposts_when_reopened() -> void:
	var world: SimWorld = _world()
	var dirt: CleanlinessState = _dirt(world)
	var controller: CleanTaskController = CleanTaskController.new(world, dirt, TUNING)
	var cell: Vector2i = Vector2i(1, 1)
	assert_true(dirt.try_spawn_at_departed_seat(cell))
	controller.sync_spots()
	var old_task: SimTask = controller.task_for(cell)
	assert_true(world.board.claim(old_task, 7, world.now))
	assert_true(world.grid.set_terrain(cell, SimGrid.Terrain.WALL))
	assert_eq(old_task.state, SimTask.State.CANCELLED)
	assert_true(dirt.has_spot(cell))
	assert_eq(controller.active_task_count(), 0)
	assert_eq(world.board.active_count(), 0)
	assert_true(world.grid.set_terrain(cell, SimGrid.Terrain.FLOOR))
	assert_not_null(controller.task_for(cell))
	assert_ne(controller.task_for(cell).id, old_task.id)
	assert_eq(world.board.active_count(), 1)


func test_exhausted_task_waits_for_layout_change_before_retrying() -> void:
	var world: SimWorld = _world()
	var dirt: CleanlinessState = _dirt(world)
	var controller: CleanTaskController = CleanTaskController.new(world, dirt, TUNING)
	var cell: Vector2i = Vector2i(1, 1)
	assert_true(dirt.try_spawn_at_departed_seat(cell))
	controller.sync_spots()
	var old_task: SimTask = controller.task_for(cell)
	for index: int in range(TaskBoard.MAX_DROPS):
		assert_true(world.board.claim(old_task, 8, world.now))
		world.board.drop(old_task, &"unreachable")
	controller.sync_spots()
	assert_eq(old_task.state, SimTask.State.CANCELLED)
	assert_eq(world.board.active_count(), 0, "a terminal failure cannot repost in a tight loop")
	assert_true(dirt.has_spot(cell))
	assert_true(world.grid.set_terrain(Vector2i(3, 1), SimGrid.Terrain.WALL))
	assert_not_null(controller.task_for(cell))
	assert_ne(controller.task_for(cell).id, old_task.id)
	assert_eq(world.board.active_count(), 1)


func test_external_removal_and_overnight_tidy_withdraw_open_and_claimed_tasks() -> void:
	var world: SimWorld = _world()
	var dirt: CleanlinessState = _dirt(world)
	var controller: CleanTaskController = CleanTaskController.new(world, dirt, TUNING)
	var first: Vector2i = Vector2i(1, 1)
	var second: Vector2i = Vector2i(2, 1)
	var third: Vector2i = Vector2i(3, 1)
	assert_true(dirt.try_spawn_at_departed_seat(first))
	assert_true(dirt.try_spawn_at_departed_seat(second))
	controller.sync_spots()
	var removed_task: SimTask = controller.task_for(first)
	assert_true(dirt.clear_spot(first))
	controller.sync_spots()
	assert_eq(removed_task.state, SimTask.State.CANCELLED)
	assert_eq(world.board.active_count(), 1)
	assert_true(dirt.try_spawn_at_departed_seat(third))
	controller.sync_spots()
	var open_task: SimTask = controller.task_for(third)
	var claimed_task: SimTask = controller.task_for(second)
	assert_true(world.board.claim(claimed_task, 9, world.now))
	controller.tidy_overnight()
	assert_eq(claimed_task.state, SimTask.State.CANCELLED)
	assert_eq(open_task.state, SimTask.State.CANCELLED)
	assert_eq(world.board.active_count(), 0)
	assert_eq(controller.active_task_count(), 0)
	assert_eq(dirt.spot_count(), 0)
	assert_eq(dirt.worst_today_count(), 0)
	controller.sync_spots()
	assert_eq(world.board.active_count(), 0)


func test_restaurant_arrival_spawns_a_walkable_spot_and_samples_both_patience_budgets_once() -> void:
	var sim: RestaurantSim = _restaurant(1001, 1.0, 1.0)
	assert_true(sim.world.clock.start_service())
	var guest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	guest_rng.seed = 5001
	var first: CustomerAgent = sim.add_customer(Vector2i(3, 3), guest_rng)
	assert_eq(sim.cleanliness.spot_count(), 1)
	var first_spot: Vector2i = sim.cleanliness.spots()[0]
	assert_true(sim.world.grid.is_walkable(first_spot), "a dirt decal never blocks the floor")
	assert_eq(sim.clean_tasks.active_task_count(), 1)
	var first_scale: float = sim.cleanliness.patience_multiplier()
	assert_eq(first.queue_patience, roundi(300.0 * first_scale))
	assert_eq(first.food_patience, roundi(1200.0 * first_scale))
	var first_queue_budget: int = first.queue_patience
	var first_food_budget: int = first.food_patience
	sim.add_customer(Vector2i(3, 3), guest_rng)
	assert_eq(sim.cleanliness.spot_count(), 2)
	assert_eq(sim.clean_tasks.active_task_count(), 2)
	assert_eq(first.queue_patience, first_queue_budget, "later dirt does not rescale a waiting guest")
	assert_eq(first.food_patience, first_food_budget)


func test_paid_departure_posts_one_seat_spot_after_release_but_unserved_guest_does_not() -> void:
	var sim: RestaurantSim = _restaurant(1002, 0.0, 1.0)
	assert_true(sim.world.clock.start_service())
	var guest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	guest_rng.seed = 5002
	var paid: CustomerAgent = sim.add_customer(Vector2i(3, 3), guest_rng)
	paid.seat_cell = Vector2i(2, 2)
	paid.paid = true
	paid.state = CustomerAgent.State.LEAVING
	sim.world.remove_agent(paid)
	assert_eq(paid.seat_cell, Vector2i(2, 2), "seat release retains the departed seat coordinate")
	assert_true(sim.cleanliness.has_spot(paid.seat_cell))
	assert_eq(sim.clean_tasks.active_task_count(), 1)
	var clean_rng: RandomNumberGenerator = sim.cleanliness.get("_rng") as RandomNumberGenerator
	var clean_rng_state: int = clean_rng.state
	sim.record_departure(paid)
	assert_eq(sim.cleanliness.spot_count(), 1)
	assert_eq(clean_rng.state, clean_rng_state, "duplicate recording draws no RNG")
	var unserved: CustomerAgent = sim.add_customer(Vector2i(3, 3), guest_rng)
	unserved.seat_cell = Vector2i(4, 2)
	sim.world.remove_agent(unserved)
	assert_eq(sim.cleanliness.spot_count(), 1)
	assert_false(sim.cleanliness.has_spot(unserved.seat_cell))


func test_restaurant_cleaner_completion_and_overnight_tidy_clear_tasks_without_losing_worst() -> void:
	var sim: RestaurantSim = _restaurant(1003, 0.0, 1.0)
	assert_true(sim.cleanliness.try_spawn_at_departed_seat(Vector2i(2, 2)))
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner", 5)
	cleaner.cell = Vector2i(2, 2)
	sim.world.add_agent(cleaner)
	sim.staff_spawns[&"cleaner"] = cleaner.cell
	for _tick: int in 60:
		sim.advance()
		if sim.cleanliness.spot_count() == 0:
			break
	assert_eq(sim.cleanliness.spot_count(), 0)
	assert_eq(sim.clean_tasks.active_task_count(), 0)
	assert_eq(sim.cleanliness.worst_today_count(), 1)
	assert_true(sim.cleanliness.try_spawn_at_departed_seat(Vector2i(3, 2)))
	sim.advance()
	assert_not_null(cleaner.task, "the cleaner has claimed this new spot")
	var claimed: SimTask = cleaner.task
	sim.start_day()
	assert_eq(claimed.state, SimTask.State.CANCELLED)
	assert_eq(sim.cleanliness.spot_count(), 0)
	assert_eq(sim.cleanliness.worst_today_count(), 0)
	assert_eq(sim.clean_tasks.active_task_count(), 0)
	assert_eq(sim.world.board.active_count(), 0)
	assert_null(cleaner.task)


func test_cleaner_skill_finishes_the_same_real_mop_task_sooner() -> void:
	var slow_ticks: int = _ticks_to_clean_with_skill(1)
	var fast_ticks: int = _ticks_to_clean_with_skill(5)
	assert_true(slow_ticks > 0 and fast_ticks > 0, "both cleaners finish within the bounded run")
	assert_true(fast_ticks < slow_ticks, "cleaner skill speeds up actual task completion")


func test_same_cleanliness_seed_replays_spots_and_patience_without_customer_rng_draws() -> void:
	var first: RestaurantSim = _restaurant(1010, 1.0, 0.0)
	var second: RestaurantSim = _restaurant(1010, 1.0, 0.0)
	assert_true(first.world.clock.start_service())
	assert_true(second.world.clock.start_service())
	var first_guest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var second_guest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	first_guest_rng.seed = 8008
	second_guest_rng.seed = 8008
	for _index: int in 5:
		var one: CustomerAgent = first.add_customer(Vector2i(3, 3), first_guest_rng)
		var two: CustomerAgent = second.add_customer(Vector2i(3, 3), second_guest_rng)
		assert_eq(first.cleanliness.spots(), second.cleanliness.spots())
		assert_eq(one.queue_patience, two.queue_patience)
		assert_eq(one.food_patience, two.food_patience)
	assert_eq(first_guest_rng.state, second_guest_rng.state)


func test_legacy_restaurant_without_cleanliness_preserves_budgets_and_rng() -> void:
	var sim: RestaurantSim = _restaurant(1011, -1.0, -1.0)
	assert_true(sim.world.clock.start_service())
	var guest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	guest_rng.seed = 8118
	var before: int = guest_rng.state
	var guest: CustomerAgent = sim.add_customer(Vector2i(3, 3), guest_rng)
	assert_eq(guest.queue_patience, 300)
	assert_eq(guest.food_patience, 1200)
	assert_eq(guest_rng.state, before)
	assert_null(sim.cleanliness)
	assert_null(sim.clean_tasks)
	assert_eq(sim.world.board.active_count(), 0)


func test_off_service_guest_injection_does_not_spawn_dirt_or_draw_its_stream() -> void:
	var sim: RestaurantSim = _restaurant(1012, 1.0, 1.0)
	var guest_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	guest_rng.seed = 8119
	var clean_rng: RandomNumberGenerator = sim.cleanliness.get("_rng") as RandomNumberGenerator
	var before: int = clean_rng.state
	var guest: CustomerAgent = sim.add_customer(Vector2i(3, 3), guest_rng)
	assert_eq(guest.queue_patience, 300)
	assert_eq(guest.food_patience, 1200)
	assert_eq(clean_rng.state, before)
	assert_eq(sim.cleanliness.spot_count(), 0)
	assert_eq(sim.clean_tasks.active_task_count(), 0)


func _restaurant(seed_value: int, arrival_chance: float, seat_chance: float) -> RestaurantSim:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"#######", "#.....#", "#.....#", "#..E..#", "#######",
	]))
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(grid)
	var guest_stream: RandomNumberGenerator = RandomNumberGenerator.new()
	guest_stream.seed = 41
	sim.spawner = CustomerSpawner.new(guest_stream)
	if arrival_chance >= 0.0:
		var tuning: CleanlinessTuning = TUNING.duplicate() as CleanlinessTuning
		tuning.arrival_chance = arrival_chance
		tuning.seat_departure_chance = seat_chance
		var clean_stream: RandomNumberGenerator = RandomNumberGenerator.new()
		clean_stream.seed = seed_value
		assert_true(sim.configure_cleanliness(CleanlinessState.new(grid, tuning, clean_stream), tuning))
	sim.start_day()
	return sim


func _world() -> SimWorld:
	return SimWorld.new(SimGrid.new(Vector2i(5, 3)))


func _dirt(world: SimWorld) -> CleanlinessState:
	var tuning: CleanlinessTuning = TUNING.duplicate() as CleanlinessTuning
	tuning.seat_departure_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 78005
	return CleanlinessState.new(world.grid, tuning, random)


func _ticks_to_clean_with_skill(skill: int) -> int:
	var world: SimWorld = _world()
	var dirt: CleanlinessState = _dirt(world)
	var controller: CleanTaskController = CleanTaskController.new(world, dirt, TUNING)
	var spot: Vector2i = Vector2i(2, 1)
	assert_true(dirt.try_spawn_at_departed_seat(spot))
	controller.sync_spots()
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner", skill)
	cleaner.cell = spot
	world.add_agent(cleaner)
	for elapsed: int in range(1, 61):
		world.advance()
		if not dirt.has_spot(spot):
			assert_eq(controller.active_task_count(), 0)
			return elapsed
	return -1
