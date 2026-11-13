class_name PropertyText
extends RefCounted
## Every player-facing line of the property market screen (FK-087), in one
## place, so no lot id, tag, customer type id or refusal code reaches the
## screen.

const TITLE: String = "Property"
const BUTTON_TOOLTIP: String = "Buy a lot for another restaurant"
const INTRO: String = "Lots for another restaurant. A fixer-upper is cheaper, but needs a few days of work before it can open."
const BUY_OWNED: String = "Owned"
const BUY_LOCKED: String = "Locked"
const BUY_REFUSED: String = "Buy"
const OWNED_LINE: String = "You own this lot."
const LOAN_LINE: String = "Pay off your loan before buying a lot."
const LIMIT_TOP_LINE: String = "You run as many restaurants as you can."
const UNKNOWN_LOT_LINE: String = "That lot is not on the market."
const NOT_LISTED_LINE: String = "That lot is not on the market yet."
const MORNING_LINE: String = "Buy property in the morning."
## A new site starts with nobody (#464): it cannot open until it has both.
const UNSTAFFED_LINE: String = "Hire a cook and a server before you open"
## Lot leases expand from #465; until then only the first restaurant can.
const LEASE_HOME_ONLY_LINE: String = "Only your first restaurant can expand its lease for now"
const EMPTY: String = "No lots are on the market."
## Lot tags as perks (LotDef.KNOWN_TAGS); a tag missing here shows nothing.
const TAG_PERKS: Dictionary[StringName, String] = {
	&"seaside": "Fresh catch",
	&"rooftop": "Rooftop bar",
}
const UPSTAIRS_PERK: String = "Room for an upstairs"
## The top guest type at or above this share reads "Mostly ...".
const MOSTLY_SHARE: float = 0.5


## "$18,000 · move-in ready", or "Fixer-upper $6,000 + renovation $2,500 (3 days)".
static func price_line(lot: LotDef) -> String:
	if lot.is_fixer_upper():
		return "Fixer-upper %s + renovation %s (%d days of work)" % [
			Fmt.money(lot.fixer_price), Fmt.money(lot.renovation_bill), lot.renovation_days]
	return "%s · move-in ready" % Fmt.money(lot.price)


static func size_line(lot: LotDef) -> String:
	return "%d floor tiles" % lot.size_cells()


static func rent_line(lot: LotDef) -> String:
	return "Rent %s a day" % Fmt.money(lot.daily_rent)


## Every lot can expand (Jared, 2026-11-13).
static func expansion_line(lot: LotDef) -> String:
	return "Expand later for %s, then rent %s a day" % [
		Fmt.money(lot.expansion_price), Fmt.money(lot.expanded_daily_rent)]


## "Guests: mostly foodies" or "Guests: families and foodies", from the
## customer types' own names; unknown types are left out.
static func guest_line(lot: LotDef, catalogue: CustomerTypeCatalogue) -> String:
	var shares: Array[Array] = []
	var total: float = 0.0
	for id: StringName in lot.guest_mix:
		var kind: CustomerType = catalogue.find_type(id) if catalogue != null else null
		var share: float = lot.guest_mix[id]
		if kind == null or not is_finite(share) or share <= 0.0:
			continue
		shares.append([share, plural(kind.display_name)])
		total += share
	if shares.is_empty():
		return ""
	shares.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and String(a[1]) < String(b[1])))
	if shares.size() == 1 or float(shares[0][0]) / total >= MOSTLY_SHARE:
		return "Guests: mostly %s" % shares[0][1]
	return "Guests: %s and %s" % [shares[0][1], shares[1][1]]


## "Perks: Fresh catch, Room for an upstairs", or "" with none.
static func perks_line(lot: LotDef) -> String:
	var perks: PackedStringArray = []
	for tag: StringName in lot.tags:
		if TAG_PERKS.has(tag):
			perks.append(TAG_PERKS[tag])
	if lot.upstairs_allowed:
		perks.append(UPSTAIRS_PERK)
	return "" if perks.is_empty() else "Perks: " + ", ".join(perks)


