class_name DifficultyTuning
extends Resource
## The ordered, authored presets used by per-run Difficulty instances.

@export var modes: Array[DifficultyModeTuning] = []
@export var hire_wage_reserve_days: int = 5


func mode_data(mode_id: StringName) -> DifficultyModeTuning:
	for preset: DifficultyModeTuning in modes:
		if preset != null and preset.id == mode_id:
			return preset
	return null


func is_valid() -> bool:
	if modes.size() != Difficulty.MODES.size() or hire_wage_reserve_days < 1:
		return false
	for index: int in modes.size():
		var preset: DifficultyModeTuning = modes[index]
		if preset == null or not preset.is_valid() or preset.id != Difficulty.MODES[index]:
			return false
	return true
