class_name ContentDB
extends RefCounted
## Loads content in sorted path order and publishes it only after validation.
## Validation reports strings rather than engine errors, including for tests.

var _ingredients: Dictionary[StringName, IngredientDef] = {}
var _recipes: Dictionary[StringName, RecipeDef] = {}
var _items: Dictionary[StringName, ItemDef] = {}
var _swatches: Dictionary[StringName, SwatchDef] = {}
var _walls: Dictionary[StringName, WallKindDef] = {}


## On failure the database is empty, so an earlier load cannot hide bad data.
func load_all(root: String = "res://data") -> PackedStringArray:
	_ingredients.clear()
	_recipes.clear()
	_items.clear()
	_swatches.clear()
	_walls.clear()
	var errors: PackedStringArray = []
	var ingredient_defs: Array[IngredientDef] = []
	var recipe_defs: Array[RecipeDef] = []
	var item_defs: Array[ItemDef] = []
	var swatch_defs: Array[SwatchDef] = []
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
	for path: String in _resource_paths(root.path_join("swatches"), errors):
		var resource: Resource = ResourceLoader.load(path)
		if resource is SwatchDef:
			swatch_defs.append(resource as SwatchDef)
		else:
			errors.append("%s: expected SwatchDef" % path)
	var wall_defs: Array[WallKindDef] = []
	for path: String in _resource_paths(root.path_join("walls"), errors):
		var resource: Resource = ResourceLoader.load(path)
		if resource is WallKindDef:
			wall_defs.append(resource as WallKindDef)
		else:
			errors.append("%s: expected WallKindDef" % path)
	errors.append_array(validate_definitions(ingredient_defs, recipe_defs, item_defs))
	errors.append_array(validate_swatches(swatch_defs))
	errors.append_array(validate_wall_kinds(wall_defs))
	if not errors.is_empty():
		return errors
	for definition: IngredientDef in ingredient_defs:
		_ingredients[definition.id] = definition
	for definition: RecipeDef in recipe_defs:
		_recipes[definition.id] = definition
	for definition: ItemDef in item_defs:
		_items[definition.id] = definition
	for definition: SwatchDef in swatch_defs:
		_swatches[definition.id] = definition
	for definition: WallKindDef in wall_defs:
		_walls[definition.id] = definition
	return errors


func ingredient(id: StringName) -> IngredientDef:
	return _ingredients.get(id) as IngredientDef


func recipe(id: StringName) -> RecipeDef:
	return _recipes.get(id) as RecipeDef


func item(id: StringName) -> ItemDef:
	return _items.get(id) as ItemDef


func swatch(id: StringName) -> SwatchDef:
	return _swatches.get(id) as SwatchDef


func wall_kind(id: StringName) -> WallKindDef:
	return _walls.get(id) as WallKindDef


## The definition for a SimGrid.Segment value, or null.
func wall_kind_for(segment: int) -> WallKindDef:
	for definition: WallKindDef in _walls.values():
		if definition.segment == segment:
			return definition
	return null


## Catalogue order (then ID); a new array each call.
func wall_kinds() -> Array[WallKindDef]:
	var result: Array[WallKindDef] = []
	result.assign(_walls.values())
	result.sort_custom(func(a: WallKindDef, b: WallKindDef) -> bool:
		return a.order < b.order or (a.order == b.order and String(a.id) < String(b.id)))
	return result


## Exactly one definition per segment type, each with a name and a price.
static func validate_wall_kinds(definitions: Array[WallKindDef]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var ids: Dictionary[StringName, bool] = {}
	var segments: Dictionary[int, bool] = {}
	for index: int in range(definitions.size()):
		var definition: WallKindDef = definitions[index]
		if definition == null:
			errors.append("wall[%d] is null" % index)
			continue
		_check_id(definition.id, "wall", ids, errors)
		if definition.display_name.strip_edges().is_empty():
			errors.append("wall '%s': display_name is empty" % definition.id)
		if definition.price < 0:
			errors.append("wall '%s': price must be >= 0" % definition.id)
		if definition.segment < SimGrid.Segment.WALL or definition.segment > SimGrid.Segment.WINDOW:
			errors.append("wall '%s': segment must be wall, doorway or window" % definition.id)
		elif segments.has(definition.segment):
			errors.append("wall '%s': another wall definition has the same segment" % definition.id)
		else:
			segments[definition.segment] = true
	return errors


func swatches() -> Array[SwatchDef]:
	var result: Array[SwatchDef] = []
	var ids: Array[StringName] = []
	ids.assign(_swatches.keys())
	ids.sort_custom(_id_before)
	for id: StringName in ids:
		result.append(_swatches[id])
	return result


static func validate_swatches(definitions: Array[SwatchDef]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var ids: Dictionary[StringName, bool] = {}
	for index: int in range(definitions.size()):
		var definition: SwatchDef = definitions[index]
		if definition == null:
			errors.append("swatch[%d] is null" % index)
			continue
		_check_id(definition.id, "swatch", ids, errors)
		if definition.display_name.strip_edges().is_empty():
			errors.append("swatch '%s': display_name is empty" % definition.id)
	return errors


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
		if not is_finite(definition.seated_forward_offset) or definition.seated_forward_offset < 0.0 \
				or definition.seated_forward_offset > ItemDef.MAX_SEATED_FORWARD_OFFSET:
			errors.append("item '%s': seated_forward_offset must be finite and between 0 and 0.05 m" % definition.id)
		if not is_finite(definition.seated_lean_degrees) or definition.seated_lean_degrees < 0.0 \
				or definition.seated_lean_degrees > ItemDef.MAX_SEATED_LEAN_DEGREES:
			errors.append("item '%s': seated_lean_degrees must be finite and between 0 and 35 degrees" % definition.id)
		if not definition.placement_layer_valid():
			errors.append("item '%s': invalid placement layer; floor decor must be non-solid decor without blocking, work or seat cells" % definition.id)
		if not definition.blocking_cells_valid():
			errors.append("item '%s': blocking cells must be unique, inside the footprint, and separate from work and seat cells" % definition.id)
		if not definition.catalogue_room.is_empty() and not ItemDef.CATALOGUE_ROOMS.has(definition.catalogue_room):
			errors.append("item '%s': unknown catalogue room '%s'" % [definition.id, definition.catalogue_room])
		if definition.serve_across and definition.category != ItemDef.Category.TABLE:
			errors.append("item '%s': only a table or counter can be served across" % definition.id)
		if definition.paintable and definition.paint_slot != &"body":
			errors.append("item '%s': only the body paint slot is supported" % definition.id)
	for index: int in range(recipe_defs.size()):
		var definition: RecipeDef = recipe_defs[index]
		if definition == null:
			errors.append("recipe[%d] is null" % index)
			continue
		_check_id(definition.id, "recipe", recipe_ids, errors)
		if not RecipeDef.Section.values().has(definition.section):
			errors.append("recipe '%s': unknown menu section" % definition.id)
		if definition.standard_price < 0:
			errors.append("recipe '%s': standard_price must be >= 0" % definition.id)
		if definition.base_quality < 0.0 or definition.base_quality > 1.0:
			errors.append("recipe '%s': base_quality must be between 0 and 1" % definition.id)
		if not RecipeDef.ORDER_TYPES.has(definition.order_type):
			errors.append("recipe '%s': unknown order type '%s'" % [definition.id, definition.order_type])
		elif definition.is_drink() != (definition.section == RecipeDef.Section.DRINKS):
			errors.append("recipe '%s': drinks, and only drinks, belong in the Drinks section" % definition.id)
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
	errors.append_array(RecipeDef.validate_unlocks(recipe_defs))
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
