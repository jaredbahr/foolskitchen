class_name StaffAdviceTuning
extends Resource
## Display-only staffing heuristics; these rules never change a simulation.

@export var high_busy_percent: float = 90.0
@export var low_busy_percent: float = 70.0
@export var min_waiting_losses: int = 1
@export var min_no_table_losses: int = 5


## One ordered recommendation from unrounded observed ratios and loss counts.
func recommendation(summary: Dictionary, leave_reasons: Dictionary) -> StringName:
	var activity: Dictionary = StaffActivity.public_snapshot(summary)
	if activity.is_empty() or not _valid_thresholds():
		return &""
	var roles: Dictionary = activity["roles"]
	var waiting: int = _loss_count(leave_reasons.get(&"waited_too_long", 0))
	if waiting >= min_waiting_losses:
		for role: StringName in [&"cook", &"server"]:
			if roles.has(String(role)) and _busy_percent(roles[String(role)]) >= high_busy_percent:
				return role
	var has_regular_staff: bool = false
	var all_low: bool = true
	for role: StringName in [&"cook", &"server", &"cleaner"]:
		if roles.has(String(role)):
			has_regular_staff = true
			all_low = all_low and _busy_percent(roles[String(role)]) < low_busy_percent
	if has_regular_staff and all_low \
			and _loss_count(leave_reasons.get(&"no_table", 0)) >= min_no_table_losses:
		return &"tables"
	return &"keeping_up"


func _valid_thresholds() -> bool:
	return is_finite(high_busy_percent) and is_finite(low_busy_percent) \
		and high_busy_percent >= 0.0 and high_busy_percent <= 100.0 \
		and low_busy_percent >= 0.0 and low_busy_percent <= high_busy_percent \
		and min_waiting_losses >= 0 and min_no_table_losses >= 0


static func _busy_percent(row: Dictionary) -> float:
	return float(row["busy_ticks"]) / float(row["open_ticks"]) * 100.0


static func _loss_count(value: Variant) -> int:
	if value is int:
		return maxi(0, value)
	if value is float and is_finite(value) and value >= 0.0 \
			and value <= StaffActivity.MAX_COUNT and floorf(value) == value:
		return int(value)
	return 0
