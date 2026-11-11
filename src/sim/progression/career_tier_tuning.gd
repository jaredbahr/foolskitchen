class_name CareerTierTuning
extends Resource
## The career ladder (D30), authored in data/balance/career_tiers.tres. Tiers
## are global to the owner, climbed in order at each close and never lost.

const TOP_TIER: int = 6

## One rung per tier from 2 to 6, in order.
@export var tiers: Array[CareerTier] = []


func is_valid() -> bool:
	if tiers.size() != TOP_TIER - 1:
		return false
	for index: int in range(tiers.size()):
		var rung: CareerTier = tiers[index]
		if rung == null or not rung.is_valid() or rung.tier != index + 2:
			return false
	return true


## The rung that reaches `tier`, or null outside 2 to 6.
func rung_for(tier: int) -> CareerTier:
	if not is_valid() or tier < 2 or tier > TOP_TIER:
		return null
	return tiers[tier - 2]


## The highest tier reachable from `current` by climbing in order.
func reachable(current: int, level: int, reputation: float) -> int:
	var tier: int = clampi(current, 1, TOP_TIER)
	if not is_valid():
		return tier
	while tier < TOP_TIER and tiers[tier - 1].met(level, reputation):
		tier += 1
	return tier


## The Goals line: what the next tier needs, or that the top is reached.
func goal_text(current: int) -> String:
	if current >= TOP_TIER:
		return "Top tier reached"
	var rung: CareerTier = rung_for(current + 1)
	if rung == null:
		return ""
	var needs: String = "reach level %d" % rung.min_level
	if rung.min_reputation > 0.0:
		needs += " and %.1f stars" % rung.min_reputation
	return "Tier %d → Tier %d: %s" % [current, current + 1, needs]


## The evening report line for a newly reached tier.
static func reached_text(tier: int) -> String:
	return "Your restaurant reached Tier %d!" % tier
