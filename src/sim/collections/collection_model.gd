class_name CollectionModel
extends RefCounted
## Pure derived progress for authored decor collections.

class Entry extends RefCounted:
	class Requirement extends RefCounted:
		var item_id: StringName = &""
		var display_name: String = ""
		var present: bool = false

	var definition: CollectionDef
	var requirements: Array[Requirement] = []
	var floor_required: bool = false
	var floor_name: String = ""
	var has_floor: bool = true
	var completed: bool = false

	func progress_text() -> String:
		var present_count: int = 0
		for requirement: Requirement in requirements:
			if requirement.present:
				present_count += 1
		var text: String = "%s — %d / %d items" % [definition.display_name,
			present_count, requirements.size()]
		if floor_required:
			text += " · floor: %s %s" % ["✓" if has_floor else "□", floor_name]
		if completed:
			text += " · Complete! (+%d)" % roundi(definition.bonus)
		return text

class Result extends RefCounted:
	var valid: bool = false
	var entries: Array[Entry] = []
	var completed_ids: Array[StringName] = []
	var nominal_bonus: float = 0.0
	var effective_bonus: float = 0.0
	var capped: bool = false


static func evaluate(definitions: Array[CollectionDef], placed_item_ids: Array[StringName],
		floor_ids: Array[StringName], maximum_bonus: float, content: ContentDB) -> Result:
	var result: Result = Result.new()
	if content == null or not is_finite(maximum_bonus) or maximum_bonus < 0.0:
		return result
	var placed: Dictionary[StringName, bool] = {}
	for id: StringName in placed_item_ids:
		placed[id] = true
	var floors: Dictionary[StringName, bool] = {}
	for id: StringName in floor_ids:
		floors[id] = true
	var seen: Dictionary[StringName, bool] = {}
	for definition: CollectionDef in definitions:
		if definition == null or definition.id.is_empty() or seen.has(definition.id) \
				or definition.item_ids.is_empty() or not is_finite(definition.bonus) \
				or definition.bonus < 0.0 or definition.display_name.strip_edges().is_empty() \
				or definition.short_line.strip_edges().is_empty():
			return Result.new()
		seen[definition.id] = true
		var entry: Entry = Entry.new()
		entry.definition = definition
		entry.floor_required = not definition.floor_id.is_empty()
		var all_items: bool = true
		var required_seen: Dictionary[StringName, bool] = {}
		for id: StringName in definition.item_ids:
			if id.is_empty() or required_seen.has(id):
				return Result.new()
			required_seen[id] = true
			var item: bool = placed.has(id)
			var item_def: ItemDef = content.item(id)
			if item_def == null:
				return Result.new()
			if not item:
				all_items = false
			var requirement: Entry.Requirement = Entry.Requirement.new()
			requirement.item_id = id
			requirement.display_name = item_def.display_name
			requirement.present = item
			entry.requirements.append(requirement)
		var floor_def: FloorStyleDef = content.floor_style(definition.floor_id) \
			if not definition.floor_id.is_empty() else null
		if entry.floor_required and floor_def == null:
			return Result.new()
		entry.floor_name = floor_def.display_name if floor_def != null else ""
		entry.has_floor = definition.floor_id.is_empty() or floors.has(definition.floor_id)
		entry.completed = all_items and entry.has_floor
		if entry.completed:
			result.completed_ids.append(definition.id)
			result.nominal_bonus += definition.bonus
		result.entries.append(entry)
	result.effective_bonus = minf(result.nominal_bonus, maximum_bonus)
	result.capped = result.nominal_bonus > maximum_bonus
	result.valid = is_finite(result.nominal_bonus) and is_finite(result.effective_bonus)
	return result
