class_name DayReport
extends RefCounted
## Plain end-of-day results, independent of the ledger, clock and scene tree.

var day: int = 1
var income: Dictionary = {}
var costs: Dictionary = {}
## Transient first-advance introduction, supplied by the closing session.
var loan_first_advance: bool = false
var dishes_sold: Dictionary = {}
var customers_served: int = 0
var customers_lost: int = 0
var leave_reasons: Dictionary = {}
var reviews: Array[String] = []
## Worst observed floor condition, already mapped to a player-facing word.
var cleanliness_label: String = ""
## Player-facing reviews for this day. Each card has an integer stars (1-5)
## and a quote; simulation cause ids are deliberately excluded.
var review_cards: Array[Dictionary] = []
var today_review_average: float = 0.0
var reputation_before: float = 3.0
var reputation_after: float = 3.0
## Day-close owner XP with happy_xp, profit_xp, review_xp and total_xp.
var owner_xp_breakdown: Dictionary = {}
var owner_level_before: int = 1
var owner_level_after: int = 1
## Player-facing unlock names, supplied by the caller rather than raw ids.
var owner_unlocks: Array[String] = []


## Returns income across all categories in whole currency units.
func total_income() -> int:
	return _sum(income)


## Returns costs as a positive amount in whole currency units.
func total_costs() -> int:
	return _sum(costs)


## Returns income minus costs; a loss is negative.
func profit() -> int:
	return total_income() - total_costs()


## Returns the most-sold recipe, breaking ties by its alphabetical id.
func best_dish() -> StringName:
	return _highest_count(dishes_sold)


## Returns the leading departure reason, or an empty id if there are none.
func top_leave_reason() -> StringName:
	return _highest_count(leave_reasons)


## Returns a detached JSON-compatible snapshot using string keys.
func to_dict() -> Dictionary:
	var cards: Array[Dictionary] = []
	for card: Dictionary in review_cards:
		cards.append(_public_review_card(card))
	return {
		"day": day,
		"income": _string_counts(income),
		"costs": _string_counts(costs),
		"loan_first_advance": loan_first_advance,
		"dishes_sold": _string_counts(dishes_sold),
		"customers_served": customers_served,
		"customers_lost": customers_lost,
		"leave_reasons": _string_counts(leave_reasons),
		"reviews": reviews.duplicate(),
		"cleanliness_label": cleanliness_label,
		"review_cards": cards,
		"today_review_average": today_review_average,
		"reputation_before": reputation_before,
		"reputation_after": reputation_after,
		"owner_xp_breakdown": _owner_xp(owner_xp_breakdown),
		"owner_level_before": owner_level_before,
		"owner_level_after": owner_level_after,
		"owner_unlocks": owner_unlocks.duplicate(),
	}


## Restores a snapshot, including JSON's string keys and numeric values.
static func from_dict(data: Dictionary) -> DayReport:
	var report: DayReport = DayReport.new()
	report.day = int(data.get("day", 1))
	report.income = _name_counts(data.get("income", {}))
	report.costs = _name_counts(data.get("costs", {}))
	var saved_loan_notice: Variant = data.get("loan_first_advance", false)
	report.loan_first_advance = saved_loan_notice is bool and saved_loan_notice
	report.dishes_sold = _name_counts(data.get("dishes_sold", {}))
	report.customers_served = int(data.get("customers_served", 0))
	report.customers_lost = int(data.get("customers_lost", 0))
	report.leave_reasons = _name_counts(data.get("leave_reasons", {}))
	var saved_reviews: Variant = data.get("reviews", [])
	if saved_reviews is Array:
		for quote: Variant in saved_reviews:
			report.reviews.append(str(quote))
	report.cleanliness_label = str(data.get("cleanliness_label", ""))
	var saved_cards: Variant = data.get("review_cards", [])
	if saved_cards is Array:
		for card: Variant in saved_cards:
			if card is Dictionary:
				report.review_cards.append(_public_review_card(card as Dictionary))
	report.today_review_average = float(data.get("today_review_average", 0.0))
	report.reputation_before = float(data.get("reputation_before", 3.0))
	report.reputation_after = float(data.get("reputation_after", 3.0))
	report.owner_xp_breakdown = _owner_xp(data.get("owner_xp_breakdown", {}))
	report.owner_level_before = maxi(1, int(data.get("owner_level_before", 1)))
	report.owner_level_after = maxi(1, int(data.get("owner_level_after", 1)))
	var saved_unlocks: Variant = data.get("owner_unlocks", [])
	if saved_unlocks is Array:
		for name: Variant in saved_unlocks:
			if name is String:
				report.owner_unlocks.append(name)
	return report


## Copy only display fields, so a sim result cannot leak its cause into a save.
static func _public_review_card(card: Dictionary) -> Dictionary:
	return {
		"stars": clampi(int(card.get("stars", 1)), 1, 5),
		"quote": str(card.get("quote", "")),
	}


## Only known numeric display fields survive a report snapshot.
static func _owner_xp(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	var amounts: Dictionary = value
	for key: String in ["happy_xp", "profit_xp", "review_xp", "total_xp"]:
		if amounts.has(key):
			result[key] = maxi(0, int(amounts[key]))
	return result


static func _sum(counts: Dictionary) -> int:
	var total: int = 0
	for value: Variant in counts.values():
		total += int(value)
	return total


static func _highest_count(counts: Dictionary) -> StringName:
	var best: StringName = &""
	var best_count: int = 0
	var found: bool = false
	for key: Variant in counts:
		var id: StringName = StringName(str(key))
		var count: int = int(counts[key])
		if not found or count > best_count or (count == best_count and String(id) < String(best)):
			best = id
			best_count = count
			found = true
	return best


static func _string_counts(counts: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in counts:
		result[str(key)] = int(counts[key])
	return result


static func _name_counts(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Dictionary:
		for key: Variant in value:
			result[StringName(str(key))] = int(value[key])
	return result
