class_name StaffActivity
extends RefCounted
## Day-local observations of time committed to existing staff tasks.
## Counters never own agents/tasks or change the world they observe.

const ROLES: Array[StringName] = [&"cook", &"server", &"cleaner", &"owner"]
const MAX_COUNT: int = 9007199254740991

var _day: int = 1
var _open_ticks: int = 0
var _roles: Dictionary = {}


func reset(day: int) -> void:
	_day = maxi(1, day)
	_open_ticks = 0
	_roles.clear()


## Sample at the beginning of an OPEN tick, before claims can finish or change.
## Travel and station waits count as busy while a valid job remains assigned.
func observe(world: SimWorld) -> void:
	if world == null or world.clock == null or world.clock.phase != SimClock.Phase.OPEN:
		return
	_open_ticks += 1
	for agent: SimAgent in world.agents:
		if not agent is StaffAgent:
			continue
		var staff: StaffAgent = agent as StaffAgent
		var role: StringName = staff.role
		if staff is OwnerAgent:
			if (staff as OwnerAgent).current_mode() == &"rest":
				continue
			role = &"owner"
		elif role == &"owner" or not ROLES.has(role):
			continue
		var key: String = String(role)
		var row: Dictionary = _roles.get(key, {"busy_ticks": 0, "open_ticks": 0})
		row["open_ticks"] = int(row["open_ticks"]) + 1
		if staff.task != null and staff.task.state == SimTask.State.CLAIMED \
				and staff.task.claimed_by == staff.id:
			row["busy_ticks"] = int(row["busy_ticks"]) + 1
		_roles[key] = row


## Employee rows contain person-ticks; owner hours include assigned time only.
func snapshot() -> Dictionary:
	if _open_ticks == 0:
		return {}
	return public_snapshot({"day": _day, "open_ticks": _open_ticks, "roles": _roles})


## Optional report data: malformed known rows make the observation unavailable.
## Unknown fields/roles are omitted, and JSON whole-valued floats are accepted.
static func public_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var summary: Dictionary = value
	if not _whole_count(summary.get("day"), 1) or not _whole_count(summary.get("open_ticks"), 1) \
			or not summary.get("roles") is Dictionary:
		return {}
	var original: Dictionary = summary["roles"]
	var roles: Dictionary = {}
	for role: StringName in ROLES:
		var key: String = String(role)
		if not original.has(key):
			continue
		if not original[key] is Dictionary:
			return {}
		var row: Dictionary = original[key]
		if not _whole_count(row.get("busy_ticks"), 0) or not _whole_count(row.get("open_ticks"), 1):
			return {}
		var busy: int = int(row["busy_ticks"])
		var opened: int = int(row["open_ticks"])
		if busy > opened:
			return {}
		roles[key] = {"busy_ticks": busy, "open_ticks": opened}
	if roles.is_empty():
		return {}
	return {"day": int(summary["day"]), "open_ticks": int(summary["open_ticks"]), "roles": roles}


static func _whole_count(value: Variant, minimum: int) -> bool:
	if value is int:
		return value >= minimum and value <= MAX_COUNT
	if not value is float:
		return false
	var number: float = value
	return is_finite(number) and number >= minimum and number <= MAX_COUNT and floorf(number) == number
