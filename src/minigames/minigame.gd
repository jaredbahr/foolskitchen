class_name Minigame
extends Control
## Small reusable optional-game boundary. A skip is distinct from a bad score.

signal finished(result: float)

var running: bool = false


func _ready() -> void:
	(%Skip as Button).pressed.connect(_on_skip_pressed)


func start() -> void:
	running = true
	show()


func _finish(result: float) -> void:
	if not running:
		return
	running = false
	hide()
	finished.emit(result)


func _on_skip_pressed() -> void:
	_finish(-1.0)
