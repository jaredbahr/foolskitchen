class_name RegularCast
extends RefCounted
## Stable regular identities and a deterministic visit calendar. Anonymous
## cohorts learn without drawing. The supplied RNG is requested only when an
## actual promotion is possible, then used only for identity and visit dates.

const DEFAULT_TUNING: RegularsTuning = preload("res://data/regulars/cast.tres")
const MAX_CANDIDATES: int = 128

class Candidate extends RefCounted:
	var repeat_key: String = ""
	var satisfied_days: int = 0
	var last_day: int = 0
	var history: RegularProfile = RegularProfile.new()

var tuning: RegularsTuning
var profiles: Array[RegularProfile] = []
var visited_today: Array[int] = []
var new_today: Array[int] = []
var left_today: Array[int] = []
var day: int = 1
var _candidates: Dictionary[String, Candidate] = {}


func _init(value: RegularsTuning = null) -> void:
	tuning = value if value != null else DEFAULT_TUNING


func begin_day(value: int) -> void:
	day = maxi(value, 1)
	visited_today.clear()
	new_today.clear()
	left_today.clear()


func get_profile(id: int) -> RegularProfile:
	for profile: RegularProfile in profiles:
		if profile.id == id:
			return profile
	return null


func for_repeat_key(repeat_key: String) -> RegularProfile:
	for profile: RegularProfile in profiles:
		if profile.repeat_key == repeat_key:
			return profile
	return null


func active_count() -> int:
	var count: int = 0
	for profile: RegularProfile in profiles:
		if profile.active:
			count += 1
	return count


## Only satisfied Regular-type guests teach the anonymous cohort. The caller
## supplies a deterministic repeat key; no identity draw is needed beforehand.
## The transient provider is deliberately not retained (no owner reference cycle).
func observe_visit(repeat_key: String, type_id: StringName, visit_day: int,
		stars: float, vibe: float, recipe_id: StringName, seat: Vector2i,
		quality: float, satisfied: bool, random_provider: Callable = Callable()) -> RegularProfile:
	if tuning == null or not tuning.is_valid() or repeat_key.is_empty() \
			or type_id != &"regular" or not satisfied or recipe_id.is_empty() \
			or not is_finite(quality) or quality < tuning.good_quality or visit_day < 1 \
			or for_repeat_key(repeat_key) != null:
		return null
	if not _candidates.has(repeat_key):
		if _candidates.size() >= MAX_CANDIDATES:
			return null
		var candidate: Candidate = Candidate.new()
		candidate.repeat_key = repeat_key
		_candidates[repeat_key] = candidate
	var candidate: Candidate = _candidates[repeat_key]
	candidate.history.learn([recipe_id] as Array[StringName], seat)
	if candidate.last_day != visit_day:
		candidate.satisfied_days += 1
		candidate.last_day = visit_day
	if not can_promote(repeat_key, visit_day, stars, vibe) or not random_provider.is_valid():
		return null
	var random: RandomNumberGenerator = random_provider.call() as RandomNumberGenerator
	if random == null:
		return null
	return _promote(candidate, visit_day, random)


func can_promote(repeat_key: String, visit_day: int, stars: float, vibe: float) -> bool:
	if tuning == null or not tuning.is_valid() or profiles.size() >= tuning.cast_cap \
			or for_repeat_key(repeat_key) != null or not _candidates.has(repeat_key) \
			or visit_day < tuning.min_day or not is_finite(stars) or stars < tuning.min_stars \
			or not is_finite(vibe) or vibe < tuning.min_vibe:
		return false
	return _candidates[repeat_key].satisfied_days >= tuning.min_satisfied_visits


func _promote(candidate: Candidate, visit_day: int, random: RandomNumberGenerator) -> RegularProfile:
	var available: PackedStringArray = []
	for name_text: String in tuning.names:
		var used: bool = false
		for existing: RegularProfile in profiles:
			if existing.display_name == name_text:
				used = true
				break
		if not used:
			available.append(name_text)
	if available.is_empty():
		return null
	var profile: RegularProfile = candidate.history
	profile.id = profiles.size() + 1
	profile.repeat_key = candidate.repeat_key
	profile.display_name = available[random.randi_range(0, available.size() - 1)]
	profile.model_id = tuning.model_ids[(profile.id - 1) % tuning.model_ids.size()]
	profile.tint_id = tuning.tint_ids[random.randi_range(0, tuning.tint_ids.size() - 1)]
	profile.greeting = tuning.greetings[random.randi_range(0, tuning.greetings.size() - 1)]
	profile.mood = tuning.initial_mood
	profile.visits = candidate.satisfied_days
	profile.last_visit_day = visit_day
	profile.next_visit_day = visit_day + random.randi_range(tuning.visit_days_min, tuning.visit_days_max)
	profiles.append(profile)
	new_today.append(profile.id)
	_candidates.erase(candidate.repeat_key)
	return profile


## Earliest overdue regular replaces an ordinary arrival; ties use stable id.
## Merely asking who is due never draws or changes a schedule.
func due_regular(visit_day: int) -> RegularProfile:
	var due: RegularProfile = null
	for profile: RegularProfile in profiles:
		if not profile.active or profile.next_visit_day > visit_day \
				or profile.last_visit_day >= visit_day:
			continue
		if due == null or profile.next_visit_day < due.next_visit_day \
				or (profile.next_visit_day == due.next_visit_day and profile.id < due.id):
			due = profile
	return due


