class_name SignatureTuning
extends Resource
## Authored signature progression; no scene, price, quality or random state.

const MAX_EXACT_INTEGER: int = 9007199254740991

@export var signature_unlock_sales: int = 150
@export var signature_demand_bonus: float = 1.05
@export var change_cooldown_days: int = 7


func is_valid() -> bool:
	return signature_unlock_sales >= 1 and signature_unlock_sales <= MAX_EXACT_INTEGER \
		and is_finite(signature_demand_bonus) and signature_demand_bonus >= 1.0 \
		and change_cooldown_days >= 1 and change_cooldown_days <= MAX_EXACT_INTEGER
