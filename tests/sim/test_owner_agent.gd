extends TestCase
## Real owner task cleanup, gradual home movement and kitchen participation.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

class CountingGrid:
	extends SimGrid
	var searches: int = 0

	func _init() -> void:
		super(Vector2i(10, 8))

	func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
		searches += 1
		return super.find_path(start, goal)

var _grid: CountingGrid
var _world: SimWorld
var _owner: OwnerAgent
var _station: PlacedItem
var _work_done: int = 0
var _real_sim: RestaurantSim
var _real_owner_id: int = -1
var _owner_cooks: int = 0


func before_each() -> void:
	_grid = CountingGrid.new()
	_station = _grid.place(Vector2i(2, 1), Vector2i(4, 2), 0, true,
		[Vector2i(0, 1)] as Array[Vector2i])
	_world = SimWorld.new(_grid)
	_owner = OwnerAgent.new(Vector2i(1, 1))
	_world.add_agent(_owner)


func after_each() -> void:
	for agent: SimAgent in _world.agents.duplicate():
		_world.remove_agent(agent)
	if _real_sim != null:
		if _real_sim.world.board.task_completed.is_connected(_on_real_task_completed):
			_real_sim.world.board.task_completed.disconnect(_on_real_task_completed)
		for agent: SimAgent in _real_sim.world.agents.duplicate():
			if agent is OwnerAgent:
				_real_sim.world.remove_agent(agent)
		_real_sim = null


func test_modes_keep_owner_role_skills_and_disable_inherited_priorities() -> void:
	assert_eq(_owner.current_mode(), &"rest")
	assert_eq(_owner.home_cell(), Vector2i(1, 1))
	assert_eq(_owner.cell, _owner.home_cell())
	var expected: Dictionary = {&"kitchen": [3, 0], &"floor": [0, 3], &"help": [1, 1], &"rest": [0, 0]}
	for mode: StringName in OwnerAgent.MODES:
		assert_true(_owner.assign_mode(mode))
		assert_eq(_owner.current_mode(), mode)
		assert_eq(_owner.role, &"owner")
		assert_eq(_owner.skill_for(&"cook"), 3)
		assert_eq(_owner.skill_for(&"server"), 3)
		assert_eq(_owner.priorities[&"cook"], expected[mode][0])
		assert_eq(_owner.priorities[&"server"], expected[mode][1])
		assert_eq(_owner.priorities[&"owner"], 0)
		assert_eq(_owner.priorities[&"any"], 0)
	var before: Dictionary = _owner.priorities.duplicate()
	assert_false(_owner.assign_mode(&"unknown"))
	assert_eq(_owner.current_mode(), &"rest")
	assert_eq(_owner.priorities, before)


func test_rest_drops_real_claim_and_reservation_on_next_tick_without_finishing() -> void:
	var held: SimTask = _hold_work(&"cook", &"kitchen")
	var work_cell: Vector2i = _station.work_cells[0]
	var before_cell: Vector2i = _owner.cell
	var before_tick: int = _world.now
	assert_true(_owner.assign_mode(&"rest"))
	assert_eq(_world.now, before_tick, "assignment never advances the world")
	assert_eq(held.claimed_by, _owner.id, "release is applied by the next owner tick")
	assert_eq(_station.reserved_by(work_cell), _owner.id)
	_world.advance()
	assert_eq(_world.now, before_tick + 1)
	assert_null(_owner.task)
	assert_eq(held.state, SimTask.State.OPEN)
	assert_eq(held.claimed_by, -1)
	assert_eq(held.drops, 1)
	assert_eq(_station.reserved_by(work_cell), -1)
	assert_eq(_work_done, 0, "rest does not simulate the work callback")
	assert_eq(_owner.cell, before_cell, "walking home does not teleport")
	assert_true(_owner.move_progress > 0.0)
	assert_false(_owner.path.is_empty())
	_run(100)
	assert_eq(_owner.cell, _owner.home_cell())
	assert_eq(_owner.why(), "Standing back at home")
	assert_eq(_work_done, 0)
	assert_eq(held.drops, 1, "rest does not repeatedly reclaim/drop the open work")


func test_repeated_rest_preserves_return_progress_and_does_not_drop_twice() -> void:
	var held: SimTask = _hold_work(&"cook", &"kitchen")
	assert_true(_owner.assign_mode(&"rest"))
	_world.advance()
	var before_cell: Vector2i = _owner.cell
	var before_progress: float = _owner.move_progress
	var before_path: Array[Vector2i] = _owner.path.duplicate()
	var before_tick: int = _world.now
	for repeat: int in 5:
		assert_true(_owner.assign_mode(&"rest"))
	assert_eq(_owner.cell, before_cell)
	assert_eq(_owner.move_progress, before_progress)
	assert_eq(_owner.path, before_path)
	assert_eq(_world.now, before_tick)
	assert_eq(held.drops, 1)
	_run(100)
	assert_eq(_owner.cell, _owner.home_cell())
	assert_eq(held.drops, 1)


