class_name CurbAppealModel
extends RefCounted
## Pure derived curb appeal. An input is one eligible object: {category, id}.
## The adapter owns eligibility; fixed families own repetition, never variants.


static func evaluate(inputs: Array[Dictionary], tuning: CurbAppealTuning) -> Dictionary:
	if tuning == null or not tuning.is_valid():
		return _invalid()
	var counts: Dictionary[StringName, int] = {}
	var seen: Dictionary[String, StringName] = {}
	for row: Dictionary in inputs:
		var category_value: Variant = row.get("category")
		var id_value: Variant = row.get("id")
		if not (category_value is StringName or category_value is String) or not id_value is String:
			return _invalid()
		var category: StringName = StringName(category_value)
		var object_id: String = id_value
		if not CurbAppealTuning.CATEGORIES.has(category) or object_id.strip_edges().is_empty():
			return _invalid()
		if seen.has(object_id):
			if seen[object_id] != category:
				return _invalid()
			continue
		seen[object_id] = category
		counts[category] = counts.get(category, 0) + 1
	var components: Dictionary[StringName, float] = {}
	var total: float = 0.0
	## Fixed addition order gives identical floats for any input permutation.
	for category: StringName in CurbAppealTuning.CATEGORIES:
		var count: int = counts.get(category, 0)
		var points: float = 0.0
		if count > 0:
			points = tuning.weights[category] * (1.0 - pow(tuning.repeat_decay, count)) \
				/ (1.0 - tuning.repeat_decay)
		if not is_finite(points):
			return _invalid()
		components[category] = minf(points, tuning.caps[category])
		total += components[category]
	var score: float = clampf(total, 0.0, 100.0)
	return {"valid": true, "score": score, "multiplier": 1.0 + score / 100.0 * tuning.max_bonus,
		"components": components}


static func _invalid() -> Dictionary:
	return {"valid": false, "score": 0.0, "multiplier": 1.0, "components": {}}
