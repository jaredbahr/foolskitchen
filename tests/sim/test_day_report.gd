extends TestCase
## Day report data and standalone UI regressions; no clock or ledger integration.

const REPORT_SCENE: PackedScene = preload("res://src/ui/evening_report.tscn")

var _screen: Control = null
var _next_day_count: int = 0


func after_each() -> void:
	if _screen != null:
		_screen.free()
		_screen = null


func test_totals_and_positive_or_negative_profit() -> void:
	var report: DayReport = _full_report()
	assert_eq(report.total_income(), 1250)
	assert_eq(report.total_costs(), 340)
	assert_eq(report.profit(), 910)
	report.costs[&"rent"] = 2000
	assert_eq(report.profit(), -890)


func test_empty_report_has_zero_totals_and_no_leaders() -> void:
	var report: DayReport = DayReport.new()
	assert_eq(report.total_income(), 0)
	assert_eq(report.total_costs(), 0)
	assert_eq(report.profit(), 0)
	assert_eq(report.best_dish(), &"")
	assert_eq(report.top_leave_reason(), &"")


func test_best_dish_uses_count_then_alphabetical_id() -> void:
	var report: DayReport = DayReport.new()
	report.dishes_sold = {&"tomato_soup": 4, &"burger": 4, &"grilled_cheese": 2}
	assert_eq(report.best_dish(), &"burger")
	report.dishes_sold[&"tomato_soup"] = 5
	assert_eq(report.best_dish(), &"tomato_soup")


func test_top_leave_reason_is_deterministic_on_ties() -> void:
	var report: DayReport = DayReport.new()
	report.leave_reasons = {&"waited_too_long": 3, &"no_table": 3}
	assert_eq(report.top_leave_reason(), &"no_table")
	report.leave_reasons[&"waited_too_long"] = 4
	assert_eq(report.top_leave_reason(), &"waited_too_long")


func test_json_round_trip_restores_typed_ids_and_counts() -> void:
	var original: DayReport = _full_report()
	var encoded: String = JSON.stringify(original.to_dict())
	var decoded: Dictionary = JSON.parse_string(encoded)
	var restored: DayReport = DayReport.from_dict(decoded)
	assert_eq(restored.to_dict(), original.to_dict())
	assert_eq(restored.income[&"sale"], 1200)
	assert_eq(typeof(restored.income.keys()[0]), TYPE_STRING_NAME)
	assert_eq(restored.best_dish(), &"burger")


func test_snapshots_do_not_share_mutable_data() -> void:
	var original: DayReport = _full_report()
	var snapshot: Dictionary = original.to_dict()
	var restored: DayReport = DayReport.from_dict(snapshot)
	snapshot["income"]["sale"] = 0
	snapshot["reviews"].append("A later review")
	assert_eq(original.total_income(), 1250)
	assert_eq(restored.total_income(), 1250)
	assert_eq(original.reviews.size(), 4)
	assert_eq(restored.reviews.size(), 4)


func test_missing_saved_fields_restore_an_empty_report() -> void:
	var report: DayReport = DayReport.from_dict({"day": 9})
	assert_eq(report.day, 9)
	assert_eq(report.profit(), 0)
	assert_true(report.reviews.is_empty())
	assert_true(report.leave_reasons.is_empty())
	assert_true(report.review_cards.is_empty())
	assert_almost_eq(report.reputation_before, 3.0)
	assert_almost_eq(report.reputation_after, 3.0)


func test_review_cards_round_trip_without_sim_cause_ids_or_shared_mutation() -> void:
	var report: DayReport = DayReport.new()
	report.review_cards = [{"stars": 4, "quote": "Fast and tasty", "cause": "too_expensive"}]
	report.today_review_average = 4.0
	report.reputation_before = 3.0
	report.reputation_after = 3.2
	var saved: Dictionary = report.to_dict()
	var cards: Array = saved["review_cards"]
	assert_eq(cards.size(), 1)
	assert_eq(cards[0], {"stars": 4, "quote": "Fast and tasty"})
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored: DayReport = DayReport.from_dict(decoded)
	assert_eq(restored.review_cards, cards)
	assert_almost_eq(restored.today_review_average, 4.0)
	assert_almost_eq(restored.reputation_before, 3.0)
	assert_almost_eq(restored.reputation_after, 3.2)
	cards[0]["quote"] = "Modified snapshot"
	assert_eq(report.review_cards[0]["quote"], "Fast and tasty")
	assert_eq(restored.review_cards[0]["quote"], "Fast and tasty")


