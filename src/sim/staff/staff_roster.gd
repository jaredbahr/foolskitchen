class_name StaffRoster
extends RefCounted
## Morning choices only. No world, books, RNG ownership or saving side effects.

const CAPACITY: int = 6
const CANDIDATE_COUNT: int = 3
const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")

var candidate_day: int = 0
var catalogue: StaffCatalogue
var _tuning: EconomyTuning
var _members: Array[StaffMember] = []
var _candidates: Array[StaffMember] = []


func _init(tuning: EconomyTuning = null, definitions: StaffCatalogue = CATALOGUE) -> void:
	_tuning = tuning if tuning != null else EconomyTuning.new()
	catalogue = definitions
	_members = catalogue.defaults(_tuning)


func members() -> Array[StaffMember]:
	return _copies(_members)


func candidates() -> Array[StaffMember]:
	return _copies(_candidates)


func total_wages() -> int:
	var total: int = 0
	for member: StaffMember in _members:
		total += member.wage
	return total


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
	return count > 1


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
		member.role = &"cook" if random.randi_range(0, 1) == 0 else &"server"
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
