class_name MishapState
extends RefCounted
## Transient station use and daily counters, sharing the existing cleanliness
## random stream supplied by Main. Nothing in this state is saved.

var tuning: MessTuning
var spills_today: int = 0
var broken_plates_today: int = 0
var degreases_today: int = 0
var _random: RandomNumberGenerator
var _grease: Dictionary[int, int] = {}


func _init(config: MessTuning, random: RandomNumberGenerator) -> void:
	tuning = config
	_random = random


## The manual probe reseeds the existing stream before any service starts.
func use_rng(random: RandomNumberGenerator) -> bool:
	if random == null or spills_today != 0 or not _grease.is_empty():
		return false
	_random = random
	return true


func spill_chance(clumsy: bool, nearby_people: int) -> float:
	if tuning == null or not tuning.is_valid() or tuning.spill_chance_per_cell == 0.0:
		return 0.0
	var chance: float = tuning.spill_chance_per_cell * (tuning.clumsy_multiplier if clumsy else 1.0)
	var crowded: int = maxi(0, nearby_people - tuning.pass_crowding_threshold + 1)
	return minf(tuning.maximum_spill_chance, chance + crowded * tuning.crowding_spill_bonus)


func roll_spill(clumsy: bool, nearby_people: int) -> bool:
	var chance: float = spill_chance(clumsy, nearby_people)
	return chance > 0.0 and _random != null and _random.randf() < chance


func roll_breakage() -> bool:
	return tuning != null and tuning.is_valid() and tuning.broken_plate_chance > 0.0 \
		and _random != null and _random.randf() < tuning.broken_plate_chance


func record_spill(broken: bool) -> void:
	spills_today += 1
	if broken:
		broken_plates_today += 1


func station_used(item_id: int) -> void:
	if item_id > 0 and tuning != null and tuning.is_valid():
		_grease[item_id] = mini(tuning.grease_threshold, grease_at(item_id) + 1)


func grease_at(item_id: int) -> int:
	return _grease.get(item_id, 0)


func is_greasy(item_id: int) -> bool:
	return tuning != null and tuning.is_valid() and grease_at(item_id) >= tuning.grease_threshold


func work_multiplier(item_id: int) -> float:
	return tuning.greasy_work_multiplier if is_greasy(item_id) else 1.0


func greasy_stations(grid: SimGrid) -> Array[int]:
	var result: Array[int] = []
	for item_id: int in _grease.keys():
		if grid.item(item_id) == null:
			_grease.erase(item_id)
		elif is_greasy(item_id):
			result.append(item_id)
	result.sort()
	return result


func degrease(item_id: int) -> bool:
	if not is_greasy(item_id):
		return false
	_grease.erase(item_id)
	degreases_today += 1
	return true


func tidy_overnight() -> void:
	_grease.clear()
	spills_today = 0
	broken_plates_today = 0
	degreases_today = 0