func test_kitchen_to_floor_releases_now_disabled_cooking() -> void:
	_assert_reassignment_releases(&"cook", &"kitchen", &"floor")


func test_floor_to_kitchen_releases_now_disabled_service_work() -> void:
	_assert_reassignment_releases(&"server", &"floor", &"kitchen")


func test_help_keeps_enabled_work_and_repeated_assignment_keeps_claim() -> void:
	var held: SimTask = _hold_work(&"cook", &"kitchen")
	assert_true(_owner.assign_mode(&"help"))
	_world.advance()
	assert_eq(_owner.task, held)
	assert_eq(held.claimed_by, _owner.id)
	assert_eq(held.drops, 0)
	assert_eq(_station.reserved_by(_station.work_cells[0]), _owner.id)
	var remaining: float = _owner.work_left
	assert_true(_owner.assign_mode(&"help"))
	assert_eq(_owner.work_left, remaining)
	assert_eq(held.drops, 0)


func test_rest_cleans_stale_reference_without_dropping_another_workers_claim() -> void:
	var held: SimTask = _hold_work(&"cook", &"kitchen")
	_world.board.drop(held, &"external_retry")
	var other: StaffAgent = StaffAgent.new(&"cook", 3)
	other.cell = Vector2i(1, 2)
	_world.add_agent(other)
	other.tick(_world)
	assert_eq(other.task, held, "the ordinary worker claims the reopened task")
	assert_eq(held.claimed_by, other.id)
	assert_true(_owner.assign_mode(&"rest"))
	_world.advance()
	assert_null(_owner.task)
	assert_eq(held.claimed_by, other.id)
	assert_eq(held.drops, 1, "owner must not drop a replacement claimant's work")
	assert_eq(_station.reserved_by(_station.work_cells[0]), other.id)


func test_owner_never_claims_any_or_owner_role_work_in_any_mode() -> void:
	for role: StringName in [&"any", &"owner"]:
		var work: SimTask = SimTask.new(&"misc", role, "Unassigned work")
		work.steps.append(TaskStep.work(1, "work", _on_work_done))
		_world.board.post(work, _world.now)
	for mode: StringName in OwnerAgent.MODES:
		assert_true(_owner.assign_mode(mode))
		_run(3)
		assert_null(_owner.task)
	assert_eq(_world.board.open_tasks().size(), 2)
	assert_eq(_work_done, 0)


func test_reassignment_preserves_normal_drop_limit_and_task_payload() -> void:
	var held: SimTask = _hold_work(&"cook", &"kitchen")
	held.payload["ingredients_taken"] = true
	for drop: int in TaskBoard.MAX_DROPS:
		assert_true(_owner.assign_mode(&"rest"))
		_world.advance()
		assert_eq(held.drops, drop + 1)
		assert_eq(held.payload["ingredients_taken"], true)
		assert_eq(_station.reserved_by(_station.work_cells[0]), -1)
		if drop + 1 < TaskBoard.MAX_DROPS:
			assert_true(_owner.assign_mode(&"kitchen"))
			_world.advance()
			assert_eq(_owner.task, held)
	assert_eq(held.state, SimTask.State.CANCELLED)
	assert_eq(_work_done, 0)


func test_home_walk_is_gradual_without_hidden_ticks() -> void:
	_owner.cell = Vector2i(8, 6)
	_world.advance()
	assert_eq(_world.now, 1)
	assert_eq(_owner.cell, Vector2i(8, 6))
	assert_true(_owner.move_progress > 0.0 and _owner.move_progress < 1.0)
	assert_true(_owner.why().contains("walking home"))
	_run(150)
	assert_eq(_owner.cell, _owner.home_cell())
	assert_true(_owner.path.is_empty())
	assert_eq(_world.now, 151)


