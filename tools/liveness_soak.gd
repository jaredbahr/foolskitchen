extends SceneTree
## Hand-run movement liveness soak (#306). See tools/liveness_soak.sh.
## Loads the core after autoloads join the tree, like the balance probe.


func _initialize() -> void:
	await process_frame
	var core: GDScript = load("res://tools/liveness_soak_core.gd")
	if core == null:
		printerr("Cannot load the liveness soak core")
		quit(2)
		return
	var status: int = core.run_cli(self, OS.get_cmdline_user_args())
	quit(status)
