class_name Milestone
extends Resource
## Authored career goal. Evaluation and day-close rewards belong to the tracker
## and session respectively; a definition never mutates cash or owner XP.

enum Condition {
	SERVED_TODAY,
	REPUTATION,
	PROFIT_TODAY,
	TOTAL_SERVED,
	OWNER_LEVEL,
	STAFF_COUNT,
	CLEAN_STREAK,
}

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export_enum("Served today", "Reputation", "Profit today", "Total served", "Owner level", "Staff count", "Clean streak") var condition: int = Condition.SERVED_TODAY
## Reputation uses a fractional star target; other conditions use whole counts.
@export var target: float = 1.0
@export_range(0, 1000000, 1) var reward_xp: int = 0
@export_range(0, 1000000, 1) var reward_cash: int = 0
@export_range(1, 1000000, 1) var unlock_level: int = 1


func is_valid() -> bool:
	if id.is_empty() or title.strip_edges().is_empty() \
			or description.strip_edges().is_empty() or condition < Condition.SERVED_TODAY \
			or condition > Condition.CLEAN_STREAK or not is_finite(target) \
			or target <= 0.0 or reward_xp < 0 or reward_xp > 1000000 \
			or reward_cash < 0 or reward_cash > 1000000 \
			or (reward_xp == 0 and reward_cash == 0) \
			or unlock_level < 1 or unlock_level > 1000000:
		return false
	if condition == Condition.REPUTATION:
		return target <= 5.0
	return target <= 1000000000.0 and floorf(target) == target
