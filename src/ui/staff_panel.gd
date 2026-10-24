class_name StaffPanel
extends Control
## A request-only morning roster. Main owns people, wages and the save boundary.

signal hire_requested(id: StringName)
signal let_go_requested(id: StringName)

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const MORNING_HINT: String = "Staff changes are available in the morning."

var _roster: StaffRoster
var _phase: int = SimClock.Phase.MORNING
var _snapshot: Dictionary = {}
var _rows: Dictionary[StringName, Control] = {}


func _ready() -> void:
	refresh()


func bind_roster(roster: StaffRoster) -> void:
	_roster = roster
	refresh()


func set_phase(phase: int) -> void:
	_phase = phase
	refresh()


func refresh() -> void:
	if _roster == null:
		return
	var snapshot: Dictionary = _roster.to_dict()
	if snapshot != _snapshot:
		_rebuild_rows()
		_snapshot = snapshot
	var editable: bool = _phase == SimClock.Phase.MORNING
	(%Status as Label).text = "No hiring fee. Wages are paid at closing. Keep a cook and a server." if editable else MORNING_HINT
	(%RosterTitle as Label).text = "Your team (%d/%d) - $%d a day" % [_roster.members().size(), StaffRoster.CAPACITY, _roster.total_wages()]
	(%Empty as Label).visible = _roster.candidates().is_empty()
	for member: StaffMember in _roster.members():
		var button: Button = _rows[member.id].get_node("Top/Action") as Button
		button.disabled = not editable or not _roster.can_let_go(member.id)
		button.tooltip_text = MORNING_HINT if not editable else ("Keep at least one cook and one server." if button.disabled else "Let this person go before today's service.")
	for member: StaffMember in _roster.candidates():
		var button: Button = _rows[member.id].get_node("Top/Action") as Button
		button.disabled = not editable or not _roster.can_hire(member.id)
		button.tooltip_text = MORNING_HINT if not editable else ("Tier 1 has room for six staff." if button.disabled else "Hire for no upfront cost; pay their wage at closing.")


func row_for(id: StringName) -> Control:
	return _rows.get(id) as Control


func _rebuild_rows() -> void:
	for parent: VBoxContainer in [%Members, %Candidates]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			# Keep ownership through a native pressed callback, and let panel.free
			# also clean retired rows if a synchronous test exits before a frame.
			add_child(child)
			(child as Control).hide()
			child.queue_free()
	_rows.clear()
	for member: StaffMember in _roster.members():
		_add_row(%Members as VBoxContainer, member, false)
	for member: StaffMember in _roster.candidates():
		_add_row(%Candidates as VBoxContainer, member, true)


func _add_row(parent: VBoxContainer, member: StaffMember, candidate: bool) -> void:
	var row: VBoxContainer = VBoxContainer.new()
	row.theme = SHARED_THEME
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var top: HBoxContainer = HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(top)
	var title: Label = Label.new()
	title.name = "Name"
	title.text = "%s - %s, skill %d - $%d/day" % [member.display_name, "Cook" if member.role == &"cook" else "Server", member.skill, member.wage]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(title)
	var button: Button = Button.new()
	button.name = "Action"
	button.text = "Hire" if candidate else "Let go"
	button.theme = SHARED_THEME
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(_on_request.bind(member.id, candidate))
	top.add_child(button)
	var trait_def: StaffTrait = _roster.catalogue.find_trait(member.trait_id)
	var detail: Label = Label.new()
	detail.name = "Trait"
	detail.text = "%s: %s" % [trait_def.display_name, trait_def.description]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(detail)
	_rows[member.id] = row


func _on_request(id: StringName, hiring: bool) -> void:
	if _phase != SimClock.Phase.MORNING or _roster == null:
		return
	if hiring and _roster.can_hire(id):
		hire_requested.emit(id)
	elif not hiring and _roster.can_let_go(id):
		let_go_requested.emit(id)
	refresh()
