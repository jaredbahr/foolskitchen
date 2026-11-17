class_name GoalsPanel
extends Control
## Read-only view of authored goals. The session owns progress and completion.

signal close_requested()

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const ACTIVE_GOAL_LIMIT: int = 3

var _catalogue: MilestoneSet
var _completed_ids: Array[StringName] = []
var _progress: Dictionary[StringName, float] = {}
var _owner_level: int = 1
var _weekly_challenge: WeeklyChallengeState
var _observation: MilestoneDay
var _day: int = 0
var _active_ids: Array[StringName] = []
var _completed_known_ids: Array[StringName] = []
var _record_lines: Array[String] = ["Finish a service day to start your records."]
var _collection_result: CollectionModel.Result
var _opening_week: OpeningWeek
## The running chain's set (#514: Opening week, then Week 2).
var _opening_catalogue: OpeningWeekSet
## Live values by OpeningGoal.Condition, for progress lines.
var _opening_values: Dictionary[int, float] = {}


func _ready() -> void:
	# One wheel step everywhere, and the wheel works over the whole card (#497).
	PanelScroll.attach(self, $Panel as Control, $Panel/Content/Scroll as ScrollContainer)
	_render()
	_render_records()


## The career ladder line (D30); Main owns the tier and its text.
func set_career_tier_line(text: String) -> void:
	var label: Label = %CareerTier as Label
	label.text = text
	label.visible = not text.is_empty()


func set_golden_ladles(prestige_score: int, earned: int) -> void:
	var label: Label = %GoldenLadles as Label
	label.text = "Golden Ladles: %d of %d" % [earned, PrestigeTuning.MAX_LADLES]
	label.visible = earned > 0 or prestige_score > 0


## Detached display text only; Main owns the saved lifetime observations.
func set_records(lines: Array[String]) -> void:
	_record_lines = lines.duplicate()
	_render_records()


