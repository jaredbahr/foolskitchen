class_name StaffCatalogue
extends Resource
## Authored traits, the starting people and names for the daily candidate pool.

@export var traits: Array[StaffTrait] = []
@export var starters: Array[StaffMember] = []
@export var candidate_names: PackedStringArray = []


func trait(id: StringName) -> StaffTrait:
	for definition: StaffTrait in traits:
		if definition.id == id:
			return definition
	return null


func defaults(tuning: EconomyTuning) -> Array[StaffMember]:
	var result: Array[StaffMember] = []
	for template: StaffMember in starters:
		var member: StaffMember = template.copy()
		member.wage = tuning.wages.get(member.role, 0)
		result.append(member)
	return result
