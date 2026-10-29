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
var _priority_requests: Array[Dictionary] = []
var _native_host: SubViewport


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
	_panel.job_priority_requested.connect(_record_priority)
	_panel.bind_roster(_roster)
	_tray_requests.clear()
	_raise_accepts.clear()
	_raise_declines.clear()
	_priority_requests.clear()


func after_each() -> void:
	_panel.free()
	if is_instance_valid(_native_host):
		_native_host.free()
	_native_host = null


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
	saved["candidates"][0].erase("priorities")
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
		saved["candidates"][0].erase("priorities")
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
		var growth: HBoxContainer = row.get_node("Growth") as HBoxContainer
		assert_false(growth.has_theme_constant_override(&"separation"),
			"the XP line keeps the shared HBox spacing")
		var inset: Control = growth.get_node("XPInset") as Control
		assert_eq(inset.custom_minimum_size.x, 8.0)
		assert_eq(inset.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		assert_eq(inset.focus_mode, Control.FOCUS_NONE)
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
	var close: Button = _panel.get_node("Panel/Content/Header/Close") as Button
	var candidate: StaffMember = _roster.candidates()[0]
	var held_button: Button = _panel.row_for(candidate.id).get_node("Top/Action") as Button
	var before: Dictionary = _roster.to_dict()
	_panel.show()
	assert_eq(close.text, "Close")
	assert_false(close.disabled)
	assert_eq(close.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_true(close.get_parent() == _panel.get_node("Panel/Content/Header"), "Close stays beside the title")
	assert_false(_panel.get_node("Panel/Content/Scroll").is_ancestor_of(close), "Close stays outside the bounded scroll area")
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


func test_priority_matrix_has_human_labels_role_defaults_and_locked_unsupported_work() -> void:
	var list: VBoxContainer = _panel.get_node("Panel/Content/Scroll/List") as VBoxContainer
	assert_true(list.get_node("Members").get_index() < list.get_node("Priorities").get_index(),
		"team cards and their XP appear before priorities")
	var lock_note: Label = _panel.get_node("%MainJobNote") as Label
	assert_true(lock_note.text.contains("main job cannot be turned off"))
	var grid: GridContainer = _panel.get_node("%PriorityGrid") as GridContainer
	assert_eq(grid.columns, 6)
	assert_eq(grid.get_child_count(), 18, "one header and two employee rows; candidates have no job cells")
	assert_eq((grid.get_child(0) as Label).text, "Team member")
	var labels: Array[String] = ["Cooking", "Serving", "Bussing", "Washing", "Cleaning"]
	for index: int in range(labels.size()):
		assert_eq((grid.get_child(index + 1) as Label).text, labels[index])
	for member: StaffMember in _roster.members():
		var choices: StaffJobPriorities = _roster.job_priorities(member.id)
		for job: StringName in StaffJobPriorities.JOBS:
			var button: Button = _panel.priority_button_for(member.id, job)
			assert_not_null(button)
			var supported: bool = StaffJobPriorities.supports(member.role, job)
			assert_eq(button.text, StaffJobPriorities.level_label(choices.priority(job)) if supported else "—")
			assert_eq(button.disabled, not supported)
			assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)
			assert_false(button.clip_text)
	assert_eq(_panel.priority_button_for(&"starter_cook", &"cooking").text, "High")
	assert_eq(_panel.priority_button_for(&"starter_server", &"serving").text, "Normal")
	assert_eq(_panel.priority_button_for(&"starter_server", &"cleaning").text, "Low")
	var unsupported: Button = _panel.priority_button_for(&"starter_cook", &"serving")
	assert_eq(unsupported.text, "—")
	assert_true(unsupported.tooltip_text.contains("not available for this role"))
	unsupported.pressed.emit()
	assert_true(_priority_requests.is_empty())
	assert_null(_panel.priority_button_for(_roster.candidates()[0].id, &"cooking"))
	assert_true(_panel.priority_button_for(&"starter_cook", &"cooking").tooltip_text.contains("main job cannot be Off"))


func test_priority_cycles_are_typed_requests_only_and_main_jobs_skip_off() -> void:
	_hire_cleaner()
	var candidate: StaffMember = _roster.candidates()[0]
	var hire: Button = _panel.row_for(candidate.id).get_node("Top/Action") as Button
	for member: StaffMember in _roster.members():
		var job: StringName = StaffJobPriorities.main_job(member.role)
		assert_true(_roster.set_job_priority(member.id, job, StaffJobPriorities.Level.HIGH))
		_panel.refresh()
		_assert_priority_cycle(member.id, job, [StaffJobPriorities.Level.NORMAL,
			StaffJobPriorities.Level.LOW, StaffJobPriorities.Level.HIGH] as Array[int])
	assert_true(_roster.set_job_priority(&"starter_server", &"bussing", StaffJobPriorities.Level.HIGH))
	_panel.refresh()
	_assert_priority_cycle(&"starter_server", &"bussing", [StaffJobPriorities.Level.NORMAL,
		StaffJobPriorities.Level.LOW, StaffJobPriorities.Level.OFF, StaffJobPriorities.Level.HIGH] as Array[int])
	assert_true(_panel.row_for(candidate.id).get_node("Top/Action") == hire,
		"priority-only controller echoes do not rebuild unrelated hire buttons")


func test_priorities_work_in_all_phases_while_hire_raise_and_tray_gates_stay_morning_only() -> void:
	var saved: Dictionary = _roster.to_dict()
	saved["members"][0]["skill"] = 4
	saved["members"][0]["growth"]["skills"]["cooking"] = 4
	saved["members"][0]["growth"]["raises"] = [{"skill": "cooking", "level": 4}]
	assert_true(_roster.from_dict(saved))
	_panel.set_morning(2, [] as Array[Dictionary])
	_panel.set_trays(0, PackedInt32Array([60, 150]), 200)
	var candidate: StaffMember = _roster.candidates()[0]
	var original: Dictionary = _roster.to_dict()
	var cell: Button = _panel.priority_button_for(&"starter_cook", &"cooking")
	for phase: int in [SimClock.Phase.MORNING, SimClock.Phase.OPEN,
			SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]:
		_panel.set_phase(phase)
		assert_true(_panel.priority_button_for(&"starter_cook", &"cooking") == cell)
		assert_false(cell.disabled, "job choices do not inherit the morning staffing gate")
		if phase != SimClock.Phase.MORNING:
			assert_true((_panel.get_node("%Status") as Label).text.contains("Job priorities can change now"))
		var count: int = _priority_requests.size()
		cell.pressed.emit()
		assert_eq(_priority_requests.size(), count + 1)
		assert_eq(_priority_requests.back(), {"id": &"starter_cook", "job": &"cooking",
			"value": StaffJobPriorities.Level.NORMAL})
		assert_eq(_roster.to_dict(), original, "requesting a choice never edits staff or their saved state")
		assert_eq((_panel.row_for(candidate.id).get_node("Top/Action") as Button).disabled,
			phase != SimClock.Phase.MORNING)
		assert_eq((_panel.get_node("%TraysBuy") as Button).disabled, phase != SimClock.Phase.MORNING)
		assert_eq(_panel.offer_row_for(&"starter_cook") == null, phase != SimClock.Phase.MORNING)


func test_server_cleaning_stays_a_configurable_conditional_fallback_and_stale_cells_do_not_request() -> void:
	var server: Button = _panel.priority_button_for(&"starter_server", &"cleaning")
	assert_false(server.disabled)
	assert_true(server.tooltip_text.contains("only when no Cleaner"))
	var cleaner_id: StringName = _hire_cleaner()
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_true(_panel.priority_button_for(&"starter_server", &"cleaning") == server)
	assert_false(server.disabled, "supported fallback can be prepared for future availability")
	assert_eq(server.text, "Low")
	assert_true(server.tooltip_text.contains("setting is inactive"))
	assert_true((_panel.get_node("%PriorityAvailability") as Label).text.contains("Cleaning settings are inactive"))
	var cleaner: Button = _panel.priority_button_for(cleaner_id, &"cleaning")
	assert_false(cleaner.disabled)
	assert_true(_panel.priority_button_for(cleaner_id, &"washing").disabled)
	assert_true(_roster.let_go(cleaner_id))
	_panel.refresh()
	assert_false(server.tooltip_text.contains("inactive"))
	cleaner.pressed.emit()
	assert_true(_priority_requests.is_empty(), "a retired employee's button cannot address another row")
	var old: Button = server
	_panel.bind_roster(null)
	old.pressed.emit()
	assert_true(_priority_requests.is_empty())
	assert_null(_panel.priority_button_for(&"starter_server", &"cleaning"))
	_panel.bind_roster(_roster)
	assert_true(_panel.priority_button_for(&"starter_server", &"cleaning") != old)
	old.pressed.emit()
	assert_true(_priority_requests.is_empty(), "a stale same-ID button is not a current cell")


func test_native_priority_down_growth_refresh_up_keeps_one_cell_and_one_request() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_native_host = SubViewport.new()
	_native_host.size = Vector2i(1600, 900)
	_native_host.handle_input_locally = true
	_native_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_native_host)
	_native_host.add_child(_panel)
	_panel.show()
	_panel.set_phase(SimClock.Phase.OPEN)
	await _priority_frames(3)
	var cell: Button = _panel.priority_button_for(&"starter_server", &"bussing")
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	scroll.ensure_control_visible(cell)
	await _priority_frames(1)
	var point: Vector2 = cell.get_global_rect().get_center()
	_native_host.push_input(_priority_mouse(point, true), true)
	assert_true(cell.is_pressed())
	var saved: Dictionary = _roster.to_dict()
	saved["members"][0]["growth"]["mood"] = 2
	assert_true(_roster.from_dict(saved))
	_panel.refresh()
	_panel.bind_roster(_roster)
	assert_true(_panel.priority_button_for(&"starter_server", &"bussing") == cell)
	assert_true(cell.is_pressed(), "growth rows may refresh while the matrix keeps its native press")
	var before: Dictionary = _roster.to_dict()
	await _priority_frames(1)
	assert_true(cell.get_global_rect().has_point(point))
	_native_host.push_input(_priority_mouse(point, false), true)
	assert_eq(_priority_requests, [{"id": &"starter_server", "job": &"bussing",
		"value": StaffJobPriorities.Level.LOW}] as Array[Dictionary])
	assert_eq(_roster.to_dict(), before)
	assert_eq(cell.text, "Normal", "the controller must accept and echo a requested choice")


