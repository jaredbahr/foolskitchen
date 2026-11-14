class_name OpeningWeek
extends RefCounted
## The paid goal chains' progress (#494 Opening week, #514 Week 2). Pure and
## deterministic: the session reports what it observed (`observe`) and pays
## the goals this returns, each once. Goals are never failed and carry over
## between days; a chain ends once every goal is done or after its last day,
## and the next chain in the GoalChainSequence starts the following morning
## (`advance`). XP waits in `pending_xp` until the day's close adds it to the
## owner's XP. The goal-taking methods take the running chain's set, which
## `current` resolves.

## ACTIVE: `chain_id` is running. ENDED: it is over and the next chain, if
## any, starts at the next morning. FINISHED: no chain is left (Creative too).
enum Status { ACTIVE, ENDED, FINISHED }

const SAVE_VERSION: int = 2
const MAX_PENDING_XP: int = 1000000
const MAX_DAY: int = 1000000

var status: Status = Status.ACTIVE
var pending_xp: int = 0
## The running (or last) chain; empty means the sequence's first chain.
var chain_id: StringName = &""
## The morning the running chain started; its last day is start_day + days - 1.
var start_day: int = 1
## The running chain's completed goal ids in the order they were met.
var _completed: Array[StringName] = []


## A new career game: the sequence's first chain from day 1.
static func starting(sequence: GoalChainSequence) -> OpeningWeek:
	var state: OpeningWeek = OpeningWeek.new()
	var first: OpeningWeekSet = sequence.at(0) if sequence != null else null
	if first == null:
		state.status = Status.FINISHED
	else:
		state.chain_id = first.id
	return state


## A save from before the chains existed: the first chain runs while still in
## its week; past it, the chain is over and `advance` decides whether a later
## chain's window still holds `day`.
static func legacy_for_day(day: int, sequence: GoalChainSequence) -> OpeningWeek:
	var state: OpeningWeek = starting(sequence)
	if state.is_active() and day > state.last_day(sequence.at(0)):
		state.status = Status.ENDED
	return state


## No chain at all, now or later (Creative games and tools).
static func ended() -> OpeningWeek:
	var state: OpeningWeek = OpeningWeek.new()
	state.status = Status.FINISHED
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
## A non-empty `goal_id` checks only that goal: the value of a goal with its
## own items, station or role belongs to it alone.
func observe(condition: int, value: float, catalogue: OpeningWeekSet,
		goal_id: StringName = &"") -> Array[OpeningGoal]:
	var met: Array[OpeningGoal] = []
	if not is_active() or catalogue == null or not catalogue.is_valid() or not is_finite(value):
		return met
	for goal: OpeningGoal in catalogue.goals:
		if goal.condition == condition and not _completed.has(goal.id) and value >= goal.target \
				and (goal_id.is_empty() or goal.id == goal_id):
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


## Ends the running chain once every goal is done or `day` is past its last
## day. Returns true only on the call that ends it.
func end_if_due(day: int, catalogue: OpeningWeekSet) -> bool:
	if not is_active():
		return false
	if catalogue == null or not catalogue.is_valid() or day > last_day(catalogue) or all_done(catalogue):
		status = Status.ENDED
		return true
	return false


## The running chain's last day.
func last_day(catalogue: OpeningWeekSet) -> int:
	return start_day + (catalogue.days if catalogue != null else 1) - 1


## The running chain's authored set, or null when none runs or its id is
## unknown (a chain removed from the data).
func current(sequence: GoalChainSequence) -> OpeningWeekSet:
	if status == Status.FINISHED or sequence == null:
		return null
	return sequence.by_id(chain_id)


## Morning hand-over: after an ended chain, starts the next chain whose window
## still holds `day`. A chain starts today, but never later than its natural
## window (an old save past it joins late with the days that remain, or skips
## it). Returns true when a chain starts; with none left, the state finishes.
func advance(day: int, sequence: GoalChainSequence) -> bool:
	if status != Status.ENDED:
		return false
	var index: int = sequence.index_of(chain_id) if sequence != null else -1
	if index >= 0:
		for next: int in range(index + 1, sequence.chains.size()):
			var chain: OpeningWeekSet = sequence.at(next)
			var first_day: int = mini(day, sequence.natural_start(next))
			if day <= first_day + chain.days - 1:
				status = Status.ACTIVE
				chain_id = chain.id
				start_day = first_day
				_completed.clear()
				return true
	status = Status.FINISHED
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


const STATUS_NAMES: Array[String] = ["active", "ended", "finished"]


func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for id: StringName in _completed:
		ids.append(String(id))
	return {"version": SAVE_VERSION, "chain": String(chain_id), "start_day": start_day,
		"status": STATUS_NAMES[status], "completed": ids, "pending_xp": pending_xp}


## Decodes transactionally. Unknown but well-formed ids stay completed, so a
## goal removed from the data and later restored is never paid twice. Version
## 1 (#494) held the Opening week alone: it becomes the first chain from day 1,
## and the next morning's `advance` hands an ended one over to Week 2.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	var version_one: bool = row.size() == 4 and _whole(row.get("version"), 1, 1)
	var version_two: bool = row.size() == 6 and _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
		and row.get("chain") is String and _whole(row.get("start_day"), 1, MAX_DAY)
	if not (version_one or version_two) \
			or not _whole(row.get("pending_xp"), 0, MAX_PENDING_XP) \
			or not row.get("completed") is Array or not row.get("status") is String:
		return false
	var status_index: int = STATUS_NAMES.find(row["status"] as String)
	if status_index < 0 or (version_one and status_index == Status.FINISHED):
		return false
	var staged: Array[StringName] = []
	for item: Variant in row["completed"]:
		if not item is String or (item as String).is_empty() or staged.has(StringName(item)):
			return false
		staged.append(StringName(item))
	status = status_index as Status
	pending_xp = int(row["pending_xp"])
	chain_id = StringName(row["chain"]) if version_two else &""
	start_day = int(row["start_day"]) if version_two else 1
	_completed = staged
	return true


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floorf(number) == number
