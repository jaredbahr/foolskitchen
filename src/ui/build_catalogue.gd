class_name BuildCatalogue
extends Control
## Content-defined furniture requests only. The session/controller owns buying.

signal buy_requested(def_id: StringName)

var item_buttons: Dictionary[StringName, Button] = {}
var _content: ContentDB
var _ordered_ids: Array[StringName] = []


func bind_content(content: ContentDB) -> void:
	_content = content
	refresh_content()


func set_build_visible(active: bool) -> void:
	if visible != active:
		visible = active


func ordered_ids() -> Array[StringName]:
	return _ordered_ids.duplicate()


## Unchanged definitions retain the same visible/enabled native button, even
## between a real mouse-down and mouse-up. No per-frame rebuild is necessary.
func refresh_content() -> void:
	var definitions: Array[ItemDef] = []
	if _content != null:
		for definition: ItemDef in _content.items():
			if _buyable(definition):
				definitions.append(definition)
	definitions.sort_custom(_definition_before)
	var desired_ids: Array[StringName] = []
	for definition: ItemDef in definitions:
		desired_ids.append(definition.id)
	var row: HBoxContainer = get_node("Panel/Margin/Rows/Scroll/Items") as HBoxContainer
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
