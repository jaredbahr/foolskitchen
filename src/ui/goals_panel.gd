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
var _active_ids: Array[StringName] = []
var _completed_known_ids: Array[StringName] = []


func _ready() -> void:
	_render()


## Stores detached read-only display inputs; no model or caller collection is mutated.
func set_goals(catalogue: MilestoneSet, completed_ids: Array[StringName],
		progress: Dictionary[StringName, float], owner_level: int) -> void:
	_catalogue = catalogue
	_completed_ids = completed_ids.duplicate()
	_progress = progress.duplicate()
	_owner_level = maxi(owner_level, 1)
	_render()


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
	var empty_state: Label = %EmptyState as Label
	_clear_rows(active_rows)
	_clear_rows(completed_rows)
	_active_ids.clear()
	_completed_known_ids.clear()
	active_heading.visible = false
	completed_heading.visible = false
	empty_state.visible = true

	if _catalogue == null or not _catalogue.is_valid():
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
	empty_state.visible = _active_ids.is_empty() and _completed_known_ids.is_empty()


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
	var body: VBoxContainer = VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tighter than the shared 10 px so three active goals fit at 1600x900 / 100%.
	body.add_theme_constant_override(&"separation", 4)
	card.add_child(body)
	var title: Label = _add_label(body, "Title", goal.title)
	title.add_theme_font_size_override(&"font_size", 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var description: Label = _add_label(body, "Description", goal.description)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var progress_text: Label = _add_label(body, "ProgressText", "Completed" if completed else _progress_text(goal))
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "ProgressBar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 10.0)
	bar.value = 1.0 if completed else _progress_ratio(goal)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.focus_mode = Control.FOCUS_NONE
	body.add_child(bar)
	var reward: Label = _add_label(body, "Reward", "Reward: %d XP   Cash: $%d" % [goal.reward_xp, goal.reward_cash])
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if completed:
		var muted: Color = SHARED_THEME.get_color("font_color", "Label")
		muted.a *= 0.55
		for label: Label in [title, description, progress_text, reward]:
			label.add_theme_color_override(&"font_color", muted)
		bar.modulate = muted
	return card


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
