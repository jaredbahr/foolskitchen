extends TestCase
## The goals panel displays supplied state; it never evaluates or applies it.

const PANEL: PackedScene = preload("res://src/ui/goals_panel.tscn")

var _panel: GoalsPanel
var _catalogue: MilestoneSet
var _close_requests: int = 0


func before_each() -> void:
	_panel = PANEL.instantiate() as GoalsPanel
	_catalogue = _selection_catalogue()
	_panel.close_requested.connect(_record_close)
	_panel.set_goals(_catalogue, [] as Array[StringName], {} as Dictionary[StringName, float], 2)
	_close_requests = 0


func after_each() -> void:
	_panel.free()


func test_selection_keeps_authored_order_limits_active_goals_and_shows_known_completions() -> void:
	var completed: Array[StringName] = [&"done", &"done_locked", &"unknown_private_id"]
	var progress: Dictionary[StringName, float] = {&"first": 4.0, &"second": 3.0, &"third": 2.0}
	_panel.set_goals(_catalogue, completed, progress, 2)
	assert_eq(_panel.active_goal_ids(), [&"first", &"second", &"third"] as Array[StringName])
	assert_eq(_panel.completed_goal_ids(), [&"done", &"done_locked"] as Array[StringName])
	assert_null(_panel.goal_card_for(&"locked"))
	assert_null(_panel.goal_card_for(&"fourth"), "only three unlocked uncompleted goals are active")
	assert_null(_panel.goal_card_for(&"unknown_private_id"), "unknown saved IDs are never rendered")
	assert_eq((_panel.goal_card_for(&"done") as Control).get_meta(&"completed"), true)
	assert_true((_panel.get_node("Panel/Content/Scroll/List/ActiveHeading") as Label).visible)
	assert_true((_panel.get_node("Panel/Content/Scroll/List/CompletedHeading") as Label).visible)


func test_progress_is_finite_bounded_and_rewards_are_player_readable() -> void:
	var catalogue: MilestoneSet = _single_goal_catalogue([
		_goal(&"partway", "One busy lunch", 10.0, 1),
		_goal(&"negative", "A rough lunch", 10.0, 1),
		_goal(&"over", "A very busy lunch", 10.0, 1),
	] as Array[Milestone])
	var progress: Dictionary[StringName, float] = {
		&"partway": 2.5,
		&"negative": -7.0,
		&"over": 99.0,
	}
	_panel.set_goals(catalogue, [] as Array[StringName], progress, 1)
	assert_almost_eq(_bar_value(&"partway"), 0.25, 0.00001)
	assert_almost_eq(_bar_value(&"negative"), 0.0, 0.00001)
	assert_almost_eq(_bar_value(&"over"), 1.0, 0.00001)
	var card: Control = _panel.goal_card_for(&"partway")
	assert_eq((card.get_node("Body/ProgressText") as Label).text, "Progress: 2 / 10 guests")
	assert_eq((card.get_node("Body/Reward") as Label).text, "Reward: 20 XP   Cash: $10")
	assert_false((card.get_node("Body/ProgressBar") as ProgressBar).show_percentage)


func test_non_finite_progress_falls_back_to_zero_within_active_goal_limit() -> void:
	var catalogue: MilestoneSet = _single_goal_catalogue([
		_goal(&"nan", "No reading", 10.0, 1),
		_goal(&"positive_infinity", "Too high to measure", 10.0, 1),
		_goal(&"negative_infinity", "Too low to measure", 10.0, 1),
	] as Array[Milestone])
	var progress: Dictionary[StringName, float] = {
		&"nan": NAN,
		&"positive_infinity": INF,
		&"negative_infinity": -INF,
	}
	_panel.set_goals(catalogue, [] as Array[StringName], progress, 1)
	assert_eq(_panel.active_goal_ids().size(), GoalsPanel.ACTIVE_GOAL_LIMIT)
	for id: StringName in [&"nan", &"positive_infinity", &"negative_infinity"]:
		var value: float = _bar_value(id)
		assert_true(is_finite(value), "non-finite progress never reaches the native bar")
		assert_almost_eq(value, 0.0, 0.00001, "non-finite progress falls back to zero")
		var progress_label: Label = _panel.goal_card_for(id).get_node("Body/ProgressText") as Label
		assert_eq(progress_label.text, "Progress: 0 / 10 guests")


