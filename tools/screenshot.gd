extends SceneTree
## Renders the main scene and saves PNG screenshots, for reviews and PRs.
## Run through tools/screenshot.sh (it provides a virtual display).
## User args (after --): --out=<dir> --frames=120,400,900 --speed=4 --scene=res://...
##   --open      press "Open shop" at the start
##   --fast=N    also run N extra sim ticks per frame (via the scene's run_ticks)

var _frames: int = 0
var _shots: Array[int] = [120, 400, 900]
var _out: String = "screens"
var _speed: int = 4
var _open: bool = false
var _fast: int = 0
var _main: Node


func _initialize() -> void:
	var scene_path := "res://src/world/main.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--speed="):
			_speed = int(arg.trim_prefix("--speed="))
		elif arg == "--open":
			_open = true
		elif arg.begins_with("--fast="):
			_fast = int(arg.trim_prefix("--fast="))
		elif arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--frames="):
			_shots.clear()
			for f in arg.trim_prefix("--frames=").split(","):
				_shots.append(int(f))
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: PackedScene = load(scene_path)
	_main = scene.instantiate()
	if "use_saves" in _main:
		_main.set("use_saves", false)  # never touch the player's autosave
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		# Autoloads aren't compile-time identifiers in a --script main loop.
		var clock: Node = root.get_node("Clock")
		if _open:
			(clock.get("sim") as SimClock).start_service()
		clock.call("set_speed", _speed)
	if _fast > 0 and _frames > 3 and _main.has_method("run_ticks"):
		_main.call("run_ticks", _fast)
	if _shots.has(_frames):
		var path := _out.path_join("shot_%04d.png" % _frames)
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	if _shots.is_empty() or _frames >= _shots.max():
		quit()
	return false
