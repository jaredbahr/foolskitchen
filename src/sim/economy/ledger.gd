class_name Ledger
extends RefCounted
## Whole-unit cash ledger with transaction detail and bounded daily history.

const SALE: StringName = &"sale"
const TIP: StringName = &"tip"
const INGREDIENTS: StringName = &"ingredients"
const WAGES: StringName = &"wages"
const RENT: StringName = &"rent"
const UPGRADES: StringName = &"upgrades"
const OTHER: StringName = &"other"
const HISTORY_DAYS: int = 30

var cash: int = 0
## Archived day -> category totals. Treat returned history as read-only.
var history: Dictionary[int, Dictionary] = {}
var _entries: Array[Dictionary] = []
## Gross flows are retained separately so refunds cannot change old reports.
var _history_income: Dictionary[int, int] = {}
var _history_costs: Dictionary[int, int] = {}


## Applies a signed movement and records why it happened on the given day.
func record(day: int, amount: int, category: StringName, note: String = "") -> void:
	cash += amount
	_entries.append({"day": day, "amount": amount, "category": category, "note": note})


## Returns category -> signed amount, including archived entries for this day.
func day_totals(day: int) -> Dictionary:
	var totals: Dictionary = history.get(day, {}).duplicate(true)
	for entry: Dictionary in _entries:
		if int(entry["day"]) == day:
			var category: StringName = entry["category"]
			totals[category] = int(totals.get(category, 0)) + int(entry["amount"])
	return totals


## Returns the day's incoming cash before subtracting any outgoing movements.
func day_income(day: int) -> int:
	var total: int = _history_income.get(day, 0)
	for entry: Dictionary in _entries:
		if int(entry["day"]) == day:
			total += maxi(0, int(entry["amount"]))
	return total


## Returns outgoing cash as a positive number, including archived movements.
func day_costs(day: int) -> int:
	var total: int = _history_costs.get(day, 0)
	for entry: Dictionary in _entries:
		if int(entry["day"]) == day:
			total -= mini(0, int(entry["amount"]))
	return total


## Returns income minus costs for the day.
func day_profit(day: int) -> int:
	return day_income(day) - day_costs(day)


## Returns independent copies of the unpruned entries in recording order.
func entries_for_day(day: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if int(entry["day"]) == day:
			found.append(entry.duplicate(true))
	return found


## Archives older detail without changing cash, retaining the last 30 days.
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


## Returns independent, JSON-safe state, including the archived graph totals.
func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		entries.append({"day": int(entry["day"]), "amount": int(entry["amount"]),
			"category": String(entry["category"]), "note": String(entry["note"])})
	var archived: Dictionary = {}
	var income: Dictionary = {}
	var costs: Dictionary = {}
	for day: int in history:
		var totals: Dictionary = {}
		for category: StringName in history[day]:
			totals[String(category)] = int(history[day][category])
		archived[str(day)] = totals
		income[str(day)] = int(_history_income.get(day, 0))
		costs[str(day)] = int(_history_costs.get(day, 0))
	return {"cash": cash, "entries": entries, "history": archived,
		"history_income": income, "history_costs": costs}


## Restores a snapshot without replaying cash changes or sharing its data.
static func from_dict(d: Dictionary) -> Ledger:
	var ledger: Ledger = Ledger.new()
	ledger.cash = int(d.get("cash", 0))
	for entry: Dictionary in d.get("entries", []):
		ledger._entries.append({"day": int(entry["day"]), "amount": int(entry["amount"]),
			"category": StringName(entry["category"]), "note": String(entry.get("note", ""))})
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
