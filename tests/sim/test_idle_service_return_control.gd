extends TestCase
## Source-only controls for actual coffee evidence. All movement and task claims
## come from public Board jobs and normal ticks; no actor/map/state repair.

const HISTORICAL: ShopLayout = preload("res://data/layouts/tier1_original.tres")
const COFFEE: ItemDef = preload("res://data/items/coffee_machine.tres")
const WATCHDOG: int = 512
var _sim: RestaurantSim
var _world: SimWorld
var _cook: StaffAgent
var _idle: StaffAgent
var _station: PlacedItem
var _service: SimTask
var _incoming: SimTask
var _service_cell: Vector2i
var _station_cell: Vector2i
var _service_callbacks: int = 0
var _work_callbacks: int = 0
var _failed: Array[Dictionary] = []
var _expected_agents: int = 0


func before_each() -> void:
	_service_callbacks = 0
	_work_callbacks = 0
	_failed.clear()


func after_each() -> void:
	if _world != null:
		_world.board.task_failed.disconnect(_on_failed)
		for actor: SimAgent in _world.all_agents():
			_world.remove_agent(actor)
	_sim = null
	_world = null
	_cook = null
	_idle = null
	_station = null
	_service = null
	_incoming = null


func test_completed_bar_service_waiter_clears_intermediate_cell_without_stale_return() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in content.ingredients():
		stock.add(ingredient.id, 50, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(_bar_layout(), content, 83, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	_world = _sim.world
	for actor: SimAgent in _world.agents:
		if actor.role == &"cook":
			_cook = actor as StaffAgent
		elif actor.role == &"server":
			_idle = actor as StaffAgent
	_station = ShopBuilder.items_with_def(_world, &"coffee_machine")[0]
	_service_cell = Vector2i(9, 6)
	_station_cell = Vector2i(12, 6)
	if not _complete_real_service():
		return
	_post_incoming()
	var saw_first_encounter: bool = false
	var saw_partial_idle_move: bool = false
	for tick: int in WATCHDOG:
		if not _advance():
			return
		if not saw_first_encounter and _cook.next_cell() == _idle.cell and _cook.move_progress == 0.0 \
				and not _world.movement.is_yielding(_idle.id):
			saw_first_encounter = true
			assert_eq(_cook.cell, Vector2i(9, 5), "test the recorded route's first actual approach rather than assume it")
			assert_eq(_idle.cell, _service_cell)
			assert_true(_world.movement.can_enter(_world, _idle, Vector2i(8, 6)), "the off-route pocket must really be free")
			assert_true(_world.grid.step_open(_idle.cell, Vector2i(8, 6)))
			assert_eq(_station.reserved_by(_station_cell), _cook.id)
		saw_partial_idle_move = saw_partial_idle_move or _idle.move_progress > 0.0
		if _incoming.state == SimTask.State.DONE:
			break
	assert_true(saw_first_encounter)
	assert_true(saw_partial_idle_move, "clearance is a real claimed walk, never disappearance")
	_assert_prepared()
	assert_false(_world.movement.is_yielding(_idle.id), "an idle employee cannot retain an obsolete service return")
	assert_true(_idle.has_arrived())
	assert_eq(_idle.move_progress, 0.0)
	assert_eq(_idle.destination(), _idle.cell, "future traffic must not revive the old service destination")
	assert_ne(_idle.cell, _service_cell)


func test_only_escape_behind_incoming_cook_requires_real_cooperative_retreat() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["##.##.", "......", "######"]))
	_station = grid.place_def(COFFEE, Vector2i(5, 0), 2)
	_world = SimWorld.new(grid)
	_cook = StaffAgent.new(&"cook")
	_cook.cell = Vector2i(2, 1)
	_world.add_agent(_cook)
	_idle = StaffAgent.new(&"server")
	_idle.cell = Vector2i(3, 1)
	_world.add_agent(_idle)
	_service_cell = Vector2i(3, 1)
	_station_cell = Vector2i(5, 1)
	if not _complete_real_service():
		return
	assert_true(_world.movement.can_enter(_world, _idle, Vector2i(2, 0)), "the endpoint behind the cook is free")
	assert_true(_world.movement.route(_world, _idle, _idle.cell, Vector2i(2, 0), true).is_empty(),
		"the idle actor cannot reach that pocket by bypassing the occupied cook")
	_post_incoming()
	var saw_cooperative_move: bool = false
	var saw_side_pocket: bool = false
	var saw_idle_move: bool = false
	for tick: int in WATCHDOG:
		if not _advance():
			return
		saw_cooperative_move = saw_cooperative_move or (_world.movement.is_yielding(_cook.id) and _cook.move_progress > 0.0)
		saw_side_pocket = saw_side_pocket or (_cook.cell == Vector2i(2, 0) and _cook.move_progress == 0.0) \
			or (_idle.cell == Vector2i(2, 0) and _idle.move_progress == 0.0)
		saw_idle_move = saw_idle_move or _idle.move_progress > 0.0
		if _incoming.state == SimTask.State.DONE:
			break
	assert_true(saw_cooperative_move)
	assert_true(saw_side_pocket, "one real actor physically reaches the side pocket; either valid exchange order is accepted")
	assert_true(saw_idle_move)
	_assert_prepared()
	assert_false(_world.movement.is_yielding(_idle.id))
	assert_eq(_idle.destination(), _idle.cell)


