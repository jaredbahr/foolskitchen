class_name AquariumCare
extends RefCounted
## Fish tank upkeep (#125): the day each placed tank was last cleaned. A tank
## is cloudy once `cloudy_after_days` days have passed since then, and stays
## cloudy until a "Clean tank" task (CleanTaskController) is done. Cloudiness
## is a pure function of the day, so it needs no daily tick and no random draw.
## Only the cleaning days are saved (by tank kind and position, since item ids
## are not kept by a load); the fish themselves are view-only.

const TASK_KIND: StringName = &"clean_tank"
const SAVE_VERSION: int = 1
const MAX_DAY: int = 1000000

## A tank was cleaned, so its charm and look change.
signal changed

var tuning: AquariumTuning
var cleaned_today: int = 0
var _cleaned: Dictionary[int, int] = {}
## Each tracked tank's kind and position ("def@x,y").
var _keys: Dictionary[int, String] = {}
## Tanks removed today, by kind and position, with their cleaning day: a tank
## put back there today (Undo of a sale) keeps its water as it was.
var _removed_today: Dictionary[String, int] = {}


func _init(config: AquariumTuning) -> void:
	tuning = config


## A tank is an item whose definition says so.
static func is_tank(placed: PlacedItem) -> bool:
	var definition: ItemDef = placed.def as ItemDef if placed != null else null
	return definition != null and not placed.removed and definition.fish_tank


## Starts newly placed tanks clean on `day` and forgets removed ones. Moving a
## tank keeps its item and so its record.
func track(grid: SimGrid, day: int) -> void:
	if grid == null:
		return
	var present: Dictionary[int, bool] = {}
	for placed: PlacedItem in grid.items():
		if is_tank(placed):
			present[placed.id] = true
	for item_id: int in _cleaned.keys():
		if not present.has(item_id):
			if _keys.has(item_id):
				_removed_today[_keys[item_id]] = _cleaned[item_id]
			_cleaned.erase(item_id)
			_keys.erase(item_id)
	for placed: PlacedItem in grid.items():
		if not present.has(placed.id):
			continue
		var key: String = place_key(placed)
		if not _cleaned.has(placed.id):
			_cleaned[placed.id] = _removed_today.get(key, day)
			_removed_today.erase(key)
		_keys[placed.id] = key


## A tank's kind and position, as the save matches them.
static func place_key(placed: PlacedItem) -> String:
	return "%s@%d,%d" % [String((placed.def as ItemDef).id), placed.origin.x, placed.origin.y]


func tank_count() -> int:
	return _cleaned.size()


func enabled() -> bool:
	return tuning != null and tuning.maintenance and tuning.is_valid()


func has_tank(item_id: int) -> bool:
	return _cleaned.has(item_id)


func cleaned_day(item_id: int) -> int:
	return _cleaned.get(item_id, -1)


func is_cloudy(item_id: int, day: int) -> bool:
	return enabled() and _cleaned.has(item_id) and day - _cleaned[item_id] >= tuning.cloudy_after_days


## Cloudy tanks still in `grid`, in id order.
func cloudy_ids(grid: SimGrid, day: int) -> Array[int]:
	var result: Array[int] = []
	if grid == null:
		return result
	for item_id: int in _cleaned.keys():
		if grid.item(item_id) != null and is_cloudy(item_id, day):
			result.append(item_id)
	result.sort()
	return result


## Item id -> share of its charm, for cloudy tanks only (VibeInputs).
func charm_factors(grid: SimGrid, day: int) -> Dictionary[int, float]:
	var result: Dictionary[int, float] = {}
	for item_id: int in cloudy_ids(grid, day):
		result[item_id] = tuning.cloudy_charm_factor
	return result


## Done by the "Clean tank" task. False when there is nothing to clean.
func clean(item_id: int, day: int) -> bool:
	if not is_cloudy(item_id, day):
		return false
	_cleaned[item_id] = day
	cleaned_today += 1
	changed.emit()
	return true


func begin_day(grid: SimGrid, day: int) -> void:
	cleaned_today = 0
	_removed_today.clear()
	track(grid, day)


## Saved by tank kind and position: {version, tanks: [{def_id, origin, cleaned_day}]}.
func to_dict(grid: SimGrid) -> Dictionary:
	var rows: Array[Dictionary] = []
	var ids: Array[int] = _cleaned.keys()
	ids.sort()
	for item_id: int in ids:
		var placed: PlacedItem = grid.item(item_id) if grid != null else null
		if placed == null:
			continue
		rows.append({"def_id": String((placed.def as ItemDef).id), "origin": [placed.origin.x, placed.origin.y],
			"cleaned_day": _cleaned[item_id]})
	return {"version": SAVE_VERSION, "tanks": rows}


## Shape check only, before anything is installed.
static func valid_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if data.size() != 2 or not _whole(data.get("version"), SAVE_VERSION, SAVE_VERSION) or not data.get("tanks") is Array:
		return false
	for row: Variant in data["tanks"]:
		if not row is Dictionary:
			return false
		var tank: Dictionary = row
		if tank.size() != 3 or not tank.get("def_id") is String or not tank.get("origin") is Array \
				or not _whole(tank.get("cleaned_day"), 0, MAX_DAY):
			return false
		var origin: Array = tank["origin"]
		if origin.size() != 2 or not _whole(origin[0], -MAX_DAY, MAX_DAY) or not _whole(origin[1], -MAX_DAY, MAX_DAY):
			return false
	return true


## Installs saved cleaning days onto the restored layout's tanks, matched by
## kind and position. Tanks without a row start clean today; rows for tanks
## no longer there are dropped. A day after `day` is treated as today.
func restore(grid: SimGrid, value: Variant, day: int) -> bool:
	if not valid_dict(value):
		return false
	_cleaned.clear()
	_keys.clear()
	_removed_today.clear()
	track(grid, day)
	for row: Variant in (value as Dictionary)["tanks"]:
		var tank: Dictionary = row
		var origin: Vector2i = Vector2i(int(tank["origin"][0]), int(tank["origin"][1]))
		for placed: PlacedItem in grid.items():
			if is_tank(placed) and placed.origin == origin and String((placed.def as ItemDef).id) == tank["def_id"]:
				_cleaned[placed.id] = mini(int(tank["cleaned_day"]), day)
	return true


static func _whole(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and floorf(number) == number
