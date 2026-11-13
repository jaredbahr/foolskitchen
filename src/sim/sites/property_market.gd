class_name PropertyMarket
extends RefCounted
## The property market (FK-087, D28). Which lots are listed, in what order,
## what keeps one locked, and whether one can be bought now and what that
## costs (#464). Pure; the market screen (PropertyPanel, words in
## PropertyText) shows what this decides, and main.gd `buy_lot` acts on it.

## Why a lot cannot be bought now; NONE when it can. PropertyText words them.
enum Refusal { NONE, OWNED, LOCKED, LIMIT, LOAN, CASH }

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


## The first reason, in this order, that `lot` cannot be bought: already
## owned, locked (tier or the closing reputation), the career tier's site
## limit, an open loan (like the lease, a big purchase waits for it), then
## cash short of LotDef.cost_to_open. NONE when it can be bought.
static func purchase_refusal(lot: LotDef, career_tier: int, reputation: float, owned: bool,
		site_count: int, limits: SiteLimitTuning, cash: int, loan: int) -> Refusal:
	if owned:
		return Refusal.OWNED
	if lot == null or locked(lot, career_tier, reputation) or not shown(career_tier):
		return Refusal.LOCKED
	if limits == null or not limits.allows_another(career_tier, site_count):
		return Refusal.LIMIT
	if loan > 0:
		return Refusal.LOAN
	if cash < lot.cost_to_open():
		return Refusal.CASH
	return Refusal.NONE


## The money a purchase moves, in order: the price (or the fixer price) as
## LOT_PURCHASE, then a fixer-upper's renovation bill as RENOVATION. Each is
## {"amount": int (negative), "category": StringName}; the sum is
## -cost_to_open.
static func purchase_charges(lot: LotDef) -> Array[Dictionary]:
	var charges: Array[Dictionary] = []
	if lot == null:
		return charges
	if lot.is_fixer_upper():
		charges.append({"amount": -lot.fixer_price, "category": Ledger.LOT_PURCHASE})
		charges.append({"amount": -lot.renovation_bill, "category": Ledger.RENOVATION})
	else:
		charges.append({"amount": -lot.price, "category": Ledger.LOT_PURCHASE})
	return charges


## Days of work before a newly bought site can open: a fixer-upper's
## renovation days, else 0.
static func renovation_days(lot: LotDef) -> int:
	return lot.renovation_days if lot != null and lot.is_fixer_upper() else 0


static func _cheaper(a: LotDef, b: LotDef) -> bool:
	if a.cost_to_open() != b.cost_to_open():
		return a.cost_to_open() < b.cost_to_open()
	if a.display_name != b.display_name:
		return a.display_name < b.display_name
	return String(a.id) < String(b.id)
