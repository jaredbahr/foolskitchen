class_name StaffPanel
extends Control
## Request-only staff, growth and job choices. Main owns people, tasks and saves.

signal hire_requested(id: StringName)
signal let_go_requested(id: StringName)
signal raise_accept_requested(id: StringName)
signal raise_decline_requested(id: StringName)
signal tray_requested(level: int)
signal close_requested()
signal job_priority_requested(id: StringName, job: StringName, value: int)
signal owner_look_requested()

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const GROWTH_RULES: StaffGrowthTuning = preload("res://data/balance/staff_growth.tres")
const MORNING_HINT: String = "Staff changes are available in the morning."
const PRIORITY_CYCLE: Array[int] = [StaffJobPriorities.Level.HIGH, StaffJobPriorities.Level.NORMAL,
	StaffJobPriorities.Level.LOW, StaffJobPriorities.Level.OFF]
## Jobs a role can't do sit flat on the panel: a faint outline and a faded dash.
const LOCKED_BORDER_ALPHA: float = 0.35
const LOCKED_TEXT_ALPHA: float = 0.45

var _roster: StaffRoster
var _phase: int = SimClock.Phase.MORNING
var _snapshot: Dictionary = {}
## Today's opening hours against the default day (FK-083): wages shown are
## what staff are paid for today's hours. Exactly 1.0 for the default day.
var _wage_factor: float = 1.0
var _rows: Dictionary[StringName, Control] = {}
var _morning_day: int = 0
var _morning_notices: Array[Dictionary] = []
var _morning_snapshot: Dictionary = {}
var _morning_generation: int = 0
var _offer_rows: Dictionary[StringName, Control] = {}
var _tray_level: int = 0
var _tray_prices: PackedInt32Array = PackedInt32Array()
var _tray_lock_reason: String = ""
var _cash: int = 0
var _priority_headers_ready: bool = false
var _priority_names: Dictionary[StringName, Label] = {}
var _priority_buttons: Dictionary[StringName, Dictionary] = {}
var _owner_name: String = OwnerAppearance.DEFAULT_NAME


func _ready() -> void:
	refresh()


func set_owner_name(display_name: String) -> void:
	_owner_name = display_name
	refresh()


func _on_owner_look() -> void:
	if _phase == SimClock.Phase.MORNING:
		owner_look_requested.emit()


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


func set_trays(level: int, prices: PackedInt32Array, cash: int, loan_lock_reason: String = "") -> void:
	_tray_level = level
	_tray_prices = prices
	_cash = cash
	_tray_lock_reason = loan_lock_reason
	refresh()


func set_wage_factor(factor: float) -> void:
	if not is_finite(factor) or factor <= 0.0 or factor == _wage_factor:
		return
	_wage_factor = factor
	_snapshot = {}
	refresh()


func _day_wage(wage: int) -> int:
	return wage if _wage_factor == 1.0 else roundi(float(wage) * _wage_factor)


func refresh() -> void:
	if not (%OwnerLook as Button).pressed.is_connected(_on_owner_look):
		(%OwnerLook as Button).pressed.connect(_on_owner_look)
	# These controls share the heading row, but retain ordinary body sizing.
	(%OwnerName as Label).add_theme_font_size_override("font_size", SHARED_THEME.default_font_size)
	(%OwnerLook as Button).add_theme_font_size_override("font_size", SHARED_THEME.default_font_size)
	(%OwnerName as Label).text = OwnerText.owner_label(_owner_name)
	(%OwnerName as Label).tooltip_text = (%OwnerName as Label).text
	(%OwnerLook as Button).text = OwnerText.CHANGE_LOOK
	(%OwnerLook as Button).disabled = _phase != SimClock.Phase.MORNING
	(%OwnerLook as Button).tooltip_text = "" if _phase == SimClock.Phase.MORNING else OwnerText.MORNING_ONLY
	IconStyle.decorate_label($Panel/Content/Title, &"staff")
	IconStyle.decorate_label(%RosterTitle, &"staff")
	IconStyle.decorate_label($Panel/Content/Scroll/List/CandidateTitle, &"staff")
	_refresh_priorities()
	if _roster == null:
		return
	var snapshot: Dictionary = _roster.to_dict()
	# Job cells update in place. Their new saved field is not part of the
	# existing hire/growth cards and must not replace those buttons either.
	for section: String in ["members", "candidates"]:
		for member: Dictionary in snapshot.get(section, []):
			member.erase("priorities")
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
	(%Status as Label).text = "No hiring fee. Wages are paid at closing. Keep a cook and a server." if editable \
		else "Hiring, letting staff go, raises and upgrades are available in the morning. Job priorities can change now."
	(%RosterTitle as Label).text = "Your team (%d/%d) - $%d a day" % [_roster.members().size(), StaffRoster.CAPACITY, _team_day_wages()]
	(%Empty as Label).visible = _roster.candidates().is_empty()
	(%Carry as Label).text = "Servers carry %d plate%s" % [1 << _tray_level, "" if _tray_level == 0 else "s"]
	for level: int in [1, 2]:
		var price: int = _tray_prices[level - 1] if _tray_prices.size() >= level else -1
		var title: String = "Trays" if level == 1 else "Big trays"
		var label: Label = %TraysLabel if level == 1 else %BigTraysLabel
		var purchase: Button = %TraysBuy if level == 1 else %BigTraysBuy
		label.text = "%s — $%d" % [title, price] if price >= 0 else "%s — price unavailable" % title
		purchase.text = "Owned" if _tray_level >= level else "Buy"
		purchase.disabled = not editable or price < 0 or _tray_level != level - 1 or _cash < price \
			or not _tray_lock_reason.is_empty()
		purchase.tooltip_text = MORNING_HINT if not editable else ("Owned" if _tray_level >= level else (
			"Buy Trays first." if level == 2 and _tray_level == 0 else (
			_tray_lock_reason if not _tray_lock_reason.is_empty() else (
			"Price unavailable." if price < 0 else (
			"Not enough cash." if _cash < price else "Servers can carry more plates.")))))
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


