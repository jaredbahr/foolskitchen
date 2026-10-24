class_name StaffMember
extends Resource
## A saved employee or candidate. Runtime agents receive their own copy.

@export var id: StringName = &""
@export var display_name: String = ""
@export var role: StringName = &"cook"
@export_range(1, 5) var skill: int = 3
@export var wage: int = 0
@export var trait_id: StringName = &"steady"


func copy() -> StaffMember:
	return duplicate() as StaffMember


func to_dict() -> Dictionary:
	return {"id": String(id), "name": display_name, "role": String(role),
		"skill": skill, "wage": wage, "trait": String(trait_id)}


static func from_dict(data: Variant, catalogue: StaffCatalogue) -> StaffMember:
	if not data is Dictionary or catalogue == null:
		return null
	var row: Dictionary = data
	if row.size() != 6:
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
	if not [&"cook", &"server"].has(member.role) or catalogue.trait(member.trait_id) == null:
		return null
	return member


static func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
