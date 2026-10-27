class_name MenuTuning
extends Resource
## Menu size grows with owner experience; no dish or economy tuning lives here.

@export var base_dishes: int = 6
@export var levels_per_extra_dish: int = 2
@export var max_dishes: int = 12


func is_valid() -> bool:
	return base_dishes >= 1 and levels_per_extra_dish >= 1 and max_dishes >= base_dishes


func limit_for_level(level: int) -> int:
	if not is_valid() or level < 1:
		return 0
	@warning_ignore("integer_division")
	var extra: int = (level - 1) / levels_per_extra_dish
	return base_dishes + mini(max_dishes - base_dishes, extra)
