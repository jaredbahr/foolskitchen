class_name MorningPaperCard
extends PanelContainer

const WIDTH: float = 440.0
const GUTTER: float = 16.0
const SLIDE_DISTANCE: float = 28.0
const SLIDE_SECONDS: float = 0.22

var _top: float = 0.0
var _slide: Tween

@onready var _masthead: Label = %Masthead
@onready var _headline: Label = %Headline
@onready var _notes: Label = %Notes
@onready var _close: Button = %CloseButton


func _ready() -> void:
	_close.pressed.connect(dismiss)
	get_viewport().size_changed.connect(_place)
	minimum_size_changed.connect(_fit_height)


func show_paper(edition: Dictionary) -> void:
	var notes: Array[String] = edition["notes"]
	_masthead.text = edition["masthead"]
	_headline.text = edition["headline"]
	_notes.text = "\n".join(notes)
	_notes.visible = not notes.is_empty()
	_place()
	show()
	if _slide != null:
		_slide.kill()
	position.y = _top - SLIDE_DISTANCE
	_slide = create_tween()
	_slide.tween_property(self, "position:y", _top, SLIDE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func dismiss() -> void:
	if _slide != null:
		_slide.kill()
		_slide = null
	hide()


func set_panel_top(top: float) -> void:
	_top = top
	_place()


func _place() -> void:
	if not is_inside_tree():
		return
	if _slide != null:
		_slide.kill()
		_slide = null
	var room: float = get_viewport_rect().size.x
	var width: float = clampf(room - GUTTER * 2.0, 0.0, WIDTH)
	size.x = width
	_fit_height()
	position = Vector2(floorf((room - width) / 2.0), _top)


## The wrapped labels report their real height after the container lays them out.
func _fit_height() -> void:
	size.y = get_combined_minimum_size().y