func test_priority_words_and_colors_use_readable_shared_theme_states() -> void:
	assert_true(_roster.set_job_priority(&"starter_server", &"bussing", StaffJobPriorities.Level.OFF))
	_panel.refresh()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	tree.root.add_child(_panel)
	await tree.process_frame
	var normal: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("normal", "Button") as StyleBoxFlat
	var accent: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("pressed", "Button") as StyleBoxFlat
	var muted: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("disabled", "Button") as StyleBoxFlat
	var high: Button = _panel.priority_button_for(&"starter_cook", &"cooking")
	var regular: Button = _panel.priority_button_for(&"starter_server", &"serving")
	var low: Button = _panel.priority_button_for(&"starter_server", &"cleaning")
	var chosen_off: Button = _panel.priority_button_for(&"starter_server", &"bussing")
	var locked: Button = _panel.priority_button_for(&"starter_cook", &"serving")
	assert_eq((high.get_theme_stylebox("normal") as StyleBoxFlat).border_color, accent.bg_color)
	assert_eq((regular.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, normal.bg_color)
	assert_eq((low.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, muted.bg_color)
	assert_eq(chosen_off.text, "Off")
	assert_false(chosen_off.disabled, "supported work set to Off remains a player choice")
	assert_eq((chosen_off.get_theme_stylebox("disabled") as StyleBoxFlat).bg_color,
		StaffPanel.SHARED_THEME.get_color("font_color", "Button"))
	assert_eq(locked.text, "—")
	assert_true(locked.disabled, "unsupported work is locked")
	var locked_style: StyleBoxFlat = locked.get_theme_stylebox("disabled") as StyleBoxFlat
	var off_style: StyleBoxFlat = chosen_off.get_theme_stylebox("normal") as StyleBoxFlat
	var low_style: StyleBoxFlat = low.get_theme_stylebox("normal") as StyleBoxFlat
	var locked_text: Color = locked.get_theme_color("font_disabled_color")
	assert_ne(locked_style.bg_color, off_style.bg_color, "a locked dash never looks like a chosen Off")
	assert_ne(locked_text, chosen_off.get_theme_color("font_color"))
	assert_ne(locked_style.bg_color, low_style.bg_color, "a locked dash never looks like Low")
	assert_ne(locked_style.border_color, low_style.border_color)
	assert_ne(locked_text, low.get_theme_color("font_color"))
	assert_eq(locked_style.bg_color,
		(StaffPanel.SHARED_THEME.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color,
		"a locked cell uses the panel's own fill")
	assert_eq(locked_style.border_color, Color(muted.border_color, StaffPanel.LOCKED_BORDER_ALPHA))
	assert_eq(locked_text, Color(StaffPanel.SHARED_THEME.get_color("font_color", "Button"), StaffPanel.LOCKED_TEXT_ALPHA))
	# The faded dash marks "not a choice"; it is intentionally below text contrast
	# but must still be visible on the panel.
	var dash: Color = locked_style.bg_color.lerp(Color(locked_text, 1.0), locked_text.a)
	var dash_contrast: float = (maxf(_luminance(dash), _luminance(locked_style.bg_color)) + 0.05) \
		/ (minf(_luminance(dash), _luminance(locked_style.bg_color)) + 0.05)
	assert_true(dash_contrast >= 2.0, "the faded dash stays visible (contrast %.2f)" % dash_contrast)
	for button: Button in [high, regular, low, chosen_off]:
		var state: StringName = &"disabled" if button.disabled else &"normal"
		var color_name: StringName = &"font_disabled_color" if button.disabled else &"font_color"
		var background: Color = (button.get_theme_stylebox(state) as StyleBoxFlat).bg_color
		var foreground: Color = button.get_theme_color(color_name)
		var contrast: float = (maxf(_luminance(foreground), _luminance(background)) + 0.05) \
			/ (minf(_luminance(foreground), _luminance(background)) + 0.05)
		assert_true(contrast >= 4.5, "%s retains readable words in its shared-theme colors" % button.text)


func test_full_priority_matrix_fits_private_windows_and_scrolls_at_supported_interface_scales() -> void:
	_hire_cleaner()
	for candidate: StaffMember in _roster.candidates():
		assert_true(_roster.hire(candidate.id))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 73
	_roster.draw_candidates(2, random)
	assert_true(_roster.hire(_roster.candidates()[0].id))
	assert_eq(_roster.members().size(), StaffRoster.CAPACITY)
	var saved: Dictionary = _roster.to_dict()
	saved["members"][StaffRoster.CAPACITY - 1]["name"] = "Alexandria Morgan"
	assert_true(_roster.from_dict(saved))
	_panel.refresh()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_native_host = SubViewport.new()
	_native_host.size = Vector2i(1600, 900)
	_native_host.gui_embed_subwindows = true
	_native_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_native_host)
	var window: Window = Window.new()
	window.borderless = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1600, 900)
	_native_host.add_child(window)
	window.add_child(_panel)
	_panel.show()
	var panel: Control = _panel.get_node("Panel") as Control
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	var grid: GridContainer = _panel.get_node("%PriorityGrid") as GridContainer
	var close: Button = _panel.get_node("%Close") as Button
	for physical: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		window.size = physical
		for scale: float in [1.25, 1.5]:
			window.content_scale_factor = scale
			for phase: int in [SimClock.Phase.MORNING, SimClock.Phase.OPEN,
					SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]:
				_panel.set_phase(phase)
				await _priority_frames(3)
				var context: String = "%s at %s/%s panel=%s scroll=%s" % [
					phase, physical, scale, panel.get_global_rect(), scroll.get_global_rect()]
				assert_true(window.get_visible_rect().grow(-11.5).encloses(panel.get_global_rect()), context)
				assert_true(panel.get_global_rect().grow(0.5).encloses(scroll.get_global_rect()), context)
				assert_true(panel.get_global_rect().grow(0.5).encloses(close.get_global_rect()), context)
				assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
				assert_true(grid.get_combined_minimum_size().x <= scroll.size.x + 0.5,
					"%s grid_min=%s" % [context, grid.get_combined_minimum_size()])
				assert_true(scroll.get_v_scroll_bar().visible, "the full team remains available through bounded scrolling")
				for member: StaffMember in _roster.members():
					var xp_label: Label = _panel.row_for(member.id).get_node("Growth/XPLabel") as Label
					var xp_bounds: Rect2 = xp_label.get_global_rect()
					var scrollbar_bounds: Rect2 = scroll.get_v_scroll_bar().get_global_rect()
					assert_true(xp_bounds.position.x >= scroll.get_global_rect().position.x - 0.5, context)
					var scrollbar_gap: float = scrollbar_bounds.position.x - xp_bounds.end.x
					assert_true(scrollbar_gap >= 6.0,
						"XP text keeps a real inset from the scrollbar (%s px): %s" % [scrollbar_gap, context])
					for job: StringName in StaffJobPriorities.JOBS:
						var button: Button = _panel.priority_button_for(member.id, job)
						assert_true(button.size.x >= button.get_combined_minimum_size().x - 0.5, context)
						assert_true(button.get_global_rect().position.x >= scroll.get_global_rect().position.x - 0.5, context)
						assert_true(button.get_global_rect().end.x <= scroll.get_global_rect().end.x + 0.5, context)
				var last: StaffMember = _roster.members().back()
				var last_cell: Button = _panel.priority_button_for(last.id, &"cleaning")
				scroll.ensure_control_visible(last_cell)
				await _priority_frames(1)
				assert_true(scroll.get_global_rect().grow(0.5).encloses(last_cell.get_global_rect()), context)


func _assert_priority_cycle(id: StringName, job: StringName, expected: Array[int]) -> void:
	_priority_requests.clear()
	var button: Button = _panel.priority_button_for(id, job)
	for value: int in expected:
		var before: Dictionary = _roster.to_dict()
		var count: int = _priority_requests.size()
		button.pressed.emit()
		assert_eq(_priority_requests.size(), count + 1)
		var request: Dictionary = _priority_requests.back()
		assert_eq(request, {"id": id, "job": job, "value": value})
		assert_eq(typeof(request["id"]), TYPE_STRING_NAME)
		assert_eq(typeof(request["job"]), TYPE_STRING_NAME)
		assert_eq(typeof(request["value"]), TYPE_INT)
		assert_eq(_roster.to_dict(), before, "the panel never writes a priority itself")
		assert_true(_roster.set_job_priority(id, job, value), "fixture controller accepts the request")
		_panel.refresh()
		assert_true(_panel.priority_button_for(id, job) == button)
		assert_eq(button.text, StaffJobPriorities.level_label(value))


func _hire_cleaner() -> StringName:
	var saved: Dictionary = _roster.to_dict()
	saved["candidates"][0]["role"] = "cleaner"
	saved["candidates"][0].erase("growth")
	saved["candidates"][0].erase("priorities")
	saved["candidates"][0]["wage"] = EconomyTuning.new().staff_wage(&"cleaner", int(saved["candidates"][0]["skill"]))
	assert_true(_roster.from_dict(saved))
	var id: StringName = _roster.candidates()[0].id
	assert_true(_roster.hire(id))
	_panel.refresh()
	return id


func _priority_frames(count: int) -> void:
	for frame: int in range(count):
		await (Engine.get_main_loop() as SceneTree).process_frame


func _priority_mouse(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return event


func _record_priority(id: StringName, job: StringName, value: int) -> void:
	_priority_requests.append({"id": id, "job": job, "value": value})


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
