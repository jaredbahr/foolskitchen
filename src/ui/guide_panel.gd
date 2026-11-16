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
	_pages = GuideBook.load_pages()
	for page: GuidePage in _pages:
		_topics.add_item(page.title)
	if not _pages.is_empty():
		_topics.select(0)
		_show_page(0)


func focus_topics() -> void:
	_topics.grab_focus()


func _show_page(index: int) -> void:
	var page: GuidePage = _pages[index]
	_heading.text = page.title
	_body.text = page.body
	_reading.scroll_vertical = 0


func _on_close_pressed() -> void:
	close_requested.emit()
