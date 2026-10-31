extends TestCase
## A mode command must settle real owner work on the next world tick even
## while an ordinary movement yield owns the sidestep/return overlay.

const STATION: ItemDef = preload("res://data/items/prep_counter.tres")
const STATION_CELL: Vector2i = Vector2i(2, 1)
const POCKET: Vector2i = Vector2i(2, 0)
const WATCHDOG: int = 400

var _world: SimWorld
var _callback_cells: Array[Vector2i] = []


func before_each() -> void:
	_callback_cells.clear()


func after_each() -> void:
	if _world != null:
		for agent: SimAgent in _world.agents.duplicate():
			_world.remove_agent(agent)
	_world = null


func test_rest_releases_work_on_next_world_tick_after_actual_pocket_arrival() -> void:
	_exercise(&"rest", false)


func test_floor_releases_cooking_on_next_world_tick_during_actual_partial_return() -> void:
	_exercise(&"floor", true)


func _exercise(mode: StringName, during_return: bool) -> void:
	_world = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["##.##", ".....", "##..#"])))
	var station: PlacedItem = _world.grid.place_def(STATION, Vector2i(2, 2))
	assert_not_null(station)
	if station == null:
		return
	assert_eq(station.work_cells, [STATION_CELL] as Array[Vector2i])
	# The lower-ID server wins by the ordinary stable movement priority.
	var crossing: StaffAgent = StaffAgent.new(&"server")
	crossing.cell = Vector2i(1, 1)
	_world.add_agent(crossing)
	var owner: OwnerAgent = OwnerAgent.new(STATION_CELL)
	_world.add_agent(owner)
	assert_true(owner.assign_mode(&"kitchen"))
	assert_true(crossing.id < owner.id)
	assert_eq(_world.movement.priority(_world, crossing), _world.movement.priority(_world, owner))
	var station_task: SimTask = SimTask.new(&"cook", &"cook", "Finish real owner station work")
	station_task.steps = [TaskStep.go_to_item(station.id), TaskStep.work(120, "work at station", _station_done)]
	_world.board.post(station_task, _world.now)
	assert_true(_world.clock.start_service())
	for _tick: int in 3:
		_advance()
	assert_eq(owner.task, station_task)
	assert_eq(owner.step_index, 1)
	assert_true(owner.work_left > 0.0 and owner.work_left < 120.0)
	assert_eq(station.reserved_by(STATION_CELL), owner.id)
	var crossing_task: SimTask = SimTask.new(&"take_order", &"server", "Cross the occupied owner aisle")
	crossing_task.steps = [TaskStep.go_to_cell(Vector2i(4, 1)), TaskStep.work(1)]
	_world.board.post(crossing_task, _world.now)
	var saw_yield: bool = false
	var saw_pocket: bool = false
	var reached_command_point: bool = false
	for _tick: int in WATCHDOG:
		_advance()
		saw_yield = saw_yield or _world.movement.is_yielding(owner.id)
		saw_pocket = saw_pocket or owner.cell == POCKET
		var partial_return: bool = owner.cell == POCKET and owner.next_cell() == STATION_CELL \
			and owner.move_progress > 0.0
		var pocket_arrival: bool = owner.cell == POCKET and owner.move_progress == 0.0
		if _world.movement.is_yielding(owner.id) and (partial_return if during_return else pocket_arrival):
			reached_command_point = true
			break
	assert_true(saw_yield, "the real blocked aisle must trigger yielding")
	assert_true(saw_pocket, "the owner must physically visit the free pocket")
	assert_true(reached_command_point, "issue the mode command only at the actual declared movement phase")
	if not reached_command_point:
		return
	assert_eq(station_task.state, SimTask.State.CLAIMED)
	assert_eq(station_task.claimed_by, owner.id)
	assert_eq(station.reserved_by(STATION_CELL), owner.id)
	assert_eq(_callback_cells, [] as Array[Vector2i])
	var before_tick: int = _world.now
	assert_true(owner.assign_mode(mode))
	assert_eq(_world.now, before_tick, "a command does not secretly advance the simulation")
	assert_eq(station_task.claimed_by, owner.id, "the existing contract settles on the next world tick")
	_advance()
	assert_eq(_world.now, before_tick + 1)
	assert_null(owner.task, "the next real world tick must release disabled work during a yield")
	assert_eq(station_task.state, SimTask.State.OPEN)
	assert_eq(station_task.claimed_by, -1)
	assert_eq(station_task.drops, 1)
	assert_eq(station.reserved_by(STATION_CELL), -1)
	assert_false(_world.movement.is_yielding(owner.id), "disabled work must not retain the old return overlay")
	assert_eq(_callback_cells, [] as Array[Vector2i], "reassignment must not complete the old work")
	# Any already reserved edge must finish through normal physical motion.
	# The other real task also has to complete; a stopped population is no pass.
	for _tick: int in WATCHDOG:
		_advance()
		assert_eq(_callback_cells, [] as Array[Vector2i])
		if crossing_task.state == SimTask.State.DONE and not _world.movement.is_stopping(owner.id) \
				and owner.has_arrived():
			break
	assert_eq(crossing_task.state, SimTask.State.DONE)
	assert_eq(crossing.cell, Vector2i(4, 1))
	assert_false(_world.movement.is_stopping(owner.id))
	assert_true(owner.has_arrived())
	assert_null(owner.task)
	assert_eq(station_task.state, SimTask.State.OPEN)
	assert_eq(station_task.drops, 1, "disabled work is not repeatedly reclaimed and dropped")
	assert_eq(station.reserved_by(STATION_CELL), -1)
	assert_eq(_callback_cells, [] as Array[Vector2i])


func _advance() -> void:
	var before: Dictionary = MovementInvariants.capture(_world)
	_world.advance()
	assert_eq(MovementInvariants.problem(_world, before), "", "mode cleanup must preserve actual physical geometry")


func _station_done(agent: SimAgent) -> bool:
	_callback_cells.append(agent.cell)
	return agent.cell == STATION_CELL and agent.move_progress == 0.0
