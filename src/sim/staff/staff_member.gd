class_name StaffMember
extends Resource
## A saved employee or candidate. Runtime agents receive their own copy.

## Floor roles: each becomes a worker in the restaurant and is drawn in every
## candidate pool. Kept as is so candidate draws below Tier 3 never change.
const ROLES: Array[StringName] = [&"cook", &"server", &"cleaner"]
const MAX_WORK_COUNT: int = 9007199254740991
## One mapping owns both task grouping and player-facing words; everything else
## is Other. Served and washed count plates, so one batched trip can add several.
const WORK_GROUPS: Array[Dictionary] = [
	{"kind": &"cook", "key": "cooked", "label": "cooked"},
	{"kind": &"take_order", "key": "orders", "singular": "order taken", "label": "orders taken"},
	{"kind": &"deliver", "key": "served", "label": "served"},
	{"kind": &"bus_table", "key": "cleared", "label": "cleared"},
	{"kind": &"wash", "key": "washed", "label": "washed"},
	{"kind": &"", "key": "other", "label": "other"},
]
## A Manager (FK-087, D24) runs a site while the owner is at another. They do
## no floor work (no worker in the world; their wage is still paid at close)
## and join candidate pools only from the manager hiring tier.
const MANAGER: StringName = &"manager"

@export var id: StringName = &""
@export var display_name: String = ""
@export var role: StringName = &"cook"
@export_range(1, 5) var skill: int = 3
@export var wage: int = 0
@export var trait_id: StringName = &"steady"
## Runtime progression is saved inside this member's staff-section row. It is
## not exported into authored starter resources.
var growth: StaffGrowth = null
## Runtime choices join this member's existing staff-section record.
var _job_priorities: StaffJobPriorities = null
var _work_today: Dictionary[String, int] = {}
var _work_total: Dictionary[String, int] = {}


func copy() -> StaffMember:
	var member: StaffMember = StaffMember.new()
	member.id = id
	member.display_name = display_name
	member.role = role
	member.skill = skill
	member.wage = wage
	member.trait_id = trait_id
	if growth != null:
		member.growth = growth.copy()
	if _job_priorities != null:
		member._job_priorities = _job_priorities.copy()
	member._work_today = _work_today.duplicate()
	member._work_total = _work_total.duplicate()
	return member


## Old saves and authored candidates start with zero XP and a neutral mood.
func growth_state() -> StaffGrowth:
	if growth == null:
		growth = StaffGrowth.new(_primary_skill(role), skill, wage)
	return growth


## Authored candidates and older records use the exact current role defaults.
func priority_state() -> StaffJobPriorities:
	if _job_priorities == null:
		_job_priorities = StaffJobPriorities.new(role)
	return _job_priorities


## Called only through the roster's completed-task signal path. The board,
## not an XP success result, owns once-only completion.
func record_completed_work(kind: StringName, quantity: int = 1) -> void:
	if quantity <= 0:
		return
	var key: String = "other"
	for group: Dictionary in WORK_GROUPS:
		if kind == group["kind"]:
			key = String(group["key"])
			break
	_work_today[key] = _capped_add(int(_work_today.get(key, 0)), quantity)
	_work_total[key] = _capped_add(int(_work_total.get(key, 0)), quantity)


static func _capped_add(count: int, quantity: int) -> int:
	return MAX_WORK_COUNT if quantity >= MAX_WORK_COUNT - count else count + quantity


func clear_work_today() -> void:
	_work_today.clear()


func work_today() -> Dictionary:
	return _work_snapshot(_work_today)


func work_total() -> Dictionary:
	return _work_snapshot(_work_total)


func work_summary() -> String:
	return "Today: %s   Total: %s" % [_work_phrase(_work_today), _work_phrase(_work_total)]


static func _work_snapshot(counts: Dictionary[String, int]) -> Dictionary:
	var result: Dictionary = {}
	for group: Dictionary in WORK_GROUPS:
		var key: String = String(group["key"])
		result[key] = counts.get(key, 0)
	return result


static func _work_phrase(counts: Dictionary[String, int]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for group: Dictionary in WORK_GROUPS:
		var count: int = counts.get(String(group["key"]), 0)
		if count > 0:
			var words: String = String(group["label"])
			if count == 1:
				words = String(group.get("singular", words))
			parts.append("%d %s" % [count, words])
	return "0 tasks" if parts.is_empty() else " · ".join(parts)


func to_dict() -> Dictionary:
	return {"id": String(id), "name": display_name, "role": String(role),
		"skill": skill, "wage": wage, "trait": String(trait_id),
		"growth": growth_state().to_dict(), "priorities": priority_state().to_dict(),
		"work": work_total()}


static func from_dict(data: Variant, catalogue: StaffCatalogue) -> StaffMember:
	if not data is Dictionary or catalogue == null:
		return null
	var row: Dictionary = data
	if row.size() < 6 or row.size() > 9:
		return null
	for key: Variant in row:
		if not ["id", "name", "role", "skill", "wage", "trait", "growth", "priorities", "work"].has(key):
			return null
	for key: String in ["id", "name", "role", "trait"]:
		if not row.get(key) is String or String(row[key]).strip_edges().is_empty():
			return null
	if not _whole_number(row.get("skill"), 1, 5) or not _whole_number(row.get("wage"), 0, 1000000):
		return null
	var member: StaffMember = StaffMember.new()
	member.id = StringName(row["id"])
	member.display_name = row["name"]
	member.role = StringName(row["role"])
	member.skill = int(row["skill"])
	member.wage = int(row["wage"])
	member.trait_id = StringName(row["trait"])
	if not is_known_role(member.role) or catalogue.find_trait(member.trait_id) == null:
		return null
	var restored: StaffGrowth = StaffGrowth.new(_primary_skill(member.role), member.skill, member.wage)
	if row.has("growth"):
		if not restored.from_dict(row["growth"]) \
				or restored.skill_level(_primary_skill(member.role)) != member.skill \
				or restored.wage != member.wage:
			return null
	member.growth = restored
	var choices: StaffJobPriorities = StaffJobPriorities.new(member.role)
	if row.has("priorities") and not choices.from_dict(row["priorities"]):
		return null
	member._job_priorities = choices
	# Only lifetime work is saved. A morning load starts today's display empty.
	if row.has("work"):
		if not row["work"] is Dictionary:
			return null
		var counts: Dictionary = row["work"]
		var known: Array[String] = []
		for group: Dictionary in WORK_GROUPS:
			known.append(String(group["key"]))
		for key: Variant in counts:
			if not key is String or not known.has(key):
				return null
		# A group added after this save was written simply starts at zero.
		for key: String in known:
			if not _whole_number(counts.get(key, 0), 0, MAX_WORK_COUNT):
				return null
			member._work_total[key] = int(counts.get(key, 0))
	return member


## Every role a saved member may have: the floor roles and the manager.
static func is_known_role(staff_role: StringName) -> bool:
	return ROLES.has(staff_role) or staff_role == MANAGER


static func _primary_skill(staff_role: StringName) -> StringName:
	match staff_role:
		&"cook": return &"cooking"
		&"server", &"manager": return &"service"
		&"cleaner": return &"cleaning"
	return &""


static func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
