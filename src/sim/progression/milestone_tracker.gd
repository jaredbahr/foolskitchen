class_name MilestoneTracker
extends RefCounted
## Deterministic day-close condition tracking. It returns newly reached goals;
## the session applies their ledger and owner-XP rewards separately, then saves
## this snapshot at the existing next-morning autosave.

const SAVE_VERSION: int = 1
const MAX_TOTAL_SERVED: int = 1000000000
const MAX_DAYS: int = 1000000

var total_served: int = 0
var clean_streak: int = 0
var last_evaluated_day: int = 0
var _completed: Dictionary[StringName, bool] = {}


func is_completed(id: StringName) -> bool:
	return _completed.has(id)


func completed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _completed:
		ids.append(id)
	ids.sort()
	return ids


## A bad catalogue/day or repeated close changes nothing. Missing days reset
## the clean streak, so a loaded game cannot invent consecutive perfect days.
func evaluate_day(observation: MilestoneDay, catalogue: MilestoneSet) -> Array[Milestone]:
	var reached: Array[Milestone] = []
	if observation == null or not observation.is_valid() or catalogue == null \
			or not catalogue.is_valid() or observation.day <= last_evaluated_day \
			or total_served > MAX_TOTAL_SERVED - observation.served_today:
		return reached
	var next_total: int = total_served + observation.served_today
	var next_streak: int = 0
	if observation.lost_today == 0:
		if last_evaluated_day == 0 or observation.day == last_evaluated_day + 1:
			next_streak = clean_streak + 1
		else:
			next_streak = 1
		if next_streak > MAX_DAYS:
			return reached
	for goal: Milestone in catalogue.milestones:
		if _completed.has(goal.id) or goal.unlock_level > observation.owner_level:
			continue
		if _meets(goal, observation, next_total, next_streak):
			reached.append(goal)
	total_served = next_total
	clean_streak = next_streak
	last_evaluated_day = observation.day
	for goal: Milestone in reached:
		_completed[goal.id] = true
	return reached


static func _meets(goal: Milestone, observation: MilestoneDay,
		cumulative_served: int, consecutive_clean_days: int) -> bool:
	match goal.condition:
		Milestone.Condition.SERVED_TODAY:
			return float(observation.served_today) >= goal.target
		Milestone.Condition.REPUTATION:
			return observation.reputation >= goal.target
		Milestone.Condition.PROFIT_TODAY:
			return float(observation.operating_profit) >= goal.target
		Milestone.Condition.TOTAL_SERVED:
			return float(cumulative_served) >= goal.target
		Milestone.Condition.OWNER_LEVEL:
			return float(observation.owner_level) >= goal.target
		Milestone.Condition.STAFF_COUNT:
			return float(observation.staff_count) >= goal.target
		Milestone.Condition.CLEAN_STREAK:
			return float(consecutive_clean_days) >= goal.target
	return false


func to_dict() -> Dictionary:
	var saved_ids: Array[String] = []
	for id: StringName in completed_ids():
		saved_ids.append(String(id))
	return {"version": SAVE_VERSION, "completed": saved_ids,
		"total_served": total_served, "clean_streak": clean_streak,
		"last_evaluated_day": last_evaluated_day}


## Decode transactionally; unknown but well-formed IDs remain completed so a
## removed content file cannot accidentally pay the same goal on its return.
## The catalogue limit bounds active goals, not lifetime completion history.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if row.size() != 5 or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("total_served"), 0, MAX_TOTAL_SERVED) \
			or not _whole(row.get("clean_streak"), 0, MAX_DAYS) \
			or not _whole(row.get("last_evaluated_day"), 0, MAX_DAYS) \
			or not row.get("completed") is Array:
		return false
	var saved_ids: Array = row["completed"]
	if int(row["clean_streak"]) > int(row["last_evaluated_day"]):
		return false
	var staged: Dictionary[StringName, bool] = {}
	for value_id: Variant in saved_ids:
		if not (value_id is String or value_id is StringName):
			return false
		var id: StringName = StringName(value_id)
		if id.is_empty() or staged.has(id):
			return false
		staged[id] = true
	total_served = int(row["total_served"])
	clean_streak = int(row["clean_streak"])
	last_evaluated_day = int(row["last_evaluated_day"])
	_completed = staged
	return true


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum \
		and floorf(number) == number
