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


func test_monthly_summary_compares_daily_averages_and_names_both_recorded_spans() -> void:
	var rows: Array[Dictionary] = _history(30)
	for row: Dictionary in rows:
		row["dish_profit"] = 10
	assert_eq(BusinessTrendText.summary(rows.slice(0, 19), 19, 30), BusinessTrendText.summary(rows, 19))
	assert_eq(BusinessTrendText.summary(rows.slice(0, 20), 20, 30),
		"Average daily dish profit over the last 15 recorded days is unchanged from the previous 5 recorded days.")
	for index: int in range(15, 30):
		rows[index]["dish_profit"] = 20
	assert_eq(BusinessTrendText.summary(rows, 30, 30),
		"Average daily dish profit over the last 15 recorded days is up 100% compared with the previous 15 recorded days.")
	var partial: Array[Dictionary] = rows.slice(0, 26)
	# Reassign the change at the boundary of the 15 newest rows (day 12).
	for index: int in range(11, 26):
		partial[index]["dish_profit"] = 20
	_report.call("show_history", partial, 26)
	var summary: Label = _report.get_node("%BusinessTrendSummary") as Label
	assert_eq(summary.text, "Dish profit is unchanged from last week.")
	_range_button(30).pressed.emit()
	assert_eq(summary.text,
		"Average daily dish profit over the last 15 recorded days is up 100% compared with the previous 11 recorded days.")
	_range_button(7).pressed.emit()
	assert_eq(summary.text, "Dish profit is unchanged from last week.")


func test_monthly_averages_preserve_loss_unknown_and_fractional_changes() -> void:
	var rows: Array[Dictionary] = _history(20)
	for index: int in rows.size():
		rows[index]["dish_profit"] = -10 if index < 5 else -5
	assert_eq(BusinessTrendText.summary(rows, 20, 30),
		"Average daily dish profit over the last 15 recorded days is $5 higher than over the previous 5 recorded days.")
	rows[0]["dish_profit_recorded"] = false
	assert_eq(BusinessTrendText.summary(rows, 20, 30), BusinessTrendText.UNAVAILABLE)
	var large: int = 600_000_000_000_000_000
	for row: Dictionary in rows:
		row["dish_profit"] = large
		row["dish_profit_recorded"] = true
	rows[-1]["dish_profit"] = large + 1
	assert_true(BusinessTrendText.summary(rows, 20, 30).contains("$0.07 higher"),
		"a real fractional difference survives large signed-integer totals")


func test_chart_uses_last_seven_calendar_days_and_explicit_today() -> void:
	var rows: Array[Dictionary] = _history(14)
	_report.call("show_history", rows, 14)
	var chart: BusinessTrendChart = _chart()
	chart.size = Vector2(800, 320)
	var snapshot: Dictionary = chart.review_snapshot()
	assert_eq(snapshot["range_days"], 7)
	assert_eq(snapshot["days"], [8, 9, 10, 11, 12, 13, 14])
	assert_eq(snapshot["day_labels"], PackedStringArray(["Day 8", "Day 9", "Day 10", "Day 11", "Day 12", "Day 13", "Day 14"]))
	assert_eq(snapshot["today_index"], 6)
	assert_eq(snapshot["profit_values"], [80, 90, 100, 110, 120, 130, 140])
	assert_eq(snapshot["served_values"], [8, 9, 10, 11, 12, 13, 14])
	assert_eq(BusinessTrendText.TODAY, "Today")
	rows[-1]["dish_profit"] = 999
	assert_eq(chart.review_snapshot(), snapshot, "the view retains a detached snapshot")


func test_range_buttons_select_thirty_days_and_survive_report_refresh() -> void:
	_report.call("show_history", _history(30), 30)
	assert_eq(_chart().review_snapshot()["days"].size(), 7)
	_range_button(30).pressed.emit()
	var snapshot: Dictionary = _chart().review_snapshot()
	assert_eq(snapshot["range_days"], 30)
	assert_eq(snapshot["days"].size(), 30)
	assert_true(_range_button(30).button_pressed)
	assert_false(_range_button(7).button_pressed)
	_report.hide()
	_report.call("show_report", DayReport.new())
	_report.call("show_history", _history(31), 31)
	assert_eq(_chart().review_snapshot()["range_days"], 30)
	assert_eq(_chart().review_snapshot()["days"].size(), 30)
	_range_button(7).pressed.emit()
	assert_eq(_chart().review_snapshot()["range_days"], 7)
	assert_eq(_chart().review_snapshot()["days"], [25, 26, 27, 28, 29, 30, 31])