func test_blocked_home_has_bounded_searches_and_recovers_after_geometry_change() -> void:
	_owner.cell = Vector2i(8, 6)
	_grid.set_terrain(_owner.home_cell(), SimGrid.Terrain.WALL)
	_run(100)
	assert_eq(_grid.searches, OwnerAgent.HOME_ATTEMPTS)
	assert_eq(_owner.cell, Vector2i(8, 6))
	assert_null(_owner.task)
	assert_true(_owner.path.is_empty())
	assert_true(_owner.why().contains("waiting for a shop change"))
	assert_true(_owner.assign_mode(&"rest"))
	_run(100)
	assert_eq(_grid.searches, OwnerAgent.HOME_ATTEMPTS, "repeated rest does not reset a spent budget")
	_grid.set_terrain(_owner.home_cell(), SimGrid.Terrain.FLOOR)
	_run(150)
	assert_eq(_owner.cell, _owner.home_cell())
	assert_eq(_grid.searches, OwnerAgent.HOME_ATTEMPTS + 1)


func test_walkable_but_unreachable_home_stays_honest_and_never_teleports() -> void:
	_owner.cell = Vector2i(8, 6)
	for block: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 2)]:
		_grid.set_terrain(block, SimGrid.Terrain.WALL)
	assert_true(_grid.is_walkable(_owner.home_cell()))
	_run(100)
	assert_eq(_grid.searches, OwnerAgent.HOME_ATTEMPTS)
	assert_eq(_owner.cell, Vector2i(8, 6))
	assert_true(_owner.why().contains("no route"))
	assert_true(_owner.path.is_empty())


func test_blocked_home_when_already_there_is_reported_without_movement() -> void:
	_grid.set_terrain(_owner.home_cell(), SimGrid.Terrain.WALL)
	_world.advance()
	assert_eq(_owner.cell, _owner.home_cell())
	assert_eq(_grid.searches, 0)
	assert_true(_owner.why().contains("home spot is blocked"))
	_grid.set_terrain(_owner.home_cell(), SimGrid.Terrain.FLOOR)
	_world.advance()
	assert_eq(_owner.why(), "Standing back at home")


func test_stalled_home_movement_is_bounded_and_can_be_reassigned() -> void:
	_owner.cell = Vector2i(8, 6)
	_owner.move_speed = 0.0
	_run((OwnerAgent.HOME_STALL_TICKS + OwnerAgent.HOME_RETRY_TICKS) * OwnerAgent.HOME_ATTEMPTS + 10)
	assert_eq(_grid.searches, OwnerAgent.HOME_ATTEMPTS)
	assert_eq(_owner.cell, Vector2i(8, 6))
	assert_true(_owner.why().contains("no movement"))
	assert_true(_owner.why().contains("waiting for a shop change"))
	assert_true(_owner.path.is_empty())
	_owner.move_speed = 0.25
	assert_true(_owner.assign_mode(&"help"))
	assert_true(_owner.assign_mode(&"rest"))
	_run(150)
	assert_eq(_owner.cell, _owner.home_cell())


func test_changed_return_path_replans_instead_of_teleporting() -> void:
	_owner.cell = Vector2i(8, 6)
	_world.advance()
	var blocked: Vector2i = _owner.next_cell()
	_grid.set_terrain(blocked, SimGrid.Terrain.WALL)
	_world.advance()
	assert_ne(_owner.cell, _owner.home_cell())
	_run(180)
	assert_eq(_owner.cell, _owner.home_cell())
	assert_true(_owner.path.is_empty())


func test_removal_disconnects_home_geometry_callback_and_releases_owner() -> void:
	_world.advance()
	var connections: int = _grid.cells_changed.get_connections().size()
	var observed: WeakRef = weakref(_owner)
	_world.remove_agent(_owner)
	assert_eq(_grid.cells_changed.get_connections().size(), connections - 1)
	_owner = null
	assert_null(observed.get_ref(), "a live grid cannot retain a removed owner")


func test_seeded_real_kitchen_work_is_completed_by_owner_with_normal_staff_present() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	_real_sim = RestaurantSim.create(LAYOUT, content, 42, errors, stock)
	assert_eq(errors, [] as Array[String])
	var owner: OwnerAgent = _real_sim.owner_agent()
	assert_not_null(owner)
	if owner == null:
		return
	_real_owner_id = owner.id
	assert_true(owner.assign_mode(&"kitchen"))
	_real_sim.world.board.task_completed.connect(_on_real_task_completed)
	assert_true(_real_sim.world.clock.start_service())
	for tick: int in 30000:
		_real_sim.advance()
		if _real_sim.world.clock.phase == SimClock.Phase.CLOSED:
			break
	assert_eq(_real_sim.world.clock.phase, SimClock.Phase.CLOSED)
	assert_true(_owner_cooks > 0, "the real kitchen records completed cooking by the owner")
	assert_true(_real_sim.served_today > 0)
	assert_eq(owner.role, &"owner")
	var paid_staff: Dictionary[StringName, int] = {&"cook": 0, &"server": 0}
	var owners: int = 0
	for agent: SimAgent in _real_sim.world.agents:
		if agent is OwnerAgent:
			owners += 1
		if agent is StaffAgent and paid_staff.has(agent.role):
			paid_staff[agent.role] += 1
			assert_eq((agent as StaffAgent).priorities[agent.role], 2, "ordinary staff remain active")
	assert_eq(paid_staff, {&"cook": 1, &"server": 1})
	assert_eq(owners, 1, "the real factory supplies exactly one owner")


