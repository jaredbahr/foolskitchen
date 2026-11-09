extends TestCase

const REPORT: PackedScene = preload("res://src/ui/evening_report.tscn")
const MENU: PackedScene = preload("res://src/ui/menu_panel.tscn")


func test_shared_plain_words_and_zero_state() -> void:
	assert_eq(ViralReviewText.demand_line(1.35), "Trending online: +35%")
	assert_eq(ViralReviewText.demand_line(1.0 + 0.35 * 2.0 / 3.0), "Trending online: +23%")
	assert_eq(ViralReviewText.demand_line(1.0 + 0.35 / 3.0), "Trending online: +12%")
	assert_eq(ViralReviewText.morning(1.0), "")
	assert_eq(ViralReviewText.evening(""),
		"A guest's post about your food is going viral! Expect more guests for a few days.")
	assert_true(ViralReviewText.morning(1.35).contains("Trending online: +35%"))


func test_report_line_is_below_existing_reviews_and_clears_for_next_report() -> void:
	var report: Control = REPORT.instantiate() as Control
	var day: DayReport = DayReport.new()
	day.viral_line = ViralReviewText.evening("Tomato soup")
	report.call("show_report", day)
	var line: Label = report.get_node("%ViralReviewLine") as Label
	var reviews: Control = report.get_node("%ReviewRows") as Control
	assert_true(line.visible)
	assert_eq(line.text, day.viral_line)
	assert_true(line.get_index() > reviews.get_index(), "Existing top report geometry is preserved")
	var restored: DayReport = DayReport.from_dict(day.to_dict())
	assert_not_null(restored)
	if restored != null:
		assert_eq(restored.viral_line, day.viral_line)
	report.call("show_report", DayReport.new())
	assert_false(line.visible)
	assert_eq(line.text, "")
	report.free()


func test_morning_reminder_hides_after_opening_and_clears_when_spell_ends() -> void:
	var panel: MenuPanel = MENU.instantiate() as MenuPanel
	panel.set_viral_notice(ViralReviewText.morning(1.35))
	panel.set_phase(SimClock.Phase.MORNING)
	var line: Label = panel.get_node("%ViralNotice") as Label
	assert_true(line.visible)
	assert_true(line.text.contains("+35%"))
	panel.set_phase(SimClock.Phase.OPEN)
	assert_false(line.visible)
	panel.set_phase(SimClock.Phase.MORNING)
	assert_true(line.visible)
	panel.set_viral_notice("")
	assert_false(line.visible)
	panel.free()


func test_forecast_preserves_neutral_shape_and_rejects_bad_optional_factor() -> void:
	var forecast: Dictionary = {"day": 2, "expected_guests": 40,
		"reputation": 1.0, "word_of_mouth": 1.0, "menu": 1.0,
		"vibe": 1.0, "curb_appeal": 1.0, "total": 1.35, "viral": 1.35}
	assert_true(DemandText.factor_lines(forecast).has("Trending online: +35%"))
	var clean: Dictionary = DayReport.public_demand_forecast(forecast)
	assert_almost_eq(clean["viral"], 1.35)
	for invalid: Variant in [true, "1.35", NAN, 0.9]:
		forecast["viral"] = invalid
		assert_true(DayReport.public_demand_forecast(forecast).is_empty())
	forecast.erase("viral")
	assert_false(DayReport.public_demand_forecast(forecast).has("viral"))
