extends CanvasLayer
## Event-driven day, speed and cash controls. refresh() also supports scenes
## instantiated before SceneTree readiness (including the custom test runner).

const SPEEDS: Array[int] = [0, 1, 2, 4]
const PHASE_NAMES: Array[String] = ["Morning", "Open", "Last orders", "Closed"]
const GAIN_COLOR: Color = Color("286B3B")
const LOSS_COLOR: Color = Color("A42E2E")

signal build_toggled()
signal menu_pressed()

var _day_label: Label
var _time_label: Label
var _phase_label: Label
var _cash_label: Label
var _context: Button
var _deltas: Control
var _merge_label: Label = null
var _merge_frame: int = -1
var _merge_amount: int = 0
var _buttons: Array[Button] = []
var _pause_bars: Array[ColorRect] = []
var _cash: int = 0
var _wall_button: Button
var _shop_view: ShopView
var _build_button: Button
var _build_hints: PanelContainer
var _build_hint_text: Label
var _build_hint_scroll: ScrollContainer
var _hint_viewport: Viewport
var _build_available: bool = false
var _build_active: bool = false
var _build_reason: String = ""
var _build_state: int = BuildMode.State.IDLE
var _menu_button: Button


func _ready() -> void:
	refresh()


## Idempotently binds controls and events, then renders current simulation state.
func refresh() -> void:
	if _day_label == null:
		_day_label = get_node("Top/Row/Day") as Label
		_time_label = get_node("Top/Row/Time") as Label
		_phase_label = get_node("Top/Row/Phase") as Label
		_cash_label = get_node("Top/Row/Cash") as Label
		_context = get_node("Top/Row/Context") as Button
		_deltas = get_node("Deltas") as Control
		_wall_button = get_node("Top/Row/Walls") as Button
		_wall_button.pressed.connect(_on_wall_button_pressed)
		_build_button = get_node("Top/Row/Build") as Button
		_build_hints = get_node("BuildHints") as PanelContainer
		_build_hint_scroll = get_node("BuildHints/Scroll") as ScrollContainer
		_build_hint_text = get_node("BuildHints/Scroll/Text") as Label
		var style: StyleBox = _build_hints.theme.get_stylebox("panel", "PanelContainer").duplicate() as StyleBox
		style.set_content_margin(SIDE_LEFT, 10.0)
		style.set_content_margin(SIDE_RIGHT, 10.0)
		style.set_content_margin(SIDE_TOP, 6.0)
		style.set_content_margin(SIDE_BOTTOM, 6.0)
		_build_hints.add_theme_stylebox_override("panel", style)
		_build_button.pressed.connect(_on_build_pressed)
		_menu_button = get_node("Top/Row/Menu") as Button
		_menu_button.pressed.connect(_on_menu_pressed)
		for name: String in ["Left", "Right"]:
			_pause_bars.append(get_node("Top/Row/Speed0/Pause/Bars/" + name) as ColorRect)
		_cash = Economy.cash
		for speed: int in SPEEDS:
			var button: Button = get_node("Top/Row/Speed%d" % speed) as Button
			_buttons.append(button)
			button.pressed.connect(_set_speed.bind(speed))
			if speed == 0:
				button.draw.connect(_refresh_pause_icon)
		_context.pressed.connect(_on_context_pressed)
	if not EventBus.sim_ticked.is_connected(_on_sim_ticked):
		EventBus.sim_ticked.connect(_on_sim_ticked)
		EventBus.day_phase_changed.connect(_on_phase_changed)
		EventBus.speed_changed.connect(_on_speed_changed)
		EventBus.cash_changed.connect(_on_cash_changed)
	_day_label.text = "Day %d" % Clock.sim.day
	_time_label.text = Fmt.clock(Clock.sim.display_minutes())
	_phase_label.text = PHASE_NAMES[Clock.sim.phase]
	_cash_label.text = Fmt.money(_cash)
	_context.visible = Clock.sim.phase == SimClock.Phase.MORNING or Clock.sim.phase == SimClock.Phase.CLOSED
	_context.text = "Open shop" if Clock.sim.phase == SimClock.Phase.MORNING else "Next day"
	_on_speed_changed(Clock.speed)
	_refresh_wall_mode()
	if is_inside_tree() and _hint_viewport != get_viewport():
		if _hint_viewport != null and _hint_viewport.size_changed.is_connected(_layout_build_hints):
			_hint_viewport.size_changed.disconnect(_layout_build_hints)
		_hint_viewport = get_viewport()
		_hint_viewport.size_changed.connect(_layout_build_hints)
	_refresh_build_controls()
	_menu_button.disabled = Clock.sim.phase != SimClock.Phase.MORNING
	_menu_button.tooltip_text = "Choose today's menu and prices" if not _menu_button.disabled else "Menu changes are available in the morning."


