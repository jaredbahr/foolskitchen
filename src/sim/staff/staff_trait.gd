class_name StaffTrait
extends Resource
## Trait effects are content values; Steady leaves every baseline unchanged.

@export var id: StringName = &"steady"
@export var display_name: String = "Steady"
@export var description: String = "Reliable, with no special bonus."
@export var role_descriptions: Dictionary[StringName, String] = {}
@export var walk_multiplier: float = 1.0
@export var cook_quality_bonus: float = 0.0
@export var food_patience_multiplier: float = 1.0


## Describe only effects this person's role can use; other roles use neutral text.
func description_for(staff_role: StringName) -> String:
	return role_descriptions.get(staff_role, description)
