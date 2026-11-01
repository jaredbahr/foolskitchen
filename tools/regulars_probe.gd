extends SceneTree
## Manual 25-day paired observation; never run from CI.


func _initialize() -> void:
	await process_frame
	var core: GDScript = load("res://tools/regulars_probe_core.gd")
	quit(core.run(self, OS.get_cmdline_user_args()))
