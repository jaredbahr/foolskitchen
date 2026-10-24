extends TestCase
## FK-013: staff agents claim tasks, walk, work and heal themselves.

var world: SimWorld
var stove: PlacedItem
var fridge: PlacedItem
var completed: Array[int] = []
var failed: Array[StringName] = []


func before_each() -> void:
	var grid := SimGrid.from_ascii(PackedStringArray([
		"##########",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"#........#",
		"####..####",
		"    EE    ",
	]))
	# Stove against the top wall, worked from the cell below its left half.
	stove = grid.place(Vector2i(2, 1), Vector2i(2, 1), 0, true, [] as Array[Vector2i])
	stove.work_cells.append(Vector2i(2, 2))
	fridge = grid.place(Vector2i(2, 1), Vector2i(6, 1), 0, true, [] as Array[Vector2i])
	fridge.work_cells.append(Vector2i(6, 2))
	world = SimWorld.new(grid)
	completed.clear()
	failed.clear()
	world.board.task_completed.connect(_on_completed)
	world.board.task_failed.connect(_on_failed)


func _on_completed(t: SimTask) -> void:
	completed.append(t.id)


func _on_failed(_t: SimTask, r: StringName) -> void:
	failed.append(r)


func _cook(at: Vector2i, skill: int = 3) -> StaffAgent:
	var a := StaffAgent.new(&"cook", skill)
	a.cell = at
	world.add_agent(a)
	return a


func _cook_task(work_ticks: int = 20) -> SimTask:
	var t := SimTask.new(&"cook", &"cook", "Cook burger")
	t.steps.append(TaskStep.go_to_item(fridge.id, "fetching ingredients"))
	t.steps.append(TaskStep.work(5, "taking ingredients"))
	t.steps.append(TaskStep.go_to_item(stove.id, "going to the stove"))
	t.steps.append(TaskStep.work(work_ticks, "cooking"))
	return t


func _run(ticks: int) -> void:
	for i in ticks:
		world.advance()


func test_cook_completes_multi_step_task() -> void:
	var cook := _cook(Vector2i(4, 4))
	var t := _cook_task()
	world.board.post(t, world.now)
	_run(5)
	assert_eq(cook.task, t, "claimed")
	assert_true(cook.why().begins_with("Cook burger"), cook.why())
	_run(200)
	assert_eq(completed, [t.id] as Array[int])
	assert_null(cook.task)
	assert_eq(cook.cell, Vector2i(2, 2), "ended at the stove")
	assert_eq(stove.reserved_by(Vector2i(2, 2)), -1, "reservation released")
	assert_eq(cook.why(), "Idle: looking for work")


func test_server_ignores_cook_tasks() -> void:
	var server := StaffAgent.new(&"server", 5)
	server.cell = Vector2i(4, 4)
	world.add_agent(server)
	world.board.post(_cook_task(), world.now)
	_run(50)
	assert_null(server.task)
	assert_eq(world.board.open_tasks().size(), 1)


func test_two_cooks_share_one_stove() -> void:
	var a := _cook(Vector2i(3, 4))
	var b := _cook(Vector2i(5, 4))
	world.board.post(_cook_task(40), world.now)
	world.board.post(_cook_task(40), world.now)
	var saw_waiting := false
	for i in 400:
		world.advance()
		if a.why().contains("waiting for") or b.why().contains("waiting for"):
			saw_waiting = true
	assert_eq(completed.size(), 2, "both finished")
	assert_true(saw_waiting, "one cook waited for the busy stove or fridge")
	assert_eq(failed.size(), 0)


func test_skill_makes_work_faster() -> void:
	var slow := StaffAgent.new(&"cook", 1)
	var fast := StaffAgent.new(&"cook", 5)
	assert_true(fast.work_speed(&"cook") > slow.work_speed(&"cook"))


