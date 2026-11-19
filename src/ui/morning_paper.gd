class_name MorningPaper
extends RefCounted
## Builds display copy from known facts and the caller's paper stream.

const MASTHEAD: String = "The Daily Ladle"
const HEADLINES: MorningPaperHeadlines = preload("res://data/paper/headlines.tres")
const FALLBACK_HEADLINE: String = "The kitchen gets ready for another day"
const FALLBACK_DISH: String = "the menu"
const MAX_NOTES: int = 3
## Yesterday's tip shows once this many guests left for one reason.
const TIP_MIN_GUESTS: int = 3
## A "full house" headline needs at least this many guests served.
const FULL_HOUSE_MIN_SERVED: int = 8
## The staff advice rules the evening report uses, so the paper never blames
## a role the report does not.
const STAFF_ADVICE_RULES: StaffAdviceTuning = preload("res://data/balance/staff_advice.tres")
## Each tip is true in every difficulty: no advice to order stock (buying may
## be automatic), none about prices when the game sets them.
const TIPS: Dictionary[StringName, String] = {
	&"no_table": "%d guests found every seat taken. More tables, and hands to serve them, would fit them in.",
	&"waited_too_long": "%d guests gave up waiting. A waiting bench by the door and quicker service help them stay.",
	&"too_expensive": "%d guests left over the prices. A gentler price brings them back.",
	&"out_of_stock": "%d guests found a dish sold out. More shelves or another fridge let the morning order bring enough.",
}
## The waiting tip when yesterday's staff advice names a busy role.
const WAITING_ROLE_TIPS: Dictionary[StringName, String] = {
	&"cook": "%d guests gave up waiting while the cooks were flat out. Another cook would speed things up.",
	&"server": "%d guests gave up waiting while the servers were flat out. Another server would speed things up.",
}


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
	var filled: String = _fill(headline, fields)
	# A template that opens with {dish} still opens with a capital ("The menu ...").
	filled = filled.left(1).to_upper() + filled.substr(1)
	return {"masthead": MASTHEAD, "headline": filled,
		"notes": _briefs(yesterday, weather_kind, notes, dish, quirk_brief(day, yesterday))}


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
	# Good news leads: a new tier, then a level-up, outrank everyday results.
	if yesterday != null and not yesterday.career_tier_line.is_empty():
		return &"tier"
	if yesterday != null and not yesterday.inspection_lines.is_empty():
		return &"inspection"
	if yesterday != null and yesterday.owner_level_after > yesterday.owner_level_before:
		return &"level_up"
	if yesterday != null and not yesterday.record_lines.is_empty():
		return &"record"
	if yesterday != null and _new_regulars(yesterday):
		return &"regular"
	var cash: int = yesterday.profit() if yesterday != null else int(history.get("cash_change", 0))
	if cash < 0:
		return &"loss"
	var lost: int = yesterday.customers_lost if yesterday != null else int(history.get("lost", 0))
	if lost >= 3:
		# Mostly turned away for want of a seat: a busy shop, not a bad one.
		if yesterday != null and int(yesterday.leave_reasons.get(&"no_table", 0)) * 2 >= lost \
				and yesterday.customers_served >= FULL_HOUSE_MIN_SERVED:
			return &"full_house"
		return &"walkouts"
	if yesterday != null:
		for card: Dictionary in yesterday.review_cards:
			if int(card.get("stars", 0)) == 5:
				return &"review"
	return &"quiet"


## One line about yesterday's most-seen guest quirk, or "". The quirk is the
## most-seen (a tie goes to the lower quirk id) and the line is picked from the
## day number, so neither draws from any stream. Lines live in the paper's
## headline data as `brief_<quirk id>`.
static func quirk_brief(day: int, yesterday: DayReport) -> String:
	if yesterday == null:
		return ""
	var best: StringName = &""
	var best_count: int = 0
	for key: Variant in yesterday.quirk_counts:
		var id: StringName = StringName(str(key))
		var count: int = int(yesterday.quirk_counts[key])
		var lines: PackedStringArray = HEADLINES.groups.get(StringName("brief_%s" % id), PackedStringArray())
		if count <= 0 or lines.is_empty():
			continue
		if count > best_count or (count == best_count and String(id) < String(best)):
			best = id
			best_count = count
	if best.is_empty():
		return ""
	var group: PackedStringArray = HEADLINES.groups[StringName("brief_%s" % best)]
	return group[posmod(day, group.size())]


static func _briefs(yesterday: DayReport, weather_kind: int, notes: Array[String],
		dish: String = "", quirk_line: String = "") -> Array[String]:
	var available: Array[String] = []
	if weather_kind in [WeatherState.Kind.SUNNY, WeatherState.Kind.CLOUDY, WeatherState.Kind.RAIN]:
		available.append(WeatherText.forecast_for(weather_kind))
	if yesterday != null and not yesterday.inspection_lines.is_empty():
		available.append(yesterday.inspection_lines[0])
	available.append_array(notes)
	if not dish.is_empty():
		available.append("%s was yesterday’s favorite." % dish)
	# Lowest priority: it only fills a free slot, never pushes out another note.
	available.append(quirk_line)
	var briefs: Array[String] = []
	for line: String in available:
		var brief: String = line.strip_edges()
		if not brief.is_empty() and not briefs.has(brief):
			briefs.append(brief)
		if briefs.size() == MAX_NOTES:
			break
	return briefs


## One practical line about yesterday's biggest reason guests left, or "".
## The caller places it among the notes (#646: ahead of a booking note).
## `prices_automatic`: the game sets prices (Easy), so no price tip. A
## `hire_note` from this morning already answered a staffing gap, so the
## waiting tip then names no role.
static func tip_for(yesterday: DayReport, prices_automatic: bool = false, hire_note: String = "") -> String:
	if yesterday == null:
		return ""
	var best: StringName = &""
	var best_count: int = TIP_MIN_GUESTS - 1
	for reason: StringName in TIPS:
		if reason == &"too_expensive" and prices_automatic:
			continue
		var count: int = int(yesterday.leave_reasons.get(reason, 0))
		if count > best_count:
			best = reason
			best_count = count
	if best.is_empty():
		return ""
	if best == &"waited_too_long" and hire_note.strip_edges().is_empty():
		var role: StringName = STAFF_ADVICE_RULES.recommendation(yesterday.staff_activity, yesterday.leave_reasons)
		if WAITING_ROLE_TIPS.has(role):
			return WAITING_ROLE_TIPS[role] % best_count
	return TIPS[best] % best_count


static func _new_regulars(yesterday: DayReport) -> bool:
	for line: String in yesterday.regulars_lines:
		if line.begins_with("New regulars: "):
			return true
	return false


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
