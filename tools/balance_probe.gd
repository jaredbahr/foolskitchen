extends SceneTree
## Load the probe only after autoloads have joined the scene tree. Godot compiles
## a --script SceneTree before they exist, so this entry has no game references.


func _initialize() -> void:
	await process_frame
	var core: GDScript = load("res://tools/balance_probe_core.gd")
	if core == null:
		printerr("Cannot load the balance probe core")
		quit(2)
		return
	var status: int = core.run_cli(self, OS.get_cmdline_user_args())
	quit(status)
