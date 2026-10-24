extends TestCase
## Request-only roster presentation. Native integration lives in staff_session.

const PANEL: PackedScene = preload("res://src/ui/staff_panel.tscn")

var _panel: StaffPanel
var _roster: StaffRoster
var _requests: Array[StringName] = []
var _close_requests: int = 0
var _tray_requests: Array[int] = []
var _raise_accepts: Array[StringName] = []
var _raise_declines: Array[StringName] = []


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
	_panel.raise_accept_requested.connect(_record_accept)
	_panel.raise_decline_requested.connect(_record_decline)
	_panel.bind_roster(_roster)
	_tray_requests.clear()
	_raise_accepts.clear()
	_raise_declines.clear()


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
		assert_true((row.get_node("Top/Name") as Label).text.contains(
			" - Cook," if member.role == &"cook" else " - Server,"))
		assert_true((row.get_node("Top/Name") as Label).text.contains("skill 3"))
		assert_true((row.get_node("Trait") as Label).text.contains("Steady"))
		assert_true((row.get_node("Top/Action") as Button).disabled)
		assert_eq((row.get_node("Top/Action") as Button).tooltip_text, "Keep at least one cook and one server.")
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(scroll.mouse_force_pass_scroll_events)


func test_optional_cleaner_is_named_and_can_be_hired_then_let_go_by_request() -> void:
	var saved: Dictionary = _roster.to_dict()
	saved["candidates"][0]["role"] = "cleaner"
	saved["candidates"][0].erase("growth")
	var expected_wage: int = EconomyTuning.new().staff_wage(
		&"cleaner", int(saved["candidates"][0]["skill"]))
	saved["candidates"][0]["wage"] = expected_wage
	assert_true(_roster.from_dict(saved))
	_panel.refresh()
	var candidate: StaffMember = _roster.candidates()[0]
	var row: Control = _panel.row_for(candidate.id)
	var title: String = (row.get_node("Top/Name") as Label).text
	assert_true(title.contains(" - Cleaner, skill "))
	assert_true(title.contains("$%d/day" % expected_wage))
	assert_false(title.contains(" - Server,"), "a cleaner is not shown as a server")
	assert_false(title.contains(" - cleaner,"), "never show a raw role id")
	assert_true((_panel.get_node("Panel/Content/Status") as Label).text.contains(
		"Keep a cook and a server"), "the cleaner remains optional")
	var hire: Button = row.get_node("Top/Action") as Button
	assert_eq(hire.text, "Hire")
	assert_false(hire.disabled)
	assert_true(hire.tooltip_text.contains("Cleaners mop floor spots"))
	var before: Dictionary = _roster.to_dict()
	hire.pressed.emit()
	assert_eq(_requests, [candidate.id] as Array[StringName])
	assert_eq(_roster.to_dict(), before, "the panel only requests a hire")
	assert_true(_roster.hire(candidate.id))
	_panel.refresh()
	var hired_row: Control = _panel.row_for(candidate.id)
	assert_true((hired_row.get_node("Top/Name") as Label).text.contains(" - Cleaner, skill "))
	var let_go: Button = hired_row.get_node("Top/Action") as Button
	assert_eq(let_go.text, "Let go")
	assert_false(let_go.disabled, "the last cleaner may be let go")
	let_go.pressed.emit()
	assert_eq(_requests, [candidate.id, candidate.id] as Array[StringName])
	assert_eq(_roster.members().size(), 3, "the panel does not make staffing changes")
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_true(let_go.disabled)
	let_go.pressed.emit()
	assert_eq(_requests.size(), 2, "staff changes are morning only")


