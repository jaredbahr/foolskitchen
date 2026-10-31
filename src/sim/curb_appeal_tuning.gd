class_name CurbAppealTuning
extends Resource
## Authored points for street-front families. Widths, colours and styles share
## a family's repeat allowance; this resource is never changed by evaluation.

const CATEGORIES: Array[StringName] = [&"finish", &"awning", &"window_box", &"sign", &"lights", &"open_sign"]

## Content IDs belong to the authored resource, not the collector's code.
@export var item_categories: Dictionary[StringName, StringName] = {}
@export var weights: Dictionary[StringName, float] = {
	&"finish": 8.0, &"awning": 14.0, &"window_box": 8.0,
	&"sign": 15.0, &"lights": 8.0, &"open_sign": 10.0,
}
@export var caps: Dictionary[StringName, float] = {
	&"finish": 20.0, &"awning": 20.0, &"window_box": 20.0,
	&"sign": 15.0, &"lights": 15.0, &"open_sign": 10.0,
}
## Copy N earns weight * repeat_decay^(N - 1), before the family cap.
@export var repeat_decay: float = 0.65
@export var max_bonus: float = 0.10


func is_valid() -> bool:
	if not is_finite(repeat_decay) or repeat_decay < 0.0 or repeat_decay >= 1.0 \
			or not is_finite(max_bonus) or max_bonus < 0.0 or max_bonus > 0.10:
		return false
	if weights.size() != CATEGORIES.size() or caps.size() != CATEGORIES.size():
		return false
	for item_id: StringName in item_categories:
		if String(item_id).strip_edges().is_empty() or not CATEGORIES.has(item_categories[item_id]):
			return false
	for category: StringName in CATEGORIES:
		if not weights.has(category) or not caps.has(category):
			return false
		var weight: float = weights[category]
		var cap: float = caps[category]
		if not is_finite(weight) or weight < 0.0 or not is_finite(cap) or cap < 0.0 or cap > 100.0:
			return false
	return true
