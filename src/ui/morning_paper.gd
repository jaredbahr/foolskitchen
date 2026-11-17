class_name MorningPaper
extends RefCounted
## Builds display copy from known facts and the caller's paper stream.

const MASTHEAD: String = "The Daily Ladle"
const HEADLINES: MorningPaperHeadlines = preload("res://data/paper/headlines.tres")
const FALLBACK_HEADLINE: String = "The kitchen gets ready for another day"
const FALLBACK_DISH: String = "the menu"
const MAX_NOTES: int = 3


static func build(day: int, yesterday: DayReport, weather_kind: int, notes: Array[String],
		rng: RandomNumberGenerator, dish: String = "", history: Dictionary = {}) -> Dictionary:
	var group: StringName = _headline_group(day, yesterday, history)
	var templates: PackedStringArray = HEADLINES.groups.get(group, PackedStringArray())
	var headline: String = FALLBACK_HEADLINE
	if not templates.is_empty():
		headline = templates[rng.randi_range(0, templates.size() - 1)]
	var guests: int = yesterday.customers_served if yesterday != null else int(history.get("served", 0))
	if group == &"walkouts":
		guests = yesterday.customers_lost if yesterday != null else int(history.get("lost", 0))
	var cash: int = yesterday.profit() if yesterday != null else int(history.get("cash_change", 0))
	var fields: Dictionary[String, String] = {
		"dish": dish if not dish.is_empty() else FALLBACK_DISH,
		"guests": str(guests),
		"cash": Fmt.money(cash),
	}
	return {"masthead": MASTHEAD, "headline": _fill(headline, fields),
		"notes": _briefs(yesterday, weather_kind, notes)}


static func best_dish(dishes: Dictionary, content: ContentDB) -> String:
	var best_count: int = 0
	var best_id: String = ""
	var best_name: String = ""
	for key: Variant in dishes:
		var id: String = String(key)
		var count: int = int(dishes[key])
		if count <= 0 or count < best_count or (count == best_count and id >= best_id):
			continue
		var recipe: RecipeDef = content.recipe(StringName(id))
		if recipe != null and not recipe.display_name.is_empty():
			best_count = count
			best_id = id
			best_name = recipe.display_name
	return best_name


static func _headline_group(day: int, yesterday: DayReport, history: Dictionary) -> StringName:
	if day == 1:
		return &"first_day"
	if yesterday == null and history.is_empty():
		return &""
	if yesterday != null and not yesterday.inspection_lines.is_empty():
		return &"inspection"
	if yesterday != null and not yesterday.record_lines.is_empty():
		return &"record"
	var cash: int = yesterday.profit() if yesterday != null else int(history.get("cash_change", 0))
	if cash < 0:
		return &"loss"
	var lost: int = yesterday.customers_lost if yesterday != null else int(history.get("lost", 0))
	if lost >= 3:
		return &"walkouts"
	if yesterday != null:
		for card: Dictionary in yesterday.review_cards:
			if int(card.get("stars", 0)) == 5:
				return &"review"
	return &"quiet"


static func _briefs(yesterday: DayReport, weather_kind: int, notes: Array[String]) -> Array[String]:
	var available: Array[String] = []
	if weather_kind in [WeatherState.Kind.SUNNY, WeatherState.Kind.CLOUDY, WeatherState.Kind.RAIN]:
		available.append(WeatherText.forecast_for(weather_kind))
	if yesterday != null and not yesterday.inspection_lines.is_empty():
		available.append(yesterday.inspection_lines[0])
	available.append_array(notes)
	var briefs: Array[String] = []
	for line: String in available:
		var brief: String = line.strip_edges()
		if not brief.is_empty() and not briefs.has(brief):
			briefs.append(brief)
		if briefs.size() == MAX_NOTES:
			break
	return briefs


## Copy only the template's fields. Replacement values are always literal.
static func _fill(template: String, fields: Dictionary[String, String]) -> String:
	var slots: RegEx = RegEx.create_from_string("\\{(dish|guests|cash)\\}")
	var text: String = ""
	var cursor: int = 0
	for slot: RegExMatch in slots.search_all(template):
		text += template.substr(cursor, slot.get_start() - cursor)
		text += fields[slot.get_string(1)]
		cursor = slot.get_end()
	return text + template.substr(cursor)
