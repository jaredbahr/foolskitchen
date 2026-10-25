class_name StaffRoster
extends RefCounted
## Saved staffing choices. Hiring is morning-only; job priorities are immediate.
## No world, books, RNG ownership or saving side effects.

const CAPACITY: int = 6
const CANDIDATE_COUNT: int = 3
const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")
const GROWTH_TUNING: StaffGrowthTuning = preload("res://data/balance/staff_growth.tres")

var candidate_day: int = 0
var catalogue: StaffCatalogue
var _tuning: EconomyTuning
var _growth_tuning: StaffGrowthTuning
var _members: Array[StaffMember] = []
var _candidates: Array[StaffMember] = []


func _init(tuning: EconomyTuning = null, definitions: StaffCatalogue = CATALOGUE,
		growth_rules: StaffGrowthTuning = GROWTH_TUNING) -> void:
	_tuning = tuning if tuning != null else EconomyTuning.new()
	_growth_tuning = growth_rules if growth_rules != null else GROWTH_TUNING
	catalogue = definitions
	_members = catalogue.defaults(_tuning)
	# Authored templates are never a source of runtime XP. Catalogue.defaults
	# sets wages after copying, so initialize progression from the final wage.
	for member: StaffMember in _members:
		member.growth = StaffGrowth.new(StaffMember._primary_skill(member.role), member.skill, member.wage)


## Runtime command staging preserves today's unflushed XP. The morning save
## format deliberately omits that transient state, so to_dict/from_dict is not
## a runtime clone. Share the same authored policies, detach every person.
func copy() -> StaffRoster:
	var result: StaffRoster = StaffRoster.new(_tuning, catalogue, _growth_tuning)
	result.candidate_day = candidate_day
	result._members = _copies(_members)
	result._candidates = _copies(_candidates)
	return result


func members() -> Array[StaffMember]:
	return _copies(_members)


func candidates() -> Array[StaffMember]:
	return _copies(_candidates)


## Changes selection at the next pick, in any phase. The session also copies
## these choices onto the existing live employee without reinstalling staff.
func set_job_priority(member_id: StringName, job: StringName, value: int) -> bool:
	var index: int = _find(_members, member_id)
	return index >= 0 and _members[index].priority_state().set_priority(job, value)


## Detached command input for the live agent; a caller cannot edit the roster.
func job_priorities(member_id: StringName) -> StaffJobPriorities:
	var index: int = _find(_members, member_id)
	return _members[index].priority_state().copy() if index >= 0 else null


func total_wages() -> int:
	var total: int = 0
	for member: StaffMember in _members:
		total += member.wage
	return total


## Stage XP for an actual employee, never a candidate or the unsalaried owner.
## The session must call this once from a completed task's stable claimant ID.
func record_completed_task(member_id: StringName, kind: StringName) -> bool:
	var index: int = _find(_members, member_id)
	return index >= 0 and _members[index].growth_state().record_task(kind, _growth_tuning)


## Apply newly staged XP after service closes and before morning serialization
## (for any later completed cleanup). Empty repeats do nothing. Current-day
## wages are already owed; skills and raises affect the next shift.
func close_growth_day() -> Dictionary:
	var raised: Dictionary = {}
	for member: StaffMember in _members:
		var events: Array[Dictionary] = member.growth_state().close_day(_growth_tuning)
		member.skill = member.growth_state().skill_level(StaffMember._primary_skill(member.role))
		if not events.is_empty():
			raised[member.id] = events
	return raised


## Read-only choices for the morning UI. Repeated reads cannot enqueue or
## consume an offer. Call process_morning_quits first on each new morning.
func morning_raise_offers(day: int, phase: int) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if day < 1 or phase != SimClock.Phase.MORNING:
		return offers
	for member: StaffMember in _members:
		if member.growth_state().quit_due_day() > 0 and member.growth_state().quit_due_day() <= day:
			continue
		var offer: Dictionary = _raise_offer(member)
		if not offer.is_empty():
			offers.append(offer)
	return offers