func test_ui_review_summary_and_star_quotes_then_clear() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.review_cards = [
		{"stars": 5, "quote": "Wonderful soup"},
		{"stars": 4, "quote": "Nice and cosy"},
		{"stars": 3, "quote": "Okay lunch"},
		{"stars": 2, "quote": "Fourth line is hidden"},
	]
	report.today_review_average = 3.5
	report.reputation_before = 3.2
	report.reputation_after = 3.4
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%ReviewStats") as Label).text, "Today's reviews: 3.5 stars")
	assert_eq((_screen.get_node("%Reputation") as Label).text, "Reputation: 3.2 to 3.4 stars")
	var lines: Node = _screen.get_node("%ReviewRows")
	assert_eq(lines.get_child_count(), 3)
	assert_eq((lines.get_child(0) as Label).text, '5 stars - "Wonderful soup"')
	assert_eq((lines.get_child(2) as Label).text, '3 stars - "Okay lunch"')
	_screen.call("show_report", DayReport.new())
	assert_eq((_screen.get_node("%ReviewStats") as Label).text, "Today's reviews: none")
	assert_eq((_screen.get_node("%Reputation") as Label).text, "Reputation: 3.0 to 3.0 stars")
	assert_eq(lines.get_child_count(), 1)
	assert_eq((lines.get_child(0) as Label).text, "No reviews today")


func test_ui_full_report_then_empty_clears_every_section() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	_screen.call("show_report", _full_report())
	assert_eq((_screen.get_node("%Header") as Label).text, "Day 3: Closed")
	assert_eq((_screen.get_node("%Profit") as Label).text, "$910 profit")
	assert_eq((_screen.get_node("%Guests") as Label).text, "12 served  /  4 lost")
	assert_almost_eq((_screen.get_node("%GuestBar") as ProgressBar).value, 12.0)
	assert_almost_eq((_screen.get_node("%GuestBar") as ProgressBar).max_value, 16.0)
	assert_eq(_screen.get_node("%ReviewRows").get_child_count(), 3)
	assert_eq((_screen.get_node("%ReasonRows").get_child(0) as Label).text, "Waited too long")
	assert_eq((_screen.get_node("%DishRows").get_child(0) as Label).text, "Burger (best seller)")
	_screen.call("show_report", DayReport.new())
	assert_eq(_screen.get_node("%IncomeRows").get_child_count(), 2)
	assert_eq((_screen.get_node("%IncomeRows").get_child(0) as Label).text, "No income today")
	assert_eq((_screen.get_node("%CostRows").get_child(0) as Label).text, "No costs today")
	assert_eq((_screen.get_node("%DishRows").get_child(0) as Label).text, "No dishes sold today")
	assert_eq((_screen.get_node("%Guests") as Label).text, "No guests visited today")
	assert_almost_eq((_screen.get_node("%GuestBar") as ProgressBar).value, 0.0)
	assert_eq((_screen.get_node("%ReasonRows").get_child(0) as Label).text, "No unhappy departures today")
	assert_eq(_screen.get_node("%ReviewRows").get_child_count(), 1)


func test_ui_loss_and_next_day_signal_without_clock_integration() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.costs = {&"rent": 1234}
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%Profit") as Label).text, "-$1,234 profit")
	_screen.connect("next_day_pressed", _on_next_day)
	(_screen.get_node("%NextDay") as Button).pressed.emit()
	assert_eq(_next_day_count, 1)
	assert_not_null(_screen.theme)


func test_ui_report_before_ready_is_preserved_and_connects_once() -> void:
	_screen = REPORT_SCENE.instantiate()
	_screen.call("show_report", _full_report())
	assert_eq((_screen.get_node("%Header") as Label).text, "Day 3: Closed")
	_screen.call("_ready")
	_screen.call("_ready")
	assert_eq((_screen.get_node("%Header") as Label).text, "Day 3: Closed")
	assert_eq((_screen.get_node("%Profit") as Label).text, "$910 profit")
	_screen.connect("next_day_pressed", _on_next_day)
	(_screen.get_node("%NextDay") as Button).pressed.emit()
	assert_eq(_next_day_count, 1)


func _full_report() -> DayReport:
	var report: DayReport = DayReport.new()
	report.day = 3
	report.income = {&"sale": 1200, &"tip": 50}
	report.costs = {&"ingredients": 140, &"rent": 200}
	report.dishes_sold = {&"tomato_soup": 2, &"burger": 8}
	report.customers_served = 12
	report.customers_lost = 4
	report.leave_reasons = {&"no_table": 1, &"waited_too_long": 3}
	report.reviews = ["Lovely soup", "Cosy place", "Great burger", "Fourth quote is hidden"]
	return report


func _on_next_day() -> void:
	_next_day_count += 1
