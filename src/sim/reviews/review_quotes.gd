class_name ReviewQuotes
extends Resource
## Authored text keyed by internal causes. Only quote text reaches the player.

const CAUSES: Array[StringName] = [
	&"slow_seating", &"slow_food", &"great_value", &"too_pricey",
	&"dirty_floor", &"sticky_floor", &"lovely_place", &"never_served", &"no_restroom", &"restroom_busy",
	&"comfortable_wait", &"petted_cat", &"critic_good", &"critic_bad",
	&"signature_dish",
	# Guest quirks (docs/GUESTS.md): good visits by a guest with that quirk.
	&"photo_happy", &"chatty_happy", &"quick_lunch",
	# Guest type voices: good visits that would otherwise use lovely_place.
	&"regular_happy", &"student_happy", &"foodie_happy", &"family_happy",
	&"tourist_happy", &"office_happy",
]
## Which group a guest type writes its good-visit review from, by customer type id.
const TYPE_CAUSES: Dictionary[StringName, StringName] = {
	&"regular": &"regular_happy", &"student": &"student_happy", &"foodie": &"foodie_happy",
	&"family": &"family_happy", &"tourist": &"tourist_happy", &"office": &"office_happy",
}

@export var groups: Dictionary[StringName, PackedStringArray] = {}


## The quote group for a good visit that would otherwise say lovely_place: the
## guest type's own voice, or lovely_place for a type without one.
static func type_cause(type_id: StringName) -> StringName:
	return TYPE_CAUSES.get(type_id, &"lovely_place")


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


## A lovely_place pick that may be written in a guest type's `voice` group.
## Quote text is the only thing the voice changes: the draw is made over the
## shared lovely_place pool exactly as pick() would (`lovely_used` is that
## pool's own used-today record, kept apart from `used_today`), so the number
## of draws and every later draw in the review stream are the same with or
## without a voice (#602). The voice line is then chosen by the same index
## position. An empty or missing voice returns the shared line itself.
func pick_lovely(voice: StringName, random: RandomNumberGenerator,
		used_today: Dictionary[String, bool], lovely_used: Dictionary[String, bool]) -> String:
	if random == null:
		return ""
	var shared: PackedStringArray = groups.get(&"lovely_place", PackedStringArray())
	if shared.is_empty():
		return ""
	var open_shared: PackedStringArray = PackedStringArray()
	for line: String in shared:
		if not lovely_used.has(line):
			open_shared.append(line)
	if open_shared.is_empty():
		open_shared = shared
	var index: int = random.randi_range(0, open_shared.size() - 1)
	var chosen: String = open_shared[index]
	lovely_used[chosen] = true
	var own: PackedStringArray = groups.get(voice, PackedStringArray())
	if own.is_empty():
		return chosen
	var open_own: PackedStringArray = PackedStringArray()
	for line: String in own:
		if not used_today.has(line):
			open_own.append(line)
	if open_own.is_empty():
		open_own = own
	return open_own[index * open_own.size() / open_shared.size()]
