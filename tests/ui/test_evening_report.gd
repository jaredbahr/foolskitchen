extends TestCase
## Closing reports use their historical name, independently of the live menu.

const REPORT: PackedScene = preload("res://src/ui/evening_report.tscn")
var _report: Control


func before_each() -> void:
	_report = REPORT.instantiate() as Control


func after_each() -> void:
	_report.free()


func test_food_quality_line_displays_average_and_empty_day_in_plain_words() -> void:
	var day: DayReport = DayReport.new()
	day.dish_quality_count = 2
	day.dish_quality_average = 0.68
	_report.call("show_report", day)
	assert_eq((_report.get_node("%FoodQuality") as Label).text, "Food quality: good (3.4 / 5)")
	_report.call("show_report", DayReport.new())
	assert_eq((_report.get_node("%FoodQuality") as Label).text, "Food quality: no dishes served")


func test_haggle_note_uses_actual_saving_and_is_not_serialized_or_reused() -> void:
	var day: DayReport = DayReport.new()
	day.stock_values_recorded = true
	day.stock_bought_recorded = true
	day.stock_bought = 19
	day.haggle_percent = 6
	day.haggle_saved = 1
	_report.call("show_report", day)
	var rows: Node = _report.get_node("%StockRows")
	assert_eq((rows.get_child(0) as Label).text, "Stock bought today")
	assert_eq((rows.get_child(1) as Label).text, "$19 (haggle saved $1)")
	assert_false(day.to_dict().has("haggle_percent"))
	_report.call("show_report", DayReport.new())
	assert_false((rows.get_child(1) as Label).text.contains("haggle"))


func test_visitor_breakdown_shows_plain_names_counts_moods_and_clears_on_empty() -> void:
	var day: DayReport = DayReport.new()
	day.visitor_breakdown = [
		{"name": "Students", "count": 2, "average_mood": 0.35},
		{"name": "Families", "count": 2, "average_mood": 0.34},
		{"name": "Regulars", "count": 3, "average_mood": 0.6},
	]
	_report.call("show_report", day)
	var label: Label = _report.get_node("%VisitorBreakdown") as Label
	assert_eq(label.text, "Regulars 3 (happy) · Families 2 (unhappy) · Students 2 (neutral)")
	assert_true(label.visible)
	assert_eq(day.visitor_breakdown[0]["name"], "Students", "display sorting does not mutate report data")
	_report.call("show_report", DayReport.from_dict({"customers_served": 4}))
	assert_eq(label.text, "")
	assert_false(label.visible, "older reports have no visitor data")
	_report.call("show_report", DayReport.new())
	assert_false(label.visible, "there is no breakdown without guests")


func test_booking_cash_rows_name_deposit_refund_and_applied_advance() -> void:
	var day: DayReport = DayReport.new()
	day.income[Ledger.BOOKING_DEPOSIT] = 30
	_report.call("show_report", day)
	assert_eq((_report.get_node("%IncomeRows").get_child(0) as Label).text, "Booking deposit")
	day = DayReport.new()
	day.income[Ledger.SALE] = 120
	day.costs[Ledger.BOOKING_DEPOSIT] = 30
	day.costs[Ledger.BOOKING_REFUND] = 5
	_report.call("show_report", day)
	var costs: GridContainer = _report.get_node("%CostRows") as GridContainer
	assert_eq((costs.get_child(0) as Label).text, "Deposit taken off the bill")
	assert_eq((costs.get_child(1) as Label).text, "$30")
	assert_eq((costs.get_child(2) as Label).text, "Booking refund")
	assert_eq(day.profit(), 85)
	assert_eq(day.purchase_basis_operating_profit(), 120)


func test_booking_and_rush_annotations_survive_json_and_keep_stable_independent_report_rows() -> void:
	var day: DayReport = DayReport.new()
	day.rush_hour_lines = ["Book club brought 8 guests."]
	_report.call("show_report", day)
	assert_null(_report.get_node_or_null("Panel/Column/Scroll/Content/Bookings"))
	day.booking_lines = ["Booking: the birthday group couldn't be seated. Deposit refunded."]
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(day.to_dict())))
	assert_eq(restored.booking_lines, day.booking_lines)
	assert_eq(restored.rush_hour_lines, day.rush_hour_lines)
	_report.call("show_report", restored)
	var booking: Label = _report.get_node("Panel/Column/Scroll/Content/Bookings") as Label
	var rush: Label = _report.get_node("Panel/Column/Scroll/Content/RushHour") as Label
	assert_true(booking.visible)
	assert_true(rush.visible)
	assert_true(rush.get_index() < booking.get_index(), "creation order cannot reorder the two annotations")
	_report.call("show_report", DayReport.new())
	assert_false(booking.visible)
	assert_false(rush.visible)


