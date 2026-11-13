class_name SiteCard
extends Control
## The morning site card (FK-087, #464; Jared's call): on a morning when the
## owner has more than one restaurant, a small card before opening lists each
## one with yesterday's takings (or its renovation) and its manager. Picking
## another asks main.gd to switch there; the current one keeps it. Every line
## of the card is here.

signal site_chosen(site_id: StringName)

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
## The Property screen's muted tone, so the screens read as one.
const MUTED_COLOR: Color = Color("766b60")
const NAME_FONT_SIZE: int = 20
const LINE_FONT_SIZE: int = 16

const TITLE: String = "Your restaurants"
const INTRO: String = "Where will you work today?"
const STAY: String = "Stay here"
const GO: String = "Work here"
const RENOVATING: String = "Renovating"
const HERE_NOW: String = "You are here"
const NO_MANAGER: String = "No manager"

var _ids: Array[StringName] = []


## One row of the card: what main.gd knows about a site this morning.
class Row extends RefCounted:
	var id: StringName
	var name: String = ""
	var current: bool = false
	var takings: int = 0
	var renovation_days: int = 0
	var manager: String = ""
	## False when the site cannot be switched to now (a renovation).
	var can_choose: bool = true


func _ready() -> void:
	(get_node("Center/Panel/Content/Title") as Label).text = TITLE
	(get_node("Center/Panel/Content/Intro") as Label).text = INTRO


## "Yesterday's takings: $412", or the renovation still to do.
static func status_line(row: Row) -> String:
	if row.renovation_days > 0:
		return "Renovating: %d %s" % [row.renovation_days, "day" if row.renovation_days == 1 else "days"]
	return "Yesterday's takings: %s" % Fmt.money(row.takings)


static func manager_line(row: Row) -> String:
	return NO_MANAGER if row.manager.is_empty() else "Manager: %s" % row.manager


func set_rows(rows: Array[Row]) -> void:
	var list: VBoxContainer = get_node("Center/Panel/Content/List") as VBoxContainer
	for child: Node in list.get_children():
		list.remove_child(child)
		child.free()
	_ids.clear()
	for row: Row in rows:
		list.add_child(_make_row(row, _ids.size()))
		_ids.append(row.id)


## Listed site ids in screen order, for tests and capture evidence.
func site_ids() -> Array[StringName]:
	return _ids.duplicate()


func row_for(id: StringName) -> Control:
	for child: Node in (get_node("Center/Panel/Content/List") as VBoxContainer).get_children():
		if child.get_meta(&"site_id", &"") == id:
			return child as Control
	return null


func _make_row(row: Row, index: int) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.name = "Site%d" % index
	card.theme = SHARED_THEME
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta(&"site_id", row.id)
	var style: StyleBox = SHARED_THEME.get_stylebox(&"panel", &"PanelContainer").duplicate()
	if style is StyleBoxFlat:
		var flat: StyleBoxFlat = style as StyleBoxFlat
		flat.content_margin_top = 8.0
		flat.content_margin_bottom = 8.0
		flat.border_color = SHARED_THEME.get_color(&"font_color", &"Label")
		flat.border_color.a = 0.6 if row.current else 0.25
		flat.set_border_width_all(2)
	card.add_theme_stylebox_override(&"panel", style)
	var body: HBoxContainer = HBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override(&"separation", 12)
	card.add_child(body)
	var lines: VBoxContainer = VBoxContainer.new()
	lines.name = "Lines"
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override(&"separation", 2)
	body.add_child(lines)
	_add_label(lines, "Name", row.name, NAME_FONT_SIZE)
	_add_label(lines, "Status", status_line(row), LINE_FONT_SIZE)
	var manager: Label = _add_label(lines, "Manager", manager_line(row), LINE_FONT_SIZE)
	manager.add_theme_color_override(&"font_color", MUTED_COLOR)
	if row.current:
		var here: Label = _add_label(lines, "Here", HERE_NOW, LINE_FONT_SIZE)
		here.add_theme_color_override(&"font_color", MUTED_COLOR)
	var pick: Button = Button.new()
	pick.name = "Pick"
	pick.text = STAY if row.current else (GO if row.can_choose else RENOVATING)
	pick.disabled = not row.current and not row.can_choose
	pick.focus_mode = Control.FOCUS_NONE
	pick.custom_minimum_size = Vector2(130.0, 0.0)
	pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pick.pressed.connect(_on_pick_pressed.bind(row.id))
	body.add_child(pick)
	return card


func _add_label(parent: Control, node_name: String, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	parent.add_child(label)
	return label


func _on_pick_pressed(id: StringName) -> void:
	site_chosen.emit(id)
