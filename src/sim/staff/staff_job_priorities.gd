class_name StaffJobPriorities
extends RefCounted
## Per-employee job choices. This is selection state, never a work-speed bonus.

enum Level { OFF, LOW, NORMAL, HIGH }

const JOBS: Array[StringName] = [&"cooking", &"serving", &"bussing", &"washing", &"cleaning"]
## The sole task-kind to player job mapping. Taking orders is Serving too.
const TASK_JOBS: Dictionary[StringName, StringName] = {
	&"cook": &"cooking", &"take_order": &"serving", &"deliver": &"serving",
	&"bus_table": &"bussing", &"wash": &"washing", &"clean_spot": &"cleaning",
	&"pour": &"serving",
}

var role: StringName
var _values: Dictionary[StringName, int] = {}


func _init(staff_role: StringName = &"cook") -> void:
	role = staff_role
	for job: StringName in JOBS:
		_values[job] = _default_value(role, job)


func copy() -> StaffJobPriorities:
	var result: StaffJobPriorities = StaffJobPriorities.new(role)
	result._values = _values.duplicate()
	return result


func priority(job: StringName) -> int:
	return _values.get(job, Level.OFF)


## Unsupported work stays Off. Every role retains its main job at some level.
func can_set(job: StringName, value: int) -> bool:
	return JOBS.has(job) and value >= Level.OFF and value <= Level.HIGH \
		and (supports(role, job) or value == Level.OFF) \
		and (job != main_job(role) or value != Level.OFF)


func set_priority(job: StringName, value: int) -> bool:
	if not can_set(job, value):
		return false
	_values[job] = value
	return true


func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for job: StringName in JOBS:
		result[String(job)] = priority(job)
	return result


## Validate the complete row before replacing any choice. JSON whole-number
## floats are accepted; booleans, missing/unknown jobs and forbidden Off fail.
func from_dict(data: Variant) -> bool:
	if not data is Dictionary or data.size() != JOBS.size() or main_job(role).is_empty():
		return false
	var row: Dictionary = data
	var staged: Dictionary[StringName, int] = {}
	for key: Variant in row:
		if not key is String or not JOBS.has(StringName(key)):
			return false
	for job: StringName in JOBS:
		var value: Variant = row.get(String(job))
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return false
		var number: float = float(value)
		if not is_finite(number) or number != floor(number) \
				or number < Level.OFF or number > Level.HIGH or not can_set(job, int(number)):
			return false
		staged[job] = int(number)
	_values = staged
	return true


static func job_for_task(kind: StringName) -> StringName:
	return TASK_JOBS.get(kind, &"")


static func main_job(staff_role: StringName) -> StringName:
	match staff_role:
		&"cook": return &"cooking"
		&"server": return &"serving"
		&"cleaner": return &"cleaning"
	return &""


## Keep existing role capabilities, including the server's conditional mop
## fallback. The live agent still checks whether a dedicated cleaner exists.
static func supports(staff_role: StringName, job: StringName) -> bool:
	match staff_role:
		&"cook": return job == &"cooking"
		&"server": return [&"serving", &"bussing", &"washing", &"cleaning"].has(job)
		&"cleaner": return job == &"cleaning"
	return false


static func job_label(job: StringName) -> String:
	match job:
		&"cooking": return "Cooking"
		&"serving": return "Serving"
		&"bussing": return "Bussing"
		&"washing": return "Washing"
		&"cleaning": return "Cleaning"
	return "Job"


static func level_label(value: int) -> String:
	match value:
		Level.HIGH: return "High"
		Level.NORMAL: return "Normal"
		Level.LOW: return "Low"
	return "Off"


static func _default_value(staff_role: StringName, job: StringName) -> int:
	if not supports(staff_role, job):
		return Level.OFF
	if staff_role == &"server":
		return Level.LOW if job == &"cleaning" else Level.NORMAL
	return Level.HIGH