func test_takeaways_line_shows_only_on_days_the_order_counter_sold_any() -> void:
	var day: DayReport = DayReport.new()
	day.customers_served = 9
	day.takeaways = 3
	_report.call("show_report", day)
	var label: Label = _report.get_node("Panel/Column/Scroll/Content/Takeaways") as Label
	assert_eq(label.text, "Takeaways: 3")
	assert_true(label.visible)
	_report.call("show_report", DayReport.new())
	assert_false(label.visible, "a shop without takeaways keeps its report as it was")


func test_weekly_reward_line_and_cash_category_are_distinct_from_milestones() -> void:
	var day: DayReport = DayReport.new()
	day.weekly_challenge_line = "Weekly challenge: +$60"
	day.income[Ledger.WEEKLY_CHALLENGE_BONUS] = 60
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(day.to_dict())))
	assert_eq(restored.weekly_challenge_line, "Weekly challenge: +$60")
	_report.call("show_report", restored)
	var line: Label = _report.get_node("%WeeklyChallengeLine") as Label
	assert_true(line.visible)
	assert_eq(line.text, "Weekly challenge: +$60")
	assert_true(_report.get_node("%IncomeRows").get_children().any(func(child: Node) -> bool:
		return child is Label and child.text == "Weekly challenge"))
	var legacy: DayReport = DayReport.new()
	assert_false(legacy.to_dict().has("weekly_challenge_line"),
		"default report snapshots keep their previous shape")
	_report.call("show_report", legacy)
	assert_false(line.visible)


func test_slowest_seller_line_uses_captured_name_and_both_hint_branches() -> void:
	var day: DayReport = DayReport.new()
	day.dishes_sold = {&"tomato_soup": 2, &"burger": 7}
	day.slowest_seller_snapshot = {"menu_count": 2, "eligible_dishes": [
		{"id": "tomato_soup", "display_name": "Tomato soup", "price": 15, "standard_price": 12},
		{"id": "burger", "display_name": "Burger", "price": 12, "standard_price": 12},
	]}
	_report.call("show_report", day)
	var line: Label = _report.get_node("%SlowestSeller") as Label
	assert_true(line.visible)
	assert_eq(line.text, "Slowest seller: Tomato soup (2 sold). Try a lower price or take it off the menu.")
	day.slowest_seller_snapshot["eligible_dishes"][0]["price"] = 12
	_report.call("show_report", day)
	assert_eq(line.text, "Slowest seller: Tomato soup (2 sold). Guests may not fancy it; try another dish or take it off the menu.")
	assert_false(line.text.contains("tomato_soup"), "the report uses the display name rather than the recipe id")
	day.dishes_sold.clear()
	_report.call("show_report", day)
	assert_false(line.visible, "no paid dishes means the hint line is hidden")
	var historical: DayReport = DayReport.from_dict({"dishes_sold": {"tomato_soup": 2}})
	_report.call("show_report", historical)
	assert_false(line.visible, "older reports without a service snapshot stay quiet")


func test_daily_special_line_round_trips_and_hides_for_legacy_or_empty_reports() -> void:
	var day: DayReport = DayReport.new()
	day.daily_special_line = "Today's special: Tomato soup, 4 sold"
	var encoded: Dictionary = day.to_dict()
	assert_eq(encoded.get("daily_special_line", ""), day.daily_special_line)
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(encoded)))
	assert_eq(restored.daily_special_line, day.daily_special_line)
	_report.call("show_report", restored)
	var label: Label = _report.get_node("Panel/Column/Scroll/Content/DailySpecial") as Label
	assert_true(label.visible)
	assert_eq(label.text, day.daily_special_line)
	assert_eq(label.get_index(), (_report.get_node("%SlowestSeller") as Label).get_index() + 1,
		"the special sits beside the dish rows")
	_report.call("show_report", DayReport.new())
	assert_false(label.visible, "reports without a special keep the original layout")
	_report.call("show_report", DayReport.from_dict({"day": 2}))
	assert_false(label.visible, "legacy reports without the optional field stay quiet")
	assert_false(DayReport.new().to_dict().has("daily_special_line"),
		"the default saved report shape stays unchanged")


