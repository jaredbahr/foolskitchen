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
var _mishaps_ref: WeakRef
var _station_tasks: Dictionary[int, SimTask] = {}
var _stations_by_id: Dictionary[int, int] = {}
var _station_suspended: Dictionary[int, bool] = {}


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
	sync_stations()
	for cell: Vector2i in _tasks.keys():
		if not dirt.has_spot(cell) or not _eligible(world, cell):
			_retire_task(world, cell, &"target_gone")
	for cell: Vector2i in _suspended.keys():
		if not dirt.has_spot(cell):
			_suspended.erase(cell)
	var cells: Array[Vector2i] = dirt.spots()
	cells.append_array(dirt.restroom_spots())
	for cell: Vector2i in cells:
		if _tasks.has(cell) or _suspended.has(cell) or not _eligible(world, cell):
			continue
		# Restroom upkeep (FK-101) is a quick tidy-up, never called mess.
		var restroom: bool = dirt.has_restroom_spot(cell) and not dirt.spots().has(cell)
		var task: SimTask = SimTask.new(&"clean_spot", &"cleaner",
			"Tidy the restroom" if restroom else MishapText.cleaning(dirt.floor_mess_kind(cell)))
		task.priority = 0
		task.defer_to_higher_priority = true
		task.steps.append(TaskStep.go_to_cell(cell, "walking to the restroom" if restroom else "walking to floor spot"))
		task.steps.append(TaskStep.work(_tuning.clean_work_ticks, "tidying the restroom" if restroom else "mopping floor"))
		world.board.post(task, world.now)
		_tasks[cell] = task
		_cells_by_id[task.id] = cell


func bind_mishaps(state: MishapState) -> void:
	_mishaps_ref = weakref(state) if state != null else null


func station_task_for(item_id: int) -> SimTask:
	return _station_tasks.get(item_id, null) as SimTask


func sync_stations() -> void:
	var world: SimWorld = _world()
	var state: MishapState = _mishaps()
	if _tidying or world == null or state == null:
		return
	for station_id: int in _station_tasks.keys():
		if world.grid.item(station_id) == null or not state.is_greasy(station_id):
			var previous: SimTask = _station_tasks[station_id]
			_forget_station(station_id, previous.id)
			world.board.cancel(previous, &"target_gone")
	for station_id: int in state.greasy_stations(world.grid):
		if _station_tasks.has(station_id) or _station_suspended.has(station_id):
			continue
		var item: PlacedItem = world.grid.item(station_id)
		var definition: ItemDef = item.def as ItemDef
		if definition == null or item.work_cells.is_empty():
			continue
		var task: SimTask = SimTask.new(&"degrease", &"cleaner", MishapText.degrease(definition.display_name))
		task.priority = 0
		task.defer_to_higher_priority = true
		task.steps.append(TaskStep.go_to_item(item.id, "walking to the station"))
		task.steps.append(TaskStep.work(state.tuning.degrease_work_ticks, "degreasing the station"))
		world.board.post(task, world.now)
		_station_tasks[station_id] = task
		_stations_by_id[task.id] = station_id


func task_for(cell: Vector2i) -> SimTask:
	return _tasks.get(cell, null) as SimTask


func active_task_count() -> int:
	return _tasks.size() + _station_tasks.size()


## Morning reset withdraws both open and claimed tasks before removing dirt.
func tidy_overnight() -> void:
	var world: SimWorld = _world()
	_tidying = true
	if world != null:
		for cell: Vector2i in _tasks.keys():
			_retire_task(world, cell, &"overnight_tidy")
		for station_id: int in _station_tasks.keys():
			var task: SimTask = _station_tasks[station_id]
			_forget_station(station_id, task.id)
			world.board.cancel(task, &"overnight_tidy")
	_station_tasks.clear()
	_stations_by_id.clear()
	_station_suspended.clear()
	_tasks.clear()
	_cells_by_id.clear()
	_suspended.clear()
	var dirt: CleanlinessState = _dirt()
	if dirt != null:
		dirt.tidy_overnight()
	_tidying = false


func _on_task_completed(task: SimTask) -> void:
	if _stations_by_id.has(task.id):
		var station_id: int = _stations_by_id[task.id]
		_forget_station(station_id, task.id)
		var state: MishapState = _mishaps()
		if state != null:
			state.degrease(station_id)
		return
	if not _cells_by_id.has(task.id):
		return
	var cell: Vector2i = _cells_by_id[task.id]
	_forget(cell, task.id)
	var dirt: CleanlinessState = _dirt()
	if dirt != null:
		dirt.clear_spot(cell)


func _on_task_failed(task: SimTask, _reason: StringName) -> void:
	if _stations_by_id.has(task.id):
		var station_id: int = _stations_by_id[task.id]
		_forget_station(station_id, task.id)
		if not _tidying:
			_station_suspended[station_id] = true
		return
	if not _cells_by_id.has(task.id):
		return
	var cell: Vector2i = _cells_by_id[task.id]
	_forget(cell, task.id)
	var dirt: CleanlinessState = _dirt()
	if not _tidying and dirt != null and dirt.has_spot(cell):
		_suspended[cell] = true


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	_suspended.clear()
	_station_suspended.clear()
	sync_spots()


func _retire_task(world: SimWorld, cell: Vector2i, reason: StringName) -> void:
	var task: SimTask = _tasks[cell]
	_forget(cell, task.id)
	world.board.cancel(task, reason)


func _forget(cell: Vector2i, task_id: int) -> void:
	_tasks.erase(cell)
	_cells_by_id.erase(task_id)


func _forget_station(station_id: int, task_id: int) -> void:
	_station_tasks.erase(station_id)
	_stations_by_id.erase(task_id)


func _mishaps() -> MishapState:
	return _mishaps_ref.get_ref() as MishapState if _mishaps_ref != null else null


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