func test_candidate_trait_text_describes_only_the_bonus_available_to_their_role() -> void:
	var cases: Array[Dictionary] = [
		{"role": &"cook", "trait": &"careful",
			"text": "Careful: Adds 0.05 to the quality of meals they cook."},
		{"role": &"server", "trait": &"careful",
			"text": "Careful: Works with care. No special bonus in this role."},
		{"role": &"cleaner", "trait": &"careful",
			"text": "Careful: Works with care. No special bonus in this role."},
		{"role": &"cook", "trait": &"cheerful",
			"text": "Cheerful: Friendly manner. No special bonus in this role."},
		{"role": &"server", "trait": &"cheerful",
			"text": "Cheerful: Guests they serve have 10% more patience for food."},
		{"role": &"cleaner", "trait": &"cheerful",
			"text": "Cheerful: Friendly manner. No special bonus in this role."},
	]
	for example: Dictionary in cases:
		var saved: Dictionary = _roster.to_dict()
		saved["candidates"][0]["role"] = String(example["role"])
		saved["candidates"][0].erase("growth")
		saved["candidates"][0]["trait"] = String(example["trait"])
		assert_true(_roster.from_dict(saved))
		var before: Dictionary = _roster.to_dict()
		_panel.refresh()
		var candidate: StaffMember = _roster.candidates()[0]
		var trait_label: Label = _panel.row_for(candidate.id).get_node("Trait") as Label
		assert_eq(trait_label.text, example["text"])
		assert_eq(_roster.to_dict(), before, "describing a trait never changes the roster")


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


func test_employee_xp_bar_and_three_mood_faces_follow_saved_growth() -> void:
	for mood: int in [3, 2, 1]:
		var saved: Dictionary = _roster.to_dict()
		saved["members"][0]["growth"]["xp"]["cooking"] = 44
		saved["members"][0]["growth"]["mood"] = mood
		assert_true(_roster.from_dict(saved))
		_panel.refresh()
		var row: Control = _panel.row_for(&"starter_cook")
		var bar: ProgressBar = row.get_node("Growth/XP") as ProgressBar
		var face: Label = row.get_node("Growth/Mood") as Label
		assert_eq(int(bar.value), 44)
		assert_eq(int(bar.max_value), StaffPanel.GROWTH_RULES.needed_for_next_level(3))
		assert_eq(face.text, [":(", ":|", ":)"][mood - 1])
		assert_eq(face.tooltip_text, ["Upset", "Okay", "Happy"][mood - 1])
		assert_eq(face.mouse_filter, Control.MOUSE_FILTER_PASS,
			"the mood word must be available as a tooltip")
		assert_eq((row.get_node("Growth/XPLabel") as Label).text,
			"XP 44/%d" % StaffPanel.GROWTH_RULES.needed_for_next_level(3))
		assert_null(_panel.row_for(&"candidate_1_0").get_node_or_null("Growth"),
			"only hired members show progression")
	var capped: Dictionary = _roster.to_dict()
	capped["members"][0]["skill"] = 5
	capped["members"][0]["growth"]["skills"]["cooking"] = 5
	capped["members"][0]["growth"]["xp"]["cooking"] = 0
	assert_true(_roster.from_dict(capped))
	_panel.refresh()
	var capped_row: Control = _panel.row_for(&"starter_cook")
	assert_eq((capped_row.get_node("Growth/XPLabel") as Label).text, "Skill maxed out")
	assert_eq((capped_row.get_node("Growth/XP") as ProgressBar).value, 1.0)


