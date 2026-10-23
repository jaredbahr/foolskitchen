class_name ContentDB
extends RefCounted
## Loads content in sorted path order and publishes it only after validation.
## Validation reports strings rather than engine errors, including for tests.

var _ingredients: Dictionary[StringName, IngredientDef] = {}
var _recipes: Dictionary[StringName, RecipeDef] = {}
var _items: Dictionary[StringName, ItemDef] = {}


## On failure the database is empty, so an earlier load cannot hide bad data.
func load_all(root: String = "res://data") -> PackedStringArray:
	_ingredients.clear()
	_recipes.clear()
	_items.clear()
	var errors: PackedStringArray = []
	var ingredient_defs: Array[IngredientDef] = []
	var recipe_defs: Array[RecipeDef] = []
	var item_defs: Array[ItemDef] = []
	for path: String in _resource_paths(root.path_join("ingredients"), errors):
		var resource: Resource = ResourceLoader.load(path)
		if resource is IngredientDef:
			ingredient_defs.append(resource as IngredientDef)
		else:
			errors.append("%s: expected IngredientDef" % path)
	for path: String in _resource_paths(root.path_join("recipes"), errors):
		var resource: Resource = ResourceLoader.load(path)
		if resource is RecipeDef:
			recipe_defs.append(resource as RecipeDef)
		else:
			errors.append("%s: expected RecipeDef" % path)
	for path: String in _resource_paths(root.path_join("items"), errors):
		var resource: Resource = ResourceLoader.load(path)
		if resource is ItemDef:
			item_defs.append(resource as ItemDef)
		else:
			errors.append("%s: expected ItemDef" % path)
	errors.append_array(validate_definitions(ingredient_defs, recipe_defs, item_defs))
	if not errors.is_empty():
		return errors
	for definition: IngredientDef in ingredient_defs:
		_ingredients[definition.id] = definition
	for definition: RecipeDef in recipe_defs:
		_recipes[definition.id] = definition
	for definition: ItemDef in item_defs:
		_items[definition.id] = definition
	return errors


func ingredient(id: StringName) -> IngredientDef:
	return _ingredients.get(id) as IngredientDef


func recipe(id: StringName) -> RecipeDef:
	return _recipes.get(id) as RecipeDef


func item(id: StringName) -> ItemDef:
	return _items.get(id) as ItemDef


## Lists are new arrays sorted by ID; changing a list cannot change the index.
func ingredients() -> Array[IngredientDef]:
	var result: Array[IngredientDef] = []
	var ids: Array[StringName] = []
	ids.assign(_ingredients.keys())
	ids.sort_custom(_id_before)
	for id: StringName in ids:
		result.append(_ingredients[id])
	return result


func recipes() -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
	var ids: Array[StringName] = []
	ids.assign(_recipes.keys())
	ids.sort_custom(_id_before)
	for id: StringName in ids:
		result.append(_recipes[id])
	return result


func items() -> Array[ItemDef]:
	var result: Array[ItemDef] = []
	var ids: Array[StringName] = []
	ids.assign(_items.keys())
	ids.sort_custom(_id_before)
	for id: StringName in ids:
		result.append(_items[id])
	return result


## Also accepts in-memory definitions, without adding broken files to data/.
static func validate_definitions(ingredient_defs: Array[IngredientDef], recipe_defs: Array[RecipeDef], item_defs: Array[ItemDef]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var ingredient_ids: Dictionary[StringName, bool] = {}
	var recipe_ids: Dictionary[StringName, bool] = {}
	var item_ids: Dictionary[StringName, bool] = {}
	var stations: Dictionary[StringName, bool] = {}
	for definition: ItemDef in item_defs:
		if definition != null and definition.category == ItemDef.Category.STATION:
			stations[definition.station_type] = true
	for index: int in range(ingredient_defs.size()):
		var definition: IngredientDef = ingredient_defs[index]
		if definition == null:
			errors.append("ingredient[%d] is null" % index)
			continue
		_check_id(definition.id, "ingredient", ingredient_ids, errors)
		if definition.unit_cost < 0:
			errors.append("ingredient '%s': unit_cost must be >= 0" % definition.id)
	for index: int in range(item_defs.size()):
		var definition: ItemDef = item_defs[index]
		if definition == null:
			errors.append("item[%d] is null" % index)
			continue
		_check_id(definition.id, "item", item_ids, errors)
		if definition.footprint.x < 1 or definition.footprint.y < 1:
			errors.append("item '%s': footprint components must be >= 1" % definition.id)
		if definition.price < 0:
			errors.append("item '%s': price must be >= 0" % definition.id)
	for index: int in range(recipe_defs.size()):
		var definition: RecipeDef = recipe_defs[index]
		if definition == null:
			errors.append("recipe[%d] is null" % index)
			continue
		_check_id(definition.id, "recipe", recipe_ids, errors)
		if definition.standard_price < 0:
			errors.append("recipe '%s': standard_price must be >= 0" % definition.id)
		if definition.base_quality < 0.0 or definition.base_quality > 1.0:
			errors.append("recipe '%s': base_quality must be between 0 and 1" % definition.id)
		for ingredient_index: int in range(definition.ingredients.size()):
			if definition.ingredients[ingredient_index] == null:
				errors.append("recipe '%s': ingredient[%d] is null" % [definition.id, ingredient_index])
		if definition.steps.is_empty():
			errors.append("recipe '%s': at least one step is required" % definition.id)
		for step_index: int in range(definition.steps.size()):
			var step: RecipeStep = definition.steps[step_index]
			if step == null:
				errors.append("recipe '%s': step[%d] is null" % [definition.id, step_index])
				continue
			if step.duration_ticks <= 0:
				errors.append("recipe '%s': step[%d] duration_ticks must be > 0" % [definition.id, step_index])
			if step.station_type.is_empty() or not stations.has(step.station_type):
				errors.append("recipe '%s': step[%d] has unknown station '%s'" % [definition.id, step_index, step.station_type])
	return errors


## StringName ordering follows interned identities; content lists need lexical IDs.
static func _id_before(first: StringName, second: StringName) -> bool:
	return String(first) < String(second)


static func _check_id(id: StringName, kind: String, seen: Dictionary[StringName, bool], errors: PackedStringArray) -> void:
	if id.is_empty():
		errors.append("%s has an empty id" % kind)
	elif seen.has(id):
		errors.append("%s id '%s' is duplicated" % [kind, id])
	else:
		seen[id] = true


static func _resource_paths(folder: String, errors: PackedStringArray) -> PackedStringArray:
	var paths: PackedStringArray = []
	# Check accessibility only. ResourceLoader supplies the original filenames
	# even when export has converted a .tres into a remapped binary resource.
	if DirAccess.open(folder) == null:
		errors.append("Cannot open content directory: %s" % folder)
		return paths
	var entries: PackedStringArray = ResourceLoader.list_directory(folder)
	entries.sort()
	for entry: String in entries:
		if entry.ends_with("/"):
			var subdirectory: String = entry.trim_suffix("/")
			if not subdirectory.begins_with("."):
				paths.append_array(_resource_paths(folder.path_join(subdirectory), errors))
		elif entry.ends_with(".tres"):
			paths.append(folder.path_join(entry))
	paths.sort()
	return paths
