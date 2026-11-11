class_name CareerTier
extends Resource
## One rung of the career ladder (D30): what the owner and shop need to reach it.

## The tier this rung reaches (2 to 6). Tier 1 is where every career starts.
@export_range(2, 6, 1) var tier: int = 2
@export_range(1, 1000, 1) var min_level: int = 1
## Closing reputation in stars; 0 means the tier needs no reputation.
@export_range(0.0, 5.0, 0.1) var min_reputation: float = 0.0


func is_valid() -> bool:
	return tier >= 2 and tier <= CareerTierTuning.TOP_TIER and min_level >= 1 and min_level <= 1000 \
		and is_finite(min_reputation) and min_reputation >= 0.0 and min_reputation <= 5.0


## Stars are compared at the precision the player sees them (one decimal).
func met(level: int, reputation: float) -> bool:
	return is_valid() and level >= min_level and is_finite(reputation) \
		and roundi(reputation * 10.0) >= roundi(min_reputation * 10.0)
