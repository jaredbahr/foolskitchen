class_name LotAccess
extends RefCounted
## A content definition with tags is available at a lot sharing any one of them.


static func allowed(definition: Resource, site_tags: Array[StringName]) -> bool:
	var tags: Array[StringName]
	if definition is ItemDef:
		tags = (definition as ItemDef).lot_tags
	elif definition is IngredientDef:
		tags = (definition as IngredientDef).lot_tags
	elif definition is RecipeDef:
		tags = (definition as RecipeDef).lot_tags
	else:
		return false
	if tags.is_empty():
		return true
	for tag: StringName in tags:
		if site_tags.has(tag):
			return true
	return false


static func valid_tags(tags: Array[StringName]) -> bool:
	for tag: StringName in tags:
		if not String(tag).is_valid_identifier():
			return false
	return true
