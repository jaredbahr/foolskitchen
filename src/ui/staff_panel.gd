class_name StaffPanel
extends Control
## A request-only morning roster. Main owns people, wages and the save boundary.

signal hire_requested(id: StringName)
signal let_go_requested(id: StringName)
signal tray_requested(level: int)
signal close_requested()

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const MORNING_HINT: String = "Staff changes are available in the morning."

var _roster: StaffRoster
var _phase: int = SimClock.Phase.MORNING
var _snapshot: Dictionary = {}
var _rows: Dictionary[StringName, Control] = {}
var _tray_level: int = 0
var _tray_prices: PackedInt32Array = PackedInt32Array()
var _cash: int = 0


func _ready() -> void:
	refresh()


func bind_roster(roster: StaffRoster) -> void:
	_roster = roster
	refresh()


func set_phase(phase: int) -> void:
	_phase = phase
	refresh()


func set_trays(level: int, prices: PackedInt32Array, cash: int) -> void:
	_tray_level = level
	_tray_prices = prices
	_cash = cash
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
	(%Carry as Label).text = "Servers carry %d plate%s" % [1 << _tray_level, "" if _tray_level == 0 else "s"]
	for level: int in [1, 2]:
		var price: int = _tray_prices[level - 1] if _tray_prices.size() >= level else -1
		var title: String = "Trays" if level == 1 else "Big trays"
		var label: Label = %TraysLabel if level == 1 else %BigTraysLabel
		var purchase: Button = %TraysBuy if level == 1 else %BigTraysBuy
		label.text = "%s — $%d" % [title, price] if price >= 0 else "%s — price unavailable" % title
		purchase.text = "Owned" if _tray_level >= level else "Buy"
		purchase.disabled = not editable or price < 0 or _tray_level != level - 1 or _cash < price
		purchase.tooltip_text = MORNING_HINT if not editable else ("Owned" if _tray_level >= level else (
			"Buy Trays first." if level == 2 and _tray_level == 0 else (
			"Price unavailable." if price < 0 else (
			"Not enough cash." if _cash < price else "Servers can carry more plates."))))
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


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_trays_buy_pressed() -> void:
	_request_tray(1)


func _on_big_trays_buy_pressed() -> void:
	_request_tray(2)


func _request_tray(level: int) -> void:
	if _phase == SimClock.Phase.MORNING and _tray_level == level - 1 \
			and _tray_prices.size() >= level and _cash >= _tray_prices[level - 1]:
		tray_requested.emit(level)