func test_month_range_uses_existing_rows_without_padding_or_zero_division() -> void:
	_range_button(30).pressed.emit()
	var rows: Array[Dictionary] = [_row(8, 10), _row(9, -5), _row(10, 0)]
	_report.call("show_history", rows, 10)
	var snapshot: Dictionary = _chart().review_snapshot()
	assert_eq(snapshot["days"], [8, 9, 10])
	assert_eq(snapshot["tracks"]["profit"]["bars"].size(), 3)
	assert_eq(snapshot["tracks"]["served"]["bars"].size(), 3)
	rows = [_row(10, 0)]
	_report.call("show_history", rows, 10)
	snapshot = _chart().review_snapshot()
	assert_false(_chart().visible)
	assert_eq((_report.get_node("%BusinessTrendSummary") as Label).text, BusinessTrendText.EMPTY)
	assert_eq(snapshot["days"], [10])
	assert_eq(snapshot["tracks"]["profit"]["bars"].size(), 1, "a known zero is a real mark")
	assert_eq(snapshot["tracks"]["served"]["bars"].size(), 1)
	rows.clear()
	_report.call("show_history", rows, 10)
	snapshot = _chart().review_snapshot()
	assert_false(_chart().visible)
	assert_eq(snapshot["days"], [])
	assert_eq(snapshot["tracks"]["profit"]["bars"], [])
	assert_true(is_finite(float(snapshot["tracks"]["profit"]["zero_y"])))


func test_month_labels_every_fifth_day_and_the_latest_at_native_widths() -> void:
	_range_button(30).pressed.emit()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		_host.size = dimensions
		for dashboard_day: int in [30, 26, 27]:
			var last_recorded: int = mini(dashboard_day, 26) if dashboard_day != 30 else 30
			_report.call("show_history", _history(last_recorded), dashboard_day)
			for frame: int in 3:
				await (Engine.get_main_loop() as SceneTree).process_frame
			var expected_days: Array[String] = ["Day 5", "Day 10", "Day 15", "Day 20"]
			if last_recorded == 30:
				expected_days.append("Day 25")
			expected_days.append("Day %d" % last_recorded)
			_assert_month_labels(expected_days, last_recorded, dashboard_day)


func _assert_month_labels(expected_days: Array[String], latest: int, today: int) -> void:
	var chart: BusinessTrendChart = _chart()
	var snapshot: Dictionary = chart.review_snapshot()
	var labels: Array = snapshot["labels"]
	var bounds: Rect2 = Rect2(Vector2.ZERO, chart.size).grow(0.5)
	var font: Font = chart.get_theme_font("font", "Label")
	var font_size: int = chart.get_theme_font_size("font_size", "Label")
	for key: String in ["profit", "served"]:
		var days: Array[String] = []
		var latest_value: String = BusinessTrendText.profit_label(latest * 10) if key == "profit" \
			else BusinessTrendText.served_label(latest)
		var has_latest_value: bool = false
		var bars: Array = snapshot["tracks"][key]["bars"]
		var has_today: bool = false
		for label: Dictionary in labels:
			if label["track"] != key:
				continue
			var text_rect: Rect2 = _rect(label["rect"])
			assert_true(bounds.encloses(text_rect), "monthly font bounds fit")
			assert_true(font.get_string_size(String(label["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x \
				<= float(label["width"]), "monthly text is not truncated to its slot")
			if label["kind"] == "day":
				days.append(label["text"])
				var day: int = String(label["text"]).trim_prefix("Day ").to_int()
				var bar: Rect2 = _rect(bars[day - 1]["rect"])
				assert_true(absf(text_rect.get_center().x - bar.get_center().x) <= text_rect.size.x * 0.5,
					"monthly day label stays aligned with its own bar")
			if label["kind"] == "value" and label["text"] == latest_value:
				var latest_bar: Rect2 = _rect(bars[-1]["rect"])
				has_latest_value = text_rect.position.x <= latest_bar.get_center().x \
					and text_rect.end.x >= latest_bar.get_center().x
			if label["kind"] == "today":
				has_today = true
			for other: Dictionary in labels:
				if label != other and label["track"] == other["track"] and label["kind"] == other["kind"]:
					assert_false(text_rect.intersects(_rect(other["rect"])), "monthly labels on one line do not overlap")
		assert_eq(days, expected_days, "%s latest record %d, viewport %s" % [key, latest, _host.size])
		assert_true(has_latest_value, "%s labels the newest bar, even when today's record is missing" % key)
		assert_eq(has_today, latest == today)


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
	var invalid: Dictionary = _row(2, 20)
	invalid["served"] = -1
	var single: Array[Dictionary] = [_row(1, 10), _row(1, 11), invalid]
	_report.call("show_history", single, 2)
	assert_false(_chart().visible, "duplicate and invalid rows cannot make a second chart day")
	assert_eq((_report.get_node("%BusinessTrendSummary") as Label).text, BusinessTrendText.EMPTY)
	single.append(_row(2, 20))
	_report.call("show_history", single, 2)
	assert_true(_chart().visible)
	assert_eq(_chart().review_snapshot()["days"], [1, 2])


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
		var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
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


func _range_button(days: int) -> Button:
	return _report.get_node("%BusinessTrendSection").get_node("BusinessTrendRanges/Days%d" % days) as Button


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
