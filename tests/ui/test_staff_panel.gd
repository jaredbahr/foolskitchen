extends TestCase
## Request-only roster presentation. Native integration lives in staff_session.

const PANEL: PackedScene = preload("res://src/ui/staff_panel.tscn")

var _panel: StaffPanel
var _roster: StaffRoster
var _requests: Array[StringName] = []
var _close_requests: int = 0
var _tray_requests: Array[int] = []


func before_each() -> void:
	_roster = StaffRoster.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 72
	_roster.draw_candidates(1, random)
	_panel = PANEL.instantiate() as StaffPanel
	_panel.hire_requested.connect(_record)
	_panel.let_go_requested.connect(_record)
	_panel.close_requested.connect(_record_close)
	_panel.tray_requested.connect(_record_tray)
	_panel.bind_roster(_roster)
	_tray_requests.clear()


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
		assert_eq((row.get_node("Top/Action") as Button).tooltip_text, "Keep at least one cook and one server.")
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(scroll.mouse_force_pass_scroll_events)


func test_tray_rows_show_price_capacity_owned_state_and_request_only() -> void:
	assert_true((_panel.get_node("Panel/Content/Scroll/List/TraysRow/TraysBuy") as Button).disabled,
		"the detached panel has no invented price before tuning is bound")
	_panel.set_trays(0, PackedInt32Array([60, 150]), 200)
	var first: Button = _panel.get_node("Panel/Content/Scroll/List/TraysRow/TraysBuy") as Button
	var second: Button = _panel.get_node("Panel/Content/Scroll/List/BigTraysRow/BigTraysBuy") as Button
	assert_eq((_panel.get_node("Panel/Content/Scroll/List/Carry") as Label).text, "Servers carry 1 plate")
	assert_true((_panel.get_node("Panel/Content/Scroll/List/TraysRow/TraysLabel") as Label).text.contains("$60"))
	assert_false(first.disabled)
	assert_true(second.disabled)
	first.pressed.emit()
	assert_eq(_tray_requests, [1] as Array[int])
	assert_eq(_panel.get("_tray_level"), 0, "the panel only sends a request")
	_panel.set_trays(1, PackedInt32Array([60, 150]), 140)
	assert_eq(first.text, "Owned")
	assert_true(first.disabled)
	assert_true(second.disabled, "the next price is not affordable")
	_panel.set_trays(1, PackedInt32Array([60, 150]), 200)
	assert_false(second.disabled)
	second.pressed.emit()
	assert_eq(_tray_requests, [1, 2] as Array[int])
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_true(second.disabled)
	second.pressed.emit()
	assert_eq(_tray_requests, [1, 2] as Array[int])


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


func test_close_requests_no_arguments_without_hiding_or_changing_the_roster() -> void:
	var close: Button = _panel.get_node("Panel/Content/Close") as Button
	var candidate: StaffMember = _roster.candidates()[0]
	var held_button: Button = _panel.row_for(candidate.id).get_node("Top/Action") as Button
	var before: Dictionary = _roster.to_dict()
	_panel.show()
	assert_eq(close.text, "Close")
	assert_false(close.disabled)
	assert_eq(close.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_true(close.get_parent() == _panel.get_node("Panel/Content"), "Close stays outside the bounded scroll area")
	assert_eq(close.size_flags_horizontal, Control.SIZE_SHRINK_END)
	close.pressed.emit()
	assert_eq(_close_requests, 1)
	assert_true(_panel.visible, "Main handles the primitive request")
	assert_eq(_roster.to_dict(), before)
	assert_true(_requests.is_empty())
	assert_true(_panel.row_for(candidate.id).get_node("Top/Action") == held_button)
	_panel.set_phase(SimClock.Phase.CLOSED)
	assert_false(close.disabled, "closing the view is available in every phase")
	close.pressed.emit()
	assert_eq(_close_requests, 2)
	assert_eq(_roster.to_dict(), before)
	assert_true(_requests.is_empty())


func test_disabled_actions_use_the_shared_opaque_readable_theme() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	assert_true(tree.root.is_inside_tree())
	tree.root.add_child(_panel)
	await tree.process_frame
	var button: Button = _panel.row_for(_roster.members()[0].id).get_node("Top/Action") as Button
	assert_true(button.is_inside_tree())
	assert_true(button.disabled)
	assert_true(StaffPanel.SHARED_THEME.has_stylebox("disabled", "Button"))
	assert_true(StaffPanel.SHARED_THEME.has_color("font_disabled_color", "Button"))
	var disabled: StyleBoxFlat = button.get_theme_stylebox("disabled") as StyleBoxFlat
	var normal: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(disabled)
	assert_not_null(normal)
	if disabled == null or normal == null:
		return
	assert_eq(disabled, StaffPanel.SHARED_THEME.get_stylebox("disabled", "Button"))
	assert_ne(disabled.bg_color, normal.bg_color, "disabled actions remain distinguishable")
	var foreground: Color = button.get_theme_color("font_disabled_color")
	assert_eq(foreground, StaffPanel.SHARED_THEME.get_color("font_disabled_color", "Button"))
	assert_almost_eq(foreground.a, 1.0)
	assert_almost_eq(disabled.bg_color.a, 1.0)
	var text_luminance: float = _luminance(foreground)
	var background_luminance: float = _luminance(disabled.bg_color)
	var contrast: float = (maxf(text_luminance, background_luminance) + 0.05) / (minf(text_luminance, background_luminance) + 0.05)
	assert_true(contrast >= 4.5, "disabled Let go text retains readable normal-text contrast")


func _record(id: StringName) -> void:
	_requests.append(id)


func _record_close() -> void:
	_close_requests += 1


func _record_tray(level: int) -> void:
	_tray_requests.append(level)


func _luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


func _linear_channel(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)
