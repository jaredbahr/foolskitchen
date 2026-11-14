class_name ServiceEventDef
extends Resource
## One service event card (#495), authored in data/events/*.tres. The text may
## name {staff}, {regular} or {ingredient}; the session fills them in when the
## card is shown (each needs the matching requirement below).

## What an event may need before it can be drawn. Keep in step with the
## session's flags (Main._service_event_context).
const REQUIREMENTS: Array[StringName] = [
	&"staff",       # a hired worker (not a manager) on today's team
	&"regulars",    # at least one named regular
	&"rain",        # today's weather is rain
	&"ingredient",  # today's menu uses a bought ingredient
]
const ICONS: Array[StringName] = [&"chef", &"stock", &"reputation", &"staff", &"music",
	&"warning", &"power", &"weather_rain", &"menu", &"paint", &"information"]

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var text: String = ""
## A role from IconCatalogue; "" shows no icon.
@export var icon: StringName = &""
@export var min_level: int = 1
@export var min_tier: int = 1
@export var requires: Array[StringName] = []
## Days before this card can come up again.
@export var cooldown_days: int = 3
## Relative chance among the cards that can come up today.
@export var weight: int = 10
@export var choices: Array[ServiceEventChoice] = []


func errors() -> PackedStringArray:
	var who: String = "event %s" % id
	var found: PackedStringArray = []
	var text_id: String = String(id)
	if text_id.is_empty() or text_id.length() > 40 or text_id != text_id.to_lower() or text_id.contains(" "):
		found.append("%s: the id must be 1-40 lower-case characters" % who)
	if title.strip_edges().is_empty() or title.length() > 40:
		found.append("%s: the title must be 1-40 characters" % who)
	if text.strip_edges().is_empty() or text.length() > 200:
		found.append("%s: the text must be 1-200 characters" % who)
	if not icon.is_empty() and not ICONS.has(icon):
		found.append("%s: unknown icon %s" % [who, icon])
	if min_level < 1 or min_level > 30 or min_tier < 1 or min_tier > 6:
		found.append("%s: level 1-30 and tier 1-6" % who)
	if cooldown_days < 1 or cooldown_days > 30 or weight < 1 or weight > 100:
		found.append("%s: cooldown 1-30 days and weight 1-100" % who)
	for need: StringName in requires:
		if not REQUIREMENTS.has(need):
			found.append("%s: unknown requirement %s" % [who, need])
	for name: String in ["staff", "regular", "ingredient"]:
		var need: StringName = &"regulars" if name == "regular" else StringName(name)
		var used: bool = text.contains("{%s}" % name)
		for choice: ServiceEventChoice in choices:
			if choice != null:
				used = used or choice.result.contains("{%s}" % name) or choice.risk_result.contains("{%s}" % name) \
					or choice.label.contains("{%s}" % name)
		if used and not requires.has(need):
			found.append("%s: {%s} needs the %s requirement" % [who, name, need])
	if choices.size() < 2 or choices.size() > 3:
		found.append("%s: an event has 2-3 choices" % who)
	for index: int in choices.size():
		var choice: ServiceEventChoice = choices[index]
		if choice == null:
			found.append("%s: choice %d is missing" % [who, index + 1])
			continue
		found.append_array(choice.errors("%s choice %d" % [who, index + 1]))
		if choice.staff_mood != 0 and not requires.has(&"staff"):
			found.append("%s: a mood change needs the staff requirement" % who)
		if choice.stock_units != 0 and not requires.has(&"ingredient"):
			found.append("%s: a stock change needs the ingredient requirement" % who)
	return found
