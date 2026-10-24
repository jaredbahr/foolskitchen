extends CanvasLayer
## Event-driven day, speed and cash controls. refresh() also supports scenes
## instantiated before SceneTree readiness (including the custom test runner).

const SPEEDS: Array[int] = [0, 1, 2, 4]
const PHASE_NAMES: Array[String] = ["Morning", "Open", "Last orders", "Closed"]
const GAIN_COLOR: Color = Color("286B3B")
const LOSS_COLOR: Color = Color("A42E2E")

signal build_toggled()

var _day_label: Label
var _time_label: Label
var _phase_label: Label
var _cash_label: Label
var _context: Button
var _deltas: Control
var _buttons: Array[Button] = []
var _cash: int = 0
var _wall_button: Button
var _shop_view: ShopView
var _build_button: Button
var _build_hints: PanelContainer
var _build_hint_text: Label
var _build_available: bool = false
var _build_active: bool = false
var _build_reason: String = ""


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
		_build_hint_text = get_node("BuildHints/Text") as Label
		_build_button.pressed.connect(_on_build_pressed)
		_cash = Economy.cash
		for speed: int in SPEEDS:
			var button: Button = get_node("Top/Row/Speed%d" % speed) as Button
			_buttons.append(button)
			button.pressed.connect(_set_speed.bind(speed))
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
	_refresh_build_controls()


## State changes only: a refresh between native down/up preserves the button.
func set_build_state(available: bool, active: bool, reason: String = "") -> void:
	_build_available = available
	_build_active = active
	_build_reason = reason
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
	if _build_hints.visible != _build_active:
		_build_hints.visible = _build_active
	var text: String = "R Rotate  |  Del Sell  |  Esc Cancel / Exit"
	if not _build_reason.is_empty():
		text += "\n" + _build_reason
	if _build_hint_text.text != text:
		_build_hint_text.text = text


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


func _on_wall_button_pressed() -> void:
	if is_instance_valid(_shop_view):
		_shop_view.cycle_wall_mode()


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
	var label: Label = Label.new()
	label.text = ("−" if delta < 0 else "+") + Fmt.money(absi(delta))
	label.add_theme_color_override("font_color", LOSS_COLOR if delta < 0 else GAIN_COLOR)
	# A cream outline keeps it readable over the dark room background.
	label.add_theme_color_override("font_outline_color", Color("F3E6CC"))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deltas.add_child(label)
	# Start just under the top bar, below the cash, and drift down, so the
	# change never covers the cash figure itself.
	var bar_bottom: float = (get_node("Top") as Control).get_global_rect().end.y
	label.position = Vector2(_cash_label.global_position.x, bar_bottom + 4.0)
	if is_inside_tree():
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(label, "position:y", label.position.y + 24.0, 1.0)
		tween.tween_property(label, "modulate:a", 0.0, 1.0)
		tween.chain().tween_callback(label.queue_free)
