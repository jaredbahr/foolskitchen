extends SceneTree
## Loads every first-party script, including scripts unused by the main scene.

var _failed: bool = false


func _initialize() -> void:
	for directory: String in ["res://src", "res://tests", "res://tools"]:
		_check_directory(directory)
	quit(1 if _failed else 0)


func _check_directory(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		push_error("Cannot open script directory: %s" % path)
		_failed = true
		return
	for filename: String in directory.get_files():
		if filename.ends_with(".gd"):
			var script: GDScript = load(path.path_join(filename)) as GDScript
			if script == null or not script.can_instantiate():
				push_error("Script failed to compile: %s" % path.path_join(filename))
				_failed = true
	for subdirectory: String in directory.get_directories():
		_check_directory(path.path_join(subdirectory))
