class_name MenuAccess
extends RefCounted
## Read-only station access for the live menu and isolated Build proposals.
## Stock, staffing and RNG never participate in these layout checks.

const NO_DISH: String = "Staff must be able to reach a stove or prep counter"


static func cookable(grid: SimGrid, recipes: Array[RecipeDef], level: int = 0,
		tier: int = 1) -> Array[RecipeDef]:
	var state: Dictionary = _state(grid)
	var result: Array[RecipeDef] = []
	if not state["fridge"] or not state["pass"]:
		return result
	var reachable: Dictionary[StringName, bool] = state["reachable"]
	for recipe: RecipeDef in recipes:
		if recipe.unlock_tier > tier or (level > 0 and recipe.unlock_level > level):
			continue
		var available: bool = true
		for station: StringName in _requirements(recipe):
			if not reachable.has(station):
				available = false
				break
		if available:
			result.append(recipe)
	return result


## Only dishes a proposal newly takes away are named. Kept duplicate stations
## count normally, and a dish that was already unavailable is not new advice.
static func lost(before: SimGrid, after: SimGrid, enabled: Array[RecipeDef], tier: int = 1) -> Array[RecipeDef]:
	var previous: Array[RecipeDef] = cookable(before, enabled, 0, tier)
	var next: Array[RecipeDef] = cookable(after, enabled, 0, tier)
	var result: Array[RecipeDef] = []
	for recipe: RecipeDef in previous:
		if not next.has(recipe):
			result.append(recipe)
	return result


static func warning(recipes: Array[RecipeDef], grid: SimGrid, content: ContentDB, opened: bool = false) -> String:
	if recipes.is_empty():
		return ""
	var state: Dictionary = _state(grid)
	var reachable: Dictionary[StringName, bool] = state["reachable"]
	var installed: Dictionary[StringName, bool] = state["installed"]
	var groups: Dictionary[StringName, Array] = {}
	for recipe: RecipeDef in recipes:
		for station: StringName in _requirements(recipe):
			if reachable.has(station):
				continue
			if not groups.has(station):
				groups[station] = []
			(groups[station] as Array).append(recipe.display_name)
			break
	var lines: PackedStringArray = []
	for station: StringName in groups:
		var names: PackedStringArray = []
		for value: String in groups[station]:
			names.append(value)
		var reason: String = "staff can't reach the %s" % station_name(station, content).to_lower() \
			if installed.has(station) else "the %s is missing" % station_name(station, content).to_lower()
		lines.append("%s %s: %s" % [_names(names), "left today's menu" if opened else "will leave the menu", reason])
	return "; ".join(lines)


static func station_name(station: StringName, content: ContentDB) -> String:
	var best: ItemDef = null
	for definition: ItemDef in content.items():
		var matches: bool = definition.category == ItemDef.Category.STATION and definition.station_type == station
		if station == &"fridge":
			matches = definition.category == ItemDef.Category.STORAGE and definition.station_type == station
		elif station == &"pass_counter":
			matches = definition.category == ItemDef.Category.PASS
		if matches and (best == null or definition.unlock_level < best.unlock_level):
			best = definition
	return best.display_name if best != null else "kitchen station"


static func _names(names: PackedStringArray) -> String:
	for index: int in range(1, names.size()):
		names[index] = names[index].left(1).to_lower() + names[index].substr(1)
	if names.size() < 2:
		return "" if names.is_empty() else names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]


static func _requirements(recipe: RecipeDef) -> Array[StringName]:
	var stations: Array[StringName] = []
	for step: RecipeStep in recipe.steps:
		if not stations.has(step.station_type):
			stations.append(step.station_type)
	# Food fetches ingredients and crosses both sides of the pass. Drinks are
	# prepared and carried by servers, so blocked kitchen supports do not stop them.
	if not recipe.is_drink():
		stations.append_array([&"fridge", &"pass_counter"] as Array[StringName])
	return stations


static func _state(grid: SimGrid) -> Dictionary:
	var reach: Dictionary[Vector2i, bool] = WallRules.reachable(grid)
	var reachable: Dictionary[StringName, bool] = {}
	var installed: Dictionary[StringName, bool] = {}
	var fridge: bool = false
	var pass_counter: bool = false
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or placed.removed:
			continue
		if definition.category == ItemDef.Category.STORAGE and definition.station_type == &"fridge" \
				and not definition.work_cells.is_empty():
			fridge = true
			installed[&"fridge"] = true
			for cell: Vector2i in placed.work_cells:
				if reach.has(cell):
					reachable[&"fridge"] = true
		elif definition.category == ItemDef.Category.PASS and definition.work_cells.size() >= 2:
			pass_counter = true
			installed[&"pass_counter"] = true
			if reach.has(placed.work_cells[0]) and reach.has(placed.work_cells[1]):
				reachable[&"pass_counter"] = true
		elif definition.category == ItemDef.Category.STATION and not definition.work_cells.is_empty():
			installed[definition.station_type] = true
			for cell: Vector2i in placed.work_cells:
				if reach.has(cell):
					reachable[definition.station_type] = true
					break
	return {"reachable": reachable, "installed": installed, "fridge": fridge, "pass": pass_counter}
