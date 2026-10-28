class_name CleanlinessState
extends RefCounted
## Pure, day-local floor dirt. The session injects GameState.rng(&"cleanliness")
## during integration; this class never obtains a global or scene dependency.

enum Band { SPOTLESS, A_BIT_MESSY, GRUBBY }

var _grid: SimGrid
var _tuning: CleanlinessTuning
var _rng: RandomNumberGenerator
var _spots: Dictionary[Vector2i, bool] = {}
## Restroom upkeep (FK-101): toilets used since the last tidy. Kept apart from
## floor dirt: never counted in the dirt fraction, patience, reviews, the day's
## worst band or the floor spot cap, and never drawn.
var _restroom_spots: Dictionary[Vector2i, bool] = {}
var _worst_today: int = 0


func _init(grid: SimGrid, tuning: CleanlinessTuning, random: RandomNumberGenerator) -> void:
	_grid = grid
	_tuning = tuning
	_rng = random


## The manual probe seeds the run after Main constructs the morning world.
## Rebind only before this state has recorded any dirt, without drawing.
func use_rng(random: RandomNumberGenerator) -> bool:
	if random == null or not _spots.is_empty() or _worst_today > 0:
		return false
	_rng = random
	return true


## A departed eater may leave a spot on their walkable floor seat. The caller
## decides whether the departure was eligible; blocked cells consume no draw.
func try_spawn_at_departed_seat(seat_cell: Vector2i) -> bool:
	if not _can_place(seat_cell):
		return false
	if _rng.randf() >= _tuning.seat_departure_chance:
		return false
	_place(seat_cell)
	return true


## An arrival may dirty one walkable floor cell adjacent to its street entry.
## Candidates are sorted before the seeded choice so insertion order is inert.
func try_spawn_on_arrival(entry: Vector2i) -> Vector2i:
	if not _configured() or _spots.size() >= _tuning.max_spots \
			or _grid.terrain(entry) != SimGrid.Terrain.ENTRY:
		return SimGrid.NO_CELL
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in _grid.walkable_neighbours(entry):
		if _can_place(cell):
			candidates.append(cell)
	if candidates.is_empty():
		return SimGrid.NO_CELL
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	if _rng.randf() >= _tuning.arrival_chance:
		return SimGrid.NO_CELL
	var chosen: Vector2i = candidates[_rng.randi_range(0, candidates.size() - 1)]
	_place(chosen)
	return chosen


## A restroom use (FK-101) leaves its toilet needing a tidy on the use cell,
## without a random draw. False when the cell can't take one or already has.
func add_use_spot(cell: Vector2i) -> bool:
	if not _configured() or _restroom_spots.has(cell) or _grid.terrain(cell) != SimGrid.Terrain.FLOOR \
			or not _grid.is_walkable(cell):
		return false
	_restroom_spots[cell] = true
	return true


func has_restroom_spot(cell: Vector2i) -> bool:
	return _restroom_spots.has(cell)


## Restroom tidy jobs, row-major.
func restroom_spots() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_restroom_spots.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


## Cleaning removes only the requested spot. It cannot erase the day's worst.
func clear_spot(cell: Vector2i) -> bool:
	var restroom: bool = _restroom_spots.erase(cell)
	return _spots.erase(cell) or restroom


## A floor spot or a restroom tidy job on this cell.
func has_spot(cell: Vector2i) -> bool:
	return _spots.has(cell) or _restroom_spots.has(cell)


func spot_count() -> int:
	return _spots.size()


## A detached, row-major list for task posting and drawing.
func spots() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _spots:
		result.append(cell)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


func dirt_fraction() -> float:
	return float(_spots.size()) / float(_tuning.max_spots) if _configured() else 0.0


## Sample once when a guest arrives; callers retain that sample for the visit.
func patience_multiplier() -> float:
	return 1.0 - _tuning.dirt_penalty * dirt_fraction() if _configured() else 1.0


func worst_today_count() -> int:
	return _worst_today


## Presentation maps this band to Spotless / A bit messy / Grubby.
func worst_category() -> Band:
	if not _configured():
		return Band.SPOTLESS
	if _worst_today >= _tuning.grubby_at:
		return Band.GRUBBY
	if _worst_today >= _tuning.messy_at:
		return Band.A_BIT_MESSY
	return Band.SPOTLESS


## Player-facing wording is authored in the tuning resource, never an enum id.
func worst_category_label() -> String:
	if not _configured():
		return ""
	match worst_category():
		Band.GRUBBY:
			return _tuning.grubby_label
		Band.A_BIT_MESSY:
			return _tuning.messy_label
		_:
			return _tuning.spotless_label


## End-of-day report reads worst before the next morning resets it.
func tidy_overnight() -> void:
	_spots.clear()
	_restroom_spots.clear()
	_worst_today = 0


func _configured() -> bool:
	return _grid != null and _tuning != null and _tuning.is_valid() and _rng != null


func _can_place(cell: Vector2i) -> bool:
	return _configured() and _spots.size() < _tuning.max_spots and not _spots.has(cell) \
		and _grid.terrain(cell) == SimGrid.Terrain.FLOOR and _grid.is_walkable(cell)


func _place(cell: Vector2i) -> void:
	_spots[cell] = true
	_worst_today = maxi(_worst_today, _spots.size())