## State changes only: a refresh between native down/up preserves the button.
func set_build_state(available: bool, active: bool, reason: String = "", held_state: int = BuildMode.State.IDLE) -> void:
	_build_available = available
	_build_active = active
	_build_reason = reason
	_build_state = held_state
	if _build_button == null:
		refresh()
	else:
		_refresh_build_controls()


func _refresh_build_controls() -> void:
	var allowed: bool = _build_available and (
		Clock.sim.phase == SimClock.Phase.MORNING or Clock.sim.phase == SimClock.Phase.CLOSED)
	if _build_button.disabled == allowed:
		_build_button.disabled = not allowed
	if _build_button.button_pressed != _build_active:
		_build_button.set_pressed_no_signal(_build_active)
	var tooltip: String = "Build furniture (B)" if allowed else "Build furniture in the morning or after closing"
	if _build_button.tooltip_text != tooltip:
		_build_button.tooltip_text = tooltip
	var resize_hint: bool = _build_hints.visible != _build_active
	if resize_hint:
		_build_hints.visible = _build_active
	var text: String = "Esc Exit"
	if _build_state == BuildMode.State.MOVE:
		text = "R Rotate  |  Del Sell  |  Esc Cancel"
	elif _build_state == BuildMode.State.BUY:
		text = "R Rotate  |  Esc Cancel"
	if not _build_reason.is_empty():
		text += "\n" + _build_reason
	if _build_hint_text.text != text:
		_build_hint_text.text = text
		resize_hint = true
	if resize_hint:
		_layout_build_hints()