func test_saved_report_name_contextualizes_reviews_without_changing_quotes() -> void:
	var day: DayReport = DayReport.new()
	day.restaurant_name = "Copper Cafe"
	day.day = 3
	day.review_cards = [{"stars": 4, "quote": "Warm food and friendly service."}]
	_report.call("show_report", day)
	assert_eq((_report.get_node("%RestaurantName") as Label).text, "Copper Cafe")
	assert_eq((_report.get_node("%Header") as Label).text, "Day 3: Closed")
	assert_eq((_report.get_node("Panel/Column/Scroll/Content/ReviewHeading") as Label).text, "Reviews of Copper Cafe")
	var reviews: Node = _report.get_node("%ReviewRows")
	assert_eq((reviews.get_child(0) as Label).text, '4 stars - "Warm food and friendly service."')
	var next: DayReport = DayReport.new()
	_report.call("show_report", next)
	assert_eq((_report.get_node("%RestaurantName") as Label).text, MenuSettings.DEFAULT_NAME)
	assert_eq((_report.get_node("Panel/Column/Scroll/Content/ReviewHeading") as Label).text,
		"Reviews of %s" % MenuSettings.DEFAULT_NAME)


func test_long_report_name_and_review_heading_fit_small_and_large_panels() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport: SubViewport = SubViewport.new()
	tree.root.add_child(viewport)
	viewport.add_child(_report)
	var day: DayReport = DayReport.new()
	day.restaurant_name = "WWWWWWWWWWWWWWWWWWWWWWWW"
	_report.call("show_report", day)
	for dimensions: Vector2i in [Vector2i(853, 480), Vector2i(1600, 900)]:
		viewport.size = dimensions
		for frame: int in 3:
			await tree.process_frame
		var panel: Control = _report.get_node("Panel") as Control
		var name: Label = _report.get_node("%RestaurantName") as Label
		var heading: Label = _report.get_node("Panel/Column/Scroll/Content/ReviewHeading") as Label
		assert_true(name.get_global_rect().position.x >= panel.get_global_rect().position.x)
		assert_true(name.get_global_rect().end.x <= panel.get_global_rect().end.x)
		assert_true(heading.size.x <= panel.size.x, "the named review heading wraps rather than widening the report")
	viewport.remove_child(_report)
	viewport.free()


func test_report_headline_and_next_day_stay_fixed_when_body_scrolls() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	tree.root.add_child(viewport)
	viewport.add_child(_report)
	var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
	var content: Control = scroll.get_node("Content") as Control
	content.custom_minimum_size.y = 1600.0
	var day: DayReport = DayReport.new()
	day.day = 4
	_report.call("show_report", day)
	for frame: int in 3:
		await tree.process_frame
	var header: Label = _report.get_node("%Header") as Label
	var profit: Label = _report.get_node("%Profit") as Label
	var footer: Button = _report.get_node("%NextDay") as Button
	var header_bounds: Rect2 = header.get_global_rect()
	var profit_bounds: Rect2 = profit.get_global_rect()
	var footer_bounds: Rect2 = footer.get_global_rect()
	assert_eq(header.text, "Day 4: Closed")
	assert_true(header_bounds.end.y <= scroll.get_global_rect().position.y)
	assert_true(profit_bounds.end.y <= scroll.get_global_rect().position.y)
	assert_true(footer_bounds.position.y >= scroll.get_global_rect().end.y)
	assert_true(viewport.get_visible_rect().encloses(footer_bounds))
	scroll.scroll_vertical = 500
	await tree.process_frame
	assert_eq(scroll.scroll_vertical, 500)
	assert_eq(header.get_global_rect(), header_bounds)
	assert_eq(profit.get_global_rect(), profit_bounds)
	assert_eq(footer.get_global_rect(), footer_bounds)
	var requests: Array[bool] = []
	_report.connect("next_day_pressed", func() -> void: requests.append(true))
	footer.pressed.emit()
	assert_eq(requests, [true] as Array[bool], "the pinned button emits the original request")
	viewport.remove_child(_report)
	viewport.free()


func test_tip_row_retains_its_amount_and_shows_the_active_bonus_after_restore() -> void:
	var day: DayReport = DayReport.new()
	day.income[Ledger.TIP] = 6
	assert_false(day.to_dict().has("tip_jar_percent"), "no jar preserves the old report shape")
	var rows: GridContainer = _report.get_node("%IncomeRows") as GridContainer
	_report.call("show_report", day)
	assert_eq((rows.get_child(0) as Label).text, "Tip")
	day.tip_jar_percent = 10
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(day.to_dict())))
	_report.call("show_report", restored)
	assert_eq((rows.get_child(0) as Label).text, "Tip (tip jar +10%)")
	assert_eq((rows.get_child(1) as Label).text, "$6")
