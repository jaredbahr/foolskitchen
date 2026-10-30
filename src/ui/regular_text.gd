class_name RegularText
extends RefCounted
## Plain, shared labels for saved regular profiles; never exposes internal IDs.

const FAVOURITE: String = "A regular's favourite"


static func feeling(mood: float) -> String:
	if mood >= 0.75:
		return "Loves coming here"
	if mood >= 0.5:
		return "Feels welcome"
	if mood >= 0.3:
		return "Feeling disappointed"
	return "May stop coming"


static func inspection(profile: RegularProfile, dish_label: String) -> String:
	var dish: String = dish_label if not dish_label.is_empty() else "A dish from an earlier menu"
	return "Favourite dish: %s\nFavourite seat: column %d, row %d\n%s" % [dish,
		profile.favourite_seat.x + 1, profile.favourite_seat.y + 1, feeling(profile.mood)]


static func report_lines(cast: RegularCast) -> Array[String]:
	var lines: Array[String] = []
	if cast == null:
		return lines
	for group: int in 2:
		var names: PackedStringArray = []
		var ids: Array[int] = cast.visited_today if group == 0 else cast.new_today
		for id: int in ids:
			var profile: RegularProfile = cast.get_profile(id)
			if profile != null:
				names.append(profile.display_name)
		if not names.is_empty():
			lines.append(("Came: " if group == 0 else "New regulars: ") + ", ".join(names))
	for id: int in cast.left_today:
		var profile: RegularProfile = cast.get_profile(id)
		if profile != null:
			lines.append("%s hasn't been back" % profile.display_name)
	return lines
