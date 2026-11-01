class_name RegularProfile
extends RefCounted
## One stable guest identity. Dish and seat ties retain the first enjoyed choice.

var id: int = 0
var repeat_key: String = ""
var display_name: String = ""
var model_id: StringName = &""
var tint_id: StringName = &""
var greeting: String = ""
var favourite_dish: StringName = &""
var favourite_seat: Vector2i = Vector2i.ZERO
var mood: float = 0.7
var active: bool = true
var next_visit_day: int = 0
var last_visit_day: int = 0
var visits: int = 0
var missing_visits: int = 0
var dish_counts: Dictionary[StringName, int] = {}
var seat_counts: Dictionary[Vector2i, int] = {}


func learn(recipe_ids: Array[StringName], seat: Vector2i) -> void:
	for recipe_id: StringName in recipe_ids:
		if recipe_id.is_empty():
			continue
		dish_counts[recipe_id] = dish_counts.get(recipe_id, 0) + 1
		if favourite_dish.is_empty() or dish_counts[recipe_id] > dish_counts.get(favourite_dish, 0):
			favourite_dish = recipe_id
	seat_counts[seat] = seat_counts.get(seat, 0) + 1
	if seat_counts.size() == 1 or seat_counts[seat] > seat_counts.get(favourite_seat, 0):
		favourite_seat = seat


func to_dict() -> Dictionary:
	var dishes: Dictionary = {}
	for recipe_id: StringName in dish_counts:
		dishes[String(recipe_id)] = dish_counts[recipe_id]
	var seats: Array[Dictionary] = []
	for cell: Vector2i in seat_counts:
		seats.append({"x": cell.x, "y": cell.y, "count": seat_counts[cell]})
	return {"id": id, "repeat_key": repeat_key, "name": display_name,
		"model": String(model_id), "tint": String(tint_id), "greeting": greeting,
		"favourite_dish": String(favourite_dish),
		"favourite_seat": [favourite_seat.x, favourite_seat.y],
		"mood": mood, "active": active, "next_day": next_visit_day,
		"last_day": last_visit_day, "visits": visits, "missing": missing_visits,
		"dishes": dishes, "seats": seats}


static func from_dict(data: Dictionary, tuning: RegularsTuning) -> RegularProfile:
	if tuning == null or not tuning.is_valid():
		return null
	for key: String in ["repeat_key", "name", "model", "tint", "greeting", "favourite_dish"]:
		if not data.get(key) is String or (data[key] as String).is_empty():
			return null
	if not _whole(data.get("id"), 1) or not _whole(data.get("next_day"), 1) \
			or not _whole(data.get("last_day"), 1) or not _whole(data.get("visits"), 1) \
			or not _whole(data.get("missing"), 0) or not data.get("active") is bool:
		return null
	var mood_value: Variant = data.get("mood")
	if not (mood_value is float or mood_value is int) or not is_finite(float(mood_value)) \
			or float(mood_value) < 0.0 or float(mood_value) > 1.0:
		return null
	if not tuning.names.has(data["name"]) or not tuning.model_ids.has(StringName(data["model"])) \
			or not tuning.tint_ids.has(StringName(data["tint"])) \
			or not tuning.greetings.has(data["greeting"]):
		return null
	if int(data["next_day"]) <= int(data["last_day"]):
		return null
	var profile: RegularProfile = history_from_dict(data)
	if profile == null:
		return null
	profile.id = int(data["id"])
	profile.repeat_key = data["repeat_key"]
	profile.display_name = data["name"]
	profile.model_id = StringName(data["model"])
	profile.tint_id = StringName(data["tint"])
	profile.greeting = data["greeting"]
	profile.mood = float(mood_value)
	profile.active = data["active"]
	profile.next_visit_day = int(data["next_day"])
	profile.last_visit_day = int(data["last_day"])
	profile.visits = int(data["visits"])
	profile.missing_visits = int(data["missing"])
	return profile


## Anonymous cohorts share the exact same history representation, without any
## invented name, look or calendar fields before they become a regular.
static func history_from_dict(data: Dictionary) -> RegularProfile:
	var cell: Variant = data.get("favourite_seat")
	var dishes: Variant = data.get("dishes")
	var seats: Variant = data.get("seats")
	if not data.get("favourite_dish") is String or (data["favourite_dish"] as String).is_empty() \
			or not cell is Array or cell.size() != 2 or not _coordinate(cell[0]) or not _coordinate(cell[1]) \
			or not dishes is Dictionary or dishes.is_empty() or not seats is Array or seats.is_empty():
		return null
	var profile: RegularProfile = RegularProfile.new()
	profile.favourite_dish = StringName(data["favourite_dish"])
	profile.favourite_seat = Vector2i(int(cell[0]), int(cell[1]))
	for key: Variant in dishes:
		if not key is String or (key as String).is_empty() or not _whole(dishes[key], 1):
			return null
		profile.dish_counts[StringName(key)] = int(dishes[key])
	for entry: Variant in seats:
		if not entry is Dictionary or not _coordinate(entry.get("x")) \
				or not _coordinate(entry.get("y")) or not _whole(entry.get("count"), 1):
			return null
		var seat: Vector2i = Vector2i(int(entry["x"]), int(entry["y"]))
		if profile.seat_counts.has(seat):
			return null
		profile.seat_counts[seat] = int(entry["count"])
	if not profile.dish_counts.has(profile.favourite_dish) \
			or not profile.seat_counts.has(profile.favourite_seat):
		return null
	return profile


static func _whole(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floorf(float(value)) and float(value) >= minimum \
		and float(value) <= 2147483647.0


static func _coordinate(value: Variant) -> bool:
	return _whole(value, -100000) and float(value) <= 100000.0