func test_timeout_drops_task_back_on_board() -> void:
	var cook := _cook(Vector2i(4, 4))
	var t := _cook_task(1000)
	t.timeout_ticks = 80
	world.board.post(t, world.now)
	_run(90)
	assert_true(t.drops >= 1, "dropped after its timeout")
	assert_true(world.event_log[-1].contains("timeout") or "\n".join(world.event_log).contains("timeout"))
	_run(400)
	assert_eq(t.state, SimTask.State.CANCELLED, "fails after MAX_DROPS timeouts")
	assert_eq(failed, [&"dropped_too_often"] as Array[StringName])
	assert_null(cook.task)


func test_removed_target_cancels_task() -> void:
	var cook := _cook(Vector2i(4, 5))
	var t := _cook_task()
	world.board.post(t, world.now)
	_run(3)
	world.grid.remove(fridge.id)
	_run(2)
	assert_eq(t.state, SimTask.State.CANCELLED)
	assert_eq(failed, [&"target_gone"] as Array[StringName])
	assert_null(cook.task, "the cook let go")


func test_walls_dropped_mid_walk_cause_repath() -> void:
	var cook := _cook(Vector2i(8, 5))
	var t := SimTask.new(&"go", &"cook", "Walk")
	t.steps.append(TaskStep.go_to_cell(Vector2i(1, 1), "walking"))
	world.board.post(t, world.now)
	_run(3)
	# Drop a wall segment across the middle, leaving a gap at x=1.
	world.grid.place(Vector2i(7, 1), Vector2i(2, 3), 0, true)
	_run(200)
	assert_eq(completed, [t.id] as Array[int], "walked around the new obstacle")
	assert_eq(cook.cell, Vector2i(1, 1))


func test_unreachable_target_is_dropped() -> void:
	_cook(Vector2i(4, 5))
	# (8,1) is boxed in by the fridge at (6..7,1) and a counter at (7..8,2).
	world.grid.place(Vector2i(2, 1), Vector2i(7, 2), 0, true)
	var t := SimTask.new(&"go", &"cook", "Walk")
	t.steps.append(TaskStep.go_to_cell(Vector2i(8, 1), "walking"))
	world.board.post(t, world.now)
	_run(20)
	assert_eq(t.state, SimTask.State.CANCELLED)
	assert_eq(failed, [&"dropped_too_often"] as Array[StringName])


func test_failed_step_cancels_task() -> void:
	var cook := _cook(Vector2i(6, 3))
	var t := SimTask.new(&"fetch", &"cook", "Fetch")
	t.steps.append(TaskStep.work(3, "checking the fridge", func(_a: StaffAgent) -> bool: return false))
	world.board.post(t, world.now)
	_run(20)
	assert_eq(failed, [&"step_failed"] as Array[StringName])
	assert_null(cook.task)


func test_buried_cook_walks_out() -> void:
	var cook := _cook(Vector2i(5, 3))
	world.grid.place(Vector2i(3, 3), Vector2i(4, 2), 0, true)
	var t := SimTask.new(&"go", &"cook", "Walk")
	t.steps.append(TaskStep.go_to_cell(Vector2i(1, 5), "walking"))
	world.board.post(t, world.now)
	_run(200)
	assert_eq(completed, [t.id] as Array[int])
	assert_eq(cook.cell, Vector2i(1, 5))


func test_removed_agent_gives_task_back() -> void:
	var cook := _cook(Vector2i(4, 4))
	var t := _cook_task()
	world.board.post(t, world.now)
	_run(20)
	assert_eq(cook.task, t)
	world.remove_agent(cook)
	assert_eq(t.state, SimTask.State.OPEN, "the task is back on the board")
	for c in fridge.work_cells + stove.work_cells:
		assert_eq(fridge.reserved_by(c), -1)
		assert_eq(stove.reserved_by(c), -1)
	var other := _cook(Vector2i(4, 4))
	_run(300)
	assert_eq(completed, [t.id] as Array[int], "someone else finished it")
	assert_null(other.task)


