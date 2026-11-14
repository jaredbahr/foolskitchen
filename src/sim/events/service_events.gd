class_name ServiceEvents
extends RefCounted
## Small choice cards during service (#495). Each open day draws one or two
## cards from data/events at fixed shop-clock minutes, keeps them clear of a
## rush, a booked party and the critic, and never repeats a card inside its
## cooldown. Every draw is seeded from the run's master seed, the day and the
## event id (a fresh RandomNumberGenerator each time), so no named stream is
## used up and the same run always meets the same cards with the same results.
## Pure sim: the session applies the chosen effects to the shop's systems.

const SAVE_VERSION: int = 1
const ROOT: String = "res://data/events"
const MAX_DAY: int = 1000000000
const NAME_KEYS: Array[String] = ["staff", "regular", "ingredient"]

var tuning: ServiceEventTuning
var definitions: Array[ServiceEventDef] = []
## Event id -> the last day its card was shown (the cooldown counts from it).
var last_shown: Dictionary[StringName, int] = {}
## The day `schedule` was drawn for (0 = none yet). A day is drawn once.
var day: int = 0
## Today's cards in clock order: {"id", "minute", "shown", "names", "staff_id",
## "staff_role", "ingredient_id"}.
var schedule: Array[Dictionary] = []
## The card on screen now ({} = none): a copy of its schedule entry.
var pending: Dictionary = {}
## Today's answered cards, for the evening report: {"title", "label", "result"}.
var answered: Array[Dictionary] = []
## A nudge to one later day's arrivals (the food blogger): day, percent and
## the site it happened at (the buzz is about that shop, not the owner's
## others). Applied as that day's arrival factor at opening, never as a
## demand factor, so it never shows up as curb appeal.
var boost_day: int = 0
var boost_percent: int = 0
var boost_site: String = ""


func _init(config: ServiceEventTuning = null, events: Array[ServiceEventDef] = []) -> void:
	tuning = config if config != null else ServiceEventTuning.new()
	definitions = events.duplicate()


## Loads every card in `root`, sorted by file name. Invalid cards are left out
## and named in `errors`.
static func load_definitions(errors: PackedStringArray, root: String = ROOT) -> Array[ServiceEventDef]:
	var result: Array[ServiceEventDef] = []
	if DirAccess.open(root) == null:
		errors.append("Cannot open %s" % root)
		return result
	var entries: PackedStringArray = ResourceLoader.list_directory(root)
	entries.sort()
	var seen: Dictionary[StringName, bool] = {}
	for entry: String in entries:
		if not entry.ends_with(".tres"):
			continue
		var resource: Resource = ResourceLoader.load(root.path_join(entry))
		var definition: ServiceEventDef = resource as ServiceEventDef
		if definition == null:
			errors.append("%s: expected ServiceEventDef" % entry)
			continue
		var problems: PackedStringArray = definition.errors()
		if seen.has(definition.id):
			problems.append("event %s: duplicate id" % definition.id)
		if not problems.is_empty():
			errors.append_array(problems)
			continue
		seen[definition.id] = true
		result.append(definition)
	return result


## One fresh generator per question, so draws never depend on each other.
static func random_for(master_seed: int, for_day: int, salt: String) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = hash("%d:service_events:%d:%s" % [master_seed, for_day, salt])
	return random


func definition(id: StringName) -> ServiceEventDef:
	for candidate: ServiceEventDef in definitions:
		if candidate.id == id:
			return candidate
	return null