## A choice changes this morning's roster wage, not yesterday's paid wages.
## Main will install the changed roster on live agents before service begins.
func accept_raise(member_id: StringName, phase: int) -> bool:
	if phase != SimClock.Phase.MORNING:
		return false
	var index: int = _find(_members, member_id)
	if index < 0:
		return false
	var member: StaffMember = _members[index]
	var offer: Dictionary = _raise_offer(member)
	if offer.is_empty() or not member.growth_state().accept_raise(int(offer["new_wage"])):
		return false
	member.wage = member.growth_state().wage
	return true


func decline_raise(member_id: StringName, day: int, phase: int) -> bool:
	if day < 1 or phase != SimClock.Phase.MORNING:
		return false
	var index: int = _find(_members, member_id)
	if index < 0:
		return false
	var offer: Dictionary = _raise_offer(_members[index])
	# A skill update whose earned wage is already covered is acknowledged,
	# never refused. Keep this guard even for direct calls outside the panel.
	if offer.is_empty() or not bool(offer["requires_raise"]):
		return false
	var member: StaffMember = _members[index]
	var protected_minimum: bool = [&"cook", &"server"].has(member.role) \
		and _role_count(member.role) <= 1
	return member.growth_state().decline_raise(day, protected_minimum)


## Settle due departures once, in roster order. A last cook or server must
## remain, with mood restored to 1. Notices contain player-ready sentences;
## member_id is only an internal handle for the caller's panel state.
func process_morning_quits(day: int, phase: int) -> Array[Dictionary]:
	var notices: Array[Dictionary] = []
	if day < 1 or phase != SimClock.Phase.MORNING:
		return notices
	for member: StaffMember in _members.duplicate():
		var growth_state: StaffGrowth = member.growth_state()
		if growth_state.quit_due_day() == 0 or day < growth_state.quit_due_day():
			continue
		var protected_minimum: bool = [&"cook", &"server"].has(member.role) \
			and _role_count(member.role) <= 1
		if growth_state.should_quit_this_morning(day, protected_minimum):
			_members.erase(member)
			notices.append({"member_id": member.id,
				"message": "%s left after their raise requests were refused." % member.display_name})
		elif protected_minimum:
			notices.append({"member_id": member.id,
				"message": "%s stayed to keep the %s running." % [member.display_name,
					"kitchen" if member.role == &"cook" else "floor"]})
	return notices


func _raise_offer(member: StaffMember) -> Dictionary:
	# A worker who has decided to leave cannot take a fourth choice before
	# their departure is settled the following morning.
	if member.growth_state().quit_due_day() > 0:
		return {}
	var pending: Dictionary = member.growth_state().pending_raise()
	if pending.is_empty():
		return {}
	var level: int = int(pending["level"])
	var proposed: int = maxi(member.wage, _tuning.staff_wage(member.role, level))
	var skill_name: String = _skill_name(StringName(pending["skill"]))
	var role_name: String = _role_name(member.role)
	var text: String = "%s (%s) got better at %s (skill %d). They'd like $%d/day instead of $%d." % [
		member.display_name, role_name, skill_name, level, proposed, member.wage]
	if proposed == member.wage:
		text = "%s (%s) got better at %s (skill %d). Their pay stays at $%d/day." % [
			member.display_name, role_name, skill_name, level, member.wage]
	return {"member_id": member.id, "message": text, "old_wage": member.wage,
		"new_wage": proposed, "skill": pending["skill"], "level": level,
		"requires_raise": proposed > member.wage}


func _role_count(staff_role: StringName) -> int:
	var count: int = 0
	for member: StaffMember in _members:
		if member.role == staff_role:
			count += 1
	return count


static func _role_name(staff_role: StringName) -> String:
	match staff_role:
		&"cook": return "Cook"
		&"server": return "Server"
		&"cleaner": return "Cleaner"
	return "Team member"


static func _skill_name(skill: StringName) -> String:
	match skill:
		&"cooking": return "cooking"
		&"service": return "service"
		&"cleaning": return "cleaning"
	return "their work"


func can_hire(id: StringName) -> bool:
	return _members.size() < CAPACITY and _find(_candidates, id) >= 0


func hire(id: StringName) -> bool:
	if not can_hire(id):
		return false
	var index: int = _find(_candidates, id)
	_members.append(_candidates[index])
	_candidates.remove_at(index)
	return true


