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


func test_open_tasks_in_post_order() -> void:
	var b := TaskBoard.new()
	var ids: Array[int] = []
	for i in 4:
		ids.append(b.post(_task(), 0))
	var seen: Array[int] = []
	for t in b.open_tasks():
		seen.append(t.id)
	assert_eq(seen, ids)
