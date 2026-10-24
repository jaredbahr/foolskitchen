class_name ReviewQuotes
extends Resource
## Authored text keyed by internal causes. Only quote text reaches the player.

const CAUSES: Array[StringName] = [
	&"slow_seating", &"slow_food", &"great_value", &"too_pricey",
	&"dirty_floor", &"lovely_place", &"never_served",
]

@export var groups: Dictionary[StringName, PackedStringArray] = {}


func is_valid() -> bool:
	var count: int = 0
	for cause: StringName in CAUSES:
		if not groups.has(cause) or groups[cause].is_empty():
			return false
		for line: String in groups[cause]:
			if line.strip_edges().is_empty():
				return false
			count += 1
	return count >= 40


func pick(cause: StringName, random: RandomNumberGenerator) -> String:
	if random == null:
		return ""
	var lines: PackedStringArray = groups.get(cause, PackedStringArray())
	if lines.is_empty():
		lines = groups.get(&"lovely_place", PackedStringArray())
	if lines.is_empty():
		return ""
	return lines[random.randi_range(0, lines.size() - 1)]
