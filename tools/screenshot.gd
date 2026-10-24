extends SceneTree
## Renders the main scene and saves PNG screenshots, for reviews and PRs.
## Run through tools/screenshot.sh (it provides a virtual display).
## User args (after --): --out=<dir> --frames=120,400,900 --speed=4 --scene=res://...

var _frames: int = 0
var _shots: Array[int] = [120, 400, 900]
var _out: String = "screens"
var _speed: int = 4


func _initialize() -> void:
	var scene_path := "res://src/world/main.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--speed="):
			_speed = int(arg.trim_prefix("--speed="))
		elif arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--frames="):
			_shots.clear()
			for f in arg.trim_prefix("--frames=").split(","):
				_shots.append(int(f))
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: PackedScene = load(scene_path)
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		# Autoloads aren't compile-time identifiers in a --script main loop.
		root.get_node("Clock").call("set_speed", _speed)
	if _shots.has(_frames):
		var path := _out.path_join("shot_%04d.png" % _frames)
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	if _shots.is_empty() or _frames >= _shots.max():
		quit()
	return false