func test_factory_has_one_resting_owner_at_authored_spawn_and_preserves_paid_staff() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_real_sim = RestaurantSim.create(LAYOUT, content, 42, errors)
	assert_eq(errors, [] as Array[String])
	var owner: OwnerAgent = _real_sim.owner_agent()
	assert_not_null(owner)
	if owner == null:
		return
	assert_eq(owner.cell, LAYOUT.staff_spawns[&"owner"])
	assert_eq(owner.home_cell(), owner.cell)
	assert_eq(_real_sim.staff_spawns[&"owner"], owner.cell)
	assert_eq(owner.current_mode(), &"rest")
	assert_eq(_real_sim.world.agents.size(), 3)
	for agent: SimAgent in _real_sim.world.agents:
		if agent == owner:
			assert_eq(owner.priorities, {&"owner": 0, &"any": 0, &"cook": 0, &"server": 0,
				&"cleaner": 0}, "a resting owner cannot take any staff task")
		else:
			assert_true(agent.role in [&"cook", &"server"])
			assert_eq((agent as StaffAgent).priorities[agent.role], 2)
			assert_eq((agent as StaffAgent).priorities[&"any"], 1)
	assert_true(_real_sim.assign_owner(&"help"))
	owner.cell = Vector2i(7, 9)
	_real_sim.start_day()
	assert_eq(owner.cell, LAYOUT.staff_spawns[&"owner"])
	assert_eq(owner.current_mode(), &"help", "normal morning reset keeps the assignment")
	assert_false(_real_sim.assign_owner(&"invalid"))
	assert_eq(owner.current_mode(), &"help")


func test_factory_reports_missing_owner_spawn_without_creating_a_fallback_owner() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	layout.staff_spawns.erase(&"owner")
	var errors: Array[String] = []
	_real_sim = RestaurantSim.create(layout, content, 42, errors)
	assert_true(errors.has("%s: missing owner spawn" % layout.id))
	assert_null(_real_sim.owner_agent())
	assert_false(_real_sim.assign_owner(&"kitchen"))
	assert_eq(_real_sim.world.agents.size(), 2)


func test_manual_restaurant_without_factory_owner_refuses_assignment() -> void:
	var sim: RestaurantSim = RestaurantSim.new()
	assert_null(sim.owner_agent())
	assert_false(sim.assign_owner(&"rest"))
	sim.world = _world
	assert_true(sim.owner_agent() == _owner)
	assert_true(sim.assign_owner(&"floor"))
	_world.remove_agent(_owner)
	assert_null(sim.owner_agent())
	assert_false(sim.assign_owner(&"floor"))


func _hold_work(role: StringName, mode: StringName) -> SimTask:
	assert_true(_owner.assign_mode(mode))
	var work: SimTask = SimTask.new(&"work", role, "Long work")
	work.steps.append(TaskStep.go_to_item(_station.id, "using station"))
	work.steps.append(TaskStep.work(300, "working", _on_work_done))
	_world.board.post(work, _world.now)
	for tick: int in 100:
		_world.advance()
		if _owner.task == work and _owner.step_index == 1:
			break
	assert_eq(_owner.task, work)
	assert_eq(_owner.step_index, 1)
	assert_eq(_station.reserved_by(_station.work_cells[0]), _owner.id)
	return work


func _assert_reassignment_releases(role: StringName, previous: StringName, next: StringName) -> void:
	var held: SimTask = _hold_work(role, previous)
	assert_true(_owner.assign_mode(next))
	_world.advance()
	assert_null(_owner.task)
	assert_eq(held.state, SimTask.State.OPEN)
	assert_eq(held.drops, 1)
	assert_eq(_station.reserved_by(_station.work_cells[0]), -1)
	assert_eq(_work_done, 0)
	assert_eq(_owner.role, &"owner")


func _run(ticks: int) -> void:
	for tick: int in ticks:
		_world.advance()


func _on_work_done(_agent: SimAgent) -> bool:
	_work_done += 1
	return true


func _on_real_task_completed(task: SimTask) -> void:
	if task.kind == &"cook" and task.claimed_by == _real_owner_id:
		_owner_cooks += 1