func _render_records() -> void:
	var rows: VBoxContainer = %RecordsRows as VBoxContainer
	_clear_rows(rows)
	for line: String in _record_lines:
		var label: Label = _add_label(rows, "Record%d" % rows.get_child_count(), line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Stores detached read-only display inputs; no model or caller collection is mutated.
func set_goals(catalogue: MilestoneSet, completed_ids: Array[StringName],
		progress: Dictionary[StringName, float], owner_level: int,
		weekly_challenge: WeeklyChallengeState = null, day: int = 0,
		observation: MilestoneDay = null) -> void:
	_catalogue = catalogue
	_completed_ids = completed_ids.duplicate()
	_progress = progress.duplicate()
	_owner_level = maxi(owner_level, 1)
	_weekly_challenge = weekly_challenge
	_day = day
	_observation = observation
	_render()


## The goal-chain card (#494, #514), titled by the running chain. Main owns
## the chain; a null or ended chain shows no card.
func set_opening_week(state: OpeningWeek, catalogue: OpeningWeekSet,
		values: Dictionary[int, float], day: int) -> void:
	_opening_week = state
	_opening_catalogue = catalogue
	_opening_values = values.duplicate()
	_day = day
	_render()


## Ids of the opening-week goals on the card, in order (tests and captures).
func opening_goal_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if _opening_week == null:
		return ids
	for goal: OpeningGoal in _opening_week.shown(_opening_catalogue):
		ids.append(goal.id)
	return ids


## Independent collection display; the session computes progress and owns all state.
func set_collections(result: CollectionModel.Result) -> void:
	_collection_result = result
	_render_collections()


## Stable selection snapshots for tests and presentation capture.
func active_goal_ids() -> Array[StringName]:
	return _active_ids.duplicate()


func completed_goal_ids() -> Array[StringName]:
	return _completed_known_ids.duplicate()


func goal_card_for(id: StringName) -> Control:
	var row_groups: Array[VBoxContainer] = [%ActiveRows as VBoxContainer, %CompletedRows as VBoxContainer]
	for rows: VBoxContainer in row_groups:
		for child: Node in rows.get_children():
			if child.get_meta(&"goal_id", &"") == id:
				return child as Control
	return null


func _render() -> void:
	var active_rows: VBoxContainer = %ActiveRows as VBoxContainer
	var completed_rows: VBoxContainer = %CompletedRows as VBoxContainer
	var active_heading: Label = %ActiveHeading as Label
	var completed_heading: Label = %CompletedHeading as Label
	var previous_weekly: Node = (%List as VBoxContainer).get_node_or_null("WeeklyChallenge")
	if previous_weekly != null:
		previous_weekly.get_parent().remove_child(previous_weekly)
		previous_weekly.free()
	_clear_rows(active_rows)
	_clear_rows(completed_rows)
	var previous_opening: Node = (%List as VBoxContainer).get_node_or_null("OpeningWeek")
	if previous_opening != null:
		previous_opening.get_parent().remove_child(previous_opening)
		previous_opening.free()
	var weekly_card: Control = _make_weekly_card() if _weekly_challenge != null \
		and _weekly_challenge.status != WeeklyChallengeState.Status.EMPTY else null
	if weekly_card != null:
		var rows: VBoxContainer = %List as VBoxContainer
		rows.add_child(weekly_card)
		rows.move_child(weekly_card, 0)
	# The opening week leads the panel while it runs.
	var opening_card: Control = _make_opening_card()
	if opening_card != null:
		var list: VBoxContainer = %List as VBoxContainer
		list.add_child(opening_card)
		list.move_child(opening_card, 0)
	_active_ids.clear()
	_completed_known_ids.clear()
	active_heading.visible = false
	completed_heading.visible = false

	if _catalogue == null or not _catalogue.is_valid():
		_refresh_empty_state()
		return

	var completed_lookup: Dictionary[StringName, bool] = {}
	for id: StringName in _completed_ids:
		completed_lookup[id] = true
	for goal: Milestone in _catalogue.milestones:
		if goal == null or not goal.is_valid():
			continue
		if completed_lookup.has(goal.id):
			_completed_known_ids.append(goal.id)
		elif goal.unlock_level <= _owner_level and _active_ids.size() < ACTIVE_GOAL_LIMIT:
			_active_ids.append(goal.id)

	var active_index: int = 0
	for goal: Milestone in _catalogue.milestones:
		if _active_ids.has(goal.id):
			active_rows.add_child(_make_goal_card(goal, false, active_index))
			active_index += 1
	var completed_index: int = 0
	for goal: Milestone in _catalogue.milestones:
		if _completed_known_ids.has(goal.id):
			completed_rows.add_child(_make_goal_card(goal, true, completed_index))
			completed_index += 1

	active_heading.visible = not _active_ids.is_empty()
	completed_heading.visible = not _completed_known_ids.is_empty()
	_refresh_empty_state()


func _render_collections() -> void:
	var rows: VBoxContainer = %CollectionsRows as VBoxContainer
	var heading: Label = %CollectionsHeading as Label
	_clear_rows(rows)
	if _collection_result != null and _collection_result.valid:
		for entry: CollectionModel.Entry in _collection_result.entries:
			var index: int = rows.get_child_count()
			var title: Label = _add_label(rows, "Collection%d" % index, entry.definition.display_name)
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var short_line: Label = _add_label(rows, "CollectionShort%d" % index, entry.definition.short_line)
			short_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			for requirement_index: int in range(entry.requirements.size()):
				var requirement: CollectionModel.Entry.Requirement = entry.requirements[requirement_index]
				var mark: String = "✓" if requirement.present else "□"
				var item_label: Label = _add_label(rows,
					"Collection%dItem%d" % [index, requirement_index], "%s %s" % [mark, requirement.display_name])
				item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if entry.floor_required:
				var floor_mark: String = "✓" if entry.has_floor else "□"
				_add_label(rows, "Collection%dFloor" % index,
					"%s Floor: %s" % [floor_mark, entry.floor_name])
			if entry.completed:
				_add_label(rows, "Collection%dComplete" % index, "Complete!")
	heading.visible = rows.get_child_count() > 0
	_refresh_empty_state()


func _refresh_empty_state() -> void:
	var empty_state: Label = %EmptyState as Label
	var list: VBoxContainer = %List as VBoxContainer
	var collections: VBoxContainer = %CollectionsRows as VBoxContainer
	empty_state.visible = _active_ids.is_empty() and _completed_known_ids.is_empty() \
		and collections.get_child_count() == 0 and not list.has_node("WeeklyChallenge") \
		and not list.has_node("OpeningWeek")


func _make_weekly_card() -> Control:
	var challenge: WeeklyChallengeState = _weekly_challenge
	if challenge == null or challenge.status == WeeklyChallengeState.Status.EMPTY:
		return null
	var card: PanelContainer = PanelContainer.new()
	card.name = "WeeklyChallenge"
	card.theme = SHARED_THEME
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta(&"weekly_challenge", true)
	var body: VBoxContainer = _compact_body(card)
	var summary: HBoxContainer = _goal_line(body, "Summary")
	var title: Label = _add_label(summary, "Title", challenge.text)
	title.add_theme_font_size_override(&"font_size", 18)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var current: int = challenge.projected_progress(_observation)
	var unit: String = ""
	match challenge.kind:
		WeeklyChallenge.Kind.SERVE_IN_ONE_DAY:
			unit = " guests"
		WeeklyChallenge.Kind.OPERATING_PROFIT:
			unit = ""
		WeeklyChallenge.Kind.NO_LOSS_DAYS:
			unit = " days"
		WeeklyChallenge.Kind.GOOD_REVIEWS:
			unit = " reviews"
		WeeklyChallenge.Kind.SELL_DISH:
			unit = " sold"
	var progress_text: String = ""
	if challenge.kind == WeeklyChallenge.Kind.OPERATING_PROFIT:
		progress_text = "Progress: $%d / $%d" % [current, challenge.target]
	else:
		progress_text = "Progress: %d / %d%s" % [current, challenge.target, unit]
	var timing: String = WeeklyChallengeText.days_left(challenge.days_left(_day))
	if challenge.status == WeeklyChallengeState.Status.COMPLETED:
		timing = "Complete"
	elif challenge.status == WeeklyChallengeState.Status.EXPIRED:
		timing = "Expired"
	var progress: Label = _add_label(summary, "ProgressText", progress_text)
	progress.size_flags_horizontal = Control.SIZE_SHRINK_END
	progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var details: HBoxContainer = _goal_line(body, "Details")
	var ratio: float = clampf(float(current) / float(maxi(1, challenge.target)), 0.0, 1.0)
	_progress_bar(details, ratio)
	var days_left: Label = _add_label(details, "DaysLeft", timing)
	var reward: Label = _add_label(details, "Reward", "Cash reward: $%d" % challenge.reward_cash)
	for label: Label in [progress, days_left, reward]:
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		label.add_theme_font_size_override(&"font_size", 15)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return card


func _make_opening_card() -> Control:
	if _opening_week == null or not _opening_week.is_active() or _opening_catalogue == null \
			or not _opening_catalogue.is_valid():
		return null
	var shown: Array[OpeningGoal] = _opening_week.shown(_opening_catalogue)
	if shown.is_empty():
		return null
	var card: PanelContainer = PanelContainer.new()
	card.name = "OpeningWeek"
	card.theme = SHARED_THEME
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body: VBoxContainer = _compact_body(card)
	var header: HBoxContainer = _goal_line(body, "Header")
	var title: Label = _add_label(header, "Title", _opening_catalogue.title)
	title.add_theme_font_size_override(&"font_size", 20)
	var done: int = 0
	for goal: OpeningGoal in _opening_catalogue.goals:
		if _opening_week.is_completed(goal.id):
			done += 1
	var status: Label = _add_label(header, "Status", "%d / %d done   %s" % [done,
		_opening_catalogue.goals.size(), OpeningWeekText.days_left(_day, _opening_week.last_day(_opening_catalogue))])
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_font_size_override(&"font_size", 16)
	for index: int in shown.size():
		var goal: OpeningGoal = shown[index]
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "Goal%d" % index
		row.set_meta(&"goal_id", goal.id)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 0)
		body.add_child(row)
		var line: HBoxContainer = _goal_line(row, "Line")
		var name_label: Label = _add_label(line, "Title", "□ " + goal.title)
		name_label.add_theme_font_size_override(&"font_size", 18)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.tooltip_text = goal.description
		var raw: float = _opening_values.get(goal.condition, 0.0)
		var progress_text: String = OpeningWeekText.progress_line(goal, raw)
		if not progress_text.is_empty():
			var detail: HBoxContainer = _goal_line(row, "Detail")
			var progress: Label = _add_label(detail, "ProgressText", progress_text)
			progress.add_theme_font_size_override(&"font_size", 15)
			var bar: ProgressBar = _progress_bar(detail, clampf(raw / goal.target, 0.0, 1.0) if is_finite(raw) else 0.0)
			bar.custom_minimum_size.x = 100.0
			bar.size_flags_horizontal = Control.SIZE_SHRINK_END
		var reward: Label = _add_label(line, "Reward", "$%d" % goal.reward_cash)
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		reward.size_flags_horizontal = Control.SIZE_SHRINK_END
		reward.add_theme_font_size_override(&"font_size", 15)
	return card


