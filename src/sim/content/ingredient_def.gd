class_name IngredientDef
extends Resource
## One purchasable ingredient. Recipe entries each consume one unit.

## Where the ingredient is kept (FK-087). SHELF is dry storage: the starter
## shop's back-room pantry and placed storage shelves. Each kind has its own
## capacity in units (StorageSpace); the Stock panel groups by it.
enum Storage { SHELF, FRIDGE, FREEZER }

@export var id: StringName = &""
@export var display_name: String = ""
## Whole currency per unit, before supplier discounts.
@export var unit_cost: int = 0
## Number of service days before a stocked unit expires. Freezer ingredients
## keep at least EconomyTuning.freezer_shelf_life_days.
@export var shelf_life_days: int = 1
@export var storage: Storage = Storage.SHELF
