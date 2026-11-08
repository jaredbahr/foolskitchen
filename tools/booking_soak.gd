extends SceneTree
## Manual 24-case booking diagnostic, never a CI loop. The relative core path
## also permits the exact same two-file harness outside a baseline checkout.


func _initialize() -> void:
	await process_frame
	var path: String = get_script().resource_path.get_base_dir().path_join("booking_soak_core.gd")
	var core: GDScript = load(path)
	if core == null:
		printerr("Booking soak core could not load")
		quit(2)
		return
	quit(core.run_cli(self))
