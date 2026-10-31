extends TestCase
## Actual report and Staff controls share one detached completed-service view.
## These constructed display fixtures do not stand in for the balance capture.

const REPORT: PackedScene = preload("res://src/ui/evening_report.tscn")
const PANEL: PackedScene = preload("res://src/ui/staff_panel.tscn")

var _report: Control
var _panel: StaffPanel
var _host: SubViewport
var _roster: StaffRoster
var _requests: int = 0


func before_each() -> void:
	_host = SubViewport.new()
	_host.size = Vector2i(853, 480)
	(Engine.get_main_loop() as SceneTree).root.add_child(_host)
	_report = REPORT.instantiate() as Control
	_panel = PANEL.instantiate() as StaffPanel
	_host.add_child(_report)
	_host.add_child(_panel)
	_roster = StaffRoster.new()
	_panel.bind_roster(_roster)
	_panel.set_phase(SimClock.Phase.MORNING)
	_panel.hire_requested.connect(_record_request)
	_panel.let_go_requested.connect(_record_request)
	_requests = 0


func after_each() -> void:
	_host.get_parent().remove_child(_host)
	_host.free()


func test_report_and_morning_panel_show_same_percentages_and_assigned_owner_hours() -> void:
	var report: DayReport = DayReport.new()
	report.day = 3
	report.staff_activity = _summary()
	report.leave_reasons = {&"waited_too_long": 1}
	_report.call("show_report", report)
	_panel.set_team_activity(report.staff_activity)
	assert_eq((_report.get_node("%TeamHeading") as Label).text, "Your team")
	assert_eq((_panel.get_node("%TeamActivityHeading") as Label).text, "Last service · Day 3")
	var expected: Dictionary = {"CookActivity": "Cooks: busy 90% of open hours",
		"ServerActivity": "Servers: busy 0% of open hours",
		"OwnerActivity": "Owner: busy 50% of assigned open hours"}
	for node_name: String in expected:
		var evening: Label = _row(_report, node_name)
		var morning: Label = _row(_panel, node_name)
		assert_true(evening.visible)
		assert_true(morning.visible)
		assert_eq(evening.text, expected[node_name])
		assert_eq(morning.text, evening.text)
	assert_false(_row(_report, "CleanerActivity").visible)
	assert_false(_row(_panel, "CleanerActivity").visible)
	assert_eq((_report.get_node("%TeamAdvice") as Label).text, StaffAdviceText.recommendation(&"cook"))
	assert_true((_report.get_node("%TeamSection") as Control).visible)
	assert_true((_panel.get_node("%TeamActivitySection") as Control).visible)
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_false((_panel.get_node("%TeamActivitySection") as Control).visible)
	_panel.set_phase(SimClock.Phase.MORNING)
	assert_true((_panel.get_node("%TeamActivitySection") as Control).visible)
	assert_eq(_row(_panel, "CookActivity").text, expected["CookActivity"])


func test_legacy_or_unknown_rebind_clears_old_values_and_recommendation() -> void:
	var measured: DayReport = DayReport.new()
	measured.staff_activity = _summary()
	measured.leave_reasons = {&"waited_too_long": 1}
	_report.call("show_report", measured)
	_panel.set_team_activity(measured.staff_activity)
	var legacy: DayReport = DayReport.from_dict({"day": 4})
	_report.call("show_report", legacy)
	_panel.set_team_activity({})
	assert_false((_report.get_node("%TeamSection") as Control).visible)
	assert_false((_panel.get_node("%TeamActivitySection") as Control).visible)
	assert_eq((_report.get_node("%TeamAdvice") as Label).text, "")
	assert_eq((_panel.get_node("%TeamActivityHeading") as Label).text, "")
	for node_name: String in ["CookActivity", "ServerActivity", "CleanerActivity", "OwnerActivity"]:
		assert_eq(_row(_report, node_name).text, "")
		assert_eq(_row(_panel, node_name).text, "")
		assert_false(_row(_report, node_name).visible)
		assert_false(_row(_panel, node_name).visible)


func test_activity_setter_detaches_input_and_retains_existing_action_rows() -> void:
	var summary: Dictionary = _summary()
	var before_roster: Dictionary = _roster.to_dict()
	var cook_row: Control = _panel.row_for(&"starter_cook")
	var server_row: Control = _panel.row_for(&"starter_server")
	var previous_buttons: Array[Node] = _panel.find_children("*", "Button", true, false)
	_panel.set_team_activity(summary)
	assert_eq(_panel.row_for(&"starter_cook"), cook_row)
	assert_eq(_panel.row_for(&"starter_server"), server_row)
	assert_eq(_panel.find_children("*", "Button", true, false), previous_buttons)
	assert_eq(_requests, 0, "read-only display setters cannot request roster changes")
	assert_eq(_roster.to_dict(), before_roster)
	summary["roles"]["cook"]["busy_ticks"] = 0
	_panel.refresh()
	assert_eq(_row(_panel, "CookActivity").text, "Cooks: busy 90% of open hours")
	assert_eq(_roster.to_dict(), before_roster)


func test_advice_wraps_inside_real_narrow_report_without_horizontal_overflow() -> void:
	var report: DayReport = DayReport.new()
	report.staff_activity = _summary()
	report.leave_reasons = {&"waited_too_long": 1}
	_report.call("show_report", report)
	_panel.hide()
	for _frame: int in 4:
		await (Engine.get_main_loop() as SceneTree).process_frame
	var advice: Label = _report.get_node("%TeamAdvice") as Label
	var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
	var content: Control = _report.get_node("Panel/Scroll/Content") as Control
	assert_eq(advice.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(advice.size.x > 0.0)
	assert_true(content.size.x <= scroll.size.x + 0.5)
	assert_false(scroll.get_h_scroll_bar().visible)
	var font: Font = advice.get_theme_font("font")
	var unwrapped: float = font.get_string_size(advice.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		advice.get_theme_font_size("font_size")).x
	if unwrapped > advice.size.x + 0.5:
		assert_true(advice.get_line_count() > 1, "a sentence wider than its label must wrap")


func _summary() -> Dictionary:
	return {"day": 3, "open_ticks": 100, "roles": {
		"cook": {"busy_ticks": 90, "open_ticks": 100},
		"server": {"busy_ticks": 0, "open_ticks": 100},
		"owner": {"busy_ticks": 10, "open_ticks": 20}}}


func _row(view: Control, node_name: String) -> Label:
	return view.get_node("%TeamActivityRows").get_node(NodePath(node_name)) as Label


func _record_request(_member_id: StringName) -> void:
	_requests += 1