## "" when the lot is open to this career; otherwise what it still needs.
static func lock_line(lot: LotDef, career_tier: int, reputation: float) -> String:
	var tier_short: bool = not PropertyMarket.tier_met(lot, career_tier)
	var stars_short: bool = not PropertyMarket.reputation_met(lot, reputation)
	if tier_short and stars_short:
		return "Locked: needs Tier %d and %.1f stars" % [lot.min_tier, lot.min_reputation]
	if tier_short:
		return "Locked: needs Tier %d" % lot.min_tier
	if stars_short:
		# Before the first close there is no closing reputation to quote.
		if not is_finite(reputation):
			return "Locked: needs %.1f stars" % lot.min_reputation
		return "Locked: needs %.1f stars (you have %.1f)" % [lot.min_reputation, reputation]
	return ""


## The Buy button: "Buy for $8,500" when it can be bought, else a short word.
static func buy_label(lot: LotDef, refusal: PropertyMarket.Refusal) -> String:
	match refusal:
		PropertyMarket.Refusal.NONE:
			return "Buy for %s" % Fmt.money(lot.cost_to_open())
		PropertyMarket.Refusal.OWNED:
			return BUY_OWNED
		PropertyMarket.Refusal.LOCKED:
			return BUY_LOCKED
	return BUY_REFUSED


## Why the lot cannot be bought now, as a sentence; "" when it can, or when
## the card's lock line already says why.
static func refusal_line(lot: LotDef, refusal: PropertyMarket.Refusal, cash: int,
		site_count: int, limits: SiteLimitTuning) -> String:
	match refusal:
		PropertyMarket.Refusal.OWNED:
			return OWNED_LINE
		PropertyMarket.Refusal.LIMIT:
			var tier: int = limits.tier_for_more(site_count) if limits != null else 0
			if tier <= 0:
				return LIMIT_TOP_LINE
			return "Your tier allows %d restaurants. Reach Tier %d to run more." % [site_count, tier]
		PropertyMarket.Refusal.LOAN:
			return LOAN_LINE
		PropertyMarket.Refusal.CASH:
			return "Not enough cash: you need %s more." % Fmt.money(maxi(0, lot.cost_to_open() - cash))
	return ""


## The evening report's note on a renovating away site, or "" when none.
static func renovation_report_note(days_left: int, just_finished: bool) -> String:
	if days_left > 0:
		return "; renovating, %d %s left" % [days_left, "day" if days_left == 1 else "days"]
	return "; renovation done, ready to open" if just_finished else ""


## Why a renovating site cannot open: "Still renovating: 2 days left".
static func renovating_line(days_left: int) -> String:
	return "Still renovating: %d %s left" % [days_left, "day" if days_left == 1 else "days"]


## The same-day question's detail line after a purchase.
static func prompt_detail(lot: LotDef) -> String:
	var days: int = PropertyMarket.renovation_days(lot)
	if days > 0:
		return "%s needs %d days of work before it can open, but you can design inside. It has no staff yet." % [
			lot.display_name, days]
	return "%s is yours. It has no staff yet: hire a cook and a server there before you open." % lot.display_name


## The log line after a purchase.
static func bought_line(lot: LotDef) -> String:
	if PropertyMarket.renovation_days(lot) > 0:
		return "You bought %s. It needs %d days of work before it can open." % [
			lot.display_name, PropertyMarket.renovation_days(lot)]
	return "You bought %s. Hire a cook and a server there before it opens." % lot.display_name


## "Foodie" -> "foodies", "Family" -> "families": a lower-case plural.
static func plural(display_name: String) -> String:
	var word: String = display_name.strip_edges().to_lower()
	if word.length() > 1 and word.ends_with("y") and not "aeiou".contains(word[word.length() - 2]):
		return word.left(word.length() - 1) + "ies"
	return word + "s"
