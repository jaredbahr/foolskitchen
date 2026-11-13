class_name PropertyMarket
extends RefCounted
## The property market (FK-087 part 2, D28): browse only. Which lots are
## listed, in what order, and what keeps one locked. Pure; the market screen
## (PropertyPanel, words in PropertyText) shows what this decides. Buying a
## lot waits for part 1.

## D28: from Tier 3 every lot is visible on the market.
const MARKET_TIER: int = 3


## Whether the morning Menu offers the Property screen at this career tier.
static func shown(career_tier: int) -> bool:
	return career_tier >= MARKET_TIER


## Every lot, cheapest to open first (LotDef.cost_to_open), then by name and
## id so the order never depends on load order. A new array.
static func listing(lots: Array[LotDef]) -> Array[LotDef]:
	var result: Array[LotDef] = []
	for lot: LotDef in lots:
		if lot != null:
			result.append(lot)
	result.sort_custom(_cheaper)
	return result


static func tier_met(lot: LotDef, career_tier: int) -> bool:
	return career_tier >= lot.min_tier


## Stars compare at the precision the player sees (one decimal), like CareerTier.
static func reputation_met(lot: LotDef, reputation: float) -> bool:
	return lot.min_reputation <= 0.0 or (is_finite(reputation)
		and roundi(reputation * 10.0) >= roundi(lot.min_reputation * 10.0))


static func locked(lot: LotDef, career_tier: int, reputation: float) -> bool:
	return not tier_met(lot, career_tier) or not reputation_met(lot, reputation)


static func _cheaper(a: LotDef, b: LotDef) -> bool:
	if a.cost_to_open() != b.cost_to_open():
		return a.cost_to_open() < b.cost_to_open()
	if a.display_name != b.display_name:
		return a.display_name < b.display_name
	return String(a.id) < String(b.id)
