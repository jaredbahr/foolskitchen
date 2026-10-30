class_name RestockForecast
extends RefCounted
## Approximate one service's ingredient use from the demand forecast and
## enabled menu. This reads no stock, prices, guest choices or random stream.


static func targets(recipes: Array[RecipeDef], expected_guests: int,
		kind_weights: Dictionary, buffer: float, drink_add_chance: float = 0.0,
		pastry_add_chance: float = 0.0) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if expected_guests < 0 or not is_finite(buffer) or buffer < 1.0 or buffer > 2.0 \
			or not is_finite(drink_add_chance) or not is_finite(pastry_add_chance):
		return result
	var by_kind: Dictionary[StringName, Array] = {}
	var drinks: Array[RecipeDef] = []
	var pastries: Array[RecipeDef] = []
	var seen: Dictionary[StringName, bool] = {}
	for recipe: RecipeDef in recipes:
		if recipe == null or seen.has(recipe.id):
			continue
		seen[recipe.id] = true
		if not by_kind.has(recipe.order_type):
			by_kind[recipe.order_type] = []
		by_kind[recipe.order_type].append(recipe)
		if recipe.is_drink():
			drinks.append(recipe)
		if recipe.with_drinks:
			pastries.append(recipe)
		for ingredient: IngredientDef in recipe.ingredients:
			if ingredient != null:
				result[ingredient.id] = 0
	var weight_total: float = 0.0
	var weights: Dictionary[StringName, float] = {}
	for kind: StringName in by_kind:
		var raw_weight: Variant = kind_weights.get(kind, 1.0)
		if not (raw_weight is float or raw_weight is int):
			return {}
		var weight: float = float(raw_weight)
		if not is_finite(weight) or weight < 0.0:
			return {}
		weights[kind] = weight
		weight_total += weight
	if weight_total <= 0.0:
		# Quiet hours still have the visit tuning's minimum arrival rate. The
		# real chooser falls back to the first available visit kind, not no meal.
		for kind: StringName in RecipeDef.ORDER_TYPES:
			if by_kind.has(kind):
				weights[kind] = 1.0
				weight_total = 1.0
				break
		if weight_total <= 0.0:
			return result
	var amounts: Dictionary[StringName, float] = {}
	for kind: StringName in by_kind:
		var guests: float = float(expected_guests) * weights[kind] / weight_total
		var choices: Array = by_kind[kind]
		for recipe: RecipeDef in choices:
			_add_recipe(amounts, recipe, guests / float(choices.size()))
		if kind == RecipeDef.FOOD and not drinks.is_empty():
			for recipe: RecipeDef in drinks:
				_add_recipe(amounts, recipe, guests * clampf(drink_add_chance, 0.0, 1.0) / drinks.size())
		if kind == RecipeDef.COFFEE and not pastries.is_empty():
			for recipe: RecipeDef in pastries:
				_add_recipe(amounts, recipe, guests * clampf(pastry_add_chance, 0.0, 1.0) / pastries.size())
	for id: StringName in amounts:
		result[id] = maxi(0, ceili(minf(amounts[id] * buffer, ReorderSettings.MAX_TARGET)))
	return result


static func _add_recipe(amounts: Dictionary[StringName, float], recipe: RecipeDef, count: float) -> void:
	for ingredient: IngredientDef in recipe.ingredients:
		if ingredient != null:
			amounts[ingredient.id] = amounts.get(ingredient.id, 0.0) + count