func test_reputation_profit_and_level_progress_use_readable_units() -> void:
	var reputation: Milestone = _goal(&"reputation", "Good word", 3.5, 1)
	reputation.condition = Milestone.Condition.REPUTATION
	var profit: Milestone = _goal(&"profit", "Black ink", 40.0, 1)
	profit.condition = Milestone.Condition.PROFIT_TODAY
	var level: Milestone = _goal(&"level", "A level up", 3.0, 1)
	level.condition = Milestone.Condition.OWNER_LEVEL
	var catalogue: MilestoneSet = _single_goal_catalogue([reputation, profit, level] as Array[Milestone])
	var progress: Dictionary[StringName, float] = {&"reputation": 2.36, &"profit": 25.0, &"level": 2.0}
	_panel.set_goals(catalogue, [] as Array[StringName], progress, 3)
	assert_eq((_panel.goal_card_for(&"reputation").get_node("Body/ProgressText") as Label).text,
		"Progress: 2.4 / 3.5 stars")
	assert_eq((_panel.goal_card_for(&"profit").get_node("Body/ProgressText") as Label).text,
		"Progress: $25 / $40")
	assert_eq((_panel.goal_card_for(&"level").get_node("Body/ProgressText") as Label).text,
		"Progress: Level 2 / 3")


func test_completed_cards_are_full_greyed_and_do_not_mutate_inputs() -> void:
	var completed: Array[StringName] = [&"first", &"done"]
	var progress: Dictionary[StringName, float] = {&"first": 1.0, &"done": 0.0}
	var saved_completed: Array[StringName] = completed.duplicate()
	var saved_progress: Dictionary[StringName, float] = progress.duplicate()
	var first_title: String = _catalogue.by_id(&"first").title
	_panel.set_goals(_catalogue, completed, progress, 2)
	var completed_card: Control = _panel.goal_card_for(&"done")
	assert_almost_eq((completed_card.get_node("Body/ProgressBar") as ProgressBar).value, 1.0)
	assert_eq((completed_card.get_node("Body/ProgressText") as Label).text, "Completed")
	var original_label: Color = GoalsPanel.SHARED_THEME.get_color("font_color", "Label")
	var completed_label: Label = completed_card.get_node("Body/Title") as Label
	assert_true(completed_label.has_theme_color_override(&"font_color"))
	assert_almost_eq(completed_label.get_theme_color(&"font_color").a, original_label.a * 0.55)
	assert_eq(completed, saved_completed)
	assert_eq(progress, saved_progress)
	assert_eq(_catalogue.by_id(&"first").title, first_title)
	assert_eq(_catalogue.milestones.size(), 7)


func test_empty_or_invalid_catalogue_shows_friendly_state_without_leaking_ids() -> void:
	var unknown: Array[StringName] = [&"former_private_goal"]
	_panel.set_goals(null, unknown, {} as Dictionary[StringName, float], 9)
	assert_true((_panel.get_node("Panel/Content/Scroll/List/EmptyState") as Label).visible)
	assert_eq(_panel.active_goal_ids(), [] as Array[StringName])
	assert_eq(_panel.completed_goal_ids(), [] as Array[StringName])
	assert_false((_panel.get_node("Panel/Content/Scroll/List/EmptyState") as Label).text.contains("former_private_goal"))
	var invalid: MilestoneSet = MilestoneSet.new()
	_panel.set_goals(invalid, unknown, {} as Dictionary[StringName, float], 9)
	assert_true((_panel.get_node("Panel/Content/Scroll/List/EmptyState") as Label).visible)
	assert_eq((_panel.get_node("Panel/Content/Scroll/List/ActiveRows") as VBoxContainer).get_child_count(), 0)
	assert_eq((_panel.get_node("Panel/Content/Scroll/List/CompletedRows") as VBoxContainer).get_child_count(), 0)