func _clear_rows(rows: VBoxContainer) -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.free()


func _make_goal_card(goal: Milestone, completed: bool, index: int) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.name = "Goal%d" % index
	card.theme = SHARED_THEME
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta(&"goal_id", goal.id)
	card.set_meta(&"completed", completed)
	var body: VBoxContainer = _compact_body(card)
	var summary: HBoxContainer = _goal_line(body, "Summary")
	var title: Label = _add_label(summary, "Title", goal.title)
	title.add_theme_font_size_override(&"font_size", 18)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var progress: Label = _add_label(summary, "ProgressText",
		"Completed" if completed else _progress_text(goal))
	progress.size_flags_horizontal = Control.SIZE_SHRINK_END
	progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress.add_theme_font_size_override(&"font_size", 15)
	var detail: HBoxContainer = _goal_line(body, "Detail")
	var description: Label = _add_label(detail, "Description", goal.description)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override(&"font_size", 15)
	var bar: ProgressBar = _progress_bar(body, 1.0 if completed else _progress_ratio(goal))
	bar.custom_minimum_size.x = 120.0
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var reward: Label = _add_label(detail, "Reward", "Reward: %d XP   Cash: $%d" % [goal.reward_xp, goal.reward_cash])
	reward.size_flags_horizontal = Control.SIZE_SHRINK_END
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reward.add_theme_font_size_override(&"font_size", 15)
	if completed:
		var muted: Color = SHARED_THEME.get_color("font_color", "Label")
		muted.a *= 0.55
		for label: Label in [title, description, progress, reward]:
			label.add_theme_color_override(&"font_color", muted)
		bar.modulate = muted
	return card


