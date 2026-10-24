class_name BuildCatalogue
extends Control
## Content-defined furniture requests only. The session/controller owns buying.

signal buy_requested(def_id: StringName)

const EDGE_MARGIN: float = 12.0

var item_buttons: Dictionary[StringName, Button] = {}
var _content: ContentDB
var _ordered_ids: Array[StringName] = []
var _layout_ready: bool = false


func bind_content(content: ContentDB) -> void:
	_prepare_layout()
	_content = content
	refresh_content()


func set_build_visible(active: bool) -> void:
	if visible != active:
		visible = active


func ordered_ids() -> Array[StringName]:
	return _ordered_ids.duplicate()


func _ready() -> void:
	_prepare_layout()
	_fit_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _layout_ready:
		_fit_panel()


## Unchanged definitions retain the same visible/enabled native button, even
## between a real mouse-down and mouse-up. No per-frame rebuild is necessary.
func refresh_content() -> void:
	_prepare_layout()
	var definitions: Array[ItemDef] = []
	if _content != null:
		for definition: ItemDef in _content.items():
			if _buyable(definition):
				definitions.append(definition)
	definitions.sort_custom(_definition_before)
	var desired_ids: Array[StringName] = []
	for definition: ItemDef in definitions:
		desired_ids.append(definition.id)
	var row: HBoxContainer = get_node("Panel/Margin/Rows/Scroll/Content/Items") as HBoxContainer
	for id: StringName in item_buttons.keys():
		if not desired_ids.has(id):
			var button: Button = item_buttons[id]
			row.remove_child(button)
			button.free()
			item_buttons.erase(id)
	for index: int in range(definitions.size()):
		var definition: ItemDef = definitions[index]
		var button: Button = item_buttons.get(definition.id) as Button
		if button == null:
			button = Button.new()
			button.name = "Buy_%s" % definition.id
			button.custom_minimum_size = Vector2(144.0, 64.0)
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.theme = theme
			button.pressed.connect(_on_buy_pressed.bind(definition.id))
			item_buttons[definition.id] = button
			row.add_child(button)
		if button.get_index() != index:
			row.move_child(button, index)
		var label: String = definition.display_name if not definition.display_name.is_empty() else String(definition.id)
		var text: String = "%s\n$%d" % [label, definition.price]
		if button.text != text:
			button.text = text
		button.tooltip_text = "Buy %s for $%d" % [label, definition.price]
	_ordered_ids = desired_ids
	_fit_panel()


func _prepare_layout() -> void:
	if _layout_ready:
		return
	var panel: PanelContainer = get_node("Panel") as PanelContainer
	# Keep the shared palette, borders and corners; compact only its padding.
	var original: StyleBox = theme.get_stylebox("panel", "PanelContainer") \
		if theme != null and theme.has_stylebox("panel", "PanelContainer") else panel.get_theme_stylebox("panel")
	var compact: StyleBox = original.duplicate() as StyleBox
	compact.set_content_margin(SIDE_LEFT, 8.0)
	compact.set_content_margin(SIDE_RIGHT, 8.0)
	compact.set_content_margin(SIDE_TOP, 6.0)
	compact.set_content_margin(SIDE_BOTTOM, 6.0)
	panel.add_theme_stylebox_override("panel", compact)
	var content: Control = get_node("Panel/Margin/Rows/Scroll/Content") as Control
	content.minimum_size_changed.connect(_fit_panel)
	_layout_ready = true


## Content-sized when it fits. Scrollbars handle both axes when it does not;
## resizing never hides, disables or replaces an in-flight native button.
func _fit_panel() -> void:
	if not _layout_ready:
		return
	var panel: PanelContainer = get_node_or_null("Panel") as PanelContainer
	var scroll: ScrollContainer = get_node_or_null("Panel/Margin/Rows/Scroll") as ScrollContainer
	var content: Control = get_node_or_null("Panel/Margin/Rows/Scroll/Content") as Control
	if panel == null or scroll == null or content == null:
		return
	var padding: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	var available: Vector2 = size - Vector2.ONE * EDGE_MARGIN * 2.0 - padding
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var natural: Vector2 = content.get_combined_minimum_size()
	var bar_width: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var bar_height: float = scroll.get_h_scroll_bar().get_combined_minimum_size().y
	var horizontal: bool = false
	var vertical: bool = false
	# One scrollbar may make the other necessary. Two passes settle both axes.
	for _pass: int in range(2):
		horizontal = horizontal or natural.x + (bar_width if vertical else 0.0) > available.x
		vertical = vertical or natural.y + (bar_height if horizontal else 0.0) > available.y
	var desired: Vector2 = natural + Vector2(bar_width if vertical else 0.0, bar_height if horizontal else 0.0)
	scroll.custom_minimum_size = Vector2(minf(desired.x, available.x), minf(desired.y, available.y))
	panel.size = scroll.custom_minimum_size + padding
	panel.position = Vector2(EDGE_MARGIN, size.y - EDGE_MARGIN - panel.size.y)


func _on_buy_pressed(id: StringName) -> void:
	if not visible or _content == null or not item_buttons.has(id):
		return
	if _buyable(_content.item(id)):
		buy_requested.emit(id)


static func _buyable(definition: ItemDef) -> bool:
	return definition != null and not definition.id.is_empty() \
		and definition.category != ItemDef.Category.DOOR and definition.price >= 0 \
		and definition.footprint.x > 0 and definition.footprint.y > 0


static func _definition_before(first: ItemDef, second: ItemDef) -> bool:
	var first_name: String = first.display_name.to_lower()
	var second_name: String = second.display_name.to_lower()
	if first_name == second_name:
		return String(first.id) < String(second.id)
	return first_name < second_name
