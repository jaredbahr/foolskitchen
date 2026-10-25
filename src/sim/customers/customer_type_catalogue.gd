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
