class_name OpeningWeekSet
extends Resource
## The authored opening-week chain (#494): ordered goals, how many show at a
## time and the last day the chain runs.

const MAX_GOALS: int = 32

@export var goals: Array[OpeningGoal] = []
## The chain retires on the morning after this day.
@export_range(1, 365, 1) var last_day: int = 7
## How many unfinished goals the Goals card and HUD tracker show at once.
@export_range(1, 8, 1) var shown_goals: int = 3


func is_valid() -> bool:
	if goals.is_empty() or goals.size() > MAX_GOALS or last_day < 1 or shown_goals < 1:
		return false
	var seen: Dictionary[StringName, bool] = {}
	for goal: OpeningGoal in goals:
		if goal == null or not goal.is_valid() or seen.has(goal.id):
			return false
		seen[goal.id] = true
	return true


func by_id(id: StringName) -> OpeningGoal:
	for goal: OpeningGoal in goals:
		if goal != null and goal.id == id:
			return goal
	return null


func total_cash() -> int:
	var total: int = 0
	for goal: OpeningGoal in goals:
		if goal != null:
			total += goal.reward_cash
	return total
