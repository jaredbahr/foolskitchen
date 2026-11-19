class_name ChainSummary
extends RefCounted
## One line of facts per site for the chain view (docs/CITY_MAP.md section 4):
## status, yesterday's money, stars, Golden Ladles, manager, team mood, the
## exact result tonight's close will book for an away site, and what needs the
## owner. Pure and deterministic: it reads a SiteBook, the ledger and each
## site's per-site sections (a frozen site's own copy; the active site's live
## capture, handed in by the caller), so one code path covers both. Nothing is
## saved; words live in the UI (ChainText), never here (rule 11).

## Where a site stands this morning.
## HERE: the active site. MANAGED: away, and its manager runs it tonight.
## CLOSED: away and shut (no manager, or one with no day to go on).
## RENOVATING: away and still under renovation.
enum Status { HERE, MANAGED, CLOSED, RENOVATING }

## What needs the owner, most urgent first (the enum order is the sort order).
## NOT_STAFFED: no cook or no server, so it cannot open.
## NO_MANAGER: away, ready and closed with nobody to run it; it still pays.
## MANAGER_NEEDS_A_DAY: away with a manager who has no day of yours to go on.
## LOSING_MONEY: its recent in-person days averaged a loss.
## BOOKING_LAPSES: an away group booking lapses at tonight's close.
## UNHAPPY_TEAM: someone on its floor staff is at the lowest mood.
## READY_TO_OPEN: a bought site, done renovating, that has never served a day.
enum Alert { NOT_STAFFED, NO_MANAGER, MANAGER_NEEDS_A_DAY, LOSING_MONEY, BOOKING_LAPSES, UNHAPPY_TEAM,
	READY_TO_OPEN }

## A floor worker at this mood or below counts as unhappy (StaffGrowth moods
## run 1 to 3; 0 means they are leaving).
const UNHAPPY_MOOD: int = 1


## The facts for one site. Money is whole dollars.
class Site extends RefCounted:
	var id: StringName
	var lot: StringName
	## The site's own name, else its menu's restaurant name, else a fallback
	## (AwaySites.display_name). The active site's comes from its live menu.
	var name: String = ""
	var status: Status = Status.CLOSED
	var renovation_days: int = 0
	## The manager named on its book row when they are a valid Manager there.
	var manager_id: StringName = &""
	var manager_name: String = ""
	## 0 when there is no valid manager.
	var manager_skill: int = 0
	## The share of the in-person average the manager keeps (0 without one).
	var manager_rate: float = 0.0
	## The rolling review stars; NAN before the site has closed a day.
	var stars: float = NAN
	var golden_ladles: int = 0
	## The mean mood of the floor staff (managers excluded), NAN with none.
	var mood: float = NAN
	## The lowest mood among the floor staff, 0 with none.
	var lowest_mood: int = 0
	var staffed: bool = false
	## In-person days on record (the manager's formula reads these).
	var recorded_days: int = 0
	## The mean dish profit of the last `history_days` recorded days, or 0.
	var recent_mean: int = 0
	## Yesterday's gross takings from guests where the owner worked there.
	var yesterday_takings: int = 0
	## Yesterday's net earnings while away (after the manager), else 0.
	var yesterday_earnings: int = 0
	## The signed total tonight's close books for this away site (earnings,
	## or rent and wages, and any booking refund). 0 for the active site.
	var tonight: int = 0
	## Alerts, most urgent first.
	var alerts: Array[Alert] = []

	func is_active() -> bool:
		return status == Status.HERE


## One Site per site, in SiteBook order (the active site first).
## `active_sections`: the active site's per-site sections as saved (for
## example SaveSystem.capture_sections(SiteSections.PER_SITE)); `active_name`:
## its restaurant name. `today` is the current day: "yesterday" is the day
## before, and tonight's preview is AwaySites.plan_close for today, the same
## call the close makes, so it matches what the evening report books unless
## something changes before then.
static func build(book: SiteBook, active_sections: Dictionary, active_name: String, ledger: Ledger,
		today: int, home_rent: int, tuning: SiteManagerTuning, booking_tuning: BookingTuning,
		lots: Array[LotDef] = [], rent_multiplier: float = 1.0) -> Array[Site]:
	var result: Array[Site] = []
	if book == null:
		return result
	var plans: Dictionary[StringName, Dictionary] = {}
	for plan: Dictionary in AwaySites.plan_close(book, today, home_rent, tuning, booking_tuning, lots,
			rent_multiplier):
		plans[StringName(plan["site"])] = plan
	for id: StringName in book.site_ids():
		var active: bool = id == book.active_id
		var sections: Dictionary = _as_json(active_sections) if active else book.frozen_sections(id)
		result.append(_site(book, id, active, sections, active_name, plans.get(id, {}), ledger, today, tuning))
	return result


