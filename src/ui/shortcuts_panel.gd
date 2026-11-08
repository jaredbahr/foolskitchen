class_name ShortcutsPanel
extends Control
## Modal keyboard reference. It does not pause or otherwise change the game.

signal close_requested

const GROUP_HEADING_SIZE: int = 17
const CELL_SIZE: int = 15
const VIEW_MARGIN: float = 16.0

@onready var _panel: PanelContainer = $Panel
@onready var _column: VBoxContainer = $Panel/Column
@onready var _scroll: ScrollContainer = $Panel/Column/Scroll
@onready var _content: VBoxContainer = $Panel/Column/Scroll/Content
@onready var _close_button: Button = $Panel/Column/Header/Close


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_build_rows()
	resized.connect(_layout_card)
	_content.minimum_size_changed.connect(_layout_card)
	get_viewport().size_changed.connect(_layout_card)
	_layout_card()


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_layout_card):
		get_viewport().size_changed.disconnect(_layout_card)


func focus_close_button() -> void:
	if is_instance_valid(_close_button) and _close_button.is_inside_tree():
		_close_button.grab_focus()


func _build_rows() -> void:
	for group_name: String in ShortcutsText.GROUPS:
		var heading: Label = Label.new()
		heading.text = group_name
		heading.add_theme_font_size_override("font_size", GROUP_HEADING_SIZE)
		_content.add_child(heading)
		for row: Dictionary in ShortcutsText.rows_for(group_name):
			var cells: HBoxContainer = HBoxContainer.new()
			cells.add_theme_constant_override("separation", 18)
			var key_label: Label = Label.new()
			key_label.custom_minimum_size.x = 205.0
			key_label.text = row["keys"]
			key_label.add_theme_font_size_override("font_size", CELL_SIZE)
			var action_label: Label = Label.new()
			action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			action_label.text = row["action"]
			action_label.add_theme_font_size_override("font_size", CELL_SIZE)
			cells.add_child(key_label)
			cells.add_child(action_label)
			_content.add_child(cells)


func _on_close_pressed() -> void:
	close_requested.emit()


func _layout_card() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = size
	var available: Vector2 = Vector2(maxf(0.0, viewport_size.x - VIEW_MARGIN * 2.0),
		maxf(0.0, viewport_size.y - VIEW_MARGIN * 2.0))
	var padding: Vector2 = _panel.get_theme_stylebox("panel").get_minimum_size()
	var fixed_height: float = _column.get_node("Header").get_combined_minimum_size().y \
		+ _column.get_node("Columns").get_combined_minimum_size().y \
		+ float(_column.get_theme_constant("separation")) * 2.0 + padding.y
	var natural: Vector2 = _content.get_combined_minimum_size()
	var content_height: float = minf(natural.y, maxf(0.0, available.y - fixed_height))
	var bar_width: float = _scroll.get_v_scroll_bar().get_combined_minimum_size().x \
		if content_height < natural.y else 0.0
	var content_width: float = minf(natural.x + bar_width, maxf(0.0, available.x - padding.x))
	_scroll.custom_minimum_size = Vector2(content_width, content_height)
	_panel.size = Vector2(content_width + padding.x, content_height + fixed_height)
	_panel.position = (viewport_size - _panel.size) * 0.5