func _layout_build_hints() -> void:
	if _build_hint_text == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600.0, 900.0)
	var padding: Vector2 = _build_hints.get_theme_stylebox("panel").get_minimum_size()
	var top: float = minf(104.0, maxf(12.0, viewport_size.y - 64.0))
	var available: Vector2 = Vector2(minf(520.0, viewport_size.x - 24.0), viewport_size.y - top - 12.0) - padding
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var font: Font = _build_hint_text.get_theme_font("font")
	var font_size: int = _build_hint_text.get_theme_font_size("font_size")
	var natural_width: float = 0.0
	for line: String in _build_hint_text.text.split("\n"):
		natural_width = maxf(natural_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var width: float = minf(ceilf(natural_width), available.x)
	var text_size: Vector2 = font.get_multiline_string_size(_build_hint_text.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
	var bar_width: float = _build_hint_scroll.get_v_scroll_bar().get_combined_minimum_size().x if text_size.y > available.y else 0.0
	width = minf(width, available.x - bar_width)
	text_size = font.get_multiline_string_size(_build_hint_text.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
	_build_hint_text.custom_minimum_size = Vector2(width, 0.0)
	_build_hint_scroll.custom_minimum_size = Vector2(width + bar_width, minf(ceilf(text_size.y), available.y))
	_build_hints.size = _build_hint_scroll.custom_minimum_size + padding
	_build_hints.position = Vector2(12.0, top)


func _on_build_pressed() -> void:
	if _build_available and (Clock.sim.phase == SimClock.Phase.MORNING or Clock.sim.phase == SimClock.Phase.CLOSED):
		build_toggled.emit()


## Binds this presentation control to the containing shop view, idempotently.
func bind_shop_view(view: ShopView) -> void:
	if is_instance_valid(_shop_view) and _shop_view.wall_mode_changed.is_connected(_on_wall_mode_changed):
		_shop_view.wall_mode_changed.disconnect(_on_wall_mode_changed)
	_shop_view = view
	if is_instance_valid(_shop_view):
		_shop_view.wall_mode_changed.connect(_on_wall_mode_changed)
	refresh()


func _exit_tree() -> void:
	_disconnect_events()


func _notification(what: int) -> void:
	# Removal before SceneTree readiness still needs to release refresh() bindings.
	if what == NOTIFICATION_UNPARENTED:
		_disconnect_events()


func _disconnect_events() -> void:
	if _hint_viewport != null and _hint_viewport.size_changed.is_connected(_layout_build_hints):
		_hint_viewport.size_changed.disconnect(_layout_build_hints)
	_hint_viewport = null
	if EventBus.sim_ticked.is_connected(_on_sim_ticked):
		EventBus.sim_ticked.disconnect(_on_sim_ticked)
	if EventBus.day_phase_changed.is_connected(_on_phase_changed):
		EventBus.day_phase_changed.disconnect(_on_phase_changed)
	if EventBus.speed_changed.is_connected(_on_speed_changed):
		EventBus.speed_changed.disconnect(_on_speed_changed)
	if EventBus.cash_changed.is_connected(_on_cash_changed):
		EventBus.cash_changed.disconnect(_on_cash_changed)


func _set_speed(speed: int) -> void:
	Clock.set_speed(speed)


func _on_speed_changed(speed: int) -> void:
	for index: int in range(_buttons.size()):
		var button: Button = _buttons[index]
		var active: bool = SPEEDS[index] == speed
		button.set_pressed_no_signal(active)
	_refresh_pause_icon()


func _refresh_pause_icon() -> void:
	# Shapes use the same foreground as the native button text, without a font
	# fallback dependency (the pause character is absent from the Web font).
	var pause: Button = _buttons[0]
	var color_name: StringName = &"font_color"
	match pause.get_draw_mode():
		BaseButton.DRAW_PRESSED:
			color_name = &"font_pressed_color"
		BaseButton.DRAW_HOVER_PRESSED:
			color_name = &"font_hover_pressed_color"
		BaseButton.DRAW_HOVER:
			color_name = &"font_hover_color"
		BaseButton.DRAW_DISABLED:
			color_name = &"font_disabled_color"
	var ink: Color = pause.theme.get_color(color_name, &"Button") if pause.theme.has_color(color_name, &"Button") else pause.get_theme_color(color_name)
	for bar: ColorRect in _pause_bars:
		bar.color = ink


func _on_wall_button_pressed() -> void:
	if is_instance_valid(_shop_view):
		_shop_view.cycle_wall_mode()


func _on_menu_pressed() -> void:
	if Clock.sim.phase == SimClock.Phase.MORNING:
		menu_pressed.emit()


func _on_wall_mode_changed(_mode: int) -> void:
	_refresh_wall_mode()


func _refresh_wall_mode() -> void:
	_wall_button.disabled = not is_instance_valid(_shop_view)
	var names: Array[String] = ["Up", "Cutaway", "Down"]
	_wall_button.text = "Walls: " + names[_shop_view.wall_mode] if is_instance_valid(_shop_view) else "Walls"


func _on_sim_ticked(_tick: int) -> void:
	refresh()


func _on_phase_changed(_day: int, _phase: int) -> void:
	refresh()


func _on_context_pressed() -> void:
	if Clock.sim.phase == SimClock.Phase.MORNING:
		if Clock.sim.start_service():
			Clock.set_speed(1)
	elif Clock.sim.phase == SimClock.Phase.CLOSED:
		Clock.sim.next_day()
	refresh()


func _on_cash_changed(new_cash: int, delta: int, _reason: StringName) -> void:
	_cash = new_cash
	_cash_label.text = Fmt.money(new_cash)
	if delta == 0:
		return
	# Several same-sign changes in one frame (the morning restock buys each
	# ingredient separately) show as one total instead of a stack of labels.
	var frame: int = Engine.get_process_frames()
	if is_instance_valid(_merge_label) and _merge_frame == frame and signi(_merge_amount) == signi(delta):
		_merge_amount += delta
		_merge_label.text = _delta_text(_merge_amount)
		return
	var label: Label = Label.new()
	label.text = _delta_text(delta)
	_merge_label = label
	_merge_frame = frame
	_merge_amount = delta
	label.add_theme_color_override("font_color", LOSS_COLOR if delta < 0 else GAIN_COLOR)
	# A cream outline keeps it readable over the dark room background.
	label.add_theme_color_override("font_outline_color", Color("F3E6CC"))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deltas.add_child(label)
	_place_delta(label)
	_animate_delta(label)


func _delta_text(amount: int) -> String:
	return ("−" if amount < 0 else "+") + Fmt.money(absi(amount))


## Start just under the top bar, below the cash, so the change never covers
## the cash figure itself.
func _place_delta(label: Label) -> void:
	var bar_bottom: float = (get_node("Top") as Control).get_global_rect().end.y
	label.position = Vector2(_cash_label.global_position.x, bar_bottom + 4.0)


## Waits one frame so the top bar has its real layout (a change can arrive
## before the first layout pass, e.g. the first morning's stock purchase).
func _animate_delta(label: Label) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(label) or not is_inside_tree():
		return
	_place_delta(label)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 24.0, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(label.queue_free)
