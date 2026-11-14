class_name OpeningWeekSet
extends Resource
## One authored paid goal chain (#494 Opening week, #514 Week 2): ordered
## goals, how many show at a time and how many days it runs. Chains follow
## one another in a GoalChainSequence.

const MAX_GOALS: int = 32

## Saved in the `opening_week` section to name the running chain; never rename.
@export var id: StringName = &""
## The card and tracker heading, and the start of each paid line.
@export var title: String = ""
@export var goals: Array[OpeningGoal] = []
## The chain runs this many days from its first morning, then retires.
@export_range(1, 365, 1) var days: int = 7
## How many unfinished goals the Goals card and HUD tracker show at once.
@export_range(1, 8, 1) var shown_goals: int = 3


func is_valid() -> bool:
	if id.is_empty() or title.strip_edges().is_empty() \
			or goals.is_empty() or goals.size() > MAX_GOALS or days < 1 or shown_goals < 1:
		return false
	var seen: Dictionary[StringName, bool] = {}
	for goal: OpeningGoal in goals:
		if goal == null or not goal.is_valid() or seen.has(goal.id):
			return false
		seen[goal.id] = true
	return true


func by_id(id_value: StringName) -> OpeningGoal:
	for goal: OpeningGoal in goals:
		if goal != null and goal.id == id_value:
			return goal
	return null


func total_cash() -> int:
	var total: int = 0
	for goal: OpeningGoal in goals:
		if goal != null:
			total += goal.reward_cash
	return total
