class_name FoodCritic
extends RefCounted
## The disguised food critic (#303). On a rare day a critic comes in looking
## like an ordinary guest, with a few tells a sharp player can spot. Their
## review weighs as several ordinary ones.
##
## All choices come from the named stream GameState.rng(&"critic"), handed in
## as a provider and called only once a critic can appear (career tier reached
## and out of cooldown). Shops that cannot have one never create the stream, so
## their saved streams are unchanged. The plan for the day is drawn in the
## morning and saved with it, so a reload neither redraws nor forgets the
## cooldown. Pure sim: no nodes, no scene tree.

const SAVE_VERSION: int = 1
const NOTEBOOK: StringName = &"notebook"
const PRICIEST: StringName = &"priciest"
const ODD_HOUR: StringName = &"odd_hour"
const LINGERS: StringName = &"lingers"
const TELLS: Array[StringName] = [NOTEBOOK, PRICIEST, ODD_HOUR, LINGERS]

## The last day a critic was due (0 = never): the cooldown counts from it.
var last_visit_day: int = 0
## The day the plan below was rolled for (0 = none yet); a day is rolled once.
var rolled_day: int = 0
## True on a day a critic is due and has not arrived yet.
var pending: bool = false
## Today's tells and arrival, while one is due or has arrived.
var tells: Array[StringName] = []
var arrival_permille: int = 0
var arrived: bool = false
var tuning: CriticTuning


func _init(config: CriticTuning = null) -> void:
	tuning = config if config != null else CriticTuning.new()


## Whether a critic could be due on `day` at this career tier (no draw).
func can_visit(day: int, career_tier: int) -> bool:
	return tuning.is_valid() and career_tier >= tuning.unlock_tier \
		and (last_visit_day == 0 or day - last_visit_day >= tuning.cooldown_days)


## Rolls the day once, in the morning. `random_provider` returns the named
## stream and is called only when a critic can appear. Idempotent per day.
func plan_day(day: int, career_tier: int, random_provider: Callable) -> void:
	# A morning save from before the tier gate may contain a pending visit.
	# Discard that plan below the gate while keeping the existing cooldown.
	if career_tier < tuning.unlock_tier:
		pending = false
		arrived = false
		tells.clear()
		arrival_permille = 0
		if rolled_day == day:
			rolled_day = 0
		return
	if rolled_day == day:
		return
	pending = false
	arrived = false
	tells = []
	# Nothing is marked rolled unless the stream was really used, so an early
	# call (before the session installed the provider) does not mark it rolled.
	if not can_visit(day, career_tier) or not random_provider.is_valid():
		return
	var random: RandomNumberGenerator = random_provider.call() as RandomNumberGenerator
	if random == null:
		return
	rolled_day = day
	if random.randf() >= tuning.daily_chance:
		return
	var pool: Array[StringName] = TELLS.duplicate()
	var chosen: Array[StringName] = []
	for _slot: int in mini(tuning.tell_count, pool.size()):
		chosen.append(pool.pop_at(random.randi_range(0, pool.size() - 1)))
	var window: Vector2i = tuning.normal_arrival_permille
	if chosen.has(ODD_HOUR):
		window = tuning.early_arrival_permille if random.randi_range(0, 1) == 0 \
			else tuning.late_arrival_permille
	tells = chosen
	arrival_permille = random.randi_range(window.x, window.y)
	pending = true


## True when the next lone arrival should be the critic.
func due(open_ticks_done: int, open_ticks: int) -> bool:
	return pending and not arrived and open_ticks > 0 \
		and open_ticks_done * 1000 >= arrival_permille * open_ticks


func has_tell(tell: StringName) -> bool:
	return tells.has(tell)


## Marks the critic as arrived (no longer due today). The cooldown starts
## here: a day on which no fitting arrival came costs nothing.
func mark_arrived(day: int) -> void:
	arrived = true
	pending = false
	last_visit_day = day


# --- Wording (player-facing; the word "critic" never appears while they sit) ---

## One plain line per visible tell. The "priciest" tell shows once they order.
static func tell_lines(tell_ids: Array[StringName], has_ordered: bool) -> Array[String]:
	var lines: Array[String] = []
	for tell: StringName in tell_ids:
		match tell:
			NOTEBOOK:
				lines.append("Scribbling in a little notebook")
			PRICIEST:
				if has_ordered:
					lines.append("Ordered the most expensive dish")
			ODD_HOUR:
				lines.append("Dining alone at an odd hour")
			LINGERS:
				lines.append("Taking their time over every bite")
	return lines


## A short verdict word for the evening report.
static func verdict_word(stars: int) -> String:
	match clampi(stars, 1, 5):
		5:
			return "A rave review"
		4:
			return "Warm praise"
		3:
			return "A mixed verdict"
		2:
			return "Unimpressed"
	return "A scathing review"


## The report line for the day: the heading, verdict and quote.
static func report_lines(result: Dictionary) -> Array[String]:
	if result.is_empty():
		return []
	var lines: Array[String] = ["A food critic visited today"]
	var stars: int = int(result.get("stars", 0))
	lines.append("%s (%d %s)" % [verdict_word(stars), stars, "star" if stars == 1 else "stars"])
	var quote: String = String(result.get("quote", ""))
	if not quote.is_empty():
		lines.append("\"%s\"" % quote)
	return lines


# --- Saving --------------------------------------------------------------------

func to_dict() -> Dictionary:
	var tell_names: Array[String] = []
	for tell: StringName in tells:
		tell_names.append(String(tell))
	return {"version": SAVE_VERSION, "last_visit_day": last_visit_day, "rolled_day": rolled_day,
		"pending": pending, "tells": tell_names, "arrival_permille": arrival_permille}


## Validates fully before changing anything; false leaves the critic as it was.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if row.size() != 6 or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("last_visit_day"), 0, 1000000000) \
			or not _whole(row.get("rolled_day"), 0, 1000000000) \
			or not _whole(row.get("arrival_permille"), 0, 1000) \
			or not row.get("pending") is bool or not row.get("tells") is Array:
		return false
	var restored: Array[StringName] = []
	for item: Variant in row["tells"]:
		if not item is String or not TELLS.has(StringName(item)) or restored.has(StringName(item)):
			return false
		restored.append(StringName(item))
	last_visit_day = int(row["last_visit_day"])
	rolled_day = int(row["rolled_day"])
	arrival_permille = int(row["arrival_permille"])
	pending = bool(row["pending"]) and not restored.is_empty()
	tells = restored
	arrived = false
	return true


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
