extends SceneTree
## Manual observer-inertness checks; load only after autoloads exist.


func _initialize() -> void:
	await process_frame
	var core: GDScript = load("res://tools/balance_probe_core.gd")
	if core == null:
		printerr("Cannot load the observer controls")
		quit(2)
		return
	quit(core.run_observer_controls(self))