func _team_day_wages() -> int:
	var total: int = 0
	for member: StaffMember in _roster.members():
		total += _day_wage(member.wage)
	return total


func row_for(id: StringName) -> Control:
	return _rows.get(id) as Control


func offer_row_for(id: StringName) -> Control:
	return _offer_rows.get(id) as Control


func priority_button_for(id: StringName, job: StringName) -> Button:
	var buttons: Dictionary = _priority_buttons.get(id, {})
	return buttons.get(job) as Button


## These cells are independent of growth/candidate cards: a roster refresh must
## retain an unchanged native button between mouse-down and mouse-up.
func _refresh_priorities() -> void:
	var section: VBoxContainer = %Priorities as VBoxContainer
	var grid: GridContainer = %PriorityGrid as GridContainer
	if not _priority_headers_ready:
		grid.columns = StaffJobPriorities.JOBS.size() + 1
		var heading: Label = Label.new()
		heading.text = "Team member"
		heading.custom_minimum_size.x = 120.0
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(heading)
		for job: StringName in StaffJobPriorities.JOBS:
			var label: Label = Label.new()
			label.text = StaffJobPriorities.job_label(job)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			label.tooltip_text = _job_description(job)
			grid.add_child(label)
		_priority_headers_ready = true
	var members: Array[StaffMember] = []
	if _roster != null:
		members.assign(_roster.members())
	var wanted: Array[StringName] = []
	var has_cleaner: bool = false
	var has_server: bool = false
	for member: StaffMember in members:
		wanted.append(member.id)
		has_cleaner = has_cleaner or member.role == &"cleaner"
		has_server = has_server or member.role == &"server"
	for id: StringName in _priority_buttons.keys():
		if wanted.has(id):
			continue
		_retire_priority_control(_priority_names[id])
		var buttons: Dictionary = _priority_buttons[id]
		for job: StringName in buttons:
			_retire_priority_control(buttons[job] as Control)
		_priority_names.erase(id)
		_priority_buttons.erase(id)
	section.visible = not members.is_empty()
	var index: int = grid.columns
	for member: StaffMember in members:
		var choices: StaffJobPriorities = _roster.job_priorities(member.id)
		if choices == null:
			continue
		var name_label: Label = _priority_names.get(member.id) as Label
		if name_label == null:
			name_label = Label.new()
			name_label.custom_minimum_size.x = 120.0
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(name_label)
			_priority_names[member.id] = name_label
		name_label.text = "%s (%s)" % [member.display_name, _role_name(member.role)]
		if name_label.get_index() != index:
			grid.move_child(name_label, index)
		index += 1
		var buttons: Dictionary = _priority_buttons.get(member.id, {})
		for job: StringName in StaffJobPriorities.JOBS:
			var button: Button = buttons.get(job) as Button
			if button == null:
				button = Button.new()
				button.theme = SHARED_THEME
				button.custom_minimum_size = Vector2(100.0, 0.0)
				button.focus_mode = Control.FOCUS_NONE
				button.mouse_filter = Control.MOUSE_FILTER_STOP
				button.pressed.connect(_on_priority_request.bind(member.id, job, button))
				grid.add_child(button)
				buttons[job] = button
			if button.get_index() != index:
				grid.move_child(button, index)
			index += 1
			var supported: bool = StaffJobPriorities.supports(choices.role, job)
			var value: int = choices.priority(job) if supported else StaffJobPriorities.Level.OFF
			button.disabled = not supported
			button.text = StaffJobPriorities.level_label(value) if supported else "—"
			button.tooltip_text = _priority_tooltip(choices, job, has_cleaner)
			if int(button.get_meta(&"priority_level", -1)) != value \
					or bool(button.get_meta(&"priority_supported", false)) != supported:
				_style_priority(button, value, supported)
		_priority_buttons[member.id] = buttons
	var availability: Label = %PriorityAvailability as Label
	availability.visible = has_server
	availability.text = "A Cleaner is on the team, so servers' Cleaning settings are inactive. They apply when no Cleaner is on the team." \
		if has_cleaner else "Servers clean floors only when no Cleaner is on the team."


