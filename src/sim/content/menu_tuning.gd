class_name MenuTuning
extends Resource
## Menu capacity and the unchanged skill weights for dish quality.

@export var base_dishes: int = 6
@export var levels_per_extra_dish: int = 2
@export var max_dishes: int = 12
@export var quality_skill_base: float = 0.7
@export var quality_per_skill: float = 0.1


func is_valid() -> bool:
	return base_dishes >= 1 and levels_per_extra_dish >= 1 and max_dishes >= base_dishes \
		and is_finite(quality_skill_base) and quality_skill_base >= 0.0 \
		and is_finite(quality_per_skill) and quality_per_skill >= 0.0


func limit_for_level(level: int) -> int:
	if not is_valid() or level < 1:
		return 0
	@warning_ignore("integer_division")
	var extra: int = (level - 1) / levels_per_extra_dish
	return base_dishes + mini(max_dishes - base_dishes, extra)
