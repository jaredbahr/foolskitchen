class_name RegularsTuning
extends Resource
## Authored cast, promotion and gentle menu-pull rules. No visual resources.

@export var min_day: int = 6
@export var min_stars: float = 2.5
@export var min_vibe: float = 1.0
@export var min_satisfied_visits: int = 2
@export var cast_cap: int = 8
@export var visit_days_min: int = 2
@export var visit_days_max: int = 4
@export var initial_mood: float = 0.7
@export var good_visit_gain: float = 0.08
@export var bad_visit_loss: float = 0.2
@export var missing_favourite_loss: float = 0.12
@export var missing_penalty_after: int = 2
@export var leave_below: float = 0.2
@export var good_quality: float = 0.6
@export var long_wait_fraction: float = 0.75
@export var favourite_happiness: float = 0.08
@export var base_tip_rate: float = 0.04
@export var favourite_tip_rate: float = 0.04
@export var names: PackedStringArray = []
@export var model_ids: Array[StringName] = []
@export var tint_ids: Array[StringName] = []
@export var greetings: PackedStringArray = []


func is_valid() -> bool:
	if min_day < 6 or min_satisfied_visits < 2 or cast_cap < 6 or cast_cap > 10 \
			or visit_days_min < 1 or visit_days_max < visit_days_min \
			or missing_penalty_after < 1 or names.size() < cast_cap \
			or model_ids.is_empty() or tint_ids.is_empty() or greetings.is_empty():
		return false
	if not is_finite(min_stars) or min_stars < 0.0 or min_stars > 5.0 \
			or not is_finite(min_vibe) or min_vibe < 0.0 or min_vibe > 100.0:
		return false
	for value: float in [initial_mood, good_visit_gain, bad_visit_loss,
			missing_favourite_loss, leave_below, good_quality, long_wait_fraction,
			favourite_happiness, base_tip_rate, favourite_tip_rate]:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return false
	if initial_mood <= leave_below:
		return false
	var seen: Dictionary[String, bool] = {}
	for name_text: String in names:
		if name_text.strip_edges().is_empty() or seen.has(name_text):
			return false
		seen[name_text] = true
	for id: StringName in model_ids:
		if id.is_empty():
			return false
	for id: StringName in tint_ids:
		if id.is_empty():
			return false
	for greeting: String in greetings:
		if greeting.strip_edges().is_empty():
			return false
	return true
