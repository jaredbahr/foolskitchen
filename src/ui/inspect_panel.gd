class_name InspectPanel
extends Control
## Reads the selected sim object. The session refreshes after each completed tick.

signal selection_cleared()
signal owner_mode_requested(mode: StringName)

const GUEST_STATES: Array[String] = ["Arriving", "Queued", "Walking to seat", "Ordering",
	"Waiting for food", "Eating", "Paying", "Leaving", "Left"]

var selected_agent_id: int = -1
var selected_item_id: int = -1

var _world: SimWorld
var _title: Label
var _why: Label
var _details: Label
var _patience: VBoxContainer
var _patience_label: Label
var _patience_bar: ProgressBar
var _reservations: Label
var _owner_modes: GridContainer
var _owner_buttons: Dictionary[StringName, Button] = {}
var _shown_owner_id: int = -1
var _nodes_bound: bool = false


func _ready() -> void:
	refresh()


func bind_world(value: SimWorld) -> void:
	if _world != value:
		_world = value
		clear()
	else:
		refresh()


func show_agent(agent_id: int) -> void:
	if agent_id < 0:
		clear()
		return
	selected_agent_id = agent_id
	selected_item_id = -1
	refresh()


func show_item(item_id: int) -> void:
	if item_id < 0:
		clear()
		return
	selected_agent_id = -1
	selected_item_id = item_id
	refresh()


func clear() -> void:
	_bind_nodes()
	var had_selection: bool = selected_agent_id >= 0 or selected_item_id >= 0
	selected_agent_id = -1
	selected_item_id = -1
	_reset_content()
	hide()
	if had_selection:
		selection_cleared.emit()


func refresh() -> void:
	_bind_nodes()
	if _world == null:
		clear()
		return
	if selected_agent_id >= 0:
		var agent: SimAgent = _world.agent(selected_agent_id)
		if agent == null:
			clear()
			return
		_reset_content(agent is OwnerAgent and _shown_owner_id == agent.id)
		_title.text = _agent_title(agent)
		_why.text = _agent_why(agent)
		_why.show()
		if agent is StaffAgent:
			_show_staff(agent as StaffAgent)
		elif agent is CustomerAgent:
			_show_guest(agent as CustomerAgent)
		show()
	elif selected_item_id >= 0 and _world.grid != null:
		var item: PlacedItem = _world.grid.item(selected_item_id)
		if item == null or item.removed:
			clear()
			return
		_reset_content()
		_show_item(item)
		show()
	else:
		clear()


## Explicit binding also works immediately after PackedScene.instantiate(),
## before this control enters the tree or receives _ready().
func _bind_nodes() -> void:
	if _nodes_bound:
		return
	_title = %Title
	_why = %Why
	_details = %Details
	_patience = %Patience
	_patience_label = %PatienceLabel
	_patience_bar = %PatienceBar
	_reservations = %Reservations
	_owner_modes = %OwnerModes
	for mode: StringName in OwnerAgent.MODES:
		var button: Button = _owner_modes.get_node(String(mode).capitalize()) as Button
		_owner_buttons[mode] = button
		button.pressed.connect(_on_owner_mode_pressed.bind(mode))
	_nodes_bound = true


func _reset_content(keep_owner_controls: bool = false) -> void:
	_title.text = ""
	_why.text = ""
	_why.hide()
	_details.text = ""
	_details.hide()
	_patience.hide()
	_patience_label.text = ""
	_patience_bar.value = 0.0
	_reservations.text = ""
	_reservations.hide()
	# Hiding or disabling a BaseButton cancels an in-flight native mouse press.
	# Tick/frame refreshes must preserve controls for the same live owner.
	if not keep_owner_controls:
		_shown_owner_id = -1
		_owner_modes.hide()
		for button: Button in _owner_buttons.values():
			button.disabled = true
			button.set_pressed_no_signal(false)


func _agent_title(agent: SimAgent) -> String:
	var role_name: String = "Guest" if agent is CustomerAgent else String(agent.role).capitalize()
	if role_name.is_empty():
		role_name = "Agent"
	if agent.display_name.is_empty():
		return "%s #%d" % [role_name, agent.id]
	return "%s (%s #%d)" % [agent.display_name, role_name, agent.id]


func _agent_why(agent: SimAgent) -> String:
	# Transitional or malformed step indices must never index the sim's array
	# from the inspector. Do not repair the sim to obtain a display string.
	if agent is StaffAgent:
		var staff: StaffAgent = agent as StaffAgent
		if staff.task != null:
			if staff.step_index < 0:
				return staff.task.label
			if staff.step_index < staff.task.steps.size() and staff.task.steps[staff.step_index] == null:
				return staff.task.label
	if agent is CustomerAgent:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest.state == CustomerAgent.State.WAITING_FOOD and guest.order == null:
			return "Waiting for food"
	return agent.why()