func test_raise_cards_and_quit_notice_are_morning_only_requests() -> void:
	var saved: Dictionary = _roster.to_dict()
	saved["members"][0]["skill"] = 4
	saved["members"][0]["growth"]["skills"]["cooking"] = 4
	saved["members"][0]["growth"]["raises"] = [{"skill": "cooking", "level": 4}]
	assert_true(_roster.from_dict(saved))
	var before: Dictionary = _roster.to_dict()
	var notices: Array[Dictionary] = [{"member_id": &"starter_cook",
		"message": "Sam left after their raise requests were refused."}]
	_panel.set_morning(2, notices)
	var notice_box: VBoxContainer = _panel.get_node("Panel/Content/Scroll/List/MorningNotices") as VBoxContainer
	assert_true(notice_box.visible)
	assert_eq((notice_box.get_child(0) as Label).text,
		"Sam left after their raise requests were refused.")
	assert_true((_panel.get_node("Panel/Content/Scroll/List/RaiseTitle") as Label).visible)
	var card: Control = _panel.offer_row_for(&"starter_cook")
	assert_not_null(card)
	assert_true((card.get_node("Message") as Label).text.contains("Alex (Cook) got better at cooking"))
	assert_false((card.get_node("Message") as Label).text.contains("starter_cook"))
	var accept: Button = card.get_node("Actions/Accept") as Button
	var decline: Button = card.get_node("Actions/NotNow") as Button
	_panel.refresh()
	assert_true(_panel.offer_row_for(&"starter_cook").get_node("Actions/Accept") == accept,
		"refresh keeps a pending choice's buttons stable")
	accept.pressed.emit()
	decline.pressed.emit()
	assert_eq(_raise_accepts, [&"starter_cook"] as Array[StringName])
	assert_eq(_raise_declines, [&"starter_cook"] as Array[StringName])
	assert_eq(_roster.to_dict(), before, "the panel never settles a raise")
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_false(notice_box.visible)
	assert_null(_panel.offer_row_for(&"starter_cook"))
	accept.pressed.emit()
	assert_eq(_raise_accepts.size(), 1, "a stale hidden button cannot request a raise")
	_panel.set_phase(SimClock.Phase.MORNING)
	assert_not_null(_panel.offer_row_for(&"starter_cook"))


func test_skill_update_with_unchanged_pay_has_only_an_acknowledgement() -> void:
	var saved: Dictionary = _roster.to_dict()
	saved["members"][1]["growth"]["skills"]["cleaning"] = 2
	saved["members"][1]["growth"]["raises"] = [{"skill": "cleaning", "level": 2}]
	assert_true(_roster.from_dict(saved))
	var notices: Array[Dictionary] = []
	_panel.set_morning(2, notices)
	var before: Dictionary = _roster.to_dict()
	var card: Control = _panel.offer_row_for(&"starter_server")
	assert_not_null(card)
	if card == null:
		return
	assert_true((card.get_node("Message") as Label).text.contains("Their pay stays at"))
	assert_null(card.get_node_or_null("Actions/NotNow"))
	var acknowledge: Button = card.get_node("Actions/Accept") as Button
	assert_eq(acknowledge.text, "Got it")
	_panel.refresh()
	assert_true(_panel.offer_row_for(&"starter_server").get_node("Actions/Accept") == acknowledge)
	acknowledge.pressed.emit()
	assert_eq(_raise_accepts, [&"starter_server"] as Array[StringName])
	assert_true(_raise_declines.is_empty())
	assert_eq(_roster.to_dict(), before, "Main handles the acknowledgement request")


func test_retired_offer_button_cannot_request_the_next_queued_raise() -> void:
	var saved: Dictionary = _roster.to_dict()
	saved["members"][0]["skill"] = 5
	saved["members"][0]["growth"]["skills"]["cooking"] = 5
	saved["members"][0]["growth"]["raises"] = [
		{"skill": "cooking", "level": 4}, {"skill": "cooking", "level": 5}]
	assert_true(_roster.from_dict(saved))
	var notices: Array[Dictionary] = []
	_panel.set_morning(2, notices)
	var old_button: Button = _panel.offer_row_for(&"starter_cook").get_node("Actions/Accept") as Button
	assert_true(_roster.accept_raise(&"starter_cook", SimClock.Phase.MORNING))
	_panel.refresh()
	var current: Control = _panel.offer_row_for(&"starter_cook")
	assert_not_null(current)
	assert_eq(_roster.morning_raise_offers(2, SimClock.Phase.MORNING)[0]["level"], 5)
	var current_button: Button = current.get_node("Actions/Accept") as Button
	assert_true(current_button != old_button)
	old_button.pressed.emit()
	assert_true(_raise_accepts.is_empty(), "a hidden button cannot settle a newer offer")
	current_button.pressed.emit()
	assert_eq(_raise_accepts, [&"starter_cook"] as Array[StringName])


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


func _record_accept(id: StringName) -> void:
	_raise_accepts.append(id)


func _record_decline(id: StringName) -> void:
	_raise_declines.append(id)


func _luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


func _linear_channel(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)