## Whether `event` may come up on `for_day` given the session's facts:
## {"level": int, "tier": int, "staff": Array, "regulars": Array,
## "rain": bool, "ingredients": Array}.
func can_show(event: ServiceEventDef, for_day: int, context: Dictionary) -> bool:
	if event == null or int(context.get("level", 1)) < event.min_level \
			or int(context.get("tier", 1)) < event.min_tier:
		return false
	if last_shown.has(event.id) and for_day - last_shown[event.id] < event.cooldown_days:
		return false
	for need: StringName in event.requires:
		match need:
			&"staff":
				if (context.get("staff", []) as Array).is_empty():
					return false
			&"regulars":
				if (context.get("regulars", []) as Array).is_empty():
					return false
			&"rain":
				if not bool(context.get("rain", false)):
					return false
			&"ingredient":
				if (context.get("ingredients", []) as Array).is_empty():
					return false
	return true


## A new morning forgets yesterday's cards; cooldowns and a boost stay.
func begin_morning(for_day: int) -> void:
	if day == for_day:
		return
	schedule.clear()
	pending.clear()
	answered.clear()
	if boost_day > 0 and boost_day < for_day:
		boost_day = 0
		boost_percent = 0
		boost_site = ""


## Draws today's cards once, at opening. `blocked` holds [from, to] shop-clock
## minute windows already taken (a rush, a booking, the critic). Returns the
## schedule; a day already drawn returns the same one without drawing again.
func plan_day(for_day: int, master_seed: int, context: Dictionary, open_minute: int,
		close_minute: int, blocked: Array[Vector2i] = []) -> Array[Dictionary]:
	if for_day < 1 or for_day > MAX_DAY or day == for_day or not tuning.is_valid():
		return schedule.duplicate(true)
	day = for_day
	schedule.clear()
	pending.clear()
	answered.clear()
	var pool: Array[ServiceEventDef] = []
	for event: ServiceEventDef in definitions:
		if can_show(event, for_day, context):
			pool.append(event)
	var first: int = open_minute + tuning.opening_margin_minutes
	var last: int = close_minute - tuning.closing_margin_minutes
	var minutes: Array[int] = []
	var start: int = ceili(float(first) / tuning.step_minutes) * tuning.step_minutes
	for minute: int in range(start, last + 1, tuning.step_minutes):
		if not _blocked(minute, blocked):
			minutes.append(minute)
	if pool.is_empty() or minutes.is_empty() or tuning.max_per_day == 0:
		return []
	var random: RandomNumberGenerator = random_for(master_seed, for_day, "plan")
	var count: int = tuning.min_per_day
	if count < tuning.max_per_day and random.randi_range(0, 99) < tuning.second_card_percent:
		count += 1
	count = mini(maxi(count, 1), pool.size())
	var chosen_minutes: Array[int] = _pick_minutes(minutes, count, first, last, random)
	for minute: int in chosen_minutes:
		var event: ServiceEventDef = _pick_event(pool, random)
		pool.erase(event)
		schedule.append(_entry(event, minute, master_seed, for_day, context))
	return schedule.duplicate(true)


## The next card due at `minute` (shop clock), or {} when none is due or one
## is already on screen. Showing a card starts its cooldown.
func due(minute: int) -> Dictionary:
	if not pending.is_empty():
		return {}
	for entry: Dictionary in schedule:
		if bool(entry["shown"]) or int(entry["minute"]) > minute:
			continue
		entry["shown"] = true
		last_shown[StringName(entry["id"])] = day
		pending = entry.duplicate(true)
		return pending.duplicate(true)
	return {}


## The pending card's text with its names filled in.
func card_text(entry: Dictionary) -> Dictionary:
	var event: ServiceEventDef = definition(StringName(entry.get("id", "")))
	if event == null:
		return {}
	var names: Dictionary = entry.get("names", {})
	var labels: Array[String] = []
	for choice: ServiceEventChoice in event.choices:
		labels.append(choice.label.format(names))
	return {"title": event.title.format(names), "text": event.text.format(names),
		"icon": event.icon, "labels": labels}


## Whether choice `index` of `id` lands on its risk today. Seeded only by the
## run, the day, the event and the choice.
static func risk_hit(choice: ServiceEventChoice, master_seed: int, for_day: int, id: StringName, index: int) -> bool:
	if choice == null or choice.risk_percent <= 0:
		return false
	var random: RandomNumberGenerator = random_for(master_seed, for_day, "%s:risk:%d" % [id, index])
	return random.randi_range(0, 99) < choice.risk_percent


