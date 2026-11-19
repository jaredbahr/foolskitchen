class_name ChainText
extends RefCounted
## Every line of the city screen (docs/CITY_MAP.md): statuses, money, the
## manager, alerts, neighbourhood and lot lines. One place for the words, so
## no enum or id ever reaches the player (rule 11). Placeholder wording until
## the map's art and names are picked (CITY_MAP.md T1 to T8).

const TITLE: String = "The City"
const BUTTON: String = "City"
const BUTTON_TOOLTIP: String = "See your restaurants and the lots around town"
const INTRO: String = "Your restaurants and the lots around town. In the morning, pick where to work today."
const HERE: String = "You are here"
const CLOSED: String = "Closed"
const GO: String = "Work here today"
const DESIGN: String = "Design here today"
const NO_MANAGER: String = "No manager"
## Pin badges on the map view.
const FOR_SALE_BADGE: String = "For sale"
const LOCKED_BADGE: String = "Locked"
const MARKET: String = "See it on the market"
const SHOW_LIST: String = "Show list"
const SHOW_MAP: String = "Show map"
const SELECT_HINT: String = "Tap a pin to see how it is doing."
const NO_STARS: String = "No stars yet"
const NO_TEAM: String = "No team yet"
const MOOD_HAPPY: String = "Team: happy"
const MOOD_FINE: String = "Team: fine"
const MOOD_UNHAPPY: String = "Team: unhappy"
## A team at this mean mood or above reads happy; at FINE_MOOD or above, fine.
const HAPPY_MOOD: float = 2.5
const FINE_MOOD: float = 1.5
const ALERTS: Dictionary[int, String] = {
	ChainSummary.Alert.NOT_STAFFED: "Hire a cook and a server before it can open.",
	ChainSummary.Alert.NO_MANAGER: "Closed: nobody runs it while you're away, and it still pays rent.",
	ChainSummary.Alert.MANAGER_NEEDS_A_DAY: "Your manager needs a day you ran there first.",
	ChainSummary.Alert.LOSING_MONEY: "Losing money: your recent days here averaged a loss.",
	ChainSummary.Alert.BOOKING_LAPSES: "A group booking there lapses tonight (the deposit is refunded).",
	ChainSummary.Alert.UNHAPPY_TEAM: "Someone on the team there is unhappy.",
	ChainSummary.Alert.READY_TO_OPEN: "Ready to open: it hasn't served a day yet.",
}


## "Managed by Morgan", "Closed", "Renovating: 2 days left", "You are here".
static func status_line(site: ChainSummary.Site) -> String:
	match site.status:
		ChainSummary.Status.HERE:
			return HERE if site.renovation_days == 0 else "%s · %s" % [HERE, PropertyText.renovating_line(site.renovation_days)]
		ChainSummary.Status.MANAGED:
			return "Managed by %s" % site.manager_name if not site.manager_name.is_empty() else "Managed"
		ChainSummary.Status.RENOVATING:
			return PropertyText.renovating_line(site.renovation_days)
	return CLOSED


## Yesterday's money: gross takings where the owner worked, net earnings
## where a manager ran it, else "" (closed yesterday).
static func yesterday_line(site: ChainSummary.Site) -> String:
	if site.yesterday_takings != 0:
		return "Yesterday's takings: %s" % Fmt.money(site.yesterday_takings)
	if site.yesterday_earnings != 0:
		return "Yesterday (after the manager): %s" % signed(site.yesterday_earnings)
	return ""


## What tonight's close books for an away site ("" for the active one).
static func tonight_line(site: ChainSummary.Site) -> String:
	if site.is_active():
		return ""
	if site.status == ChainSummary.Status.MANAGED:
		return "Tonight: about %s" % signed(site.tonight)
	if site.tonight == 0:
		return "Tonight: nothing to pay"
	return "Tonight: %s in rent and wages" % signed(site.tonight)


## "Manager: Morgan (keeps 85% of what you made here)" or "No manager".
static func manager_line(site: ChainSummary.Site) -> String:
	if site.manager_skill <= 0 or site.manager_name.is_empty():
		return NO_MANAGER
	return "Manager: %s (keeps %d%% of what you made here)" % [site.manager_name, roundi(site.manager_rate * 100.0)]


