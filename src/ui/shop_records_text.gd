class_name ShopRecordsText
extends RefCounted
## All Records wording and units; simulation keys never become player text.

const TITLES: Dictionary = {
	&"guests": "Most guests in a day", &"profit": "Best operating profit",
	&"dishes": "Most dishes in a day", &"reputation": "Highest reputation",
	&"streak": "Longest run without angry guests",
}


static func rows(records: Dictionary, content: ContentDB = null) -> Array[String]:
	var lines: Array[String] = []
	if int(records["last_day"]) == 0:
		lines.append("Finish a service day to start your records.")
		return lines
	lines.append("Total guests served: %d" % records["guests"])
	lines.append("Total revenue (meals and tips): %s" % Fmt.money(int(records["revenue"])))
	var dishes: Dictionary = records["dishes"]
	var ids: Array[String] = []
	for id: StringName in dishes:
		ids.append(String(id))
	ids.sort()
	var most: StringName = &""
	var total: int = 0
	for id: String in ids:
		var count: int = int(dishes[StringName(id)])
		total += count
		if most == &"" or count > int(dishes[most]):
			most = StringName(id)
	lines.append("Total dishes sold: %d" % total)
	lines.append("Most-sold dish ever: %s (%d)" % [_dish_name(most, content), int(dishes[most])] \
		if most != &"" else "Most-sold dish ever: no dishes sold")
	var bests: Dictionary = records["bests"]
	for id: StringName in ShopRecords.BEST_IDS:
		if bests.has(id):
			var best: Dictionary = bests[id]
			lines.append("%s: %s (day %d)" % [TITLES[id], _value(id, best["value"]), best["day"]])
		elif id == &"profit":
			lines.append("Best operating profit: not recorded yet")
	if not ids.is_empty():
		lines.append("Dishes sold over the shop's lifetime:")
		for id: String in ids:
			lines.append("%s: %d" % [_dish_name(StringName(id), content), dishes[StringName(id)]])
	return lines


static func new_record_lines(records: Dictionary, beaten: Array[StringName]) -> Array[String]:
	var lines: Array[String] = []
	for id: StringName in ShopRecords.BEST_IDS:
		if beaten.has(id):
			var best: Dictionary = records["bests"][id]
			if id != &"profit" and float(best["value"]) <= 0.0:
				continue
			lines.append("New record: %s (%s)!" % [String(TITLES[id]).to_lower(), _value(id, best["value"])])
	return lines


static func _value(id: StringName, value: Variant) -> String:
	match id:
		&"profit":
			return Fmt.money(int(value))
		&"reputation":
			return "%.1f stars" % float(value)
		&"streak":
			return "%d days" % int(value)
	return str(int(value))


static func _dish_name(id: StringName, content: ContentDB) -> String:
	var recipe: RecipeDef = content.recipe(id) if content != null else null
	return recipe.display_name if recipe != null else "Former dish"
