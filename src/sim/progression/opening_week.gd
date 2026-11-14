class_name OpeningWeek
extends RefCounted
## The opening-week goal chain's progress (#494). Pure and deterministic: the
## session reports what it observed (`observe`) and pays the goals this
## returns, each once. Goals are never failed and carry over between days;
## the chain ends once every goal is done or after the set's last day. XP
## waits in `pending_xp` until the day's close adds it to the owner's XP.

enum Status { ACTIVE, ENDED }

const SAVE_VERSION: int = 1
const MAX_PENDING_XP: int = 1000000

var status: Status = Status.ACTIVE
var pending_xp: int = 0
## Completed goal ids in the order they were met.
var _completed: Array[StringName] = []


## A save from before the chain existed: it joins only while still in the week.
static func legacy_for_day(day: int, catalogue: OpeningWeekSet) -> OpeningWeek:
	var state: OpeningWeek = OpeningWeek.new()
	if catalogue == null or not catalogue.is_valid() or day > catalogue.last_day:
		state.status = Status.ENDED
	return state


static func ended() -> OpeningWeek:
	var state: OpeningWeek = OpeningWeek.new()
	state.status = Status.ENDED
	return state


func is_active() -> bool:
	return status == Status.ACTIVE


func is_completed(id: StringName) -> bool:
	return _completed.has(id)


func completed_ids() -> Array[StringName]:
	return _completed.duplicate()


## Records one observation and returns the goals it newly meets, in chain
## order. Every unfinished goal of that condition is checked, shown or not,
## so nothing the player does early is wasted. Their XP joins pending_xp.
func observe(condition: int, value: float, catalogue: OpeningWeekSet) -> Array[OpeningGoal]:
	var met: Array[OpeningGoal] = []
	if not is_active() or catalogue == null or not catalogue.is_valid() or not is_finite(value):
		return met
	for goal: OpeningGoal in catalogue.goals:
		if goal.condition == condition and not _completed.has(goal.id) and value >= goal.target:
			met.append(goal)
	for goal: OpeningGoal in met:
		_completed.append(goal.id)
		pending_xp = mini(MAX_PENDING_XP, pending_xp + goal.reward_xp)
	return met


## True when every authored goal is done.
func all_done(catalogue: OpeningWeekSet) -> bool:
	if catalogue == null or not catalogue.is_valid():
		return false
	for goal: OpeningGoal in catalogue.goals:
		if not _completed.has(goal.id):
			return false
	return true


## Ends the chain once every goal is done or `day` is past the last day.
## Returns true only on the call that ends it.
func end_if_due(day: int, catalogue: OpeningWeekSet) -> bool:
	if not is_active():
		return false
	if catalogue == null or not catalogue.is_valid() or day > catalogue.last_day or all_done(catalogue):
		status = Status.ENDED
		return true
	return false


## The next unfinished goals in chain order, at most `shown_goals` of them.
func shown(catalogue: OpeningWeekSet) -> Array[OpeningGoal]:
	var result: Array[OpeningGoal] = []
	if not is_active() or catalogue == null or not catalogue.is_valid():
		return result
	for goal: OpeningGoal in catalogue.goals:
		if not _completed.has(goal.id):
			result.append(goal)
			if result.size() >= catalogue.shown_goals:
				break
	return result


## Hands the waiting XP to the caller once.
func take_pending_xp() -> int:
	var xp: int = pending_xp
	pending_xp = 0
	return xp


func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for id: StringName in _completed:
		ids.append(String(id))
	return {"version": SAVE_VERSION, "status": "active" if is_active() else "ended",
		"completed": ids, "pending_xp": pending_xp}


## Decodes transactionally. Unknown but well-formed ids stay completed, so a
## goal removed from the data and later restored is never paid twice.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if row.size() != 4 or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("pending_xp"), 0, MAX_PENDING_XP) \
			or not row.get("completed") is Array \
			or not (row.get("status") is String and (row["status"] == "active" or row["status"] == "ended")):
		return false
	var staged: Array[StringName] = []
	for item: Variant in row["completed"]:
		if not item is String or (item as String).is_empty() or staged.has(StringName(item)):
			return false
		staged.append(StringName(item))
	status = Status.ACTIVE if row["status"] == "active" else Status.ENDED
	pending_xp = int(row["pending_xp"])
	_completed = staged
	return true


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floorf(number) == number