func _complete_real_service() -> bool:
	assert_not_null(_cook)
	assert_not_null(_idle)
	assert_not_null(_station)
	if _cook == null or _idle == null or _station == null:
		return false
	_expected_agents = _world.agents.size()
	_world.board.task_failed.connect(_on_failed)
	assert_true(_cook.id < _idle.id)
	assert_eq(_world.movement.priority(_world, _cook), _world.movement.priority(_world, _idle),
		"ordinary equal staff priority and stable ID choose the incoming cook")
	_service = SimTask.new(&"finished_service_control", &"server", "Finish real service at the bar")
	_service.steps = [TaskStep.go_to_cell(_service_cell), TaskStep.work(1, "finish service", _service_done)]
	_world.board.post(_service, _world.now)
	assert_true(_world.clock.start_service())
	for tick: int in 100:
		if not _advance():
			return false
		if _service.state == SimTask.State.DONE:
			break
	assert_eq(_service.state, SimTask.State.DONE)
	assert_eq(_service_callbacks, 1)
	assert_eq(_service.drops, 0)
	assert_null(_idle.task)
	assert_eq(_idle.cell, _service_cell)
	assert_eq(_idle.destination(), _service_cell, "the stale goal is produced by completed work, not fabricated")
	assert_true(_idle.has_arrived())
	return _service.state == SimTask.State.DONE


func _post_incoming() -> void:
	_incoming = SimTask.new(&"cook", &"cook", "Use the coffee station behind the idle waiter")
	_incoming.steps = [TaskStep.go_to_item(_station.id), TaskStep.work(4, "work at coffee station", _prepared)]
	assert_eq(_incoming.timeout_ticks, 600)
	_world.board.post(_incoming, _world.now)


func _assert_prepared() -> void:
	assert_eq(_incoming.state, SimTask.State.DONE, "real station work finishes before the unchanged600 timeout")
	assert_eq(_incoming.drops, 0)
	assert_eq(_failed, [] as Array[Dictionary])
	assert_eq(_work_callbacks, 1)
	assert_eq(_cook.cell, _station_cell)
	assert_eq(_cook.move_progress, 0.0)
	assert_eq(_station.reserved_by(_station_cell), -1, "completed work releases its real station lease")


func _advance() -> bool:
	var before: Dictionary = MovementInvariants.capture(_world)
	if _sim != null:
		_sim.advance()
	else:
		_world.advance()
	var problem: String = MovementInvariants.problem(_world, before)
	assert_eq(problem, "", "every body, swept edge and trace keeps full physical invariants")
	assert_eq(_world.agents.size(), _expected_agents, "clearance cannot hide/remove actors")
	assert_true(_world.pending_agents().is_empty())
	return problem.is_empty()


func _service_done(actor: SimAgent) -> bool:
	_service_callbacks += 1
	assert_eq(actor.id, _idle.id)
	assert_eq(actor.cell, _service_cell)
	assert_eq(actor.move_progress, 0.0)
	return actor.cell == _service_cell and actor.move_progress == 0.0


func _prepared(actor: SimAgent) -> bool:
	_work_callbacks += 1
	assert_eq(actor.id, _cook.id)
	assert_eq(actor.cell, _station_cell)
	assert_eq(actor.move_progress, 0.0)
	assert_eq(_station.reserved_by(_station_cell), actor.id)
	return actor.cell == _station_cell and actor.move_progress == 0.0


func _on_failed(task: SimTask, reason: StringName) -> void:
	_failed.append({"id": task.id, "reason": String(reason)})


func _bar_layout() -> ShopLayout:
	# Exact bespoke concept-test geometry: its rows/staff/items intentionally do
	# not carry room/wall metadata, matching the measured failing source.
	var layout: ShopLayout = ShopLayout.new()
	layout.id = &"idle_service_bar_control"
	layout.rows = HISTORICAL.rows.duplicate()
	layout.staff_spawns = HISTORICAL.staff_spawns.duplicate()
	for authored: ShopPlacement in HISTORICAL.placements:
		if authored.item_id == &"potted_plant" or (authored.item_id == &"table_2" and authored.origin == Vector2i(10, 6)):
			continue
		var placed: ShopPlacement = authored.duplicate(true) as ShopPlacement
		if placed.item_id == &"table_2" and placed.origin == Vector2i(6, 6):
			placed.quarter_turns = 1
		layout.placements.append(placed)
	for x: int in range(9, 13):
		layout.placements.append(_placement(&"bar_end_right" if x == 9 else &"bar_section", Vector2i(x, 7), 2))
		layout.placements.append(_placement(&"bar_stool", Vector2i(x, 8), 0))
	layout.placements.append(_placement(&"drinks_shelf", Vector2i(10, 5), 2))
	layout.placements.append(_placement(&"drinks_fridge", Vector2i(11, 5), 2))
	layout.placements.append(_placement(&"coffee_machine", Vector2i(12, 5), 2))
	return layout


func _placement(id: StringName, origin: Vector2i, turns: int) -> ShopPlacement:
	var placed: ShopPlacement = ShopPlacement.new()
	placed.item_id = id
	placed.origin = origin
	placed.quarter_turns = turns
	return placed