func test_task_posted_for_missing_item_fails_fast() -> void:
	_cook(Vector2i(4, 4))
	world.grid.remove(fridge.id)
	var t := _cook_task()
	world.board.post(t, world.now)
	_run(2)
	assert_eq(t.state, SimTask.State.CANCELLED)
	assert_eq(failed, [&"target_gone"] as Array[StringName])


func test_deeply_buried_cook_escapes_with_long_step() -> void:
	var grid := SimGrid.new(Vector2i(30, 12))
	var w := SimWorld.new(grid)
	var cook := StaffAgent.new(&"cook", 3)
	cook.cell = Vector2i(15, 6)
	w.add_agent(cook)
	grid.place(Vector2i(25, 11), Vector2i(2, 0), 0, true)
	var t := SimTask.new(&"go", &"cook", "Walk")
	t.steps.append(TaskStep.go_to_cell(Vector2i(0, 11), "walking"))
	w.board.post(t, w.now)
	for i in 400:
		w.advance()
	assert_eq(t.state, SimTask.State.DONE, "escaped and arrived (%s)" % [w.event_log])
	assert_eq(cook.cell, Vector2i(0, 11))


func test_drop_signal_sees_final_state() -> void:
	var b := TaskBoard.new()
	var t := SimTask.new(&"x", &"cook", "x")
	t.steps.append(TaskStep.work(1))
	b.post(t, 0)
	var states: Array[int] = []
	b.task_dropped.connect(func(task: SimTask, _a: int, _r: StringName) -> void: states.append(task.state))
	for i in TaskBoard.MAX_DROPS:
		b.claim(t, 1, 0)
		b.drop(t, &"stuck")
	assert_eq(states, [SimTask.State.OPEN, SimTask.State.OPEN, SimTask.State.CANCELLED] as Array[int])
	assert_false(b.claim(t, 2, 0))


func test_any_task_uses_own_role_skill() -> void:
	var a := StaffAgent.new(&"server", 5)
	assert_eq(a.skill_for(&"any"), 5)
	assert_almost_eq(a.work_speed(&"any"), 1.1)


## An explicit side follows rotated work cells and releases its reservation on completion.
func test_exact_work_cell_uses_rotated_side_and_releases_it() -> void:
	var item: PlacedItem = _selector_pass(1)
	var cook: StaffAgent = _cook(Vector2i(1, 1))
	var task: SimTask = SimTask.new(&"cook", &"cook", "Use exact side")
	task.steps.append(TaskStep.go_to_work_cell(item.id, 1))
	task.steps.append(TaskStep.work(5))
	world.board.post(task, world.now)
	for tick: int in 200:
		world.advance()
		assert_eq(item.reserved_by(item.work_cells[0]), -1, "never borrows the opposite side")
		if task.state == SimTask.State.DONE:
			break
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(cook.cell, item.work_cells[1])
	assert_eq(item.reserved_by(item.work_cells[1]), -1)


## Consecutive sides of one item release the old hold before waiting for a busy new side.
func test_exact_work_cell_same_item_busy_side_releases_previous_hold() -> void:
	var item: PlacedItem = _selector_pass()
	var cook: StaffAgent = _cook(Vector2i(1, 1))
	item.reserve(item.work_cells[1], 999)
	var task: SimTask = SimTask.new(&"cook", &"cook", "Both pass sides")
	task.steps.append(TaskStep.go_to_work_cell(item.id, 0))
	task.steps.append(TaskStep.work(5))
	task.steps.append(TaskStep.go_to_work_cell(item.id, 1))
	task.steps.append(TaskStep.work(5))
	world.board.post(task, world.now)
	_run(120)
	assert_eq(task.state, SimTask.State.CLAIMED)
	assert_eq(cook.step_index, 2)
	assert_eq(item.reserved_by(item.work_cells[0]), -1)
	assert_eq(item.reserved_by(item.work_cells[1]), 999)
	item.release(item.work_cells[1], 999)
	_run(120)
	assert_eq(task.state, SimTask.State.DONE)
	assert_eq(cook.cell, item.work_cells[1])
	assert_eq(item.reserved_by(item.work_cells[1]), -1)


