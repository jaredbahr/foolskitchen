extends CanvasLayer
## Event-driven day, speed and cash controls. refresh() also supports scenes
## instantiated before SceneTree readiness (including the custom test runner).

const SPEEDS: Array[int] = [0, 1, 2, 4]
const PHASE_NAMES: Array[String] = ["Morning", "Open", "Last orders", "Closed"]
const ACTIVE_COLOR: Color = Color("F3E6CC")
const INACTIVE_COLOR: Color = Color("3B2A20")
const GAIN_COLOR: Color = Color("286B3B")
const LOSS_COLOR: Color = Color("A42E2E")

var _day_label: Label
var _time_label: Label
var _phase_label: Label
var _cash_label: Label
var _context: Button
var _deltas: Control
var _buttons: Array[Button] = []
var _cash: int = 0


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
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, ACTIVE_COLOR if active else INACTIVE_COLOR)


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
	label.text = ("−" if delta < 0 else "+") + str(delta).trim_prefix("-")
	label.add_theme_color_override("font_color", LOSS_COLOR if delta < 0 else GAIN_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deltas.add_child(label)
	label.position = _cash_label.global_position + Vector2(0.0, 28.0)
	if is_inside_tree():
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(label, "position:y", label.position.y - 28.0, 1.0)
		tween.tween_property(label, "modulate:a", 0.0, 1.0)
		tween.chain().tween_callback(label.queue_free)
