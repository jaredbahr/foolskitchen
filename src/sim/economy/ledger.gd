class_name Ledger
extends RefCounted
## Whole-unit cash ledger with transaction detail and bounded daily history.

const SALE: StringName = &"sale"
const TIP: StringName = &"tip"
const INGREDIENTS: StringName = &"ingredients"
const WAGES: StringName = &"wages"
const RENT: StringName = &"rent"
const UPGRADES: StringName = &"upgrades"
const BANK_LOAN: StringName = &"bank_loan"
const LOAN_INTEREST: StringName = &"loan_interest"
const LOAN_REPAYMENT: StringName = &"loan_repayment"
const EARLY_LOAN_REPAYMENT: StringName = &"early_loan_repayment"
const EARLY_REPAYMENT_NOTE: String = "Loan repaid early"
const MILESTONE_BONUS: StringName = &"milestone_bonus"
const WEEKLY_CHALLENGE_BONUS: StringName = &"weekly_challenge_bonus"
## Opening-week goal rewards (#494): one entry per goal, booked when it is met.
const OPENING_WEEK_BONUS: StringName = &"opening_week_bonus"
const BREAKAGES: StringName = &"breakages"
const CAT_FOOD: StringName = &"cat_food"
## Customer advances are cash movements, never earned operating income.
const BOOKING_DEPOSIT: StringName = &"booking_deposit"
const BOOKING_REFUND: StringName = &"booking_refund"
## Small service event choices (#495): a tip, a comped drink, a busker.
const SERVICE_EVENT: StringName = &"service_event"
const OTHER: StringName = &"other"
## Multi-site money (FK-087). All four are non-operating (DayReport): they move
## the owner's cash but never the active site's operating profit.
const AWAY_SITE_INCOME: StringName = &"away_site_income"
const AWAY_SITE_RENT: StringName = &"away_site_rent"
const LOT_PURCHASE: StringName = &"lot_purchase"
const RENOVATION: StringName = &"renovation"
const HISTORY_DAYS: int = 30
## The site an entry belongs to when none is named: the starter shop. Equal to
## SiteBook.HOME_ID (a test keeps them together); kept here so the economy
## model does not depend on the sites model. Saves omit it.
const HOME_SITE: StringName = &"home"
## Site ids follow SiteBook's rules: 1-40 of a-z, 0-9 and "_".
const MAX_SITE_ID_LENGTH: int = 40
## Passed as a query's site: every site's entries (the owner's whole books).
const ALL_SITES: StringName = &""

var cash: int = 0
## Archived day -> category totals. Treat returned history as read-only.
var history: Dictionary[int, Dictionary] = {}
## Each entry: {day: int, amount: int, category: StringName, note: String,
## site: StringName}. The site is the one that made it (FK-087).
var _entries: Array[Dictionary] = []
## Gross flows are retained separately so refunds cannot change old reports.
var _history_income: Dictionary[int, int] = {}
var _history_costs: Dictionary[int, int] = {}


## Applies a signed movement and records why it happened on the given day and
## which site made it. Cash always moves; an invalid site id is a caller bug
## (Economy validates its active site) and is booked to the home site.
func record(day: int, amount: int, category: StringName, note: String = "",
		site: StringName = HOME_SITE) -> void:
	if not is_valid_site(site):
		push_error("Ledger entry with an invalid site id; booked to the home site")
		site = HOME_SITE
	cash += amount
	_entries.append({"day": day, "amount": amount, "category": category, "note": note, "site": site})


## True for a usable site id: the same rules as SiteBook ids.
static func is_valid_site(id: StringName) -> bool:
	var text: String = String(id)
	if text.is_empty() or text.length() > MAX_SITE_ID_LENGTH:
		return false
	for character: String in text:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") \
				and character != "_":
			return false
	return true


## The queries below take an optional site. ALL_SITES (the default) reads the
## whole books, including archived days. A named site reads only that site's
## unpruned entries: archived days keep no per-site split, and per-site
## readers only ask about today, which is never archived.
func _counts(entry: Dictionary, day: int, site: StringName) -> bool:
	return int(entry["day"]) == day and (site == ALL_SITES or entry["site"] == site)


## Returns category -> signed amount, including archived entries for this day.
func day_totals(day: int, site: StringName = ALL_SITES) -> Dictionary:
	var totals: Dictionary = history.get(day, {}).duplicate(true) if site == ALL_SITES else {}
	for entry: Dictionary in _entries:
		if _counts(entry, day, site):
			var category: StringName = entry["category"]
			totals[category] = int(totals.get(category, 0)) + int(entry["amount"])
	return totals


