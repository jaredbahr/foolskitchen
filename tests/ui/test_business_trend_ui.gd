extends TestCase
## Real report/chart controls plus plain wording at the signed-money boundary.

const REPORT: PackedScene = preload("res://src/ui/evening_report.tscn")

var _host: SubViewport
var _report: Control


func before_each() -> void:
	_host = SubViewport.new()
	_host.size = Vector2i(1280, 720)
	(Engine.get_main_loop() as SceneTree).root.add_child(_host)
	_report = REPORT.instantiate() as Control
	_host.add_child(_report)


func after_each() -> void:
	_host.get_parent().remove_child(_host)
	_host.free()


func test_summary_up_down_flat_and_two_complete_weeks_use_plain_words() -> void:
	assert_true(BusinessTrendText.summary([_row(1, 10), _row(2, 20)], 2).contains("up 100%"))
	assert_true(BusinessTrendText.summary([_row(1, 20), _row(2, 10)], 2).contains("down 50%"))
	assert_true(BusinessTrendText.summary([_row(1, 10), _row(2, 10)], 2).contains("unchanged"))
	var rows: Array[Dictionary] = _history(14)
	for index: int in 14:
		rows[index]["dish_profit"] = 10 if index < 7 else 20
	assert_eq(BusinessTrendText.summary(rows, 14), "Dish profit is up 100% on last week.")


func test_partial_windows_keep_unknown_days_and_name_equal_recorded_counts() -> void:
	var rows: Array[Dictionary] = _history(7)
	for index: int in 7:
		rows[index]["dish_profit"] = 10 if index < 4 else 20
	rows[0]["dish_profit_recorded"] = false
	var text: String = BusinessTrendText.summary(rows, 7)
	assert_true(text.contains("last 3 recorded days"))
	assert_true(text.contains("previous 3 recorded days"))
	assert_true(text.contains("up 100%"), "the unmatched oldest row is outside both equal windows")
	assert_false(text.contains("week"))
	rows[1]["dish_profit_recorded"] = false
	assert_eq(BusinessTrendText.summary(rows, 7), BusinessTrendText.UNAVAILABLE,
		"a selected unknown day cannot be dropped to manufacture another comparison")
	var gapped: Array[Dictionary] = _history(14)
	gapped[-1]["day"] = 15
	assert_false(BusinessTrendText.summary(gapped, 15).contains("week"))


func test_zero_loss_crossing_and_tiny_percent_use_signed_dollar_changes() -> void:
	var narrowed: String = BusinessTrendText.summary([_row(1, -10), _row(2, -5)], 2)
	assert_true(narrowed.contains("$5 higher"))
	assert_false(narrowed.contains("%"))
	var from_zero: String = BusinessTrendText.summary([_row(1, 0), _row(2, -5)], 2)
	assert_true(from_zero.contains("$5 lower"))
	assert_false(from_zero.contains("%"))
	var crossing: String = BusinessTrendText.summary([_row(1, 10), _row(2, -5)], 2)
	assert_true(crossing.contains("$15 lower"))
	assert_false(crossing.contains("%"))
	var small: String = BusinessTrendText.summary([_row(1, 1000), _row(2, 1001)], 2)
	assert_true(small.contains("$1 higher"))
	assert_false(small.contains("0%"))


func test_signed_money_overflow_cannot_reverse_a_profit_trend() -> void:
	var rows: Array[Dictionary] = _history(14)
	for row: Dictionary in rows:
		row["dish_profit"] = BusinessTrendText.MAX_TOTAL
	assert_eq(BusinessTrendText.summary(rows, 14), BusinessTrendText.UNAVAILABLE)
	assert_eq(BusinessTrendText.summary([_row(1, BusinessTrendText.MIN_TOTAL), _row(2, 0)], 2),
		BusinessTrendText.UNAVAILABLE)
	assert_true(BusinessTrendText.summary([
		_row(1, BusinessTrendText.MIN_TOTAL), _row(2, BusinessTrendText.MIN_TOTAL + 1)], 2).contains("$1 higher"))


func test_chart_uses_last_seven_calendar_days_and_explicit_today() -> void:
	var rows: Array[Dictionary] = _history(14)
	_report.call("show_history", rows, 14)
	var chart: BusinessTrendChart = _chart()
	chart.size = Vector2(800, 320)
	var snapshot: Dictionary = chart.review_snapshot()
	assert_eq(snapshot["days"], [8, 9, 10, 11, 12, 13, 14])
	assert_eq(snapshot["day_labels"], PackedStringArray(["Day 8", "Day 9", "Day 10", "Day 11", "Day 12", "Day 13", "Day 14"]))
	assert_eq(snapshot["today_index"], 6)
	assert_eq(snapshot["profit_values"], [80, 90, 100, 110, 120, 130, 140])
	assert_eq(snapshot["served_values"], [8, 9, 10, 11, 12, 13, 14])
	assert_eq(BusinessTrendText.TODAY, "Today")
	rows[-1]["dish_profit"] = 999
	assert_eq(chart.review_snapshot(), snapshot, "the view retains a detached snapshot")