func _show_staff(staff: StaffAgent) -> void:
	var skill_role: StringName = staff.role if staff.task == null else staff.task.role
	if skill_role == &"any":
		skill_role = staff.role
	var lines: PackedStringArray = ["%s skill: %d/5" % [String(skill_role).capitalize(), staff.skill_for(skill_role)]]
	if staff.task == null:
		if staff is OwnerAgent and (staff as OwnerAgent).current_mode() == &"rest":
			lines.append("Task: Standing back")
		else:
			lines.append("Task: Looking for work")
	else:
		lines.append("Task: %s" % staff.task.label)
		var count: int = staff.task.steps.size()
		if staff.step_index >= 0 and staff.step_index < count and staff.task.steps[staff.step_index] != null:
			lines.append("Step %d/%d: %s" % [staff.step_index + 1, count, staff.task.steps[staff.step_index].label])
		elif staff.step_index >= count and count > 0:
			lines.append("Step: Completing task")
		else:
			lines.append("Step: No active step")
	_details.text = "\n".join(lines)
	_details.show()
	if staff is OwnerAgent:
		_show_owner_modes(staff as OwnerAgent)


func _show_owner_modes(selected_owner: OwnerAgent) -> void:
	_shown_owner_id = selected_owner.id
	_owner_modes.show()
	for mode: StringName in OwnerAgent.MODES:
		var button: Button = _owner_buttons[mode]
		if button.disabled:
			button.disabled = false
		var active: bool = mode == selected_owner.current_mode()
		if button.button_pressed != active:
			button.set_pressed_no_signal(active)


func _on_owner_mode_pressed(mode: StringName) -> void:
	_bind_nodes()
	if not visible:
		return
	if _world == null or not _owner_modes.visible or not OwnerAgent.MODES.has(mode):
		refresh()
		return
	var selected_owner: OwnerAgent = _world.agent(selected_agent_id) as OwnerAgent
	if selected_owner != null and mode != selected_owner.current_mode():
		owner_mode_requested.emit(mode)
	# Selection and the committed mode remain owned by the session, even when
	# a request is ignored, rejected, or synchronously changes the selection.
	refresh()


## Keep reads of guest wait counters together; this presenter never advances
## a timer. Failed seat walks join the queue wait in the sim's search budget.
func _show_guest(guest: CustomerAgent) -> void:
	var state_name: String = "Visiting"
	if int(guest.state) >= 0 and int(guest.state) < GUEST_STATES.size():
		state_name = GUEST_STATES[int(guest.state)]
	_details.text = "State: %s" % state_name
	_details.show()
	match guest.state:
		CustomerAgent.State.ARRIVING, CustomerAgent.State.QUEUED:
			_show_patience("Table patience", guest.queue_patience, guest._queue_wait)
		CustomerAgent.State.WALKING_TO_SEAT:
			_show_patience("Table search patience", guest.queue_patience, guest._queue_wait + guest._walk_wait)
		CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD:
			_show_patience("Food patience", guest.food_patience, guest._food_wait)


func _show_patience(label: String, total: int, elapsed: int) -> void:
	var limit: int = maxi(total, 0)
	var remaining: int = clampi(total - elapsed, 0, limit)
	_patience_label.text = "%s: %ds left" % [label, ceili(float(remaining) / SimClock.TICKS_PER_SECOND)]
	_patience_bar.min_value = 0.0
	_patience_bar.max_value = maxi(limit, 1)
	_patience_bar.value = remaining
	_patience_bar.tooltip_text = label
	_patience.show()


func _show_item(item: PlacedItem) -> void:
	var definition: ItemDef = item.def as ItemDef
	var item_name: String = "Item"
	var station_name: String = "None"
	if definition != null:
		item_name = definition.display_name if not definition.display_name.is_empty() else String(definition.id).capitalize()
		if not definition.station_type.is_empty():
			station_name = String(definition.station_type).replace("_", " ")
	_title.text = "%s #%d" % [item_name, item.id]
	_details.text = "Station: %s" % station_name
	_details.show()
	var lines: PackedStringArray = []
	for cell: Vector2i in item.work_cells:
		lines.append(_reservation_line("Work", cell, item.reserved_by(cell)))
	for cell: Vector2i in item.seat_cells:
		lines.append(_reservation_line("Seat", cell, item.reserved_by(cell)))
	_reservations.text = "No work or seat cells" if lines.is_empty() else "\n".join(lines)
	_reservations.show()


func _reservation_line(kind: String, cell: Vector2i, holder_id: int) -> String:
	var holder_name: String = "Free"
	if holder_id >= 0:
		var holder: SimAgent = _world.agent(holder_id)
		holder_name = "Agent #%d (not present)" % holder_id if holder == null else _agent_title(holder)
	return "%s %s: %s" % [kind, cell, holder_name]