func mark_arrived(profile: RegularProfile, visit_day: int, random: RandomNumberGenerator) -> bool:
	if profile == null or not profiles.has(profile) or not profile.active \
			or profile.last_visit_day >= visit_day or profile.next_visit_day > visit_day \
			or random == null or not tuning.is_valid():
		return false
	profile.last_visit_day = visit_day
	profile.next_visit_day = visit_day + random.randi_range(tuning.visit_days_min, tuning.visit_days_max)
	profile.visits += 1
	if not visited_today.has(profile.id):
		visited_today.append(profile.id)
	return true


## One departure per visit. The caller owns that lifecycle guard, as it does
## reviews and payments. Only enjoyed meals teach favourites.
func finish_visit(profile: RegularProfile, _visit_day: int,
		recipe_ids: Array[StringName], seat: Vector2i, served: bool,
		quality: float, wait_fraction: float, favourite_available: bool) -> void:
	if profile == null or not profiles.has(profile) or not profile.active \
			or not is_finite(quality) or not is_finite(wait_fraction):
		return
	var good: bool = served and quality >= tuning.good_quality \
		and wait_fraction < tuning.long_wait_fraction
	if good:
		profile.learn(recipe_ids, seat)
		profile.mood += tuning.good_visit_gain
	else:
		profile.mood -= tuning.bad_visit_loss
	if favourite_available:
		profile.missing_visits = 0
	else:
		profile.missing_visits += 1
		if profile.missing_visits >= tuning.missing_penalty_after:
			profile.mood -= tuning.missing_favourite_loss
	profile.mood = clampf(profile.mood, 0.0, 1.0)
	if profile.mood < tuning.leave_below:
		profile.active = false
		if not left_today.has(profile.id):
			left_today.append(profile.id)


func menu_happiness(profile: RegularProfile, favourite_available: bool) -> float:
	return tuning.favourite_happiness if profile != null and profile.active and favourite_available else 0.0


func tip_rate(profile: RegularProfile, favourite_available: bool) -> float:
	if profile == null or not profile.active:
		return 0.0
	return tuning.base_tip_rate + (tuning.favourite_tip_rate if favourite_available else 0.0)


func favourite_on_menu(recipe_id: StringName) -> bool:
	for profile: RegularProfile in profiles:
		if profile.active and profile.favourite_dish == recipe_id:
			return true
	return false


func to_dict() -> Dictionary:
	var rows: Array[Dictionary] = []
	for profile: RegularProfile in profiles:
		rows.append(profile.to_dict())
	var candidates: Array[Dictionary] = []
	for candidate: Candidate in _candidates.values():
		var history: Dictionary = candidate.history.to_dict()
		candidates.append({"key": candidate.repeat_key, "days": candidate.satisfied_days,
			"last_day": candidate.last_day, "dishes": history["dishes"], "seats": history["seats"],
			"favourite_dish": history["favourite_dish"], "favourite_seat": history["favourite_seat"]})
	return {"version": 1, "profiles": rows, "candidates": candidates}


## Missing old-save section is represented by {}. Restore validates into local
## objects first, so a corrupt section cannot partially replace the live cast.
func from_dict(data: Dictionary) -> bool:
	if data.is_empty():
		profiles.clear()
		_candidates.clear()
		begin_day(day)
		return true
	if not RegularProfile._whole(data.get("version"), 1) or int(data["version"]) != 1 \
			or not data.get("profiles") is Array or not data.get("candidates") is Array \
			or data["profiles"].size() > tuning.cast_cap or data["candidates"].size() > MAX_CANDIDATES:
		return false
	var restored: Array[RegularProfile] = []
	var keys: Dictionary[String, bool] = {}
	var names: Dictionary[String, bool] = {}
	for value: Variant in data["profiles"]:
		if not value is Dictionary:
			return false
		var profile: RegularProfile = RegularProfile.from_dict(value, tuning)
		if profile == null or profile.id != restored.size() + 1 \
				or keys.has(profile.repeat_key) or names.has(profile.display_name):
			return false
		keys[profile.repeat_key] = true
		names[profile.display_name] = true
		restored.append(profile)
	var candidates: Dictionary[String, Candidate] = {}
	for value: Variant in data["candidates"]:
		if not value is Dictionary or not value.get("key") is String \
				or (value["key"] as String).is_empty() or keys.has(value["key"]) \
				or candidates.has(value["key"]) or not RegularProfile._whole(value.get("days"), 1) \
				or not RegularProfile._whole(value.get("last_day"), 1):
			return false
		var history: RegularProfile = RegularProfile.history_from_dict(value)
		if history == null:
			return false
		var candidate: Candidate = Candidate.new()
		candidate.repeat_key = value["key"]
		candidate.satisfied_days = int(value["days"])
		candidate.last_day = int(value["last_day"])
		candidate.history = history
		candidates[candidate.repeat_key] = candidate
	profiles = restored
	_candidates = candidates
	begin_day(day)
	return true
