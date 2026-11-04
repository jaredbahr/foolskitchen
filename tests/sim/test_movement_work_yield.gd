extends TestCase
## Regression for real WORK interrupted by ordinary lower-ID priority yielding.
## The test never calls _yield or manufactures coordinator recovery maps.

const STATION: ItemDef = preload("res://data/items/prep_counter.tres")
const STATION_CELL: Vector2i = Vector2i(2, 1)
const POCKET: Vector2i = Vector2i(2, 0)
const WATCHDOG: int = 400

var _callback_cells: Array[Vector2i] = []


func before_each() -> void:
	_callback_cells.clear()


func test_work_pauses_through_legitimate_sidestep_and_return_then_completes_at_station() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["##.##", ".....", "##..#"])))
	var station: PlacedItem = world.grid.place_def(STATION, Vector2i(2, 2))
	assert_not_null(station)
	if station == null:
		return
	assert_eq(station.work_cells, [STATION_CELL] as Array[Vector2i])
	# Same real role priority: lower stable ID legitimately wins the aisle.
	# Neither actor overrides priority or carries a fictitious plate.
	var crossing: StaffAgent = StaffAgent.new(&"server")
	crossing.cell = Vector2i(1, 1)
	world.add_agent(crossing)
	var working: StaffAgent = StaffAgent.new(&"cook")
	working.cell = STATION_CELL
	world.add_agent(working)
	assert_true(crossing.id < working.id)
	assert_eq(world.movement.priority(world, crossing), world.movement.priority(world, working))
	var station_task: SimTask = SimTask.new(&"cook", &"cook", "Finish real station work")
	station_task.steps = [TaskStep.go_to_item(station.id, "walking to station"),
		TaskStep.work(120, "work at station", _station_done)]
	world.board.post(station_task, world.now)
	assert_true(world.clock.start_service())
	# Actual claim, actual station reservation and actual first WORK tick.
	for _tick: int in 3:
		_advance(world)
	assert_eq(working.task, station_task)
	assert_eq(working.step_index, 1)
	assert_true(working.work_left > 0.0 and working.work_left < 120.0)
	assert_eq(station.reserved_by(STATION_CELL), working.id)
	var crossing_task: SimTask = SimTask.new(&"take_order", &"server", "Cross the occupied aisle")
	crossing_task.steps = [TaskStep.go_to_cell(Vector2i(4, 1)), TaskStep.work(1)]
	world.board.post(crossing_task, world.now)
	var saw_yield: bool = false
	var saw_pocket: bool = false
	var saw_return_motion: bool = false
	var resumed_at_station: bool = false
	var work_away: Dictionary = {}
	for _tick: int in WATCHDOG:
		var was_working: bool = working.task == station_task and working.step_index == 1
		var before_work: float = working.work_left
		var before_position: Vector3 = working.movement_position()
		_advance(world)
		saw_yield = saw_yield or world.movement.is_yielding(working.id)
		saw_pocket = saw_pocket or working.cell == POCKET
		if saw_pocket and working.next_cell() == STATION_CELL and working.move_progress > 0.0:
			saw_return_motion = true
		if was_working and working.work_left < before_work:
			var at_station: bool = before_position.is_equal_approx(GridMath.cell_to_world(STATION_CELL)) \
				and working.movement_position().is_equal_approx(GridMath.cell_to_world(STATION_CELL))
			if not at_station and work_away.is_empty():
				work_away = {"tick": world.now, "cell": working.cell, "next": working.next_cell(),
					"progress": working.move_progress, "before_work": before_work, "after_work": working.work_left}
			resumed_at_station = resumed_at_station or (saw_pocket and at_station)
		if station_task.state in [SimTask.State.DONE, SimTask.State.CANCELLED] \
				and crossing_task.state == SimTask.State.DONE:
			break
	assert_true(saw_yield, "ordinary blocked movement must actually make the working actor yield")
	assert_true(saw_pocket, "the actor must physically reach the real free pocket")
	assert_eq(work_away, {}, "WORK advanced away from its station during sidestep/return: %s" % work_away)
	assert_true(saw_return_motion, "returning to the station must physically traverse its edge")
	assert_true(resumed_at_station, "productive work resumes only after the actual return")
	assert_eq(_callback_cells, [STATION_CELL] as Array[Vector2i], "the real work callback must run at the station")
	assert_eq(station_task.state, SimTask.State.DONE)
	assert_eq(crossing_task.state, SimTask.State.DONE)
	assert_eq(crossing.cell, Vector2i(4, 1))


func _advance(world: SimWorld) -> void:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	assert_eq(MovementInvariants.problem(world, before), "", "the ordinary fixture must retain all physical invariants")


func _station_done(agent: SimAgent) -> bool:
	_callback_cells.append(agent.cell)
	return agent.cell == STATION_CELL and agent.move_progress == 0.0
