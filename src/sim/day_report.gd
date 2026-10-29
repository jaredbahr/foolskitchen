class_name DayReport
extends RefCounted
## Plain end-of-day results, independent of the ledger, clock and scene tree.

const NON_OPERATING_CATEGORIES: Array[StringName] = [
	Ledger.BANK_LOAN, Ledger.LOAN_INTEREST, Ledger.LOAN_REPAYMENT,
	Ledger.MILESTONE_BONUS,
]
const MAX_MILESTONE_REWARD: int = 1000000

var day: int = 1
## Snapshot of the name used for this service day and its review heading.
var restaurant_name: String = MenuSettings.DEFAULT_NAME
var income: Dictionary = {}
var costs: Dictionary = {}
## Transient first-advance introduction, supplied by the closing session.
var loan_first_advance: bool = false
var dishes_sold: Dictionary = {}
var customers_served: int = 0
var dish_quality_count: int = 0
var dish_quality_average: float = 0.0
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
## Player-facing tips for what this level-up changed (authored data text).
var owner_tips: Array[String] = []
## Player-facing goal names and rewards completed on this day; never contains IDs.
var milestones_reached: Array[Dictionary] = []
## Player-facing "Low stock" sentences (StockAlerts): what ran out today and
## when, then ingredients below tomorrow's target or expiring tomorrow.
var low_stock: Array[String] = []


## Returns income across all categories in whole currency units.
func total_income() -> int:
	return _sum(income)


func record_dish_quality(orders: Array[Order]) -> void:
	dish_quality_count = 0
	var total: float = 0.0
	for order: Order in orders:
		if order.state == Order.State.DELIVERED:
			total += order.quality
			dish_quality_count += 1
	dish_quality_average = total / dish_quality_count if dish_quality_count > 0 else 0.0


func food_quality_text() -> String:
	if dish_quality_count == 0:
		return "Food quality: no dishes served"
	var word: String = "poor"
	if dish_quality_average >= 0.8:
		word = "excellent"
	elif dish_quality_average >= 0.6:
		word = "good"
	elif dish_quality_average >= 0.4:
		word = "fair"
	return "Food quality: %s (%.1f / 5)" % [word, dish_quality_average * 5.0]


## Returns costs as a positive amount in whole currency units.
func total_costs() -> int:
	return _sum(costs)


## Full financial cash movement, including loans, interest and repayments.
## Kept for existing accounting callers and decoded historical reports.
func profit() -> int:
	return total_income() - total_costs()


## Shop performance before financing. Borrowing cannot turn a loss into profit,
## and paying back principal does not make the shop's operations look worse.
func operating_profit() -> int:
	return _operating_sum(income) - _operating_sum(costs)


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
	var milestones: Array[Dictionary] = public_milestones(milestones_reached)
	return {
		"day": day,
		"restaurant_name": restaurant_name,
		"income": _string_counts(income),
		"costs": _string_counts(costs),
		"loan_first_advance": loan_first_advance,
		"dishes_sold": _string_counts(dishes_sold),
		"customers_served": customers_served,
		"dish_quality_count": dish_quality_count,
		"dish_quality_average": dish_quality_average,
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
		"owner_tips": owner_tips.duplicate(),
		"milestones_reached": milestones,
		"low_stock": low_stock.duplicate(),
	}


## Restores a snapshot, including JSON's string keys and numeric values.
static func from_dict(data: Dictionary) -> DayReport:
	var report: DayReport = DayReport.new()
	report.day = int(data.get("day", 1))
	var saved_name: Variant = data.get("restaurant_name", MenuSettings.DEFAULT_NAME)
	if saved_name is String:
		var normalized: String = MenuSettings.normalized_restaurant_name(saved_name)
		if not normalized.is_empty():
			report.restaurant_name = normalized
	report.income = _name_counts(data.get("income", {}))
	report.costs = _name_counts(data.get("costs", {}))
	var saved_loan_notice: Variant = data.get("loan_first_advance", false)
	report.loan_first_advance = saved_loan_notice is bool and saved_loan_notice
	report.dishes_sold = _name_counts(data.get("dishes_sold", {}))
	report.customers_served = int(data.get("customers_served", 0))
	report.dish_quality_count = maxi(0, int(data.get("dish_quality_count", 0)))
	report.dish_quality_average = clampf(float(data.get("dish_quality_average", 0.0)), 0.0, 1.0)
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
	var saved_tips: Variant = data.get("owner_tips", [])
	if saved_tips is Array:
		for tip: Variant in saved_tips:
			if tip is String:
				report.owner_tips.append(tip)
	report.milestones_reached = public_milestones(data.get("milestones_reached", []))
	var saved_low_stock: Variant = data.get("low_stock", [])
	if saved_low_stock is Array:
		for line: Variant in saved_low_stock:
			if line is String:
				report.low_stock.append(line)
	return report


## Copy only display fields, so a sim result cannot leak its cause into a save.
static func _public_review_card(card: Dictionary) -> Dictionary:
	return {
		"stars": clampi(int(card.get("stars", 1)), 1, 5),
		"quote": str(card.get("quote", "")),
	}


## Keep report snapshots player-facing; raw milestone IDs and conditions are not saved here.
static func public_milestones(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for item: Variant in value:
		if not item is Dictionary:
			continue
		var row: Dictionary = item
		var title_value: Variant = row.get("title")
		if not title_value is String:
			continue
		var title: String = str(title_value).strip_edges()
		var reward_xp: Variant = row.get("reward_xp")
		var reward_cash: Variant = row.get("reward_cash")
		if title.is_empty() or not _whole_in_range(reward_xp, 0, MAX_MILESTONE_REWARD) \
				or not _whole_in_range(reward_cash, 0, MAX_MILESTONE_REWARD):
			continue
		result.append({
			"title": title,
			"reward_xp": int(reward_xp),
			"reward_cash": int(reward_cash),
		})
	return result


## Returns -1 for a malformed optional display field so direct UI callers can omit it.
static func milestone_xp(value: Variant) -> int:
	if not _whole_in_range(value, 0, OwnerProgress.MAX_TOTAL_XP):
		return -1
	return int(value)


static func _whole_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floorf(number) == number


## Only known numeric display fields survive a report snapshot.
static func _owner_xp(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	var amounts: Dictionary = value
	for key: String in ["happy_xp", "profit_xp", "review_xp", "milestone_xp", "total_xp"]:
		if amounts.has(key):
			if key == "milestone_xp":
				var xp: int = milestone_xp(amounts[key])
				if xp < 0:
					continue
				result[key] = xp
				continue
			result[key] = maxi(0, int(amounts[key]))
	return result


static func _sum(counts: Dictionary) -> int:
	var total: int = 0
	for value: Variant in counts.values():
		total += int(value)
	return total


static func _operating_sum(counts: Dictionary) -> int:
	var total: int = 0
	for key: Variant in counts:
		if not NON_OPERATING_CATEGORIES.has(StringName(str(key))):
			total += int(counts[key])
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
