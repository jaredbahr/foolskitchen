class_name SiteLimitTuning
extends Resource
## How many restaurants the owner may run at each career tier (FK-087, D28),
## authored in data/balance/sites.tres: 2 at Tier 3, 3 at Tier 5 and
## unlimited at Tier 6 (the chain). The home site counts as one.

## Means "no limit" in `sites_by_tier`.
const UNLIMITED: int = 0

## One entry per career tier, Tier 1 first: the most sites owned at once.
## UNLIMITED may only appear from some tier on, never before a number.
@export var sites_by_tier: Array[int] = [1, 1, 2, 2, 3, UNLIMITED]


func is_valid() -> bool:
	if sites_by_tier.size() != CareerTierTuning.TOP_TIER or sites_by_tier[0] < 1:
		return false
	for index: int in range(1, sites_by_tier.size()):
		var limit: int = sites_by_tier[index]
		var before: int = sites_by_tier[index - 1]
		if limit < UNLIMITED or (before == UNLIMITED and limit != UNLIMITED) \
				or (limit != UNLIMITED and limit < before):
			return false
	return true


## The most sites allowed at `career_tier` (clamped to 1..6), or UNLIMITED.
## An invalid tuning allows only the home site.
func limit_for(career_tier: int) -> int:
	if not is_valid():
		return 1
	return sites_by_tier[clampi(career_tier, 1, CareerTierTuning.TOP_TIER) - 1]


## True when owning `site_count` sites leaves room for one more.
func allows_another(career_tier: int, site_count: int) -> bool:
	var limit: int = limit_for(career_tier)
	return limit == UNLIMITED or site_count < limit


## The lowest tier that allows more than `site_count` sites, or 0 if none.
func tier_for_more(site_count: int) -> int:
	for tier: int in range(1, CareerTierTuning.TOP_TIER + 1):
		if allows_another(tier, site_count):
			return tier
	return 0
