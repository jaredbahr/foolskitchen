class_name GuidePanel
extends Control

signal close_requested

@onready var _close_button: Button = $Card/Column/Header/Close
@onready var _topics: ItemList = $Card/Column/Pages/Topics
@onready var _reading: ScrollContainer = $Card/Column/Pages/Reading
@onready var _heading: Label = $Card/Column/Pages/Reading/Article/Heading
@onready var _body: Label = $Card/Column/Pages/Reading/Article/Body

var _pages: Array[GuidePage] = []


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_topics.item_selected.connect(_show_page)
	_style_topics()
	_pages = GuideBook.load_pages()
	for page: GuidePage in _pages:
		_topics.add_item(page.title)
	if not _pages.is_empty():
		_topics.select(0)
		_show_page(0)


func _style_topics() -> void:
	var ink: Color = _topics.get_theme_color("font_color", "Label")
	_topics.add_theme_color_override("font_color", ink)
	_topics.add_theme_color_override("font_selected_color", ink)
	_topics.add_theme_color_override("font_hovered_color", ink)
	_topics.add_theme_color_override("font_hovered_selected_color", ink)
	_topics.add_theme_stylebox_override("panel", _topics.get_theme_stylebox("panel", "PopupMenu"))
	_topics.add_theme_stylebox_override("focus", _topics.get_theme_stylebox("focus", "LineEdit"))
	var selection: StyleBox = _topics.get_theme_stylebox("hover", "PopupMenu")
	_topics.add_theme_stylebox_override("selected", selection)
	_topics.add_theme_stylebox_override("selected_focus", selection)
	_topics.add_theme_stylebox_override("hovered", selection)
	_topics.add_theme_stylebox_override("hovered_selected", selection)
	_topics.add_theme_stylebox_override("hovered_selected_focus", selection)
	_topics.add_theme_stylebox_override("separator", _topics.get_theme_stylebox("separator", "PopupMenu"))


func focus_topics() -> void:
	_topics.grab_focus()


func _show_page(index: int) -> void:
	var page: GuidePage = _pages[index]
	_heading.text = page.title
	_body.text = page.body
	_reading.scroll_vertical = 0


func _on_close_pressed() -> void:
	close_requested.emit()