func _retire_priority_control(control: Control) -> void:
	control.get_parent().remove_child(control)
	add_child(control)
	control.hide()
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.queue_free()


func _style_priority(button: Button, value: int, supported: bool) -> void:
	if not supported:
		# Unsupported work is flat on the panel with a faded dash, so it reads
		# as "not a choice" and never looks like Low or a chosen Off.
		var locked: StyleBoxFlat = locked_priority_style()
		var faded: Color = locked_priority_foreground()
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
			button.add_theme_stylebox_override(state, locked)
		for color: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
				&"font_hover_pressed_color", &"font_disabled_color"]:
			button.add_theme_color_override(color, faded)
		button.set_meta(&"priority_level", value)
		button.set_meta(&"priority_supported", false)
		return
	var normal: StyleBoxFlat = SHARED_THEME.get_stylebox("normal", "Button") as StyleBoxFlat
	var accent: StyleBoxFlat = SHARED_THEME.get_stylebox("pressed", "Button") as StyleBoxFlat
	var muted: StyleBoxFlat = SHARED_THEME.get_stylebox("disabled", "Button") as StyleBoxFlat
	var style: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	var foreground: Color = SHARED_THEME.get_color("font_color", "Button")
	match value:
		StaffJobPriorities.Level.HIGH:
			style.border_color = accent.bg_color
			style.set_border_width_all(3)
		StaffJobPriorities.Level.LOW:
			style.bg_color = muted.bg_color
			style.border_color = muted.border_color
		StaffJobPriorities.Level.OFF:
			style.bg_color = foreground
			style.border_color = foreground
			foreground = SHARED_THEME.get_color("font_pressed_color", "Button")
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		button.add_theme_stylebox_override(state, style)
	for color: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
			&"font_hover_pressed_color", &"font_disabled_color"]:
		button.add_theme_color_override(color, foreground)
	button.set_meta(&"priority_level", value)
	button.set_meta(&"priority_supported", true)


## Locked job cell: the panel's own fill with a faint outline in the theme's
## muted border colour, keeping the Button margins so the grid does not shift.
static func locked_priority_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = SHARED_THEME.get_stylebox("normal", "Button").duplicate() as StyleBoxFlat
	var panel: StyleBoxFlat = SHARED_THEME.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var muted: StyleBoxFlat = SHARED_THEME.get_stylebox("disabled", "Button") as StyleBoxFlat
	style.bg_color = panel.bg_color
	style.border_color = Color(muted.border_color, LOCKED_BORDER_ALPHA)
	style.set_border_width_all(1)
	return style


## Locked job dash: the theme's Button text colour, faded.
static func locked_priority_foreground() -> Color:
	return Color(SHARED_THEME.get_color("font_color", "Button"), LOCKED_TEXT_ALPHA)


static func _job_description(job: StringName) -> String:
	match job:
		&"cooking": return "Cooking meals"
		&"serving": return "Taking orders, delivering meals and putting deliveries away"
		&"bussing": return "Clearing tables"
		&"washing": return "Washing plates"
		&"cleaning": return "Mopping floor spots; a Cleaner also puts deliveries away"
	return "Job priority"


static func _priority_tooltip(choices: StaffJobPriorities, job: StringName, has_cleaner: bool) -> String:
	var label: String = StaffJobPriorities.job_label(job)
	if not StaffJobPriorities.supports(choices.role, job):
		return "%s is not available for this role." % label
	var text: String = "%s: %s. " % [label, StaffJobPriorities.level_label(choices.priority(job))]
	text += "This role's main job cannot be Off. Cycle High, Normal, Low." \
		if job == StaffJobPriorities.main_job(choices.role) else "Cycle High, Normal, Low, Off."
	if choices.role == &"server" and job == &"cleaning":
		text += " A Cleaner is on the team, so this setting is inactive." if has_cleaner else " Servers clean only when no Cleaner is on the team."
	text += " Applies on the next task pick; current work continues."
	return text


func _on_priority_request(id: StringName, job: StringName, source: Button) -> void:
	if _roster == null or not is_instance_valid(source) \
			or priority_button_for(id, job) != source or source.disabled:
		return
	var choices: StaffJobPriorities = _roster.job_priorities(id)
	if choices == null or not StaffJobPriorities.supports(choices.role, job):
		return
	var start: int = PRIORITY_CYCLE.find(choices.priority(job))
	for offset: int in range(1, PRIORITY_CYCLE.size() + 1):
		var value: int = PRIORITY_CYCLE[(start + offset) % PRIORITY_CYCLE.size()]
		if choices.can_set(job, value):
			job_priority_requested.emit(id, job, value)
			refresh()
			return


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
		member.display_name, _role_name(member.role), member.skill, _day_wage(member.wage)]
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
	var inset: Control = Control.new()
	inset.name = "XPInset"
	inset.custom_minimum_size.x = 8.0
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.focus_mode = Control.FOCUS_NONE
	line.add_child(inset)


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
			and _tray_prices.size() >= level and _cash >= _tray_prices[level - 1] \
			and _tray_lock_reason.is_empty():
		tray_requested.emit(level)
