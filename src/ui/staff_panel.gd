class_name StaffPanel
extends Control
## A request-only morning roster. Main owns people, wages and the save boundary.

signal hire_requested(id: StringName)
signal let_go_requested(id: StringName)
signal raise_accept_requested(id: StringName)
signal raise_decline_requested(id: StringName)
signal tray_requested(level: int)
signal close_requested()

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const GROWTH_RULES: StaffGrowthTuning = preload("res://data/balance/staff_growth.tres")
const MORNING_HINT: String = "Staff changes are available in the morning."

var _roster: StaffRoster
var _phase: int = SimClock.Phase.MORNING
var _snapshot: Dictionary = {}
var _rows: Dictionary[StringName, Control] = {}
var _morning_day: int = 0
var _morning_notices: Array[Dictionary] = []
var _morning_snapshot: Dictionary = {}
var _morning_generation: int = 0
var _offer_rows: Dictionary[StringName, Control] = {}
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


## Main supplies the current day and already-readable departure notices.
## No decision or save happens inside this request-only panel.
func set_morning(day: int, notices: Array[Dictionary]) -> void:
	_morning_day = maxi(0, day)
	_morning_notices.clear()
	for notice: Dictionary in notices:
		if notice.get("message") is String:
			_morning_notices.append({"message": String(notice["message"])})
	refresh()


func set_trays(level: int, prices: PackedInt32Array, cash: int) -> void:
	_tray_level = level
	_tray_prices = prices
	_cash = cash
	refresh()


func refresh() -> void:
	IconStyle.decorate_label($Panel/Content/Title, &"staff")
	IconStyle.decorate_label(%RosterTitle, &"staff")
	IconStyle.decorate_label($Panel/Content/Scroll/List/CandidateTitle, &"staff")
	if _roster == null:
		return
	var snapshot: Dictionary = _roster.to_dict()
	if snapshot != _snapshot:
		_rebuild_rows()
		_snapshot = snapshot
	var offers: Array[Dictionary] = _roster.morning_raise_offers(_morning_day, _phase)
	var morning_snapshot: Dictionary = {"offers": offers,
		"notices": _morning_notices if _phase == SimClock.Phase.MORNING else []}
	if morning_snapshot != _morning_snapshot:
		_rebuild_morning_items(offers)
		_morning_snapshot = morning_snapshot.duplicate(true)
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
		button.tooltip_text = MORNING_HINT if not editable else ("Tier 1 has room for six staff." if button.disabled else (
			"Cleaners mop floor spots. No hiring fee; wages are paid at closing."
			if member.role == &"cleaner" else "Hire for no upfront cost; pay their wage at closing."))


func row_for(id: StringName) -> Control:
	return _rows.get(id) as Control


func offer_row_for(id: StringName) -> Control:
	return _offer_rows.get(id) as Control


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
	title.text = "%s - %s, skill %d - $%d/day" % [
		member.display_name, _role_name(member.role), member.skill, member.wage]
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
	detail.text = "%s: %s" % [trait_def.display_name, trait_def.description_for(member.role)]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(detail)
	if not candidate:
		_add_growth(row, member)
	_rows[member.id] = row


func _add_growth(row: VBoxContainer, member: StaffMember) -> void:
	var growth: StaffGrowth = member.growth_state()
	var primary: StringName = StaffMember._primary_skill(member.role)
	var level: int = growth.skill_level(primary)
	var needed: int = GROWTH_RULES.needed_for_next_level(level)
	var earned: int = growth.progress_xp(primary)
	var line: HBoxContainer = HBoxContainer.new()
	line.name = "Growth"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var face: Label = Label.new()
	face.name = "Mood"
	face.text = _mood_face(growth.mood)
	face.tooltip_text = _mood_name(growth.mood)
	face.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(face)
	var bar: ProgressBar = ProgressBar.new()
	bar.name = "XP"
	bar.custom_minimum_size = Vector2(120.0, 18.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = float(maxi(1, needed))
	bar.value = float(earned if needed > 0 else 1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(bar)
	var caption: Label = Label.new()
	caption.name = "XPLabel"
	caption.text = "XP %d/%d" % [earned, needed] if needed > 0 else "Skill maxed out"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(caption)


static func _mood_face(mood: int) -> String:
	return ":)" if mood >= 3 else (":|" if mood == 2 else ":(")


static func _mood_name(mood: int) -> String:
	return "Happy" if mood >= 3 else ("Okay" if mood == 2 else "Upset")


static func _role_name(staff_role: StringName) -> String:
	match staff_role:
		&"cook": return "Cook"
		&"server": return "Server"
		&"cleaner": return "Cleaner"
	return "Team member"


func _rebuild_morning_items(offers: Array[Dictionary]) -> void:
	_morning_generation += 1
	var notice_box: VBoxContainer = %MorningNotices as VBoxContainer
	var offer_box: VBoxContainer = %RaiseOffers as VBoxContainer
	for parent: VBoxContainer in [notice_box, offer_box]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			add_child(child)
			(child as Control).hide()
			child.queue_free()
	_offer_rows.clear()
	var showing_morning: bool = _phase == SimClock.Phase.MORNING
	notice_box.visible = showing_morning and not _morning_notices.is_empty()
	if showing_morning:
		for notice: Dictionary in _morning_notices:
			var label: Label = Label.new()
			label.text = String(notice["message"])
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			notice_box.add_child(label)
	(%RaiseTitle as Label).visible = not offers.is_empty()
	offer_box.visible = not offers.is_empty()
	for offer: Dictionary in offers:
		var member_id: StringName = StringName(offer["member_id"])
		var card: VBoxContainer = VBoxContainer.new()
		card.theme = SHARED_THEME
		offer_box.add_child(card)
		var sentence: Label = Label.new()
		sentence.name = "Message"
		sentence.text = String(offer["message"])
		sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(sentence)
		var actions: HBoxContainer = HBoxContainer.new()
		actions.name = "Actions"
		card.add_child(actions)
		var requires_raise: bool = bool(offer["requires_raise"])
		for accepting: bool in [true, false]:
			if not accepting and not requires_raise:
				continue
			var button: Button = Button.new()
			button.name = "Accept" if accepting else "NotNow"
			button.text = ("Accept" if requires_raise else "Got it") if accepting else "Not now"
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_on_raise_request.bind(member_id, accepting, _morning_generation))
			actions.add_child(button)
		_offer_rows[member_id] = card


func _on_raise_request(member_id: StringName, accepting: bool, generation: int) -> void:
	if _phase != SimClock.Phase.MORNING or _roster == null or _morning_day < 1 \
			or generation != _morning_generation:
		return
	var found: bool = false
	for offer: Dictionary in _roster.morning_raise_offers(_morning_day, _phase):
		if offer["member_id"] == member_id:
			found = true
			break
	if not found:
		return
	if accepting:
		raise_accept_requested.emit(member_id)
	else:
		raise_decline_requested.emit(member_id)
	refresh()


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
