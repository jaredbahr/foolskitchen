class_name MorningPaperCard
extends PanelContainer

const WIDTH: float = 440.0
const GUTTER: float = 16.0
const SLIDE_DISTANCE: float = 28.0
const SLIDE_SECONDS: float = 0.22

var _top: float = 0.0
var _slide: Tween
var _keep_clear_source: Callable
var _left_obstacle: Control

@onready var _masthead: Label = %Masthead
@onready var _headline: Label = %Headline
@onready var _notes: Label = %Notes
@onready var _close: Button = %CloseButton


func _ready() -> void:
	_close.pressed.connect(dismiss)
	get_viewport().size_changed.connect(refresh_layout)
	minimum_size_changed.connect(_fit_height)


func show_paper(edition: Dictionary) -> void:
	var notes: Array[String] = edition["notes"]
	_masthead.text = edition["masthead"]
	_headline.text = edition["headline"]
	_notes.text = "\n".join(notes)
	_notes.visible = not notes.is_empty()
	refresh_layout()
	show()
	var top: float = position.y
	position.y = top - SLIDE_DISTANCE
	_slide = create_tween()
	_slide.tween_property(self, "position:y", top, SLIDE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func dismiss() -> void:
	if _slide != null:
		_slide.kill()
		_slide = null
	hide()


func set_panel_top(top: float) -> void:
	_top = top
	refresh_layout()


func set_keep_clear_source(source: Callable, left_obstacle: Control) -> void:
	_keep_clear_source = source
	_left_obstacle = left_obstacle


func refresh_layout() -> void:
	if not is_inside_tree():
		return
	if _slide != null:
		_slide.kill()
		_slide = null
	var room: float = get_viewport_rect().size.x
	var left: float = GUTTER
	var right: float = room - GUTTER
	var top: float = _top
	var left_box: Rect2
	if is_instance_valid(_left_obstacle) and _left_obstacle.is_visible_in_tree():
		left_box = _left_obstacle.get_global_rect()
		left = maxf(left, left_box.end.x + GUTTER)
	var right_boxes: Array[Rect2] = []
	if _keep_clear_source.is_valid():
		right_boxes = _keep_clear_source.call()
	for box: Rect2 in right_boxes:
		right = minf(right, box.position.x - GUTTER)
	if right - left < get_combined_minimum_size().x:
		left = GUTTER
		right = room - GUTTER
		top = maxf(top, left_box.end.y + GUTTER)
		for box: Rect2 in right_boxes:
			top = maxf(top, box.end.y + GUTTER)
	size.x = clampf(right - left, 0.0, WIDTH)
	_fit_height()
	var center: float = floorf((room - size.x) / 2.0)
	position = Vector2(clampf(center, left, maxf(left, right - size.x)), top)


## The wrapped labels report their real height after the container lays them out.
func _fit_height() -> void:
	size.y = get_combined_minimum_size().y
