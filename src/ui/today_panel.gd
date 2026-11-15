class_name TodayPanel
extends PanelContainer
## A nonmodal service log. Opening it leaves the shop clock running.

const WIDTH: float = 398.0
const HEIGHT: float = 330.0
const GUTTER: float = 12.0

var _log: DayLog
var _panel_top: float = 112.0


func _ready() -> void:
	PanelScroll.attach(self, self, %Scroll as ScrollContainer)
	(%Close as Button).pressed.connect(hide)
	get_viewport().size_changed.connect(_fit_panel)


func bind_log(log: DayLog) -> void:
	if _log == log:
		return
	if _log != null:
		_log.changed.disconnect(_on_log_changed)
	_log = log
	if _log != null:
		_log.changed.connect(_on_log_changed)
	hide()


func set_panel_top(top: float) -> void:
	_panel_top = top
	_fit_panel()


func toggle() -> void:
	if visible:
		hide()
		return
	_render_lines()
	(%Scroll as ScrollContainer).scroll_vertical = 0
	show()
	_fit_panel()


func _on_log_changed() -> void:
	if visible:
		_render_lines()


func _render_lines() -> void:
	var lines: Array[String] = _log.newest_first() if _log != null else []
	(%Lines as Label).text = "Nothing to report yet." if lines.is_empty() else "\n".join(lines)


func _fit_panel() -> void:
	if not is_inside_tree() or not visible:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	position = Vector2(GUTTER, _panel_top)
	size = Vector2(minf(WIDTH, viewport_size.x - 2.0 * GUTTER),
		minf(HEIGHT, viewport_size.y - _panel_top - GUTTER))
