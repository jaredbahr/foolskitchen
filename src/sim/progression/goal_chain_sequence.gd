class_name GoalChainSequence
extends Resource
## The paid goal chains in the order they run (#514): Opening week from day 1,
## then Week 2 from the morning after it ends. Each chain's natural window
## starts the day after the windows of the chains before it.

const MAX_CHAINS: int = 16

@export var chains: Array[OpeningWeekSet] = []


func is_valid() -> bool:
	if chains.is_empty() or chains.size() > MAX_CHAINS:
		return false
	var seen: Dictionary[StringName, bool] = {}
	for chain: OpeningWeekSet in chains:
		if chain == null or not chain.is_valid() or seen.has(chain.id):
			return false
		seen[chain.id] = true
	return true


## The chain's position, -1 when unknown. An empty id is the first chain
## (an OpeningWeek made before it was told which chain it runs).
func index_of(id: StringName) -> int:
	if not is_valid():
		return -1
	if id.is_empty():
		return 0
	for index: int in chains.size():
		if chains[index].id == id:
			return index
	return -1


func at(index: int) -> OpeningWeekSet:
	if not is_valid() or index < 0 or index >= chains.size():
		return null
	return chains[index]


func by_id(id: StringName) -> OpeningWeekSet:
	return at(index_of(id))


## The first day of the chain's natural window: day 1 for the first, then the
## day after the earlier chains' full runs (day 8 for Week 2).
func natural_start(index: int) -> int:
	var day: int = 1
	for earlier: int in mini(index, chains.size()):
		day += chains[earlier].days
	return day
