extends TestCase
## Request-only roster presentation. Native integration lives in staff_session.

const PANEL: PackedScene = preload("res://src/ui/staff_panel.tscn")

var _panel: StaffPanel
var _roster: StaffRoster
var _requests: Array[StringName] = []


func before_each() -> void:
	_roster = StaffRoster.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 72
	_roster.draw_candidates(1, random)
	_panel = PANEL.instantiate() as StaffPanel
	_panel.hire_requested.connect(_record)
	_panel.let_go_requested.connect(_record)
	_panel.bind_roster(_roster)


func after_each() -> void:
	_panel.free()


func test_staff_rows_show_people_traits_wages_and_role_minimums() -> void:
	assert_eq(_panel.theme, StaffPanel.SHARED_THEME)
	assert_false(_panel.visible)
	assert_eq((_panel.get_node("Panel/Content/Scroll/List/Members") as VBoxContainer).get_child_count(), 2)
	assert_eq((_panel.get_node("Panel/Content/Scroll/List/Candidates") as VBoxContainer).get_child_count(), 3)
	assert_eq((_panel.get_node("Panel/Content/Scroll/List/RosterTitle") as Label).text, "Your team (2/6) - $55 a day")
	for member: StaffMember in _roster.members():
		var row: Control = _panel.row_for(member.id)
		assert_true((row.get_node("Top/Name") as Label).text.contains(member.display_name))
		assert_true((row.get_node("Top/Name") as Label).text.contains("skill 3"))
		assert_true((row.get_node("Trait") as Label).text.contains("Steady"))
		assert_true((row.get_node("Top/Action") as Button).disabled)
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(scroll.mouse_force_pass_scroll_events)


func test_requests_are_primitive_and_rebinding_or_refresh_preserves_buttons() -> void:
	var candidate: StaffMember = _roster.candidates()[0]
	var button: Button = _panel.row_for(candidate.id).get_node("Top/Action") as Button
	var before: Dictionary = _roster.to_dict()
	_panel.refresh()
	_panel.bind_roster(_roster)
	assert_true(_panel.row_for(candidate.id).get_node("Top/Action") == button)
	button.pressed.emit()
	assert_eq(_requests, [candidate.id] as Array[StringName])
	assert_eq(_roster.to_dict(), before)
	_panel.set_phase(SimClock.Phase.CLOSED)
	assert_true(button.disabled)
	button.pressed.emit()
	assert_eq(_requests.size(), 1)
	assert_eq(_roster.to_dict(), before)


func test_hired_or_stale_candidate_is_not_requested_again() -> void:
	var id: StringName = _roster.candidates()[0].id
	assert_true(_roster.hire(id))
	_panel.refresh()
	var button: Button = _panel.row_for(id).get_node("Top/Action") as Button
	assert_eq(button.text, "Let go")
	assert_false(button.disabled)
	button.pressed.emit()
	assert_eq(_requests, [id] as Array[StringName])
	_panel.call("_on_request", &"missing", true)
	assert_eq(_requests.size(), 1)


func _record(id: StringName) -> void:
	_requests.append(id)