func test_close_emits_request_and_responsive_layout_uses_native_scroll_controls() -> void:
	var panel: Control = _panel.get_node("Panel") as Control
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	var close: Button = _panel.get_node("Panel/Content/Header/Close") as Button
	assert_eq(_panel.theme, GoalsPanel.SHARED_THEME)
	assert_eq(_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(panel.mouse_force_pass_scroll_events)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_false(scroll.mouse_force_pass_scroll_events)
	assert_eq(close.focus_mode, Control.FOCUS_NONE)
	close.pressed.emit()
	assert_eq(_close_requests, 1)
	assert_false(_panel.visible, "the owning session controls panel visibility")


func test_full_completed_catalogue_stays_bounded_and_scrollable_in_native_windows() -> void:
	await _assert_full_catalogue_window(Vector2i(1280, 720))
	await _assert_full_catalogue_window(Vector2i(1600, 900))


func _assert_full_catalogue_window(window_size: Vector2i) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport: SubViewport = SubViewport.new()
	viewport.size = window_size
	viewport.handle_input_locally = true
	tree.root.add_child(viewport)
	_panel.set_goals(_full_completed_catalogue(), _full_completed_ids(),
		{} as Dictionary[StringName, float], 1)
	_panel.show()
	viewport.add_child(_panel)
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	scroll.scroll_vertical = 0
	await tree.process_frame
	await tree.process_frame
	var panel: Control = _panel.get_node("Panel") as Control
	var header: Control = _panel.get_node("Panel/Content/Header") as Control
	var close: Control = _panel.get_node("Panel/Content/Header/Close") as Control
	var panel_rect: Rect2 = panel.get_global_rect()
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(window_size))
	assert_true(viewport_rect.encloses(panel_rect), "the panel fits inside %s" % str(window_size))
	assert_true(panel_rect.encloses(header.get_global_rect()), "the header stays inside the panel")
	assert_true(header.get_global_rect().encloses(close.get_global_rect()), "Close stays inside its header")
	assert_true(panel_rect.encloses(scroll.get_global_rect()), "the scroll area stays inside the panel")
	var first_card: Control = _panel.goal_card_for(&"career_goal_00")
	assert_true(first_card.size.x > 0.0 and first_card.size.y > 0.0, "long goal text has a measured card")
	assert_true(panel_rect.encloses(first_card.get_global_rect()), "long card width stays within the panel")
	var title: Label = first_card.get_node("Body/Title") as Label
	var reward: Label = first_card.get_node("Body/Reward") as Label
	assert_eq(title.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_eq(reward.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(first_card.get_global_rect().encloses(title.get_global_rect()))
	assert_true(first_card.get_global_rect().encloses(reward.get_global_rect()))
	var scroll_bar: VScrollBar = scroll.get_v_scroll_bar()
	assert_true(scroll_bar.max_value > scroll_bar.page, "the full completed catalogue has scrollable overflow")
	scroll.scroll_vertical = int(scroll_bar.max_value - scroll_bar.page)
	await tree.process_frame
	assert_true(scroll.scroll_vertical > 0, "the native scroll control can reach later completed goals")
	viewport.remove_child(_panel)
	_panel.hide()
	viewport.free()


func _full_completed_catalogue() -> MilestoneSet:
	var goals: Array[Milestone] = []
	for index: int in range(12):
		var id: StringName = StringName("career_goal_%02d" % index)
		var goal: Milestone = _goal(id, "Goal %02d" % index, 50.0, 1)
		if index == 0:
			goal.title = "A particularly long career goal title that should wrap inside the panel"
			goal.description = "Serve a full room, keep the kitchen moving, and send every customer home smiling. " \
				+ "This longer description checks that text wraps within the scrollable card at both tested window sizes."
			goal.reward_xp = 1000000
			goal.reward_cash = 1000000
		goals.append(goal)
	return _single_goal_catalogue(goals)


func _full_completed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for index: int in range(12):
		ids.append(StringName("career_goal_%02d" % index))
	return ids


func _selection_catalogue() -> MilestoneSet:
	return _single_goal_catalogue([
		_goal(&"first", "First goal", 10.0, 1),
		_goal(&"done", "Already done", 10.0, 1),
		_goal(&"locked", "Later goal", 10.0, 3),
		_goal(&"second", "Second goal", 10.0, 2),
		_goal(&"third", "Third goal", 10.0, 1),
		_goal(&"fourth", "Fourth goal", 10.0, 2),
		_goal(&"done_locked", "Completed later goal", 10.0, 4),
	] as Array[Milestone])


func _single_goal_catalogue(goals: Array[Milestone]) -> MilestoneSet:
	var catalogue: MilestoneSet = MilestoneSet.new()
	catalogue.milestones = goals
	return catalogue


func _goal(id: StringName, title: String, target: float, unlock_level: int) -> Milestone:
	var goal: Milestone = Milestone.new()
	goal.id = id
	goal.title = title
	goal.description = "A readable goal description."
	goal.condition = Milestone.Condition.SERVED_TODAY
	goal.target = target
	goal.reward_xp = 20
	goal.reward_cash = 10
	goal.unlock_level = unlock_level
	return goal


func _bar_value(id: StringName) -> float:
	var card: Control = _panel.goal_card_for(id)
	return (card.get_node("Body/ProgressBar") as ProgressBar).value


func _record_close() -> void:
	_close_requests += 1