## Answers the pending card at `site` (where a nudge to tomorrow lands).
## Returns {"id", "index", "choice", "risk", "result", "title", "label",
## "entry"} for the session to apply, or {} when nothing is pending or the
## index is out of range. The session checks the choice is affordable first.
func pick(index: int, master_seed: int, site: String = "") -> Dictionary:
	if pending.is_empty():
		return {}
	var event: ServiceEventDef = definition(StringName(pending["id"]))
	if event == null or index < 0 or index >= event.choices.size():
		return {}
	var choice: ServiceEventChoice = event.choices[index]
	var names: Dictionary = pending.get("names", {})
	var risk: bool = risk_hit(choice, master_seed, day, event.id, index)
	var result: String = (choice.risk_result if risk else choice.result).format(names)
	var outcome: Dictionary = {"id": event.id, "index": index, "choice": choice, "risk": risk,
		"result": result, "title": event.title.format(names), "label": choice.label.format(names),
		"entry": pending.duplicate(true)}
	answered.append({"title": outcome["title"], "label": outcome["label"], "result": result})
	if choice.tomorrow_arrivals_percent != 0:
		boost_day = day + 1
		boost_percent = choice.tomorrow_arrivals_percent
		boost_site = site
	pending.clear()
	return outcome


## Closing drops a card nobody answered (only possible when ticks run without
## the clock, as tools and tests do): it has no effect.
func end_service() -> void:
	pending.clear()
	for entry: Dictionary in schedule:
		entry["shown"] = true


## The blogger's nudge to `for_day`'s arrivals at `site`; 1.0 elsewhere.
func arrival_factor(for_day: int, site: String = "") -> float:
	return 1.0 + float(boost_percent) / 100.0 \
		if boost_day > 0 and boost_day == for_day and boost_site == site else 1.0


## One line per answered card, already player-facing.
func report_lines() -> Array[String]:
	var lines: Array[String] = []
	for row: Dictionary in answered:
		lines.append("%s: %s. %s" % [row["title"], row["label"], row["result"]])
	return lines


func to_dict() -> Dictionary:
	var shown: Dictionary = {}
	for id: StringName in last_shown:
		shown[String(id)] = last_shown[id]
	var rows: Array = []
	for entry: Dictionary in schedule:
		rows.append(entry.duplicate(true))
	return {"version": SAVE_VERSION, "last_shown": shown, "day": day, "schedule": rows,
		"boost_day": boost_day, "boost_percent": boost_percent, "boost_site": boost_site}


## Validates everything before replacing live state. A card on screen is never
## saved (saves happen in the morning), so a loaded game has none pending.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) or not _whole(row.get("day"), 0, MAX_DAY) \
			or not row.get("last_shown") is Dictionary or not row.get("schedule") is Array \
			or not _whole(row.get("boost_day"), 0, MAX_DAY + 1) or not _whole(row.get("boost_percent"), -20, 20) \
			or not row.get("boost_site", "") is String or String(row.get("boost_site", "")).length() > 40:
		return false
	var shown: Dictionary[StringName, int] = {}
	var saved_shown: Dictionary = row["last_shown"]
	for key: Variant in saved_shown:
		if not key is String or String(key).is_empty() or String(key).length() > 40 \
				or not _whole(saved_shown[key], 1, MAX_DAY):
			return false
		shown[StringName(key)] = int(saved_shown[key])
	var rows: Array[Dictionary] = []
	for entry: Variant in row["schedule"]:
		if not entry is Dictionary:
			return false
		var item: Dictionary = entry
		if not item.get("id") is String or not _whole(item.get("minute"), 0, 1440) \
				or not item.get("shown") is bool or not item.get("names") is Dictionary:
			return false
		var clean: Dictionary = {"id": String(item["id"]), "minute": int(item["minute"]),
			"shown": bool(item["shown"]), "names": {},
			"staff_id": String(item.get("staff_id", "")), "staff_role": String(item.get("staff_role", "")),
			"ingredient_id": String(item.get("ingredient_id", ""))}
		var names: Dictionary = item["names"]
		for key: Variant in names:
			if not NAME_KEYS.has(key) or not names[key] is String or String(names[key]).length() > 40:
				return false
			clean["names"][key] = names[key]
		rows.append(clean)
	if rows.size() > 3:
		return false
	last_shown = shown
	day = int(row["day"])
	schedule = rows
	pending = {}
	answered = []
	boost_day = int(row["boost_day"])
	boost_percent = int(row["boost_percent"])
	boost_site = String(row.get("boost_site", ""))
	return true


