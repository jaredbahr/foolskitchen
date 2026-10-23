class_name IngredientDef
extends Resource
## One purchasable ingredient. Recipe entries each consume one unit.

enum Storage { SHELF, FRIDGE, FREEZER }

@export var id: StringName = &""
@export var display_name: String = ""
## Whole currency per unit, before supplier discounts.
@export var unit_cost: int = 0
## Number of service days before a stocked unit expires.
@export var shelf_life_days: int = 1
@export var storage: Storage = Storage.SHELF
