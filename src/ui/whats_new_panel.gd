class_name WhatsNewPanel
extends Control
## "What's new in vX": the release notes bundled with this build, What to test
## first. Shown once per new version on the title screen, and on demand from
## the title screen and Settings. It reads only bundled files.

signal close_requested

const CARD_WIDTH: float = 680.0
const CARD_MARGIN: float = 24.0
const CARD_MAX_HEIGHT: float = 640.0
const EMPTY_TEXT: String = "There are no release notes in this build."
const ALL_NOTES_TEXT: String = "All release notes"
const CLOSE_TEXT: String = "Close"
const BUTTON_TEXT: String = "What's new"
const MUTED: Color = Color(0.4705882, 0.3882353, 0.3137255, 1)

## Replaceable so tests never open a browser.
var opener: Callable = OS.shell_open

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Column/Title
@onready var _version: Label = $Panel/Column/Version
@onready var _scroll: ScrollContainer = $Panel/Column/Scroll
@onready var _list: VBoxContainer = $Panel/Column/Scroll/List
@onready var _all_notes: Button = $Panel/Column/Buttons/AllNotes
@onready var _close: Button = $Panel/Column/Buttons/Close


func _ready() -> void:
	_all_notes.text = ALL_NOTES_TEXT
	_close.text = CLOSE_TEXT
	_all_notes.pressed.connect(open_all_notes)
	_close.pressed.connect(close)
	resized.connect(_layout_card)
	visibility_changed.connect(_layout_card)


## Fills the panel from a version and its notes (see BuildInfo) and shows it.
func present(version: String, notes_text: String) -> void:
	_title.text = BuildInfo.panel_title(version)
	_version.text = "Version %s" % BuildInfo.label(version)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var groups: Array[Dictionary] = ReleaseNotes.parse(notes_text)
	if groups.is_empty():
		_add_line(EMPTY_TEXT, false)
	for group: Dictionary in groups:
		var title: String = String(group["title"])
		if not title.is_empty():
			_add_heading(title)
		for item: String in group["items"]:
			_add_line(item, true)
	show()
	_scroll.scroll_vertical = 0
	_layout_card()


## The headings the panel is showing, in order (used by tests and captures).
func heading_texts() -> PackedStringArray:
	var result: PackedStringArray = []
	for child: Node in _list.get_children():
		if child.is_in_group(&"whats_new_heading") and not child.is_queued_for_deletion():
			result.append((child as Label).text)
	return result


func line_count() -> int:
	var count: int = 0
	for child: Node in _list.get_children():
		if child is Label and not child.is_queued_for_deletion() and not child.is_in_group(&"whats_new_heading"):
			count += 1
	return count


func open_all_notes() -> void:
	opener.call(BuildInfo.RELEASES_URL)


func close() -> void:
	hide()
	close_requested.emit()


func _add_heading(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 20)
	label.add_to_group(&"whats_new_heading")
	if _list.get_child_count() > 0:
		var gap: Control = Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		_list.add_child(gap)
	_list.add_child(label)


func _add_line(text: String, bullet: bool) -> void:
	var label: Label = Label.new()
	label.text = "• " + text if bullet else text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not bullet:
		label.add_theme_color_override(&"font_color", MUTED)
	_list.add_child(label)


func _layout_card() -> void:
	if not is_node_ready() or not visible:
		return
	var width: float = minf(CARD_WIDTH, maxf(0.0, size.x - CARD_MARGIN * 2.0))
	var height: float = minf(CARD_MAX_HEIGHT, maxf(0.0, size.y - CARD_MARGIN * 2.0))
	_panel.size = Vector2(width, height)
	_panel.position = Vector2((size.x - width) * 0.5, (size.y - height) * 0.5)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if visible and key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
