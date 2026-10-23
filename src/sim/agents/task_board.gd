class_name TaskBoard
extends RefCounted
## Shared list of work. Systems post tasks; idle agents claim the best one
## for them. Claims are exclusive. A dropped task goes back on the board;
## after MAX_DROPS drops it fails, so a broken task can never loop forever.

## Drops allowed before a task fails.
const MAX_DROPS: int = 3

signal task_posted(task: SimTask)
signal task_completed(task: SimTask)
## The task was dropped too often, or cancelled by its poster.
signal task_failed(task: SimTask, reason: StringName)
## A claimant gave the task back (it is open again). For logs and the overlay.
signal task_dropped(task: SimTask, agent_id: int, reason: StringName)

var _tasks: Dictionary[int, SimTask] = {}
var _next_id: int = 1


## Puts a task on the board and returns its id.
func post(task: SimTask, now_tick: int) -> int:
	task.id = _next_id
	_next_id += 1
	task.state = SimTask.State.OPEN
	task.posted_tick = now_tick
	_tasks[task.id] = task
	task_posted.emit(task)
	return task.id


func get_task(task_id: int) -> SimTask:
	return _tasks.get(task_id, null)


## Open tasks in id order (deterministic).
func open_tasks() -> Array[SimTask]:
	return _tasks_in_state(SimTask.State.OPEN)


## Claimed tasks in id order.
func claimed_tasks() -> Array[SimTask]:
	return _tasks_in_state(SimTask.State.CLAIMED)


## Claims an open task for an agent. False if it isn't open.
func claim(task: SimTask, agent_id: int, now_tick: int) -> bool:
	if task == null or task.state != SimTask.State.OPEN or not _tasks.has(task.id):
		return false
	task.state = SimTask.State.CLAIMED
	task.claimed_by = agent_id
	task.claimed_tick = now_tick
	return true


## The claimant gives the task back. It reopens, or fails after MAX_DROPS.
func drop(task: SimTask, reason: StringName) -> void:
	if task == null or task.state != SimTask.State.CLAIMED:
		return
	var agent_id := task.claimed_by
	task.drops += 1
	task.state = SimTask.State.OPEN
	task.claimed_by = -1
	task.claimed_tick = -1
	task_dropped.emit(task, agent_id, reason)
	if task.drops >= MAX_DROPS:
		_finish(task, SimTask.State.CANCELLED)
		task_failed.emit(task, &"dropped_too_often")


## The claimant finished every step.
func complete(task: SimTask) -> void:
	if task == null or task.state != SimTask.State.CLAIMED:
		return
	_finish(task, SimTask.State.DONE)
	task_completed.emit(task)


## The poster withdraws a task (e.g. the customer left). Whoever holds it
## notices on its next tick and stops.
func cancel(task: SimTask, reason: StringName = &"cancelled") -> void:
	if task == null or task.state == SimTask.State.DONE or task.state == SimTask.State.CANCELLED:
		return
	_finish(task, SimTask.State.CANCELLED)
	task_failed.emit(task, reason)


## Number of tasks still on the board (open or claimed).
func active_count() -> int:
	return _tasks.size()


func _finish(task: SimTask, final_state: SimTask.State) -> void:
	task.state = final_state
	_tasks.erase(task.id)


func _tasks_in_state(wanted: SimTask.State) -> Array[SimTask]:
	var ids := _tasks.keys()
	ids.sort()
	var out: Array[SimTask] = []
	for id: int in ids:
		var t: SimTask = _tasks[id]
		if t.state == wanted:
			out.append(t)
	return out
