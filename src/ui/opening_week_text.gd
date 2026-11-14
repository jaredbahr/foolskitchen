class_name OpeningWeekText
extends RefCounted
## Player wording for the opening-week chain (#494), in one place.

const TITLE: String = "Opening week"
const COMPLETE_LINE: String = "Opening week complete! Every goal paid out."


## The toast and log line when a goal is met.
static func met_line(goal: OpeningGoal) -> String:
	return "Opening week: %s  +$%d" % [goal.title, goal.reward_cash]


## One compact HUD tracker row.
static func tracker_line(goal: OpeningGoal) -> String:
	return "□ %s  $%d" % [goal.title, goal.reward_cash]


## The Goals card's progress line for one goal, from its live value.
static func progress_line(goal: OpeningGoal, value: float) -> String:
	var current: float = clampf(value if is_finite(value) else 0.0, 0.0, goal.target)
	match goal.condition:
		OpeningGoal.Condition.SERVED_TODAY:
			return "Today: %d / %d guests" % [floori(current), floori(goal.target)]
		OpeningGoal.Condition.FIVE_STAR_REVIEWS_TODAY:
			return "Today: %d / %d five-star reviews" % [floori(current), floori(goal.target)]
	return ""


## "3 days left", counting today, or "Last day".
static func days_left(day: int, last_day: int) -> String:
	var left: int = last_day - day + 1
	if left <= 1:
		return "Last day"
	return "%d days left" % left
