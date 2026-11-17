class_name DifficultyModeTuning
extends Resource
## One authored difficulty preset. A run reads these values through Difficulty.

@export var id: StringName = &"normal"
@export var auto_buy: bool = true
@export var auto_buy_premium: bool = true
@export var auto_hire: bool = false
@export var auto_wages: bool = false
@export var auto_prices: bool = false
@export var auto_jobs: bool = false
@export_range(0.1, 3.0, 0.01) var patience: float = 1.0
@export_range(0.1, 3.0, 0.01) var rent: float = 1.0
@export_range(0.1, 3.0, 0.01) var messes: float = 1.0
@export_range(-1.0, 1.0, 0.01) var review_bonus: float = 0.0


func is_valid() -> bool:
	return not id.is_empty() \
		and is_finite(patience) and patience > 0.0 \
		and is_finite(rent) and rent > 0.0 \
		and is_finite(messes) and messes > 0.0 \
		and is_finite(review_bonus)
