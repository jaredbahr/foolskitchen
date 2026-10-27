class_name RecipeDef
extends Resource
## Data for one menu dish; no preparation or economy behavior lives here.

const FOOD: StringName = &"food"
const COFFEE: StringName = &"coffee"
const DRINKS: StringName = &"drinks"
## Visit kinds in their fixed order (also the arrival draw order).
const ORDER_TYPES: Array[StringName] = [FOOD, COFFEE, DRINKS]

@export var id: StringName = &""
@export var display_name: String = ""
## One unit per entry; repeated references represent multiple units.
@export var ingredients: Array[IngredientDef] = []
## Operations are performed in array order.
@export var steps: Array[RecipeStep] = []
@export_range(0.0, 1.0) var base_quality: float = 0.5
## Whole currency; serves as the initial/reference menu price.
@export var standard_price: int = 0
@export var unlock_tier: int = 1
@export var unlock_level: int = 1
@export var theme_tags: Array[StringName] = []
## What kind of visit orders this (FK-083): a meal, a hot drink, or a cold or
## alcoholic drink. Drinks are listed under Drinks on the menu, are made by
## front-of-house staff at their station and carried straight to the guest.
@export var order_type: StringName = FOOD


func is_drink() -> bool:
	return order_type != FOOD


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
