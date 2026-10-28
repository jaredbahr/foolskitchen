class_name ReviewQuotes
extends Resource
## Authored text keyed by internal causes. Only quote text reaches the player.

const CAUSES: Array[StringName] = [
	&"slow_seating", &"slow_food", &"great_value", &"too_pricey",
	&"dirty_floor", &"lovely_place", &"never_served", &"no_restroom", &"restroom_busy",
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


## Prefer lines not yet shown today. When this cause group is exhausted, a
## repeat is better than dropping the review; either path draws exactly once.
func pick(cause: StringName, random: RandomNumberGenerator,
		used_today: Dictionary[String, bool]) -> String:
	if random == null:
		return ""
	var lines: PackedStringArray = groups.get(cause, PackedStringArray())
	if lines.is_empty():
		lines = groups.get(&"lovely_place", PackedStringArray())
	if lines.is_empty():
		return ""
	var unused: PackedStringArray = PackedStringArray()
	for line: String in lines:
		if not used_today.has(line):
			unused.append(line)
	if not unused.is_empty():
		lines = unused
	return lines[random.randi_range(0, lines.size() - 1)]
