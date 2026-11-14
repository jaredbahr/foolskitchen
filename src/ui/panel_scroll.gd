class_name PanelScroll
extends Node
## One scroll behaviour for every panel (#497). A panel attaches this to its
## root with its card (`frame`), its one main scroll area and any extra scroll
## areas. Then:
## - every wheel notch moves a scroll area by WHEEL_STEP pixels;
## - a wheel anywhere over the card scrolls: over an extra scroll area that
##   area, anywhere else (header, footer, fixed blocks) the main one;
## - the wheel never reaches a slider, option list or other control, so it
##   can never change a value while scrolling;
## - PgUp, PgDn, Home and End scroll the main area while the panel is open.
## Esc is not handled here: Main owns it.
## Menu, Stock and Staff also wrap the whole card in a scroll (`overflow`) so
## a very short window (150% UI on a small screen) can still reach the footer.
## It only takes the wheel while it actually overflows; otherwise header and
## footer wheels go to the main area.

## About three rows. The one wheel step for every panel.
const WHEEL_STEP: int = 110
const KEY_PAGE_SHARE: float = 0.85
const NODE_NAME: StringName = &"PanelScroll"
## Marks a control already hooked; it is freed with the control.
const HOOKED_META: StringName = &"_panel_scroll_hooked"

var _host: Control
var _frame: Control
var _main: ScrollContainer
var _scrolls: Array[ScrollContainer] = []
var _overflow: ScrollContainer


## Adds the helper under `host` (the panel root whose visibility opens it).
static func attach(host: Control, frame: Control, main: ScrollContainer,
		extras: Array[ScrollContainer] = [], overflow: ScrollContainer = null) -> PanelScroll:
	var helper: PanelScroll = PanelScroll.new()
	helper.name = NODE_NAME
	helper.setup(host, frame, main, extras, overflow)
	host.add_child(helper, false, Node.INTERNAL_MODE_BACK)
	return helper


func setup(host: Control, frame: Control, main: ScrollContainer, extras: Array[ScrollContainer],
		overflow: ScrollContainer = null) -> void:
	_host = host
	_frame = frame
	_main = main
	_overflow = overflow
	_scrolls = [main]
	for scroll: ScrollContainer in extras:
		if scroll != null and not _scrolls.has(scroll):
			_scrolls.append(scroll)
	if overflow != null and not _scrolls.has(overflow):
		_scrolls.append(overflow)
		# It never takes focus away from the panel's controls.
		overflow.focus_mode = Control.FOCUS_NONE
	# The card takes every wheel its children pass up and never lets one
	# through to the camera zoom behind it.
	_frame.mouse_force_pass_scroll_events = false
	if _frame.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	for scroll: ScrollContainer in _scrolls:
		scroll.scroll_vertical_custom_step = WHEEL_STEP
		scroll.mouse_force_pass_scroll_events = false
		_hook(scroll.get_v_scroll_bar())
		_hook(scroll.get_h_scroll_bar())
	_hook_tree(_frame)


func _enter_tree() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func main_scroll() -> ScrollContainer:
	return _main


## True while the panel is open and on screen.
func is_open() -> bool:
	return _host != null and _host.is_visible_in_tree() and _frame.is_visible_in_tree()


## Rows built later (stock lines, staff cards, catalogue items) are hooked as
## they arrive.
func _on_node_added(node: Node) -> void:
	if node is Control and _frame != null and _frame.is_ancestor_of(node):
		_hook(node as Control)


func _hook_tree(node: Node) -> void:
	_hook(node as Control)
	for child: Node in node.get_children():
		_hook_tree(child)


## The card, the scroll areas and every control that would use the wheel
## itself. Plain buttons and labels pass the wheel up to one of these.
func _hook(control: Control) -> void:
	if control == null or control.has_meta(HOOKED_META):
		return
	if not (control == _frame or control is ScrollContainer or control is Range \
			or control is OptionButton or control is Tree or control is ItemList \
			or control is TextEdit or control is TabBar):
		return
	control.set_meta(HOOKED_META, true)
	control.gui_input.connect(_on_gui_input.bind(control))


## gui_input is emitted before a control's own handling, so accepting here
## keeps sliders and lists from ever seeing the wheel.
func _on_gui_input(event: InputEvent, control: Control) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not is_open():
		return
	var vertical: bool = button.button_index == MOUSE_BUTTON_WHEEL_UP \
		or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
	var sideways: bool = button.button_index == MOUSE_BUTTON_WHEEL_LEFT \
		or button.button_index == MOUSE_BUTTON_WHEEL_RIGHT
	if not vertical and not sideways:
		return
	var target: ScrollContainer = _scroll_for(control)
	if sideways or button.shift_pressed:
		# Sideways scrolling stays with a scroll area that has it; anywhere
		# else it is simply used up so no value can change.
		if control is ScrollContainer or control is ScrollBar:
			return
		if button.pressed and target != null \
				and target.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			var sign_x: float = -1.0 if button.button_index == MOUSE_BUTTON_WHEEL_LEFT \
				or button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			target.scroll_horizontal += roundi(sign_x * WHEEL_STEP * _factor(button))
		control.accept_event()
		return
	if button.pressed and target != null:
		var direction: float = -1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		target.scroll_vertical += roundi(direction * WHEEL_STEP * _factor(button))
	# accept_event also stops the event climbing to the card, which would
	# otherwise scroll a second time.
	control.accept_event()


## The innermost registered scroll area holding `control`, else the main one.
## The card's fallback scroll counts only while it overflows.
func _scroll_for(control: Control) -> ScrollContainer:
	var node: Node = control
	while node != null and node != _host:
		if node is ScrollContainer and _scrolls.has(node as ScrollContainer):
			var scroll: ScrollContainer = node as ScrollContainer
			if scroll == _overflow and not overflows(scroll):
				return _main
			return scroll
		node = node.get_parent()
	return _main


static func overflows(scroll: ScrollContainer) -> bool:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 0.5


func _factor(button: InputEventMouseButton) -> float:
	return button.factor if button.factor > 0.0 else 1.0


## Keys come before the focused control so a focused list cannot turn PgDn
## into a new selection; typing in a text field keeps its own Home and End.
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or not is_open() or key.is_command_or_control_pressed() \
			or key.alt_pressed or key.shift_pressed:
		return
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code not in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if scroll_key(code):
		get_viewport().set_input_as_handled()


## Scrolls the main area for one of PgUp, PgDn, Home or End.
func scroll_key(code: Key) -> bool:
	if _main == null:
		return false
	var page: int = maxi(WHEEL_STEP, roundi(_main.size.y * KEY_PAGE_SHARE))
	match code:
		KEY_PAGEUP:
			_main.scroll_vertical -= page
		KEY_PAGEDOWN:
			_main.scroll_vertical += page
		KEY_HOME:
			_main.scroll_vertical = 0
		KEY_END:
			var bar: VScrollBar = _main.get_v_scroll_bar()
			_main.scroll_vertical = roundi(bar.max_value)
		_:
			return false
	return true
