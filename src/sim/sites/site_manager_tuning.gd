class_name SiteManagerTuning
extends Resource
## Managers and away sites (FK-087, D24, D28), authored in
## data/balance/site_managers.tres. A managed inactive site earns, at each
## close of the active site, min(rate * mean, mean) of its own recent
## in-person days; rate rises linearly with the manager's service skill.

## Managers join candidate pools and can be hired from this career tier.
@export_range(1, 6) var hire_tier: int = 3
## The share of a site's recent in-person mean a skill 1 manager earns.
@export_range(0.0, 1.0, 0.01) var rate_at_skill_1: float = 0.70
## The share at skill 5 (never above 1: a manager never beats the owner).
@export_range(0.0, 1.0, 0.01) var rate_at_skill_5: float = 1.00
## How many recorded in-person business_history days the mean reads.
@export_range(1, 30) var history_days: int = 7


func is_valid() -> bool:
	return hire_tier >= 1 and hire_tier <= CareerTierTuning.TOP_TIER \
		and is_finite(rate_at_skill_1) and is_finite(rate_at_skill_5) \
		and rate_at_skill_1 >= 0.0 and rate_at_skill_1 <= rate_at_skill_5 and rate_at_skill_5 <= 1.0 \
		and history_days >= 1 and history_days <= BusinessHistory.MAX_DAYS


## The earning rate for a manager of `skill` (clamped to 1..5).
func rate_for(skill: int) -> float:
	var step: float = float(clampi(skill, 1, 5) - 1) / 4.0
	return rate_at_skill_1 + (rate_at_skill_5 - rate_at_skill_1) * step