static func _site(book: SiteBook, id: StringName, active: bool, sections: Dictionary, active_name: String,
		plan: Dictionary, ledger: Ledger, today: int, tuning: SiteManagerTuning) -> Site:
	var site: Site = Site.new()
	site.id = id
	site.lot = book.lot_id(id)
	site.renovation_days = book.renovation_days_left(id)
	site.name = book.site_name(id)
	if site.name.is_empty():
		site.name = active_name.strip_edges() if active and not active_name.strip_edges().is_empty() \
			else AwaySites.display_name(book, id)
	var staff: Dictionary = _section(sections, "staff")
	var roster: StaffRoster = StaffRoster.new()
	var roster_ok: bool = not staff.is_empty() and roster.from_dict(staff)
	site.manager_skill = AwaySites.manager_skill(staff, book.manager(id))
	if site.manager_skill > 0:
		site.manager_id = book.manager(id)
		site.manager_name = SiteMorning.manager_name(staff, site.manager_id)
		site.manager_rate = tuning.rate_for(site.manager_skill) if tuning != null and tuning.is_valid() else 0.0
	if roster_ok:
		site.staffed = roster.is_staffed()
		_read_mood(site, roster)
	else:
		# A copy saved without a staff section loads the starter team.
		site.staffed = staff.is_empty()
	var history: Dictionary = _section(sections, "business_history")
	site.recorded_days = AwaySites.recorded_days(history)
	site.recent_mean = recent_mean(history, tuning)
	site.stars = _stars(_section(sections, "reviews")) if site.recorded_days > 0 else NAN
	site.golden_ladles = _ladles(_section(sections, "critic"))
	site.yesterday_takings = SiteMorning.takings(ledger, today - 1, id)
	site.yesterday_earnings = SiteMorning.away_earnings(ledger, today - 1, id)
	if active:
		site.status = Status.HERE
	elif site.renovation_days > 0:
		site.status = Status.RENOVATING
	elif plan.get("status") == AwaySites.MANAGED:
		site.status = Status.MANAGED
	else:
		site.status = Status.CLOSED
	for movement: Dictionary in plan.get("movements", []):
		site.tonight += int(movement.get("amount", 0))
	site.alerts = _alerts(site, active, plan)
	return site


## Alerts for a built site, most urgent first.
static func _alerts(site: Site, active: bool, plan: Dictionary) -> Array[Alert]:
	var alerts: Array[Alert] = []
	if not site.staffed:
		alerts.append(Alert.NOT_STAFFED)
	if not active and site.renovation_days == 0 and site.manager_skill == 0:
		alerts.append(Alert.NO_MANAGER)
	if not active and bool(plan.get("no_history", false)):
		alerts.append(Alert.MANAGER_NEEDS_A_DAY)
	if site.recorded_days > 0 and site.recent_mean < 0:
		alerts.append(Alert.LOSING_MONEY)
	if int(plan.get("refund", 0)) > 0:
		alerts.append(Alert.BOOKING_LAPSES)
	if site.lowest_mood > 0 and site.lowest_mood <= UNHAPPY_MOOD:
		alerts.append(Alert.UNHAPPY_TEAM)
	if site.lot != SiteBook.HOME_LOT and site.renovation_days == 0 and site.recorded_days == 0:
		alerts.append(Alert.READY_TO_OPEN)
	return alerts


## The mean recorded dish profit over the last `tuning.history_days` recorded
## days (the figure a manager's earnings scale), rounded; 0 with none.
static func recent_mean(history: Dictionary, tuning: SiteManagerTuning) -> int:
	if history.is_empty() or tuning == null or not tuning.is_valid():
		return 0
	var decoded: BusinessHistory = BusinessHistory.new()
	if not decoded.restore(history):
		return 0
	var recorded: Array[int] = []
	for row: Dictionary in decoded.summaries():
		if bool(row.get("dish_profit_recorded", false)):
			recorded.append(int(row.get("dish_profit", 0)))
	var count: int = mini(recorded.size(), tuning.history_days)
	if count == 0:
		return 0
	var total: int = 0
	for index: int in range(recorded.size() - count, recorded.size()):
		total += recorded[index]
	return roundi(float(total) / float(count))


static func _read_mood(site: Site, roster: StaffRoster) -> void:
	var total: int = 0
	var count: int = 0
	for member: StaffMember in roster.members():
		if member.role == StaffMember.MANAGER:
			continue
		var mood: int = member.growth_state().mood
		total += mood
		count += 1
		if site.lowest_mood == 0 or mood < site.lowest_mood:
			site.lowest_mood = mood
	site.mood = float(total) / float(count) if count > 0 else NAN


static func _stars(reviews: Dictionary) -> float:
	var book: ReputationBook = ReputationBook.new()
	return book.average() if not reviews.is_empty() and book.from_dict(reviews) else NAN


static func _ladles(critic: Dictionary) -> int:
	if critic.is_empty():
		return 0
	var decoded: FoodCritic = FoodCritic.new()
	return decoded.golden_ladles if decoded.from_dict(critic) else 0


static func _section(sections: Dictionary, key: String) -> Dictionary:
	var value: Variant = sections.get(key, {})
	return value if value is Dictionary else {}


## The live capture in the shape a saved file gives (numbers as floats, no
## StringNames), so every decoder sees what it sees on a load.
static func _as_json(sections: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(sections))
	return parsed if parsed is Dictionary else {}
