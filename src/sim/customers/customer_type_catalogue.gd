class_name CustomerTypeCatalogue
extends Resource
## Authored customer types and their reputation-dependent spawn weights.

@export var types: Array[CustomerType] = []


func is_valid() -> bool:
	if types.is_empty():
		return false
	var ids: Dictionary[StringName, bool] = {}
	for kind: CustomerType in types:
		if kind == null or not kind.is_valid() or ids.has(kind.id):
			return false
		ids[kind.id] = true
	return true


func find_type(id: StringName) -> CustomerType:
	for kind: CustomerType in types:
		if kind != null and kind.id == id:
			return kind
	return null


## Authored tips for guest groups that start visiting at a level in
## (previous_level, current_level], once each and in catalogue order.
func level_up_tips(previous_level: int, current_level: int) -> Array[String]:
	var tips: Array[String] = []
	for kind: CustomerType in types:
		if kind == null or kind.party_tip.strip_edges().is_empty():
			continue
		var level: int = kind.group_level()
		if level > previous_level and level <= current_level and not tips.has(kind.party_tip):
			tips.append(kind.party_tip)
	return tips
