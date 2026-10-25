class_name MilestoneSet
extends Resource
## The authored, ordered starter goals. IDs must be unique before a day closes.

const MAX_MILESTONES: int = 64

@export var milestones: Array[Milestone] = []


func is_valid() -> bool:
	if milestones.is_empty() or milestones.size() > MAX_MILESTONES:
		return false
	var seen: Dictionary[StringName, bool] = {}
	for goal: Milestone in milestones:
		if goal == null or not goal.is_valid() or seen.has(goal.id):
			return false
		seen[goal.id] = true
	return true


func by_id(id: StringName) -> Milestone:
	for goal: Milestone in milestones:
		if goal != null and goal.id == id:
			return goal
	return null
