class_name RecipeDef
extends Resource
## Data for one menu dish; no preparation or economy behavior lives here.

enum Section { STARTERS, MAINS, SIDES, DRINKS, DESSERTS }
const FOOD: StringName = &"food"
const COFFEE: StringName = &"coffee"
const DRINKS: StringName = &"drinks"
## Visit kinds in their fixed order (also the arrival draw order).
const ORDER_TYPES: Array[StringName] = [FOOD, COFFEE, DRINKS]

@export var id: StringName = &""
@export var display_name: String = ""
@export var section: Section = Section.MAINS
## One unit per entry; repeated references represent multiple units.
@export var ingredients: Array[IngredientDef] = []
## Operations are performed in array order.
@export var steps: Array[RecipeStep] = []
@export_range(0.0, 1.0) var base_quality: float = 0.5
## Whole currency; serves as the initial/reference menu price.
@export var standard_price: int = 0
@export var unlock_tier: int = 1
@export var unlock_level: int = 1
## Owner-level route: this earlier dish leads to this node in the menu tree.
## Empty means a root. Levels are authoritative; no recipe-point save state.
@export var unlock_from: StringName = &""
@export var theme_tags: Array[StringName] = []
## What kind of visit orders this (FK-083): a meal, a hot drink, or a cold or
## alcoholic drink. Drinks are listed under Drinks on the menu, are made by
## front-of-house staff at their station and carried straight to the guest.
@export var order_type: StringName = FOOD
## A dish coffee guests may add to their drink (the croissant; FK-083).
@export var with_drinks: bool = false


func is_drink() -> bool:
	return order_type != FOOD


## The menu heading this recipe is listed under: every drink (FK-083) is in
## Drinks whatever its authored section; food keeps its own section.
func menu_section() -> int:
	return Section.DRINKS if is_drink() else section


static func section_name(value: int) -> String:
	match value:
		Section.STARTERS:
			return "Starters"
		Section.MAINS:
			return "Mains"
		Section.SIDES:
			return "Sides"
		Section.DRINKS:
			return "Drinks"
		Section.DESSERTS:
			return "Desserts"
	return ""


func ingredient_cost() -> int:
	var total: int = 0
	for ingredient_def: IngredientDef in ingredients:
		if ingredient_def != null:
			total += ingredient_def.unit_cost
	return total


func total_ticks() -> int:
	var total: int = 0
	for step: RecipeStep in steps:
		if step != null:
			total += step.duration_ticks
	return total


## Owner-level unlock links form a forest. A parent is learned automatically
## at its authored level, so adding links cannot change existing menu choices.
static func validate_unlocks(recipes: Array[RecipeDef]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var by_id: Dictionary[StringName, RecipeDef] = {}
	for recipe: RecipeDef in recipes:
		if recipe != null:
			by_id[recipe.id] = recipe
	for recipe: RecipeDef in recipes:
		if recipe == null or recipe.unlock_from.is_empty():
			continue
		var parent: RecipeDef = by_id.get(recipe.unlock_from) as RecipeDef
		if parent == null:
			errors.append("recipe '%s': unknown unlock prerequisite '%s'" % [recipe.id, recipe.unlock_from])
			continue
		if parent.unlock_level > recipe.unlock_level or parent.unlock_tier > recipe.unlock_tier:
			errors.append("recipe '%s': prerequisite must unlock no later than the dish" % recipe.id)
		var seen: Dictionary[StringName, bool] = {recipe.id: true}
		var cursor: RecipeDef = parent
		while cursor != null:
			if seen.has(cursor.id):
				errors.append("recipe '%s': unlock prerequisites contain a cycle" % recipe.id)
				break
			seen[cursor.id] = true
			cursor = by_id.get(cursor.unlock_from) as RecipeDef
	return errors


## Display projection only. Never replaces the sim's quality or review score.
static func quality_stars(quality: float) -> int:
	return clampi(roundi(clampf(quality, 0.0, 1.0) * 5.0), 1, 5) if is_finite(quality) else 1
