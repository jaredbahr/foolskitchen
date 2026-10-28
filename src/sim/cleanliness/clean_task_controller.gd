class_name CleanTaskController
extends RefCounted
## Posts one walk-and-mop task for each reachable dirt cell. The session owns
## this controller, the world, and the dirt state for the same service day.

var _world_ref: WeakRef
var _dirt_ref: WeakRef
var _tuning: CleanlinessTuning
var _tasks: Dictionary[Vector2i, SimTask] = {}
var _cells_by_id: Dictionary[int, Vector2i] = {}
## A task that exhausted its retries waits for a layout change before reposting.
var _suspended: Dictionary[Vector2i, bool] = {}
var _tidying: bool = false


func _init(world: SimWorld, dirt: CleanlinessState, tuning: CleanlinessTuning) -> void:
	_world_ref = weakref(world) if world != null else null
	_dirt_ref = weakref(dirt) if dirt != null else null
	_tuning = tuning
	if world != null:
		# Method callables and weak references avoid a world/grid/controller cycle.
		world.board.task_completed.connect(_on_task_completed)
		world.board.task_failed.connect(_on_task_failed)
		world.grid.cells_changed.connect(_on_cells_changed)


## Call after every dirt spawn or external clear. Layout changes re-sync via
## cells_changed. A terminal failed task retries only after a layout change.
func sync_spots() -> void:
	var world: SimWorld = _world()
	var dirt: CleanlinessState = _dirt()
	if _tidying or world == null or dirt == null or _tuning == null or not _tuning.is_valid():
		return
	for cell: Vector2i in _tasks.keys():
		if not dirt.has_spot(cell) or not _eligible(world, cell):
			_retire_task(world, cell, &"target_gone")
	for cell: Vector2i in _suspended.keys():
		if not dirt.has_spot(cell):
			_suspended.erase(cell)
	for cell: Vector2i in dirt.spots():
		if _tasks.has(cell) or _suspended.has(cell) or not _eligible(world, cell):
			continue
		# A restroom spot (FK-101) is a quick tidy-up, never called mess.
		var restroom: bool = world.grid.room(cell) == SimGrid.Room.RESTROOM
		var task: SimTask = SimTask.new(&"clean_spot", &"cleaner",
			"Tidy the restroom" if restroom else "Mop up a floor spot")
		task.priority = 0
		task.defer_to_higher_priority = true
		task.steps.append(TaskStep.go_to_cell(cell, "walking to the restroom" if restroom else "walking to floor spot"))
		task.steps.append(TaskStep.work(_tuning.clean_work_ticks, "tidying the restroom" if restroom else "mopping floor"))
		world.board.post(task, world.now)
		_tasks[cell] = task
		_cells_by_id[task.id] = cell


func task_for(cell: Vector2i) -> SimTask:
	return _tasks.get(cell, null) as SimTask


func active_task_count() -> int:
	return _tasks.size()


## Morning reset withdraws both open and claimed tasks before removing dirt.
func tidy_overnight() -> void:
	var world: SimWorld = _world()
	_tidying = true
	if world != null:
		for cell: Vector2i in _tasks.keys():
			_retire_task(world, cell, &"overnight_tidy")
	_tasks.clear()
	_cells_by_id.clear()
	_suspended.clear()
	var dirt: CleanlinessState = _dirt()
	if dirt != null:
		dirt.tidy_overnight()
	_tidying = false


func _on_task_completed(task: SimTask) -> void:
	if not _cells_by_id.has(task.id):
		return
	var cell: Vector2i = _cells_by_id[task.id]
	_forget(cell, task.id)
	var dirt: CleanlinessState = _dirt()
	if dirt != null:
		dirt.clear_spot(cell)


func _on_task_failed(task: SimTask, _reason: StringName) -> void:
	if not _cells_by_id.has(task.id):
		return
	var cell: Vector2i = _cells_by_id[task.id]
	_forget(cell, task.id)
	var dirt: CleanlinessState = _dirt()
	if not _tidying and dirt != null and dirt.has_spot(cell):
		_suspended[cell] = true


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	_suspended.clear()
	sync_spots()


func _retire_task(world: SimWorld, cell: Vector2i, reason: StringName) -> void:
	var task: SimTask = _tasks[cell]
	_forget(cell, task.id)
	world.board.cancel(task, reason)


func _forget(cell: Vector2i, task_id: int) -> void:
	_tasks.erase(cell)
	_cells_by_id.erase(task_id)


func _eligible(world: SimWorld, cell: Vector2i) -> bool:
	return world.grid.terrain(cell) == SimGrid.Terrain.FLOOR and world.grid.is_walkable(cell)


func _world() -> SimWorld:
	if _world_ref == null:
		return null
	return _world_ref.get_ref() as SimWorld


func _dirt() -> CleanlinessState:
	if _dirt_ref == null:
		return null
	return _dirt_ref.get_ref() as CleanlinessState
