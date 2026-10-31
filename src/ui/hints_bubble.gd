class_name HintsBubble
extends Control
## Only the two buttons receive input; the card and its labels pass through.

signal got_it
signal skip_guide

const MARGIN: float = 12.0
const WIDTH: float = 390.0
var _panel: PanelContainer
var _text: Label
var _target: Control
var _top: float = 112.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://src/ui/theme/main_theme.tres")
	_panel = PanelContainer.new()
	_panel.name = "Bubble"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var title: Label = Label.new()
	title.text = Hints.TITLE
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	_text = Label.new()
	_text.name = "Text"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_text)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "Actions"
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(actions)
	var acknowledge_button: Button = Button.new()
	acknowledge_button.name = "GotIt"
	acknowledge_button.text = Hints.GOT_IT
	acknowledge_button.focus_mode = Control.FOCUS_NONE
	acknowledge_button.pressed.connect(_on_got_it)
	actions.add_child(acknowledge_button)
	var skip_button: Button = Button.new()
	skip_button.name = "SkipGuide"
	skip_button.text = Hints.SKIP_GUIDE
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.pressed.connect(_on_skip_guide)
	actions.add_child(skip_button)
	hide()


func show_hint(step: int, target: Control = null, top: float = 112.0) -> void:
	if _panel == null:
		return
	_text.text = Hints.text_for(step)
	_target = target
	_top = top
	show()
	_layout_bubble()


func clear_hint() -> void:
	hide()
	_target = null


func _process(_delta: float) -> void:
	if visible:
		_layout_bubble()


func _layout_bubble() -> void:
	var available: float = maxf(1.0, size.x - MARGIN * 2.0)
	var width: float = minf(WIDTH, available)
	var padding: Vector2 = _panel.get_theme_stylebox("panel").get_minimum_size()
	_text.custom_minimum_size.x = maxf(1.0, width - padding.x)
	_panel.size = Vector2(width, _panel.get_combined_minimum_size().y)
	var x: float = size.x - width - MARGIN
	var y: float = size.y - _panel.size.y - MARGIN
	if is_instance_valid(_target):
		var target_rect: Rect2 = _target.get_global_rect()
		x = target_rect.get_center().x - width * 0.5
		y = maxf(_top, target_rect.end.y + MARGIN)
	_panel.position = Vector2(clampf(x, MARGIN, maxf(MARGIN, size.x - width - MARGIN)),
		clampf(y, MARGIN, maxf(MARGIN, size.y - _panel.size.y - MARGIN)))
	queue_redraw()


func _on_got_it() -> void:
	got_it.emit()


func _on_skip_guide() -> void:
	skip_guide.emit()


func _draw() -> void:
	if not is_instance_valid(_target) or _panel == null:
		return
	var target_x: float = _target.get_global_rect().get_center().x
	var x: float = clampf(target_x, _panel.position.x + 16.0, _panel.position.x + _panel.size.x - 16.0)
	var y: float = _panel.position.y
	var style: StyleBoxFlat = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	draw_colored_polygon(PackedVector2Array([Vector2(x - 10.0, y + 1.0),
		Vector2(x, y - 10.0), Vector2(x + 10.0, y + 1.0)]), style.bg_color)
