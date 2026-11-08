extends TestCase
## FK-013: TaskBoard claim/drop/complete/cancel rules.


func _task(label: String = "t") -> SimTask:
	var t := SimTask.new(&"test", &"cook", label)
	t.steps.append(TaskStep.work(5))
	return t


func test_claim_is_exclusive() -> void:
	var b := TaskBoard.new()
	var t := _task()
	b.post(t, 0)
	assert_true(b.claim(t, 1, 0))
	assert_false(b.claim(t, 2, 0), "already claimed")
	assert_eq(t.claimed_by, 1)
	assert_eq(b.open_tasks().size(), 0)
	assert_eq(b.claimed_tasks(), [t] as Array[SimTask])


func test_drop_reopens_then_fails() -> void:
	var b := TaskBoard.new()
	var failed: Array[StringName] = []
	b.task_failed.connect(func(_t: SimTask, r: StringName) -> void: failed.append(r))  # captures a local, not self
	var t := _task()
	b.post(t, 0)
	for i in TaskBoard.MAX_DROPS - 1:
		b.claim(t, 1, i)
		b.drop(t, &"stuck")
		assert_eq(t.state, SimTask.State.OPEN, "reopened after drop %d" % (i + 1))
	b.claim(t, 1, 9)
	b.drop(t, &"stuck")
	assert_eq(t.state, SimTask.State.CANCELLED)
	assert_eq(failed, [&"dropped_too_often"] as Array[StringName])
	assert_eq(b.active_count(), 0)


func test_complete_and_cancel() -> void:
	var b := TaskBoard.new()
	var done: Array[int] = []
	b.task_completed.connect(func(t: SimTask) -> void: done.append(t.id))
	var a := _task("a")
	var c := _task("c")
	b.post(a, 0)
	b.post(c, 0)
	b.complete(a)
	assert_eq(done.size(), 0, "can't complete an unclaimed task")
	b.claim(a, 1, 0)
	b.complete(a)
	assert_eq(done, [a.id] as Array[int])
	b.cancel(c)
	assert_eq(c.state, SimTask.State.CANCELLED)
	assert_false(b.claim(c, 1, 0), "cancelled tasks can't be claimed")
	assert_eq(b.active_count(), 0)


func test_voluntary_yields_preserve_identity_failure_count_and_signal_state() -> void:
	var board: TaskBoard = TaskBoard.new()
	var task: SimTask = _task()
	var observations: Array[Dictionary] = []
	var failures: Array[StringName] = []
	board.task_dropped.connect(func(dropped: SimTask, agent_id: int, reason: StringName) -> void:
		observations.append({"state": dropped.state, "claimant": dropped.claimed_by,
			"claimed_tick": dropped.claimed_tick, "drops": dropped.drops, "agent": agent_id, "reason": reason}))
	board.task_failed.connect(func(_task: SimTask, reason: StringName) -> void: failures.append(reason))
	var original_id: int = board.post(task, 12)
	for attempt: int in TaskBoard.MAX_DROPS - 1:
		assert_true(board.claim(task, 4, 20 + attempt))
		board.drop(task, &"stuck")
	for attempt: int in 5:
		assert_true(board.claim(task, 4, 30 + attempt))
		board.drop(task, &"reserved_bussing", false)
		assert_eq(board.get_task(original_id), task)
		assert_eq(task.posted_tick, 12)
		assert_eq(task.drops, TaskBoard.MAX_DROPS - 1)
		assert_eq(observations[-1], {"state": SimTask.State.OPEN, "claimant": -1,
			"claimed_tick": -1, "drops": TaskBoard.MAX_DROPS - 1, "agent": 4, "reason": &"reserved_bussing"})
	assert_true(failures.is_empty(), "voluntary scheduling is not failed work")
	assert_true(board.claim(task, 4, 40))
	board.drop(task, &"stuck")
	assert_eq(task.state, SimTask.State.CANCELLED, "the next real failure still reaches the ordinary threshold")
	assert_eq(failures, [&"dropped_too_often"] as Array[StringName])


func test_open_tasks_in_post_order() -> void:
	var b := TaskBoard.new()
	var ids: Array[int] = []
	for i in 4:
		ids.append(b.post(_task(), 0))
	var seen: Array[int] = []
	for t in b.open_tasks():
		seen.append(t.id)
	assert_eq(seen, ids)