## Invalid exact indices fail through ordinary bounded drops rather than choosing another side.
func test_exact_work_cell_invalid_index_never_falls_back() -> void:
	var item: PlacedItem = _selector_pass()
	var cook: StaffAgent = _cook(Vector2i(1, 1))
	var task: SimTask = SimTask.new(&"cook", &"cook", "Invalid side")
	task.steps.append(TaskStep.go_to_work_cell(item.id, 99))
	world.board.post(task, world.now)
	_run(30)
	assert_eq(task.state, SimTask.State.CANCELLED)
	assert_eq(cook.cell, Vector2i(1, 1))
	for cell: Vector2i in item.work_cells:
		assert_eq(item.reserved_by(cell), -1)


## An unwalkable requested side fails even when the opposite side is available.
func test_exact_work_cell_unwalkable_side_never_falls_back() -> void:
	var item: PlacedItem = _selector_pass()
	world.grid.set_terrain(item.work_cells[1], SimGrid.Terrain.WALL)
	var cook: StaffAgent = _cook(Vector2i(1, 1))
	var task: SimTask = SimTask.new(&"cook", &"cook", "Blocked side")
	task.steps.append(TaskStep.go_to_work_cell(item.id, 1))
	world.board.post(task, world.now)
	_run(30)
	assert_eq(task.state, SimTask.State.CANCELLED)
	assert_eq(cook.cell, Vector2i(1, 1))
	assert_eq(item.reserved_by(item.work_cells[0]), -1)


## Removing the target cancels exact-cell tasks and clears their held reservation.
func test_exact_work_cell_target_removal_releases_hold() -> void:
	var item: PlacedItem = _selector_pass()
	var cook: StaffAgent = _cook(Vector2i(1, 1))
	var task: SimTask = SimTask.new(&"cook", &"cook", "Removed pass")
	task.steps.append(TaskStep.go_to_work_cell(item.id, 1))
	world.board.post(task, world.now)
	_run(2)
	assert_eq(item.reserved_by(item.work_cells[1]), cook.id)
	world.grid.remove(item.id)
	_run(2)
	assert_eq(task.state, SimTask.State.CANCELLED)
	assert_true(cook.task == null)
	assert_eq(item.reserved_by(item.work_cells[1]), -1)
	assert_eq(world.board.active_count(), 0)


func _selector_pass(turns: int = 0) -> PlacedItem:
	world = SimWorld.new(SimGrid.new(Vector2i(10, 10)))
	return world.grid.place(Vector2i(2, 1), Vector2i(4, 3), turns, true,
		[Vector2i(0, -1), Vector2i(0, 1)] as Array[Vector2i])


## A dropped exact-cell task gives its reservation back when the worker notices.
func test_exact_work_cell_drop_releases_hold() -> void:
	var item: PlacedItem = _selector_pass()
	var cook: StaffAgent = _cook(Vector2i(1, 1))
	var task: SimTask = SimTask.new(&"cook", &"cook", "Dropped pass work")
	task.steps.append(TaskStep.go_to_work_cell(item.id, 1))
	task.steps.append(TaskStep.work(100))
	world.board.post(task, world.now)
	for tick: int in 100:
		world.advance()
		if cook.task == task and cook.step_index == 1:
			break
	assert_eq(item.reserved_by(item.work_cells[1]), cook.id)
	world.board.drop(task, &"test_retry")
	_run(1)
	assert_true(cook.task == null)
	assert_eq(item.reserved_by(item.work_cells[1]), -1)
	world.board.cancel(task)