## "★ 4.3 · Golden Ladles: 2 · Team: happy".
static func standing_line(site: ChainSummary.Site) -> String:
	var parts: PackedStringArray = [stars(site.stars)]
	if site.golden_ladles > 0:
		parts.append(ladles(site.golden_ladles))
	parts.append(mood(site.mood))
	return " · ".join(parts)


static func stars(value: float) -> String:
	return "★ %.1f" % value if is_finite(value) else NO_STARS


static func ladles(count: int) -> String:
	return "Golden Ladles: %d" % count


static func mood(value: float) -> String:
	if not is_finite(value):
		return NO_TEAM
	if value >= HAPPY_MOOD:
		return MOOD_HAPPY
	return MOOD_FINE if value >= FINE_MOOD else MOOD_UNHAPPY


static func alert_line(alert: int) -> String:
	return ALERTS.get(alert, "")


## The row's button: "You are here", "Work here today", "Design here today"
## (renovating), or why it cannot be chosen now.
static func go_label(site: ChainSummary.Site, refusal: String) -> String:
	if site.is_active():
		return HERE
	if not refusal.is_empty():
		return refusal
	return DESIGN if site.renovation_days > 0 else GO


## A neighbourhood's state under its name: "" when open, "Opens at Tier 4"
## while the owner is below its lowest tier, else what its nearest lot still
## needs (`lock`, the market's lock line, e.g. "Locked: needs 4.3 stars"), or
## "Coming soon: A cabin in the woods".
static func area_line(state: CityMap.AreaState, opening_tier: int, coming_soon: String,
		career_tier: int = 0, lock: String = "") -> String:
	match state:
		CityMap.AreaState.LOCKED:
			if opening_tier > 0 and career_tier < opening_tier:
				return "Opens at Tier %d" % opening_tier
			return lock if not lock.is_empty() else "Locked for now"
		CityMap.AreaState.COMING_SOON:
			return "Coming soon: %s" % coming_soon
	return ""


## A lot that is not yours: "For sale · $11,500" or its lock line.
static func lot_line(lot: LotDef, state: CityMap.LotState, career_tier: int, reputation: float) -> String:
	if state == CityMap.LotState.FOR_SALE:
		return "For sale · %s" % PropertyText.price_line(lot)
	var lock: String = PropertyText.lock_line(lot, career_tier, reputation)
	return lock if not lock.is_empty() else "Not for sale yet"


## The chain strip: "3 restaurants · ★ 4.2 average · Golden Ladles: 1".
static func chain_line(sites: Array[ChainSummary.Site]) -> String:
	var parts: PackedStringArray = ["%d %s" % [sites.size(), "restaurant" if sites.size() == 1 else "restaurants"]]
	var mean: float = ChainStats.mean_stars(sites)
	if is_finite(mean):
		parts.append("★ %.1f average" % mean)
	parts.append(ladles(ChainStats.total_ladles(sites)))
	return " · ".join(parts)


## "2 things need you" over the alerts list, or "" with none.
static func alerts_heading(count: int) -> String:
	if count <= 0:
		return ""
	return "1 thing needs you" if count == 1 else "%d things need you" % count


## The bottom bar's tail when more things need you than it lists.
static func more_line(count: int) -> String:
	return "and %d more" % count


## The short state word under a shop pin: "Here", "Managed", "Closed",
## "Renovating", or "Needs you" when it has an alert.
static func pin_badge(site: ChainSummary.Site) -> String:
	if not site.alerts.is_empty() and not site.is_active():
		return "Needs you"
	match site.status:
		ChainSummary.Status.HERE:
			return "Here"
		ChainSummary.Status.MANAGED:
			return "Managed"
		ChainSummary.Status.RENOVATING:
			return "Renovating"
	return CLOSED


## The art state under a shop pin (CityPin.HERE ...): the badge word as a key,
## so the pin picture and its word never disagree.
static func pin_state(site: ChainSummary.Site) -> StringName:
	if not site.alerts.is_empty() and not site.is_active():
		return CityPin.NEEDS
	match site.status:
		ChainSummary.Status.HERE:
			return CityPin.HERE
		ChainSummary.Status.MANAGED:
			return CityPin.MANAGED
		ChainSummary.Status.RENOVATING:
			return CityPin.RENOVATING
	return CityPin.CLOSED


static func signed(amount: int) -> String:
	return ("-" if amount < 0 else "+") + Fmt.money(absi(amount))
