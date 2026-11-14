class_name OpeningWeekText
extends RefCounted
## Player wording for the paid goal chains (#494 Opening week, #514 Week 2),
## in one place. Each chain's title comes from its data.

## The evening report's ledger line for every chain's payouts.
const LEDGER_LABEL: String = "Week goals"


## The toast and log line when a chain is complete.
static func complete_line(chain: OpeningWeekSet) -> String:
	return "%s complete! Every goal paid out." % chain.title


## The toast and log line when a goal is met.
static func met_line(chain: OpeningWeekSet, goal: OpeningGoal) -> String:
	return "%s: %s  +$%d" % [chain.title, goal.title, goal.reward_cash]


## The morning log line when a chain retires.
static func ended_line(chain: OpeningWeekSet) -> String:
	return "%s is over" % chain.title


## The morning log line when a chain starts.
static func started_line(chain: OpeningWeekSet) -> String:
	return "%s starts: new paid goals in Goals" % chain.title


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
		OpeningGoal.Condition.FLOOR_ADDED:
			return "Since the last opening: %d / %d tiles" % [floori(current), floori(goal.target)]
		OpeningGoal.Condition.CALM_DAY_STARS:
			# The live value is the rating, or -1 once too many guests left today.
			if is_finite(value) and value < 0.0:
				if goal.max_turned_away == 0:
					return "A guest gave up waiting today"
				return "More than %d guests gave up today" % goal.max_turned_away
			return "Now: %.1f stars" % (value if is_finite(value) else 0.0)
	return ""


## "3 days left", counting today, or "Last day".
static func days_left(day: int, last_day: int) -> String:
	var left: int = last_day - day + 1
	if left <= 1:
		return "Last day"
	return "%d days left" % left
