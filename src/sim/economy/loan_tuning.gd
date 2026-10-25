class_name LoanTuning
extends Resource
## Authored bank terms. Phase 2 balancing may adjust the daily interest within
## the director's 4–6% range without changing accounting code.

@export_range(0.04, 0.06, 0.005) var daily_interest: float = 0.05
@export_range(0.0, 1.0, 0.05) var repay_share: float = 0.5
@export var borrowing_step: int = 50
@export var large_purchase_limit: int = 50


func is_valid() -> bool:
	return is_finite(daily_interest) and daily_interest >= 0.04 and daily_interest <= 0.06 \
		and is_finite(repay_share) and repay_share >= 0.0 and repay_share <= 1.0 \
		and borrowing_step > 0 and large_purchase_limit >= 0