func test_negative_bars_zero_and_unknown_profit_gap_preserve_served_track() -> void:
	var unknown: Dictionary = _row(2, 100)
	unknown["dish_profit_recorded"] = false
	var rows: Array[Dictionary] = [_row(1, -20), unknown, _row(3, 0), _row(4, 10)]
	_report.call("show_history", rows, 4)
	_chart().size = Vector2(800, 320)
	var snapshot: Dictionary = _chart().review_snapshot()
	assert_eq(snapshot["profit_values"], [-20, null, 0, 10])
	assert_eq(snapshot["served_values"], [1, 2, 3, 4])
	var profit: Dictionary = snapshot["tracks"]["profit"]
	var served: Dictionary = snapshot["tracks"]["served"]
	assert_eq(profit["minimum"], -20)
	assert_eq(profit["maximum"], 10)
	assert_eq(served["minimum"], 0)
	assert_eq(served["maximum"], 4)
	assert_eq(profit["bars"].size(), 3, "unknown is a gap; known zero still has a mark")
	assert_eq(served["bars"].size(), 4)
	var loss_bar: Dictionary = profit["bars"][0]
	assert_almost_eq(float(loss_bar["rect"][1]), float(profit["zero_y"]))
	assert_true(float(loss_bar["rect"][3]) > 0.0, "loss extends below the signed zero line")


func test_short_history_and_legacy_rebind_replace_the_entire_previous_view() -> void:
	_report.call("show_history", _history(14), 14)
	assert_true(_chart().visible)
	_report.call("show_report", DayReport.new())
	assert_false(_chart().visible)
	assert_eq((_report.get_node("%BusinessTrendSummary") as Label).text,
		"Come back tomorrow to see your trend.")
	assert_eq(_chart().review_snapshot()["days"], [])
	var single: Array[Dictionary] = [_row(1, 10)]
	_report.call("show_history", single, 1)
	assert_false(_chart().visible)
	assert_eq((_report.get_node("%BusinessTrendSummary") as Label).text, BusinessTrendText.EMPTY)


func test_section_follows_team_and_chart_fits_native_report_widths() -> void:
	_report.call("show_history", _history(14), 14)
	var section: Control = _report.get_node("%BusinessTrendSection") as Control
	var team: Control = _report.get_node("%TeamSection") as Control
	assert_eq(section.get_parent(), team.get_parent())
	assert_true(section.get_index() > team.get_index())
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		_host.size = dimensions
		for frame: int in 3:
			await (Engine.get_main_loop() as SceneTree).process_frame
		var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
		var chart: BusinessTrendChart = _chart()
		assert_true(chart.size.x > 0.0)
		assert_true(chart.size.x <= scroll.size.x + 0.5)
		assert_false(scroll.get_h_scroll_bar().visible)
		assert_eq((_report.get_node("%BusinessTrendSummary") as Label).autowrap_mode,
			TextServer.AUTOWRAP_WORD_SMART)
		var labels: Array = chart.review_snapshot()["labels"]
		var bounds: Rect2 = Rect2(Vector2.ZERO, chart.size).grow(0.5)
		for label: Dictionary in labels:
			assert_true(bounds.encloses(_rect(label["rect"])), "actual font bounds fit the chart")
			if label["kind"] != "title" and label["kind"] != "today":
				continue
			for other: Dictionary in labels:
				if other["track"] != label["track"]:
					continue
				if (label["kind"] == "title" and other["kind"] == "value") \
						or (label["kind"] == "today" and other["kind"] == "day"):
					assert_false(_rect(label["rect"]).intersects(_rect(other["rect"])),
						"track titles, values, day labels and Today use separate text lines")


func _chart() -> BusinessTrendChart:
	return _report.get_node("%BusinessTrendChart") as BusinessTrendChart


func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


func _history(count: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for day: int in range(1, count + 1):
		rows.append(_row(day, day * 10))
	return rows


func _row(day: int, profit: int) -> Dictionary:
	return {"day": day, "served": day, "lost": 0, "dish_profit": profit,
		"dish_profit_recorded": true, "cash_change": profit, "reputation": 3.0}