func can_let_go(id: StringName) -> bool:
	var index: int = _find(_members, id)
	if index < 0:
		return false
	var count: int = 0
	for member: StaffMember in _members:
		if member.role == _members[index].role:
			count += 1
	return _members[index].role == &"cleaner" or count > 1


func let_go(id: StringName) -> bool:
	if not can_let_go(id):
		return false
	_members.remove_at(_find(_members, id))
	return true


## Same-morning loads and refreshes consume no random values, even after hires.
func draw_candidates(day: int, random: RandomNumberGenerator) -> bool:
	if day <= 0 or day < candidate_day or random == null:
		return false
	if candidate_day == day:
		return true
	if catalogue.traits.is_empty() or catalogue.candidate_names.is_empty():
		return false
	var used_names: Dictionary[String, bool] = {}
	for member: StaffMember in _members:
		used_names[member.display_name.strip_edges().to_lower()] = true
	var names: Array[String] = []
	for name: String in catalogue.candidate_names:
		var key: String = name.strip_edges().to_lower()
		if not key.is_empty() and not used_names.has(key):
			names.append(name)
			used_names[key] = true
	# Check the whole pool before consuming the hiring stream or changing state.
	if names.size() < CANDIDATE_COUNT:
		return false
	var next: Array[StaffMember] = []
	for index: int in range(CANDIDATE_COUNT):
		var member: StaffMember = StaffMember.new()
		member.id = StringName("candidate_%d_%d" % [day, index])
		while _find(_members, member.id) >= 0:
			member.id = StringName(String(member.id) + "_new")
		var name_index: int = random.randi_range(0, names.size() - 1)
		member.display_name = names[name_index]
		names.remove_at(name_index)
		member.role = StaffMember.ROLES[random.randi_range(0, StaffMember.ROLES.size() - 1)]
		member.skill = random.randi_range(1, 5)
		member.trait_id = catalogue.traits[random.randi_range(0, catalogue.traits.size() - 1)].id
		member.wage = _tuning.staff_wage(member.role, member.skill)
		next.append(member)
	_candidates = next
	candidate_day = day
	return true


func to_dict() -> Dictionary:
	var employees: Array[Dictionary] = []
	var available: Array[Dictionary] = []
	for member: StaffMember in _members:
		employees.append(member.to_dict())
	for member: StaffMember in _candidates:
		available.append(member.to_dict())
	return {"version": 1, "candidate_day": candidate_day, "members": employees, "candidates": available}


## Validate all records, IDs, role minimums and bounds before replacing choices.
func from_dict(data: Dictionary) -> bool:
	if data.size() != 4 or not StaffMember._whole_number(data.get("version"), 1, 1) \
			or not StaffMember._whole_number(data.get("candidate_day"), 0, 100000000):
		return false
	if not data.get("members") is Array or not data.get("candidates") is Array:
		return false
	var employees: Array = data["members"]
	var available: Array = data["candidates"]
	if employees.size() < 2 or employees.size() > CAPACITY or available.size() > CANDIDATE_COUNT:
		return false
	if int(data["candidate_day"]) == 0 and not available.is_empty():
		return false
	var seen: Dictionary[StringName, bool] = {}
	var next_members: Array[StaffMember] = []
	var next_candidates: Array[StaffMember] = []
	for records: Array in [employees, available]:
		for row: Variant in records:
			var member: StaffMember = StaffMember.from_dict(row, catalogue)
			if member == null or seen.has(member.id):
				return false
			seen[member.id] = true
			if records == employees:
				next_members.append(member)
			else:
				next_candidates.append(member)
	var roles: Array[StringName] = []
	for member: StaffMember in next_members:
		roles.append(member.role)
	if not roles.has(&"cook") or not roles.has(&"server"):
		return false
	_members = next_members
	_candidates = next_candidates
	candidate_day = int(data["candidate_day"])
	return true


static func _find(people: Array[StaffMember], id: StringName) -> int:
	for index: int in range(people.size()):
		if people[index].id == id:
			return index
	return -1


static func _copies(people: Array[StaffMember]) -> Array[StaffMember]:
	var result: Array[StaffMember] = []
	for member: StaffMember in people:
		result.append(member.copy())
	return result
