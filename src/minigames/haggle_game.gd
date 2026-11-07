class_name HaggleGame
extends Minigame
## Real-time view only. Main supplies all seeded centers before start.

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")

var tuning: HaggleTuning
var _centers: Array[float] = []
var _scores: Array[float] = []
var _round: int = 0
var _elapsed: float = 0.0
var _await_release: bool = false


func _ready() -> void:
	super._ready()
	(%Stop as Button).pressed.connect(_on_stop_pressed)
	(%Bar as Control).gui_input.connect(_on_bar_input)
	# Godot's default focus text is white; retain the shared dark text on this cream card.
	for button: Button in [%Stop as Button, %Skip as Button]:
		button.add_theme_color_override("font_focus_color", SHARED_THEME.get_color("font_color", "Button"))
	var zone_style: StyleBoxFlat = SHARED_THEME.get_stylebox("fill", "ProgressBar") as StyleBoxFlat
	(%Zone as ColorRect).color = zone_style.bg_color
	(%Marker as ColorRect).color = SHARED_THEME.get_color("font_color", "Label")


func prepare(terms: HaggleTuning, centers: Array[float]) -> bool:
	if running or terms == null or not terms.is_valid() or centers.size() != terms.rounds:
		return false
	for index: int in centers.size():
		var half: float = terms.zone_widths[index] * 0.5
		if not is_finite(centers[index]) or centers[index] < half or centers[index] > 1.0 - half:
			return false
	tuning = terms.duplicate(true) as HaggleTuning
	_centers = centers.duplicate()
	return true


func start() -> void:
	if tuning == null or not tuning.is_valid() or _centers.size() != tuning.rounds:
		return
	_round = 0
	_scores.clear()
	_elapsed = 0.0
	_await_release = false
	super.start()
	_refresh_bar()
	(%Stop as Button).grab_focus()


func _process(delta: float) -> void:
	if running and delta > 0.0:
		_elapsed += delta
		_refresh_bar()


func marker_position() -> float:
	return pingpong(_elapsed * tuning.speeds[_round], 1.0) if running else 0.0


## Read-only observations for tests and native captures, never saved.
func snapshot() -> Dictionary:
	return {"round": _round, "centers": _centers.duplicate(), "scores": _scores.duplicate(),
		"marker": marker_position(), "running": running, "await_release": _await_release}


func _refresh_bar() -> void:
	if not running:
		return
	(%Round as Label).text = "Round %d of %d" % [_round + 1, tuning.rounds]
	var bar: Control = %Bar as Control
	var zone: ColorRect = %Zone as ColorRect
	var marker: ColorRect = %Marker as ColorRect
	zone.position = Vector2((_centers[_round] - tuning.zone_widths[_round] * 0.5) * bar.size.x, 0.0)
	zone.size = Vector2(tuning.zone_widths[_round] * bar.size.x, bar.size.y)
	marker.position = Vector2(clampf(marker_position() * bar.size.x - 2.0, 0.0,
		maxf(0.0, bar.size.x - 4.0)), 0.0)
	marker.size = Vector2(4.0, bar.size.y)


func _on_stop_pressed() -> void:
	if not running or _await_release:
		return
	_scores.append(HaggleRules.score(marker_position(), _centers[_round], tuning.zone_widths[_round]))
	_await_release = true
	if _scores.size() == tuning.rounds:
		var total: float = 0.0
		for value: float in _scores:
			total += value
		_finish(total / float(tuning.rounds))
	else:
		_round += 1
		_elapsed = 0.0
		_refresh_bar()


func _on_bar_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if running and button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		(%Stop as Button).pressed.emit()
		accept_event()


## Consume action keys before GUI and Clock's _unhandled_input. Space always
## stops, Enter activates the focused game button; Tab cannot leave the card.
func _input(event: InputEvent) -> void:
	if not running or not is_visible_in_tree():
		return
	var key: InputEventKey = event as InputEventKey
	if key != null:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if not key.pressed:
			if code == KEY_SPACE or code == KEY_ENTER or code == KEY_KP_ENTER:
				_await_release = false
		elif not key.echo:
			match code:
				KEY_SPACE:
					(%Stop as Button).pressed.emit()
				KEY_ENTER, KEY_KP_ENTER:
					if (%Skip as Button).has_focus():
						(%Skip as Button).pressed.emit()
					else:
						(%Stop as Button).pressed.emit()
				KEY_ESCAPE:
					_on_skip_pressed()
				KEY_TAB:
					if (%Stop as Button).has_focus():
						(%Skip as Button).grab_focus()
					else:
						(%Stop as Button).grab_focus()
		get_viewport().set_input_as_handled()
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
		# A real Button emits pressed during GUI release, after _input. Defer
		# unlocking until that release finishes so it cannot stop two rounds.
		call_deferred("_release_stop")


func _release_stop() -> void:
	_await_release = false


func _unhandled_input(_event: InputEvent) -> void:
	if running and is_visible_in_tree():
		get_viewport().set_input_as_handled()