func _compact_body(card: PanelContainer) -> VBoxContainer:
	var style: StyleBox = SHARED_THEME.get_stylebox(&"panel", &"PanelContainer").duplicate()
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	card.add_theme_stylebox_override(&"panel", style)
	var body: VBoxContainer = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override(&"separation", 1)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(body)
	return body


func _goal_line(body: VBoxContainer, line_name: String) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.name = line_name
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 12)
	body.add_child(line)
	return line


func _progress_bar(parent: Control, ratio: float) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "ProgressBar"
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 7.0)
	bar.value = ratio
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.focus_mode = Control.FOCUS_NONE
	parent.add_child(bar)
	return bar


func _add_label(parent: Control, node_name: String, text: String) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _progress_ratio(goal: Milestone) -> float:
	var raw: float = _progress.get(goal.id, 0.0)
	if not is_finite(raw):
		return 0.0
	return clampf(raw, 0.0, goal.target) / goal.target


func _progress_text(goal: Milestone) -> String:
	var raw: float = _progress.get(goal.id, 0.0)
	if not is_finite(raw):
		raw = 0.0
	var current: float = clampf(raw, 0.0, goal.target)
	if goal.condition == Milestone.Condition.REPUTATION:
		return "Progress: %.1f / %.1f stars" % [current, goal.target]
	if goal.condition == Milestone.Condition.PROFIT_TODAY:
		return "Progress: $%d / $%d" % [floori(current), floori(goal.target)]
	if goal.condition == Milestone.Condition.OWNER_LEVEL:
		return "Progress: Level %d / %d" % [floori(current), floori(goal.target)]
	var unit: String = ""
	match goal.condition:
		Milestone.Condition.SERVED_TODAY, Milestone.Condition.TOTAL_SERVED:
			unit = " guests"
		Milestone.Condition.STAFF_COUNT:
			unit = " staff"
		Milestone.Condition.CLEAN_STREAK:
			unit = " days"
	return "Progress: %d / %d%s" % [floori(current), floori(goal.target), unit]


func _on_close_pressed() -> void:
	close_requested.emit()
