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


func test_saved_report_name_contextualizes_reviews_without_changing_quotes() -> void:
	var day: DayReport = DayReport.new()
	day.restaurant_name = "Copper Cafe"
	day.day = 3
	day.review_cards = [{"stars": 4, "quote": "Warm food and friendly service."}]
	_report.call("show_report", day)
	assert_eq((_report.get_node("%RestaurantName") as Label).text, "Copper Cafe")
	assert_eq((_report.get_node("%Header") as Label).text, "Day 3: Closed")
	assert_eq((_report.get_node("Panel/Scroll/Content/ReviewHeading") as Label).text, "Reviews of Copper Cafe")
	var reviews: Node = _report.get_node("%ReviewRows")
	assert_eq((reviews.get_child(0) as Label).text, '4 stars - "Warm food and friendly service."')
	var next: DayReport = DayReport.new()
	_report.call("show_report", next)
	assert_eq((_report.get_node("%RestaurantName") as Label).text, MenuSettings.DEFAULT_NAME)
	assert_eq((_report.get_node("Panel/Scroll/Content/ReviewHeading") as Label).text,
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
		var heading: Label = _report.get_node("Panel/Scroll/Content/ReviewHeading") as Label
		assert_true(name.get_global_rect().position.x >= panel.get_global_rect().position.x)
		assert_true(name.get_global_rect().end.x <= panel.get_global_rect().end.x)
		assert_true(heading.size.x <= panel.size.x, "the named review heading wraps rather than widening the report")
	viewport.remove_child(_report)
	viewport.free()
