class_name ServiceEventCard
extends Control
## A service event card (#495): the icon, title, a line of text and two or
## three choices, each with a short preview of what it does. The game is paused
## while it shows, and only a choice closes it (Escape does nothing). Main owns
## the pause, the effects and the log; this view only reports the pick.

signal choice_picked(index: int)

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
## The Property screen's muted tone, as on the site card.
const MUTED_COLOR: Color = Color("766b60")
const PAUSED: String = "Paused"
const LABEL_FONT_SIZE: int = 18
const PREVIEW_FONT_SIZE: int = 14

var _event_id: StringName = &""


## `labels` and `previews` run in choice order; the first choice is on top.
func show_card(event_id: StringName, title: String, text: String, icon: StringName,
		labels: Array[String], previews: Array[String]) -> void:
	_event_id = event_id
	var texture: Texture2D = IconCatalogue.texture_for(icon) if not icon.is_empty() else null
	var icon_rect: TextureRect = get_node("Center/Panel/Content/Header/Icon") as TextureRect
	icon_rect.texture = texture
	icon_rect.visible = texture != null
	if texture != null:
		icon_rect.modulate = SHARED_THEME.get_color(&"font_color", &"Label")
	(get_node("Center/Panel/Content/Header/Title") as Label).text = title
	var paused: Label = get_node("Center/Panel/Content/Header/Paused") as Label
	paused.text = PAUSED
	paused.add_theme_color_override(&"font_color", MUTED_COLOR)
	(get_node("Center/Panel/Content/Text") as Label).text = text
	var list: VBoxContainer = _choices()
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for index: int in labels.size():
		list.add_child(_make_choice(index, labels[index], previews[index] if index < previews.size() else ""))
	show()


func event_id() -> StringName:
	return _event_id if visible else &""


## The choice buttons in order, for tests and capture tools.
func choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices().get_children():
		var button: Button = child as Button
		if button != null:
			buttons.append(button)
	return buttons


func close() -> void:
	_event_id = &""
	hide()


func _choices() -> VBoxContainer:
	return get_node("Center/Panel/Content/Choices") as VBoxContainer


## A wide button: the choice on the first line, its preview below in the muted
## tone, both in the theme's font.
func _make_choice(index: int, label: String, preview: String) -> Button:
	var button: Button = Button.new()
	button.name = "Choice%d" % index
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, 58.0)
	button.tooltip_text = preview
	var lines: VBoxContainer = VBoxContainer.new()
	lines.name = "Lines"
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override(&"separation", 0)
	button.add_child(lines)
	var title: Label = _label("Label", label, LABEL_FONT_SIZE)
	title.add_theme_color_override(&"font_color", SHARED_THEME.get_color(&"font_color", &"Button"))
	lines.add_child(title)
	var detail: Label = _label("Preview", preview, PREVIEW_FONT_SIZE)
	detail.add_theme_color_override(&"font_color", MUTED_COLOR)
	lines.add_child(detail)
	button.pressed.connect(_on_choice_pressed.bind(index))
	return button


func _label(node_name: String, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	return label


func _on_choice_pressed(index: int) -> void:
	choice_picked.emit(index)
