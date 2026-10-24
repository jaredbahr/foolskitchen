class_name StaffGrowth
extends RefCounted
## One person's XP, skills, raise decisions, and mood. Callers stage task XP
## during service and apply it at day close, with a final morning flush for
## any later completed cleanup. No world or save side effects.

const SKILLS: Array[StringName] = [&"cooking", &"service", &"cleaning"]
const MAX_XP: int = 1000000

var mood: int = 3
var wage: int = 0

var _skills: Dictionary[StringName, int] = {}
var _xp: Dictionary[StringName, int] = {}
var _earned_today: Dictionary[StringName, int] = {}
var _raises: Array[Dictionary] = []
var _quit_day: int = 0


func _init(primary_skill: StringName = &"service", starting_level: int = 3,
		starting_wage: int = 0) -> void:
	for skill: StringName in SKILLS:
		_skills[skill] = 1
		_xp[skill] = 0
		_earned_today[skill] = 0
	if SKILLS.has(primary_skill):
		_skills[primary_skill] = clampi(starting_level, 1, 5)
	wage = clampi(starting_wage, 0, 1000000)


## A detached UI/roster copy includes today's transient earnings, while the
## morning save snapshot omits them after the final close_day flush has run.
func copy() -> StaffGrowth:
	var result: StaffGrowth = StaffGrowth.new()
	if result.from_dict(to_dict()):
		result._earned_today = _earned_today.duplicate()
	return result


func skill_level(skill: StringName) -> int:
	return _skills.get(skill, 0)


func progress_xp(skill: StringName) -> int:
	return _xp.get(skill, 0)


func earned_today(skill: StringName) -> int:
	return _earned_today.get(skill, 0)


## Unknown task kinds cannot silently grant XP. The board's completed signal
## should call this only once per genuinely finished task.
func record_task(kind: StringName, tuning: StaffGrowthTuning) -> bool:
	if tuning == null or not tuning.is_valid():
		return false
	var skill: StringName = tuning.skill_for_task(kind)
	var amount: int = tuning.xp_for_task(kind)
	if not SKILLS.has(skill) or amount <= 0 or _earned_today[skill] > MAX_XP - amount:
		return false
	_earned_today[skill] += amount
	return true


## Returns detached skill-up events. Each level-up queues exactly one raise
## offer, including when several levels are earned in a single exceptional day.
func close_day(tuning: StaffGrowthTuning) -> Array[Dictionary]:
	var raised: Array[Dictionary] = []
	if tuning == null or not tuning.is_valid():
		return raised
	for skill: StringName in SKILLS:
		var gained: int = _earned_today[skill]
		_earned_today[skill] = 0
		_xp[skill] = mini(MAX_XP, _xp[skill] + gained)
		while _skills[skill] < 5 and _xp[skill] >= tuning.needed_for_next_level(_skills[skill]):
			_xp[skill] -= tuning.needed_for_next_level(_skills[skill])
			_skills[skill] += 1
			var event: Dictionary = {"skill": String(skill), "level": _skills[skill]}
			_raises.append(event.duplicate())
			raised.append(event)
		if _skills[skill] == 5:
			_xp[skill] = 0
	return raised


func pending_raise() -> Dictionary:
	return _raises[0].duplicate() if not _raises.is_empty() else {}


func pending_raise_count() -> int:
	return _raises.size()


func quit_due_day() -> int:
	return _quit_day


## The caller computes the proposed wage with EconomyTuning.staff_wage.
func accept_raise(proposed_wage: int) -> bool:
	if _raises.is_empty() or proposed_wage < wage or proposed_wage > 1000000:
		return false
	wage = proposed_wage
	_raises.pop_front()
	return true


## A refusal reduces mood once. Reaching zero schedules departure for the
## following morning, never during the current day's player choice.
func decline_raise(day: int) -> bool:
	if _raises.is_empty() or day < 1:
		return false
	_raises.pop_front()
	mood = maxi(0, mood - 1)
	if mood == 0:
		_quit_day = day + 1
	return true


## The roster caller supplies the cook/server minimum guard. A protected last
## worker stays on the team at mood 1 instead of quitting.
func should_quit_this_morning(day: int, protected_minimum: bool) -> bool:
	if _quit_day == 0 or day < _quit_day:
		return false
	_quit_day = 0
	if protected_minimum:
		mood = 1
		return false
	# The caller removes this person now. Keep even an interrupted caller from
	# saving an impossible mood-zero record with no scheduled departure.
	mood = 1
	return true


func to_dict() -> Dictionary:
	var skills: Dictionary = {}
	var xp: Dictionary = {}
	for skill: StringName in SKILLS:
		skills[String(skill)] = _skills[skill]
		xp[String(skill)] = _xp[skill]
	return {"version": 1, "skills": skills, "xp": xp, "mood": mood,
		"wage": wage, "raises": _raises.duplicate(true), "quit_day": _quit_day}


## Strict, atomic decoder for the morning staff section. In-progress daily XP
## is transient because morning setup flushes it before cloning and saving.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if data.size() != 7 or not _whole(data.get("version"), 1, 1) \
			or not _whole(data.get("mood"), 0, 3) or not _whole(data.get("wage"), 0, 1000000) \
			or not _whole(data.get("quit_day"), 0, 100000000) \
			or not data.get("skills") is Dictionary or not data.get("xp") is Dictionary \
			or not data.get("raises") is Array:
		return false
	# Normal decisions reach mood zero exactly when a next-morning departure is
	# scheduled. A malformed save must not dismiss a happy employee on load.
	if (int(data["mood"]) == 0) != (int(data["quit_day"]) > 0):
		return false
	var saved_skills: Dictionary = data["skills"]
	var saved_xp: Dictionary = data["xp"]
	var saved_raises: Array = data["raises"]
	if saved_skills.size() != SKILLS.size() or saved_xp.size() != SKILLS.size() \
			or saved_raises.size() > 12:
		return false
	var next_skills: Dictionary[StringName, int] = {}
	var next_xp: Dictionary[StringName, int] = {}
	for skill: StringName in SKILLS:
		var key: String = String(skill)
		if not _whole(saved_skills.get(key), 1, 5) or not _whole(saved_xp.get(key), 0, MAX_XP):
			return false
		next_skills[skill] = int(saved_skills[key])
		next_xp[skill] = int(saved_xp[key])
	var next_raises: Array[Dictionary] = []
	var seen_raises: Dictionary[String, bool] = {}
	for value_row: Variant in saved_raises:
		if not value_row is Dictionary:
			return false
		var row: Dictionary = value_row
		if row.size() != 2 or not row.get("skill") is String:
			return false
		var skill: StringName = StringName(row["skill"])
		if not SKILLS.has(skill) or not _whole(row.get("level"), 2, next_skills[skill]):
			return false
		var raise_key: String = "%s:%d" % [skill, int(row["level"])]
		if seen_raises.has(raise_key):
			return false
		seen_raises[raise_key] = true
		next_raises.append({"skill": String(skill), "level": int(row["level"])})
	_skills = next_skills
	_xp = next_xp
	_raises = next_raises
	mood = int(data["mood"])
	wage = int(data["wage"])
	_quit_day = int(data["quit_day"])
	for skill: StringName in SKILLS:
		_earned_today[skill] = 0
	return true


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