## Returns the day's incoming cash before subtracting any outgoing movements.
func day_income(day: int, site: StringName = ALL_SITES) -> int:
	var total: int = _history_income.get(day, 0) if site == ALL_SITES else 0
	for entry: Dictionary in _entries:
		if _counts(entry, day, site):
			total += maxi(0, int(entry["amount"]))
	return total


## Returns outgoing cash as a positive number, including archived movements.
func day_costs(day: int, site: StringName = ALL_SITES) -> int:
	var total: int = _history_costs.get(day, 0) if site == ALL_SITES else 0
	for entry: Dictionary in _entries:
		if _counts(entry, day, site):
			total -= mini(0, int(entry["amount"]))
	return total


## Returns income minus costs for the day.
func day_profit(day: int, site: StringName = ALL_SITES) -> int:
	return day_income(day, site) - day_costs(day, site)


## Returns independent copies of the unpruned entries in recording order.
func entries_for_day(day: int, site: StringName = ALL_SITES) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if _counts(entry, day, site):
			found.append(entry.duplicate(true))
	return found


## Archives older detail without changing cash, retaining the last 30 days.
## Archived totals are the owner's whole books (cash flow), not split by site.
func prune_before(day: int) -> void:
	var retained: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		var entry_day: int = int(entry["day"])
		if entry_day >= day:
			retained.append(entry)
			continue
		var category: StringName = entry["category"]
		var amount: int = int(entry["amount"])
		var totals: Dictionary = history.get(entry_day, {})
		totals[category] = int(totals.get(category, 0)) + amount
		history[entry_day] = totals
		_history_income[entry_day] = int(_history_income.get(entry_day, 0)) + maxi(0, amount)
		_history_costs[entry_day] = int(_history_costs.get(entry_day, 0)) - mini(0, amount)
	_entries = retained
	for archived_day: int in history.keys():
		if archived_day < day - HISTORY_DAYS:
			history.erase(archived_day)
			_history_income.erase(archived_day)
			_history_costs.erase(archived_day)


## Returns independent state; decimal strings preserve int64 values through JSON.
## A home-site entry has no "site" key, so a one-site game saves as before.
func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		var saved: Dictionary = {"day": str(entry["day"]), "amount": str(entry["amount"]),
			"category": String(entry["category"]), "note": String(entry["note"])}
		if entry["site"] != HOME_SITE:
			saved["site"] = String(entry["site"])
		entries.append(saved)
	var archived: Dictionary = {}
	var income: Dictionary = {}
	var costs: Dictionary = {}
	for day: int in history:
		var totals: Dictionary = {}
		for category: StringName in history[day]:
			totals[String(category)] = str(history[day][category])
		archived[str(day)] = totals
		income[str(day)] = str(_history_income.get(day, 0))
		costs[str(day)] = str(_history_costs.get(day, 0))
	return {"cash": str(cash), "entries": entries, "history": archived,
		"history_income": income, "history_costs": costs}


## Restores a snapshot without replaying cash changes or sharing its data.
## An entry without "site" (every save before FK-087 part 1) is the home
## site's. Returns null when an entry names an invalid site.
static func from_dict(d: Dictionary) -> Ledger:
	var ledger: Ledger = Ledger.new()
	ledger.cash = int(d.get("cash", 0))
	for entry: Dictionary in d.get("entries", []):
		var site_value: Variant = entry.get("site", String(HOME_SITE))
		if not site_value is String or not is_valid_site(StringName(site_value)):
			return null
		ledger._entries.append({"day": int(entry["day"]), "amount": int(entry["amount"]),
			"category": StringName(entry["category"]), "note": String(entry.get("note", "")),
			"site": StringName(site_value)})
	var archived: Dictionary = d.get("history", {})
	var income: Dictionary = d.get("history_income", {})
	var costs: Dictionary = d.get("history_costs", {})
	for day_key: Variant in archived:
		var day: int = int(day_key)
		var totals: Dictionary = {}
		for category: Variant in archived[day_key]:
			totals[StringName(category)] = int(archived[day_key][category])
		ledger.history[day] = totals
		ledger._history_income[day] = int(income.get(str(day), 0))
		ledger._history_costs[day] = int(costs.get(str(day), 0))
	return ledger
