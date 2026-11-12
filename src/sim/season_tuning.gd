class_name SeasonTuning
extends Resource
## Authored supplier availability by season (data/balance/seasons.tres).

const KIND_NAMES: PackedStringArray = ["Spring", "Summer", "Autumn", "Winter"]

@export_range(0.01, 1.0, 0.01) var in_season_multiplier: float = 0.8
@export_range(1.0, 2.0, 0.01) var out_of_season_multiplier: float = 1.2

@export var spring_in: Array[StringName] = []
@export var spring_out: Array[StringName] = []
@export var summer_in: Array[StringName] = []
@export var summer_out: Array[StringName] = []
@export var autumn_in: Array[StringName] = []
@export var autumn_out: Array[StringName] = []
@export var winter_in: Array[StringName] = []
@export var winter_out: Array[StringName] = []


func is_in_season(id: StringName, kind: int) -> bool:
	return _in_ids(kind).has(id)


func is_out_of_season(id: StringName, kind: int) -> bool:
	return _out_ids(kind).has(id)


func multiplier_for(id: StringName, kind: int) -> float:
	if is_in_season(id, kind):
		return in_season_multiplier
	if is_out_of_season(id, kind):
		return out_of_season_multiplier
	return 1.0


func validate(ingredients: Array[IngredientDef]) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not is_finite(in_season_multiplier) or in_season_multiplier <= 0.0 \
			or in_season_multiplier > 1.0:
		errors.append("In-season multiplier must be finite and between 0 and 1")
	if not is_finite(out_of_season_multiplier) or out_of_season_multiplier < 1.0 \
			or out_of_season_multiplier > 2.0:
		errors.append("Out-of-season multiplier must be finite and between 1 and 2")
	var known: Dictionary[StringName, bool] = {}
	for ingredient: IngredientDef in ingredients:
		if ingredient != null and not ingredient.id.is_empty():
			known[ingredient.id] = true
	for kind: int in 4:
		var in_ids: Array[StringName] = _in_ids(kind)
		var out_ids: Array[StringName] = _out_ids(kind)
		var label: String = KIND_NAMES[kind]
		if in_ids.size() < 3 or in_ids.size() > 5:
			errors.append("%s needs 3 to 5 in-season ingredients" % label)
		if out_ids.size() < 2 or out_ids.size() > 3:
			errors.append("%s needs 2 to 3 out-of-season ingredients" % label)
		var seen: Dictionary[StringName, bool] = {}
		for id: StringName in in_ids:
			if not known.has(id):
				errors.append("%s has unknown in-season ingredient '%s'" % [label, id])
			if seen.has(id):
				errors.append("%s repeats ingredient '%s'" % [label, id])
			seen[id] = true
		for id: StringName in out_ids:
			if not known.has(id):
				errors.append("%s has unknown out-of-season ingredient '%s'" % [label, id])
			if seen.has(id):
				errors.append("%s repeats or overlaps ingredient '%s'" % [label, id])
			seen[id] = true
	return errors


func _in_ids(kind: int) -> Array[StringName]:
	match kind:
		0: return spring_in
		1: return summer_in
		2: return autumn_in
		3: return winter_in
	return []


func _out_ids(kind: int) -> Array[StringName]:
	match kind:
		0: return spring_out
		1: return summer_out
		2: return autumn_out
		3: return winter_out
	return []