func _blocked(minute: int, blocked: Array[Vector2i]) -> bool:
	for window: Vector2i in blocked:
		if minute >= window.x - tuning.clear_minutes and minute <= window.y + tuning.clear_minutes:
			return true
	return false


## One card: anywhere in the window. Two: one in each half, far enough apart;
## when the halves cannot hold them apart, the day keeps one card.
func _pick_minutes(minutes: Array[int], count: int, first: int, last: int,
		random: RandomNumberGenerator) -> Array[int]:
	if count <= 1:
		return [minutes[random.randi_range(0, minutes.size() - 1)]]
	var picked: Array[int] = []
	var span: float = float(last - first) / float(count)
	for part: int in count:
		var low: float = first + span * part
		var high: float = first + span * (part + 1)
		var options: Array[int] = []
		for minute: int in minutes:
			if minute >= low and (minute < high or part == count - 1 and minute <= high) \
					and (picked.is_empty() or minute - picked.back() >= tuning.min_gap_minutes):
				options.append(minute)
		if options.is_empty():
			continue
		picked.append(options[random.randi_range(0, options.size() - 1)])
	if picked.is_empty():
		picked.append(minutes[random.randi_range(0, minutes.size() - 1)])
	return picked


func _pick_event(pool: Array[ServiceEventDef], random: RandomNumberGenerator) -> ServiceEventDef:
	var total: int = 0
	for event: ServiceEventDef in pool:
		total += event.weight
	var ticket: int = random.randi_range(0, total - 1)
	for event: ServiceEventDef in pool:
		ticket -= event.weight
		if ticket < 0:
			return event
	return pool.back()


## Fills in who and what the card is about, drawn from the event's own seed.
func _entry(event: ServiceEventDef, minute: int, master_seed: int, for_day: int,
		context: Dictionary) -> Dictionary:
	var random: RandomNumberGenerator = random_for(master_seed, for_day, "%s:names" % event.id)
	var entry: Dictionary = {"id": String(event.id), "minute": minute, "shown": false, "names": {},
		"staff_id": "", "staff_role": "", "ingredient_id": ""}
	if event.requires.has(&"staff"):
		var staff: Array = context.get("staff", [])
		var person: Dictionary = staff[random.randi_range(0, staff.size() - 1)]
		entry["names"]["staff"] = String(person.get("name", "Your cook"))
		entry["staff_id"] = String(person.get("id", ""))
		entry["staff_role"] = String(person.get("role", ""))
	if event.requires.has(&"regulars"):
		var regulars: Array = context.get("regulars", [])
		entry["names"]["regular"] = String(regulars[random.randi_range(0, regulars.size() - 1)])
	if event.requires.has(&"ingredient"):
		var ingredients: Array = context.get("ingredients", [])
		var ingredient: Dictionary = ingredients[random.randi_range(0, ingredients.size() - 1)]
		entry["names"]["ingredient"] = String(ingredient.get("name", "stock")).to_lower()
		entry["ingredient_id"] = String(ingredient.get("id", ""))
	return entry


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floorf(number) == number
